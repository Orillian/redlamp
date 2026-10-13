#!/usr/bin/env python3
"""What an app bundle holds, part by part, and how it compares with others (ARC-18).

    scripts/bundle-sizes.py build/release/Redlamp.app
    scripts/bundle-sizes.py <older>.app <newer>.app [...]   # side by side, the last column's growth
    scripts/bundle-sizes.py --binaries <app> [...]          # each Mach-O's segments and link-edit data
    scripts/bundle-sizes.py --json <app> [...]

Sizes are kilobytes as du counts them, the blocks a file takes on disk, which is what
scripts/check-release-bundle.sh holds to its budget. The README's installed size is the files'
own bytes, as Finder counts them, which --bytes shows instead.

A part is the main executable, each framework, XPC service and helper, and each item at the top
of Contents/Resources; what's left (Info.plist, the app's signature) is Other.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def part_of(relative: Path) -> tuple[str, str]:
    """The part a file belongs to, and what it is within it."""
    parts = relative.parts
    if len(parts) < 2 or parts[0] != "Contents":
        return "Other", ""
    area = parts[1]
    if area in ("Frameworks", "XPCServices", "PlugIns") and len(parts) > 2:
        name = parts[2]
        inner = Path(*parts[3:]) if len(parts) > 3 else Path()
        stem = name.rsplit(".", 1)[0]
        if inner.name == stem and inner.parent.name in ("A", "B", "C", ""):
            return name, "binary"
        if "Resources" in inner.parts and inner.name != "Info.plist":
            return name, "resources"
        if inner.parts[-2:] == ("MacOS", stem) or (area == "XPCServices" and "MacOS" in inner.parts):
            return name, "binary"
        return name, "other"
    if area in ("MacOS", "Helpers") and len(parts) > 2:
        return f"{area}/{parts[2]}", "binary"
    if area == "Resources" and len(parts) > 2:
        return f"Resources/{parts[2]}", "resources"
    return "Other", ""


def measure(app: Path) -> dict:
    """Every part's kilobytes on disk and bytes, with what's inside it."""
    totals: dict[str, dict] = {}
    seen: set[tuple[int, int]] = set()
    for folder, folders, files in os.walk(app):
        for name in folders + files:
            path = Path(folder) / name
            info = path.lstat()
            if (info.st_dev, info.st_ino) in seen:
                continue
            seen.add((info.st_dev, info.st_ino))
            part, kind = part_of(path.relative_to(app))
            entry = totals.setdefault(part, {"kb": 0, "bytes": 0, "inside": {}})
            entry["kb"] += info.st_blocks * 512 / 1024
            if path.is_file() and not path.is_symlink():
                entry["bytes"] += info.st_size
                if kind:
                    entry["inside"][kind] = entry["inside"].get(kind, 0) + info.st_size
    root = app.lstat()
    totals.setdefault("Other", {"kb": 0, "bytes": 0, "inside": {}})["kb"] += root.st_blocks * 512 / 1024
    du = int(subprocess.run(["du", "-sk", str(app)], capture_output=True, text=True, check=True).stdout.split()[0])
    return {"app": str(app), "du_kb": du, "bytes": sum(p["bytes"] for p in totals.values()), "parts": totals}


LOAD = re.compile(r"^\s*cmd (LC_\w+)")
FIELD = re.compile(r"^\s*(\w+) (\S+)")


def machos(app: Path) -> list[Path]:
    found = []
    for folder, _, files in os.walk(app):
        for name in files:
            path = Path(folder) / name
            if path.is_symlink() or path.stat().st_size < 4096:
                continue
            with path.open("rb") as handle:
                magic = handle.read(4)
            if magic in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe"):
                found.append(path)
    return sorted(found)


def binary(path: Path) -> dict:
    """A Mach-O's segments and the link-edit data inside __LINKEDIT, in bytes."""
    listing = subprocess.run(["otool", "-l", "-arch", "arm64", str(path)], capture_output=True, text=True).stdout
    segments: dict[str, int] = {}
    sections: dict[str, int] = {}
    linkedit: dict[str, int] = {}
    command, fields, section = None, {}, None

    def flush():
        if command == "LC_SEGMENT_64" and "segname" in fields:
            segments[fields["segname"]] = segments.get(fields["segname"], 0) + int(fields.get("filesize", "0"))
        names = {
            "LC_SYMTAB": None,
            "LC_DYLD_EXPORTS_TRIE": "exports trie",
            "LC_DYLD_CHAINED_FIXUPS": "chained fixups",
            "LC_FUNCTION_STARTS": "function starts",
            "LC_DATA_IN_CODE": "data in code",
            "LC_CODE_SIGNATURE": "code signature",
            "LC_DYLD_INFO_ONLY": None,
        }
        if command == "LC_SYMTAB":
            linkedit["symbol table"] = int(fields.get("nsyms", "0")) * 16
            linkedit["symbol names"] = int(fields.get("strsize", "0"))
        elif command == "LC_DYSYMTAB":
            linkedit["indirect symbols"] = int(fields.get("nindirectsyms", "0")) * 4
        elif command == "LC_DYLD_INFO_ONLY":
            for key in ("rebase_size", "bind_size", "weak_bind_size", "lazy_bind_size", "export_size"):
                linkedit[key.replace("_size", "").replace("_", " ")] = int(fields.get(key, "0"))
        elif names.get(command):
            linkedit[names[command]] = int(fields.get("datasize", "0"))

    for line in listing.splitlines():
        if line.startswith("Load command"):
            flush()
            command, fields, section = None, {}, None
            continue
        if line.strip() == "Section":
            section = {}
            continue
        match = LOAD.match(line)
        if match:
            command = match.group(1)
            continue
        match = FIELD.match(line)
        if not match:
            continue
        key, value = match.groups()
        if section is not None:
            section[key] = value
            if key == "size" and "sectname" in section:
                name = f"{section.get('segname', '?')},{section['sectname']}"
                sections[name] = sections.get(name, 0) + int(value, 16)
        else:
            fields.setdefault(key, value)
    flush()
    return {"bytes": path.stat().st_size, "segments": segments, "sections": sections, "linkedit": linkedit}


def mb(value: float) -> str:
    return f"{value / 1e6:,.2f}"


def table(builds: list[dict], use_bytes: bool) -> None:
    key = "bytes" if use_bytes else "kb"
    unit = "MB (bytes)" if use_bytes else "KB on disk"
    names = sorted({p for b in builds for p in b["parts"]}, key=lambda p: -max(b["parts"].get(p, {}).get(key, 0) for b in builds))
    width = max(len(n) for n in names + ["Total"])
    labels = [Path(b["app"]).parent.name or b["app"] for b in builds]
    header = f"{'Part':<{width}}  " + "  ".join(f"{label[-12:]:>12}" for label in labels)
    if len(builds) > 1:
        header += f"  {'growth':>10}"
    print(f"Sizes in {unit}")
    print(header)
    for name in names:
        values = [b["parts"].get(name, {}).get(key, 0) for b in builds]
        cells = "  ".join(f"{(mb(v) if use_bytes else f'{v:,.0f}'):>12}" for v in values)
        line = f"{name:<{width}}  {cells}"
        if len(builds) > 1:
            growth = values[-1] - values[-2]
            line += f"  {(mb(growth) if use_bytes else f'{growth:+,.0f}'):>10}"
        print(line)
    totals = [b["bytes"] if use_bytes else b["du_kb"] for b in builds]
    cells = "  ".join(f"{(mb(v) if use_bytes else f'{v:,}'):>12}" for v in totals)
    line = f"{'Total':<{width}}  {cells}"
    if len(builds) > 1:
        growth = totals[-1] - totals[-2]
        line += f"  {(mb(growth) if use_bytes else f'{growth:+,}'):>10}"
    print(line)


def binaries(apps: list[Path]) -> None:
    for app in apps:
        print(f"== {app}")
        for path in machos(app):
            info = binary(path)
            relative = path.relative_to(app)
            segments = ", ".join(f"{name} {value / 1024:,.0f}" for name, value in sorted(info["segments"].items(), key=lambda s: -s[1]) if value)
            linkedit = ", ".join(f"{name} {value / 1024:,.0f}" for name, value in sorted(info["linkedit"].items(), key=lambda s: -s[1]) if value >= 1024)
            print(f"{relative}: {info['bytes'] / 1024:,.0f} KB")
            print(f"    segments (KB): {segments}")
            print(f"    link-edit (KB): {linkedit}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("apps", nargs="+", type=Path)
    parser.add_argument("--bytes", action="store_true", help="the files' own sizes, as the README's installed size")
    parser.add_argument("--binaries", action="store_true", help="each Mach-O's segments and link-edit data")
    parser.add_argument("--json", action="store_true")
    options = parser.parse_args()
    for app in options.apps:
        if not app.is_dir():
            sys.exit(f"no app at {app}")
    if options.binaries:
        binaries(options.apps)
        return 0
    builds = [measure(app) for app in options.apps]
    if options.json:
        for build, app in zip(builds, options.apps):
            build["binaries"] = {str(p.relative_to(app)): binary(p) for p in machos(app)}
        print(json.dumps(builds, indent=1))
        return 0
    table(builds, options.bytes)
    return 0


if __name__ == "__main__":
    sys.exit(main())
