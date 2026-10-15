#!/usr/bin/env python3
"""ViTMatte with some or all of its 8-bit weights back in float16, for the GPU on macOS 27 (MSK-33).

There Metal Performance Shaders Graph at times aborts as it specialises the shipped model
(compress_vitmatte.py's ViTMatteBaseW8) for the GPU: rewriting a global-attention matmul whose
right-hand operand is an 8-bit constant, it rebuilds the matmul with another constant's shape. This
writes two models from the shipped package, each with the weights compress_vitmatte.py quantised, so
their mattes stay those of the shipped model:

- ViTMatteBaseFP16: every weight decompressed (coremltools' decompress_weights).
- ViTMatteBaseW8RelPos16: only the 24 relative-position tables matmul takes as a constant (global
  and windowed attention's, two a block) decompressed; the rest stays 8-bit.

    research/prototypes/masking/.venv-coreml/bin/python research/prototypes/masking/decompress_vitmatte.py

Writes them to build/models/; vitmatte_gpu_probe.py counts their aborts on the build Mac. Every abort
on 15 October 2026 (28 of the shipped model's 1,296 trials) swapped these tables between windowed and
global attention; neither model aborted (RelPos16 in 850 trials, FP16 in 1,530). RelPos16 is 111.1 MB
against the shipped 108.8 MB, FP16 204.1 MB. On the GPU both give the shipped model's Subject and People
masks bit for bit on the fixtures, on macOS 26 (M1 Ultra) and macOS 27 (M4 Max), as fast (People
masks 2.5 to 3.8 s on the M4 Max, against 5.2 to 8.2 s on its CPU), and pass MatteQualityTests'
strands (recall 0.656 on macOS 27, the shipped model's 0.661, against 0.6).
"""

import pathlib

import coremltools as ct
from coremltools.models import utils as model_utils
from coremltools.optimize.coreml._quantization_passes import WeightDecompressor

SOURCE = pathlib.Path.home() / "Library/Application Support/Redlamp/Models/vitmatte-base/1/ViTMatteBaseW8.mlpackage"
MODELS = pathlib.Path(__file__).resolve().parents[3] / "build/models"


def feeds_matmul(op):
    return any(child.op_type == "matmul" for output in op.outputs for child in output.child_ops)


def main():
    MODELS.mkdir(parents=True, exist_ok=True)
    for name, selector in (("ViTMatteBaseFP16", lambda op: True), ("ViTMatteBaseW8RelPos16", feeds_matmul)):
        chosen = []

        def counted(op, selector=selector, chosen=chosen):
            picked = selector(op)
            if picked:
                chosen.append(op.outputs[0].name)
            return picked
        model = model_utils._apply_graph_pass(ct.models.MLModel(str(SOURCE), skip_model_load=True),
                                              WeightDecompressor(op_selector=counted))
        destination = MODELS / f"{name}.mlpackage"
        model.save(str(destination))
        size = sum(path.stat().st_size for path in destination.rglob("*") if path.is_file())
        print(f"{name}: {len(chosen)} constants decompressed, {size / 1e6:.1f} MB: {destination}")


if __name__ == "__main__":
    main()
