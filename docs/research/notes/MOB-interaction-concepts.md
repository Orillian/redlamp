# MOB-01: interaction concepts for the iPhone editor

Written by the interaction designer of the mobile UX team (an agent), on 13 October 2026, for MOB-01 ([#406](https://github.com/pdcgomes/redlamp/issues/406)), the iPhone design study. It builds on the team's three notes: [the Mac editor, distilled](MOB-desktop-distilled.md), [Lightroom for iPhone](MOB-lightroom-mobile.md) and [iPhone photo editors](MOB-mobile-editors.md).

## In short

- **Eight principles** judge every concept: the photo stays large, one thumb reaches what's common, positions never move, every gesture has a visible equivalent, precision when wanted, nothing is cut, accessible from the start, and no fight with the system's gestures.
- **Five concepts**, from the familiar to the new: **A, Bar and ruler** (a fixed module bar, a strip of adjustments with rings, one large ruler); **B, Slider sheet** (a module opens a list of sliders in a sheet with detents); **C, The photo is the control** (vertical drags on the photo choose, horizontal drags set); **D, Flick compass** (a hierarchic marking menu: one flick picks the module, a second the adjustment); **E, My sliders** (a pinned row of the photographer's own sliders, and search that reaches any slider by name).
- **The three tasks cost the same in A, B and C, and little less elsewhere.** Brightening and warming, darkening the sky with a Sky mask, and cropping to 4:5 with a straighten take 2 taps and 2 drags, 2 and 1, and 2 and 2 in A, B and C. D's expert strokes take 0 taps and 4, 2 and 3 drags; E takes 0 and 2 for the first task. The concepts differ on the less common adjustments: lifting Shadows and lowering Orange Luminance takes 8 actions in A, 6 in B, C and D, and 4 plus typing in E.
- **Several parts are shared whatever the concept,** and some of them change the team's earlier proposals. **The module bar has eight fixed slots** (Looks, Light, Colour, Effects, Crop, Masks, Remove, Detail, with Optics inside Detail), so that each slot keeps 44 points on an iPhone SE without scrolling. **Auto joins Paste and Previous at the start of Looks.** **A mask is a context, not a place:** while one is selected, the Light, Colour, Effects and Detail tabs edit the mask, with the same positions as the global ones.
- **Recommendation: build two prototypes that share everything except how you move between modules and adjustments.** **Prototype 1** is A, with B's list as a layer you pull up, C's horizontal drag on the photo as a setting, and E's search. **Prototype 2** is D, the flick compass. Both use the same ruler and the same Masks and Crop modules. Together they test the familiar and the new on the same tasks, and record taps, time, errors and where the thumb lands.

## How it was done

I read the three notes and the harness's iPhone foundations (`packages/RedlampMobile/Sources` in the `darkroom-iphone-harness` worktree): the 44-point minimum target (`MobileTarget.minimum`), the spacing scale from 2 to 32 points, the sheet's 24-point corner radius, and the default stage of 402 × 874 points with safe areas of 62 at the top and 34 at the bottom (`MobileLayout.phonePortrait`). Every layout below uses those numbers. Claims about other apps come from the team's notes, which give their sources; I link the section each claim comes from. Three sources of my own are cited from working knowledge and were not fetched today: Steven Hoober's study of how people hold phones [H13], Kurtenbach and Buxton's study of marking menus [KB93], and the names of Apple's APIs. Nobody on the team can run the apps, so behaviour the notes mark as unverified stays unverified here.

**Counting.** A tap is one touch and lift. A drag is one continuous movement of the finger, including a flick. Typing counts separately. Each task starts with the photo just opened from the gallery, with the editor on the module last used, assumed to be Looks, so that every task has to travel to its module. Leaving a tool by going to another module commits it and costs nothing.

**Percentages of photo.** The screen is 402 × 874 points (351,348 square points). The **canvas** is the rectangle the photo is drawn in, given as its share of the screen's height (and so of its area, since it spans the full width). Two real photos are also given: a **3:2 landscape** photo fills 402 × 268 points, **30.7%** of the screen, in any canvas at least 268 points tall; a **2:3 portrait** photo fills what's left once it's fitted into the canvas. With every control hidden (a tap on the photo), the canvas is 778 points tall, and a 2:3 photo fills **69.0%** of the screen.

---

## 1. Principles

Every concept is judged against these eight.

1. **The photo stays as large as it can.** While a control is showing, the canvas keeps at least half of the screen's height, and a tap on the photo hides everything. An edit is judged by looking at the photo, and the distiller asked the prototypes to test that half ([distilled, What a phone takes away](MOB-desktop-distilled.md#what-a-phone-takes-away)).
2. **One thumb reaches everything used while editing.** Modules, adjustments and values sit in the bottom third of the screen; the top bar holds only what's used between edits (Done, undo, history, share). Hoober observed 49% of people holding their phone in one hand [H13], and every editor the team studied keeps its controls under the photo ([editors, In short](MOB-mobile-editors.md#in-short)).
3. **Positions never move, so they can be learnt.** The order of modules, of the adjustments in each module, and of the same adjustments inside a mask is fixed across photos, contexts and releases, and nothing reflows when content changes. The few complaints about Lightroom Mobile's design followed releases that moved controls ([Lightroom, §5](MOB-lightroom-mobile.md#5-what-users-praise-and-complain-about)).
4. **Every gesture has a visible equivalent, and every control has a name on screen.** Hidden gestures are fast once learnt, but nothing on the screen teaches them, as Snapseed's reviewers found ([editors, pattern 1](MOB-mobile-editors.md#1-drag-on-the-photo-to-adjust)). VoiceOver and Voice Control users need a path that doesn't depend on them.
5. **Precision when wanted.** Every value can be nudged finely, typed, reset and felt at its default, with Lightroom's names, ranges and units read from the Mac's catalog. Raw edits need small, repeatable moves: a third of a stop, 100 K.
6. **Nothing is cut; depth comes from layers.** Every Mac capability the distiller placed has a place: one tap from the photo (T1), inside a module (T2), or behind search and More (T3) ([distilled, Tiers](MOB-desktop-distilled.md#tiers)). The owner's direction is that missing features irritate more than a busy screen.
7. **Accessible from the start.** VoiceOver, Voice Control, Dynamic Type up to the accessibility sizes, Reduce Motion, and left-handed use are part of each concept's design, not added later.
8. **No fight with the system's gestures.** Nothing interactive sits in the bottom 34 points, where a swipe goes home or to another app, or starts at the top edge, where Notification Centre and Control Centre live. A gesture that iOS gives a meaning (three-finger undo, swipe down to dismiss) keeps that meaning or is deliberately turned off.

---

## 2. The concepts

All five share the top bar and the parts in [section 3](#3-shared-parts); they differ in how you move between modules and adjustments and how you set a value. The top bar, from left to right: **Done** (saves and returns to the gallery), **Undo**, **Redo**, the photo's place in its album (**12/340**, which opens the filmstrip), **B/A** (before and after), **History**, **Share** and **More (⋯)**. Eight buttons of 44 points fit in 402 with about 6 points between them.

In the diagrams, the module bar's slots are abbreviated: **Lk** Looks, **Li** Light, **Co** Colour, **Ef** Effects, **Cr** Crop, **Ma** Masks, **Re** Remove, **De** Detail.

### Concept A: Bar and ruler

**Idea.** The familiar concept, built from Apple Photos' adjustment row and Lightroom Mobile's two-level toolbar, held still. A bar of eight modules sits along the bottom. Above it, a strip shows the selected module's adjustments as round buttons in a fixed order, each with a ring that shows how far it has moved from its default, as Photos does ([editors, Apple Photos](MOB-mobile-editors.md#apple-photos-ios-26-and-what-ios-27-changes)). Above the bar, one large ruler, the width of the screen, sets the selected adjustment. Every strip has the same eight slots: up to seven adjustments or named groups, then the module's own ⋯ (Reset, the module's on-off switch, Copy this module). A group such as Curve or Color Mixer swaps the strip for its own contents, with Back in the first slot. A module opens on the adjustment last used in it, or on its first adjustment the ruler can set.

**Storyboard.**

(a) Brighten and warm. *2 taps, 2 drags.*
1. Tap **Light** in the module bar. The strip shows Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Curve and ⋯; Exposure is selected and the ruler shows it.
2. Drag the ruler to the right, to +0.40. A haptic tick marks 0 as the finger passes it.
3. Tap **Colour**. The strip shows B&W, Temp, Tint, Vibrance, Saturation, Mixer, Grading and ⋯; Temp is selected, since B&W is a switch.
4. Drag the ruler to the right, to 6100 K.

(b) Darken the sky with a Sky mask. *2 taps, 1 drag.*
1. Tap **Masks**. The strip shows the mask list, then Sky, Subject, Background, Brush, Linear, Radial and More.
2. Tap **Sky**. The sky is found (Apple Vision, about a second), its coverage flashes as a red tint, and the editor enters the mask's context: a pill reading "Sky 1 ×" sits at the bottom edge of the photo, the module bar is tinted, and Light is selected with the mask's Exposure on the ruler.
3. Drag the ruler to the left, to −0.70.

(c) Crop to 4:5 and straighten. *2 taps, 2 drags.*
1. Tap **Crop**. The crop frame appears with its handles. The strip shows Original, 1:1, 4:5, 9:16, Ratios, Rotate, Geometry and ⋯; the ruler shows Angle.
2. Tap **4:5**. The frame becomes the largest 4:5 that fits, upright; tapping 4:5 again would turn it to 5:4.
3. Drag the ruler to −1.8°. A grid appears while dragging, and a tick marks 0°.
4. Drag the photo under the frame to place it.

**Layout.**

```
y   0 +----------------------------------------------+
      |  9:41         (  island  )          5G  100  |  status bar, safe area 62
y  62 +----------------------------------------------+
      | Done  Undo Redo   12/340   B/A Hist Shr  ... |  top bar 44
y 106 +----------------------------------------------+
      |                                              |
      |                                              |
      |                    PHOTO                     |  canvas 402 x 526
      |              fit, never covered              |  60.2% of the screen
      |                                              |
      |                                              |
y 632 +----------------------------------------------+
      |  (o)   (o)   (O)   (o)   (o)   (o)  Crv>  .. |  strip 76: 8 slots of 50
      |  Exp   Con   Hil   Sha   Whi   Bla           |  rings show each amount
y 716 +----------------------------------------------+
      |               Highlights  -32                |  ruler 68, value on top
      |  ' | ' | ' | ' | ' | '[#]' | ' | ' | ' | '   |  index fixed at centre
y 784 +----------------------------------------------+
      |  Lk    Li    Co    Ef    Cr    Ma    Re   De |  module bar 56: 8 slots
y 840 +----------------------------------------------+
      |                  ==========                  |  home indicator 34
y 874 +----------------------------------------------+
```

The canvas is 526 points tall, **60.2%** of the screen. A 3:2 landscape photo fills **30.7%**; a 2:3 portrait photo, fitted to the canvas's height (351 × 526), fills **52.5%**. The controls take 208 points (24% of the height). On an iPhone SE (375 × 667, with 20 points of status bar and no home indicator), the same controls leave a canvas of 395 points, 59% of its height. The Color Mixer and Color Grading make the strip taller while they're open (below).

**Gestures and the thumb.** The thumb rests on the ruler, in the middle of the bottom quarter, and travels up one row to the strip or down one row to the bar. Taps: a module, an adjustment, the selected adjustment again for its options (white balance presets and the eyedropper behind Temp, typing a value, reset). Drags: the ruler, moving relative to where the finger lands. Double-tap the ruler or an adjustment's button to reset it. On the photo: tap to hide the controls, press and hold for before, pinch to zoom, double-tap for Fit or 1:1, a horizontal swipe at Fit for the next photo, a swipe down to close (section 3).

**Many sliders, masks and tools.** Groups replace the strip and add a Back slot, so depth is a tap down and a tap up. The **Color Mixer** needs a band and a property: its layer shows two rows, eight colour dots above and Hue, Saturation and Luminance with Back below, which makes the strip 20 points taller (the canvas shrinks to 506). **Color Grading** shows one wheel at a time: the strip's place grows from 76 to 180 points to hold a wheel of 160, with the range (Shadows, Midtones, Highlights, Global) as four buttons beside it and Luminance on the ruler; the canvas shrinks to 422 points (48%) while it's open, and Hue and Saturation show as numbers beside the wheel, since the thumb hides the puck ([distilled, 4.8](MOB-desktop-distilled.md#4-colour)). **Detail** shows Sharpening, Noise, Colour Noise, Lens, Defringe and Manual as groups, and opens a 1:1 inset of the place last looked at ([distilled, 6.1](MOB-desktop-distilled.md#6-detail)). **Masks** use the shared mask context (section 3), so a mask's Light strip is the global Light strip. **Crop and Remove** make the photo their canvas: one finger draws, drags handles or places the frame; two fingers pan and zoom; the ruler sets Angle, brush Size, Feather or Opacity.

**Muscle memory and the first time.** Three things are learnt, all as places: eight module slots, eight strip slots per module, and the ruler's direction (right is more). Rings show where the edit has been without opening anything, and a dot on a module's tab says it holds edits ([distilled, 1.15](MOB-desktop-distilled.md#1-the-editors-frame-viewing-history-and-search)). The first time, everything is labelled and nothing needs teaching: the editor opens on Light with Exposure selected, and for the first three uses a line under the ruler says "Drag to adjust · double-tap to reset".

**Accessibility, landscape, system gestures, iPad.** VoiceOver reads the bar as tabs, each strip button as "Exposure, +0.40, adjustable": swiping up or down steps the value, and custom actions reset it, type a value or step finely. At the accessibility text sizes, the bar's labels move into iOS's Large Content Viewer (press and hold a tab, as system tab bars do), and the strip shows four buttons a page with their labels below, which is the one place positions change; at AX3 and above, the strip becomes B's list. Reduce Motion swaps the strip without sliding. Left-handed use needs nothing, since the controls span the width. In landscape, the controls become a column on the thumb's side (right by default, left with the left-handed setting): the module bar becomes a rail along the edge, the strip a column beside it, and the ruler vertical, which suits a thumb holding the phone's side; the photo keeps about 70% of the width. Nothing sits in the bottom 34 points or the top edge. On the iPad, the column becomes an inspector at the side with the strip shown as a list, and the ruler stays under the photo.

**Risks, and what's new.** Setting several related values means switching back and forth (Highlights against Whites), which Apple's single slider suffers from ([editors, pattern 2](MOB-mobile-editors.md#2-one-adjustment-at-a-time-with-a-large-control-under-the-photo)). The Mixer's 24 values cost a tap per band and per property. Nothing here is new as an idea; what's new is the discipline of eight slots everywhere and a ruler that carries the Mac's ranges and units.

### Concept B: Slider sheet

**Idea.** Lightroom Mobile's and Darkroom's model, held still. A module opens a sheet of sliders above the module bar, in the Mac's order, with the module's folded groups at the end ([editors, Darkroom](MOB-mobile-editors.md#darkroom-bergen-co); [Lightroom, §3.1](MOB-lightroom-mobile.md#31-the-toolbar-and-its-tools)). The sheet has three heights: **compact**, which shows only the slider last touched; **medium**, which shows the module's main sliders, all six of Light at once; and **large**, which shows the whole module with its groups open. The photo shrinks above the sheet instead of being covered. Groups open downward only, so nothing above a group ever moves, and each module keeps its scroll position.

**Storyboard.**

(a) Brighten and warm. *2 taps, 2 drags.*
1. Tap **Light**. The sheet opens at medium with Exposure, Contrast, Highlights, Shadows, Whites and Blacks.
2. Drag the Exposure slider to +0.40.
3. Tap **Colour**. The sheet shows Treatment, the white balance menu, Temp, Tint, Vibrance and Saturation.
4. Drag the Temp slider to 6100 K.

(b) Darken the sky with a Sky mask. *2 taps, 1 drag.*
1. Tap **Masks**. The sheet shows the mask list, empty, and a row of kinds: Sky, Subject, Background, Brush, Linear, Radial, More.
2. Tap **Sky**. The mask is made and the editor enters its context; the sheet shows the mask's Light sliders.
3. Drag the Exposure slider to −0.70.

(c) Crop to 4:5 and straighten. *2 taps, 2 drags.*
1. Tap **Crop**. The sheet drops to compact: a row of ratios and the Angle slider.
2. Tap **4:5**.
3. Drag the Angle slider to −1.8°.
4. Drag the photo under the frame to place it.

**Layout** (medium height).

```
y   0 +----------------------------------------------+
      |                                              |  status bar 62
y  62 +----------------------------------------------+
      | Done  Undo Redo   12/340   B/A Hist Shr  ... |  top bar 44
y 106 +----------------------------------------------+
      |                                              |
      |                    PHOTO                     |  canvas 402 x 348
      |                                              |  39.8% of the screen
      |                                              |
y 462 +----------------------------------------------+
      |                    ----                      |  grabber
      |  Light                       (on)  Reset ... |  header 44
      |  Exposure     ---------o------------  +0.40  |  6 rows of 44
      |  Contrast     --------------o-------    +12  |
      |  Highlights   -----o----------------    -32  |
      |  Shadows      --------------o-------    +18  |
      |  Whites       -----------o----------      0  |
      |  Blacks       -----------o----------      0  |
      |  > Curve                                     |  folded groups below
y 784 +----------------------------------------------+
      |  Lk    Li    Co    Ef    Cr    Ma    Re   De |  module bar 56
y 840 +----------------------------------------------+
      |                  ==========                  |  home indicator 34
y 874 +----------------------------------------------+
```

At medium height the canvas is 348 points, **39.8%** of the screen: a 3:2 photo still fills **30.7%**, but a 2:3 photo shrinks to 232 × 348, **23.0%**. At compact height (one slider, a sheet of 72 points) the canvas is 598 points, **68.4%**, and a 2:3 photo fills **67.9%**. At large height the photo is a strip 120 points tall (13.7%). On an iPhone SE, the medium sheet leaves a canvas of 217 points, too short for a 3:2 photo at full width. The medium height breaks principle 1; the concept depends on people living at compact height and rising to medium only to compare several sliders.

**Gestures and the thumb.** The thumb sweeps the rows; the top row at medium height is about 330 points above the bottom edge, a stretch for one thumb on a 402-point phone. A drag on a row that starts horizontal sets the slider, after 8 points of movement within 30° of horizontal; a vertical drag scrolls the list; a drag on the grabber changes the height. Double-tap a slider to reset it ([editors, Darkroom and Photomator](MOB-mobile-editors.md#6-precision-aids-on-every-slider)); tap its value to type one.

**Many sliders, masks and tools.** This is what the concept does well: a module's related sliders are visible together, and the Color Mixer in Color mode shows eight dots with three sliders under them, which fits the width ([distilled, 4.6](MOB-desktop-distilled.md#4-colour)). Color Grading opens a wheel inside the sheet, at large height. Masks use the shared context: the sheet shows the mask's sliders, grouped as Light, Colour, Effects and Detail like the global modules. Crop and Remove drop the sheet to compact, since they need the photo.

**Muscle memory and the first time.** The bar's slots are learnt as places. Inside the sheet, rows are learnt as names, because their position on screen depends on how far the list has scrolled and which groups are open; Photomator shows the same cost ([editors, Photomator](MOB-mobile-editors.md#photomator-pixelmator-now-apple)). The first time needs no teaching: it looks like Lightroom and the Mac.

**Accessibility, landscape, system gestures, iPad.** VoiceOver reads a standard list with group headings, which its rotor can jump between, and each slider is adjustable. Dynamic Type makes rows taller and fewer; the list scrolls. Reduce Motion snaps between heights. Left-handed use needs nothing. In landscape the sheet becomes a column on the thumb's side, a natural fit. The sheet's own drag is far from the screen's edges. On the iPad it becomes the inspector, as on the Mac.

**Risks, and what's new.** The photo shrinks too far at medium height, especially on the SE. Scrolling a list of sliders with a thumb changes sliders by accident; the axis lock reduces but doesn't remove it. Nothing here is new; it's the baseline the others are measured against.

### Concept C: The photo is the control

**Idea.** Snapseed's model, kept for a Lightroom-sized set and given visible equivalents ([editors, Snapseed](MOB-mobile-editors.md#snapseed-google)). The module bar stays at the bottom. Above it, a thin value bar shows the selected adjustment ("Exposure +0.40") over a slim ruler that can be dragged too. A vertical drag anywhere on the photo shows the module's adjustments as a list beside the thumb, and moving up or down picks one; a horizontal drag anywhere on the photo sets it. The direction is decided by the first 10 points of movement. Turning the corner without lifting the finger, from vertical to horizontal, picks and sets in one stroke. The photo takes nearly the whole screen.

**Storyboard.**

(a) Brighten and warm. *2 taps, 2 drags.*
1. Tap **Light**. The value bar reads "Exposure 0.00".
2. Drag right across the photo, to +0.40.
3. Tap **Colour**. The value bar reads "Temp 5200 K".
4. Drag right across the photo, to 6100 K.

(b) Darken the sky with a Sky mask. *2 taps, 1 drag.*
1. Tap **Masks**. A row of kinds appears above the value bar: Sky, Subject, Background, Brush, Linear, Radial, More.
2. Tap **Sky**. The editor enters the mask's context, with the mask's Exposure in the value bar.
3. Drag left across the photo, to −0.70. A Sky mask has no handles, so the drag can't catch one.

(c) Crop to 4:5 and straighten. *2 taps, 2 drags.*
1. Tap **Crop**. The frame appears, and a row of ratios above the value bar, which shows Angle.
2. Tap **4:5**.
3. Drag the slim ruler to −1.8°. In Crop, a drag on the photo moves the photo under the frame, as in Photos, so the angle has to come from the ruler.
4. Drag the photo under the frame to place it.

A photographer who wants a slider other than the first reaches and sets it with one stroke: from Light, a stroke down two places to Highlights then right to −30.

**Layout.**

```
y   0 +----------------------------------------------+
      |                                              |  status bar 62
y  62 +----------------------------------------------+
      | Done  Undo Redo   12/340   B/A Hist Shr  ... |  top bar 44
y 106 +----------------------------------------------+
      |                                              |
      |                           +--------------+   |
      |                           |  Exposure    |   |  list shown only during
      |                           |> Contrast   <|   |  a vertical drag, beside
      |                    PHOTO  |  Highlights  |   |  the thumb
      |                           |  Shadows     |   |
      |                           +--------------+   |  canvas 402 x 630
      |                                              |  72.1% of the screen
      |                                              |
y 736 +----------------------------------------------+
      |  Contrast  +12      ' | ' | '[#]' | ' | '    |  value bar 48, slim ruler
y 784 +----------------------------------------------+
      |  Lk    Li    Co    Ef    Cr    Ma    Re   De |  module bar 56
y 840 +----------------------------------------------+
      |                  ==========                  |  home indicator 34
y 874 +----------------------------------------------+
```

The canvas is 630 points, **72.1%** of the screen; a 2:3 photo fills **69.0%**, the same as with the controls hidden, and a 3:2 photo **30.7%**. In Masks, Crop and the Mixer, a row of 44 points appears above the value bar and the canvas shrinks to 586 (67%).

**Gestures and the thumb.** The thumb rests on the photo's lower half, where both drags start, and drops to the bar for modules. Vertical drag: choose. Horizontal drag: set. Both work anywhere on the photo, so the thumb doesn't look for a control. Press and hold still compares, since it doesn't move. The cost is that the photo's other drags have to go: a horizontal swipe can't move to the next photo (the filmstrip does it), a swipe down can't close the editor (Done does it), and when zoomed in, one finger pans, so values come from the slim ruler.

**Many sliders, masks and tools.** The vertical list holds the module's main adjustments, at most eight with the groups at the end; picking a group swaps the list. A list of more than about seven items becomes a hunt ([editors, pattern 1](MOB-mobile-editors.md#1-drag-on-the-photo-to-adjust)), so the eight-slot rule of concept A holds here too. The Color Mixer's bands appear as a row of dots above the value bar, tapped; the vertical list then holds Hue, Saturation and Luminance. Color Grading shows its wheel over the photo's lower half, dragged directly. Inside a mask with handles (gradients, radials), a drag that starts on a handle moves it, and any other drag sets a value; inside Crop and Remove the photo is the tool's canvas and the value drags stop, which a tinted frame around the photo shows.

**Muscle memory and the first time.** The gesture is the same in every module, which builds memory quickly; positions in the list are learnt as counts ("Highlights is two down"). Nothing on the photo says it can be dragged, so the first time in each module the value bar reads "Drag sideways on the photo" beside a still drawing of a thumb, and the slim ruler works for anyone who never tries.

**Accessibility, landscape, system gestures, iPad.** VoiceOver takes over touches on the screen, so its users use the module bar and the value bar, which is an adjustable element, and never meet the concept's main gesture. Voice Control can say "Tap Contrast" only if the list is on screen, so the value bar's menu lists the module's adjustments. Dynamic Type affects only the value bar and the list. Reduce Motion stops the list from sliding in. Left-handed use needs only the list to appear on the other side of the thumb. In landscape, the bar becomes a rail on the thumb's side, and vertical and horizontal keep their meaning. Swipe down to close and swipe to the next photo are turned off, a conflict with Darkroom's and Photomator's habits ([editors, pattern 8](MOB-mobile-editors.md#8-gestures-for-moving-through-photos-and-the-editor)). On the iPad, the drags work with a finger or the Pencil, and the list becomes a column.

**Risks, and what's new.** It is the one concept whose main gesture is invisible and unavailable to VoiceOver users. The photo's gestures conflict with panning, the next photo and closing, and in Detail, used zoomed in, the concept falls back to the ruler. New: the stroke that turns a corner to pick and set at once, the list shown beside the thumb, and the module bar beneath for a Lightroom-sized set, which Snapseed's tools, each about seven parameters, never needed.

### Concept D: Flick compass

**Idea.** A hierarchic marking menu, a technique from interface research [KB93] that none of the studied editors uses. A round hub sits in the middle of the control area, labelled with where you are ("Light › Exposure"). The eight modules sit at fixed compass directions around it, and each module's eight strip slots at fixed directions on the second level, in the same order as concept A's bar and strips, placed clockwise from the left. **Novices tap:** a tap on the hub opens a ring of the eight modules as buttons; tapping one opens its eight adjustments; tapping one selects it. **Experts flick:** a stroke from the hub toward Light and then, without lifting, toward Exposure selects it without waiting for any ring to appear. A ring appears only if the finger rests for 0.3 seconds, so the novice's path and the expert's are the same movement. A ruler under the hub sets the value. The eight-slot rule makes the compass and the bar the same map: Looks is left, Light up-left, Colour up, Effects up-right, Crop right, Masks down-right, Remove down, Detail down-left.

**Storyboard.**

(a) Brighten and warm. *Expert: 0 taps, 4 drags. Novice: 6 taps, 2 drags.*
1. Stroke from the hub up-left (Light), then left (Exposure). The hub reads "Light › Exposure". *(Novice: tap the hub, tap Light, tap Exposure.)*
2. Drag the ruler to +0.40.
3. Stroke from the hub up (Colour), then up-left (Temp). *(Novice: tap the hub, tap Colour, tap Temp.)*
4. Drag the ruler to 6100 K.

(b) Darken the sky with a Sky mask. *Expert: 0 taps, 2 drags. Novice: 3 taps, 1 drag.*
1. Stroke from the hub down-right (Masks), then up-left (Sky). The mask is made and the editor enters its context; the hub reads "Sky 1 › Exposure". *(Novice: tap the hub, tap Masks, tap Sky.)*
2. Drag the ruler to −0.70.

(c) Crop to 4:5 and straighten. *Expert: 0 taps, 3 drags. Novice: 3 taps, 2 drags.*
1. Stroke from the hub right (Crop), then up (4:5). The frame appears at 4:5 and the ruler shows Angle. *(Novice: tap the hub, tap Crop, tap 4:5.)*
2. Drag the ruler to −1.8°.
3. Drag the photo under the frame to place it.

**Layout** (the ring drawn open, as a novice sees it after tapping the hub).

```
y   0 +----------------------------------------------+
      |                                              |  status bar 62
y  62 +----------------------------------------------+
      | Done  Undo Redo   12/340   B/A Hist Shr  ... |  top bar 44
y 106 +----------------------------------------------+
      |                                              |
      |                    PHOTO                     |  canvas 402 x 578
      |                                              |  66.1% of the screen
      |                                              |
      |                    Colour                    |  ring: 8 buttons of 52
      |          Light               Effects         |  on a radius of 84,
y 684 +----------------------------------------------+  over the photo and
      |       Looks       ( Hub )         Crop       |  ruler only while open
      |          Detail               Masks          |  hub row 88, hub 64
      |                    Remove                    |
y 772 +----------------------------------------------+
      |  ' | ' | ' | ' | ' | '[#]' | ' | ' | ' | '   |  ruler 68
y 840 +----------------------------------------------+
      |                  ==========                  |  home indicator 34
y 874 +----------------------------------------------+
```

The diagram squeezes the ring; drawn to scale, the hub's centre is at y = 728, and the ring's buttons centre 84 points from it, from y = 644 (Colour) to y = 812 (Remove), whose button ends at 838, above the home indicator. With the ring closed, the hub row reads "Light › Exposure", then the hub, then the value "+0.40". With the ring closed, the canvas is 578 points, **66.1%** of the screen: a 2:3 photo fills **63.4%** (385 × 578) and a 3:2 photo **30.7%**. On an iPhone SE the canvas is 447 points, 67% of its height.

**Gestures and the thumb.** The thumb rests on the hub, in the middle of the bottom fifth, and every module and adjustment is a short flick from that one spot; the hub's centred position serves either hand. Each leg of a stroke needs 24 points in one of eight 45° directions. A stroke that starts on the hub belongs to the hub even when it crosses the photo. Tapping the breadcrumb ("Light › Exposure") opens the ring at the second level, for another adjustment in the same module. The ruler and the photo's gestures are those of concept A.

**Many sliders, masks and tools.** Every module's first level fits eight directions because of the eight-slot rule. Kurtenbach and Buxton found error rates rising with depth and breadth, with eight items per level usable at two levels [KB93], so strokes stop at two levels: a group (Curve, Mixer, Grading, the Detail groups) is reached by a stroke and then shows its contents as visible buttons in the hub row, such as the Mixer's eight colour dots and Hue, Saturation and Luminance, tapped. In a mask's context the directions are unchanged and edit the mask, and Masks' own directions hold the kinds of mask: the mask list left, Sky up-left, Subject up, Background up-right, Brush right, Linear down-right, Radial down, More down-left. Crop and Remove work on the photo as in concept A, with the ruler for Angle and brush size.

**Muscle memory and the first time.** Marking menus are designed for this: each tap a novice makes on the ring rehearses the direction an expert flicks, and the whole map is two words of a gesture language ("up-left, left" is Exposure). The compass and concept A's bar share one map, so either teaches the other. The first time, the hub shows its label and a tap opens the ring; after a photographer has tapped the same path five times, a line under the hub says "Next time, flick: up-left, then left".

**Accessibility, landscape, system gestures, iPad.** VoiceOver and Switch Control use the tap path: the hub is a button, the ring's items are buttons in reading order, and the ruler is adjustable. At the accessibility text sizes the ring's labels don't fit around a radius of 84, so above AX2 the ring opens as a list sheet in the same order. Reduce Motion shows the ring without expanding it. The hub is centred, so the left hand flicks the same directions; mirroring is offered, but off by default, so that one map serves people, hands and the manual alike. In landscape the hub and the ruler move to a column on the thumb's side; the column is the screen's full height, 402 points, enough for the whole ring, and the ruler turns vertical. Strokes start on the hub, far from the screen's edges, and the down leg stops above the home indicator. On the iPad, the hub can be placed wherever the hand rests, and flicked with the Pencil.

**Risks, and what's new.** People may never move from taps to flicks, which leaves them with six taps for task (a) against A's two. Eight directions with a thumb, which pivots instead of moving freely, may be less accurate than the pen and mouse of the published studies. The ring covers the bottom of the photo while open. New: the whole concept on a photo editor, and the shared map between bar and compass.

### Concept E: My sliders

**Idea.** The first level is the photographer's own, not the app's structure. A deck of pinned sliders sits above a bottom row, four to a page, swiped sideways for the next page: Snapseed's Faves, Photomator's Customize Adjustments and RAW Power's ordering, taken further ([editors, pattern 5](MOB-mobile-editors.md#5-the-users-own-set-of-adjustments)). The pins are suggested from the adjustments the photographer's own Mac edits use, read from their history (an assessment: nobody has measured whether those histories make good suggestions); with none, Exposure, Highlights, Shadows and Temp on the first page, then Contrast, Tint, Vibrance and Saturation. The bottom row holds **Modules** (a sheet of the eight modules, each opening as concept B's list), a **search field** that reaches any slider by name and accepts the Mac palette's syntax ("exposure +0.4", "temp 5600k", [distilled, 1.21](MOB-desktop-distilled.md#1-the-editors-frame-viewing-history-and-search)), and **Crop**, **Masks** and **Remove**, the three tools that take over the photo. Any slider in any list can be pinned from its options.

**Storyboard.**

(a) Brighten and warm. *0 taps, 2 drags.*
1. Drag the **Exposure** row to +0.40.
2. Drag the **Temp** row to 6100 K. Both are on the suggested first page; a slider on the second page costs one more drag, a sideways swipe of the deck.

(b) Darken the sky with a Sky mask. *2 taps, 1 drag.*
1. Tap **Masks**. The deck's place shows the mask list and a row of kinds.
2. Tap **Sky**. The editor enters the mask's context; the deck shows the pins the mask can use, Exposure first.
3. Drag the **Exposure** row to −0.70.

(c) Crop to 4:5 and straighten. *2 taps, 2 drags.*
1. Tap **Crop**. The deck's place shows a row of ratios and the Angle slider.
2. Tap **4:5**.
3. Drag the **Angle** row to −1.8°.
4. Drag the photo under the frame to place it.

A slider that isn't pinned: tap the search field, type "ora lum", tap **Orange Luminance (Color Mixer)** and drag it; or type "orange lum -20" and press Return, with no drag at all.

**Layout.**

```
y   0 +----------------------------------------------+
      |                                              |  status bar 62
y  62 +----------------------------------------------+
      | Done  Undo Redo   12/340   B/A Hist Shr  ... |  top bar 44
y 106 +----------------------------------------------+
      |                                              |
      |                    PHOTO                     |  canvas 402 x 490
      |                                              |  56.1% of the screen
      |                                              |
y 604 +----------------------------------------------+
      |  Exposure     ---------o------------  +0.40  |  deck: 4 pinned rows
      |  Highlights   -----o----------------    -32  |  of 44, page dots
      |  Shadows      --------------o-------    +18  |
      |  Temp         ------------o---------  6100K  |
      |                     o  .                     |
y 784 +----------------------------------------------+
      |  [Mod]  [ Find a slider...     ]  Cr  Ma  Re |  bottom row 56
y 840 +----------------------------------------------+
      |                  ==========                  |  home indicator 34
y 874 +----------------------------------------------+
```

The canvas is 490 points, **56.1%** of the screen: a 2:3 photo fills **45.6%** (327 × 490) and a 3:2 photo **30.7%**. The deck can be folded to one row, the last touched, which raises the canvas to 618 points (70.7%). On an iPhone SE the canvas is about 360 points, 54% of its height. While typing, the keyboard covers the controls, not the photo, and results list above it; the canvas shrinks to about 300 points.

**Gestures and the thumb.** The thumb rests on the deck's rows, the same drags as concept B's sliders, and a sideways swipe that starts between rows turns the page. The search field is in the middle of the bottom row, where either thumb reaches it; the keyboard needs two thumbs or a careful one.

**Many sliders, masks and tools.** Any of them can be pinned, Orange Luminance or Grain Amount included, so the depth of a module costs nothing once pinned, and search reaches anything else by name in one query. The Modules sheet holds everything in the Mac's order, as concept B's list. In a mask, the pins that exist locally show, in the same order, and the mask's full set is in the Modules sheet. The three tools work on the photo as in concept A.

**Muscle memory and the first time.** The photographer sets the positions once and they stay, which is strong memory for a personal set. But two photographers' screens differ, so a tutorial, the manual or a friend can't say "the third row". The first time, the suggested pins are labelled, the search field's placeholder reads "Find a slider, or type 'shadows +20'", and the Modules button shows where the rest is.

**Accessibility, landscape, system gestures, iPad.** VoiceOver reads each row as adjustable; search suits VoiceOver and Voice Control, since saying or typing a slider's name skips navigation. Dynamic Type makes rows taller, so fewer fit a page. Reduce Motion turns pages without sliding. Left-handed use needs nothing, but the tool buttons can move to the left with the left-handed setting. In landscape the deck becomes a column on the thumb's side. The keyboard is a system surface and conflicts with nothing. On the iPad the pins become the top of an inspector and the search answers ⌘K on a keyboard.

**Risks, and what's new.** It depends on good suggestions; a photographer who never pins meets a deck of four sliders and a Modules button, which is concept B a tap further away. The first level looks different from Lightroom's, so a Lightroom user may look for modules first. Typing one-handed is slow. New: a first level built from the photographer's own Mac history, and a typed value syntax on a phone.

### Considered and set aside

- **An edge rail of modules,** standing on the right edge in portrait. The right thumb reaches it, the left doesn't, and the labels have to be icons or turned text. It returns as the landscape form of concepts A and C, where a thumb holds the phone's side.
- **A scrolling dial of module names,** as Halide's tab-dial ([editors, Halide](MOB-mobile-editors.md#halide-mark-iii-photo-lab-lux-optics)). Its positions move under a fixed centre, some modules are always off screen, and flicks overshoot ([editors, pattern 4](MOB-mobile-editors.md#4-a-rotary-or-carousel-selector-for-modules)). Concept D keeps its idea, one small gesture to any module from one spot, without the scrolling.
- **A two-axis drag through looks,** as Infltr's ([editors, Infltr](MOB-mobile-editors.md#infltr-yooshr)). It finds a look but can't repeat a value, so it doesn't set an edit.

---

## 3. Shared parts

These hold whatever the concept, and the prototypes should build them once.

**The module bar's eight slots.** Looks, Light, Colour, Effects, Crop, Masks, Remove and Detail, with Optics as the second half of Detail. The distiller's proposal had nine modules and Auto ([distilled, A proposed grouping](MOB-desktop-distilled.md#a-proposed-grouping-into-phone-modules)), which needs a scrolling bar: 10 slots on a 375-point iPhone SE leave 37.5 points each, under the 44-point minimum. Eight leave 46.9 points on the SE and 50 on a standard iPhone, with every module always visible and in the same place. Detail and Optics share a slot because both are set once or left at their defaults (distiller, departure 4); nothing in either is cut. Auto moves to Looks (below). Whether the owner accepts this, against the distiller's open question 5 on the bar's order, is the first decision these concepts need.

**Opening a photo.** A tap on a thumbnail in the gallery zooms the photo from its place in the grid into the canvas (SwiftUI's zoom navigation transition, available since iOS 18), with Photos' own preview shown at once and Redlamp's render replacing it when ready, marked by a thin progress line under the top bar. The controls rise into place after the photo lands, 150 ms behind it. With Reduce Motion, the photo cross-fades in. The editor opens on the module last used; on a first launch, on Light with Exposure selected.

**Moving to the next photo.** In concepts A, B, D and E, a horizontal swipe on the photo at Fit moves to the next or previous photo of the album the photo was opened from, as Darkroom and Photomator do ([editors, pattern 8](MOB-mobile-editors.md#8-gestures-for-moving-through-photos-and-the-editor)). It doesn't when the photo is zoomed in (one finger pans) or a tool is using the photo (Crop, Masks with handles, Remove), where a stray swipe would cost a photographer their place. The distiller didn't propose the swipe because of those clashes ([distilled, 1.2](MOB-desktop-distilled.md#1-the-editors-frame-viewing-history-and-search)); limiting it to Fit outside the tools keeps the habit and avoids them. The visible equivalent everywhere is the **12/340** button in the top bar, which opens a filmstrip under it. Concept C gives up the swipe. Each photo's edit is kept as the photographer moves on, as Photomator does ([editors, Photomator](MOB-mobile-editors.md#photomator-pixelmator-now-apple)); where it's kept, and when it's written into Photos, are the distiller's open questions 1 to 3.

**Before and after.** Press and hold the photo to see the before, a convention every studied editor shares ([editors, pattern 7](MOB-mobile-editors.md#7-press-and-hold-to-compare)). Press and hold an adjustment's button or row to see the photo without that adjustment, as Apple's buttons and Darkroom's per-tool eye do; press and hold a module's tab to see the photo without that module (at the accessibility text sizes, that press shows the Large Content Viewer instead, and the comparison is in the B/A button's menu). The **B/A** button in the top bar is the visible equivalent; held, it compares, and its menu offers Side by Side and Split ([distilled, 1.6](MOB-desktop-distilled.md#1-the-editors-frame-viewing-history-and-search)). In a picking mode (the white balance eyedropper, Point Color, Objects), the touch is the loupe, so comparing goes through the B/A button.

**Undo and history.** Undo and Redo are in the top bar. iOS's own three-finger swipes (left to undo, right to redo) work through the app's undo manager; the two-finger tap that Photomator uses for undo ([editors, Photomator](MOB-mobile-editors.md#photomator-pixelmator-now-apple)) is worth testing in the prototypes, since it is quicker but begins like a pinch. **History** opens a sheet listing every step with its before and after values, the last sessions, Snapshots and, once built, Versions, as the Mac does ([distilled, 1.18](MOB-desktop-distilled.md#1-the-editors-frame-viewing-history-and-search)); tapping a step previews it and **Go Back to This Step** keeps it, undoably. Lightroom Mobile has no full history ([Lightroom, §4](MOB-lightroom-mobile.md#4-whats-missing-against-lightroom-classic-and-lightroom-desktop)).

**Resetting.** Double-tap an adjustment's ruler, button or row to reset it, as Darkroom and Photomator do ([editors, pattern 6](MOB-mobile-editors.md#6-precision-aids-on-every-slider)); its options (tap the selected adjustment again) also hold Reset. A module's ⋯ resets the module; More › Reset All resets the photo, and Undo brings any of them back.

**Fine adjustment and typed values.** The ruler and the slider rows move relative to where the finger lands, never jumping to it ([distilled, What a phone takes away](MOB-desktop-distilled.md#what-a-phone-takes-away)). While dragging, moving the finger up and away from the control slows it by up to ten times, RAW Power's "gear down" ([editors, RAW Power](MOB-mobile-editors.md#raw-power-gentlemen-coders)), and a label ("×1/10") shows it. The value has no momentum: it stops where the finger lifts. The ruler's sensitivity puts each adjustment's common range in one sweep of the thumb (about 250 points: ±1.5 stops of Exposure), with the whole range a few sweeps away. Tapping the value above the ruler, or a row's value, opens a compact number pad over the controls, never the photo, with minus, a decimal point, units ("5600k") and the Mac's arithmetic ("+10", as `ParameterSpec.parse` accepts). VoiceOver steps by the catalog's step, and a custom action steps by a tenth of it.

**Haptic detents.** A selection tick when a value crosses its default (0, As Shot, the catalog's default), at each whole unit (each stop of Exposure, each 500 K on Temp's mired scale), at the ends of the range, when the crop angle reaches 0° or the frame snaps to a ratio, and when an AI mask is ready ([distilled, Phone-only opportunities](MOB-desktop-distilled.md#phone-only-opportunities)). No tick on every step, which tires the hand. The system's haptics setting turns them off.

**Looks and their strength.** Looks opens on three chips, **Auto**, **Paste** and **Previous**, the three ways to bring in an edit from elsewhere, followed by groups (Favourites first, then Film and the rest) and a strip of recipes rendered on the photo. Scrolling the strip previews the recipe at its centre, and lifting the finger applies it ([distilled, 2.1](MOB-desktop-distilled.md#2-looks-recipes-and-base-looks)). Tapping the applied recipe again puts its Amount on the ruler, VSCO's "tap the filter again" ([editors, pattern 10](MOB-mobile-editors.md#10-looks-with-one-strength-control)). Auto sits here rather than in the bar so that the bar keeps eight slots; it is undone in one step and leaves ordinary values on the sliders, which answers the "magic wand" complaint ([Lightroom, §6](MOB-lightroom-mobile.md#6-keep-do-better-avoid)). Base Looks are a segment of Looks with their own Amount.

**Copy and paste of settings.** **Copy Settings…** is in More, with the Mac's checklist of groups as a sheet that remembers its last choice ([distilled, 11.5](MOB-desktop-distilled.md#11-the-parts-of-library-a-phone-edit-touches)); a module's ⋯ copies that module alone. **Paste** and **Previous** are the chips at the start of Looks. In the gallery, selecting photos offers Paste Settings, written as one change to the library so that Photos asks permission once ([distilled, Phone-only opportunities](MOB-desktop-distilled.md#phone-only-opportunities)).

**A mask is a context, not a place.** Selecting a mask (making one, tapping its pin on the photo, or choosing it from the mask list) puts the editor in its context: a pill at the bottom edge of the photo names it ("Sky 1 ×"), the module bar is tinted, and **Light, Colour, Effects and Detail edit the mask**, with the strips, rows or compass directions exactly where they are for the whole photo. Looks, Crop and Remove are dimmed in place, since they don't apply to a mask. The Masks tab holds the mask's own controls: its components (Add, Subtract, Intersect, Invert), Amount, mask Effects (Dodge, Burn, Warm…), Feather and Edge, Refine, the overlay, and the ⋯ menu each row needs ([distilled, 9.19](MOB-desktop-distilled.md#9-masks)). Tapping × on the pill, or the photo outside every mask, leaves the context. This turns the distiller's "grouped as the global modules are" ([distilled, 9.16](MOB-desktop-distilled.md#9-masks)) into one rule: a photographer learns one map of positions, and a mask reuses it. Making a mask lands in its Light with Exposure selected; whether it should stay in Masks instead is for the prototypes.

**The Masks and Crop modules' first level.** Masks starts with its mask list in the first slot and the common kinds in fixed slots after it (Sky, Subject, Background, Brush, Linear, Radial), with **More** for People, Objects, Landscape, Depth Range, the ranges and the mask presets. New masks appear in the list, never in the strip, so the kinds keep their places. Crop starts with Original, 1:1, 4:5 and 9:16, then Ratios (the rest, custom ones included), Rotate (90° to the left a tap), Geometry (Upright, Transform, Flip, Overlay, Constrain to Image) and ⋯; tapping the selected ratio turns it between portrait and landscape. Angle is always on the ruler, as Photos keeps its straighten dial under the photo ([editors, Apple Photos](MOB-mobile-editors.md#apple-photos-ios-26-and-what-ios-27-changes)).

**Search, in every concept.** More holds **Find a Slider**, the search field of concept E, with the same syntax; concept E lifts it to the first level. A result opens the slider where it lives, so search also teaches where things are.

**Gestures on the photo.** Tap: hide or show the controls. Press and hold: before. Pinch: zoom. Double-tap: Fit or 1:1. One finger when zoomed in: pan; two fingers in a tool: pan. Horizontal swipe at Fit outside the tools: next photo. Swipe down at Fit outside the tools: close (Darkroom and Photomator, [editors, pattern 8](MOB-mobile-editors.md#8-gestures-for-moving-through-photos-and-the-editor)). Concept C keeps tap, hold and pinch, and gives the drags to editing.

---

## 4. Comparison

### Against the principles

| Principle | A: Bar and ruler | B: Slider sheet | C: The photo is the control | D: Flick compass | E: My sliders |
|---|---|---|---|---|---|
| 1. Photo large | Good: canvas 60%, a 2:3 photo 53% | Fails at medium height (40%, a 2:3 photo 23%); good at compact (68%) | Strong: canvas 72%, a 2:3 photo 69% | Good: canvas 66%, a 2:3 photo 63% | Fair: canvas 56%, a 2:3 photo 46% |
| 2. One thumb | Good: all controls in the bottom 24% | Fair: the list's top rows are 330 points up | Good: the thumb anywhere on the photo | Good: everything a flick from one spot | Good, except typing |
| 3. Fixed positions | Good: eight slots in the bar and every strip | Fair: rows learnt as names, since the list scrolls | Fair: list learnt as counts | Strong: fixed directions, one map with A | Strong for one person, but differs between people |
| 4. Visible equivalent | Good: nothing hidden | Good: nothing hidden | Weak: the main gesture is hidden; the ruler and bar stand in | Good: the ring opens on a tap | Good |
| 5. Precision | Good: full-width ruler, gear-down, typing | Fair: tracks about 210 points long | Good on the photo; the slim ruler when zoomed | Good: same ruler as A | Fair: as B's rows; typing exact |
| 6. Nothing cut | Yes, three levels deep | Yes, two levels deep | Yes, but list length is a limit | Yes; strokes stop at two levels | Yes; search reaches anything in one query |
| 7. Accessibility | Good; strip changes at large text | Good: a standard list | Weak: VoiceOver users never meet the main gesture | Fair: tap path works; ring becomes a list above AX2 | Good: search suits VoiceOver and Voice Control |
| 8. System gestures | No conflict | No conflict | Gives up swipe to close and to the next photo | No conflict | No conflict |

### Taps and drags for each task

The fourth task, lifting Shadows and lowering Orange Luminance, isn't one of the three asked for; it is added because the three common tasks cost the same in A, B and C, and it shows where they differ.

| Concept | (a) Brighten and warm | (b) Darken the sky | (c) Crop 4:5, straighten | (d) Shadows and Orange Luminance |
|---|---|---|---|---|
| A: Bar and ruler | 2 taps, 2 drags | 2 taps, 1 drag | 2 taps, 2 drags | 6 taps, 2 drags |
| B: Slider sheet | 2 taps, 2 drags | 2 taps, 1 drag | 2 taps, 2 drags | 4 taps, 2 drags |
| C: The photo is the control | 2 taps, 2 drags | 2 taps, 1 drag | 2 taps, 2 drags | 3 taps, 3 drags |
| D: Flick compass, expert | 0 taps, 4 drags | 0 taps, 2 drags | 0 taps, 3 drags | 2 taps, 4 drags |
| D: Flick compass, novice | 6 taps, 2 drags | 3 taps, 1 drag | 3 taps, 2 drags | 8 taps, 2 drags |
| E: My sliders | 0 taps, 2 drags (with the suggested pins) | 2 taps, 1 drag | 2 taps, 2 drags | 2 taps, 2 drags, and typing |

Task (d), step by step: **A** taps Light, Shadows, drags, taps Colour, Mixer, Orange, Luminance, drags. **B** taps Light, drags Shadows, taps Colour, the Mixer group, Orange, drags Luminance. **C** taps Light, strokes down to Shadows and right, taps Colour, drags down to Mixer, taps Orange, strokes to Luminance and right. **D** strokes Light › Shadows, drags the ruler, strokes Colour › Mixer, taps Orange and Luminance, drags the ruler. **E** drags the pinned Shadows, taps search, types "ora lum", taps the result, drags.

**Assessment.** For the everyday tasks, the structure barely changes the count; it changes how much photo is left, how much is learnt, and how much is hidden. A list (B) is quicker when a module's sliders are wanted together, at the cost of the photo. A single control (A, C, D) keeps the photo and costs taps in the deep modules. D trades taps for strokes and its value rests on whether people make the move from novice to expert.

---

## 5. Recommendation

Build **two prototypes** in the harness, sharing the top bar, the ruler and its aids, the Looks, Masks and Crop modules, the mask context and the gestures on the photo, so that the only difference is how a photographer moves between modules and adjustments. Run both on the phone, not only on the Mac's drawing of it, since thumb reach can't be judged with a pointer.

**Prototype 1: Bar and ruler, with layers (concept A).** Add three layers, each one a switch in the harness, so they can be tested inside the same build:
- **B's list as A's pull-up:** a drag up on the strip turns it into the module's slider list at B's medium height, and a drag down returns. Test whether photographers find it, whether they use it for the Color Mixer and Detail, and whether they come back down, so that the photo's share stays at 60% most of the time.
- **C's horizontal drag on the photo,** setting the selected adjustment. Test whether people use it once shown, how often it fires by accident, and whether losing the swipe to the next photo bothers them.
- **E's search,** in More and as a first-level button. Test whether photographers coming from the Mac's ⌘K reach for it, and whether a result's "opens where it lives" teaches the modules.

Measure the three tasks and task (d): time, taps and drags, wrong modules opened, accidental changes, and where the thumb lands (which needs the harness to record touch positions on the phone). Also check the strip at AX3 and above, on the iPhone SE and on the largest iPhone.

**Prototype 2: Flick compass (concept D).** Test the move from novice to expert: over three short sessions with the same tasks, the share of selections made by stroke without the ring, the error rate of each of the eight directions with the right thumb and the left, on the SE and the largest iPhone, and whether strokes beat A's taps on time once learnt. Also test whether the shared map transfers: someone who learns A's bar first should flick in D without being taught. Check the VoiceOver path and the list that replaces the ring above AX2.

**What I'd not prototype yet.** Concept B is the baseline that Prototype 1's pull-up already contains. Concept C's full form fails principles 4, 7 and 8; its useful part, the horizontal drag, is a layer in Prototype 1. Concept E's pinned deck is a later layer for Prototype 1 if search proves popular, since it needs real Mac histories to suggest good pins.

**Decisions for the owner before building.** Eight slots in the bar, with Optics inside Detail; Auto in Looks; the swipe to the next photo at Fit (against a horizontal drag on the photo that edits); swipe down to close; and whether making a mask lands in its Light or stays in Masks.

## Sources

From the team's notes (each gives its own sources):

- [MOB-desktop-distilled.md](MOB-desktop-distilled.md): the Mac's capabilities, tiers and proposed modules.
- [MOB-lightroom-mobile.md](MOB-lightroom-mobile.md): Lightroom for iPhone 11.6.10 and its reviews.
- [MOB-mobile-editors.md](MOB-mobile-editors.md): Apple Photos, Snapseed, VSCO, Darkroom, Photomator, RAW Power, Capture One, Halide and Infltr, and eleven patterns.

Added in this note, cited from working knowledge and not fetched on 13 October 2026:

- [H13] Steven Hoober, "How Do Users Really Hold Mobile Devices?", UXmatters, February 2013: <https://www.uxmatters.com/mt/archives/2013/02/how-do-users-really-hold-mobile-devices.php>. Of 1,333 people observed using phones, 49% held them in one hand.
- [KB93] Gordon Kurtenbach and William Buxton, "The limits of expert performance using hierarchic marking menus", Proceedings of INTERCHI '93, ACM. Experts select from radial menus by stroke without waiting for the menu, and errors rise with the menu's depth and breadth.
- Apple's APIs named above: SwiftUI's zoom navigation transition (iOS 18), UIKit's `UILargeContentViewerInteraction` (the Large Content Viewer), `UIResponder.editingInteractionConfiguration` (iOS's three-finger editing gestures), `preferredScreenEdgesDeferringSystemGestures`, and the adjustable accessibility trait.

## Design critic's review

Written by the design critic of the mobile UX team (an agent) on 13 October 2026. I checked the note's geometry against four screens, its research claims against the papers, and its platform claims against Apple's Human Interface Guidelines and API documentation, all fetched today; sources are listed at the end of this section as [R1] to [R24]. What I couldn't read is marked (unverified).

### In short

- **Ranking:** A, E, B, D, C. A meets every principle with conditions that can be fixed; C fails three of them.
- **The recommendation:** I agree with Prototype 1, with four changes: search goes into both prototypes as a shared part, the pull-up gets a visible grabber, C's drag on the photo is off by default, and Undo moves within reach of the thumb. I don't agree with building D in full now. Its central assumption, that people move from tapping to flicking with a thumb, can be tested with a stroke rig in a fraction of the effort. The second full prototype should be B, the Lightroom model that the owner's users bring with them.
- **What the note misses:** Undo sits in the top bar, out of the thumb's reach on a 440 × 956 phone, although it's used while editing. The eight-button top bar doesn't fit an iPhone SE with system margins. D's tap path doesn't rehearse the flick, which the marking-menu research depends on. iOS 26's horizontal back swipe from anywhere in the content competes with every horizontal drag on the photo. Stepping by the catalog's step makes VoiceOver need 180 swipes for a −1.8° straighten. iOS 27 runs on a foldable iPhone Duo whose outer screen leaves A's canvas under half the height.

### 1. The concepts against the principles

A score of 5 meets the principle with room to spare, 3 meets it on a condition the note names or I name below, and 1 fails it.

| Principle | A: Bar and ruler | B: Slider sheet | C: Photo is the control | D: Flick compass | E: My sliders |
|---|---|---|---|---|---|
| 1. Photo large | 4 | 2 | 5 | 4 | 3 |
| 2. One thumb | 4 | 2 | 4 | 3 | 3 |
| 3. Fixed positions | 4 | 2 | 3 | 4 | 2 |
| 4. Visible equivalent | 5 | 5 | 2 | 3 | 4 |
| 5. Precision | 4 | 3 | 3 | 4 | 3 |
| 6. Nothing cut | 4 | 4 | 3 | 3 | 5 |
| 7. Accessibility | 4 | 4 | 2 | 2 | 4 |
| 8. System gestures | 4 | 4 | 2 | 3 | 4 |
| Total (of 40) | 33 | 26 | 24 | 26 | 28 |

Where I differ from the note's own table: every concept loses a point on principle 2, since Undo is in the top bar (section 2 below), and none scores 5 there. D's map can't be seen while the ring is closed, so a photographer can't check where Masks is without opening it (principle 4: 3, not "good"). D's thumb legs toward the palm and its ruler directly above the home indicator cost it on principles 2 and 8. E's positions are fixed for one person but differ between people and change whenever the suggestions change (principle 3: 2, not "strong"). A, B, D and E all meet iOS 26's horizontal back swipe and the zoom transition's interactive dismissal (section 3), which the note's "no conflict" leaves out.

**A: Bar and ruler.**
- *Strength.* Every target is visible and stays in one place, taps sit next to the home indicator and drags sit in the middle row, and the expert path is the same as the novice path: two taps at learnt places. Research on spatially stable layouts finds that experienced users become faster with them than with menus, and novices aren't slower ([R9], below).
- *Main risk.* The same tap means different things in different states. A module opens on the adjustment last used in it, so "tap Light, drag the ruler" sets Exposure on one photo and Highlights on the next. A group (Curve, Mixer) swaps the strip's contents, so slot 3 is Highlights in one state and a colour band in another. At the accessibility text sizes the strip pages, four buttons at a time.
- *Fails in use when* the photographer drags by habit, watching the photo rather than the value line, and moves the wrong adjustment; or when comparing Highlights against Whites costs a tap for every switch, which the note names.

**B: Slider sheet.**
- *Strength.* A module's related sliders are visible together, as in Lightroom and on the Mac, and nothing needs teaching.
- *Main risk.* At medium height a 2:3 photo fills 23% of the screen, and on an iPhone SE the canvas is 225 points (section 3). The concept depends on people living at compact height, which they have no reason to do while they're comparing sliders.
- *Fails in use when* a thumb scrolling the list catches a slider. A right thumb scrolls in an arc that leans from vertical, and the note's 30° axis lock is about the lean such an arc reaches (my estimate; unverified). People then judge the edit on a small photo.

**C: The photo is the control.**
- *Strength.* The canvas is the tallest of the five, and one gesture works in every module.
- *Main risk.* The main gesture is hidden, and it takes the photo's other drags: the swipe to the next photo, the swipe down to close, and one-finger panning.
- *Fails in use when* a pinch starts with one finger, whose first 10 points set a value before the second finger lands; or when a photographer with Darkroom's or Photomator's habit swipes to the next photo and changes Temp instead.

**D: Flick compass.**
- *Strength.* One resting place for the thumb, short movements, and a map shared with A's bar.
- *Main risk.* Its value rests on a move from taps to flicks that the research finds only with heavy practice (section 4). The tap path costs three taps per adjustment, and the down-left and down legs move the thumb toward the palm.
- *Fails in use when* a photographer who never makes the move pays 6 taps for task (a) against A's 2, or when a down-left leg read as down opens Remove instead of Detail.

**E: My sliders.**
- *Strength.* Search reaches every slider by name, and the typed syntax sets an exact value. This is also the path that suits VoiceOver and Voice Control.
- *Main risk.* The suggested pins come from Mac histories that nobody has measured, and the first level looks unlike Lightroom's.
- *Fails in use when* a photographer never pins anything and meets concept B one tap further away, or when a manual or a friend can't say "the third row", because the rows differ between people.

### 2. Accessibility

**VoiceOver.** The adjustable trait [R18] is the right base for every value. But the note's rule that VoiceOver steps by the catalog's step fails on some parameters. Redlamp's catalog (`ParameterSpec.swift`) steps Exposure by 0.05, so +0.40 is 8 swipes; Temp by 50 K, so 5500 to 6100 K is 12; Contrast by 1, so +12 is 12; and crop Angle by 0.01°, so −1.8° is 180 swipes. Each parameter needs its own VoiceOver step (Angle 0.1°, Temp 100 K), with the catalog's step as the fine custom action, and **Type a Value** as the first custom action. Custom rotors [R19] should list the modules, the adjustments that hold edits (what the rings show sighted users), and the masks. Custom actions on every adjustment: Reset, Type a Value, Fine Step, and Compare Without This, which stands in for press and hold. C can offer VoiceOver users its photo drag through the direct-interaction trait [R17] on the canvas, which the note doesn't mention; that would lift C's accessibility, though not its other conflicts.

**Switch Control.** Item scanning visits every element in turn: A's screen has about 25 (8 in the top bar, 8 in the strip, the ruler, 8 in the bar), so the rows should be accessibility groups that scanning enters only when chosen. Nothing may need a drag. Placing the photo under the crop frame and painting a Brush mask are drag-only in every concept. Crop needs nudge actions or offset fields; for Brush, whether Switch Control's own gesture tools are usable for painting is (unverified), so AI masks and numerically placed Linear and Radial masks have to cover what Brush does. D's tap path costs a Switch Control user three selections per adjustment, each after a scan of the ring.

**Voice Control.** It acts on names it can see. In A, C and D, the adjustments of other modules aren't on screen, so "Tap Highlights" fails unless Light is selected; in D, nothing below the hub has a name until the ring opens. Every concept needs alternative spoken names (`accessibilityUserInputLabels`: "Temperature" and "White balance" for Temp) and search as a first-level button, so that "Tap Find a Slider" followed by dictating "shadows plus 20" reaches anything. Whether Voice Control can step an adjustable element by voice is (unverified), so typed entry is required, not optional.

**Dynamic Type at the accessibility sizes on an iPhone SE.** At AX5, Body text is 53 points and Caption 2 is 40 points; at AX3, 40 and 29 [R14]. A's ruler is 68 points tall and holds the value line and the ticks, so at AX5 the value alone fills it. A's plan to turn the strip into B's list at AX3 meets B's worst case: on the SE the medium sheet already leaves a 225-point canvas, and rows tall enough for 40-point text show about three sliders. I'd keep the positions instead: icons in their slots at every text size, with their labels in the Large Content Viewer [R20], as the note already does for the bar, and one line that scales, the selected adjustment's name and value above the ruler, which grows into the canvas's space. The list should then be a choice, not forced. D's ring becomes a list sheet that covers the photo; E's deck shows one or two rows at AX5.

**Reduce Motion, transparency, contrast and colour.** The note covers Reduce Motion. Custom glass on the ruler, strip and ring has to follow Reduce Transparency and Increase Contrast, which system components do on their own [R13]. A mask's context is shown by a tinted module bar and its coverage by a red tint: the pill names the mask in text, which suffices for the context, but the overlay's colour should be a choice, as on the Mac, for photographers who can't separate red from green.

**Left-handed use.** A, B and E need nothing. D's map is fixed and its centred hub serves either hand, but the legs that are easy for a right thumb (up-left, left) aren't the ones that are easy for a left thumb; Apple's guidance warns against gestures that depend on a hand [R16]. D's prototype has to report errors by direction and by hand, as the note asks, and the owner has to decide what happens if the left hand's errors differ.

**One-handed reach on 440 × 956 points.** All five put their controls in the bottom quarter, but the top bar sits from y = 62 to 106, and it holds Undo. Hoober's later field work found that 75% of people touch with one thumb, fewer than half hold the phone in one hand, and people change their grip to reach the top of the screen, which is why the top-left Back button is used as much as it is [R12]. A grip change in the middle of an edit is what principle 2 exists to avoid, and the three-finger undo needs a second hand. Every concept needs an Undo within the thumb's reach.

**What each concept must add to pass:**
- **All:** an Undo within reach; per-parameter VoiceOver steps and Type a Value; rotors for modules, edited adjustments and masks; non-drag paths for crop placement; search reachable from the first level; spoken alternative names.
- **A:** keep the strip's positions at the accessibility sizes, with the Large Content Viewer and one growing value line, rather than paging or switching to a list.
- **B:** a smallest detent that holds the selected slider at AX sizes, and accessibility groups for each module's rows.
- **C:** the direct-interaction trait on the canvas, a visible list of the module's adjustments for Voice Control, and a menu on the value bar.
- **D:** a custom rotor on the hub that reaches modules and adjustments without opening the ring, the ring as a modal element while open, and an at-rest view of the map (for example the bar's labels shown under the hub).
- **E:** VoiceOver's page scroll on the deck, and pins that can be reordered without a drag.

### 3. Ergonomics and system gestures

**The note's geometry.** Its arithmetic holds where I checked it: eight slots give 46.9 points on an iPhone SE and 50.25 on a standard iPhone, and A's canvas is 60.2% of the standard screen and 59% of the SE's. Three figures disagree with the diagrams by up to 8 points: A's strip is labelled 76 points but drawn from y = 632 to 716 (84), B's canvas is given as 348 points but drawn as 356, and E's as 490 but drawn as 498. None changes a conclusion. The canvas measure overstates what matters for landscape photos: a 3:2 photo fills 30.7% of the standard screen in every concept, and 30.6% of the largest, because its width limits it. Holding the phone sideways would roughly double that: with a 200-point control column and the top bar moved into it, a 3:2 photo fills about 57% of a standard screen (my calculation, assuming landscape safe areas of 62 points at each side and 21 at the bottom; unverified for current models).

The canvas's height in points, and as a share of the screen's height, on four screens, from the controls' heights in the note (the iPhone Duo's outer screen is 1398 × 2034 pixels [R24]; I assume a 3× scale, 466 × 678 points, and the standard phone's safe areas, all unverified):

| Concept | iPhone SE, 375 × 667 | Standard, 402 × 874 | Largest, 440 × 956 | iPhone Duo outer, 466 × 678 |
|---|---|---|---|---|
| A | 395 (59%) | 526 (60%) | 608 (64%) | 330 (49%) |
| B, medium | 225 (34%) | 356 (41%) | 438 (46%) | 160 (24%) |
| C | 499 (75%) | 630 (72%) | 712 (74%) | 434 (64%) |
| D, ring closed | 447 (67%) | 578 (66%) | 660 (69%) | 382 (56%) |
| E | 367 (55%) | 498 (57%) | 580 (61%) | 302 (45%) |

iOS 27 still runs on the iPhone SE (second generation and later), so 375 × 667 stays a target, and it adds the foldable iPhone Duo [R23]. On its outer screen, A's canvas falls under half the height, which breaks principle 1 for the recommended concept; the inner screen (1878 × 2670 pixels) is close to an iPad's and suits the note's iPad layouts.

**The top bar doesn't fit the SE.** Eight 44-point buttons take 352 of the SE's 375 points, leaving 23 for the gaps and both margins, and "12/340" set at 17 points is wider than 44 (my estimate). Apple's guidance asks toolbars to avoid crowding, to keep to at most three groups, and to give Done a section of its own [R5]. I'd keep Done at the leading edge, Undo and Redo as one group, B/A and More at the trailing edge, and move History, Share and the photo's position into More and the filmstrip.

**Thumb precision.** Apple's minimum is 44 × 44 points [R4]. Parhi, Karlson and Bederson recommend 9.2 mm for discrete one-handed thumb taps [R10]. A point is about 0.156 mm on an iPhone SE (326 pixels per inch at 2×) and about 0.166 mm on a 460-pixel-per-inch phone at 3×, so the SE's 46.9-point slots are 7.3 mm and the standard phone's 50-point slots 8.3 mm: within Apple's rule, under the thumb study's. The rows are tall enough (the bar's 56 points are 9.3 mm), so the risk is a horizontal miss, which selects the neighbouring adjustment and leads to a drag on the wrong one. The selected adjustment's name above the ruler, and a selection haptic, are what catch it.

**The ruler.** A sweep of 250 points for ±1.5 stops gives 83 points a stop and about 4 points for each 0.05 step, which a thumb can hold. Two things in the note need care. Gear-down by moving the finger up and away will fire by itself: a right thumb sweeping left rises along its arc [R11], by a few tens of points over 250 (my estimate; unverified), so gear-down needs a dead zone and its label. A finger also moves a little as it lifts, so the value should be the one held just before the lift (a known technique; its size on iPhones is unverified). And a double-tap to reset has to require no movement, or two quick nudges will reset the value.

**System gestures.**
- **The home indicator.** A puts taps (the module bar) next to it and drags in the middle row. D puts its ruler, a horizontal drag, from y = 772 to 840, directly above the 34 points where a horizontal swipe switches apps. A thumb landing low for a ruler drag risks that switch (the system's threshold is unverified). A's order is the safer one.
- **iOS 26's back swipe from the content.** `interactiveContentPopGestureRecognizer`, new in iOS 26, pops a navigation stack when a person pans horizontally anywhere in the view [R21]. If the editor is pushed with the zoom transition, the swipe to the next photo, C's horizontal drag and every horizontal control compete with it. The editor has to turn it off, or not be a pushed view.
- **The zoom transition's own gestures.** The note uses SwiftUI's zoom transition to open a photo [R22]; that transition can be dismissed interactively by dragging down or pinching (from Apple's 2024 presentation; unverified in today's documentation). The swipe down to close comes free, but a pinch-in at Fit could close the editor instead of zooming out, and a drag in Crop could start a dismissal. Both need turning off inside the tools.
- **Control Centre and Notification Centre.** The top bar starts at y = 62, clear of the top edge. With the controls hidden, nothing interactive is near the top, so deferring the system's top-edge gestures [R15] is needed only in Crop and Remove, where a handle can sit at the top of the photo.
- **Accidental edits.** Looks applies the recipe at the strip's centre when the finger lifts after scrolling, so browsing changes the edit; preview while scrolling and apply on a tap. B's list and E's page swipe "between rows" both share their space with sliders; C's pinch has the problem above.

### 4. Muscle memory and discoverability

**What the marking-menu research found.** Kurtenbach and Buxton measured how many items each level of a hierarchic marking menu can hold, and how deep it can go, before marks become too slow or too error-prone [R1]. The figure the note uses, eight items at two levels, is the commonly cited result, but I couldn't read the full text today (unverified). Their field study [R2] followed two people editing for 8.55 hours over six days and 10.1 hours over 29 days, making 5,237 selections. Once expert, both used marks extensively, and a mark was on average 3.5 times faster than a selection from the menu. The transition wasn't one way: experts went back to the menu to refresh their memory of its layout, especially after a break. Three cautions follow for D. The transition was seen after thousands of selections in intensive work, while a phone edit is a short, irregular session. The input was a mouse or pen, not a thumb gripping the phone; Lepinski, Grossman and Fitzmaurice found high angular accuracy for directional finger gestures, but on a multitouch table [R6]. And Zhao and Balakrishnan found a series of simple marks more accurate and faster than one zig-zag compound mark, and needing less space [R3], which matters in a hub row 88 points tall.

**Do people make the move?** In general, rarely. In a survey of 251 experienced Word users, most rarely used keyboard shortcuts even though they were faster [R7]; Scarr and colleagues describe the same failure to switch, and the dip in performance that discourages it [R8]. Marking menus are the exception because the novice's movement is the expert's: the novice presses, waits for the menu, and drags to the item, so every use rehearses the mark. **D's tap path breaks that property.** Tapping the hub, then Light, then Exposure teaches which directions the items lie in, but not the stroke. The note's claim that "each tap a novice makes on the ring rehearses the direction an expert flicks" holds for the knowledge and not for the movement. D's sighted novice path should be press, wait 0.3 seconds, and slide to the item, with taps kept for VoiceOver and Switch Control. Without that change I'd expect most people to stay on taps and pay three per adjustment (a prediction, not a measurement).

**What A has instead.** Fixed visible positions give an expert path of their own: with CommandMaps, a flat and spatially stable layout, experienced users were faster than with menus or the Ribbon, and novices were no slower [R9]. A's two taps at learnt places are the same kind of path. Its ceiling is about one action per adjustment above D's, and it has no transition to make. A could add a stroke accelerator without hiding anything: press a module's tab and slide up onto a slot in its strip, then lift, as iOS's menus allow a press, slide and release on their items (unverified for custom controls).

**What A loses by layering.** Each layer is a second route to the same result, which splits practice between two half-learnt paths. The pull-up list places its rows by scroll position, so they're learnt as names, not places, which weakens principle 3. The drag on the photo takes away the swipe to the next photo. Groups swapping the strip, and the strip paging at the accessibility sizes, make a slot mean different things in different states. And a layer only helps if it's found: the pull-up needs a visible grabber, as Apple asks of resizable sheets [R5b], and search needs a button, not only a place in More.

### 5. iOS 26 and 27 conventions

**Where the concepts fight the system.**
- **The top bar,** as above: eight items against the toolbar guidance [R5].
- **The module bar as a tab bar.** Apple's tab bars are for navigation, not actions [R5a]; switching modules is closer to navigation, so a tab-like bar is defensible. But a system tab bar now floats on Liquid Glass and can minimise as content scrolls; I'd build a custom bar with the tab-bar accessibility semantics rather than use the system's tab view. The guidance also asks for monochrome tab bars over colourful content [R5a], which argues against tinting the bar to show a mask's context; the pill and a neutral outline do it without colour.
- **Glass over the photo.** Liquid Glass lets content show through beneath controls [R13]; over a photo, it tints and blurs what's beneath it, which is the wrong thing next to a colour judgment. A's uncovered canvas avoids it. When zoomed in, controls over the photo should use the clear variant with Apple's dimming layer [R13], and D's open ring needs the regular variant for its labels.
- **B's sheet.** Apple expects a sheet to be dismissed by swiping down, and only one sheet to show at a time [R5b]. B's sheet is always there, so History, Copy Settings and other sheets would stack on top of it. B should be built as an inline panel with detents, not a system sheet; and Apple's medium detent is about half the screen [R5b], which is where B fails principle 1.
- **Custom gestures.** Apple asks that shortcut gestures supplement standard ones, not replace them, that they be discoverable, and that they not conflict with the system's gestures [R16]. D's flick supplements the tap; C's drag on the photo replaces the swipe to the next photo and the swipe to close.
- **Slider direction.** Apple puts a slider's minimum on the leading side [R16a]. In right-to-left languages that mirrors the ruler, so "right is more" is a decision, not a given.

**Where they benefit.** A's row of buttons with rings matches Photos' Adjust row in iOS 26 and 27 ([editors, Apple Photos](MOB-mobile-editors.md#apple-photos-ios-26-and-what-ios-27-changes)), which iPhone owners know already. The zoom transition gives the opening animation and an interactive close for free. The Large Content Viewer is the system's answer for bars that can't grow [R20]. System glass components follow Reduce Transparency and Increase Contrast without extra work [R13]. A and D, whose canvas isn't covered, need the least glass.

### 6. Ranking and what to prototype

**Ranking: A, E, B, D, C.** A meets every principle on conditions that can be fixed. E's search is what makes the rest accessible, but its deck makes positions personal. B and D tie on the principles; I put B ahead because its costs are known from Lightroom and Darkroom, while D's rest on an assumption nobody has tested with thumbs. C fails principles 4, 7 and 8.

**Prototype 1: A, with layers, as the note proposes, changed in five ways.**
1. Search is a shared part of both prototypes, as a button on the first level, not a switch: it's the Voice Control path.
2. The pull-up has a visible grabber on the strip.
3. C's drag on the photo is off by default and tested in one session of its own, since it costs the swipe to the next photo and meets iOS 26's back swipe.
4. Undo has a place within the thumb's reach (where is question 1 below).
5. The slide from a module's tab onto its strip, as a stroke accelerator that hides nothing.

**Instead of D in full: a stroke rig first, then B as Prototype 2.** The rig is a hub with two levels of eight targets and logging, built in the harness. It measures the error and time of each direction and each pair, with the right thumb and the left, on the SE and the largest iPhone, comparing three paths: taps, press-wait-slide, and two simple flicks against one compound stroke. D is built in full only if expert two-level strokes stay under an error rate the owner sets; I'd suggest 5%. Prototype 2 is then B, the model the owner's users know, so that A's gain in photo and B's gain in seeing several sliders are measured against each other rather than assumed.

**What each must measure.**
- Time per task, from the photo opening to the edit being committed, in each of three sessions on separate days, and once more after a week away, since experts in [R2] fell back to the menu after a break.
- Errors: a wrong module or adjustment selected, a wrong direction (the rig), any change to a value the task didn't ask for (read from the edit's history), and each Undo.
- Precision: the final value's distance from the target (Exposure +0.40 within 0.05, Temp 6100 K within 50 K, Angle −1.8° within 0.1°) and the time from first touch on the control to its last change.
- Reach failures: touches with a second hand, use of Reachability, changes of grip seen on video, and touches that land on a neighbouring target.
- System gestures triggered by accident: going home, switching apps, Control Centre, the back swipe, the zoom transition's dismissal.
- Photo visibility: the share of each task's time with the canvas at least half the screen's height (Prototype 1's pull-up, B's detents).
- Discovery: whether each layer is found without instruction, and in the rig, the share of selections made by stroke in each session.
- Preference after the third session, and one pass of each prototype with VoiceOver, Switch Control, Voice Control and AX5 on the SE.

**The tasks:** (a) brighten to Exposure +0.40 and warm to Temp 6100 K; (b) make a Sky mask and set its Exposure to −0.70; (c) crop to 4:5 and straighten to −1.8°; and the note's fourth, (d) lift Shadows and lower Orange Luminance. I'd add a fifth if there's time: set Highlights and Whites against each other, switching between them three times, which is A's named weakness and B's strength.

### 7. Questions for the owner

1. Undo is used while editing, so where should it sit within the thumb's reach: a slot in the control area, a two-finger tap on the photo, or both?
2. The top bar doesn't fit an iPhone SE: may History, Share and the photo's position move into More and the filmstrip?
3. Should a module open on the adjustment last used in it (fewer taps) or always on its first (one habit for every photo)?
4. Is editing with the phone held sideways in scope for landscape photos, which would nearly double their size?
5. Is the iPhone Duo in scope? Its outer screen leaves A's canvas under half its height.
6. Should D begin as a stroke rig rather than a full prototype, with B as the second prototype, and what error rate would justify building D?
7. Should Looks apply a recipe when the finger lifts after scrolling, or only on a tap?
8. Should the ruler mirror in right-to-left languages?
9. Can someone who uses VoiceOver or Switch Control every day take part in the prototype sessions?

### Sources for this review

Checked on 13 October 2026. Abstracts were read through OpenAlex and titles checked through Crossref, unless noted.

- [R1] G. Kurtenbach and W. Buxton, "The limits of expert performance using hierarchic marking menus", CHI '93: <https://doi.org/10.1145/169059.169426>. Abstract only; the full text wasn't reachable.
- [R2] G. Kurtenbach and W. Buxton, "User learning and performance with marking menus", CHI '94: <https://doi.org/10.1145/191666.191759>; full text at <https://www.billbuxton.com/MMUserLearn.html>.
- [R3] S. Zhao and R. Balakrishnan, "Simple vs. compound mark hierarchical marking menus", UIST '04: <https://doi.org/10.1145/1029632.1029639>.
- [R4] Apple, Human Interface Guidelines, Buttons and Accessibility (44 × 44 points): <https://developer.apple.com/tutorials/data/design/human-interface-guidelines/buttons.json>, <https://developer.apple.com/tutorials/data/design/human-interface-guidelines/accessibility.json>.
- [R5] Apple, HIG, Toolbars: <https://developer.apple.com/tutorials/data/design/human-interface-guidelines/toolbars.json>. [R5a] Tab bars: <https://developer.apple.com/tutorials/data/design/human-interface-guidelines/tab-bars.json>. [R5b] Sheets: <https://developer.apple.com/tutorials/data/design/human-interface-guidelines/sheets.json>.
- [R6] J. Lepinski, T. Grossman and G. Fitzmaurice, "The design and evaluation of multitouch marking menus", CHI 2010: <https://doi.org/10.1145/1753326.1753663>.
- [R7] D. Lane, H. Napier, S. Peres and A. Sándor, "Hidden costs of graphical user interfaces: failure to make the transition from menus and icon toolbars to keyboard shortcuts", International Journal of Human-Computer Interaction 18(2), 2005: <https://doi.org/10.1207/s15327590ijhc1802_1>.
- [R8] J. Scarr, A. Cockburn, C. Gutwin and P. Quinn, "Dips and ceilings: understanding and supporting transitions to expertise in user interfaces", CHI 2011: <https://doi.org/10.1145/1978942.1979348>. For the wider survey, A. Cockburn, C. Gutwin, J. Scarr and S. Malacria, "Supporting novice to expert transitions in user interfaces", ACM Computing Surveys, 2014: <https://doi.org/10.1145/2659796> (title checked; not read).
- [R9] J. Scarr, A. Cockburn, C. Gutwin and A. Bunt, "Improving command selection with CommandMaps", CHI 2012: <https://doi.org/10.1145/2207676.2207713>.
- [R10] P. Parhi, A. Karlson and B. Bederson, "Target size study for one-handed thumb use on small touchscreen devices", MobileHCI 2006: <https://doi.org/10.1145/1152215.1152260>.
- [R11] J. Bergstrom-Lehtovirta and A. Oulasvirta, "Modeling the functional area of the thumb on mobile touchscreen surfaces", CHI 2014: <https://doi.org/10.1145/2556288.2557354>.
- [R12] S. Hoober, "Design for Fingers, Touch, and People, Part 1", UXmatters, March 2017: <https://www.uxmatters.com/mt/archives/2017/03/design-for-fingers-touch-and-people-part-1.php>. The note's [H13] was also checked today: 1,333 observations, 49% one-handed, 36% cradled, 15% two-handed.
- [R13] Apple, HIG, Materials (Liquid Glass, its variants, dimming, accessibility settings): <https://developer.apple.com/tutorials/data/design/human-interface-guidelines/materials.json>.
- [R14] Apple, HIG, Typography (Dynamic Type sizes): <https://developer.apple.com/tutorials/data/design/human-interface-guidelines/typography.json>.
- [R15] Apple, `preferredScreenEdgesDeferringSystemGestures`: <https://developer.apple.com/tutorials/data/documentation/uikit/uiviewcontroller/preferredscreenedgesdeferringsystemgestures.json>.
- [R16] Apple, HIG, Gestures: <https://developer.apple.com/tutorials/data/design/human-interface-guidelines/gestures.json>. [R16a] Sliders: <https://developer.apple.com/tutorials/data/design/human-interface-guidelines/sliders.json>.
- [R17] Apple, `UIAccessibilityTraits.allowsDirectInteraction`: <https://developer.apple.com/tutorials/data/documentation/uikit/uiaccessibilitytraits/allowsdirectinteraction.json>.
- [R18] Apple, `UIAccessibilityTraits.adjustable`: <https://developer.apple.com/tutorials/data/documentation/uikit/uiaccessibilitytraits/adjustable.json>.
- [R19] Apple, `UIAccessibilityCustomRotor`: <https://developer.apple.com/tutorials/data/documentation/uikit/uiaccessibilitycustomrotor.json>.
- [R20] Apple, `UILargeContentViewerInteraction`: <https://developer.apple.com/tutorials/data/documentation/uikit/uilargecontentviewerinteraction.json>.
- [R21] Apple, `UINavigationController.interactiveContentPopGestureRecognizer` (iOS 26): <https://developer.apple.com/tutorials/data/documentation/uikit/uinavigationcontroller/interactivecontentpopgesturerecognizer.json>.
- [R22] Apple, SwiftUI `NavigationTransition.zoom(sourceID:in:)` (iOS 18): <https://developer.apple.com/tutorials/data/documentation/swiftui/navigationtransition/zoom(sourceid:in:).json>. Its interactive dismissal is (unverified) in this documentation.
- [R23] Apple, iPhone User Guide, Supported models (iOS 27): <https://support.apple.com/guide/iphone/supported-models-iphe3fa5df43/ios>; Apple, iOS: <https://www.apple.com/os/ios/>.
- [R24] Apple, iPhone Duo technical specifications: <https://www.apple.com/iphone-duo/specs/>.
- Redlamp's parameter steps: `packages/RedlampEngineAPI/Sources/ParameterSpec.swift`.
