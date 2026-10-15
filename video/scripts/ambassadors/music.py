"""
The ambassadors reel's track (src/ambassadors/AmbassadorsReel.tsx): dark synthwave in F minor at 100 BPM, 8 bars
and 19.2 seconds on the reel's cue sheet, src/ambassadors/cues.json, which scripts/ambassadors-score.py plays
under the reel with its sounds on screen. It is E12's darksynth (scripts/features/music/e12.py) carried to F minor
and to the reel's four acts, which have no opener before them.

- Act 1, the hook: the lead-in, from a deep hit on the first frame, with a drone, a pad swelling with the lamp, a
  kick muffled as if through a wall, and the arpeggio growing out of nothing from the third beat, the first hit's
  own reverb swelling up into it.
- Act 2, why it matters: the first hit lands as the roadmap comes in, with the bass and the arpeggio, in half
  time; the full beat and the riff come in with the print, the series' glass sting on its develop.
- Act 3, why Redlamp needs you: a breakdown under the one person who makes it, the music thinning to the drone, a
  muffled kick and the riff's first notes, a riser and a snare roll doubling into the stop; then the drop, the
  loudest bar, as the roll fills with photographers.
- Act 4, how to apply: the groove holds under the editor, where the closing phrase begins; it sits on the dominant
  under the address and lands on the tonic on the last hit; the last chord dies away as the picture fades.

The chords: Fm6/9 under the hook, Abmaj7#11 under the roadmap, Ebmaj9 and Dbmaj7#11 under the print; Dbmaj7#11
through the breakdown, then Dm7(b5) and C7(b9) into the drop on Fm9; Dbmaj7#11 and Ebmaj9 under the editor, C7(b9)
under the address, and Fm9 on the last hit. The voicings are E12's a fourth up, rootless between G3 and G4.

The riff is F minor's: G, E flat and G, up to A flat and down to F, held, with the print; its first three notes alone
in the breakdown; on the drop C, A flat and C up to E flat, then C held; the closing phrase turns to A flat, F and E
under the address, and lands on F on the last hit.

The samples are from Sonic Pi's pack (CC0), in the samples' folder outside the repository (synth.SAMPLES), as
E12's are.
"""

import importlib.util
import json
from pathlib import Path

import numpy as np

import synth as s

SCRIPTS = Path(__file__).resolve().parents[1]


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


theme = load(SCRIPTS / "features-theme.py", "features_theme")
opening, dying, trim, start, chord_at = theme.opening, theme.dying, theme.trim, theme.start, theme.chord_at

SHEET = json.loads((SCRIPTS.parent / "src/ambassadors/cues.json").read_text())
cue = SHEET["cues"]
BEAT = 60 / SHEET["bpm"]
BEATS = SHEET["bars"] * SHEET["beatsPerBar"]
TOTAL = BEATS * BEAT
LENGTH = TOTAL + 4
FIRST, FULL, BREAK, ROLL = cue["roadmap"], cue["print"], cue["onePerson"], cue["roll"]
STOP, DROP, END, CTA, LAST = cue["stop"], cue["drop"], cue["editor"], cue["cta"], cue["lastHit"]


def at(beat):
    return beat * BEAT


# How fully the track plays from each cue: held back under the hook, growing through act 2, thin through the
# breakdown, full on the drop, then easing a little for act 4 and the last chord.
SWELL = [(0, 0.72), (FIRST, 0.8), (FULL, 0.9), (BREAK, 0.7), (DROP, 1.0), (END, 0.95), (LAST, 0.85)]


def swell(beat):
    return [level for first, level in SWELL if first <= beat][-1]


def grooving(beat):
    """Whether the beat plays at `beat`: everywhere from the first hit but the breakdown and the stop."""
    return FIRST <= beat < LAST and not BREAK <= beat < DROP


def playing(first, last, step):
    """Beats from `first` up to `last`, every `step`, leaving out the breakdown and the stop."""
    return [b for b in np.arange(first, last - 1e-9, step) if not BREAK <= b < DROP]


CHORDS = [("Fm6/9", 0, 4), ("Abmaj7#11", 4, 4), ("Ebmaj9", 8, 2), ("Dbmaj7#11", 10, 2), ("Dbmaj7#11", 12, 2),
          ("Dm7(b5)", 14, 1), ("C7(b9)", 15, 1), ("Fm9", 16, 4), ("Dbmaj7#11", 20, 2), ("Ebmaj9", 22, 2),
          ("C7(b9)", 24, 4), ("Fm9", 28, 4)]

VOICINGS = {
    "Fm6/9": (41, [56, 60, 62, 67]),
    "Abmaj7#11": (44, [55, 60, 62, 67]),
    "Ebmaj9": (39, [55, 58, 62, 65]),
    "Dm7(b5)": (38, [56, 60, 62, 65]),
    "C7(b9)": (36, [55, 58, 61, 64]),
    "Fm9": (41, [56, 60, 63, 67]),
    "Dbmaj7#11": (37, [55, 60, 61, 65]),
}


def chord(beat):
    root, voicing = VOICINGS[chord_at(beat, CHORDS)]
    return root, voicing, [n + 12 for n in voicing]


def placed(first, part, level=1.0):
    return [(first + beat, note, beats, level) for beat, note, beats in part]


# The riff, [beat, note, beats] from where each phrase starts.
CALL = [(0, 67, 0.75), (0.75, 63, 0.25), (1, 67, 0.5), (1.5, 68, 0.5), (2, 65, 1.5), (3.5, 63, 0.5)]
HEAD = [(0, 72, 0.75), (0.75, 68, 0.25), (1, 72, 0.5), (1.5, 75, 0.5), (2, 72, 1.5), (3.5, 68, 0.5)]
CLOSE = [(0, 68, 0.75), (0.75, 65, 0.25), (1, 68, 0.5), (1.5, 72, 0.5), (2, 68, 1.0), (3, 65, 1.0), (4, 64, 2.0),
         (6, 67, 1.0), (7, 73, 1.0), (8, 65, 4.0)]
TUNE = placed(FULL, CALL) + placed(BREAK, CALL[:3], 0.6) + placed(DROP, HEAD) + placed(END, CLOSE)

ARP, ECHO = 0.24, 0.08
PULSE = (0, 3, 1, 3, 2, 3, 1, 3)
GATE = (1, 0, 1, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 0)

PACK = "sonic-pi/"
IMPACT = 1.66
BOOM_ROOT = 34.36
DRONE_ROOT = 43
# tbd_pad_1 is G minor's seventh chord about G2: under each chord, the minor seventh chord inside it.
LAYER = {"Fm6/9": 41, "Abmaj7#11": 48, "Ebmaj9": 43, "Fm9": 41, "Dbmaj7#11": 41}
CHOIR = 68.45


def mixed(*parts):
    out = np.zeros((max(len(x) for x, _ in parts), 2))
    for x, gain in parts:
        out[: len(x)] += (s.pan(x, 0.0) if x.ndim == 1 else x) * gain
    return out


def wider(x, width):
    middle, side = (x[:, 0] + x[:, 1]) / 2, (x[:, 0] - x[:, 1]) / 2 * width
    return np.stack([middle + side, middle - side], axis=1)


def driven(x, amount=2.5, tone=3200):
    return s.drive(x, amount, tone=tone, asym=0.1)


def cut(x, seconds):
    out = x[: max(0, int(round(seconds * s.SR)))].copy()
    fade = min(len(out), int(0.03 * s.SR))
    out[len(out) - fade:] *= np.linspace(1, 0, fade)[:, None] if out.ndim == 2 else np.linspace(1, 0, fade)
    return out


def kick():
    x = mixed((s.sample(PACK + "drum_heavy_kick.flac"), 0.7), (s.sample(PACK + "bd_fat.flac"), 0.6))
    return s.shelf(x, 2500, 4.0)


def snare():
    return mixed((s.sample(PACK + "sn_zome.flac", seconds=0.15, release=0.07), 0.7),
                 (s.sample(PACK + "elec_snare.flac", seconds=0.15, release=0.07), 0.55))


def boom(seconds, rising=1.0):
    """The cinematic boom from the air that swells up into its impact, IMPACT seconds before it."""
    x = s.sample(PACK + "misc_cineboom.flac", seconds=IMPACT + seconds, attack=0.002, release=seconds * 0.7)
    gain = np.interp(np.arange(len(x)) / s.SR, [IMPACT - 0.01, IMPACT], [rising, 1.0])
    return s.highpass(x * gain[:, None], 40, order=3)


def struck(seconds):
    """The cinematic boom from its impact, for the first frame, which has nothing before it."""
    x = s.sample(PACK + "misc_cineboom.flac", start=IMPACT, seconds=seconds, attack=0.001, release=seconds * 0.7)
    return s.highpass(x, 40, order=3)


def eight08(seconds=1.4):
    """The 808's boom, tuned to F2."""
    return s.sample(PACK + "bd_boom.flac", note=41, root=BOOM_ROOT, seconds=seconds, release=seconds * 0.5)


def choir(note, seconds=None, reverse=False):
    return s.sample(PACK + "ambi_choir.flac", note=note, root=CHOIR, seconds=seconds, release=0.3, reverse=reverse)


def pluck(note, bright):
    return driven(s.pluck(note, 0.85, 0.18, bright=bright), 2.2, 3600)


def pad(notes, seconds, cutoff, attack, release):
    saws = s.supersaw(notes, seconds, voices=6, spread=16, cutoff=cutoff, attack=attack, release=release)
    return wider(driven(saws, 1.8, 5000), 1.5)


def gated(notes, cutoff):
    saws = s.supersaw(notes, 0.11, voices=5, spread=14, cutoff=cutoff, attack=0.004, release=0.03)
    return wider(driven(saws, 2.2, 5200), 1.4)


def lead(note, seconds, cutoff, vibrato):
    brassy = s.brass([note], seconds, 0.9, cutoff=cutoff, attack=0.03, release=0.15)
    saws = s.saw_lead(note, seconds, 0.9, cutoff=cutoff * 1.2, detune=9, vibrato=vibrato)
    return wider(s.highpass(driven(mixed((brassy, 0.8), (saws, 0.7)), 2.6, 2800), 150), 1.6)


def bass(root, velocity, bright):
    sampled = s.sample(PACK + "bass_trance_c.flac", note=root, root=36, seconds=0.2, release=0.05, mono=True)
    saws = s.grit_bass(root, velocity, 0.18, bright=bright, grit=0.7)
    return s.lowpass(mixed((driven(sampled, 2.0, 2600) * velocity, 0.6), (saws, 0.9)), 4500)


def sting(bus, room, beat, tonic=77):
    """The series' sting: glass struck on the tonic, its fifth and its ninth, its own reverb swelling up into it."""
    glass = sum(s.pan(s.glass(tonic + up, 4.0, velocity), p) for up, velocity, p in ((0, 0.9, -0.3), (7, 0.7, 0.2), (14, 0.5, 0.45)))
    bus.add(at(beat - 1), s.swell_into(glass, BEAT, room), gain=0.07, wet=0.0)
    bus.add(at(beat), glass, gain=0.32, wet=0.5)


def darksynth(sounds=lambda fx: None):
    start(131)
    room = s.reverb(3.0, 0.75, 0.025)
    drums, low, pads, layer, arps, gate, lead_, fx, bed, drone = (s.Bus(LENGTH) for _ in range(10))
    kicks = []
    beat_kick, beat_snare = kick(), snare()
    muffled = s.lowpass(beat_kick, 180)
    closed = s.sample(PACK + "hat_gnu.flac", mono=True)
    opened = s.sample(PACK + "hat_metal.flac", seconds=0.25, release=0.15, mono=True)
    crash = s.sample(PACK + "drum_cymbal_hard.flac", release=0.4)

    # The first frame: the boom from its impact, the deep kick and the 808 on F. The recorded drone holds F from the
    # first frame to the drop, and a synth drone on F and C under the hook and the roadmap.
    fx.add(at(0), struck(2.4), gain=0.32, wet=0.3)
    drums.add(at(0), s.deep_kick(0.9), gain=0.4, wet=0.12)
    low.add(at(0), eight08(1.6), gain=0.26, wet=0.1)
    kicks.append(at(0))
    bedded = s.held(PACK + "loop_drone_g_97.flac", at(DROP), note=41, root=DRONE_ROOT, cross=0.4, attack=0.4, release=0.5)
    grow = np.interp(np.arange(len(bedded)) / s.SR, [0, at(FIRST), at(BREAK), at(DROP)], [0.8, 0.85, 1.0, 1.1])
    drone.add(at(0), bedded * grow[:, None], gain=0.6, wet=0.3)
    bed.add(at(0), s.drone([41, 48], at(FULL), cutoff=400, release=1.2, attack=at(FIRST)), gain=0.5, wet=0.3)

    # The lead-in, and the breakdown after it: a kick muffled as if through a wall on each beat, and in the lead-in
    # the arpeggio growing out of nothing from the third beat, a riser, and the first hit's reverb swelling into it.
    for beat in list(range(1, FIRST)) + list(range(BREAK, int(STOP) + 1)):
        drums.add(at(beat), muffled, gain=0.45 + 0.04 * (beat % 4), wet=0.02)
        kicks.append(at(beat))
    grows_from = 2
    for i, beat in enumerate(np.arange(grows_from, FIRST, 0.25)):
        grown = ((beat - grows_from + 0.25) / (FIRST - grows_from)) ** 1.6
        note = chord(beat)[2][PULSE[i % 8]]
        tone = pluck(note, 0.1 + 0.3 * grown)
        arps.add(at(beat), tone, gain=ARP * swell(FIRST) * grown, pan_to=(-0.3, 0.3)[i % 2], wet=0.25)
        arps.add(at(beat + 0.75), s.lowpass(tone, 2200), gain=ECHO * grown, pan_to=(0.4, -0.4)[i % 2], wet=0.4)
    fx.add(at(0), s.riser(at(FIRST), 250, 4000, curve=2.6), gain=0.07, wet=0.3)
    fx.add(at(FIRST - 2), s.swell_into(s.boom(1.4, 0.7), at(FIRST) - at(FIRST - 2), room), gain=0.28, wet=0.0)
    backwards = s.sample(PACK + "drum_cymbal_hard.flac", seconds=1.2, release=0.6, reverse=True)
    drums.add(at(FIRST) - len(backwards) / s.SR, backwards, gain=0.24, wet=0.3)

    # The first hit: the kick, the deep kick and the 808 as the roadmap comes in.
    drums.add(at(FIRST), beat_kick, gain=0.5, wet=0.1)
    drums.add(at(FIRST), s.deep_kick(0.85), gain=0.32, wet=0.12)
    low.add(at(FIRST), eight08(1.2), gain=0.22, wet=0.1)
    kicks.append(at(FIRST))

    # The pads: the supersaw's, swelling with the lamp from the first frame and opening through act 2; the recorded
    # pad, the minor seventh chord inside each chord; and the synth choir from the first hit.
    for name, first, length in CHORDS:
        _, voicing = VOICINGS[name]
        last = first == LAST
        seconds = 3.0 if last else length * BEAT
        cutoff = 2600 if first >= DROP else 1300 if BREAK <= first < DROP else opening(first, 0, BREAK, 1000, 2200)
        attack = at(FIRST) * 0.9 if first == 0 else 0.1
        tone = pad(voicing, seconds, cutoff, attack=attack, release=1.6 if last else 0.25)
        pads.add(at(first), dying(tone, 1.3) if last else tone, gain=0.18 * swell(first), wet=0.5)
        if name in LAYER:
            under = s.held(PACK + "tbd_pad_1.flac", seconds, note=LAYER[name], root=43, cross=0.3,
                           attack=attack if first == 0 else 0.08, release=1.6 if last else 0.25)
            under = s.highpass(dying(under, 1.4) if last else under, 140)
            layer.add(at(first), under, gain=0.4 * swell(first), wet=0.45)
        if first >= FIRST:
            sung = s.choir([n + 12 for n in voicing[1:]], seconds, attack=0.35 if first in (FIRST, DROP) else 0.12,
                           release=1.8 if last else 0.3)
            layer.add(at(first), dying(sung, 1.4) if last else sung, gain=0.2 * swell(first), wet=0.55)

    # The arpeggio in sixteenths from the first hit, its top note pulsing, with an echo a dotted eighth later,
    # opening through act 2, darker and quieter through the breakdown.
    for i, beat in enumerate(np.arange(FIRST, LAST - 1e-9, 0.25)):
        if STOP <= beat < DROP:
            continue
        quiet = BREAK <= beat < DROP
        note = chord(beat)[2][PULSE[round(beat * 4) % 8]]
        bright = 0.2 if quiet else opening(beat, FIRST, BREAK, 0.28, 0.62) if beat < DROP else 0.66
        tone = pluck(note, bright)
        level = ARP * swell(beat) * (1.0 if i % 2 == 0 else 0.8) * (0.55 if quiet else 1.0)
        arps.add(at(beat), tone, gain=level, pan_to=(-0.45, 0.45)[i % 2], wet=0.3)
        arps.add(at(beat + 0.75), s.lowpass(tone, 2000), gain=ECHO * swell(beat), pan_to=(0.6, -0.6)[i % 2], wet=0.45)

    # The trance gate with the full beat, from the print and again from the drop.
    for beat in playing(FULL, LAST, 0.25):
        if not GATE[round(beat * 4) % 16]:
            continue
        cutoff = opening(beat, FULL, BREAK, 1800, 3000) if beat < DROP else 3600
        gate.add(at(beat), gated(chord(beat)[2], cutoff), gain=0.2 * swell(beat), wet=0.3)

    # The bass: F held under the hook, swelling with the lamp; the offbeats with the beat; through the breakdown
    # D flat held low; the last F dies away.
    held = s.grit_bass(41, 0.8, at(FIRST) - 0.05, bright=0.12, grit=0.5)
    held = held * np.clip(np.arange(len(held)) / s.SR / at(FIRST), 0, 1)
    low.add(at(0), dying(s.lowpass(held, 1800), 2.4), gain=0.3, wet=0.08)
    for beat in playing(FIRST, LAST, 1):
        bright = opening(beat, FIRST, BREAK, 0.2, 0.55) if beat < DROP else 0.65
        low.add(at(beat + 0.5), bass(chord(beat)[0], 0.9, bright), gain=0.48 * swell(beat), wet=0.04)
    under = s.grit_bass(37, 0.8, at(STOP) - at(BREAK), bright=0.15, grit=0.5)
    low.add(at(BREAK), dying(s.lowpass(under, 1500), 3.0), gain=0.32, wet=0.08)
    low.add(at(LAST), dying(s.lowpass(s.grit_bass(41, 0.9, 3.0, bright=0.3, grit=0.6), 2200), 0.9), gain=0.4, wet=0.1)

    # The kit. In half time under the roadmap, a kick on 1 and the and of 2 and the snare in a long room on 3, with
    # closed hats in eighths; four on the floor from the print and again from the drop, the snare on 2 and 4, closed
    # hats in sixteenths accented on the offbeats and an open hat on each offbeat, eighths again from the address. In
    # the breakdown, a snare roll from the roll's cue doubles from eighths to sixteenths to thirty-seconds into the
    # stop.
    for beat in playing(FIRST, LAST, 0.5):
        if beat == FIRST or beat < FULL and beat % 4 not in (0, 1.5) or beat >= FULL and beat % 1:
            continue
        drums.add(at(beat), beat_kick, gain=0.52 * swell(beat) ** 0.5, wet=0.04)
        kicks.append(at(beat))
    for beat in playing(FIRST, LAST, 1):
        if beat < FULL and beat % 4 == 2 or beat >= FULL and beat % 2 == 1:
            drums.add(at(beat), beat_snare, gain=0.36 if beat < FULL else 0.4, wet=0.34)
    for beat in playing(FIRST, FULL, 0.5):
        drums.add(at(beat), closed, gain=(0.4 if beat % 1 else 0.24) * swell(beat), pan_to=0.3, wet=0.06)
    for beat in playing(FULL, LAST, 0.25):
        if beat >= CTA and beat % 0.5:
            continue
        accent = (0.45, 0.3, 1.0, 0.3)[round(beat * 4) % 4]
        drums.add(at(beat), closed, gain=0.34 * accent * swell(beat), pan_to=0.3, wet=0.06)
    for beat in playing(FULL + 0.5, CTA, 1):
        drums.add(at(beat), opened, gain=0.13 * swell(beat), pan_to=-0.3, wet=0.15)
    roll = list(np.arange(ROLL, ROLL + 0.75, 0.5)) + list(np.arange(ROLL + 0.75, STOP - 0.25, 0.25)) + list(np.arange(STOP - 0.25, STOP, 0.125))
    for i, beat in enumerate(roll):
        drums.add(at(beat), beat_snare, gain=0.16 + 0.22 * i / len(roll), pan_to=0.1, wet=0.3)

    # The riff on the brass and the saws, with an echo a dotted eighth later that stops before the breakdown, the drop
    # and the last hit; doubled an octave down, and an octave up from the drop to the editor.
    for beat, note, beats, weight in TUNE:
        last = beat >= LAST
        seconds = beats * BEAT * 0.94
        cutoff = 2400 if beat >= DROP else 1600 if BREAK <= beat < DROP else 1900
        tone = lead(note, seconds, cutoff, 0.14 if beats >= 1 else 0.0)
        below = lead(note - 12, seconds, cutoff * 0.7, 0.0)
        if last:
            tone, below = dying(tone, 1.0), dying(below, 1.0)
        level = 0.27 * swell(beat) ** 0.5 * weight
        lead_.add(at(beat), tone, gain=level, wet=0.3 if weight == 1 else 0.5)
        lead_.add(at(beat), below, gain=level * 0.45, wet=0.25)
        stop = BREAK if beat < BREAK else STOP if beat < DROP else LAST if beat < LAST else BEATS
        echo = cut(s.lowpass(tone.mean(axis=1), 1800), (stop - beat - 0.75) * BEAT)
        lead_.add(at(beat + 0.75), echo, gain=level * 0.28, pan_to=-0.5, wet=0.5)
        if DROP <= beat < END:
            lead_.add(at(beat), lead(note + 12, seconds, 3000, 0.1), gain=level * 0.26, wet=0.4)

    # The print: a crash as the full beat comes in, and the series' glass sting on its develop. The build: a riser
    # through the breakdown, and into the drop the air before the boom's impact, a crash played backwards, the choir
    # breathing in, and the hit's own reverb swelling up through the stop.
    drums.add(at(FULL), crash, gain=0.1, wet=0.35)
    sting(fx, room, FULL)
    hit = pad([n + 12 for n in VOICINGS["Fm9"][1]], 1.2, 3600, attack=0.02, release=0.6)
    fx.add(at(BREAK), s.riser(at(DROP) - at(BREAK), 250, 7000, curve=2.4), gain=0.07, wet=0.35)
    fx.add(at(STOP), s.swell_into(hit, at(DROP) - at(STOP), room), gain=0.18, wet=0.0)
    fx.add(at(DROP) - IMPACT, boom(3.5), gain=0.34, wet=0.25)
    backwards = s.sample(PACK + "drum_cymbal_hard.flac", seconds=1.6, release=0.8, reverse=True)
    drums.add(at(DROP) - len(backwards) / s.SR, backwards, gain=0.16, wet=0.3)
    breath = choir(68, 1.2, reverse=True)
    layer.add(at(DROP) - len(breath) / s.SR, breath, gain=0.24, wet=0.5)

    # The drop and the last hit: the boom, the 808 and the deep kick under the kick, an impact, a trailer's low
    # brass on F, the choir and a crash; a low swell and a soft crash as the lamp comes on with the address; the boom
    # again, smaller, on the last hit, and the arpeggio's last chord rising after it.
    brass = driven(s.braam([41, 48, 53, 56, 60], 2.6, 1.0), 1.6, 3000)
    for beat, weight in ((DROP, 1.0), (LAST, 0.8)):
        drums.add(at(beat), beat_kick, gain=0.55, wet=0.1)
        drums.add(at(beat), s.deep_kick(1.0), gain=0.55 * weight, wet=0.08)
        low.add(at(beat), eight08(2.2), gain=0.42 * weight, wet=0.1)
        low.add(at(beat), dying(brass, 1.1) if beat == LAST else brass, gain=0.34 * weight, wet=0.3)
        kicks.append(at(beat))
        fx.add(at(beat), s.sample(PACK + "perc_impact2.flac", release=0.3), gain=0.18 * weight, wet=0.35)
        layer.add(at(beat), choir(68), gain=0.3 * weight, wet=0.5)
        drums.add(at(beat), crash, gain=0.2 * weight, wet=0.35)
    fx.add(at(LAST) - IMPACT, boom(3.4, rising=0.5), gain=0.24, wet=0.3)
    pads.add(at(DROP), hit, gain=0.2, wet=0.3)
    fx.add(at(CTA), s.swell_into(pad(VOICINGS["C7(b9)"][1], 1.0, 1400, attack=0.4, release=0.5), BEAT, room),
           gain=0.12, wet=0.0)
    drums.add(at(CTA), crash, gain=0.12, wet=0.35)
    for i, (note, p) in enumerate(zip(VOICINGS["Fm9"][1], (-0.4, -0.15, 0.15, 0.4))):
        arps.add(at(LAST + i / 4), pluck(note + 12, 0.45), gain=ARP * 0.9, pan_to=p, wet=0.55)

    sounds(fx)

    pump = s.sidechain(LENGTH, kicks, depth=0.55, release=0.17)
    low.duck(1 - 0.6 * (1 - pump))
    pads.duck(1 - 0.4 * (1 - pump))
    layer.duck(1 - 0.3 * (1 - pump))
    arps.duck(1 - 0.25 * (1 - pump))
    gate.duck(1 - 0.3 * (1 - pump))
    drone.duck(1 - 0.4 * (1 - pump))
    trim(drums, 40)
    trim(low, 45)
    trim(fx, 45)
    trim(bed, 45)
    trim(drone, 50)
    return [drums, low, pads, layer, arps, gate, lead_, fx, bed, drone], dict(room=room, wet=0.55, presence=4.0)


ARRANGEMENTS = {"darksynth": darksynth}
