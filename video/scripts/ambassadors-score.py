#!/usr/bin/env python3
"""
The ambassadors reel's score (src/ambassadors/AmbassadorsReel.tsx): its track (scripts/ambassadors/music.py) with
the reel's sounds on the frames their pictures land on. The sounds come from the reel's board
(scripts/ambassadors/reel.py, sounds()), which times them on the reel's cue sheet as it times the picture; the
feature videos' clicks, ticks and landings are scripts/features-score.py's, and the reel's own are here.

    python3 scripts/ambassadors-score.py      # public/ambassadors/score.wav, score.json and cues.json

Beside score.wav it writes score.json, the score's level at every frame for the storyboard sheet, and cues.json,
the cue sheet with the chords and every sound on screen added as a cue, for scripts/score-report.py. The reel has
no opener, so the whole video's sound is the score, mastered to the platforms' −14 LUFS with its true peak at or
under −1 dBFS. Needs numpy, Pillow and pixelkit (the board draws with it), and the samples' folder (synth.SAMPLES).
"""

import importlib.util
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import synth as s  # noqa: E402
from features import world as w  # noqa: E402


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


music = load(HERE / "ambassadors/music.py", "ambassadors_music")
reel = load(HERE / "ambassadors/reel.py", "ambassadors_reel")
features = load(HERE / "features-score.py", "features_score")


def rising(velocity):
    """Air rushing up with the lamp's light as it shrinks into the header's mark, in the half beat it takes."""
    return s.whoosh(0.3, 500, 4200) * velocity


def lifting(velocity):
    """A soft two-note rise as the picked row lifts out of the roadmap: F, then C a sixteenth later."""
    late = int(round(music.BEAT / 4 * s.SR))
    first, second = s.blip(89, velocity, 0.07, duty=0.5), s.blip(96, velocity * 0.8, 0.12, duty=0.5)
    out = np.zeros(late + len(second))
    out[: len(first)] += first
    out[late:] += second
    return out


def shutter(velocity):
    """A camera's shutter: the curtain opening and closing 30 ms apart, two short mechanical clacks."""
    t = s.times(0.09)
    out = np.zeros(len(t))
    for start, centre, level in ((0.0, 2400, 1.0), (0.03, 3600, 0.75)):
        n = int(start * s.SR)
        burst = s.bandpass(s.rng.standard_normal(len(t) - n), centre, octaves=1.2) * np.exp(-t[: len(t) - n] / 0.006)
        out[n:] += burst * level
    return out * velocity


def squeak(velocity):
    """A marker drawn round a frame on paper: a rubbing hiss with a faint pitch that wavers, over a quarter beat."""
    t = s.times(music.BEAT / 4 + 0.05)
    pitch = 1500 + 300 * np.sin(2 * np.pi * 7 * t)
    tone = np.sin(2 * np.pi * np.cumsum(pitch) / s.SR) * 0.35
    rub = s.bandpass(s.rng.standard_normal(len(t)), 2600, octaves=1.5)
    envelope = np.clip(t / 0.01, 0, 1) * np.clip((t[-1] - t) / 0.04, 0, 1)
    return (tone + rub) * envelope * velocity


def switch(velocity):
    """The lamp's switch: a low clack with a short thump under it."""
    t = s.times(0.12)
    thump = np.sin(2 * np.pi * np.cumsum(140 + 90 * np.exp(-t / 0.01)) / s.SR) * np.exp(-t / 0.04)
    clack = s.bandpass(s.rng.standard_normal(len(t)), 1800, octaves=1.0) * np.exp(-t / 0.005)
    return (0.7 * thump + clack) * velocity


def washing(velocity):
    """Developer washing over the print as it comes up: soft water noise that rises and settles over the beat."""
    t = s.times(music.BEAT * 1.2)
    noise = s.lowpass(s.bandpass(s.rng.standard_normal(len(t)), 900, octaves=2.0), 3000)
    envelope = np.sin(np.pi * np.clip(t / (music.BEAT * 1.2), 0, 1)) ** 1.5
    return noise * envelope * velocity


SOUNDS = {
    **features.SOUNDS,
    "rise": (lambda: rising(0.8), 0.28, 0.3),
    "lift": (lambda: lifting(0.7), 0.24, 0.2),
    "shutter": (lambda: shutter(0.8), 0.26, 0.1),
    "marker": (lambda: squeak(0.7), 0.16, 0.1),
    "switch": (lambda: switch(0.9), 0.3, 0.1),
    "wash": (lambda: washing(0.7), 0.12, 0.3),
}


def on_screen(events):
    """Puts the reel's sounds, (beat, kind, pan), on the track's effects bus."""

    def sounds(fx):
        for beat, kind, pan in events:
            sound, gain, wet = SOUNDS[kind]
            fx.add(music.at(beat), sound(), gain=gain, pan_to=pan, wet=wet)

    return sounds


def main():
    events = reel.sounds()
    unknown = sorted({kind for _, kind, _ in events} - set(SOUNDS))
    if unknown:
        sys.exit(f"the reel has sounds this script can't play: {', '.join(unknown)}")
    out = w.VIDEO / "public/ambassadors"
    out.mkdir(parents=True, exist_ok=True)
    name, arrange = next(iter(music.ARRANGEMENTS.items()))
    buses, mastering = arrange(sounds=on_screen(events))
    mix = s.master(buses, seconds=music.TOTAL, target=features.TARGET, ceiling=features.CEILING, fade=1.2, **mastering)
    s.write(out / "score.wav", mix)

    per = s.SR // reel.FPS
    frames = len(mix) // per
    rms = np.sqrt((mix[: frames * per] ** 2).mean(axis=1).reshape(frames, per).mean(axis=1))
    (out / "score.json").write_text(json.dumps({"fps": reel.FPS, "arrangement": name,
                                                "level": [round(float(x), 4) for x in rms / rms.max()]}))
    counts, cues = {}, dict(reel.CUE)
    for beat, kind, _ in events:
        counts[kind] = counts.get(kind, 0) + 1
        cues[f"{kind.replace(' ', '-')}-{counts[kind]}"] = beat
    (out / "cues.json").write_text(json.dumps({**reel.SHEET, "chords": music.CHORDS, "cues": cues}, indent=1))
    print(f"==> public/ambassadors/score.wav ({name}, {music.TOTAL:.1f} s, {s.loudness(mix):.1f} LUFS, "
          f"true peak {s.true_peak(mix):.1f} dBFS, {len(events)} sounds on screen)")


if __name__ == "__main__":
    main()
