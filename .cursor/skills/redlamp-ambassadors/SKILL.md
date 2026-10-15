---
name: redlamp-ambassadors
description: The ambassadors room, where Redlamp's ambassador programme is run in a canvas the owner triages and sends from. It holds the applications from redlamp.app/ambassadors, the candidates for each wave of invitations with a drafted invitation each, the cohort with their terms, edits and showcases, the quarterly ambassadors' pick (DEC-86), and the replies the owner sends. Use when working on the ambassadors, the ambassador campaign or its recruitment posts, finding or inviting photographers, triaging or replying to an application, onboarding an ambassador, an ambassador's showcase, the monthly ambassadors' call, or the ambassadors' pick.
---

# The ambassadors room

Redlamp's ambassadors are photographers who send an edit a month made in Redlamp and honest feedback, and in return pick one feature a quarter that's built next (DEC-86), join a monthly call with the owner, and have their edits shown with their name wherever Redlamp is seen. The programme, its offer, terms, privacy note, rubric and cadence are in the private social repository's `plans/2026-10-15-ambassadors.md`: read it first, and keep everything the room drafts in step with it. The owner triages, decides and sends; agents find, score, draft and keep the room.

## Where

| What | Where |
| --- | --- |
| The room | `~/.cursor/projects/Users-pedrogomes-src-darkroom/canvases/ws-ambassadors.canvas.tsx`, from [template.tsx](template.tsx). It began as the campaign's workstream canvas and keeps that name. Edit its `workstream` object (Overview, Plan, Decisions, Log) and its `room` object (`scores`, `replies`, `candidates`, `cohort`, `picks`); [room.py](room.py) writes the APPLICATIONS block. A change to the rendering goes into the template and the room together. |
| The owner's marks | `ws-ambassadors.canvas.data.json` beside it: `needsYou`, `applications` (by issue number: `shortlist`, `accept` or `decline`) and `candidates` (by candidate ID: `sent`, `replied`, `applied` or `not now`). Only the canvas writes it. |
| Applications | Issues in the private `pdcgomes/redlamp-ambassadors`, filed by the site's relay (`web/lib/ambassadors.ts`, `web/README.md`), each with its photos and one `.redlamp` sidecar stored beside it, and its fields in a hidden `<!-- redlamp-ambassador v1 {…} -->` marker. |
| Thumbnails | `~/Library/Caches/redlamp-ambassadors/<number>/`, made by `room.py sync`, never committed |
| Ambassadors' raws for showcases | `~/src/redlamp-social/photos/ambassadors/<handle>/`, which git ignores |
| The campaign's posts and assets | The social room (`~/.cursor/skills/redlamp-social`) and `~/src/redlamp-social/marketing/campaigns/ambassadors/` |
| What never goes into the public repository | Applicants' and candidates' names, contacts, photos and replies, and the cohort's details. They live in the room, its data file, the private repository and the social repository's ignored folders; the template holds nobody's details. |

Read `~/.cursor/skills-cursor/canvas/SKILL.md` once per session before the first edit of the room. Link the room in every reply that changes it: `[Ambassadors room](/Users/pedrogomes/.cursor/projects/Users-pedrogomes-src-darkroom/canvases/ws-ambassadors.canvas.tsx)`.

## Every time: know where things stand

1. **Read the owner's marks first.** Fold the `needsYou` marks into `workstream` as `.cursor/skills/workstream-canvas/SKILL.md` describes. Never write the data file.
2. **Run `python3 .cursor/skills/redlamp-ambassadors/room.py sync`, then `status`.** Never take an application or a mark from memory.
3. **Act on the marks:**
   - `accept`: draft the reply with `room.py draft <n> accept --line "<one line about their photos>"`, put it in `room.replies`, and with Gmail connected save it as a draft with `--gmail`. Once the owner says the call went well, add them to `room.cohort` (`termsAgreed: false` until they've agreed), and close the issue with a comment saying so.
   - `decline`: the same with `decline`; the line thanks them for something specific. Close the issue once the owner has sent it. Delete declined applications' files and issues six months after they arrived, as the privacy note promises.
   - `shortlist`: score it on the rubric in `room.scores` if it isn't scored, and say in Needs you what would decide it.
   - A candidate marked `sent` gets a follow-up drafted a week later, once; one marked `applied` is matched to their application.
4. **Bring the room up to date in the same turn:** `status`, `needsYou`, `plan`, a `log` entry and `updated`. Say plainly what you didn't check.

## The rubric

Score each candidate and applicant 1 to 3 on photography, sharing (do they explain their edits?), fit (a Mac with Apple Silicon, raw, edited in Redlamp), spread (genre, camera make and region against the cohort) and engagement (how their audience talks to them, not its size). A 1 on photography or fit is a no. Write a one-line `note` with what decided it. The owner decides; scores only inform.

## Finding candidates and inviting them

- Wave 0 is warm: the Discord, Ko-fi supporters, the Reddit launch thread's commenters, GitHub stargazers whose profiles show photography (`gh api repos/pdcgomes/redlamp/stargazers`, then each profile), and people the owner names. Wave 1 is 25 to 40 photographers with roughly 2,000 to 50,000 followers who post edit breakdowns, recipes or film looks and edit on a Mac.
- Never invent a person, a handle or a figure. Add only people whose public profile you or the owner have seen, with `source` saying where.
- An invitation is personal: one line about their work that's true and specific, the offer in two lines, the ask (edit a photo in Redlamp, apply at redlamp.app/join), and nothing else. Write in the owner's voice, as `.cursor/skills/redlamp-blog/SKILL.md` describes (Writing in the owner's voice). The owner sends every DM and email; agents never contact anyone.

## The cohort

- Ten founding places; a term of six months, renewable; either side can stop.
- Onboarding, once an ambassador has agreed the terms: the Discord role, their ambassador card and badge (the campaign's visual system), their first showcase, and a "Meet the founding ambassadors" post in the social room.
- Each month, record the edits received and the showcases posted in `room.cohort`. An ambassador who sends nothing for two months gets a friendly note drafted for the owner.

## The ambassadors' pick (DEC-86)

1. Early each quarter, shortlist three to five rows that are `Accepted` and `Not started`, in the current phase and sized S or M, from the tracker; the owner approves it (a Needs you item). Add it to `room.picks`.
2. Draft the poll for the ambassadors' Discord channel: each row in plain words with its issue, open a week; the best average rank wins.
3. Add "ambassadors' pick" and the quarter to the winning row's Decision cell in the tracker, sync the issues (`.cursor/rules/tracker-issues.mdc`), and record the result in `room.picks`. When the supporters picked the same row, the ambassadors' second choice also goes next.

## The monthly call

Draft its agenda a few days before: what shipped (`gh release list`), what's being designed (the wireframe canvases), what's next, and the owner's questions. After it, the notes and actions go in the room's log.

## Evolving the room

The owner shapes the room as needs come up. A new tab, state or button goes into the template, the room and this skill in the same change. Commit the template, the skill and `room.py` on main: `Ambassadors room: …`.
