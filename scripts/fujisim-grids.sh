#!/usr/bin/env bash
# Contact sheets of the Sony raws: Redlamp Color, Fujifilm's LUT (the import's defaults) and the
# firmware model, per simulation; the simulations only the model has; Camera Recipes both ways.
set -euo pipefail
cd "$(dirname "$0")/.."
R=build/DerivedData-fujisim/Build/Products/Debug/redlamp
OUT=build/fujisim/sheets
LUTS=build/fujisim/luts
mkdir -p "$OUT"
IMAGES=(~/src/redlamp-social/photos/*.ARW)
export REDLAMP_FIRMWARE_MODEL=1

pairs=(
  "PROVIA:standard" "Velvia:vivid-slide" "ASTIA:soft-slide" "CLASSIC-CHROME:chrome"
  "CLASSIC-Neg-:negative-classic" "REALA-ACE:reala-ace" "PRO-Neg-Std:negative-standard"
  "ETERNA:cinema" "ETERNA-BB:bleach" "ACROS:acros"
)
for pair in "${pairs[@]}"; do
  lut=${pair%%:*}
  sim=${pair##*:}
  "$R" recipe contact-sheet --original --tile 300 \
    --recipes "$LUTS/FLog2_to_${lut}_65grid_V-1-00.redrecipe,local/firmware-model/$sim" \
    -o "$OUT/$sim.jpg" --images "${IMAGES[@]}"
done

"$R" recipe contact-sheet --tile 300 \
  --recipes "local/firmware-model/negative-nostalgic,local/firmware-model/negative-high,local/firmware-model/monochrome,local/firmware-model/monochrome-yellow,local/firmware-model/monochrome-red,local/firmware-model/monochrome-green,local/firmware-model/acros-yellow,local/firmware-model/acros-red,local/firmware-model/acros-green,local/firmware-model/sepia" \
  -o "$OUT/firmware-only.jpg" --images "${IMAGES[@]}"

"$R" recipe contact-sheet --tile 300 --recipes "group:Camera Recipes" -o "$OUT/camera-recipes-firmware.jpg" \
  --images "${IMAGES[@]}"
REDLAMP_FIRMWARE_MODEL= "$R" recipe contact-sheet --tile 300 --recipes "group:Camera Recipes" \
  -o "$OUT/camera-recipes-redlamp.jpg" --images "${IMAGES[@]}"
