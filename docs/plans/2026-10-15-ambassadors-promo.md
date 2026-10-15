# The ambassadors promo

The recruitment reel and carousel for Redlamp's ambassador programme (DEC-86): ten founding photographers who pick one feature a quarter that's built next, and whose edits are shown with their name. The programme, its terms and its phases are in the private social repository (`plans/2026-10-15-ambassadors.md`); the carousel's visual system is in its marketing library (`marketing/campaigns/ambassadors/`). Made in the promo studio (`.cursor/skills/redlamp-promo-studio/SKILL.md`), and posted through the social room.

The reel is drawn in pixel art, as an episode of the feature videos (the owner, 15 October 2026), and replaces the photographic reel this document first described, in which a print came up under the lamp; that script is in this file's history. At the owner's request its script and words were written by domain experts, each a separate agent: a short-form video scriptwriter wrote the concept and the beat sheet, a copywriter who has recruited photographers for ambassador programmes wrote every word, and an independent copy editor who wrote none of it reviewed them against the social room's checklist. Their files are in the social repository's `work/ambassadors/pixel-reel/`: `script.md`, `copy-deck.md`, `copy.md`, `copy-faces.md` and `copy-review-2.md`.

## Brief

| Row | What it says |
| --- | --- |
| Goal | Applications to the ambassador programme at redlamp.app/join: none on 15 October 2026 (the form isn't live yet); 30 by the open call's close, three weeks after it opens. |
| Audience | Photographers on the Mac who edit raw and show their edits: Lightroom users, people who follow Fujifilm-style recipes, and the people already editing in Redlamp. |
| Platforms | 9:16 for Instagram Reels and TikTok; a 4:5 carousel for the Instagram feed. |
| Length | 8 bars at 100 BPM (18 frames a beat at 30 fps): 19.2 s, the feature videos' episode without their 10 s opener. |
| The one message | Help decide what Redlamp builds next, and have your edits shown, with your name. |
| The ask | Edit a photo in Redlamp, then apply with it at redlamp.app/join. |
| Tone | The feature videos': simple and direct words over a colourful pixel-art editor, and dark synthwave. What happens can be playful; the words stay plain. |
| Must keep | The brand's rules (the lamp's red the only red, with a source; one red light per picture; no bright point in the lens); the social room's copy rules; claims only from the README and the programme; no count of places or ambassadors that isn't true for as long as the reel stays up. |
| Success | Applications in the ambassadors room 48 hours and 7 days after each post, against the days before; visits to /ambassadors (Vercel Analytics); the posts' views, saves and shares from the social room's analyst. |

## Concept

The scriptwriter weighed three, each in the pixel world:

1. **The episode** (chosen). The programme told as one of the feature videos, under the header REDLAMP · AMBASSADORS: the hook over the lamp, then the dashboard, where an edit is made, a roadmap row lifts as the viewer's pick, the photo comes up as a post with the viewer's handle, a roll of photographers is shot with one frame left for the viewer, and the ask comes over the lamp.
2. **The print comes up.** The first concept redrawn in pixel art: a sheet of paper under the lamp, the photo developing on it on the drop. It reads less as one of the series, its large white sheet competes with the hook, and its drop comes before the viewer has seen the editor.
3. **Ten frames.** A contact sheet first, the camera pushing into the one empty frame. Its first picture suits one hook only, a push-in steps rather than glides in pixel art, and the say comes last.

The episode won because it does the most with the series' own pieces, as the owner asked (the opener's first bar, the header, the caption, the dashboard, the develop and the end card), and carries the message in the order a viewer would live it: the offer on the first frame, an edit at three seconds, the say at five, the credit on the drop at seven, then the photographers and the ask. It starts and ends with words over the lamp, so it loops.

1. **The hook** over the lamp warming in the dark: the opener's first bar, its 100 frames at 72 BPM drawn into 72 at 100 BPM, so the cover is every episode's: the hook over the lamp at its warmest.
2. **The first hit:** the lamp shrinks and rises into the header's mark as the dashboard develops in, so there's one red light throughout. The pointer drags Exposure, then Vibrance, on a pixel-art street at dusk.
3. **The pick:** the Basic panel turns into a roadmap of four unnamed rows, and the pointer lifts one, labelled YOUR PICK.
4. **The drop:** the street comes up out of white as a post, the way a print comes up in the developer, and a credit strip lands under it with the Redlamp mark and @YOUR.HANDLE.
5. **The photographers:** two strips of film run across a contact sheet and off its edges, shot to a motor drive's burst: nine drawn photographers, quirky and fun, and the viewer's frame, empty but for the default profile picture, which a white marker rings. The faces are the owner's (15 October, after the first draft); the strips run off the edges so the roll can't be counted as ten places, the copywriter's proposal.
6. **The ask** over the lamp lit, then the picture dissolves into the wall the reel loops back to.

## Hooks

Each is a prop of the composition (`hook`), on screen from frame 0 to frame 71 over the lamp warming, with its own cover (frame 71) and its own first sentence in the alt text.

| ID | Hook | Why |
| --- | --- | --- |
| `pick` | PICK WHAT REDLAMP / BUILDS NEXT | Leads: the part of the offer no other programme has, said with the sound off, naming Redlamp on the first frame; bar 3 says it again in fewer words as the row lifts |
| `credit` | YOUR EDITS SHOWN / WITH YOUR NAME | The trial reel's: the other half of the one message, with no figure to date and credit rather than an audience; it pays off on the drop with the handle |
| `edit` | APPLY WITH / ONE EDIT | A spare: the application at its smallest |
| `say` | A SAY IN WHAT / REDLAMP BUILDS | A spare: the offer named |
| `become` | BECOME A REDLAMP / AMBASSADOR | A spare: puts "ambassador" on the first frame, where nothing yet says it's unpaid |

LOOKING FOR 10 / PHOTOGRAPHERS and 10 FOUNDING / AMBASSADORS are retired: over nine faces a 10 on the first frame reads as nine found, and "looking for 10" stops being true once the seeding wave accepts anyone. YOUR EDITS ON / REDLAMP'S FEED was dropped as exposure offered as payment, since the feed will be three weeks old at the open call.

## Script

8 bars at 100 BPM, in F minor; a beat is 0.6 s. The cues are in `video/src/ambassadors/cues.json`, which the frames and the score both read. At most two lines are on screen at once, counting a caption line or a word in the picture the story needs read (YOUR PICK, the handle); the series' own interface (the header, the panel titles, the file name, the meters) isn't counted, as the feature videos' reviews haven't counted it.

| Beat | Time | Picture | Words on screen | Sound |
| --- | --- | --- | --- | --- |
| 0 | 0.0 s | The dark wall; the lamp comes in over 14 frames and warms through the bar, its glow spreading in the ordered dither | The hook | A deep hit with its sub, a drone on F and a pad swelling with the lamp; a kick muffled as if through a wall on each beat; the arpeggio growing out of nothing from beat 2 |
| 4 | 2.4 s | The lamp rises into the header's mark over half a beat as the dashboard develops in: REDLAMP · AMBASSADORS, the street as opened (STREET.ARW, RAW), its histogram, the Basic meters at 0, the level | A FREE RAW EDITOR / FOR MAC | The first hit: kick, bass and arpeggio; air rushing up with the lamp |
| 4.5 to 7.75 | 2.7 to 4.65 s | The pointer drags Exposure to +0.50 and +1.00, then Vibrance to +20 and +40; the street brightens, then its amber and violet come up | (held) | A press, two ticks and a release for each slider, panned with its knob |
| 8 | 4.8 s | The Basic panel turns into ROADMAP: four rows, each a sprite and a dim bar where a name would be, drawn for rows that could be on January's shortlist (UX-38, UX-35, UX-41, UX-37) | PICK WHAT'S NEXT | The full beat, the riff and the trance gate; air as the panel opens |
| 9.5 to 10 | 5.7 to 6.0 s | The pointer presses the second row; on 10 it lifts two pixels with a shadow and a gold rim | + YOUR PICK, on the row | The press; a two-note lift in the key |
| 10.5 to 12 | 6.3 to 7.2 s | Everything holds still for the stop on 11.5 | (held) | Toms falling from F to A flat into the stop; a riser, and the drop's reverb swelling up through it |
| 12 | 7.2 s | **The drop:** the stage turns into a post, whose print comes up out of paper white into the street as edited, with sparkles; nothing on it counts likes, followers or views | YOUR EDITS SHOWN | The loudest bar: the boom, the 808, a trailer's low brass on F, the choir, a crash and the series' glass sting on F; developer washing over the print |
| 14 | 8.4 s | The credit strip slides up out of the post's bottom edge: the Redlamp mark in white and the handle | + @YOUR.HANDLE, on the strip | A soft landing |
| 16 to 18.25 | 9.6 to 10.95 s | A contact sheet: two strips of film running off both edges of the stage, two half-hidden faces at their ends; the ten whole frames are shot one a sixteenth, each flashing white: nine drawn photographers and the viewer's empty frame | FOR PHOTOGRAPHERS / LIKE YOU | A camera's shutter for each frame, as a motor drive fires a burst |
| 19 | 11.4 s | A white marker rings the viewer's frame, the second whole frame of the lower strip | (held) | A marker's squeak |
| 20 | 12.0 s | The end card: the dark wall, no header, the lamp coming on, its light spreading in six steps | EDIT A PHOTO / IN REDLAMP | A switch, and a low swell as the light spreads; the closing phrase begins |
| 24 | 14.4 s | The address in the end line's place, above the lamp: REDLAMP.APP/JOIN is too wide to sit under it clear of the apps' side buttons | APPLY AT / REDLAMP.APP/JOIN | A soft crash, over C7(b9) |
| 28 | 16.8 s | The lamp's light blooms out a step and settles back | (held) | The last hit on F, with a smaller boom |
| 30 to 32 | 18.0 to 19.2 s | The picture dissolves into the wall, gone by the last frame, which is frame 0's wall | The address, dissolving | The last chord dies away |

Muted, it reads: pick what Redlamp builds next; a free raw editor for Mac, as an edit is made; pick what's next, as a row lifts as your pick; your edits shown, as the photo comes up as a post with your handle; for photographers like you, over a roll of drawn photographers and an empty frame ringed for the viewer; edit a photo in Redlamp; apply at redlamp.app/join.

The photo is a pixel-art street at dusk drawn for the reel, not a Redlamp render, so its strip doesn't say EDITED IN REDLAMP. The photographers are drawn characters, not real people or ambassadors, and nothing in them is red.

## Formats

- **9:16, 1080 × 1920**, for Reels and TikTok: the series' 216 × 384 grid shown four times the size in its margin, so the picture keeps clear of the sides tall phones crop, and every word clear of the apps' controls (`world.covered`). The frames script warns about any word in a covered zone; it warns about none.
- **The cover** is frame 71, the hook over the lamp at its warmest, inside the middle 3:4 the profile grid shows.

## Sound

Its own track, dark synthwave in F minor at 100 BPM (`video/scripts/ambassadors/music.py`): E12's darksynth carried to F minor and to the reel's shape, recorded drums, drones, pads, a choir and impacts from Sonic Pi's pack (CC0) layered over our own synths. Fm6/9 under the hook and Abmaj7#11 from the first hit; the bass steps down from E flat through D to C, under Ebmaj9, Dm7(b5) and C7(b9), and rises to F on the drop, on Fm9; Dbmaj7#11 and Ebmaj9 under the photographers; Dbmaj7#11 and Dm7(b5) under the end line, C7(b9) under the address, and Fm9 on the last hit. The riff is on brass and saws from the roadmap, the series' glass sting on the drop. The reel's sounds on screen (`video/scripts/ambassadors-score.py`) are the series' presses, ticks, releases, the panel's air and the landing, and its own: the lamp's rush of air, the row's lift, the developer's wash, the shutter, the marker and the switch, 27 in all, each on its picture's beat.

Measured on 15 October: −14.0 LUFS integrated with a true peak of −1.5 dBFS, as the platforms' meter reads it; by bar, −17.8 LUFS under the hook, −15.5, −13.1, −12.1 on the drop, −13.6 under the photographers, −14.4 and −14.2 on the end card and −17.5 for the last chord; 5.6% of the energy under 60 Hz.

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

**The reel, on Instagram and TikTok**, in the copy rules' order, with the ambassadors' call to action in place of the standard `cta`:

> I'm looking for photographers to be Redlamp's ten founding ambassadors. Each quarter, they pick one feature from a shortlist of my roadmap for me to build next, and I show their edits here with their name.
>
> Redlamp is a free raw photo editor for Mac, with Lightroom's layout and shortcuts.
> Edit a photo in Redlamp, then apply with it at redlamp.app/join (link in bio). Ambassadors send me one edit a month. It's unpaid, and they get no early builds or fixes first. Your photos stay yours, and you don't need a lot of followers to apply.
> Needs an Apple Silicon Mac with macOS 26. It's in early development.
>
> Redlamp isn't affiliated with Adobe.
>
> #photoediting #rawediting #editbreakdown #macphotography #lightroomalternative

**The trial reel**, on Instagram, the same with this first sentence:

> I'm looking for photographers who edit raw on a Mac to be Redlamp's ten founding ambassadors.

**Audio name:** Redlamp theme: Ambassadors, on both platforms.

**The carousel:** the reel's caption, with "Swipe for what ambassadors get and what I ask." after the first sentence.

**X** (277 characters as X counts them), from the first copy review:

> I'm looking for ten photographers to be founding ambassadors for Redlamp, my free raw editor for the Mac. Each quarter you'd pick one feature I build next, and I'd show your edits with your name. It's unpaid. Apply with a photo you've edited in Redlamp: https://redlamp.app/join

**LinkedIn**, from the first copy review:

> I'm looking for ten photographers to be Redlamp's founding ambassadors. Redlamp is a free, open-source raw editor for the Mac.
>
> Each quarter, ambassadors pick one feature from a shortlist of my roadmap, and I build it next. There's a call with me every month, and I show their edits on Redlamp's accounts and site, with their name.
>
> It's unpaid, and ambassadors don't get early builds or fixes first. It needs an Apple Silicon Mac with macOS 26 or later, and Redlamp is in early development.
>
> To apply, edit a photo in Redlamp and send it with your application: https://redlamp.app/join

**Alt text (the reel, `pick`):** Pixel art of Redlamp's lamp warming in the dark under the words Pick what Redlamp builds next. Its light rises into a header reading Redlamp, Ambassadors, as a colourful photo editor comes in with a pixel-art street at dusk, flat and dark: a figure in silhouette crossing in front of a shopfront lit amber, its windows reflected in a wet pavement under a violet sky. Under the words A free raw editor for Mac, the pointer drags Exposure up a stop and the street brightens, then drags Vibrance to 40, and the amber and the violet come up. The sliders give way to a roadmap of four rows, each a small icon with no name, under the words Pick what's next, and the pointer lifts the second row out of the list as Your pick appears beside it in gold. The photo comes up out of white as a post, the way a print comes up in the developer, under the words Your edits shown, and a strip lands under it with Redlamp's mark and @your.handle. Two strips of film run across a contact sheet and off its edges, their frames holding pixel-art portraits of photographers, with an afro and round glasses, a beanie and a beard, a camera held up to the eye, a mohawk and a wink, a bucket hat and sunglasses, headphones, a big moustache, a cap turned sideways, and purple curls. Two more are half hidden at the edges. One frame in the lower strip holds only the silhouette an app shows before a profile photo is added, and a white marker rings it, under the words For photographers like you. The video ends with the lamp lit in the dark under the words Edit a photo in Redlamp, then Apply at redlamp.app/join.

The other hooks change only the first sentence: `credit`, "Pixel art of Redlamp's lamp warming in the dark under the words Your edits shown with your name."; `edit`, "… under the words Apply with one edit."; `say`, "… under the words A say in what Redlamp builds."; `become`, "… under the words Become a Redlamp ambassador."

## For the owner to decide

- **The script and the cut** (studio checkpoints 1 and 2), in Studio or as the half-size draft.
- **The end card:** APPLY AT / REDLAMP.APP/JOIN in place of the series' DOWNLOAD FREE / REDLAMP.APP, for this campaign's posts. The copywriter and both copy reviews would make the exception: applying needs a download and an edit first, and EDIT A PHOTO / IN REDLAMP comes just before it.
- **"Unpaid":** in the caption, as written, or on screen as ONE EDIT A MONTH / UNPAID in the end line's slot, at the cost of EDIT A PHOTO / IN REDLAMP. The writers and the editor would keep it in the caption.
- **The trial hook:** `credit`, as the copywriter and the editor recommend.
- **The roadmap's rows,** drawn for UX-38, UX-35 (the one that lifts), UX-41 and UX-37, or others he'd shortlist.
- **Length:** 19.2 s, with the end card held for 7.2 s of it; or 16.8 s with a bar less, which the scriptwriter would take from the photographers' bar and the director would rather take from the end card.
- **Before the post is scheduled:** the social room's caption check needs a call to action of the post's own (`room.py` refuses any caption without the standard one); the standard `requirements` line to say "macOS 26 or later", as the README and the page do; and both accounts' bios to link to redlamp.app/join for the open call.
- **X, LinkedIn and the page** still say "I'm looking for ten photographers", which goes out of date once the seeding wave accepts anyone; the second copy review's change to the reel's caption applies to them too, for the copywriter before the open call.
- **The closing date,** added to the caption once the open call's dates are fixed.

## Review notes

### The pixel reel's script and copy, 15 October 2026

The scriptwriter's beat sheet (8 bars at 100 BPM) and the copywriter's words were written in parallel and then fitted together; nothing in the copy moved a beat. After the owner watched the first draft and asked for faces on the contact sheet, the copywriter reworded bar 5 (FOR PHOTOGRAPHERS / LIKE YOU in place of 10 FOUNDING / PLACES, which read as nine places taken over nine faces), retired the two hooks with a 10 in them, and proposed running the strips off the stage's edges, which the director took. The independent review (`copy-review-2.md`) made five changes, one on screen: the roadmap's third row was drawn for LNS-15, which is aimed at 0.3.3 and so can't be on January's shortlist; it's now UX-41. The others put the caption's ten on the cohort ("Redlamp's ten founding ambassadors"), which stays true as places fill, and described bar 5 and the end card in the alt text as drawn. Every word as drawn matches the copy, within 17 characters, two lines at a time and clear of the apps' controls. The review also noted the lamp passing over bar 2's caption for four frames; the caption is now drawn over it.

### As built, 15 October 2026

The frames script draws all 576 frames for each of the five hooks with no layout or safe-zone warnings. A frame rendered by Remotion matches the drawn frame pixel for pixel. The half-size draft (`work/reels/ambassadors/ambassadors-pick-draft.mp4` in the social repository) is 19.2 s at −14.0 LUFS with a −1.5 dBFS peak after encoding. `scripts/score-report.py` finds 30 of the 43 cues within a frame of their beat. Of the other 13, three aren't sounds (the stop, the fade and the end); the rest, among them the first frame and the first hit, it reads 35 to 55 ms off, where a sound swells rather than strikes or a louder note of the track sits beside it. Every sound is placed on its beat in code, so they're for checking by ear. Not yet checked: the cut by ear and eye in Studio, and on a phone.

## Results

Added a week after the open call's first post.
