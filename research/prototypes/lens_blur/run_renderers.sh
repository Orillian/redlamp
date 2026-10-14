#!/bin/sh
# Renders and scores every renderer configuration, in three chains that can run side by side:
#   for c in gather layers clipped; do
#       nohup research/prototypes/lens_blur/run_renderers.sh $c > build/proto-out/lens_blur/logs/$c.log 2>&1 &
#   done
# and the gather on estimated depth: depth_moge2_l, depth_moge2_b and depth_mono_l.
# Each step's log lines carry uptime before and after it.
cd "$(dirname "$0")" || exit 1
PY="../../../build/research-venv/bin/python -u"
mkdir -p ../../../build/proto-out/lens_blur/logs

step() {
    echo "== $* :: $(uptime)"
    /usr/bin/time -p "$@" 2>&1 | grep --line-buffered -v -e Warning -e warnings.warn -e "^layered/" -e "^blender/"
    echo "== done :: $(uptime)"
}

gather() {
    step $PY render_gather.py
    step $PY score.py gather
    step $PY render_gather.py --sprites
    step $PY score.py gather-sprites
}

layers() {
    for mode in plain fill oracle; do
        step $PY render_layers.py --mode $mode
        step $PY score.py layers-$mode
    done
    step $PY render_layers.py --mode fill --sprites
    step $PY score.py layers-fill-sprites
}

sprites() {
    step $PY render_gather.py --sprites
    step $PY score.py gather-sprites
    step $PY render_gather.py --clipped --sprites --set layered
    step $PY score.py gather-sprites-clipped --set layered
}

matte() {
    step $PY render_gather.py --matte exact
    step $PY score.py gather-matte-exact
    step $PY render_gather.py --matte coarse
    step $PY score.py gather-matte-coarse
    step $PY render_layers.py --mode oracle --matte coarse
    step $PY score.py layers-oracle-coarse
}

# The depth bake-off's leading estimates under the gather, one chain per source: its bilinear base
# (which the two layers are built on), its leading refinement, its two layers with ViTMatte and with
# the true alpha, and the leading refinement with the coarse matte snapped in the renderer.
estimated() {
    lead=$1
    shift
    for label in "$@"; do
        step $PY render_gather.py --depth "$label" --circles
        step $PY score.py "gather@$label"
    done
    step $PY render_gather.py --depth "$lead" --matte coarse --circles
    step $PY score.py "gather-matte-coarse@$lead"
}

depth_moge2_l() {
    estimated moge2-l@2x+wmf moge2-l@2x+none moge2-l@2x+wmf moge2-l@2x+layers-vitmatte moge2-l@2x+layers-oracle
}

depth_moge2_b() {
    estimated moge2-b@2x+wmf moge2-b@2x+none moge2-b@2x+wmf moge2-b@2x+layers-vitmatte moge2-b@2x+layers-oracle
}

depth_mono_l() {
    estimated da3-mono-l@app+app da3-mono-l@app+none da3-mono-l@app+app da3-mono-l@app+layers-vitmatte da3-mono-l@app+layers-oracle
}

clipped() {
    step $PY render_gather.py --clipped --set layered
    step $PY score.py gather-clipped --set layered
    step $PY render_gather.py --clipped --sprites --set layered
    step $PY score.py gather-sprites-clipped --set layered
    step $PY render_layers.py --mode fill --clipped --set layered
    step $PY score.py layers-fill-clipped --set layered
    step $PY render_layers.py --mode fill --clipped --sprites --set layered
    step $PY score.py layers-fill-sprites-clipped --set layered
}

"$1"
