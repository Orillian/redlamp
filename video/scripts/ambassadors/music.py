"""
The ambassadors reel's track (src/ambassadors/AmbassadorsReel.tsx): dark synthwave in F minor at 100 BPM, 8 bars
and 19.2 seconds on the reel's cue sheet, src/ambassadors/cues.json, which scripts/ambassadors-score.py plays
under the reel with its sounds on screen. It is E12's darksynth (scripts/features/music/e12.py) carried to F minor
and to the reel's shape, which has no opener before it. Its first bar is the lead-in, under the hook and the lamp
warming: a deep hit on the first frame, a drone, a pad swelling with the lamp, a kick muffled as if through a
wall, and the arpeggio growing out of nothing from the third beat, with the first hit's own reverb swelling up
into it. The first hit lands as the dashboard comes in, with the bass and the arpeggio; the riff and the full beat
come in with the roadmap, with falling toms into the stop; the drop is the loudest bar, with the series' glass
sting; the groove holds through the ten frames; the closing phrase starts with the end line, sits on the dominant
under the address and lands on the tonic on the last hit; and the last chord dies away as the picture fades.

The chords: Fm6/9 under the hook and Abmaj7#11 from the first hit; then the bass steps down from E flat through D
to C, under Ebmaj9, Dm7(b5) and C7(b9), and rises a fourth to F on the drop, on Fm9; Dbmaj7#11 and Ebmaj9 under
the ten frames; Dbmaj7#11 and Dm7(b5) under the end line, C7(b9) under the address, and Fm9 on the last hit. The
voicings are E12's a fourth up, rootless between G3 and G4, every voice moving by step.

The riff is F minor's: G, E flat and G, up to A flat, falling to F and E as the bass steps down, the leading note
held into the stop; on the drop C, A flat and C up to E flat, then C held; over the ten frames A flat, F and A
flat, up to C and down to B flat; the closing phrase turns the same way to A flat, F and E under the address, and
lands on F on the last hit.

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
FIRST, FULL, STOP, DROP = cue["dashboard"], cue["roadmap"], cue["stop"], cue["drop"]
END, CTA, LAST = cue["endLine"], cue["cta"], cue["lastHit"]
FILL = STOP - 1


def at(beat):
    return beat * BEAT


# How fully the track plays from each cue: held back under the hook, growing through the dashboard, full on the
# drop and through the ten frames, then easing a little for the end card and the last chord.
SWELL = [(0, 0.72), (FIRST, 0.8), (FULL, 0.88), (DROP, 1.0), (END, 0.93), (LAST, 0.85)]


def swell(beat):
    return [level for first, level in SWELL if first <= beat][-1]


def playing(first, last, step):
    """Beats from `first` up to `last`, every `step`, leaving out the stop before the drop."""
    return [b for b in np.arange(first, last - 1e-9, step) if not STOP <= b < DROP]


CHORDS = [("Fm6/9", 0, 4), ("Abmaj7#11", 4, 4), ("Ebmaj9", 8, 2), ("Dm7(b5)", 10, 1), ("C7(b9)", 11, 1),
          ("Fm9", 12, 4), ("Dbmaj7#11", 16, 2), ("Ebmaj9", 18, 2), ("Dbmaj7#11", 20, 2), ("Dm7(b5)", 22, 2),
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


def placed(first, part):
    return [(first + beat, note, beats) for beat, note, beats in part]


# The riff, [beat, note, beats] from where each phrase starts.
CALL = [(0, 67, 0.75), (0.75, 63, 0.25), (1, 67, 0.5), (1.5, 68, 0.5), (2, 65, 1.0), (3, 64, 0.5)]
HEAD = [(0, 72, 0.75), (0.75, 68, 0.25), (1, 72, 0.5), (1.5, 75, 0.5), (2, 72, 1.5), (3.5, 68, 0.5)]
FRAMES = [(0, 68, 0.75), (0.75, 65, 0.25), (1, 68, 0.5), (1.5, 72, 0.5), (2, 70, 1.5), (3.5, 67, 0.5)]
CLOSE = [(0, 68, 0.75), (0.75, 65, 0.25), (1, 68, 0.5), (1.5, 72, 0.5), (2, 68, 1.0), (3, 65, 1.0), (4, 64, 2.0),
         (6, 67, 1.0), (7, 73, 1.0), (8, 65, 4.0)]
TUNE = placed(FULL, CALL) + placed(DROP, HEAD) + placed(cue["sheet"], FRAMES) + placed(END, CLOSE)

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
# The toms, tuned to F, C and A flat, falling through F minor.
TOMS = {"high": ("drum_tom_hi_hard", 50.58, 53, 0.35), "middle": ("drum_tom_mid_hard", 46.87, 48, 0.0),
        "low": ("drum_tom_lo_hard", 41.9, 44, -0.35)}


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


def tom(which):
    name, root, note, _ = TOMS[which]
    return s.sample(PACK + f"{name}.flac", note=note, root=root, seconds=0.6, release=0.2, mono=True)


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


def sting(bus, room, tonic=77):
    """The series' sting on the drop: glass struck on the tonic, its fifth and its ninth, its own reverb
    swelling up into it."""
    glass = sum(s.pan(s.glass(tonic + up, 4.0, velocity), p) for up, velocity, p in ((0, 0.9, -0.3), (7, 0.7, 0.2), (14, 0.5, 0.45)))
    bus.add(at(DROP - 1), s.swell_into(glass, BEAT, room), gain=0.07, wet=0.0)
    bus.add(at(DROP), glass, gain=0.32, wet=0.5)


def darksynth(sounds=lambda fx: None):
    start(131)
    room = s.reverb(3.0, 0.75, 0.025)
    drums, low, pads, layer, arps, gate, lead_, fx, bed, drone = (s.Bus(LENGTH) for _ in range(10))
    kicks = []
    beat_kick, beat_snare = kick(), snare()
    closed = s.sample(PACK + "hat_gnu.flac", mono=True)
    opened = s.sample(PACK + "hat_metal.flac", seconds=0.25, release=0.15, mono=True)
    crash = s.sample(PACK + "drum_cymbal_hard.flac", release=0.4)

    # The first frame: the boom from its impact, its sub, the deep kick and the 808 on F. The recorded drone comes
    # in on F under the hook and grows through the dashboard, swelling on through the stop into the drop.
    fx.add(at(0), struck(2.4), gain=0.32, wet=0.3)
    drums.add(at(0), s.deep_kick(0.9), gain=0.4, wet=0.12)
    low.add(at(0), eight08(1.6), gain=0.26, wet=0.1)
    kicks.append(at(0))
    bedded = s.held(PACK + "loop_drone_g_97.flac", at(DROP), note=41, root=DRONE_ROOT, cross=0.4, attack=0.4, release=0.5)
    grow = np.interp(np.arange(len(bedded)) / s.SR, [0, at(FIRST), at(DROP)], [0.8, 0.85, 1.0])
    drone.add(at(0), bedded * grow[:, None], gain=0.6, wet=0.3)
    bed.add(at(0), s.drone([41, 48], at(FULL), cutoff=400, release=1.2, attack=at(FIRST)), gain=0.5, wet=0.3)

    # The lead-in: a kick muffled as if through a wall on each beat after the first, the arpeggio growing out of
    # nothing from the third beat on Fm6/9's notes, a riser, and the first hit's reverb swelling up into it.
    for beat in range(1, FIRST):
        drums.add(at(beat), s.lowpass(beat_kick, 180), gain=0.45 + 0.04 * beat, wet=0.02)
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

    # The first hit: the kick, the deep kick and the 808 as the dashboard comes in.
    drums.add(at(FIRST), beat_kick, gain=0.5, wet=0.1)
    drums.add(at(FIRST), s.deep_kick(0.85), gain=0.32, wet=0.12)
    low.add(at(FIRST), eight08(1.2), gain=0.22, wet=0.1)
    kicks.append(at(FIRST))

    # The pads: the supersaw's, swelling with the lamp from the first frame and opening through the build; the
    # recorded pad, the minor seventh chord inside each chord; and the synth choir from the first hit.
    for name, first, length in CHORDS:
        _, voicing = VOICINGS[name]
        last = first == LAST
        seconds = 3.0 if last else length * BEAT
        cutoff = 2600 if first >= DROP else opening(first, 0, STOP, 1000, 2200)
        attack = at(FIRST) * 0.9 if first == 0 else 0.1
        tone = pad(voicing, seconds, cutoff, attack=attack, release=1.6 if last else 0.25)
        pads.add(at(first), dying(tone, 1.3) if last else tone, gain=0.18 * swell(first), wet=0.5)
        if name in LAYER:
            under = s.held(PACK + "tbd_pad_1.flac", seconds, note=LAYER[name], root=43, cross=0.3,
                           attack=attack if first == 0 else 0.08, release=1.6 if last else 0.25)
            under = s.highpass(dying(under, 1.4) if last else under, 140)
            layer.add(at(first), under, gain=0.4 * swell(first), wet=0.45)
        if first >= FIRST:
            sung = s.choir([n + 12 for n in voicing[1:]], seconds, attack=0.35 if first == FIRST else 0.12,
                           release=1.8 if last else 0.3)
            layer.add(at(first), dying(sung, 1.4) if last else sung, gain=0.2 * swell(first), wet=0.55)

    # The arpeggio in sixteenths from the first hit, its top note pulsing, with an echo a dotted eighth later,
    # opening through the build.
    for i, beat in enumerate(playing(FIRST, LAST, 0.25)):
        note = chord(beat)[2][PULSE[round(beat * 4) % 8]]
        bright = opening(beat, FIRST, STOP, 0.28, 0.62) if beat < DROP else 0.66
        tone = pluck(note, bright)
        arps.add(at(beat), tone, gain=ARP * swell(beat) * (1.0 if i % 2 == 0 else 0.8), pan_to=(-0.45, 0.45)[i % 2], wet=0.3)
        arps.add(at(beat + 0.75), s.lowpass(tone, 2000), gain=ECHO * swell(beat), pan_to=(0.6, -0.6)[i % 2], wet=0.45)

    # The trance gate from the roadmap, opening into the drop and full from it.
    for beat in playing(FULL, LAST, 0.25):
        if not GATE[round(beat * 4) % 16]:
            continue
        cutoff = opening(beat, FULL, STOP, 1600, 3400) if beat < DROP else 3600
        gate.add(at(beat), gated(chord(beat)[2], cutoff), gain=0.2 * swell(beat), wet=0.3)

    # The bass: F held under the hook, swelling with the lamp; the offbeats from the first hit; the last F dies away.
    held = s.grit_bass(41, 0.8, at(FIRST) - 0.05, bright=0.12, grit=0.5)
    held = held * np.clip(np.arange(len(held)) / s.SR / at(FIRST), 0, 1)
    low.add(at(0), dying(s.lowpass(held, 1800), 2.4), gain=0.3, wet=0.08)
    for beat in playing(FIRST, LAST, 1):
        if STOP <= beat + 0.5 < DROP:
            continue
        bright = opening(beat, FIRST, STOP, 0.2, 0.55) if beat < DROP else 0.65
        low.add(at(beat + 0.5), bass(chord(beat)[0], 0.9, bright), gain=0.48 * swell(beat), wet=0.04)
    low.add(at(LAST), dying(s.lowpass(s.grit_bass(41, 0.9, 3.0, bright=0.3, grit=0.6), 2200), 0.9), gain=0.4, wet=0.1)

    # The kit. In half time through the dashboard's bar, a kick on 1 and the and of 2 and the snare in a long room
    # on 3, with closed hats in eighths; from the roadmap four on the floor, the snare on 2 and 4, closed hats in
    # sixteenths accented on the offbeats and an open hat on each offbeat; eighths again from the end line. Toms
    # fall from F to A flat into the stop, and into the last hit.
    for beat in playing(FIRST, LAST, 0.5):
        if beat < FULL and beat % 4 not in (0, 1.5) or beat >= FULL and beat % 1:
            continue
        if beat == FIRST:
            continue
        drums.add(at(beat), beat_kick, gain=0.52 * swell(beat) ** 0.5, wet=0.04)
        kicks.append(at(beat))
    for beat in playing(FIRST, LAST, 1):
        if beat < FULL and beat % 4 == 2 or beat >= FULL and beat % 2 == 1:
            if FILL <= beat < DROP:
                continue
            drums.add(at(beat), beat_snare, gain=0.36 if beat < FULL else 0.4, wet=0.34)
    for beat in playing(FIRST, FULL, 0.5):
        drums.add(at(beat), closed, gain=(0.4 if beat % 1 else 0.24) * swell(beat), pan_to=0.3, wet=0.06)
    for beat in playing(FULL, LAST, 0.25):
        if FILL <= beat < DROP or beat >= END and beat % 0.5:
            continue
        accent = (0.45, 0.3, 1.0, 0.3)[round(beat * 4) % 4]
        drums.add(at(beat), closed, gain=0.34 * accent * swell(beat), pan_to=0.3, wet=0.06)
    for beat in playing(FULL + 0.5, END, 1):
        if FILL <= beat < DROP:
            continue
        drums.add(at(beat), opened, gain=0.13 * swell(beat), pan_to=-0.3, wet=0.15)
    beat = FILL
    for i, (which, step) in enumerate([("high", 0.25), ("middle", 0.25), ("middle", 0.125), ("low", 0.125),
                                       ("low", 0.125), ("low", 0.125)]):
        drums.add(at(beat), tom(which), gain=0.36 + 0.04 * i, pan_to=TOMS[which][3], wet=0.3)
        beat += step
    for beat, which in zip(np.arange(LAST - 1, LAST, 0.25), ("high", "middle", "middle", "low")):
        drums.add(at(beat), tom(which), gain=0.32, pan_to=TOMS[which][3], wet=0.3)

    # The riff on the brass and the saws, with an echo a dotted eighth later that stops on the drop and the last
    # hit; doubled an octave down, and an octave up from the drop to the end line.
    for beat, note, beats in TUNE:
        last = beat >= LAST
        seconds = beats * BEAT * 0.94
        cutoff = 2400 if beat >= DROP else 1900
        tone = lead(note, seconds, cutoff, 0.14 if beats >= 1 else 0.0)
        below = lead(note - 12, seconds, cutoff * 0.7, 0.0)
        if last:
            tone, below = dying(tone, 1.0), dying(below, 1.0)
        level = 0.27 * swell(beat) ** 0.5
        lead_.add(at(beat), tone, gain=level, wet=0.3)
        lead_.add(at(beat), below, gain=level * 0.45, wet=0.25)
        stop = STOP if beat < DROP else LAST if beat < LAST else BEATS
        echo = cut(s.lowpass(tone.mean(axis=1), 1800), (stop - beat - 0.75) * BEAT)
        lead_.add(at(beat + 0.75), echo, gain=level * 0.28, pan_to=-0.5, wet=0.5)
        if DROP <= beat < END:
            lead_.add(at(beat), lead(note + 12, seconds, 3000, 0.1), gain=level * 0.26, wet=0.4)

    # The build: a crash as the full beat comes in, a riser through the roadmap's bar, and into the drop the air
    # before the boom's impact, a crash played backwards, the choir breathing in, and the hit's own reverb
    # swelling up through the stop.
    drums.add(at(FULL), crash, gain=0.1, wet=0.35)
    hit = pad([n + 12 for n in VOICINGS["Fm9"][1]], 1.2, 3600, attack=0.02, release=0.6)
    fx.add(at(FULL), s.riser(at(DROP) - at(FULL), 300, 7000, curve=2.2), gain=0.06, wet=0.35)
    fx.add(at(STOP), s.swell_into(hit, at(DROP) - at(STOP), room), gain=0.18, wet=0.0)
    fx.add(at(DROP) - IMPACT, boom(3.5), gain=0.34, wet=0.25)
    backwards = s.sample(PACK + "drum_cymbal_hard.flac", seconds=1.6, release=0.8, reverse=True)
    drums.add(at(DROP) - len(backwards) / s.SR, backwards, gain=0.16, wet=0.3)
    breath = choir(68, 1.2, reverse=True)
    layer.add(at(DROP) - len(breath) / s.SR, breath, gain=0.24, wet=0.5)

    # The drop and the last hit: the boom, the 808 and the deep kick under the kick, an impact, a trailer's low
    # brass on F, the choir and a crash; a low swell as the lamp's light spreads on the end card; a soft crash as
    # the address comes in; the boom again, smaller, on the last hit, and the arpeggio's last chord rising after it.
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
    fx.add(at(END), s.swell_into(pad(VOICINGS["Dbmaj7#11"][1], 1.0, 1400, attack=0.4, release=0.5), BEAT, room),
           gain=0.12, wet=0.0)
    drums.add(at(CTA), crash, gain=0.12, wet=0.35)
    for i, (note, p) in enumerate(zip(VOICINGS["Fm9"][1], (-0.4, -0.15, 0.15, 0.4))):
        arps.add(at(LAST + i / 4), pluck(note + 12, 0.45), gain=ARP * 0.9, pan_to=p, wet=0.55)

    sting(fx, room)
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
