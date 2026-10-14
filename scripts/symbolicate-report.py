#!/usr/bin/env python3
"""Symbolicates a crash or hang report from the app (UX-11): names Redlamp's own frames in its stacks from
the release's dSYMs, for the reports room (.cursor/skills/redlamp-reports/SKILL.md).

    scripts/symbolicate-report.py <issue>             the crashed thread, the main thread and an Objective-C
                                                      exception's backtrace, as Markdown
    scripts/symbolicate-report.py <issue> --all       every thread
    scripts/symbolicate-report.py <issue> --comment   and posts it on the issue, in place of an earlier run's
    scripts/symbolicate-report.py diagnostics.json    a report's diagnostics.json kept here, or an incident alone
    scripts/symbolicate-report.py <issue> --dsyms <folder>
                                                      another build's dSYMs, such as a development build's
    scripts/symbolicate-report.py --fetch <version>   only downloads a release's dSYMs into the cache

An in-app report's diagnostics.json holds its incident (packages/RedlampUI/Sources/Feedback/Incidents/
Incident.swift): each thread's frames as an index into its binaries and an offset from the start of that
binary's text segment, with Apple's frames named by the Mac and Redlamp's unnamed, since a release ships
stripped. Each of Redlamp's binaries is matched by UUID to a dSYM of the version the incident names, from
dSYMs-<version>.zip on its GitHub release (mise/tasks/release), which is downloaded once, about 105 MB, and
kept unzipped, about 350 MB, in ~/Library/Caches/Redlamp/dSYMs/<version>/ (REDLAMP_DSYMS_CACHE moves it;
delete a version's folder to free it). atos names each frame at the binary's load address plus its offset,
or, when the incident has no load address, at the address of the __TEXT segment in the dSYM; a caller's
frame is looked up one byte before its return address, inside its call. A version with no dSYMs, and a
binary whose UUID matches none of them, as a development build's doesn't, are said plainly in the Markdown,
and their frames keep only the names the Mac gave them.

The Markdown starts with a hidden `<!-- redlamp-symbolicated v1 {…} -->` line, from which the room shows a
report as symbolicated, with the first of Redlamp's frames in the thread that crashed.
"""

import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

REPO = "pdcgomes/redlamp"
CACHE = pathlib.Path(os.environ.get("REDLAMP_DSYMS_CACHE") or pathlib.Path.home() / "Library/Caches/Redlamp/dSYMs")
# Written beside a version's dSYMs before they're moved into place, so a download cut short is never taken for them.
UUIDS = "uuids.json"
FEEDBACK_LINE = re.compile(r"<!-- redlamp-feedback v1 (\{.*?\}) -->")
DIAGNOSTICS_LINK = re.compile(r"\[diagnostics\.json\]\((https://[^)\s]+)\)")
GITHUB_FILE = re.compile(r"^https://(?:github\.com/([^/]+/[^/]+)/blob|raw\.githubusercontent\.com/([^/]+/[^/]+))/([^/]+)/(.+)$")
RELEASE_VERSION = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?")
SYMBOLICATED = "redlamp-symbolicated v1"
MAIN_QUEUE = "com.apple.main-thread"
SOURCES = {"crashReport": "macOS's crash report", "metricKit": "MetricKit", "watchdog": "Redlamp's hang watchdog"}
FRAMES = 100
# GitHub refuses a comment over 65,536 characters.
COMMENT_LIMIT = 65_000


class GitHubError(Exception):
    """What gh said when a call failed."""


class Unavailable(Exception):
    """Why there are no dSYMs to name Redlamp's frames with, in a sentence for the report."""


def gh(*args, stdin=None):
    result = subprocess.run(["gh", *args], capture_output=True, text=True, input=stdin)
    if result.returncode != 0:
        raise GitHubError(result.stderr.strip() or f"gh {' '.join(args[:2])} failed")
    return result.stdout


# ---------------------------------------------------------------- the report


def read_linked(url):
    """A file a report links to, read through gh when it's on GitHub, so the attachments repository can be private."""
    match = GITHUB_FILE.match(url)
    if not match:
        with urllib.request.urlopen(url, timeout=60) as response:
            return response.read().decode()
    repo, ref, path = match[1] or match[2], match[3], match[4]
    return gh("api", "-H", "Accept: application/vnd.github.raw+json", f"repos/{repo}/contents/{path}?ref={ref}")


def load(source, repo):
    """(the diagnostics.json, the issue) for an issue number, or (the file's JSON, None) for a file."""
    number = source.lstrip("#")
    if number.isdigit():
        issue = json.loads(gh("issue", "view", number, "--repo", repo, "--json", "number,title,url,body"))
        link = DIAGNOSTICS_LINK.search(issue["body"] or "")
        if not link:
            raise SystemExit(f"#{number} links no diagnostics.json (a report sent without its details has none), "
                             "so there are no stacks to symbolicate.")
        return json.loads(read_linked(link[1])), issue
    try:
        return json.loads(pathlib.Path(source).expanduser().read_text()), None
    except OSError as error:
        raise SystemExit(f"Couldn't read {source}: {error.strerror}.")
    except json.JSONDecodeError as error:
        raise SystemExit(f"{source} isn't JSON: {error}.")


def feedback_line(body):
    """The hidden line an in-app report starts with, as a dict."""
    match = FEEDBACK_LINE.search(body or "")
    try:
        return json.loads(match[1]) if match else {}
    except json.JSONDecodeError:
        return {}


def incident_in(document):
    """The incident a diagnostics.json holds, or the document itself when it's an incident alone."""
    if isinstance(document.get("incident"), dict):
        return document["incident"]
    if document.get("kind") in ("crash", "hang") and "binaries" in document:
        return document
    return None


def release_version(text):
    """The release a version names: "0.3.2-alpha" for "0.3.2-alpha (431)"."""
    match = RELEASE_VERSION.match(text or "")
    return match[0] if match else None


def stacks(incident):
    """Every list of frames the incident holds: each thread's, then the exception's backtrace."""
    found = [thread.get("frames") or [] for thread in incident.get("threads") or []]
    return found + ([incident["exceptionBacktrace"]] if incident.get("exceptionBacktrace") else [])


def lookups(frames):
    """Each frame with the offset to look up. A caller's frame holds the address its call returns to, which can
    be the next line's, or the next function's after a call that never returns, so it's looked up a byte before."""
    return [(frame, frame.get("offset", 0) - (1 if position and frame.get("offset") else 0))
            for position, frame in enumerate(frames)]


def binary_at(incident, index):
    binaries = incident.get("binaries") or []
    return binaries[index] if isinstance(index, int) and 0 <= index < len(binaries) else None


def in_app(incident, index):
    return bool((binary_at(incident, index) or {}).get("inApp"))


# ---------------------------------------------------------------- the dSYMs


def dsym_index(folder):
    """{UUID: {"name", "arch", "path"}} for the dSYMs in `folder`, or for `folder` when it's one, as dwarfdump reads them."""
    folder = pathlib.Path(folder).resolve()
    bundles = [str(folder)] if folder.suffix == ".dSYM" else sorted(str(path) for path in folder.glob("*.dSYM"))
    out = subprocess.run(["dwarfdump", "--uuid", *bundles], capture_output=True, text=True).stdout if bundles else ""
    index = {}
    for line in out.splitlines():
        if found := re.match(r"^UUID: ([0-9A-F-]+) \(([^)]+)\) (.+)$", line):
            index[found[1]] = {"name": pathlib.Path(found[3]).name, "arch": found[2], "path": found[3]}
    return index


def cached_index(folder):
    """The index a release's cached dSYMs were written with, its paths inside `folder`."""
    entries = json.loads((folder / UUIDS).read_text())
    return {uuid: {**entry, "path": str(folder / entry["path"])} for uuid, entry in entries.items()}


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while chunk := handle.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def release_dsyms(version, repo=REPO, cache=CACHE):
    """The folder holding Redlamp `version`'s dSYMs, downloaded and unzipped the first time they're asked for."""
    folder = cache / version
    if (folder / UUIDS).exists():
        return folder
    tag, name = f"v{version}", f"dSYMs-{version}.zip"
    try:
        release = json.loads(gh("release", "view", tag, "--repo", repo, "--json", "assets"))
    except GitHubError as error:
        if "not found" not in str(error).lower():
            raise
        raise Unavailable(f"{repo} has no release {tag}, so there are no dSYMs for Redlamp {version}: the report "
                          "came from a build that wasn't released, such as a development build.") from None
    asset = next((a for a in release["assets"] if a["name"] == name), None)
    if asset is None:
        raise Unavailable(f"Redlamp {version}'s release has no {name}, so there are no dSYMs to name Redlamp's frames with.")
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=cache, prefix=f".{version}-") as scratch:
        scratch = pathlib.Path(scratch)
        print(f"Downloading {name} ({asset['size'] / 1e6:.0f} MB) into {folder}, once.", file=sys.stderr)
        gh("release", "download", tag, "--repo", repo, "--pattern", name, "--dir", str(scratch))
        digest = (asset.get("digest") or "").removeprefix("sha256:")
        if digest and sha256(scratch / name) != digest:
            raise SystemExit(f"{name} doesn't match the digest GitHub gives for it; nothing was kept.")
        subprocess.run(["ditto", "-x", "-k", str(scratch / name), str(scratch / "unzipped")], check=True)
        # The release zips the dSYMs' folder itself (ditto --keepParent).
        unzipped = scratch / "unzipped" / "dSYMs"
        if not unzipped.is_dir():
            unzipped = scratch / "unzipped"
        index = dsym_index(unzipped)
        if not index:
            raise SystemExit(f"{name} holds no dSYMs that dwarfdump can read; nothing was kept.")
        base = str(unzipped.resolve())
        entries = {uuid: {**entry, "path": os.path.relpath(entry["path"], base)} for uuid, entry in index.items()}
        (unzipped / UUIDS).write_text(json.dumps(entries, indent=1, sort_keys=True) + "\n")
        if folder.exists() and not (folder / UUIDS).exists():
            shutil.rmtree(folder)
        try:
            unzipped.rename(folder)
        except OSError:
            # Another run put them there first.
            if not (folder / UUIDS).exists():
                raise
    return folder


def text_address(path):
    """Where a binary's __TEXT segment starts before it's slid, as its dSYM records: 0x100000000 for an app, 0 for a framework."""
    out = subprocess.run(["otool", "-l", path], capture_output=True, text=True).stdout
    for command in out.split("Load command ")[1:]:
        if re.search(r"^\s+segname __TEXT$", command, re.M) and (found := re.search(r"^\s+vmaddr (0x[0-9a-fA-F]+)$", command, re.M)):
            return int(found[1], 16)
    return 0


def atos(entry, load, offsets):
    """{offset: name} for the offsets atos can name in a binary loaded at `load`."""
    offsets = sorted(set(offsets))
    result = subprocess.run(["atos", "-arch", entry["arch"], "-o", entry["path"], "-l", hex(load),
                             *(hex(load + offset) for offset in offsets)], capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"atos couldn't read {entry['path']}: {result.stderr.strip()}")
    names = {}
    for offset, line in zip(offsets, result.stdout.splitlines()):
        line = line.strip()
        # An address it can't name comes back as itself.
        if line and not line.startswith("0x"):
            names[offset] = line.replace(f" (in {entry['name']})", "", 1)
    return names


def symbolicate(incident, index):
    """({(binary, offset looked up): name} for Redlamp's frames, {binary: "other build" or "no dSYM"} for those
    `index` has nothing for: another build's binary, whose UUID differs, or one no dSYM is named for."""
    wanted = {}
    for frames in stacks(incident):
        for frame, offset in lookups(frames):
            if in_app(incident, frame.get("binary")):
                wanted.setdefault(frame["binary"], set()).add(offset)
    names, unmatched = {}, {}
    known = {entry["name"] for entry in index.values()}
    for number, offsets in sorted(wanted.items()):
        binary = binary_at(incident, number)
        entry = index.get((binary.get("uuid") or "").upper())
        if entry is None:
            unmatched[number] = "other build" if binary.get("name") in known else "no dSYM"
            continue
        load = binary["base"] if binary.get("base") is not None else text_address(entry["path"])
        names.update({(number, offset): name for offset, name in atos(entry, load, offsets).items()})
    return names, unmatched


# ---------------------------------------------------------------- the Markdown


def seconds(interval):
    """"14 s", "2 min 5 s", as the app writes a hang's length."""
    whole = max(1, int(interval + 0.5))
    return f"{whole} s" if whole < 60 else f"{whole // 60} min" + ("" if whole % 60 == 0 else f" {whole % 60} s")


def headline(incident):
    """"Crash: EXC_BAD_ACCESS (SIGSEGV)", "Hang: 14 s, then Redlamp was closed": how the app's title for it begins."""
    if incident.get("kind") == "hang":
        duration = incident.get("duration")
        length = seconds(duration) if isinstance(duration, (int, float)) else "the main thread stopped"
        return f"Hang: {length}" + (", then Redlamp was closed" if incident.get("endedSession") else "")
    return f"Crash: {incident.get('exception') or 'Redlamp quit unexpectedly'}"


def moment(value):
    """An incident's time in words, "14 October 2026 at 09:08 UTC", from ISO 8601 as the app writes it, or from
    seconds since 2001, JSONEncoder's default."""
    try:
        if isinstance(value, (int, float)):
            when = dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc) + dt.timedelta(seconds=value)
        else:
            when = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError, OverflowError):
        return None
    when = when.astimezone(dt.timezone.utc) if when.tzinfo else when.replace(tzinfo=dt.timezone.utc)
    return f"{when.day} {when:%B %Y} at {when:%H:%M} UTC"


def listed(names):
    return names[0] if len(names) == 1 else ", ".join(names[:-1]) + " and " + names[-1]


def threads_of_note(incident):
    """(the crashed thread's index, the main thread's, whether its queue says it's the main thread). Without one
    on the main queue, as MetricKit's threads have none, it's thread 0."""
    threads = incident.get("threads") or []
    crashed = next((i for i, thread in enumerate(threads) if thread.get("crashed")), None)
    queued = next((i for i, thread in enumerate(threads) if thread.get("queue") == MAIN_QUEUE), None)
    return crashed, queued if queued is not None else (0 if threads else None), queued is not None


def heading(incident, index, crashed, main, named_main):
    thread = incident["threads"][index]
    title = f"Thread {index}"
    if index == crashed:
        title += " crashed" if incident.get("kind") != "hang" else " hung"
    if index == main and named_main:
        title += ", the main thread"
    labels = [f"`{label}`" for label in (thread.get("name"), thread.get("queue")) if label and label != MAIN_QUEUE]
    return f"**{title}**" + (f": {', '.join(labels)}" if labels else "")


def block(incident, frames, names, limit):
    """A stack as a code block: each frame's number, binary and name, or its offset where it has no name."""
    def binary_name(frame):
        return (binary_at(incident, frame.get("binary")) or {}).get("name") or "???"
    width = min(26, max((len(binary_name(frame)) for frame in frames[:limit]), default=0))
    lines = []
    for position, (frame, offset) in enumerate(lookups(frames)[:limit]):
        name = names.get((frame.get("binary"), offset)) or frame.get("symbol") or f"+ {frame.get('offset', 0):#x}"
        lines.append(f"{position:<4}{binary_name(frame):<{width}}  {name}")
    if len(frames) > limit:
        lines.append(f"… and {len(frames) - limit} more frames")
    return ["```text", *lines, "```"]


def culprit(incident, names):
    """The first of Redlamp's frames in the thread that crashed or hung (the main thread's without one): (binary, frame)."""
    crashed, main, _ = threads_of_note(incident)
    focus = crashed if crashed is not None else main
    frames = incident["threads"][focus].get("frames") or [] if focus is not None else []
    for frame, offset in lookups(frames):
        if in_app(incident, frame.get("binary")):
            name = names.get((frame["binary"], offset)) or frame.get("symbol") or f"+ {frame.get('offset', 0):#x}"
            return binary_at(incident, frame["binary"]).get("name"), name
    return None, None


def markdown(incident, names, notes, *, source=None, version=None, number=None, everything=False, limit=FRAMES,
             reporter=False):
    """The report's stacks as Markdown, its first line the hidden one the room reads."""
    threads = incident.get("threads") or []
    crashed, main, named_main = threads_of_note(incident)
    shown = list(range(len(threads))) if everything else [i for i in dict.fromkeys((crashed, main)) if i is not None]
    own = [(frame.get("binary"), offset) for frames in stacks(incident) for frame, offset in lookups(frames)
           if in_app(incident, frame.get("binary"))]
    named = sum(1 for key in own if key in names)
    binary, frame = culprit(incident, names)
    empty = None
    if not any(stacks(incident)):
        why = (": Redlamp's hang watchdog records when a hang began and how long it lasted, not where the main thread was"
               if (incident.get("sources") or []) == ["watchdog"] else "")
        empty = f"The report holds no stacks{why}, so there's nothing to symbolicate."
    meta = {"version": version, "binary": binary, "culprit": frame, "named": named, "unnamed": len(own) - named,
            "note": (notes or [empty])[0]}
    # "--" would end the HTML comment; JSON never has it outside a string, and "\u002d" is a dash inside one.
    hidden = json.dumps(meta, ensure_ascii=False).replace("--", "-\\u002d")
    lines = [f"<!-- {SYMBOLICATED} {hidden} -->"]
    if reporter:
        what = "stopped responding" if incident.get("kind") == "hang" else "quit"
        lines += [f"This is where Redlamp was when it {what}, with its own functions named, so I can work out the fix. "
                  "There's nothing you need to do.", ""]
    when = moment(incident.get("time"))
    lines.append(f"**{headline(incident)}** in Redlamp {incident.get('version') or version or '(the version is unknown)'}"
                 + (f", on {when}" if when else "") + ".")
    if names:
        lines += ["", f"Redlamp's own frames are named from {source}; Apple's are as the Mac named them."]
    lines += [f"\n{note}" for note in notes]
    if incident.get("reasons"):
        lines += ["", "```text", *incident["reasons"], "```"]
    if empty:
        lines += ["", empty]
    for index in shown:
        lines += ["", heading(incident, index, crashed, main, named_main), "",
                  *block(incident, threads[index].get("frames") or [], names, limit)]
    if incident.get("exceptionBacktrace"):
        lines += ["", "**Where the Objective-C exception was raised**", "",
                  *block(incident, incident["exceptionBacktrace"], names, limit)]
    others = len(threads) - len(shown)
    if others:
        lines += ["", f"{others} other thread{'s' if others != 1 else ''} not shown: "
                  f"`scripts/symbolicate-report.py {number or 'diagnostics.json'} --all` prints every thread."]
    sources = [SOURCES.get(s, s) for s in incident.get("sources") or []]
    lines += ["", f"<sub>From {listed(sources) if sources else 'the report'}, by scripts/symbolicate-report.py.</sub>"]
    return "\n".join(lines) + "\n"


def fitting(*args, **options):
    """The Markdown, with fewer frames to a thread, then only the threads of note, until it fits in a comment."""
    for limit in (FRAMES, 50, 25, 12):
        text = markdown(*args, **options, limit=limit)
        if len(text) <= COMMENT_LIMIT:
            return text
    return markdown(*args, **{**options, "everything": False}, limit=12)


def notes_on(unmatched, incident, source):
    """A sentence on each kind of binary whose frames couldn't be named from `source`."""
    def names(why):
        return [binary_at(incident, number)["name"] for number, reason in sorted(unmatched.items()) if reason == why]
    notes = []
    if other := names("other build"):
        notes.append(f"The UUID{'s' if len(other) > 1 else ''} of {listed(other)} match{'' if len(other) > 1 else 'es'} "
                     f"none of {source}: the report came from another build of Redlamp, such as a development build, "
                     f"so {'their' if len(other) > 1 else 'its'} frames are named only where the Mac named them.")
    if none := names("no dSYM"):
        notes.append(f"{listed(none)} {'have' if len(none) > 1 else 'has'} no dSYM among {source}, so "
                     f"{'their' if len(none) > 1 else 'its'} frames are named only where the Mac named them.")
    return notes


# ---------------------------------------------------------------- the comment


def post(number, repo, body):
    """Posts the Markdown on the issue, or puts it in place of the comment an earlier run posted. Returns
    (its address, whether it replaced one)."""
    me = gh("api", "user", "--jq", ".login").strip()
    earlier = gh("api", "--paginate", f"repos/{repo}/issues/{number}/comments", "--jq",
                 f'.[] | select(.user.login == "{me}" and (.body | contains("{SYMBOLICATED}"))) | .id').split()
    payload = json.dumps({"body": body})
    if earlier:
        reply = gh("api", "-X", "PATCH", f"repos/{repo}/issues/comments/{earlier[-1]}", "--input", "-", stdin=payload)
    else:
        reply = gh("api", "-X", "POST", f"repos/{repo}/issues/{number}/comments", "--input", "-", stdin=payload)
    return json.loads(reply)["html_url"], bool(earlier)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("report", nargs="?", help="an issue number, or a diagnostics.json (or an incident's JSON) here")
    parser.add_argument("--all", action="store_true", help="every thread, not only the crashed and main threads")
    parser.add_argument("--comment", action="store_true", help="post it on the issue, in place of an earlier run's comment")
    parser.add_argument("--dsyms", type=pathlib.Path, help="a folder of dSYMs to use instead of the release's")
    parser.add_argument("--repo", default=REPO, help=f"the issues' repository (default: {REPO})")
    parser.add_argument("--fetch", metavar="VERSION", help="only download VERSION's dSYMs into the cache")
    options = parser.parse_args()
    try:
        if options.fetch:
            print(release_dsyms(options.fetch, options.repo))
            return
        if not options.report:
            parser.error("give an issue number or a diagnostics.json")
        document, issue = load(options.report, options.repo)
        if options.comment and issue is None:
            parser.error("--comment needs an issue number")
        incident = incident_in(document)
        if incident is None:
            raise SystemExit(f"{'#' + str(issue['number']) if issue else options.report} holds no incident: "
                             "it's a report of a bug, not of a crash or a hang.")
        system = document.get("system") or {}
        version = (release_version(incident.get("version")) or release_version(system.get("appVersion"))
                   or release_version(feedback_line(issue["body"] if issue else "").get("version")))
        notes = []
        if system.get("configuration") not in (None, "Release"):
            notes.append(f"It came from a {system['configuration']} build"
                         + (f" at {system['commit']}" if system.get("commit") else "") + ", which no release's dSYMs cover.")
        index, source = {}, None
        if not any(in_app(incident, frame.get("binary")) for frames in stacks(incident) for frame in frames):
            pass
        elif options.dsyms:
            index, source = dsym_index(options.dsyms), f"the dSYMs in {options.dsyms}"
        elif not version:
            notes.append("The report doesn't say which version of Redlamp it came from, so there are no dSYMs to "
                         "name Redlamp's frames with.")
        else:
            try:
                index, source = cached_index(release_dsyms(version, options.repo)), f"Redlamp {version}'s dSYMs"
            except Unavailable as reason:
                notes.append(str(reason))
        names, unmatched = symbolicate(incident, index) if index else ({}, {})
        notes += notes_on(unmatched, incident, source)
        details = dict(source=source, version=version, number=issue["number"] if issue else None, everything=options.all)
        if not options.comment:
            print(markdown(incident, names, notes, **details), end="")
            return
        text = fitting(incident, names, notes, **details, reporter=True)
        print(text, end="")
        url, replaced = post(issue["number"], options.repo, text)
        print(f"\n{'Replaced the earlier comment' if replaced else 'Posted it'} on #{issue['number']}: {url}", file=sys.stderr)
    except GitHubError as error:
        raise SystemExit(f"gh: {error}")


if __name__ == "__main__":
    main()
