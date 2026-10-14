#!/usr/bin/env python3
"""Fails when the branch adds a number from the firmware model's files.

The fujisim-prototype branch reads every number of the firmware-derived model at runtime from
its folder (REDLAMP_FIRMWARE_MODEL, or ~/src/redlamp-fujix100v/model) and must never hold one.
This reads the folder's JSON files, then checks every line the branch adds over origin/main, its
uncommitted changes and untracked files included:

- a decimal with three or more significant digits that equals one of the model's values
  rounded to as many places, so a copied matrix or curve is caught however it was rounded;
- an integer of 100 or more that is one of the model's integers and not a multiple of 100,
  which Redlamp's own code is full of (the cards' dynamic range percentages among them).

Usage: scripts/check-firmware-numbers.py [--base <ref>]
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

FILES = [
    "fsim_params.json",
    "tone_gain_curves.json",
    "calibration.json",
    "fujisim_constants.json",
    "test_vectors.json",
]
NUMBER = re.compile(r"(?<![\w.])[-+]?(?:\d+\.\d+|\d+)(?:[eE][-+]?\d+)?(?![\w.])")
# Numbers that equal one of the model's by chance, each where it means something else.
ALLOWED = {
    ("packages/RedlampRecipes/Sources/Firmware/FirmwareModelHost.swift", "404"): "HTTP's Not Found",
}


def model_folder() -> Path:
    value = os.environ.get("REDLAMP_FIRMWARE_MODEL")
    if value and value != "1":
        return Path(value).expanduser()
    return Path.home() / "src/redlamp-fujix100v/model"


def numbers(value, floats: set, integers: set) -> None:
    if isinstance(value, bool):
        return
    if isinstance(value, int):
        integers.add(abs(value))
    elif isinstance(value, float):
        floats.add(abs(value))
        if value.is_integer():
            integers.add(abs(int(value)))
    elif isinstance(value, dict):
        for key, item in value.items():
            if re.fullmatch(r"-?\d+", key):
                integers.add(abs(int(key)))
            numbers(item, floats, integers)
    elif isinstance(value, list):
        for item in value:
            numbers(item, floats, integers)


def added_lines(root: Path, base: str):
    merge_base = subprocess.check_output(["git", "merge-base", base, "HEAD"], cwd=root, text=True).strip()
    diff = subprocess.check_output(["git", "diff", "--unified=0", merge_base], cwd=root, text=True)
    path = None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else None
        elif line.startswith("+") and path:
            yield path, line[1:]
    untracked = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard"], cwd=root, text=True)
    for name in untracked.splitlines():
        try:
            text = (root / name).read_text()
        except (UnicodeDecodeError, OSError):
            continue
        for line in text.splitlines():
            yield name, line


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="origin/main")
    args = parser.parse_args()
    root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    folder = model_folder()
    floats: set = set()
    integers: set = set()
    for name in FILES:
        file = folder / name
        if not file.exists():
            print(f"missing {file}", file=sys.stderr)
            return 2
        numbers(json.loads(file.read_text()), floats, integers)

    by_places: dict = {}
    found = []
    for path, line in added_lines(root, args.base):
        if path == "scripts/check-firmware-numbers.py":
            continue
        for match in NUMBER.finditer(line):
            token = match.group().lstrip("+-")
            if (path, token) in ALLOWED:
                continue
            if "." in token and "e" not in token.lower():
                places = len(token.split(".")[1])
                if places < 3 or len(token.replace(".", "").lstrip("0")) < 3:
                    continue
                if places not in by_places:
                    by_places[places] = {round(value, places) for value in floats}
                if round(float(token), places) in by_places[places]:
                    found.append((path, token, line.strip()))
            elif token.isdigit():
                value = int(token)
                if value >= 100 and value % 100 != 0 and value in integers:
                    found.append((path, token, line.strip()))
    for path, token, line in found:
        print(f"{path}: {token}: {line[:160]}")
    if found:
        print(f"{len(found)} number(s) from {folder} in the branch's changes", file=sys.stderr)
        return 1
    print(f"no numbers from {folder} in the branch's changes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
