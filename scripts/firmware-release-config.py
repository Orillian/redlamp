#!/usr/bin/env python3
"""Puts the firmware model's hosted addresses and secret into a release's build worktree (TON-50).

The owner keeps Firmware.local.xcconfig outside the repository (`redlamp recipe firmware-pack`
writes it). It holds the two addresses of the hosted files and the masked secret the inner key
needs. This writes the worktree's own Firmware.local.xcconfig with only the two addresses, which
Version.xcconfig includes so the build's Info.plist carries them, and writes the masked secret into
FirmwareBakedSecret.swift, so the binary carries it and no build setting does. Only `mise run
release` runs this, on its throwaway worktree; nothing it writes is committed, and it never prints
the secret.

Each address is written https:/$()/host/path: an xcconfig reads // as a comment, so a plain
https://host would reach Info.plist as "https:". A hand-edited plain address is re-escaped here.

Usage: scripts/firmware-release-config.py <kept config> <worktree>
"""

import re
import sys
from pathlib import Path
from urllib.parse import urlparse

SECRET_BYTES = 32
BAKED = "packages/RedlampRecipes/Sources/Firmware/FirmwareBakedSecret.swift"


def settings(text: str) -> dict:
    values = {}
    for line in text.splitlines():
        if line.lstrip().startswith("//"):
            continue
        match = re.fullmatch(r"\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*", line)
        if match:
            values[match.group(1)] = match.group(2)
    return values


def address(values: dict, name: str) -> str:
    # The kept file may write the escaped https:/$()/… or, if hand-edited, a plain https://….
    value = values.get(name, "").replace("$()", "")
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc:
        sys.exit(f"firmware-release-config: {name} isn't an https address; fill it in the kept config")
    # Re-escape, so // never reaches the xcconfig as a comment.
    return value.replace("://", ":/$()/", 1)


def main() -> int:
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[-1])
    config, worktree = Path(sys.argv[1]), Path(sys.argv[2])
    values = settings(config.read_text())
    tables = address(values, "REDLAMP_FIRMWARE_TABLES_URL")
    key = address(values, "REDLAMP_FIRMWARE_KEY_URL")
    masked = values.get("REDLAMP_FIRMWARE_SECRET_MASKED", "")
    if not re.fullmatch(rf"[0-9a-fA-F]{{{SECRET_BYTES * 2}}}", masked):
        sys.exit(f"firmware-release-config: REDLAMP_FIRMWARE_SECRET_MASKED isn't {SECRET_BYTES} bytes of hex")
    baked = worktree / BAKED
    if "static let masked: [UInt8] = []" not in baked.read_text():
        sys.exit(f"firmware-release-config: {BAKED} isn't the repository's empty one")

    # Only the two addresses, so the secret never becomes a build setting (and so never reaches a
    # future script phase's environment or the build log).
    (worktree / "Firmware.local.xcconfig").write_text(
        "// Written by scripts/firmware-release-config.py in a release's build worktree; never committed.\n"
        f"REDLAMP_FIRMWARE_TABLES_URL = {tables}\n"
        f"REDLAMP_FIRMWARE_KEY_URL = {key}\n"
    )
    pairs = [masked[i : i + 2] for i in range(0, len(masked), 2)]
    rows = [", ".join(f"0x{pair.upper()}" for pair in pairs[i : i + 8]) for i in range(0, len(pairs), 8)]
    body = ",\n        ".join(rows)
    baked.write_text(
        "// Written by scripts/firmware-release-config.py in a release's build worktree; never committed.\n"
        "enum FirmwareBakedSecret {\n"
        f"    static let masked: [UInt8] = [\n        {body},\n    ]\n"
        "}\n"
    )
    print("==> Firmware model: both addresses and the masked secret are in the build")
    return 0


if __name__ == "__main__":
    sys.exit(main())
