#!/usr/bin/env bash
# Seals the firmware model's files for release builds (TON-50) with the app's own pack code, so
# the format can't drift: builds the redlamp CLI and runs `redlamp recipe firmware-pack`, passing
# its options on. It writes tables.bin and key.bin into --out, to host at two unlisted addresses,
# and keeps the secret in --config, the Firmware.local.xcconfig that `mise run release` reads: the
# secret there is used again when the file exists, and made new and written there when it doesn't.
# The secret is never passed on the command line. Neither folder may be in a checkout, and the
# config may not sit in --out, so it isn't uploaded with the two files.
#
# Usage: scripts/firmware-pack.sh --out <folder> --config <kept config> [--model <folder>] [--team <Team ID>]
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

export REDLAMP_TEAM_ID="${REDLAMP_TEAM_ID:-$(mise exec -- sh -c 'printf %s "$REDLAMP_TEAM_ID"')}"
DERIVED="$ROOT/build/DerivedData-firmware-pack"
xcodebuild build -workspace Redlamp.xcworkspace -scheme redlamp -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" -quiet
exec "$DERIVED/Build/Products/Debug/redlamp" recipe firmware-pack "$@"
