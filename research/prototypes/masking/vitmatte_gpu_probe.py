#!/usr/bin/env python3
"""Runs vitmatte_gpu_probe.swift in a loop of processes and counts its aborts (MSK-33).

On macOS 27.0.1 Metal Performance Shaders Graph at times aborts a ViTMatte prediction on the GPU as
it specialises the model for it. Each probe process makes a number of trials, each a fresh load and
its first prediction; an abort ends the process, so a trial is the unit counted. Standard library
only, so it runs on the build Mac as it is.

    vitmatte_gpu_probe.py run --probe <binary> --model <x.mlmodelc> --label <name> --processes 40 \\
        --workers 2 --out results.jsonl [--clean <folder>] -- loads=10 units=gpu …
    vitmatte_gpu_probe.py summary results.jsonl [--baseline <label>]

summary gives each label's aborts per trial with its exact (Clopper-Pearson) 95% interval and, against
the baseline, the one-sided Fisher exact test that its rate is lower, and how many clean trials rule
out the baseline's rate: n with (1 - p)^n <= 0.05, about 3 / p.

The rate rises with the Mac's load, so a candidate runs beside the baseline, each probe under a binary
name of its own (Core ML keeps a cache for each), about eight at once. On 15 October 2026, so, the
shipped ViTMatteBaseW8 aborted in 28 of 1,296 trials (2.2%, 95% 1.4% to 3.1%), each Core ML option
and MPS Graph run directly within 17 to 119, ViTMatteBaseW8RelPos16 in none of 850 (Fisher
p = 7e-7) and ViTMatteBaseFP16 in none of 1,530; with two to four at once the shipped model aborted
in 1 of 1,195. To check a macOS update, run the shipped model so for 1,000 trials or more.
"""

import argparse
import concurrent.futures
import json
import math
import pathlib
import re
import shutil
import statistics
import subprocess
import sys
import threading
import time

TRIAL = re.compile(r"TRIAL (\d+) load=([\d.]+) first=([\d.]+) next=([\d.]+) band=([\d.-]+)(?: passes=(\d+)\+(\d+))?")
BEGIN = re.compile(r"BEGIN (\d+)")


def one(probe, model, options, timeout):
    started = time.time()
    try:
        done = subprocess.run([probe, model, *options], capture_output=True, text=True, timeout=timeout)
        code, out, err = done.returncode, done.stdout, done.stderr
    except subprocess.TimeoutExpired as expired:
        code, out, err = "timeout", expired.stdout or "", expired.stderr or ""
        out = out.decode() if isinstance(out, bytes) else out
        err = err.decode() if isinstance(err, bytes) else err
    trials = [tuple(float(v) if v is not None else -1 for v in m.groups()[1:]) for m in TRIAL.finditer(out)]
    begun = [int(m.group(1)) for m in BEGIN.finditer(out)]
    aborted = code in (77, -6) or "PROBE-ABORT" in err
    return {
        "exit": code,
        "trials": len(trials),
        "aborted": aborted,
        "abort_trial": begun[-1] if aborted and begun else None,
        "mps": "incompatible dimensions" in err or "Failed to infer result type" in err,
        "load": [t[0] for t in trials],
        "first": [t[1] for t in trials],
        "next": [t[2] for t in trials],
        "band": [t[3] for t in trials],
        "passes": [[int(t[4]), int(t[5])] for t in trials],
        "warm": re.findall(r"WARM \S+ [\d.]+", out),
        "stderr": err[-3000:] if code != 0 else "",
        "seconds": round(time.time() - started, 1),
    }


def run(arguments):
    out = pathlib.Path(arguments.out)
    lock = threading.Lock()
    counts = {"processes": 0, "trials": 0, "aborts": 0}

    def task(index):
        if arguments.stop_on_abort and counts["aborts"]:
            return
        result = one(arguments.probe, arguments.model, arguments.options, arguments.timeout)
        result.update(label=arguments.label, options=arguments.options, index=index, time=time.strftime("%H:%M:%S"))
        with lock:
            if arguments.clean:
                for item in pathlib.Path(arguments.clean).glob("*"):
                    shutil.rmtree(item, ignore_errors=True)
            with out.open("a") as file:
                file.write(json.dumps(result) + "\n")
            counts["processes"] += 1
            counts["trials"] += result["trials"] + (1 if result["aborted"] else 0)
            counts["aborts"] += 1 if result["aborted"] else 0
            status = "ABORT" if result["aborted"] else ("ok" if result["exit"] == 0 else f"exit {result['exit']}")
            print(f"{result['time']} {arguments.label} #{index}: {status}, {result['trials']} trials, "
                  f"{result['seconds']} s; so far {counts['aborts']} aborts in {counts['trials']} trials", flush=True)

    with concurrent.futures.ThreadPoolExecutor(arguments.workers) as pool:
        list(pool.map(task, range(arguments.processes)))


def binomial_tail(k, n, p, upper):
    """P(X >= k) if upper else P(X <= k), for X ~ Binomial(n, p)."""
    if p <= 0:
        return 1.0 if (not upper or k == 0) else 0.0
    if p >= 1:
        return 1.0 if (upper or k == n) else 0.0
    terms = range(k, n + 1) if upper else range(0, k + 1)
    logs = [math.lgamma(n + 1) - math.lgamma(i + 1) - math.lgamma(n - i + 1) + i * math.log(p)
            + (n - i) * math.log1p(-p) for i in terms]
    top = max(logs)
    return min(1.0, math.exp(top) * sum(math.exp(v - top) for v in logs))


def interval(k, n, alpha=0.05):
    """The exact (Clopper-Pearson) interval for k events in n trials."""
    def solve(condition):
        low, high = 0.0, 1.0
        for _ in range(100):
            middle = (low + high) / 2
            low, high = (middle, high) if condition(middle) else (low, middle)
        return (low + high) / 2
    lower = 0.0 if k == 0 else solve(lambda p: binomial_tail(k, n, p, True) < alpha / 2)
    upper = 1.0 if k == n else solve(lambda p: binomial_tail(k, n, p, False) > alpha / 2)
    return lower, upper


def fisher_lower(k1, n1, k2, n2):
    """One-sided Fisher exact p-value that the first group's rate is below the second's."""
    total, events = n1 + n2, k1 + k2

    def log_choose(a, b):
        return math.lgamma(a + 1) - math.lgamma(b + 1) - math.lgamma(a - b + 1)
    denominator = log_choose(total, events)
    return sum(math.exp(log_choose(n1, i) + log_choose(n2, events - i) - denominator)
               for i in range(max(0, events - n2), min(k1, n1) + 1))


def summary(arguments):
    rows = [json.loads(line) for path in arguments.files for line in open(path) if line.strip()]
    labels = list(dict.fromkeys(row["label"] for row in rows))
    tallies = {}
    for label in labels:
        mine = [row for row in rows if row["label"] == label]
        aborts = sum(row["aborted"] for row in mine)
        trials = sum(row["trials"] for row in mine) + aborts
        other = [row for row in mine if not row["aborted"] and row["exit"] != 0]
        tallies[label] = (aborts, trials)
        low, high = interval(aborts, trials)
        first = [t for row in mine for t in row["first"]]
        later = [t for row in mine for t in row["next"] if t > 0]
        load = [t for row in mine for t in row["load"]]
        print(f"{label}: {aborts} aborts in {trials} trials ({len(mine)} processes, {len(other)} other failures): "
              f"{aborts / max(trials, 1):.2%} a trial, 95% {low:.2%} to {high:.2%}; "
              f"MPS Graph's message in {sum(row['mps'] for row in mine)}")
        if first:
            print(f"    load {statistics.median(load):.2f} s, first prediction {statistics.median(first):.2f} s "
                  f"(max {max(first):.2f}), next {statistics.median(later) if later else 0:.3f} s (median)")
        passes = [tuple(p) for row in mine for p in row.get("passes", [])]
        if passes:
            counts = {key: passes.count(key) for key in sorted(set(passes))}
            print(f"    MPS Graph's passes run (at load + at the predictions) in each trial: {counts}")
        trials_at = [row["abort_trial"] for row in mine if row["aborted"]]
        if trials_at:
            print(f"    aborted at trial {sorted(trials_at)}")
    if arguments.baseline in tallies:
        k, n = tallies[arguments.baseline]
        p = k / n if n else 0
        low, _ = interval(k, n)
        if p > 0:
            print(f"\nbaseline {arguments.baseline}: {p:.2%}; clean trials that rule it out at 95%: "
                  f"{math.ceil(math.log(0.05) / math.log1p(-p))} (at its lower bound {low:.2%}: "
                  f"{math.ceil(math.log(0.05) / math.log1p(-low)) if low > 0 else 'n/a'})")
        for label, (k2, n2) in tallies.items():
            if label != arguments.baseline:
                print(f"    {label}: {k2}/{n2}, Fisher one-sided p = {fisher_lower(k2, n2, k, n):.2g}"
                      f"{'' if k2 else f', (1 - p)^n = {(1 - p) ** n2:.2g}'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    runner = commands.add_parser("run")
    runner.add_argument("--probe", required=True)
    runner.add_argument("--model", required=True)
    runner.add_argument("--label", required=True)
    runner.add_argument("--processes", type=int, default=20)
    runner.add_argument("--workers", type=int, default=1)
    runner.add_argument("--timeout", type=float, default=900)
    runner.add_argument("--out", required=True)
    runner.add_argument("--clean", help="a folder emptied after each process (Core ML's cache, for fresh=1)")
    runner.add_argument("--stop-on-abort", action="store_true", help="start no more processes after an abort")
    runner.add_argument("options", nargs="*")
    reader = commands.add_parser("summary")
    reader.add_argument("files", nargs="+")
    reader.add_argument("--baseline")
    arguments = parser.parse_args()
    run(arguments) if arguments.command == "run" else summary(arguments)


if __name__ == "__main__":
    sys.exit(main())
