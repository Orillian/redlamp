+++
deck = "Report a problem or suggest an idea from inside Redlamp, with the details that help, and read all of it before it's sent. Follow the replies in Your Reports, and report a crash or a hang the next time Redlamp opens."
sources = [
  "`README.md`: Reporting bugs and feedback",
  "`packages/RedlampUI/Sources/Feedback/FeedbackSheet.swift`, `FeedbackSheetModel.swift`, `FeedbackActions.swift` (the sheet, its draft and sending)",
  "`packages/RedlampUI/Sources/Feedback/FeedbackReport.swift`, `FeedbackContext.swift`, `SystemSnapshot.swift`, `ActivityLog.swift`, `ActivityRecorder.swift`, `AppLogTail.swift` (what a report holds, and the issue)",
  "`packages/RedlampUI/Sources/Feedback/FeedbackRedaction.swift`, `Screenshots.swift`",
  "`packages/RedlampUI/Sources/Feedback/AreaPicker.swift`, `FeedbackArea.swift`, `FeedbackAreaCatalog.swift`",
  "`packages/RedlampUI/Sources/Feedback/FeedbackClient.swift`, `FeedbackFallbacks.swift`, `FeedbackHistory.swift`, `YourReportsView.swift` (sending, the outbox and Your Reports)",
  "`packages/RedlampUI/Sources/Feedback/Incidents/`: `IncidentCheck.swift`, `IncidentBanner.swift`, `IncidentReport.swift`, `Incident.swift`, `HangWatchdog.swift`, `SessionJournal.swift`, `SessionRecorder.swift`",
  "`apps/RedlampMac/Sources/AppCommands.swift`, `RedlampApp.swift`; `packages/RedlampUI/Sources/Editor/EditorWindowController.swift`, `CanvasArea.swift`, `SaveErrorBanner.swift` (where they open)",
  "`packages/RedlampUI/Sources/Shortcuts/ShortcutAction.swift`, `CommandPalette/ShortcutAction+Palette.swift`; the report buttons in `Inspector/MasksPanel.swift`, `Export/ExportActions.swift` and `CameraBench/CameraBenchView.swift`",
  "`web/lib/feedback.ts` (where the relay keeps attachments)",
]
+++

Report a Bug or Send Feedback files what you write as an issue in Redlamp's public issues on GitHub. It goes through redlamp.app, which files it as the Redlamp Feedback bot, so you don't need a GitHub account. Redlamp is made by one person, who reads every report: bugs get looked into, and ideas shape what comes next.

Anyone can read an issue, so the sheet shows you everything a report holds before you send it, and leaves out what would say who you are or where your files are, unless you add it.

## Opening a report

Click the Feedback button in the toolbar, choose Help › Report a Bug or Send Feedback…, or find it in the command palette, described in [](#start.controls), by a word such as bug, feedback, idea or crash. It has no keyboard shortcut to start with.

Some messages have a button that starts a report for you, with the area chosen and the message quoted at the start of your words, after the words Redlamp said. The buttons are:

- Report… beside a photo that won't open, or Send Feedback… when its format isn't supported yet, which starts an Idea under Photos & Cameras › Unsupported Camera or Format.
- Report… on the banner that says edits couldn't be saved.
- Report… under a message in the Masks panel.
- Report This Problem… in the alert when an export fails, or when some photos of a batch weren't exported.
- Report This Problem… in the Camera Bench window, which Help › Test Your Camera… opens.

The first time, a note headed Before you send a report asks you to keep reports friendly and constructive, and says that they're public. Click Continue. The note comes back only if its words change.

## Writing a report

1. Choose the Kind: Bug, Idea or Question.
2. Check the Area. Redlamp suggests the one you were using and says so under it; click it to choose another.
3. Write a Title of one line.
4. Fill in the boxes under it. The first is needed; the others help.
5. Add screenshots if they show the problem.
6. Under Included with your report, choose what goes with your words, and click Preview the Report… to read the issue as GitHub will show it.
7. Click Send Report.

Each kind asks for different things, and gives the issue a label of its own on GitHub:

| Kind | Boxes | Label |
| --- | --- | --- |
| Bug | What happened?, What did you expect?, Steps to reproduce, How often? and Other photos too? | bug |
| Idea | What would you like to do? and How could it work? | enhancement |
| Question | Your question or message | question |

Send Report stays dimmed until the report has an area, a title and words in its first box. The issue's title is the area in brackets, then the first 120 characters of yours, as in [Masking › Objects] Clicking a second object drops the first.

For a bug, Insert Recent Steps, under Steps to reproduce, adds the last things you did, up to 12 of them from the last 15 minutes, as numbered steps you can edit. How often? offers Every time, Sometimes and Once. Other photos too?, shown while a photo is open, offers Yes, those too, No, only this one and Haven't tried. Both start at Not sure.

Redlamp keeps the report you're writing until it's sent. Close the sheet with Cancel, and the next time it opens it says Your unsent report is back as you left it; Start Over clears it. Screenshots aren't kept with it.

### Choosing the area

The 16 areas follow the app, from Develop, Masking and Healing to Export, Saving & Files and Performance & Stability; the last, Something Else, holds General Feedback, Website and Documentation, Command-Line Tool and Not Sure. Click the button beside Area, which reads Choose an area… until one is chosen, to open the picker. Choose an area at the left, read what it covers at the top of the right side, and click the feature your report is about. Each area ends with a feature for the rest of it, such as Something else in Develop.

The search field at the top finds features by the words people use for them: object selector finds Masking › Objects. When nothing matches, choose Something Else › Not Sure. Suggested from what you were doing, under the search field, chooses the suggestion again.

## What goes with it

Under Included with your report, switches choose what goes with your words; all but File names start on. Each adds a section to the issue, folded until someone opens it, and the same in full to a file attached to the issue, `diagnostics.json`.

About what I was doing just now
: Turns the three below it on or off together.

The photo, its edit and its history
: The open photo's format, camera, lens, exposure, size, as-shot white balance and the kind of disk it's on; its edit, with the settings you've changed, each mask and how it was made, the recipe, the crop and the healing spots; and its steps in History. `diagnostics.json` adds the edit as Redlamp's sidecar holds it, so it can be tried on another photo. For a photo kept in Apple Photos, its disk is Apple Photos, with where its original is: on this Mac, in iCloud only, waiting to download, or downloading; while Develop waits for its original, the photo is included with its file name, format and size. Dimmed when no photo is open.

What I did in the last 15 minutes, and the editor's state
: The photos you opened, the tools, panels and commands you used, your edits and masks, the messages you saw, exports, model downloads and slow renders, each with how long before the report it happened; then the tool, the open panels, the zoom, the selected mask and the messages on screen. `diagnostics.json` holds the whole session's activity, up to its last 500 events.

Redlamp's log
: Redlamp's own notices and errors in the Mac's log since Redlamp opened, the last 60 of them.

The Mac and the Redlamp build
: Redlamp's version and build; the version of macOS; the Mac's model, chip, cores, memory and GPU; each display's size, scale, colour space and HDR headroom; the Mac's thermal state and Low Power Mode; the language and region setting; and which of Redlamp's models are downloaded. With it off, the report still names Redlamp's version.

File names (otherwise Photo A, Photo B)
: Off, each photo you've opened since Redlamp started is named by a letter, in the order you opened them: Photo A, Photo B, and after Photo Z, Photo AA. On, their file names go instead.

### What's left out

Paths, folder names, location and serial numbers are never included, as the note under the switches says, and neither is the photo itself. Redlamp doesn't read a photo's location or a camera's serial number for a report, and before anything leaves the Mac it cleans the rest:

- Your home folder becomes ~.
- The open folder, and the folders you've added to Redlamp, become a folder.
- The identifiers Apple Photos gives the photo are taken out.
- Any other path is cut to its last part.
- The names of the albums you've added from Apple Photos become an album, and those of Photos' folders holding them a folder, where a name is three characters or more.
- Unless File names is on, each photo's file name, with or without its extension, becomes its letter.

This covers your own words too, the title included.

::: caution Reports are public
Anyone can read an issue and the files attached to it. Read the preview before you send, and leave out of your words anything else you don't want to be public.
:::

### Screenshots

A report can carry up to 3 images. The first can be Redlamp's window as it was when you opened the sheet: tick Include this screenshot of Redlamp's window to send it. It shows your photo and its file name, whatever File names says. Add Image… adds image files, Paste adds the image on the clipboard, and image files can be dragged onto the section; Remove takes one out.

Each image goes as a JPEG of at most 2560 pixels on its long side, without its metadata, location included. A video can't go with a report: once the report is sent, open it on GitHub and drag the video into a comment, which needs a GitHub account.

## Sending

Click Send Report. Once redlamp.app has filed the issue, the sheet gives its number, as in Thank you. Report #212 is on GitHub. Copy Link copies its address and Open on GitHub opens it. You don't need a GitHub account to read it or its replies.

Under Hearing back, type your GitHub username, with or without the @, and the report names you as its reporter, so GitHub tells you about replies. A name GitHub couldn't have is left out. Without one, Your Reports follows the report for you.

### When it can't be sent

If sending fails, the sheet says why above its buttons, and Send Report becomes Try Again. Under the message are other ways to keep or send it:

Send When Online
: Shown when redlamp.app couldn't be reached. The report waits in Your Reports, under Waiting to send, and goes the next time Redlamp can reach redlamp.app.

Save Report…
: Saves it as a folder holding `report.md`, its screenshots and `diagnostics.json`.

File on GitHub Instead…
: Opens GitHub's page for a new issue with the title and as much of the report as fits, and copies the whole report to paste there. You add the screenshots and `diagnostics.json` yourself. This needs a GitHub account.

Waiting reports are tried when Redlamp opens, whenever you switch back to it, and when you open Your Reports, where Send Now tries them at once. Up to 20 can wait; past that, the oldest is dropped.

### The issue on GitHub

The issue is filed by the Redlamp Feedback bot and labelled in-app, with its kind's label and its area's, such as component:masking. It opens with the area, the kind and the Mac it came from, then your words under their headings and the screenshots, then each detail you included, folded under its own heading, and a link to `diagnostics.json`. The screenshots and `diagnostics.json` are public too. A report too long for GitHub shows fewer lines of activity, history and log, and `diagnostics.json` keeps them all.

## Your Reports

Help › Your Reports… lists the reports sent from this Mac, newest first, and each opens on GitHub. Your Reports… in the report sheet closes the sheet and opens the list, keeping what you've written. The list is kept on this Mac and sent nowhere. It has up to three groups:

Not reported yet
: Crashes and hangs found when Redlamp opened, described under [](#files.feedback.crash-and-hang-reports).

Waiting to send
: Reports that couldn't reach redlamp.app, each with when it was saved, and Send Now. Right-click one and choose Delete to discard it.

Sent
: Each report with a symbol for its kind, its title as the issue has it now, and a line such as #12 · 2 replies · Tracked as MSK-18 · Phase 3 · sent 4 Oct 2026. Tracked as names the item on Redlamp's roadmap that the report has become, and Phase 3 the roadmap phase it's planned in. New marks a report with a reply or a change of state since you last opened the list. Click a report to open it on GitHub, or right-click it for Open on GitHub, Copy Link and Remove from List, which takes it off this list and leaves the issue as it is.

Each sent report shows its state at the right; the pointer over it gives the state in full.

| State | Means |
| --- | --- |
| Open | Not closed yet |
| Completed | Closed as completed |
| Not planned | Closed as not planned |
| Duplicate | Closed as a duplicate of another issue |
| Closed | Closed for another reason |
| Removed | Deleted, or moved where redlamp.app can't see it |

Once you've sent a report, Redlamp asks redlamp.app how your reports are doing, sending their issues' numbers, when it opens and whenever you switch back to it, at most every six hours; Check for replies and changes turns this off. Opening Your Reports checks at once, and Check Now checks again. The Feedback button in the toolbar counts reports with news you haven't seen and those waiting to be sent.

## Crash and hang reports

After Redlamp quits unexpectedly or stops responding, it can offer a report on what happened the next time it opens; the table below says when. Nothing is sent until you've read the report and clicked Send Report.

### When one is offered

A hang is a time when Redlamp didn't respond to clicks or keys. Redlamp notes every hang of 2 seconds or more as it happens, so it knows of a hang even when it's closed in the middle of one.

| What happened in the last session | What Redlamp offers |
| --- | --- |
| It quit unexpectedly | A report on the crash |
| It stopped responding for 2 seconds or more and was closed while stuck, as Force Quit closes it | A report on the hang, which says Redlamp was closed |
| It stopped responding for 10 seconds or more, at any time | A report on the longest such hang |
| It was force quit while it was responding | Nothing, unless a hang lasted 10 seconds or more |
| The Mac restarted or lost power while it was open | Nothing, unless a hang lasted 10 seconds or more |

Each session offers one report at most, a crash before a hang. A hang Redlamp was closed in isn't offered once the Mac has restarted, while a hang of 10 seconds or more is offered however the session ended.

### The banner

The offer is a banner at the top of the photo in Develop, and over the top of the photos in the Library. It reads Redlamp quit unexpectedly or Redlamp stopped responding, then says when and, for a hang, for how long, as in Today at 10:08, for 14 s, and that you can read the report before you send it. In the Library it waits while a banner there says edits couldn't be saved, or that a change didn't reach some photos.

Review Report…
: Opens the report, to read and send. If you cancel it, the banner stays.

Not Now
: Hides the banner and keeps the report in Your Reports, under Not reported yet, for 30 days.

When Redlamp found more than one, the banner offers the newest first, then the others in turn.

### The report

A crash or hang report is a bug report that asks for less. Its Kind is fixed at Bug and its Area at Performance & Stability › Crashes or › Freezes, and its title is made from what happened, as in Crash: EXC_BAD_ACCESS (SIGSEGV) in RedlampEngine or Hang: 14 s, then Redlamp was closed; change it as you like. Under What were you doing?, write anything you remember about what led to it. Three switches choose the rest, all on to start:

What happened, with the threads' stacks
: What went wrong: the exception macOS recorded and why, or how long Redlamp didn't respond and whether it came back; which part of Redlamp it was in; the version and the time; and the threads' stacks, which show what Redlamp's code was doing. `diagnostics.json` holds every thread's stack. Without it, the report needs your own words.

What I did in the 15 minutes before it
: The activity of the session that ended, from 15 minutes before the crash or the hang until the session ended, or until Redlamp responded again after a hang. `diagnostics.json` holds the same events.

The Mac and the Redlamp build
: The same details as a bug report's.

Photos are always named Photo A, Photo B, as they were in that session; the time is given in UTC, so your time zone stays on the Mac; and paths, folder names, location and serial numbers are left out as from any report. No screenshot, photo, edit or log of the session you're in goes with it. Once sent, the report leaves Not reported yet and appears under Sent; if redlamp.app can't be reached, Send When Online keeps it under Waiting to send.

Under Not reported yet, each crash or hang shows when it happened, its exception or how long it lasted, and the day it will be dropped, as in kept until 13 Nov 2026: 30 days after Redlamp found it. Review Report… opens its report, and Remove takes it off the list without sending anything.

::: note Building Redlamp yourself
A Debug or Profiling build offers no crash or hang reports unless its `feedback.offersIncidentReports` setting is on, since Xcode's Stop button ends it without quitting. It also sends every report as a dry run, which files nothing, unless `FeedbackSendsLive` is on; the sheet says so beside Send Report.
:::
