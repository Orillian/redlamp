"""
E07's track (Speed): a driving dark synthwave track in G sharp minor at 100 BPM, 8 bars and 19.2 seconds on the
series' cue sheet, src/features/cues.json, which scripts/features-score.py plays under the episode with its own
sounds. Its first chord, Emaj9, shares E and F sharp with the opener's held D major chord: the lead-in plays the
arpeggio on E and F sharp over a drone on E with F sharp above, and on the first hit the music lifts a whole tone,
the bass landing on E and the pads bringing in G sharp, B and D sharp.

The chords start on the sixth and climb back to it, then rise by steps into the drop: Emaj9 under the hook, then
F#6/9, C#m9 and Bmaj9 a bar each, then Emaj9 to F#6, the bass rising E, F sharp, G sharp onto G#m9 on the drop; on
the end line Emaj9 to D#7(b9), and G#m9 on the last hit. The pads sit between G3 and G sharp 4, every voice moving
by step.

The riff is two bars on a lead that slides between its notes, each bar a long note falling a step and back, then
climbing: G sharp, F sharp and G sharp, up through A sharp to D sharp, and down through C sharp to A sharp; then
the same shape from E, up to B, held. The answer plays the first bar again over Bmaj9, then over Emaj9 falls from G
sharp to D sharp and climbs to A sharp, held through the stop, which falls a step to G sharp on the drop, where the
riff's first bar comes back; the closing phrase turns over D#7(b9) through A sharp and G, the leading note, to G
sharp on the last hit.

darksynth, its one arrangement, is the most driving of the series' tracks, after Perturbator: a bass sequence
running in sixteenths from the first frame, muffled under the hook and opening through the build, its octave on
the third sixteenth of each beat and a fifth on the bar's last beat; an arpeggio climbing the chord a beat at a time
in sixteenths, with an echo a dotted eighth later, and from the fourth step a sequencer in thirty-seconds over it;
a kick muffled as if through a wall until the third step, when tight gated drums come in with a crash: four on the
floor, a snare whose room is gated short on 2 and 4, closed hats in sixteenths, and from the drop open hats on the
offbeats; electronic toms fall in sixteenths and then thirty-seconds into the stop, and into the last hit. The
riff is on a hard-sync lead over two saws an octave down, driven and spread wide, doubled an octave up on the drop;
the pads are driven supersaws that open through the build, and from the drop they stab the offbeats.

Recorded sounds from Sonic Pi's pack (CC0), in the samples' folder outside the repository (synth.SAMPLES), are
layered in: a cinematic boom whose air rises into the first hit, the drop and, smaller, the last hit, with a
cymbal played backwards; a dark woosh swelling into the drop; a drone pitched to G sharp and D sharp, held under
everything from the first hit as a pedal; a glass hum pitched to B, which with its own D sharp and F sharp is the
top of Emaj9 and of G#m9, under the hook, the drop and the last chord; a pad pitched to the cluster inside each
chord that has one; a hard bass under the sequence; and the kit, an electronic kick, an electronic snare over a
dry one, closed and open hats, a fuzz tom tuned to G sharp, D sharp and B, and cymbals. On the drop the boom, the
kick under a deep kick, a trailer's low brass on G sharp, the chord struck and a cymbal land together with the
series' sting, glass struck on G sharp, D sharp and A sharp.
"""

import importlib.util
from pathlib import Path

import numpy as np

import synth as s


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


theme = load(Path(__file__).resolve().parents[2] / "features-theme.py", "features_theme")
at, swell, opening, cue = theme.at, theme.swell, theme.opening, theme.cue
S1, S2, S3, S4, DROP, STOP, LAST = theme.S1, theme.S2, theme.S3, theme.S4, theme.DROP, theme.STOP, theme.LAST

# The chords as the cue sheet lists E01's: a name, its first beat and how many beats it lasts.
CHORDS = [("Emaj9", 0, 4), ("F#6/9", 4, 4), ("C#m9", 8, 4), ("Bmaj9", 12, 4), ("Emaj9", 16, 2), ("F#6", 18, 2),
          ("G#m9", 20, 4), ("Emaj9", 24, 2), ("D#7(b9)", 26, 2), ("G#m9", 28, 4)]

# Each chord: the bass's root, from E2 up to F sharp, down to B1 and back up by steps to G sharp 2 on the drop;
# and the pads' voicing, rootless between G3 and G sharp 4, its voices moving by step and keeping the colour
# notes: E's major seventh and ninth, F sharp's sixth and ninth, C sharp minor's ninth against its minor third, B's
# major seventh, G sharp minor's ninth against its minor third, and D sharp's flat ninth over its leading note.
VOICINGS = {
    "Emaj9": (40, [56, 59, 63, 66]),
    "F#6/9": (42, [58, 61, 63, 68]),
    "C#m9": (37, [59, 63, 64, 68]),
    "Bmaj9": (35, [58, 61, 63, 66]),
    "F#6": (42, [58, 61, 63, 66]),
    "G#m9": (44, [58, 59, 63, 66]),
    "D#7(b9)": (39, [55, 58, 61, 64]),
}


def chord(beat):
    root, voicing = VOICINGS[theme.chord_at(beat, CHORDS)]
    return root, voicing, [n + 12 for n in voicing]


# The riff, [beat, note, beats] from where it starts: G sharp, F sharp and G sharp, A sharp, D sharp held, C sharp
# and A sharp; then E, D sharp and E, F sharp, B held and G sharp. The answer falls to D sharp and holds A sharp
# through the stop; the head is the first bar; the closing phrase turns through G to G sharp on the last hit.
MOTIF = [(0, 68, 0.75), (0.75, 66, 0.25), (1, 68, 0.5), (1.5, 70, 0.5), (2, 75, 1.0), (3, 73, 0.5), (3.5, 70, 0.5),
         (4, 64, 0.75), (4.75, 63, 0.25), (5, 64, 0.5), (5.5, 66, 0.5), (6, 71, 1.5), (7.5, 68, 0.5)]
ANSWER = MOTIF[:7] + [(4, 68, 0.75), (4.75, 66, 0.25), (5, 63, 0.5), (5.5, 66, 0.5), (6, 70, 2.0)]
HEAD = MOTIF[:7]
CLOSE = [(0, 68, 0.75), (0.75, 66, 0.25), (1, 68, 0.5), (1.5, 71, 0.5), (2, 70, 0.75), (2.75, 67, 0.25), (3, 70, 0.5),
         (3.5, 67, 0.5), (4, 68, 4.0)]
TUNE = (theme.placed(S1, MOTIF) + theme.placed(S3, ANSWER) + theme.placed(DROP, HEAD)
        + theme.placed(cue["endLine"], CLOSE))

# The bass sequence, a bar of sixteenths above each chord's root: the octave on the third sixteenth of each beat,
# and the fifth on the bar's last beat, leading into the next chord; and how hard each is played.
SEQUENCE = (0, 0, 12, 0, 0, 0, 12, 0, 0, 0, 12, 0, 0, 12, 7, 12)
ACCENT = (1.0, 0.62, 0.86, 0.62)
# The arpeggio's levels for a note and its echo, which the lead-in grows to; it climbs the chord a beat at a time.
ARP, ECHO = 0.28, 0.09
RUN = (0, 1, 2, 3)
# The sequencer over it in thirty-seconds: up the chord and back down, two octaves over the pads.
FAST = (0, 1, 2, 3, 2, 1, 2, 3)

# ---------------------------------------------------------------- the recorded sounds
# Samples from Sonic Pi's pack (CC0) in the samples' folder (synth.SAMPLES).
PACK = "sonic-pi/"
# Where misc_cineboom's impact falls, after the air that swells up into it.
IMPACT = 1.66
# Where ambi_dark_woosh is loudest, after it swells in.
WOOSH = 1.3
# ambi_drone holds C4 and C5 about 20 cents sharp with G between them; pitched down to G sharp, it holds G sharp and
# D sharp, the tonic and its fifth.
DRONE_ROOT = 60.2
# ambi_glass_hum hums A3 with its major third and fifth over it; pitched up to B3, it's B major, the top of Emaj9
# and of G#m9.
GLASS_ROOT = 57
# tbd_pad_4 is a cluster of D, E flat, F and G about D4. A semitone up it's D sharp, E, F sharp and G sharp, inside
# Emaj9 and C#m9; four semitones down it's A sharp, B, C sharp and D sharp, inside Bmaj9 and G#m9. The other chords
# have none, so the pad leaves them to the synths.
PAD_ROOT = 62
LAYER = {"Emaj9": 63, "C#m9": 63, "Bmaj9": 58, "G#m9": 58}
# The fuzz tom sounds E2 a quarter of a semitone sharp: tuned to G sharp, D sharp and B, falling through the tonic
# chord, and where each sits, from the right to the left.
TOM_ROOT = 40.23
TOMS = {"high": (44, 0.35), "middle": (39, 0.0), "low": (35, -0.35)}


def mixed(*parts):
    """Sounds of any lengths, each with its gain, added together from the same start, stereo."""
    out = np.zeros((max(len(x) for x, _ in parts), 2))
    for x, gain in parts:
        out[: len(x)] += (s.pan(x, 0.0) if x.ndim == 1 else x) * gain
    return out


def wider(x, width):
    """A stereo sound with what differs between its ears `width` times as loud against what they share."""
    middle, side = (x[:, 0] + x[:, 1]) / 2, (x[:, 0] - x[:, 1]) / 2 * width
    return np.stack([middle + side, middle - side], axis=1)


def driven(x, amount=2.5, tone=3200):
    """A synth pushed through the waveshaper, its grit warm rather than fizzing."""
    return s.drive(x, amount, tone=tone, asym=0.1)


def cut(x, seconds):
    """`x` stopped after `seconds`, with a short fade."""
    out = x[: max(0, int(round(seconds * s.SR)))].copy()
    fade = min(len(out), int(0.03 * s.SR))
    out[len(out) - fade:] *= np.linspace(1, 0, fade)[:, None] if out.ndim == 2 else np.linspace(1, 0, fade)
    return out


def kick():
    """The kick: an electronic kick's body under a hard kick's beater, short, so four on the floor stays tight."""
    x = mixed((s.sample(PACK + "bd_gas.flac", seconds=0.3, release=0.08), 0.75), (s.punch_kick(0.9, 0.22), 0.45))
    return s.shelf(x, 2500, 4.0)


def snare():
    """The snare: an electronic snare's crack over a dry one and a burst of bright room, gated off within a fifth of
    a second, as the eighties' big snares were."""
    x = mixed((s.sample(PACK + "elec_hi_snare.flac", seconds=0.2, release=0.04), 0.7),
              (s.sample(PACK + "sn_generic.flac", seconds=0.2, release=0.04), 0.5), (s.gated_snare(0.9, 190, 0.19), 0.45))
    return cut(x, 0.21)


def tom(which):
    """The fuzz tom, `high`, `middle` or `low`, tuned, mono for Bus.add to pan."""
    note, _ = TOMS[which]
    return s.sample(PACK + "elec_fuzz_tom.flac", note=note, root=TOM_ROOT, seconds=0.45, release=0.15, mono=True)


def cymbal(seconds=1.6):
    """A cymbal: a splash's wash under an electronic cymbal's strike, dark, so it doesn't fizz."""
    x = mixed((s.sample(PACK + "drum_splash_soft.flac", seconds=seconds, release=seconds * 0.5), 0.8),
              (s.sample(PACK + "elec_cymbal.flac", release=0.2), 0.45))
    return s.lowpass(x, 9000)


def boom(seconds, rising=1.0):
    """The cinematic boom, from the air that swells up into its impact IMPACT seconds before it, that air `rising`
    times as loud; its low tail cut to `seconds` after the impact, and the rumble under 40 Hz a phone doesn't play
    taken out."""
    x = s.sample(PACK + "misc_cineboom.flac", seconds=IMPACT + seconds, attack=0.002, release=seconds * 0.7)
    gain = np.interp(np.arange(len(x)) / s.SR, [IMPACT - 0.01, IMPACT], [rising, 1.0])
    return s.highpass(x * gain[:, None], 40, order=3)


def glass(seconds, attack=0.3, release=1.0):
    """The glass hum on B major, held from where it has swelled in."""
    return s.held(PACK + "ambi_glass_hum.flac", seconds, note=59, root=GLASS_ROOT, start=1.2, end=6.0, cross=0.5,
                  attack=attack, release=release)


# ---------------------------------------------------------------- the synths

def pluck(note, bright):
    """A note of the arpeggio: a saw plucked dark and driven, so it growls a little as it snaps shut."""
    return driven(s.pluck(note, 0.85, 0.17, bright=bright), 2.2, 3600)


def growing(note, grown):
    """A note of the arpeggio in the lead-in, darker as it starts."""
    return pluck(note, 0.1 + 0.3 * grown)


def pad(notes, seconds, cutoff, attack, release):
    """The supersaw pad, driven and spread wide."""
    saws = s.supersaw(notes, seconds, voices=6, spread=16, cutoff=cutoff, attack=attack, release=release)
    return wider(driven(saws, 1.8, 5000), 1.5)


def stab(notes, cutoff):
    """A chord stab on an offbeat: the supersaw's chord, short and driven."""
    saws = s.supersaw(notes, 0.14, voices=5, spread=14, cutoff=cutoff, attack=0.003, release=0.05)
    return wider(driven(saws, 2.2, 5200), 1.4)


def lead(note, seconds, cutoff, glide, vibrato):
    """The riff's voice: a hard-sync lead whose bright peak falls through the harmonics as each note speaks, sliding
    in from the note before it, over two detuned saws an octave down; driven and spread wide, its grit kept under
    3 kHz so the ticks on screen carry over it."""
    sync = s.sync_lead(note, seconds, 0.9, glide=glide, cutoff=cutoff, vibrato=vibrato)
    saws = s.saw_lead(note - 12, seconds, 0.9, cutoff=cutoff * 0.7, detune=9)
    return wider(s.highpass(driven(mixed((sync, 0.8), (saws, 0.55)), 2.6, 2800), 150), 1.5)


def bass(root, velocity, bright):
    """A sixteenth of the bass sequence: two detuned saws driven into a growl, over the recorded hard bass."""
    sampled = s.sample(PACK + "bass_hard_c.flac", note=root, root=36, seconds=0.14, release=0.04, mono=True)
    saws = s.grit_bass(root, velocity, 0.13, bright=bright, grit=0.6)
    return s.lowpass(mixed((driven(sampled, 2.0, 2400) * velocity, 0.5), (saws, 0.9)), 4500)


def darksynth(sounds=theme.ui):
    theme.start(149)
    room = s.reverb(2.6, 0.65, 0.022)
    drums, low, pads, layer, arps, seq, lead_, fx, bed, drone = (s.Bus(theme.LENGTH) for _ in range(10))
    kicks = []
    beat_kick, beat_snare = kick(), snare()
    closed = s.sample(PACK + "hat_star.flac", mono=True)
    opened = s.sample(PACK + "hat_noiz.flac", seconds=0.22, release=0.12, mono=True)

    # The lead-in, on E and F sharp, the notes the held D major chord and Emaj9 share, on the arpeggio's pluck, over
    # a drone on E with F sharp above; the boom's air and a cymbal played backwards rise into the first hit. The
    # drone gives way to the bass sequence over the hit's first beat.
    theme.lead_in((arps, drums, bed, fx), kicks, room, [64, 66, 76, 78], [40, 52, 66], ARP * swell(0), ECHO * swell(0),
                  tone=growing)
    bed.duck(np.interp(np.arange(len(bed.dry)) / s.SR, [at(0), at(1)], [1.0, 0.0]))
    fx.add(at(0) - IMPACT, boom(1.2, rising=1.5), gain=0.25, wet=0.3)
    backwards = s.sample(PACK + "drum_splash_hard.flac", seconds=1.4, release=0.7, reverse=True)
    drums.add(at(0) - len(backwards) / s.SR, backwards, gain=0.12, wet=0.3)

    # The first frame lands as the kick under the deep kick and the boom. From it the recorded drone holds G sharp and
    # D sharp under everything, growing through the build, and the glass hum sings B major over Emaj9.
    drums.add(at(0), beat_kick, gain=0.5, wet=0.1)
    drums.add(at(0), s.deep_kick(0.85), gain=0.4, wet=0.12)
    kicks.append(at(0))
    pedal = s.held(PACK + "ambi_drone.flac", at(theme.BEATS) - at(0), note=56, root=DRONE_ROOT, cross=0.5, attack=0.4,
                   release=0.5)
    grow = np.interp(np.arange(len(pedal)) / s.SR, [0, at(S1) - at(0), at(DROP) - at(0), at(LAST) - at(0)],
                     [0.8, 0.8, 1.0, 0.9])
    drone.add(at(0), s.highpass(pedal * grow[:, None], 120), gain=0.22, wet=0.35)
    drone.add(at(0), s.highpass(glass(at(S1) - at(0) - 0.4, attack=0.25, release=0.5), 150), gain=0.26, wet=0.4)

    # The pads: the supersaw's, driven and wide, opening through the build; and the recorded pad, the cluster inside
    # each chord that has one.
    for name, first, length in CHORDS:
        _, voicing = VOICINGS[name]
        last = first == LAST
        seconds = 2.8 if last else length * theme.BEAT
        cutoff = 2600 if first >= DROP else opening(first, 0, S4, 1100, 2400)
        tone = pad(voicing, seconds, cutoff, attack=0.45 if first == 0 else 0.08, release=1.6 if last else 0.25)
        pads.add(at(first), theme.dying(tone, 1.3) if last else tone, gain=0.3 * swell(first), wet=0.45)
        if name in LAYER:
            under = s.held(PACK + "tbd_pad_4.flac", seconds, note=LAYER[name], root=PAD_ROOT, cross=0.3,
                           attack=0.4 if first == 0 else 0.08, release=1.6 if last else 0.25)
            under = s.highpass(theme.dying(under, 1.4) if last else under, 170)
            layer.add(at(first), under, gain=0.2 * swell(first), wet=0.45)

    # The arpeggio in sixteenths, climbing the chord a beat at a time an octave over the pads, with an echo a dotted
    # eighth later between its notes; dark under the hook, it opens through the build. From the fourth step the
    # sequencer runs over it in thirty-seconds, growing into the stop and full on the drop.
    for i, beat in enumerate(theme.playing(0, LAST, 0.25)):
        note = chord(beat)[2][RUN[round(beat * 4) % 4]]
        bright = 0.2 if beat < S1 else opening(beat, S1, STOP, 0.26, 0.6) if beat < DROP else 0.62
        tone = pluck(note, bright)
        arps.add(at(beat), tone, gain=ARP * swell(beat) * (1.0 if i % 2 == 0 else 0.82), pan_to=(-0.4, 0.4)[i % 2],
                 wet=0.3)
        arps.add(at(beat + 0.75), s.lowpass(tone, 2000), gain=ECHO * swell(beat), pan_to=(0.55, -0.55)[i % 2], wet=0.45)
    for i, beat in enumerate([b for b in theme.playing(S4, cue["endLine"], 0.125)]):
        note = chord(beat)[2][FAST[i % 8]] + 12
        grown = opening(beat, S4, STOP, 0.35, 0.8) if beat < DROP else 0.85
        seq.add(at(beat), s.seq_pluck(note, grown, 0.06, cutoff=700 + 500 * grown, accent=0.4 if i % 4 == 0 else 0.0),
                gain=0.2 * grown, pan_to=(0.3, -0.3)[(i // 2) % 2], wet=0.3)

    # The bass sequence in sixteenths from the first frame, muffled and held back under the hook and opening through
    # the steps and the build; the last root holds and dies away.
    for beat in theme.playing(0, LAST, 0.25):
        step = round(beat * 4) % 16
        root = chord(beat)[0]
        bright = (0.12 if beat < S1 else opening(beat, S1, S3, 0.25, 0.5) if beat < S3
                  else opening(beat, S3, STOP, 0.5, 0.75) if beat < DROP else 0.85)
        low.add(at(beat), bass(root + SEQUENCE[step], ACCENT[step % 4], bright),
                gain=0.4 * swell(beat) * (0.85 if beat < S1 else 1.2 if beat < S3 else 1.1 if beat < DROP else 1.0),
                wet=0.04)
    low.add(at(LAST), theme.dying(s.lowpass(s.grit_bass(44, 0.9, 3.0, bright=0.3, grit=0.5), 2200), 0.9), gain=0.42,
            wet=0.1)

    # The kit. The kick muffled as if through a wall until the third step, a little less so from the first; from the
    # third step the tight kit comes in with a cymbal: four on the floor, the gated snare on 2 and 4, closed hats in
    # sixteenths accented on the offbeat eighths, and from the drop open hats on the offbeats. The fuzz toms fall
    # from G sharp to B in sixteenths and then thirty-seconds into the stop, and into the last hit.
    for beat in range(1, S3):
        drums.add(at(beat), s.lowpass(beat_kick, 200 if beat < S1 else 400), gain=0.56, wet=0.02)
        kicks.append(at(beat))
    for beat in theme.playing(S3, LAST, 1):
        drums.add(at(beat), beat_kick, gain=0.52 * swell(beat) ** 0.5, wet=0.04)
        kicks.append(at(beat))
        if beat % 2 == 1 and not S4 + 2 <= beat < DROP:
            drums.add(at(beat), beat_snare, gain=0.46, wet=0.22)
    for beat in theme.playing(S3, LAST, 0.25):
        if S4 + 2 <= beat < DROP:
            continue
        accent = (0.45, 0.3, 1.0, 0.3)[round(beat * 4) % 4]
        drums.add(at(beat), closed, gain=0.36 * accent * swell(beat), pan_to=0.3, wet=0.05)
    for beat in theme.playing(DROP + 0.5, LAST, 1):
        drums.add(at(beat), opened, gain=0.13, pan_to=-0.3, wet=0.12)
    fill = [("high", 0.25), ("high", 0.25), ("middle", 0.25), ("middle", 0.25), ("middle", 0.125), ("low", 0.125),
            ("middle", 0.125), ("low", 0.125)]
    beat = S4 + 2
    for i, (which, step) in enumerate(fill):
        drums.add(at(beat), tom(which), gain=0.34 + 0.03 * i, pan_to=TOMS[which][1], wet=0.25)
        beat += step
    for beat, which in zip(np.arange(LAST - 1, LAST, 0.25), ("high", "middle", "middle", "low")):
        drums.add(at(beat), tom(which), gain=0.34, pan_to=TOMS[which][1], wet=0.25)

    # The riff on the sync lead and its saws, sliding from note to note, with an echo a dotted eighth later that stops
    # on the drop and the last hit so the held note resolves; from the drop to the end line, an octave up too.
    previous, end = None, 0.0
    for beat, note, beats in TUNE:
        last = beat >= LAST
        seconds = beats * theme.BEAT * 0.94
        glide = previous if abs(beat - end) < 1e-6 else None
        cutoff = 2600 if beat >= DROP else 2100
        tone = lead(note, seconds, cutoff, glide, 0.15 if beats >= 1 else 0.0)
        if last:
            tone = theme.dying(tone, 1.0)
        level = 0.34 * swell(beat) ** 0.5
        lead_.add(at(beat), tone, gain=level, wet=0.28)
        stop = DROP if beat < DROP else LAST if beat < LAST else theme.BEATS
        echo = cut(s.lowpass(tone.mean(axis=1), 1800), (stop - beat - 0.75) * theme.BEAT)
        lead_.add(at(beat + 0.75), echo, gain=level * 0.26, pan_to=-0.5, wet=0.5)
        if DROP <= beat < cue["endLine"]:
            lead_.add(at(beat), lead(note + 12, seconds, 3200, None, 0.1), gain=level * 0.22, wet=0.4)
        previous, end = note, beat + beats

    # The build: a cymbal as the full beat comes in, a riser through the fourth step, and into the drop the boom's air,
    # the dark woosh, a cymbal played backwards and the hit's own reverb, swelling up through the stop.
    drums.add(at(S3), cymbal(), gain=0.16, wet=0.35)
    hit = pad([n + 12 for n in VOICINGS["G#m9"][1]], 1.2, 3600, attack=0.02, release=0.6)
    fx.add(at(S4), s.riser(at(DROP) - at(S4), 300, 7000, curve=2.2), gain=0.06, wet=0.35)
    fx.add(at(STOP), s.swell_into(hit, at(DROP) - at(STOP), room), gain=0.18, wet=0.0)
    fx.add(at(DROP) - IMPACT, boom(3.5), gain=0.28, wet=0.25)
    woosh = s.sample(PACK + "ambi_dark_woosh.flac", seconds=WOOSH, release=0.02)
    fx.add(at(DROP) - WOOSH, s.highpass(woosh, 60), gain=0.22, wet=0.3)
    backwards = s.sample(PACK + "drum_splash_hard.flac", seconds=1.6, release=0.8, reverse=True)
    drums.add(at(DROP) - len(backwards) / s.SR, backwards, gain=0.18, wet=0.3)

    # The drop, and the last hit lighter: the kick under the deep kick, a trailer's low brass on G sharp, driven, and a
    # cymbal; the boom's impact on the drop, and again, smaller, on the last hit; the pad struck at full width on the
    # drop and the glass hum swelling in under it; from the drop the chord stabbed on the offbeats.
    brass = driven(s.braam([32, 39, 44, 47, 51], 2.6, 1.0), 1.6, 3000)
    for beat, weight in ((DROP, 1.0), (LAST, 0.8)):
        drums.add(at(beat), beat_kick, gain=0.55, wet=0.1)
        drums.add(at(beat), s.deep_kick(1.0), gain=0.55 * weight, wet=0.08)
        low.add(at(beat), theme.dying(brass, 1.1) if beat == LAST else brass, gain=0.22 * weight, wet=0.3)
        drums.add(at(beat), cymbal(2.4), gain=0.18 * weight, wet=0.35)
        kicks.append(at(beat))
    fx.add(at(LAST) - IMPACT, boom(3.4, rising=0.5), gain=0.24, wet=0.3)
    pads.add(at(DROP), hit, gain=0.16, wet=0.3)
    drone.add(at(DROP), s.highpass(glass(at(cue["endLine"] + 2) - at(DROP) - 0.4, attack=0.05, release=0.5), 150),
              gain=0.3, wet=0.4)
    drone.add(at(LAST), s.highpass(theme.dying(glass(2.6, attack=0.05, release=1.4), 1.6), 150), gain=0.36, wet=0.45)
    for beat in theme.playing(DROP + 0.5, LAST, 1):
        pads.add(at(beat), stab(chord(beat)[2], 3200), gain=0.1, wet=0.25)
    drums.add(at(cue["cta"]), cymbal(), gain=0.14, wet=0.35)
    for i, (note, p) in enumerate(zip(VOICINGS["G#m9"][1], (-0.4, -0.15, 0.15, 0.4))):
        arps.add(at(LAST + i / 4), pluck(note + 12, 0.45), gain=ARP * 0.9, pan_to=p, wet=0.55)

    theme.develop(fx, room, 68)
    sounds(fx)

    pump = s.sidechain(theme.LENGTH, kicks, depth=0.55, release=0.16)
    low.duck(1 - 0.62 * (1 - pump))
    pads.duck(1 - 0.45 * (1 - pump))
    layer.duck(1 - 0.3 * (1 - pump))
    arps.duck(1 - 0.25 * (1 - pump))
    seq.duck(1 - 0.2 * (1 - pump))
    drone.duck(1 - 0.4 * (1 - pump))
    theme.trim(drums, 40)
    theme.trim(low, 45)
    theme.trim(fx, 45)
    theme.trim(bed, 45)
    theme.trim(drone, 50)
    return [drums, low, pads, layer, arps, seq, lead_, fx, bed, drone], dict(room=room, wet=0.55, presence=4.0)


ARRANGEMENTS = {"darksynth": darksynth}
