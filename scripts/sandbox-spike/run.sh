#!/bin/bash
# ARC-17's sandbox spike: what the App Sandbox allows Redlamp, tried on this Mac. Builds a small app
# twice from Spike.swift, sandboxed and not, signed with one Apple Development identity under one
# bundle ID, and opens it with Launch Services, which grants it the documents it's given. Results:
# docs/research/notes/ARC-17-app-sandbox.md.
#
#   scripts/sandbox-spike/run.sh        the study's run: the container's migration, related items,
#                                       a bookmark used again, bookmarks minted unsandboxed, volumes
#   scripts/sandbox-spike/run.sh mint   bookmarks minted unsandboxed, kept for `use`
#   scripts/sandbox-spike/run.sh use    those bookmarks resolved sandboxed, as after a restart
#
# Each run has a bundle ID of its own, so its first sandboxed launch makes a new container and runs
# the migration. What a run keeps is removed at its end; its empty container stays in
# ~/Library/Containers. The volumes step mounts and ejects a small disk image named SPIKECARD.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mode="${1:-all}"
identity="${SPIKE_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)}"
work="$HOME/Library/Caches/redlamp-sandbox-spike"
[ "$mode" = use ] && [ -f "$work/run-id" ] && run="$(cat "$work/run-id")" || run="$(date +%Y%m%d%H%M%S)"
id="app.redlamp.sandbox-spike.r$run"
[ -n "$identity" ] || { echo "No Apple Development signing identity in the keychain." >&2; exit 1; }

build() {
    mkdir -p "$work"
    xcrun swiftc -O -swift-version 6 -o "$work/SandboxSpike" "$here/Spike.swift" -framework AppKit -framework CoreServices
    cat > "$work/container-migration.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Move</key><array>
<string>\${ApplicationSupport}/SandboxSpike</string><string>\${Caches}/$id</string>
</array></dict></plist>
EOF
    for variant in Sandboxed Plain; do
        local app="$work/$variant/SandboxSpike.app"
        rm -rf "$work/$variant"
        mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
        cp "$work/SandboxSpike" "$app/Contents/MacOS/"
        cp "$here/Info.plist" "$app/Contents/"
        plutil -replace CFBundleIdentifier -string "$id" "$app/Contents/Info.plist"
        cp "$work/container-migration.plist" "$app/Contents/Resources/"
        if [ "$variant" = Sandboxed ]; then
            codesign --force --timestamp=none --sign "$identity" --entitlements "$here/sandboxed.entitlements" "$app"
        else
            codesign --force --timestamp=none --sign "$identity" "$app"
        fi
    done
    rm -rf "$work/data"
    mkdir -p "$work/data/photos" "$work/data/folderF/sub" "$work/data/folderG"
    for photo in A B C D E; do printf 'not a raw' > "$work/data/photos/$photo.ARW"; done
    mkdir "$work/data/photos/D.ARW.redlamp"
    printf '{"existing":1}' > "$work/data/photos/D.ARW.redlamp/edit.json"
    printf '<x:xmpmeta xmlns:x="adobe:ns:meta/"/>' > "$work/data/photos/D.ARW.xmp"
    printf '<x:xmpmeta xmlns:x="adobe:ns:meta/"/>' > "$work/data/photos/D.xmp"
    printf 'f' > "$work/data/folderF/file.txt"
    printf 's' > "$work/data/folderF/sub/inside.txt"
    printf 'g' > "$work/data/folderG/file.txt"
    echo "$run" > "$work/run-id"
}

# Opens the spike with `out-<step>` and the other documents given, and prints its log.
step() {
    local variant="$1" name="$2"
    shift 2
    local out="$work/data/out-$name"
    mkdir -p "$out"
    [ -n "${MINTED:-}" ] && cp "$MINTED" "$out/minted.txt"
    open -W -n -a "$work/$variant/SandboxSpike.app" "$out" "$@"
    cat "$out/log.txt"
}

lsregister=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
cleanup() {
    step Sandboxed cleanup
    for variant in Sandboxed Plain; do "$lsregister" -u "$work/$variant/SandboxSpike.app" 2>/dev/null || true; done
}

case "$mode" in
all)
    build
    d="$work/data"
    step Plain seed
    step Plain mint
    step Sandboxed report
    echo "Outside the container after the first sandboxed launch:"
    ls "$HOME/Library/Application Support/SandboxSpike" 2>&1 || true
    step Sandboxed docs "$d/photos/A.ARW" "$d/photos/B.ARW" "$d/photos/C.ARW" "$d/photos/D.ARW" "$d/photos/E.ARW" "$d/folderF"
    step Sandboxed resolve
    for kind in scoped readonly plain; do
        grep "^$kind=" "$d/out-mint/minted.txt" > "$work/minted-$kind.txt"
        MINTED="$work/minted-$kind.txt" step Sandboxed "useminted-$kind"
    done
    rm -rf "$work/card" && mkdir -p "$work/card/DCIM/100TEST" && printf 'jpeg' > "$work/card/DCIM/100TEST/IMG_0001.JPG"
    hdiutil create -quiet -srcfolder "$work/card" -volname SPIKECARD -fs APFS -ov "$work/card.dmg"
    (sleep 5 && hdiutil attach -quiet -noautoopen "$work/card.dmg") &
    step Sandboxed volumes
    hdiutil detach -quiet /Volumes/SPIKECARD || true
    cleanup
    ;;
mint)
    build
    step Plain mint
    echo "Restart the Mac when you like, then run: scripts/sandbox-spike/run.sh use"
    ;;
use)
    for kind in scoped readonly plain; do
        grep "^$kind=" "$work/data/out-mint/minted.txt" > "$work/minted-$kind.txt"
        MINTED="$work/minted-$kind.txt" step Sandboxed "useminted-$kind"
    done
    cleanup
    ;;
*)
    echo "usage: run.sh [all | mint | use]" >&2
    exit 2
    ;;
esac
