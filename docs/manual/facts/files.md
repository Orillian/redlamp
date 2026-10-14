# Files, Settings and Help — fact sheet for the user manual

Read from the code at commit `5eb32a241` (14 October 2026), on the branch `ux-11/crash-reports`, for section 7.4,
Reporting a bug or sending feedback. Sections 7.1 to 7.3 aren't gathered yet. Every fact cites the file and lines it
was read from; facts marked **(inferred)** were reasoned from the code rather than read as a string. "Label" means a
string literal the app displays. Where `README.md` and the code disagree, both are given in §14.

Files are cited by name; their paths are:

| Name | Path |
| --- | --- |
| `FeedbackActions.swift`, `FeedbackSheet.swift`, `FeedbackSheetModel.swift`, `FeedbackReport.swift`, `FeedbackContext.swift`, `FeedbackRedaction.swift`, `Screenshots.swift`, `FeedbackClient.swift`, `FeedbackFallbacks.swift`, `FeedbackHistory.swift`, `YourReportsView.swift`, `AreaPicker.swift`, `FeedbackArea.swift`, `FeedbackAreaCatalog.swift`, `SystemSnapshot.swift`, `ActivityLog.swift`, `ActivityRecorder.swift`, `AppLogTail.swift` | `packages/RedlampUI/Sources/Feedback/` |
| `Incident.swift`, `IncidentCheck.swift`, `IncidentBanner.swift`, `IncidentReport.swift`, `HangWatchdog.swift`, `SessionJournal.swift`, `SessionRecorder.swift`, `MacCrashReport.swift`, `MetricKitDiagnostics.swift` | `packages/RedlampUI/Sources/Feedback/Incidents/` |
| `AppCommands.swift`, `RedlampApp.swift` | `apps/RedlampMac/Sources/` |
| `EditorWindowController.swift`, `CanvasArea.swift` | `packages/RedlampUI/Sources/Editor/` |
| `EditorModel+Shortcuts.swift`, `FolderLibrary.swift` | `packages/RedlampUI/Sources/Model/` |
| `FeedbackReportTests.swift`, `IncidentCheckTests.swift`, `IncidentReportTests.swift` | `packages/RedlampUI/Tests/` |
| `ShortcutAction.swift` | `packages/RedlampUI/Sources/Shortcuts/` |
| `ShortcutAction+Palette.swift` | `packages/RedlampUI/Sources/CommandPalette/` |
| `MasksPanel.swift` | `packages/RedlampUI/Sources/Inspector/` |
| `ExportActions.swift` | `packages/RedlampUI/Sources/Export/` |
| `CameraBenchView.swift`, `CameraBenchModel.swift` | `packages/RedlampUI/Sources/CameraBench/` |
| `LibraryModuleView.swift` | `packages/RedlampUI/Sources/Modules/` |
| `feedback.ts` | `web/lib/` (the relay on redlamp.app; read only) |

---

## 1. Where Report a Bug or Send Feedback opens

- The toolbar's **Feedback** button (symbol `exclamationmark.bubble`), tooltip "Report a Bug or Send Feedback" (`EditorWindowController.swift:191-198`); it's in the default toolbar, after Theme (`:141-147`).
- **Help › Report a Bug or Send Feedback…** and **Help › Your Reports…**, after What's New and before Keyboard Shortcuts and Test Your Camera (`AppCommands.swift:373-383`). The action's title is "Report a Bug or Send Feedback…" (`ShortcutAction.swift:438`); it has no keys (`:610`) and is in the File & Edit category (`:240-242`).
- The command palette finds it by: bug, report, feedback, issue, problem, idea, feature request, github, crash, support (`ShortcutAction+Palette.swift:192-203`). Your Reports has no palette entry **(inferred: it isn't a `ShortcutAction`)**.
- From a message, with the area set and the message quoted at the start of the first box as `Redlamp said: “…”` (`FeedbackSheetModel.swift:86-89`):
  - Beside a photo that won't open: **Report…** (help "Report a Bug about this photo not opening"), or **Send Feedback…** when the format isn't supported yet (help "Ask for these files to be supported. You can follow the reply in Your Reports.") (`CanvasArea.swift:174-188`). The first is a Bug under Photos & Cameras › A Photo Won't Open, the second an Idea under Photos & Cameras › Unsupported Camera or Format (`EditorModel+Shortcuts.swift:28-35`; titles `FeedbackAreaCatalog.swift:454-457`).
  - The failed save's banner: **Report…** (help "Report a Bug about edits not saving"), under Saving & Files › Edits Not Saved (`CanvasArea.swift:279-286`; `FeedbackAreaCatalog.swift:491-492`).
  - A message in the Masks panel: **Report…** (help "Report a Bug about this message"), its area suggested from what the person was doing (`MasksPanel.swift:337-348`).
  - An export that fails: **Report This Problem…** in its alert, under Export › Export Dialog; a batch with photos not exported: **Report This Problem…**, under Export › Exporting Several Photos, with the list of failures (`ExportActions.swift:181-191, 217-226`; `FeedbackAreaCatalog.swift:411-415`).
  - The Camera Bench window: **Report This Problem…**, a Bug under the Photos & Cameras feature its worst check concerns (`CameraBenchView.swift:183-187`; `CameraBenchModel.swift:288-300`).
- The sheet doesn't open while another sheet is open (`EditorModel+Shortcuts.swift:23-26`; `FeedbackActions.swift:35`).
- Redlamp's window is captured as the sheet opens, so its screenshot shows what the person was looking at (`FeedbackActions.swift:4-5, 44-45`).

## 2. The note

- Shown the first time, and again whenever its words change (`FeedbackSheet.swift:37`; `FeedbackSheetModel.swift:63-65, 100`), before a crash or hang report too **(inferred: the phase is chosen the same way for every report, `:100`)**.
- Title "Before you send a report"; text: "Redlamp is made by one person, and every report is read by that person. Bugs get looked into, and ideas shape what comes next." / "Reports are posted on GitHub, in Redlamp's public issues, where anyone can read them. You'll see everything a report holds before you send it, and nothing that names you, your files or where they are goes with it unless you add it." / "Please keep it friendly and constructive. Saying what you saw, and what you expected instead, helps most." / "Thank you for helping make Redlamp better." Buttons **Cancel**, **Continue** (`FeedbackSheet.swift:48-73`).

## 3. The report

- **Kind**: a segmented picker, **Bug**, **Idea**, **Question** (`FeedbackSheet.swift:132-135`; `FeedbackReport.swift:9-22`). GitHub labels: bug, enhancement, question (`FeedbackReport.swift:24-31`).
- **Area**: a button reading the area's path or "Choose an area…", opening the picker (`FeedbackSheet.swift:136-152`). Footer while it's the suggestion: "Suggested from what you were doing. Change it if it's about something else." (`:154-156`). The suggestion: a message on screen first, then an open workspace, then the tool and what's selected in it, then the last edit (`FeedbackContext.swift:128-168`).
- **Title**: placeholder "What went wrong, in a line" (Bug), "What you'd like, in a line" (Idea), "Your question, in a line" (Question) (`FeedbackSheet.swift:160, 293-302`). The issue keeps the first 120 characters (`FeedbackReport.swift:128, 150-154`).
- First box: "What happened?", "What would you like to do?", "Your question or message" (`FeedbackSheet.swift:161, 305-311`).
- Second box, not for a Question: "What did you expect?" (Bug), "How could it work?" (Idea) (`:162-168`).
- Bug only: "Steps to reproduce", with **Insert Recent Steps** (help "Adds the last things you did, from the activity this report includes"; dimmed with no activity) (`:169-175`). It adds up to the last 12 events of the last 15 minutes, without system events and messages, as numbered lines after any already there (`FeedbackSheetModel.swift:160-168`).
- Bug only: **How often?** Not sure, Every time, Sometimes, Once (`FeedbackSheet.swift:176-180`; `FeedbackReport.swift:34-48`). **Other photos too?**, only while a photo is open: Not sure, Yes, those too, No, only this one, Haven't tried (`FeedbackSheet.swift:181-186`; `FeedbackReport.swift:50-64`).
- **Send Report** is enabled once the report has a title, words in its first box and an area (`FeedbackSheetModel.swift:146-148`; `FeedbackReport.swift:142-147`).
- Draft: kept on every change until it's filed or queued, without its screenshots; restored next time only when it has words in it, with "Your unsent report is back as you left it." and **Start Over** (`FeedbackSheetModel.swift:41-43, 90-92, 170-178, 189-191, 209-236`; `FeedbackSheet.swift:122-130`). A report from a message or a crash starts from its prefill instead (`FeedbackSheetModel.swift:79-94`).

## 4. The area picker

- A popover 580 × 440 points: a search field, "Search, for example “object selector” or “export”"; under it, while not searching, a link "Suggested from what you were doing: <path>"; areas at the left, the chosen area's summary and features at the right; a tick beside the chosen feature; choosing one closes it (`AreaPicker.swift:29-52, 54-76, 98-122`).
- Search matches every word in a feature's title, its area's title or its keywords, up to 30 results with the area under each (`AreaPicker.swift:79-95`; `FeedbackArea.swift:108-126`). No match: "Nothing matches “…”." and "Try another word, or choose Something Else › Not Sure." (`AreaPicker.swift:83-85`).
- The areas, in order: Develop, Masking, Crop & Straighten, Healing, Recipes & Looks, History & Snapshots, Copy, Paste & Sync, Library, Viewing, Export, Focus Stacking, Photos & Cameras, Saving & Files, Workspace, Performance & Stability, Something Else (`FeedbackAreaCatalog.swift:9-561`). Every area but Something Else ends with "Something else in <area>" (`FeedbackArea.swift:36`). Performance & Stability: Slow or Laggy Editing, Crashes, Freezes, Memory, Heat and Battery, Slow Folders and Thumbnails (`FeedbackAreaCatalog.swift:535-558`). Something Else: General Feedback, Website and Documentation, Command-Line Tool, Not Sure (`:559-569`).
- A topic reads "Area › Feature" (`FeedbackArea.swift:88-91`); the area's GitHub label is `component:<area id>` (`:17-20`).

## 5. Included with your report

Section header "Included with your report"; footer "Paths, folder names, location and serial numbers are never included."; button **Preview the Report…** (`FeedbackSheet.swift:192-214`). Defaults: all on but File names; the photo off without an open photo (`FeedbackReport.swift:66-78`; `FeedbackSheetModel.swift:95-97`).

| Switch | What it adds | Source |
| --- | --- | --- |
| About what I was doing just now | On while any of the next three is; sets the three together | `FeedbackSheet.swift:193`; `FeedbackSheetModel.swift:107-116` |
| The photo, its edit and its history (indented; dimmed with no photo) | Photo table: file name or alias, Format, Camera, Lens, Exposure, Size, As-shot white balance, Look in the file, Lens correction, Disk ("APFS, internal", "smbfs, network", "iCloud Drive"), Notice. Edit: process version, treatment, Base Look, white balance, recipe, each panel's changed sliders, point curve, masks (kinds, adjustments, amount, AI model and revision), crop, orientation, healing spots, snapshots. This session's history, the latest 40 steps in the issue. `diagnostics.json` adds the edit in the sidecar format | `FeedbackSheet.swift:195-196`; `FeedbackReport.swift:259-275, 349-385, 459-470`; `FeedbackContext.swift:177-270` |
| What I did in the last 15 minutes, and the editor's state (indented) | The activity of the last 15 minutes, the latest 150 events in the issue, each with how long before the report it was; Editor state: Tool, Panels open, Zoom, Before / After, Selected mask, Focused slider, Photos in the folder, Photos selected, Hidden, On screen. `diagnostics.json` holds the whole session's activity, the latest 500 events | `FeedbackSheet.swift:197-200`; `FeedbackReport.swift:132-133, 205-210, 276-301, 447-449`; `ActivityLog.swift:46, 111-113` |
| Redlamp's log (indented) | Redlamp's own entries at notice level or above from the unified log since the session began, the last 60 | `FeedbackSheet.swift:201`; `AppLogTail.swift:4-26`; `FeedbackActions.swift:41, 53` |
| The Mac and the Redlamp build | Redlamp's version, build, commit and configuration; macOS and its build; the Mac's model, chip and cores; memory; GPU and working set; each display's size in points, scale, colour space and SDR or HDR headroom; thermal state and Low Power Mode; locale; each downloadable model and whether it's on the Mac. Off, the issue still reads "From: Redlamp <version>" | `FeedbackSheet.swift:204`; `SystemSnapshot.swift:28-85`; `FeedbackReport.swift:230-232` |
| File names (otherwise Photo A, Photo B) | Off: photos are named by alias. On: file names, and `diagnostics.json` lists each alias with its file name | `FeedbackSheet.swift:205`; `FeedbackReport.swift:451` |

- The activity records photos opened (as aliases), tools, panels, Before / After, zoom, selections, masks, model downloads, healing modes, the Stack workspace, messages and errors shown, exports, renders slower than 400 ms, thermal state and memory pressure; actions and edits are recorded where they happen (`ActivityRecorder.swift:1-133`).
- `diagnostics.json` is attached only when a detail is included (`FeedbackReport.swift:174-178, 434-437`).

## 6. What's left out

- Location and serial numbers are never read into the report: Redlamp doesn't read them into its own types, and this never asks ImageIO for them (`FeedbackContext.swift:8-9`).
- Aliases: "Photo A", "Photo B" … "Photo Z", "Photo AA", by the order photos were first opened this session (`ActivityLog.swift:120-146`).
- Redaction of the issue's body and of `diagnostics.json`: each known folder (the open folder and the folders the person added, `FeedbackContext.swift:122`; `FolderLibrary.swift:90-91`) becomes "…/" before what's inside it, or "a folder"; the home folder becomes "~"; any other path of two or more parts becomes "…/<last part>"; unless File names is on, each photo's file name, and its name without the extension, becomes its alias (`FeedbackRedaction.swift:35-72`; tests `FeedbackReportTests.swift:300-317`).
- The body includes the person's own words, so they're redacted too (`FeedbackReport.swift:189-194`). **The title is not**: `issueTitle` is never passed through the redactor (`FeedbackReport.swift:150-154`; `FeedbackClient.swift:138-141`), and the relay only escapes HTML comments in it (`feedback.ts:136, 148-150`).
- The photo itself is never attached: the attachments are the screenshots and `diagnostics.json` (`FeedbackClient.swift:122-143`).

## 7. Screenshots

- Section "Screenshots": the window's screenshot with **Include this screenshot of Redlamp's window**, off to start, and "It shows your photo and its file name, as they were when you opened this, and it will be public." (`FeedbackSheet.swift:411-422`; `FeedbackSheetModel.swift:50`). Each added image with its name and **Remove**; **Add Image…** (an open panel, prompt "Add"), **Paste**, "Up to 3"; images can be dropped on the section; footer "Images lose their metadata, location included, before they're sent. To show a video, add it to the report on GitHub once it's sent." (`FeedbackSheet.swift:424-466`).
- At most 3, the window's included (`FeedbackReport.swift:131`; `FeedbackSheetModel.swift:118-124`). Each is re-encoded as a JPEG no larger than 2560 pixels on the long edge and about 1.1 MB, with no metadata; the window capture needs no Screen Recording permission (`Screenshots.swift:6-34, 58-89`).

## 8. Preview

- "The report, as it will appear on GitHub": the title, the labels, "Attached: …", the body in monospace; **Copy** (title and body) and **Done** (`FeedbackSheet.swift:485-530`).

## 9. Hearing back

- Section "Hearing back": **GitHub username** (placeholder "Optional") and **Your Reports…**, which closes the sheet and opens Your Reports; footer "With a GitHub account, you're mentioned in the report and notified of replies. Either way, Help › Your Reports lists what you've sent, with a link to each report." (`FeedbackSheet.swift:217-232`; `FeedbackActions.swift:49-52`).
- The name may start with @; it's mentioned as "**Reported by:** @name" only if it's 1 to 39 letters, digits and single hyphens, not starting with one (`FeedbackReport.swift:164-172, 233-235`).

## 10. Sending

- Footer text: "Reports are public. Please be kind: a person reads every one." or, in a Debug or Profiling build, "Debug build: sending is a dry run, and files nothing."; **Cancel**; **Send Report**, or **Try Again** after an error (`FeedbackSheet.swift:250-269`). Debug and Profiling builds send dry runs unless `FeedbackSendsLive` is set (`FeedbackClient.swift:71-79`).
- The relay is `https://redlamp.app/api/feedback`, which files the issue as the Redlamp Feedback bot, so nobody needs a GitHub account (`FeedbackClient.swift:49-53`).
- Filed: "Thank you. Report #<n> is on GitHub.", "Help › Your Reports lists it with its status, and links to it. You don't need a GitHub account to read it or its replies.", "To add a video, open the report on GitHub and drag the video into a comment. That needs a GitHub account.", **Copy Link**, **Open on GitHub**, **Done** (`FeedbackSheet.swift:567-592, 608-611`).
- Errors: "Redlamp couldn't reach redlamp.app: <reason>", "The report couldn't be filed (<status>): <message>", "The report was sent, but the reply couldn't be read." (`FeedbackClient.swift:31-42`). Under the error: **Send When Online**, only when redlamp.app couldn't be reached (help "Keep the report and send it the next time Redlamp can reach redlamp.app"); **Save Report…**; **File on GitHub Instead…** (help "Opens GitHub's new-issue page and copies the whole report; needs a GitHub account") (`FeedbackSheet.swift:236-249`).
- Save Report…: a save panel named "Redlamp Report <date>", "Saves the report as a folder: report.md, its screenshots and diagnostics.json." (`FeedbackSheet.swift:273-284`; `FeedbackFallbacks.swift:36-46`).
- File on GitHub Instead…: GitHub's new-issue page for `pdcgomes/redlamp` with the title and as much of the body as fits in 7,000 characters of address, "(Shortened: paste the full report from your clipboard here.)" when cut; the whole report copied, with "(attach <name> here)" in place of each attachment (`FeedbackFallbacks.swift:6-34, 48-50`; `FeedbackSheet.swift:286-291`).
- Send When Online: "Saved, to send later", "Redlamp sends it the next time it can reach redlamp.app. Until then it waits in Your Reports.", **Your Reports…**, **Done** (`FeedbackSheet.swift:532-557`; `FeedbackSheetModel.swift:208-214`).
- The outbox keeps 20 reports, the oldest going first; it's sent at launch, whenever Redlamp becomes active, when Your Reports opens, and with Send Now; what can't be sent stays (`FeedbackHistory.swift:127-128, 243-267`; `FeedbackActions.swift:10-28`; `YourReportsView.swift:64, 108-110`).

## 11. The issue

- Title: "[Area › Feature] title", as in "[Masking › Objects] Clicking a second object drops the first" (`FeedbackReport.swift:149-154`). Labels: in-app, the kind's label, `component:<area>` (`:156-158`).
- Body: a hidden line `<!-- redlamp-feedback v1 {…} -->` with the report's ID, kind, version, area and, for a crash or hang, its kind, never the person's words (`:321-331`); "**Area:** … · **Kind:** … · **How often:** … · **Other photos:** …"; "**From:** Redlamp <version> on macOS <x>, <model> (<chip>)"; "**Reported by:**"; the person's words under "What happened", "What I expected", "Steps to reproduce" (Bug), "What I'd like to do", "How it could work" (Idea) or "Message" (Question); "Screenshots"; folded `<details>` sections: Photo, Edit (process version N), This photo's history (N steps), What happened before (last 15 minutes, N events), Editor state, System, Redlamp's log (N entries); then "diagnostics.json has these details in full, with the photo's edit in Redlamp's sidecar format." and "Sent from Redlamp's Report a Bug or Send Feedback." (`:222-319`).
- Too long for GitHub (60,000 characters): the activity, log, history and stacks shrink until it fits, else it's cut with "*Shortened to fit GitHub's limit; diagnostics.json has everything.*" (`:128-130, 189-220`).
- The relay stores screenshots and `diagnostics.json` in a public attachments repository, one folder per report by month (`feedback.ts:4-13, 152-156`); README names it (README.md:1280).

## 12. Your Reports

- A sheet 620 × 540 points: "Your Reports", **Check Now** (dimmed with nothing sent or while checking), a spinner while checking; "Reports sent from this Mac. Each opens on GitHub, where anyone can read it and its replies, with or without an account."; empty: "Nothing sent from this Mac yet. Reports you send appear here." (`YourReportsView.swift:17-39`).
- Groups: **Not reported yet** (crashes and hangs, §13), **Waiting to send** (title; "Saved <date>; sends when redlamp.app can be reached"; **Send Now**; right-click **Delete**), **Sent** (`:41-96`).
- A sent report: symbol by kind (ladybug, lightbulb, questionmark.bubble); its title as GitHub has it now; "#12 · 2 replies · Tracked as MSK-18 · Phase 3 · sent 4 Oct 2026" (`YourReportsView.swift:159-226`); **New** while it has a reply or a change of state not seen (`:173-179`; `FeedbackHistory.swift:94-97`); its state at the right. Click opens it on GitHub; right-click **Open on GitHub**, **Copy Link**, **Remove from List** (`YourReportsView.swift:74-93`).
- "Tracked as" comes from a tracker ID at the start of the issue's title ("MSK-18: …"); "Phase 3" is the issue's milestone (`FeedbackHistory.swift:51-54`; `YourReportsView.swift:217-222`).
- States, badge and tooltip: Open / Open (green ringed dot); Completed / Closed as completed (purple tick); Not planned / Closed as not planned (grey slash); Duplicate / Closed as a duplicate (grey squares); Closed / Closed (purple tick); Removed / Removed, an issue deleted or moved where the relay can't see it (grey cross) (`FeedbackHistory.swift:3-49`; `YourReportsView.swift:180-200`).
- Toggle **Check for replies and changes** (help "Asks redlamp.app every few hours how your reports are doing"), on to start; **Done** (`YourReportsView.swift:99-104`; `FeedbackHistory.swift:149`).
- Checks: at launch and whenever Redlamp becomes active, at most every six hours, only once something has been sent and while the toggle is on; opening Your Reports and Check Now check at once, whatever the toggle (`FeedbackHistory.swift:129-130, 221-239`; `FeedbackActions.swift:10-28`; `YourReportsView.swift:108-113`). A check sends the issues' numbers and the Redlamp version to `redlamp.app/api/feedback/status` (`FeedbackHistory.swift:61-78`).
- Opening the list marks everything in it as seen (`YourReportsView.swift:111-112`; `FeedbackHistory.swift:210-219`).
- The toolbar's Feedback button shows a count: reports with news plus reports waiting to be sent (`EditorWindowController.swift:241-245`).
- Kept in Application Support/Redlamp/Feedback (reports.json, outbox.json, incidents.json), never sent anywhere (`FeedbackHistory.swift:110-112, 142-145, 269-276`).

## 13. Crash and hang reports

- Each session keeps a journal in Application Support/Redlamp/Feedback/Session: the activity, the photos opened, the folders shown and the hangs, each line written as it happens, and a last line once it quits; it keeps the latest 500 events (`SessionJournal.swift:5-10, 109-116, 140-149, 268-269`).
- The hang watchdog marks the main thread away from its run loop for 2 s or more, checking every second, while it lasts and with its length once it's back; its clock stops while the Mac sleeps (`HangWatchdog.swift:6-11, 45-47`). A hang it came back from is written into the activity as "Not responding for 14 s" (`SessionRecorder.swift:48-55`).
- What the next launch offers, in order (`IncidentCheck.swift:41-79`):
  1. A crash, from macOS's crash report (`~/Library/Logs/DiagnosticReports`, `MacCrashReport.swift:3-10`) merged with MetricKit's (`IncidentCheck.swift:81-92`).
  2. Else, if the session didn't quit and the Mac didn't restart since, the hang it ended in, as a Force Quit of a stuck Redlamp ends it: `endedSession` (`:62-65`; `Incident.swift:56-57`).
  3. Else the longest hang of 10 s or more, however the session ended, after a restart too (`IncidentCheck.swift:47-48, 66-69`; `IncidentCheckTests.swift:33-52`).
  4. Else nothing: a Force Quit of a Redlamp that was responding, or the Mac restarting during the session, offers nothing (`IncidentCheck.swift:41-45`; `IncidentCheckTests.swift:54-59`).
  A session that ended without quitting and has no crash report yet waits 6 s for one (`IncidentCheck.swift:49-51, 117-119`).
- Only sessions of the same bundle ID and the same kind of build are read, and their journals are removed once read (`IncidentCheck.swift:97-128`).
- Development builds (Debug and Profiling, `RedlampApp.swift:183-189`) keep and offer what's found only with the defaults key `feedback.offersIncidentReports`, since Xcode's Stop button and the regression suite end them without quitting (`SessionRecorder.swift:10-12, 41, 81-85`; `RedlampApp.swift:90-96`).
- The banner: over the photo in Develop, below a damaged edit's and a failed save's banners (`CanvasArea.swift:105-113`); in the Library, over the top of the photos, while no culling problem is shown in its place (`IncidentBanner.swift:43-48`; `LibraryModuleView.swift:20-22, 62`). It shows "Redlamp quit unexpectedly" or "Redlamp stopped responding" (`Incident.swift:72-75`) and "Today at 10:08. You can read the report before you send it.", a hang's with ", for 14 s" after the time (`IncidentBanner.swift:50-63`). **Review Report…** (help "Opens the report, to read before you send it") and **Not Now** (help "Keeps it in Help › Your Reports for 30 days") (`IncidentBanner.swift:25-32`).
- The banner offers the newest crash or hang not dismissed (`FeedbackHistory.swift:156-170`). Not Now dismisses it: it stays listed and the banner moves to the next (`:172-178`; `IncidentReportTests.swift:287-299`). Cancel in the report dismisses nothing **(inferred: only `dismiss`, `record`, `enqueue` and `forgetIncident` change the list, `FeedbackHistory.swift:172-252`; `FeedbackActions.swift:77-86`)**.
- The report (`FeedbackSheet.swift:314-383`, 620 × 660 points, `:17-18`): the headline with "Today at 10:08, for 14 s, in Redlamp 0.3.2-alpha (431)"; **Kind** fixed at Bug (help "A report on a crash or a hang is a bug"); **Area** Performance & Stability › Crashes or › Freezes (`IncidentReport.swift:6-9`); **Title**, prefilled "Crash: EXC_BAD_ACCESS (SIGSEGV) in RedlampEngine" or "Hang: 14 s, then Redlamp was closed" (`Incident.swift:86-97`); **What were you doing?** with "Optional. Anything you remember about what led to it helps." or, with What happened off, "Without what happened, the report needs your own words."; switches **What happened, with the threads' stacks**, **What I did in the 15 minutes before it**, **The Mac and the Redlamp build**, all on (`FeedbackReport.swift:76-77`); **Preview the Report…**; footer "Photos are named Photo A, Photo B. Paths, folder names, location and serial numbers are never included."; then Hearing back as in §9.
- No screenshot, photo, edit or log of the current session goes with it; it keeps no draft (`FeedbackSheetModel.swift:24-27, 79-85, 216-221`; `FeedbackActions.swift:58-75`). Send needs a title, and words only while What happened is off (`FeedbackReport.swift:142-147`).
- The issue (`IncidentReport.swift:143-188`): "What happened": the headline, Exception, "Not responding for: 14 s, then Redlamp was closed" or "then it responded again", Reason or Reasons, In (the first of Redlamp's own binaries on the crashed thread), Version, When (in UTC, so the time zone stays on the Mac), Recorded by (macOS's crash report, MetricKit, Redlamp's hang watchdog) (`:16-44, 85-108`); "What I was doing"; the crashed thread's stack, the main thread's (always for a hang, and for a crash on another thread), and where an Objective-C exception was raised, each frame as its binary and symbol or offset, up to 200 frames each (`:46-83`; `FeedbackReport.swift:209-210`); "What happened before the crash" or "the hang" (last 15 minutes, N events), to the hang's end for a hang it came back from (`IncidentReport.swift:110-119, 159-175`); System; "Sent from Redlamp's crash and hang reports." (`:186`).
- `diagnostics.json`: every thread, the binaries' UUIDs and load addresses, and the session's whole activity (`IncidentReport.swift:180-184, 204-225`). The incident keeps no identifiers, registers or memory map, and binaries by name, not path (`Incident.swift:3-5`).
- Redacted with that session's photos and folders, always by alias: there's no File names switch (`FeedbackReport.swift:180-185`; `IncidentReport.swift:121-135`).
- Sent: it leaves the list and joins Sent; queued: it leaves the list and waits in the outbox (`FeedbackHistory.swift:191-202, 243-252`; `IncidentReportTests.swift:300-326`).
- Your Reports' Not reported yet rows: the headline; "14 Oct 2026 at 10:08 · EXC_BAD_ACCESS (SIGSEGV) · kept until 13 Nov 2026" (a hang's "for 14 s" in the exception's place); **Remove** (help "Removes it from this list. Nothing is sent.") and **Review Report…**; right-click **Review Report…**, **Remove from List** (`YourReportsView.swift:117-157`). Kept for 30 days from when the launch found it, then dropped at the next launch (`FeedbackHistory.swift:131-132, 152-153`).

## 14. README and code

| README | Code |
| --- | --- |
| "the Feedback button counts replies and changes" (README.md:1282) | It counts reports with news **and** reports waiting to be sent (`EditorWindowController.swift:241-245`). The code is followed |
| "what you did in the last 15 minutes" goes with the report, and `diagnostics.json` "holds the same in full" (README.md:1278) | The issue shows the last 15 minutes; `diagnostics.json` holds the whole session's activity, up to 500 events (`FeedbackReport.swift:132, 449`). Consistent with "in full", but the switch's label names only 15 minutes |
| No text on crash and hang reports yet (README.md:1274-1282) | §13 |

## 15. Read wrongly or confusingly

- The issue's title isn't redacted, while the body and the person's words in it are (§6).
- The activity switches read "the last 15 minutes" and "the 15 minutes before it", but `diagnostics.json` carries the whole session's activity (§5, §13).
- `FeedbackActions.client`'s and `FeedbackRelay.client`'s doc comments give "Redlamp/0.2.1-prealpha (412)" as an example (`FeedbackActions.swift:115`; `FeedbackClient.swift:56`): harmless.

## 16. Screenshots for figures

None of `docs/images` shows the feedback sheet, Your Reports or the banner. The capture scripts the manual's skill names (`scripts/capture-hero.sh`, `capture-promo.sh`, `capture-screenshots.sh`) launch the Debug app with the release app's bundle ID and preferences, saving and restoring them, not in a home of their own, so no figure was captured for 7.4.
