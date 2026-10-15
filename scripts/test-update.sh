#!/usr/bin/env bash
#
# Runs a Sparkle update end to end on this Mac: an old copy of a dry-run build updates itself to
# a new copy from a feed served on 127.0.0.1. Make the dry run first:
#
#   REF=HEAD DRY_RUN=1 mise run release
#   scripts/test-update.sh          # choose Check for Updates… in the old copy, then Install Update
#   scripts/test-update.sh --auto   # Sparkle checks on launch and installs when the app quits
#
# Both copies get their own bundle ID, so Sparkle's state stays out of Redlamp's preferences, and
# the dry run's Developer ID. sign_update uses the release key, so the keychain may ask to let it.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/build/release/Redlamp.app"
ID="app.redlamp.mac.update-test"
PORT=8742
AUTO=0
[ "${1:-}" != "--auto" ] || AUTO=1

fail() {
    echo "error: $*" >&2
    exit 1
}

[ -d "$SOURCE" ] || fail "no dry run at $SOURCE; run REF=HEAD DRY_RUN=1 mise run release first"
TEAM="$(codesign -dv "$SOURCE" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
IDENTITY="$(security find-identity -v -p codesigning \
    | awk -v team="($TEAM)\"" '/"Developer ID Application:/ && index($0, team) { print $2; exit }')"
[ -n "$IDENTITY" ] || fail "no Developer ID Application identity for team $TEAM in the keychain"

# The resolved path (/private/var/…), which is how the running app is known to LaunchServices.
WORK="$(cd "$(mktemp -d)" && pwd -P)"
OLD="$WORK/old/Redlamp.app"
SERVER=""

# By process: both copies have the test bundle ID, and an app named by ID or path resolves to the
# newer one, which isn't running.
quit_old() {
    local pid
    pid="$(pgrep -f "$OLD/Contents/MacOS/Redlamp")" || return 0
    osascript -l JavaScript \
        -e "ObjC.import('AppKit'); \$.NSRunningApplication.runningApplicationWithProcessIdentifier($pid).terminate"
}

cleanup() {
    [ -z "$SERVER" ] || { kill "$SERVER" && wait "$SERVER"; } 2>/dev/null || true
    ! pgrep -f "$OLD/Contents/MacOS/Redlamp" >/dev/null || quit_old >/dev/null 2>&1 || true
    for _ in $(seq 30); do
        pgrep -f "Autoupdate $ID" >/dev/null || break
        sleep 1
    done
    pkill -f "$(basename "$WORK")/" 2>/dev/null || true
    defaults delete "$ID" >/dev/null 2>&1 || true
    rm -rf "$WORK" "$HOME/Library/Caches/$ID" "$HOME/Library/HTTPStorages/$ID" \
        "$HOME/Library/Saved Application State/$ID.savedState"
}
trap cleanup EXIT

# A copy of the dry run under the test bundle ID, with the given build number, checking the local
# feed. Only the outer signature changes; nothing inside the bundle is touched.
copy() {
    local app="$WORK/$1/Redlamp.app"
    mkdir -p "$WORK/$1"
    ditto "$SOURCE" "$app"
    plutil -replace CFBundleIdentifier -string "$ID" "$app/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$2" "$app/Contents/Info.plist"
    plutil -replace SUFeedURL -string "http://127.0.0.1:$PORT/appcast.xml" "$app/Contents/Info.plist"
    codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$app"
}

build_of() {
    plutil -extract CFBundleVersion raw "$1/Contents/Info.plist"
}

# The update unpacked where Sparkle's installer checks it, its signature checking out (so every
# file is in place), and the installer idle for 2 s, waiting for the app to quit.
ready() {
    local pid app before
    pid="$(pgrep -n -f "Autoupdate $ID")" || return 1
    for app in "$HOME/Library/Caches/$ID/org.sparkle-project.Sparkle/Installation"/*/*/Redlamp.app; do
        [ -d "$app" ] && codesign --verify --deep --strict "$app" 2>/dev/null || continue
        before="$(ps -o time= -p "$pid")" || return 1
        sleep 2
        [ "$(ps -o time= -p "$pid")" = "$before" ]
        return
    done
    return 1
}

# What Sparkle's processes in this test logged as errors, where the log can be read.
sparkle_errors() {
    local ours="(processImagePath BEGINSWITH \"$WORK/\" OR processImagePath CONTAINS \"/Caches/$ID/\")"
    /usr/bin/log show --last 15m --style compact \
        --predicate "subsystem == \"org.sparkle-project.Sparkle\" AND messageType == error AND $ours" 2>/dev/null \
        | sed -n 's/^.*\[org\.sparkle-project\.Sparkle:Sparkle\] /Sparkle: /p' | tail -5 >&2 || true
}

NEW_BUILD="$(build_of "$SOURCE")"
copy new "$NEW_BUILD"
copy old 1

mkdir -p "$WORK/feed"
ditto -c -k --keepParent "$WORK/new/Redlamp.app" "$WORK/feed/Redlamp.zip"
echo "- An update served from 127.0.0.1 by scripts/test-update.sh." >"$WORK/notes.md"
"$ROOT/scripts/appcast.sh" "$WORK/new/Redlamp.app" "$WORK/feed/Redlamp.zip" \
    "http://127.0.0.1:$PORT/Redlamp.zip" "$WORK/notes.md" >"$WORK/feed/appcast.xml"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$WORK/feed" >/dev/null 2>&1 &
SERVER=$!

if [ "$AUTO" = 1 ]; then
    # Sparkle's second-launch question, answered: check now, and install when the app quits.
    defaults write "$ID" SUHasLaunchedBefore -bool YES
    defaults write "$ID" SUEnableAutomaticChecks -bool YES
    defaults write "$ID" SUAutomaticallyUpdate -bool YES
    open -n "$OLD"
    echo "==> Opened build 1; waiting for Sparkle to download build $NEW_BUILD and stage it..."
    # Sparkle's installer takes the app's bundle ID as its first argument; other apps run their own.
    for _ in $(seq 90); do
        pgrep -f "Autoupdate $ID" >/dev/null && break
        sleep 2
    done
    pgrep -f "Autoupdate $ID" >/dev/null || fail "Sparkle didn't stage the update (see Console, subsystem org.sparkle-project.Sparkle)"
    # The installer starts before it has unpacked and checked the update, and Sparkle drops the
    # update if the app quits before then; it logs nothing once it's ready.
    for _ in $(seq 60); do
        ready && break
        sleep 1
    done
    ready || { sparkle_errors; fail "Sparkle's installer wasn't ready to install build $NEW_BUILD"; }
    quit_old
else
    open -n "$OLD"
    echo "==> Opened build 1. Choose Redlamp > Check for Updates…, then Install Update."
fi

echo "==> Waiting for build $NEW_BUILD to replace it..."
for _ in $(seq 150); do
    [ "$(build_of "$OLD")" = "$NEW_BUILD" ] && break
    sleep 2
done
[ "$(build_of "$OLD")" = "$NEW_BUILD" ] || { sparkle_errors; fail "the old copy is still build $(build_of "$OLD")"; }
codesign --verify --deep --strict "$OLD"
echo "==> Updated build 1 to build $NEW_BUILD, and its signature checks out."
