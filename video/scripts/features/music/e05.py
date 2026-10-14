"""
E05's track (Presets and LUTs): a lush, cinematic deep-trance track in C sharp minor at 100 BPM, 8 bars and 19.2
seconds on the series' cue sheet, src/features/cues.json, which scripts/features-score.py plays under the episode
with its own sounds. Its first chord, C#m11, holds E and F sharp, which the opener's held D major chord has too: the
lead-in plays the arpeggio on E and F sharp over a drone on E and a glass rubbed on F sharp, and on the first hit the
bass falls a semitone from the opener's D to C sharp and the pads bring in G sharp, B and D sharp.

Where E12 climbs to the relative major and E04 walks up from the sixth, this one falls to the sixth and climbs
through the relative major to the seventh, the minor key's long trance progression: C#m11 under the hook, then
Amaj9, Emaj9 and B6/9 a bar each, every chord with its seventh or sixth and its ninth; then F#m9 and the dominant,
G#7(b9), into the drop on C#m9; on the end line Amaj9 to G#7(b9), and C#m9 on the last hit. The pads sit between G
sharp 3 and A4, every voice moving by step.

The riff moves by step: E held, then D sharp, C sharp, B and back to C sharp; then G sharp held, up through B to D
sharp, held, and C sharp. The answer plays its first bar again over B, then climbs A, B and C sharp over F sharp
minor and turns over B sharp onto D sharp, held through the stop, which rises to E on the drop; the head on the drop
is the riff's first bar; the closing phrase turns over B sharp, the leading note, to C sharp on the last hit.

deeptrance, its one arrangement, layers recorded sounds into our own synthesis, after the music the owner listens to
(11 October 2026), with the pads and the drone in front: Luftrum's pads, dronescapes and deep trance. The samples are
from Sonic Pi's pack (CC0), in the samples' folder outside the repository (synth.SAMPLES). A recorded drone pitched
to C sharp comes in on the first hit over a synth drone on its root and fifth, grows through the build, and holds
under the drop and the end line as a pedal, dying away with the last chord. The pads are a wide supersaw and a
string section, both swelling in on every chord, with a recorded pad pitched to each chord, an E major ninth chord
over C sharp and E and an A major ninth chord over A and F sharp, and a recorded glass hum, A major, pitched to each
major chord. The pulse is deep trance's: a bass rolling on the three sixteenths after each beat, pumping against the
kick, its filter opening and closing over every bar, and an arpeggio of a struck FM bell over a soft saw in
sixteenths with an echo a dotted eighth later, doubled an octave up from the drop. The riff is on a supersaw lead
with a struck glass an octave up at each note's start and an echo a dotted eighth and a beat later, doubled an
octave up from the drop. Until the third step the beat is a kick muffled as if through a wall, with synth hats from
the second; the recorded kit comes in with the third step: a kick over a deeper one, a clap of a snare and a snap on
2 and 4, closed hats in sixteenths, an open hat on the offbeats, a ride from the drop and soft toms tuned to E, C
sharp and G sharp falling into the stop. A cinematic boom lands on the first hit, its air rising into it with a dark
woosh on C sharp played backwards, and again, larger, on the drop with an impact, a landing's rumble, the choir on E
major over the C sharp, a crash and the series' sting, glass struck on C sharp, G sharp and D sharp; it comes again,
smaller, on the last hit.
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
CHORDS = [("C#m11", 0, 4), ("Amaj9", 4, 4), ("Emaj9", 8, 4), ("B6/9", 12, 4), ("F#m9", 16, 2), ("G#7(b9)", 18, 2),
          ("C#m9", 20, 4), ("Amaj9", 24, 2), ("G#7(b9)", 26, 2), ("C#m9", 28, 4)]

# Each chord: the bass's root, falling a third to A, up a fourth to E, down a fourth to B, then up to F sharp and G
# sharp and down a fifth to C sharp on the drop; and the pads' voicing, rootless between G sharp 3 and A4, its voices
# moving by step and keeping the colour notes: C sharp minor's ninth and eleventh, A's major seventh and ninth, E's
# major seventh and ninth, B's sixth and ninth, F sharp minor's ninth, G sharp's flat ninth over its third, B sharp.
VOICINGS = {
    "C#m11": (37, [52, 59, 63, 66]),
    "Amaj9": (33, [56, 59, 61, 64]),
    "Emaj9": (40, [56, 59, 63, 66]),
    "B6/9": (35, [56, 61, 63, 66]),
    "F#m9": (42, [57, 61, 64, 68]),
    "G#7(b9)": (44, [57, 60, 63, 66]),
    "C#m9": (37, [56, 59, 63, 64]),
}


def chord(beat):
    root, voicing = VOICINGS[theme.chord_at(beat, CHORDS)]
    return root, voicing, [n + 12 for n in voicing]


# The riff, [beat, note, beats] from where it starts: E held, D sharp, C sharp, B and C sharp; then G sharp held, B,
# D sharp held and C sharp. The answer climbs A, B and C sharp, turns over B sharp and holds D sharp through the stop;
# the head is the first bar; the closing phrase turns over B sharp to C sharp on the last hit.
MOTIF = [(0, 76, 1.5), (1.5, 75, 0.5), (2, 73, 1.0), (3, 71, 0.5), (3.5, 73, 0.5),
         (4, 68, 1.5), (5.5, 71, 0.5), (6, 75, 1.5), (7.5, 73, 0.5)]
ANSWER = MOTIF[:5] + [(4, 69, 1.0), (5, 71, 0.5), (5.5, 73, 0.5), (6, 72, 0.5), (6.5, 75, 1.5)]
HEAD = MOTIF[:5]
CLOSE = [(0, 76, 1.5), (1.5, 75, 0.5), (2, 72, 1.0), (3, 75, 0.5), (3.5, 72, 0.5), (4, 73, 4.0)]
TUNE = (theme.placed(S1, MOTIF) + theme.placed(S3, ANSWER) + theme.placed(DROP, HEAD)
        + theme.placed(cue["endLine"], CLOSE))

# The arpeggio's levels for a note and its echo, which the lead-in grows to.
ARP, ECHO = 0.3, 0.1
# Which of the chord's four notes each sixteenth of a beat plays: the lowest on the beat, then the top one, the
# second and the third.
ROLL = (0, 3, 1, 2)

# ---------------------------------------------------------------- the recorded sounds
# Samples from Sonic Pi's pack (CC0) in the samples' folder (synth.SAMPLES).
PACK = "sonic-pi/"
# Where misc_cineboom's impact falls, after the air that swells up into it.
IMPACT = 1.66
# ambi_drone hums C4 with its fifth and octave, a little sharp and beating; pitched down to C sharp 3.
DRONE_ROOT = 60.15
# ambi_glass_rub rings F sharp 5, 5 cents flat.
RUB_ROOT = 77.95
# ambi_dark_woosh rumbles round C sharp 2, 11 cents flat.
WOOSH_ROOT = 36.89
# tbd_pad_3 holds E flat major's ninth chord about E flat 3. Under each chord it plays the major ninth chord inside it:
# E major's (up a semitone) under C#m11, Emaj9, B6/9 and C#m9, and A major's (down a tritone) under Amaj9 and F#m9.
# G#7(b9) has none, so the pad leaves it to the synths.
PAD_ROOT = 51.03
LAYER = {"C#m11": 52, "Amaj9": 45, "Emaj9": 52, "B6/9": 52, "F#m9": 45, "C#m9": 52}
# ambi_glass_hum holds A major about A3, in tune: at A over A major, and pitched to E, B and G sharp over theirs.
GLASS = {"Amaj9": 57, "Emaj9": 52, "B6/9": 59, "G#7(b9)": 56}
# ambi_choir sings A flat major 45 cents sharp; down to E major, C sharp minor's seventh, over the drop's and the last
# hit's C sharp.
CHOIR = 68.45
# The toms: each one's sample, the note it was recorded at and the note it's tuned to (E, C sharp and G sharp, falling
# through C sharp minor), and where it sits, from the right to the left.
TOMS = {"high": ("drum_tom_hi_soft", 52.38, 52, 0.35), "middle": ("drum_tom_mid_soft", 48.12, 49, 0.0),
        "low": ("drum_tom_lo_soft", 43.54, 44, -0.35)}


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


def warmed(x, amount=1.6, tone=5000):
    """A synth pushed gently through the waveshaper, warm rather than gritty."""
    return s.drive(x, amount, tone=tone, asym=0.08)


def cut(x, seconds):
    """`x` stopped after `seconds`, with a short fade."""
    out = x[: max(0, int(round(seconds * s.SR)))].copy()
    fade = min(len(out), int(0.03 * s.SR))
    out[len(out) - fade:] *= np.linspace(1, 0, fade)[:, None] if out.ndim == 2 else np.linspace(1, 0, fade)
    return out


def kick():
    """The kick: a punchy kick's knock over a round, deeper one, brought forward so it carries on a phone."""
    x = mixed((s.sample(PACK + "bd_zome.flac", seconds=0.35, release=0.1), 0.7), (s.sample(PACK + "bd_haus.flac"), 0.6))
    return s.shelf(x, 2500, 4.0)


def clap():
    """The clap on 2 and 4: a snare's body under a snap, damped within a sixteenth and a half, its room from the
    reverb."""
    return mixed((s.sample(PACK + "sn_generic.flac", seconds=0.2, release=0.08), 0.6),
                 (s.sample(PACK + "perc_snap.flac", seconds=0.2, release=0.08), 0.55))


def tom(which):
    """A tom, `high`, `middle` or `low`, tuned, mono for Bus.add to pan."""
    name, root, note, _ = TOMS[which]
    return s.sample(PACK + f"{name}.flac", note=note, root=root, seconds=0.6, release=0.2, mono=True)


def boom(seconds, rising=1.0):
    """The cinematic boom, from the air that swells up into its impact IMPACT seconds before it, that air `rising`
    times as loud; its low tail cut to `seconds` after the impact, and the rumble under 40 Hz a phone doesn't play
    taken out."""
    x = s.sample(PACK + "misc_cineboom.flac", seconds=IMPACT + seconds, attack=0.002, release=seconds * 0.7)
    gain = np.interp(np.arange(len(x)) / s.SR, [IMPACT - 0.01, IMPACT], [rising, 1.0])
    return s.highpass(x * gain[:, None], 40, order=3)


def woosh(seconds):
    """The dark woosh on C sharp, played backwards so it swells into the moment it ends on, `seconds` long."""
    return s.highpass(s.sample(PACK + "ambi_dark_woosh.flac", seconds=seconds, attack=0.02, release=0.3, reverse=True), 50)


def choir(note, seconds=None, reverse=False):
    """The recorded choir's "ah" on a major chord rooted on `note`, or backwards, breathing in."""
    return s.sample(PACK + "ambi_choir.flac", note=note, root=CHOIR, seconds=seconds, release=0.3, reverse=reverse)


# ---------------------------------------------------------------- the synths

def bell(note, bright):
    """A note of the arpeggio: a struck FM bell over a soft saw plucked dark, so it rings and glows."""
    struck = s.fm(note, 0.32, 0.8, ratio=3.5, index=1.2 + 1.6 * bright, decay=0.08)
    soft = s.pluck(note, 0.7, 0.32, bright=0.2 + 0.5 * bright)
    return s.lowpass(0.6 * struck + 0.7 * soft, 6500)


def growing(note, grown):
    """A note of the arpeggio in the lead-in, darker as it starts."""
    return bell(note, 0.05 + 0.3 * grown)


def pad(notes, seconds, cutoff, attack, release):
    """The supersaw pad, warmed and spread wide."""
    saws = s.supersaw(notes, seconds, voices=7, spread=24, cutoff=cutoff, attack=attack, release=release)
    return wider(warmed(saws, 1.4, 6000), 1.6)


def section(notes, seconds, bright, attack, release):
    """The string section holding the chord, each voice a bowed section of its own, opening as it plays."""
    out = None
    for note in notes:
        tone = s.strings(note, seconds, bright=bright, attack=attack, release=release, voices=5)
        out = tone if out is None else out + tone
    return out / len(notes) ** 0.5


def lead(note, seconds, cutoff, vibrato):
    """The riff's voice: a supersaw lead, as trance's, with a vibrato on its long notes, warmed and spread wide, its
    top kept under 3.5 kHz so the clicks and ticks on screen carry over it."""
    saws = s.supersaw([note], seconds, voices=5, spread=14, cutoff=cutoff, attack=0.01, release=0.18)
    sung = s.saw_lead(note, seconds, 0.9, cutoff=cutoff * 0.9, detune=6, vibrato=vibrato)
    return wider(s.lowpass(warmed(mixed((saws, 0.9), (sung, 0.6)), 1.5, 3500), 3500), 1.4)


def bass(root, velocity, bright):
    """A note of the rolling bass: the recorded woody bass over two warm saws, a sixteenth long."""
    sampled = s.sample(PACK + "bass_woodsy_c.flac", note=root, root=35.94, seconds=0.14, release=0.04, mono=True)
    saws = s.grit_bass(root, velocity, 0.13, bright=bright, grit=0.25)
    return s.lowpass(mixed((sampled * velocity, 0.55), (saws, 0.9)), 3800)


def deeptrance(sounds=theme.ui):
    theme.start(151)
    room = s.reverb(3.2, 0.8, 0.028)
    drums, low, pads, layer, arps, lead_, fx, bed, drone = (s.Bus(theme.LENGTH) for _ in range(9))
    kicks = []
    beat_kick, beat_clap = kick(), clap()
    closed = s.sample(PACK + "hat_psych.flac", seconds=0.12, release=0.06, mono=True)
    opened = s.sample(PACK + "hat_zan.flac", seconds=0.22, release=0.12, mono=True)
    ride = s.sample(PACK + "ride_via.flac", seconds=1.2, release=0.6, mono=True)
    crash = s.sample(PACK + "drum_splash_soft.flac", release=0.5)

    # The lead-in, on E and F sharp, the notes the held D major chord and C#m11 share, on the arpeggio's bell, over a
    # drone on E and a glass rubbed on F sharp, which carries on over the hook as C#m11's eleventh and fades; the
    # boom's air and the dark woosh rise into the first hit. The drone gives way to the bass as it comes in with the
    # first step.
    theme.lead_in((arps, drums, bed, fx), kicks, room, [64, 66, 76, 78], [40, 52], ARP * swell(0), ECHO * swell(0),
                  tone=growing)
    bed.duck(np.interp(np.arange(len(bed.dry)) / s.SR, [at(0), at(1), at(S1), at(S1 + 1)], [1.0, 0.45, 0.45, 0.0]))
    rub = s.held(PACK + "ambi_glass_rub.flac", at(S1) - at(-theme.LEAD_IN), note=66, root=RUB_ROOT, cross=0.5,
                 attack=theme.PRE * 0.8, release=1.6)
    drone.add(at(-theme.LEAD_IN), s.lowpass(rub, 4000), gain=0.16, wet=0.5)
    fx.add(at(0) - IMPACT, boom(2.4, rising=1.5), gain=0.3, wet=0.3)
    rising = woosh(1.8)
    fx.add(at(0) - len(rising) / s.SR, rising, gain=0.2, wet=0.3)

    # The first frame lands as the deep kick under the boom and an impact. The recorded drone comes in on C sharp over
    # a synth drone on its root and fifth, and grows from the first step through the build, swelling on through the
    # stop into the drop; it holds under the drop and the end line and dies away with the last chord.
    drums.add(at(0), s.deep_kick(0.9), gain=0.5, wet=0.12)
    fx.add(at(0), s.sample(PACK + "perc_impact1.flac", release=0.3), gain=0.2, wet=0.35)
    seconds = at(LAST + 2) - at(0)
    bedded = s.held(PACK + "ambi_drone.flac", seconds, note=49, root=DRONE_ROOT, cross=0.6, attack=0.4, release=1.6)
    under = s.drone([37, 44], seconds, cutoff=380, release=1.6, attack=0.5)
    grow = np.interp(np.arange(len(bedded)) / s.SR, [at(b) - at(0) for b in (0, S1, S3, DROP, cue["endLine"], LAST,
                                                                             LAST + 2)],
                     [0.62, 0.72, 0.88, 1.0, 0.75, 0.6, 0.35])
    drone.add(at(0), s.highpass(bedded, 90) * grow[:, None], gain=0.34, wet=0.4)
    drone.add(at(0), under[: len(grow)] * grow[:, None], gain=0.42, wet=0.25)

    # The pads: the supersaw's, warmed and wide, opening through the build; the string section under it; the recorded
    # pad, the major ninth chord inside each chord; and the glass hum on each major chord.
    for name, first, length in CHORDS:
        _, voicing = VOICINGS[name]
        last = first == LAST
        seconds = 3.0 if last else length * theme.BEAT
        cutoff = 2800 if first >= DROP else opening(first, 0, S4, 1200, 2400)
        attack = 0.35 if first == 0 else 0.25
        release = 1.8 if last else 0.4
        tone = pad(voicing, seconds, cutoff, attack=attack, release=release)
        pads.add(at(first), theme.dying(tone, 1.4) if last else tone, gain=0.16 * swell(first), wet=0.55)
        bowed = section(voicing, seconds, (0.25, 0.55) if first < DROP else (0.45, 0.7), attack=attack + 0.2,
                        release=release)
        pads.add(at(first), theme.dying(bowed, 1.4) if last else bowed, gain=0.28 * swell(first), wet=0.6)
        if name in LAYER:
            sampled = s.held(PACK + "tbd_pad_3.flac", seconds, note=LAYER[name], root=PAD_ROOT, cross=0.3,
                             attack=0.5 if first == 0 else 0.12, release=release)
            sampled = s.highpass(theme.dying(sampled, 1.5) if last else sampled, 150)
            layer.add(at(first), sampled, gain=0.34 * swell(first), wet=0.5)
        if name in GLASS:
            hum = s.sample(PACK + "ambi_glass_hum.flac", note=GLASS[name], root=57, seconds=seconds + 0.6, attack=0.3,
                           release=0.9)
            layer.add(at(first), s.highpass(hum, 180), gain=0.2 * swell(first), wet=0.6)

    # The arpeggio in sixteenths, the lowest note on each beat and the others rolling over it, with an echo a dotted
    # eighth later; darker under the hook, it opens through the build.
    for i, beat in enumerate(theme.playing(0, LAST, 0.25)):
        note = chord(beat)[2][ROLL[round(beat * 4) % 4]]
        bright = 0.25 if beat < S1 else opening(beat, S1, STOP, 0.3, 0.75) if beat < DROP else 0.8
        tone = bell(note, bright)
        arps.add(at(beat), tone, gain=ARP * swell(beat) * (1.0 if i % 4 == 0 else 0.78), pan_to=(-0.4, 0.4)[i % 2],
                 wet=0.35)
        arps.add(at(beat + 0.75), s.lowpass(tone, 2200), gain=ECHO * swell(beat), pan_to=(0.55, -0.55)[i % 2], wet=0.5)
        if DROP <= beat < cue["endLine"]:
            arps.add(at(beat), bell(note + 12, 0.6), gain=ARP * 0.4, pan_to=(0.5, -0.5)[i % 2], wet=0.4)

    # The bass: the root held under the hook, swelling in over the hit's first beat; then rolling on the three
    # sixteenths after each beat from the first step, its filter opening and closing over every bar and opening through
    # the build; the last root dies away.
    held = s.grit_bass(37, 0.8, at(S1) - at(0) - 0.05, bright=0.12, grit=0.2)
    held = held * np.clip(np.arange(len(held)) / s.SR / theme.BEAT, 0, 1)
    low.add(at(0), theme.dying(s.lowpass(held, 1600), 2.4), gain=0.3, wet=0.08)
    for beat in theme.playing(S1, LAST, 1):
        root = chord(beat)[0]
        base = opening(beat, S1, STOP, 0.18, 0.45) if beat < DROP else 0.55
        for offset, velocity in ((0.25, 0.8), (0.5, 0.68), (0.75, 0.9)):
            if theme.STOP <= beat + offset < DROP:
                continue
            breathe = 0.5 + 0.5 * np.sin(2 * np.pi * ((beat + offset) % 4) / 4 - np.pi / 2)
            low.add(at(beat + offset), bass(root, velocity, base + 0.2 * breathe), gain=0.6 * swell(beat), wet=0.04)
    low.add(at(LAST), theme.dying(s.lowpass(s.grit_bass(37, 0.9, 3.0, bright=0.3, grit=0.3), 2000), 0.9), gain=0.38,
            wet=0.1)

    # Until the third step the beat is a kick muffled as if through a wall, on every beat, opening a little through the
    # first two steps, with synth hats on the offbeats from the second. With the third step the recorded kit comes in:
    # four on the floor, the clap on 2 and 4, closed hats in sixteenths accented on the offbeats, an open hat on the
    # offbeats, and from the drop a ride on every beat; soft toms fall from E to G sharp into the stop, and into the
    # last hit.
    for beat in theme.playing(1, S3, 1):
        muffle = 200 if beat < S1 else opening(beat, S1, S3, 240, 420)
        drums.add(at(beat), s.lowpass(beat_kick, muffle), gain=0.48, wet=0.03)
        kicks.append(at(beat))
    for beat in theme.playing(S2 + 0.5, S3, 1):
        drums.add(at(beat), s.hat(0.7), gain=0.07, pan_to=0.3, wet=0.08)
    for beat in theme.playing(S3, LAST, 1):
        drums.add(at(beat), beat_kick, gain=0.62 * swell(beat) ** 0.5, wet=0.04)
        kicks.append(at(beat))
        if beat % 2 == 1 and not S4 + 2 <= beat < DROP:
            drums.add(at(beat), beat_clap, gain=0.4, wet=0.32)
    for beat in theme.playing(S3, LAST, 0.25):
        if S4 + 2 <= beat < DROP:
            continue
        accent = (0.4, 0.28, 1.0, 0.28)[round(beat * 4) % 4]
        drums.add(at(beat), closed, gain=0.34 * accent * swell(beat), pan_to=0.3, wet=0.06)
    for beat in theme.playing(S3 + 0.5, LAST, 1):
        if S4 + 2 <= beat < DROP:
            continue
        drums.add(at(beat), opened, gain=0.12 * swell(beat), pan_to=-0.3, wet=0.15)
    for beat in theme.playing(DROP, LAST, 1):
        drums.add(at(beat), ride, gain=0.08, pan_to=0.4, wet=0.2)
    fill = [("high", 0.25), ("high", 0.25), ("middle", 0.25), ("middle", 0.25), ("low", 0.125), ("middle", 0.125),
            ("low", 0.125), ("low", 0.125)]
    beat = S4 + 2
    for i, (which, step) in enumerate(fill):
        drums.add(at(beat), tom(which), gain=0.4 + 0.03 * i, pan_to=TOMS[which][3], wet=0.3)
        beat += step
    for beat, which in zip(np.arange(LAST - 1, LAST, 0.25), ("high", "middle", "middle", "low")):
        drums.add(at(beat), tom(which), gain=0.36, pan_to=TOMS[which][3], wet=0.3)

    # The riff on the supersaw lead, a struck glass an octave up at each note's start, with an echo a dotted eighth and
    # a beat later that stops on the drop and the last hit so the held note resolves; doubled an octave up from the
    # drop to the end line.
    for beat, note, beats in TUNE:
        last = beat >= LAST
        seconds = beats * theme.BEAT * 0.94
        cutoff = 2600 if beat >= DROP else 2100
        tone = lead(note, seconds, cutoff, 0.16 if beats >= 1 else 0.0)
        if last:
            tone = theme.dying(tone, 1.0)
        level = 0.3 * swell(beat) ** 0.5
        lead_.add(at(beat), tone, gain=level, wet=0.35)
        lead_.add(at(beat), s.glass(note + 12, 1.2, 0.6), gain=level * 0.22, pan_to=0.15, wet=0.5)
        stop = DROP if beat < DROP else LAST if beat < LAST else theme.BEATS
        for later, cut_at, share, p, wet in ((0.75, 1800, 0.3, -0.55, 0.5), (1.0, 1300, 0.14, 0.55, 0.6)):
            echo = cut(s.lowpass(tone.mean(axis=1), cut_at), (stop - beat - later) * theme.BEAT)
            lead_.add(at(beat + later), echo, gain=level * share, pan_to=p, wet=wet)
        if DROP <= beat < cue["endLine"]:
            lead_.add(at(beat), lead(note + 12, seconds, 3200, 0.1), gain=level * 0.28, wet=0.4)

    # The build: a crash as the recorded kit comes in, a riser through the fourth step, and into the drop the air
    # before the boom's impact, the dark woosh and a crash played backwards, the choir breathing in the chord it sings
    # on the drop and the hit's own reverb, swelling up through the stop.
    drums.add(at(S3), crash, gain=0.16, wet=0.35)
    hit = pad([n + 12 for n in VOICINGS["C#m9"][1]], 1.4, 3600, attack=0.02, release=0.8)
    fx.add(at(S4), s.riser(at(DROP) - at(S4), 300, 6500, curve=2.2), gain=0.06, wet=0.35)
    fx.add(at(STOP), s.swell_into(hit, at(DROP) - at(STOP), room), gain=0.18, wet=0.0)
    fx.add(at(DROP) - IMPACT, boom(3.6), gain=0.36, wet=0.25)
    rising = woosh(2.4)
    fx.add(at(DROP) - len(rising) / s.SR, rising, gain=0.26, wet=0.3)
    backwards = s.sample(PACK + "drum_splash_soft.flac", seconds=1.6, release=0.8, reverse=True)
    drums.add(at(DROP) - len(backwards) / s.SR, backwards, gain=0.2, wet=0.3)
    breath = choir(64, 1.2, reverse=True)
    layer.add(at(DROP) - len(breath) / s.SR, breath, gain=0.22, wet=0.5)

    # The drop: the boom and the deep kick under the beat's kick, an impact, the pad struck at full width, the choir on
    # E major over the C sharp and a crash; the choir again on A major on the end line, a crash on the call to action,
    # and the last hit, with the boom again, smaller, and the arpeggio's last chord rising after it into the room.
    for beat, weight in ((DROP, 1.0), (LAST, 0.8)):
        drums.add(at(beat), beat_kick, gain=0.55, wet=0.1)
        drums.add(at(beat), s.deep_kick(1.0), gain=0.5 * weight, wet=0.08)
        kicks.append(at(beat))
        fx.add(at(beat), s.sample(PACK + "perc_impact1.flac", release=0.3), gain=0.2 * weight, wet=0.35)
        layer.add(at(beat), choir(64), gain=0.3 * weight, wet=0.5)
        drums.add(at(beat), crash, gain=0.24 * weight, wet=0.35)
    fx.add(at(LAST) - IMPACT, boom(3.4, rising=0.5), gain=0.26, wet=0.3)
    pads.add(at(DROP), hit, gain=0.26, wet=0.3)
    landing = s.sample(PACK + "ambi_lunar_land.flac", seconds=4.0, attack=0.01, release=2.0)
    fx.add(at(DROP), s.highpass(landing, 250), gain=0.24, wet=0.45)
    layer.add(at(cue["endLine"]), choir(69, 1.3), gain=0.16, wet=0.55)
    drums.add(at(cue["cta"]), crash, gain=0.15, wet=0.35)
    for i, (note, p) in enumerate(zip(VOICINGS["C#m9"][1], (-0.4, -0.15, 0.15, 0.4))):
        arps.add(at(LAST + i / 4), bell(note + 12, 0.5), gain=ARP * 0.9, pan_to=p, wet=0.6)

    theme.develop(fx, room, 73)
    sounds(fx)

    pump = s.sidechain(theme.LENGTH, kicks, depth=0.55, release=0.17)
    low.duck(1 - 0.65 * (1 - pump))
    pads.duck(1 - 0.4 * (1 - pump))
    layer.duck(1 - 0.3 * (1 - pump))
    arps.duck(1 - 0.25 * (1 - pump))
    drone.duck(1 - 0.35 * (1 - pump))
    theme.trim(drums, 40)
    theme.trim(low, 45)
    theme.trim(fx, 45)
    theme.trim(bed, 45)
    theme.trim(drone, 50)
    return [drums, low, pads, layer, arps, lead_, fx, bed, drone], dict(room=room, wet=0.55, presence=4.0)


ARRANGEMENTS = {"deeptrance": deeptrance}
