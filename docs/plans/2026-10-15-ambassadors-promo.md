# The ambassadors promo

The recruitment reel and carousel for Redlamp's ambassador programme (DEC-86): ten founding photographers who help decide what Redlamp builds next, picking one feature a quarter from the owner's shortlist, and whose edits are shown with their name. The programme, its terms and its phases are in the private social repository (`plans/2026-10-15-ambassadors.md`); the carousel's visual system is in its marketing library (`marketing/campaigns/ambassadors/`). Made in the promo studio (`.cursor/skills/redlamp-promo-studio/SKILL.md`), and posted through the social room.

The reel is drawn in pixel art, in the look of the feature videos (the owner, 15 October 2026). It replaces a photographic reel this document first described, and a first pixel cut the owner watched twice and couldn't tell what it was about; both are in this file's history. At his request the reel tells the programme in four acts, in his order: what this is, why it matters, why Redlamp needs you, how to apply. Its script and words were written by domain experts, each a separate agent: a short-form video scriptwriter wrote the concept and the beat sheet, a copywriter who has recruited photographers for ambassador programmes wrote every word, and an independent copy editor who wrote none of it reviewed them. Their files are in the social repository's `work/ambassadors/pixel-reel/` (`script.md`, `copy-v2.md`, `copy-review-4.md`, with the earlier passes beside them). The owner approved the cut on 15 October 2026, and its posts are packaged in the social repository's `reels/ambassadors/`.

## Brief

| Row | What it says |
| --- | --- |
| Goal | Applications to the ambassador programme at redlamp.app/join: none on 15 October 2026 (the form isn't open yet); 30 by the open call's close, three weeks after it opens. |
| Audience | Photographers on the Mac who edit raw and show their edits: Lightroom users, people who follow Fujifilm-style recipes, and the people already editing in Redlamp. |
| Platforms | 9:16 for Instagram Reels and TikTok; a 4:5 carousel for the Instagram feed. |
| Length | 8 bars at 100 BPM (18 frames a beat at 30 fps): 19.2 s, the feature videos' episode without their 10 s opener. |
| The one message | Help decide what Redlamp builds next, and have your edits shown, with your name. |
| The ask | Edit a photo in Redlamp, then apply with it at redlamp.app/join. |
| Tone | The feature videos': simple and direct words over a colourful pixel-art editor, and dark synthwave. What happens can be playful; the words stay plain. |
| Must keep | The brand's rules (the lamp's red the only red, with a source; one red light per picture; no bright point in the lens); the social room's copy rules; claims only from the README, the programme and the site's AI disclosure; no count of places or ambassadors that isn't true for as long as the reel stays up. |
| Success | Applications in the ambassadors room 48 hours and 7 days after each post, against the days before; visits to /ambassadors (Vercel Analytics); the posts' views, saves and shares from the social room's analyst. |

## Concept

The four acts, each legible with the sound off:

1. **What this is (bar 1, 0.0 to 2.4 s):** BECOME A REDLAMP / AMBASSADOR over the lamp warming in the dark, the opener's first bar re-timed to the reel's grid. The programme is named on the first frame, in the largest type on screen, and the cover is every episode's: the hook over the lamp at its warmest.
2. **Why it matters (bars 2 and 3, 2.4 to 7.2 s):** the lamp rises into the header's mark (REDLAMP · AMBASSADORS) as a roadmap fills the stage, and a row lifts as YOUR PICK under PICK WHAT'S NEXT. Then a street at dusk comes up out of white as a post, the way a print comes up in the developer, and a credit strip lands with @YOUR.HANDLE under YOUR EDITS SHOWN.
3. **Why Redlamp needs you (bars 4 and 5, 7.2 to 12.0 s):** a roll of film running off both edges of the stage, every frame dark but one, a person behind a laptop, under FREE RAW EDITOR / RUN BY ONE PERSON, as the music thins. On the drop the roll fills with drawn photographers, quirky and fun, one frame a sixteenth, and one frame stays empty with the default profile picture, which a white marker rings, under IT NEEDS YOUR / EDITS AND IDEAS.
4. **How to apply (bars 6 to 8, 12.0 to 19.2 s):** the editor, where the same street is edited, under EDIT A PHOTO / IN REDLAMP; then APPLY AT / REDLAMP.APP/JOIN over the lamp lit, which dissolves into the wall the reel loops back to.

Asked what it's about after the first two seconds, a viewer would say "Redlamp is looking for ambassadors"; watched muted to the end, one sentence an act. The faces were the owner's own idea; the strips run off the stage's edges, and no hook has a number in it, so nothing invites counting the faces as places taken. The faces and the person at the laptop are drawn characters, not real people or ambassadors. RUN BY ONE PERSON, rather than BY ONE PERSON, keeps the line true beside the site's AI disclosure, which says agents write the code and the owner directs the work.

## Hooks

Each is a prop of the composition (`hook`), on screen from frame 0 to frame 71 over the lamp warming, with its own cover (frame 71) and its own first sentence in the alt text. Every hook names the programme on the first frame.

| ID | Hook | Why |
| --- | --- | --- |
| `become` | BECOME A REDLAMP / AMBASSADOR | Leads: what this is, in the plainest words, naming Redlamp; it matches the page's title |
| `say` | AMBASSADORS HAVE / A SAY IN REDLAMP | The trial reel's: what this is and what it gives |
| `wanted` | REDLAMP NEEDS / AMBASSADORS | A spare: pairs with the faces, but to a stranger can read as a paid brand deal |
| `credit` | AMBASSADORS GET / THEIR EDITS SHOWN | A spare: leaves the name Redlamp to the header at 2.4 s |
| `photographers` | PHOTOGRAPHERS, / BE AN AMBASSADOR | A spare: leaves the name Redlamp to the header at 2.4 s |

## Script

8 bars at 100 BPM, in F minor; a beat is 0.6 s. The cues are in `video/src/ambassadors/cues.json`, which the frames and the score both read. At most two lines are on screen at once, counting a caption line or a word in the picture the story needs read (YOUR PICK, the handle).

| Beat | Time | Act | Picture | Words on screen | Sound |
| --- | --- | --- | --- | --- | --- |
| 0 | 0.0 s | 1 | The dark wall; the lamp comes in over 14 frames and warms through the bar | The hook | A deep hit with its sub, a drone on F, a pad swelling with the lamp, a muffled kick on each beat, the arpeggio growing out of nothing from beat 2 |
| 4 | 2.4 s | 2 | The lamp rises into the header's mark as the roadmap develops in, filling the stage: four unnamed rows, drawn for rows that could be on January's shortlist (UX-38, UX-35, UX-41, UX-37) | PICK WHAT'S NEXT | The first hit: kick, bass and arpeggio, in half time; air rushing up with the lamp |
| 5.5 to 6 | 3.3 to 3.6 s | 2 | The pointer presses the second row; on 6 it lifts with a shadow and a gold rim | + YOUR PICK, on the row | The press; the release and a two-note lift |
| 8 | 4.8 s | 2 | The stage turns into a post, whose print comes up out of paper white into the street | YOUR EDITS SHOWN | The full beat and the riff; the series' glass sting on the develop, and the developer's wash |
| 10 | 6.0 s | 2 | The credit strip slides up and lands: the Redlamp mark in white and the handle | + @YOUR.HANDLE, on the strip | A soft landing |
| 12 | 7.2 s | 3 | The roll, two strips of film running off both edges, every frame dark but the maker's, which comes up behind his laptop | FREE RAW EDITOR / RUN BY ONE PERSON | A shutter; the music thins to the drone, a muffled kick and the riff's first notes |
| 14 to 16 | 8.4 to 9.6 s | 3 | (held); the stop on 15.5 | (held) | A riser and a snare roll doubling into the stop |
| 16 | 9.6 s | 3 | **The drop:** the dark frames come up one a sixteenth to 18, each flashing white: eight photographers, two more half hidden at the edges, and the viewer's frame with the default profile picture | IT NEEDS YOUR / EDITS AND IDEAS | The loudest bar: the boom, the 808, the low brass on F, the choir and a crash; a shutter for each frame |
| 19 | 11.4 s | 3 | A white marker rings the viewer's frame | (held) | A marker's squeak |
| 20 | 12.0 s | 4 | The editor: the street as opened, its histogram, the Basic meters, the level; the pointer drags Exposure to +1.00, then Vibrance to +40 | EDIT A PHOTO / IN REDLAMP | The groove holds and the closing phrase begins; a press, two ticks and a release for each slider |
| 24 | 14.4 s | 4 | The end card: the lamp comes on, its light spreading in six steps; the address above it | APPLY AT / REDLAMP.APP/JOIN | A switch, a low swell and a soft crash, over C7(b9) |
| 28 | 16.8 s | 4 | The lamp's light blooms out a step and settles back | (held) | The last hit on F, with a smaller boom |
| 30 to 32 | 18.0 to 19.2 s | 4 | The picture dissolves into the wall, gone by the last frame, which is frame 0's wall | The address, dissolving | The last chord dies away |

## Formats

- **9:16, 1080 × 1920**, for Reels and TikTok: the series' 216 × 384 grid shown four times the size in its margin, so the picture keeps clear of the sides tall phones crop, and every word clear of the apps' controls (`world.covered`). The frames script warns about any word in a covered zone; it warns about none.
- **The cover** is frame 71, the hook over the lamp at its warmest, inside the middle 3:4 the profile grid shows.

## Sound

Its own track, dark synthwave in F minor at 100 BPM (`video/scripts/ambassadors/music.py`): E12's darksynth carried to F minor and to the four acts, recorded drums, drones, pads, a choir and impacts from Sonic Pi's pack (CC0) layered over our own synths. Fm6/9 under the hook, Abmaj7#11 under the roadmap, Ebmaj9 and Dbmaj7#11 under the print; Dbmaj7#11 through the breakdown, then Dm7(b5) and C7(b9) into the drop on Fm9; Dbmaj7#11 and Ebmaj9 under the editor, C7(b9) under the address, and Fm9 on the last hit. The reel's sounds on screen (`video/scripts/ambassadors-score.py`) are the series' presses, ticks, releases and landing, and its own: the lamp's rush of air, the row's lift, the developer's wash, the shutter, the marker and the switch, 26 in all, each on its picture's beat.

Measured on 15 October: −14.0 LUFS integrated with a true peak of −1.5 dBFS, as the platforms' meter reads it, and −14.1 LUFS in the posted files; by bar, −17.4 LUFS under the hook, −15.2, −13.5 with the print, −16.0 through the breakdown, −11.2 on the drop, −13.6, −14.7 and −17.3 for the last chord; 6.1% of the energy under 60 Hz.

## How it's built

In `video/`, beside the feature videos and on their shared pieces (`scripts/features/world.py`):

- `src/ambassadors/cues.json`, the cue sheet; `src/ambassadors/copy.json`, every word, so the words change without touching a scene.
- `scripts/ambassadors/reel.py`, the board: `frame(c, beat, hook)` draws any moment, `sounds()` lists each sound on screen, `PANELS` the storyboard's eight.
- `scripts/ambassadors/music.py`, the track.
- `scripts/ambassadors-frames.py` draws every frame of every hook into `public/ambassadors/frames/` (about 15 s; the hooks share their frames from the first hit on); `scripts/ambassadors-score.py` writes `public/ambassadors/score.wav` with its level for the storyboard and a cue sheet for `scripts/score-report.py`; `scripts/ambassadors-board.py` writes the storyboard sheet, each hook's cover and the post into `out/ambassadors/`.
- `src/ambassadors/AmbassadorsReel.tsx`, the composition, in Studio's Ambassadors folder, with `hook`, `score` and `guides` props.

```bash
npm run ambassadors-frames && npm run ambassadors-score
python3 scripts/ambassadors-board.py
npm run studio   # Ambassadors › AmbassadorsReel
```

## The carousel

Seven slides at 4:5, made by `marketing/campaigns/ambassadors/build.py` (`carousel`). Every photo is Redlamp's render of the owner's raw (the colour hunt's renders, `work/colour-hunt/prototype/tiles/`), so EDITED IN REDLAMP is true.

1. **Cover:** an edit with the credit strip. BECOME A REDLAMP / AMBASSADOR.
2. **The pick:** the roadmap pick, YOUR PICK on the lifted row. PICK WHAT REDLAMP / BUILDS NEXT. "Each quarter, ambassadors pick one feature from a shortlist of my roadmap, and I build it next."
3. **The credit:** an edit with the credit strip. YOUR EDITS ON / REDLAMP'S FEED. "Always with your name and a link to you."
4. **Posts made for you:** a raw as Redlamp opens it beside the same raw in a camera recipe. POSTS MADE / FOR YOU. "Send me a raw and its edit, and I send back a before-and-after carousel and reel to post as your own."
5. **Founding places:** the contact sheet, ten frames. 10 FOUNDING / AMBASSADORS. "The first ten are listed on redlamp.app as founding ambassadors, for good."
6. **What I ask:** ONE EDIT / A MONTH. "Send me one edit a month, and tell me what gets in your way. It's unpaid, and needs an Apple Silicon Mac with macOS 26 or later."
7. **The ask:** APPLY AT / REDLAMP.APP/JOIN. "Edit a photo in Redlamp, then apply with it."

## Post copy

The posts, as packaged in the social repository's `reels/ambassadors/` (`caption.txt`, `caption-b.txt`, `alt.txt`, `alt-b.txt`, `post.txt`).

**The reel, on Instagram and TikTok**, in the copy rules' order, with the ambassadors' call to action in place of the standard `cta`:

> I'm looking for photographers to be Redlamp's ten founding ambassadors, an unpaid role with a say in what I build. Each quarter, they pick one feature from a shortlist of my roadmap for me to build next, and I show their edits here with their name.
>
> Redlamp is a free raw photo editor for Mac, with Lightroom's layout and shortcuts.
> Edit a photo in Redlamp, then apply with it at redlamp.app/join (link in bio). Ambassadors send me one edit a month. It's unpaid, and they get no early builds or fixes first. Your photos stay yours, and you don't need a lot of followers to apply.
> Needs an Apple Silicon Mac with macOS 26. It's in early development.
>
> Redlamp isn't affiliated with Adobe.
>
> #photoediting #rawediting #editbreakdown #macphotography #lightroomalternative

**The trial reel**, on Instagram, the same with this first sentence:

> I'm looking for photographers who edit raw on a Mac to be Redlamp's ten founding ambassadors, an unpaid role with a say in what I build.

**Audio name:** Redlamp theme: Ambassadors, on both platforms.

**The carousel:** the reel's caption, with "Swipe for what ambassadors get and what I ask." after the first sentence.

**X** (277 characters as X counts them), after the third copy review:

> I'm looking for photographers to be the ten founding ambassadors of Redlamp, my free raw editor for the Mac. Each quarter you'd pick one feature I build next, and I'd show your edits with your name. It's unpaid. Apply with a photo you edited in Redlamp: https://redlamp.app/join

**LinkedIn**, after the third copy review:

> I'm looking for photographers to be Redlamp's ten founding ambassadors. Redlamp is a free, open-source raw editor for the Mac.
>
> Ambassadors propose features and recommend what to build next, in a monthly call with me and in their channel. Each quarter, they also pick one feature from a shortlist of my roadmap, and I build it next. I show their edits on Redlamp's accounts and site, with their name.
>
> It's unpaid, and ambassadors don't get early builds or fixes first. It needs an Apple Silicon Mac with macOS 26 or later, and Redlamp is in early development.
>
> To apply, edit a photo in Redlamp and send it with your application: https://redlamp.app/join

**Alt text (the reel, `become`):** Pixel art of Redlamp's lamp warming in the dark under the words Become a Redlamp ambassador. Its light rises into a header reading Redlamp, Ambassadors, as a roadmap of four rows fills the frame, each a small icon with no name, under the words Pick what's next, and the pointer lifts the second row out of the list as Your pick appears beside it in gold. A pixel-art photo of a street at dusk, a figure crossing in front of a shopfront lit amber, comes up out of white as a post, the way a print comes up in the developer, under the words Your edits shown, and a strip lands under it with Redlamp's mark and @your.handle. Two strips of film run across a contact sheet and off its edges, every frame dark but one, where a drawn figure sits behind an open laptop, under the words Free raw editor run by one person. Then the dark frames around it light up one after another with pixel-art portraits of photographers, with an afro and round glasses, a beanie and a beard, a mohawk and a wink, a bucket hat and sunglasses, headphones, a big moustache, a cap turned sideways, and purple curls. Two more are half hidden at the edges, one of them holding a camera up to the eye. One frame in the lower strip holds only the silhouette an app shows before a profile photo is added, and a white marker rings it, under the words It needs your edits and ideas. A colourful photo editor opens the same street, flat and dark, and the pointer drags Exposure up a stop and Vibrance to 40 as the amber and the violet come up, under the words Edit a photo in Redlamp. The video ends with the lamp lit in the dark under the words Apply at redlamp.app/join.

The other hooks change only the first sentence: `say`, "Pixel art of Redlamp's lamp warming in the dark under the words Ambassadors have a say in Redlamp."; `wanted`, "… under the words Redlamp needs ambassadors."; `credit`, "… under the words Ambassadors get their edits shown."; `photographers`, "… under the words Photographers, be an ambassador."

## Before it's posted

- **The form opens:** on 15 October redlamp.app/join answered "Applications aren't open right now"; the relay waits on the Redlamp Feedback app's access to `pdcgomes/redlamp-ambassadors` and `AMBASSADORS_ENABLED` and `AMBASSADORS_REPO` on Vercel. A test application goes through before the reel goes up.
- **The bio** links to redlamp.app/join for as long as the call is open.
- **The page's terms,** reworded on 15 October to give ambassadors an active seat, are approved by the owner, since every applicant agrees to them.
- **The social room's caption check** gives a post its own call to action before this one is scheduled in `posts.json` (`room.py` refuses any caption without the standard one).

## Review notes

### The four-act reel, 15 October 2026

The owner watched the first pixel cut twice and couldn't tell what it was about: its hook named a benefit rather than the programme, and AMBASSADORS was only in the small header until the address. He asked for four acts, in order. The scriptwriter rebuilt the beat sheet around them, mostly from what was drawn; the copywriter wrote its words, keeping the beats; the copy editor's review (`copy-review-4.md`) found it passes his test with the sound off, act by act, and in the first two seconds, and made one change, to the alt text. Earlier the owner had asked for faces on the contact sheet, with the ringed frame left for the viewer, and the copywriter reworded around them so nine faces don't read as nine places taken. The page, its share image, the open call's posts and the programme were reworded the same day to give ambassadors an active seat, so the page no longer contradicts the reel (copy review 3). The owner approved the cut on 15 October.

### As built, 15 October 2026

The frames script draws all 576 frames for each of the five hooks with no layout or safe-zone warnings. A frame rendered by Remotion matches the drawn frame pixel for pixel. The posts (`ambassadors-a.mp4`, the lead, and `ambassadors-b.mp4`, the trial) are 19.2 s at 1080 × 1920, H.264 and AAC, at −14.1 LUFS with a −1.5 dBFS peak. `scripts/score-report.py` reads most cues within a frame; the shutters and clicks it reads 35 to 60 ms off sit among louder notes on the drop and elsewhere, and are placed on their beats in code. The storyboard, covers and stills are in the marketing library (`campaigns/ambassadors/reel/`) and on redlamp-hub.

## Results

Added a week after the open call's first post.
