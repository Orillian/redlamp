#!/bin/bash
#
# The census of this Mac's Photos library (LIB-57), one step at a time, in the kit's own Redlamp under its own access
# to Photos (DEC-106: Photos is only read). Needs only Terminal: no Xcode, no repository.
#
# usage: bash run.sh [measure | recovered | offline | week]
#
#   measure     about 15 minutes: allow access to Photos when asked, then leave the Mac alone, on power and Wi-Fi
#   recovered   a few seconds, once one photo has been deleted in Photos and recovered from Recently Deleted
#   offline     under a minute, with Wi-Fi off and Ethernet unplugged
#   week        a week after measuring; it deletes what the census kept on this Mac
#
# Each step leaves the report in results/census.json, with its text in results/census.txt, to send back. The report
# holds counts, sizes, times and answers, never a photo's name, place, album or identifier. Until the week step, the
# identifiers the later steps need stay in ~/Library/Application Support/Redlamp Photos Census/State.
#
# CENSUS_FOLDER keeps the census somewhere else (a path without spaces), CENSUS_SIMULATED reads a simulated library's
# manifest in place of Photos and CENSUS_SAMPLE samples fewer photos: for a dry run where the kit is made.

set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP="${1:-measure}"
case "$STEP" in
measure | recovered | offline | week) ;;
*)
    echo "usage: bash run.sh [measure | recovered | offline | week]" >&2
    exit 2
    ;;
esac
APP_NAME="Redlamp Photos Census.app"
BUNDLE_ID=app.redlamp.mac.census
WORK="${CENSUS_FOLDER:-$HOME/Library/Application Support/Redlamp Photos Census}"
APP="$WORK/$APP_NAME"
LOG="$WORK/census.log"
mkdir -p "$WORK" "$KIT/results"

# AirDrop and the Finder's unzipping mark every file; macOS would refuse to run the app's code.
xattr -dr com.apple.quarantine "$KIT" 2>/dev/null || true
# The census runs from a copy outside Downloads, whose privacy prompts it doesn't need, the same copy at every step.
if [[ ! -d "$APP" || "$KIT/$APP_NAME/Contents/Info.plist" -nt "$APP/Contents/Info.plist" ]]; then
    rm -rf "$APP"
    ditto "$KIT/$APP_NAME" "$APP"
fi
[[ "$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")" == "$BUNDLE_ID" ]] || {
    echo "run.sh: the app in $APP isn't the census's ($BUNDLE_ID)" >&2
    exit 1
}
pkill -f "$APP/Contents/MacOS/" 2>/dev/null || true

# `open` can drop --args, so the app reads its arguments from the file beside it, which it then deletes.
ARGS="--photos-census $STEP"
[[ -z "${CENSUS_FOLDER:-}" ]] || ARGS+=" --photos-census-folder $CENSUS_FOLDER"
[[ -z "${CENSUS_SIMULATED:-}" ]] || ARGS+=" --photos-census-simulated $CENSUS_SIMULATED"
[[ -z "${CENSUS_SAMPLE:-}" ]] || ARGS+=" --photos-census-sample $CENSUS_SAMPLE"
printf '%s\n' "$ARGS" >"$WORK/redlamp-launch-args"

echo "== Redlamp's census of this Mac's Photos library: $STEP ($(sed -n 's/.*"commit": *"\([^"]*\)".*/\1/p' "$KIT/kit.json"))"
touch "$LOG"
tail -n 0 -F "$LOG" 2>/dev/null &
TAIL=$!
disown "$TAIL"
caffeinate -i -d -w $$ &
# Opened through macOS, so Photos asks for the census's own access rather than Terminal's.
open -n -W "$APP" || {
    kill "$TAIL" 2>/dev/null || true
    echo "run.sh: macOS didn't open the census's app; see System Settings › Privacy & Security" >&2
    exit 1
}
sleep 1
kill "$TAIL" 2>/dev/null || true

if [[ -f "$WORK/census.json" ]]; then
    # A last look that the report holds no identifier: Photos' local identifiers are UUIDs.
    if grep -Eq '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-' "$WORK/census.json"; then
        echo "run.sh: the report holds something like an identifier, so it isn't copied to results/" >&2
        exit 1
    fi
    cp "$WORK/census.json" "$WORK/census.txt" "$KIT/results/"
    echo "== The report is in $KIT/results: send census.json back (AirDrop it to the Mac the kit came from)."
fi

if [[ "$STEP" == week ]]; then
    # The census is over: its app, its preferences and its access to Photos go; the report stays.
    rm -rf "$APP" "$LOG"
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    rm -rf "$HOME/Library/Preferences/$BUNDLE_ID.plist" "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState" \
        "$HOME/Library/Caches/$BUNDLE_ID" "$HOME/Library/HTTPStorages/$BUNDLE_ID"
    tccutil reset Photos "$BUNDLE_ID" >/dev/null 2>&1 || true
    echo "== The census is finished. $WORK holds only its report; delete it, and this kit, once the report is back."
fi
