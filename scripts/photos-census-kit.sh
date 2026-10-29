#!/usr/bin/env bash
#
# The census of the owner's Photos library (LIB-57) as a kit for the Mac that has the library, and its report read
# back here.
#
#   scripts/photos-census-kit.sh [--app <Redlamp.app>] [output directory (build/photos-census-kit)]
#     Builds a kit from the current commit: the app as `scripts/build-mac.py app` builds it (Debug, where
#     --photos-census runs the census in the editor's place), or the one --app names, as "Redlamp Photos
#     Census.app" under its own bundle ID, its Photos usage text the census's, signed again for that ID; with
#     run.sh (scripts/photos-census-kit/run.sh) and a README, zipped to send by AirDrop. On that Mac,
#     `bash run.sh` in Terminal takes the first step, and `bash run.sh recovered`, `offline` and `week` the others.
#   scripts/photos-census-kit.sh read <census.json>
#     Checks that the report holds nothing like an identifier, and prints its text.
#
# The working tree must be clean (ALLOW_DIRTY=1 builds it anyway), since the kit names a commit.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "${1:-}" == "read" ]]; then
    REPORT="${2:?usage: scripts/photos-census-kit.sh read <census.json>}"
    exec python3 - "$REPORT" <<'PY'
import json, pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
report = json.loads(text)
if report.get("format") != "app.redlamp.photokit-census":
    sys.exit(f"{path} isn't a census report")
if re.search(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-", text):
    sys.exit(f"{path} holds something like an identifier: don't record it")
steps = ", ".join(f"{step} {when}" for step, when in sorted(report.get("ran", {}).items()))
print(f"{path}: census report version {report.get('version')}, steps {steps or 'none'}")
lines = path.with_suffix(".txt")
if lines.exists():
    print(lines.read_text(), end="")
PY
fi

APP_SOURCE=""
if [[ "${1:-}" == "--app" ]]; then
    APP_SOURCE="${2:?usage: scripts/photos-census-kit.sh [--app <Redlamp.app>] [output directory]}"
    shift 2
fi
OUT="${1:-$ROOT/build/photos-census-kit}"
BUNDLE_ID=app.redlamp.mac.census
COMMIT="$(git rev-parse --short HEAD)"
if [[ -n "$(git status --porcelain --untracked-files=no)" && "${ALLOW_DIRTY:-0}" != "1" ]]; then
    echo "uncommitted changes: the kit would name $COMMIT without them (ALLOW_DIRTY=1 to build anyway)" >&2
    exit 2
fi

if [[ -z "$APP_SOURCE" ]]; then
    BUILT="$(scripts/build-mac.py app 2>&1 | tee /dev/stderr)"
    APP_SOURCE="$(sed -n 's/^==> The app is in \(.*Redlamp\.app\)$/\1/p' <<<"$BUILT" | tail -1)"
fi
[[ -d "$APP_SOURCE/Contents/MacOS" ]] || { echo "no app at '$APP_SOURCE'" >&2; exit 2; }

NAME="redlamp-photos-census-$COMMIT"
KIT="$OUT/$NAME"
APP="$KIT/Redlamp Photos Census.app"
rm -rf "$KIT" "$KIT.zip"
mkdir -p "$KIT/results"
ditto "$APP_SOURCE" "$APP"
# Its own name and ID, so an installed Redlamp's settings and access to Photos are never its; no update feed.
PLIST="$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST"
plutil -replace CFBundleName -string "Redlamp Photos Census" "$PLIST"
plutil -replace CFBundleDisplayName -string "Redlamp Photos Census" "$PLIST"
plutil -replace SUFeedURL -string "" "$PLIST"
plutil -replace RedlampCommit -string "$COMMIT" "$PLIST"
plutil -replace NSPhotoLibraryUsageDescription -string "Redlamp's census reads your Photos library to measure what \
Photos keeps on this Mac. It never changes your Photos library, and its report names no photo." "$PLIST"
IDENTITY="${REDLAMP_SIGN_IDENTITY:-$(codesign -dvv "$APP_SOURCE" 2>&1 | sed -n 's/^Authority=//p' | head -1)}"
# Not the build's requirements: they name app.redlamp.mac, so the copy wouldn't meet its own.
codesign --force --sign "${IDENTITY:--}" --preserve-metadata=entitlements,flags --timestamp=none "$APP"
codesign --verify --strict "$APP"

cp scripts/photos-census-kit/run.sh "$KIT/run.sh"
chmod +x "$KIT/run.sh"
python3 - "$KIT/kit.json" "$COMMIT" "$BUNDLE_ID" <<'PY'
import datetime, json, subprocess, sys
path, commit, bundle = sys.argv[1:]
subject = subprocess.run(["git", "log", "-1", "--format=%s", commit], capture_output=True, text=True).stdout.strip()
json.dump({"commit": commit, "subject": subject, "bundleID": bundle,
           "built": datetime.datetime.now().astimezone().isoformat(timespec="seconds")}, open(path, "w"), indent=2)
PY
cat >"$KIT/README.txt" <<EOF
Redlamp's census of this Mac's Photos library (LIB-57), built from $COMMIT.

It measures, through Redlamp's own code, what Apple doesn't document about Photos under Optimize Mac Storage, and
writes a report of counts, sizes, times and answers. The report names no photo, album, place or person, and holds no
identifier. It never changes your Photos library; it downloads at most 10 originals from iCloud, which Photos may
keep. It opens no Redlamp library, so a Redlamp installed here is left alone.

In Terminal:
    cd ~/Downloads/$NAME

1.  bash run.sh
    About 15 minutes; the first time, macOS may take a few minutes to check the app before it starts. Allow
    "Redlamp Photos Census" to access Photos when macOS asks, then leave the Mac alone, plugged in and on Wi-Fi,
    while it downloads.
2.  In Photos, delete one photo, open Recently Deleted and Recover it. Then:
        bash run.sh recovered
3.  Turn Wi-Fi off and unplug Ethernet. Then:
        bash run.sh offline
    and turn Wi-Fi back on.
4.  AirDrop results/census.json back.
5.  A week after step 1:
        bash run.sh week
    then AirDrop results/census.json back again. This step deletes what the census kept on this Mac.

Until step 5, ~/Library/Application Support/Redlamp Photos Census/State keeps what the later steps need: the
identifiers of the photos measured, Photos' change token and an index of the Library. None of it leaves this Mac.
EOF

ditto -c -k --keepParent "$KIT" "$KIT.zip"
echo "made $KIT ($(du -sh "$KIT" | cut -f1)), zipped as $KIT.zip ($(du -sh "$KIT.zip" | cut -f1))"
