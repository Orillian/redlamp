# Mac App Store compliance

This file is the checklist that decides when Redlamp's Mac App Store build is ready to submit: a paid, one-time purchase with a StoreKit tip jar, the same app as the free download from GitHub and Homebrew (DEC-87). It was compiled on 15 October 2026 from two audits of that date, one of Apple's rules and the legal duties of a sale, the other of the app's code and its shipped bundle (`v0.3.1-alpha`, build 2481, and `main` at `096096602`), and it is checked against the App Review Guidelines last updated on 8 June 2026, the text Apple's page carried on 15 October 2026. It is kept current until the first submission, and then checked again for every App Store release. The build is ready when every row is Compliant or Not applicable, each with its evidence.

## Status

Every row has one of these statuses:

- `Compliant`: the requirement is met; the Evidence column says how it is known.
- `Fix`: work is needed; the last column names the tracker row that does it.
- `Decision`: the requirement can't be met, or shown to be met, until the owner decides; the last column names the DEC row, and the fix that follows it.
- `Not applicable`: the requirement doesn't reach Redlamp, for the one reason given.
- `Unverified`: nobody could check it yet; the Evidence column says what would settle it.

A row that needs a fix and also waits on a decision whose answer settles whether the requirement can be met is marked `Decision`. Where the decision only shapes how the fix is built, the row is marked `Fix`, and the last column names both.

## Summary

### Rows by status

| Section | Compliant | Fix | Decision | Not applicable | Unverified | Rows |
| --- | --- | --- | --- | --- | --- | --- |
| 1. App Review Guidelines | 29 | 36 | 18 | 123 | 2 | 208 |
| 2. App Store Connect | 5 | 18 | 9 | 6 | 2 | 40 |
| 3. Technical checks | 15 | 21 | 1 | 3 | 3 | 43 |
| 4. Apple's trademarks | 0 | 12 | 0 | 0 | 0 | 12 |
| 5. Legal duties of a sale | 9 | 8 | 13 | 2 | 3 | 35 |
| All | 58 | 95 | 41 | 134 | 10 | 338 |

### Fixes, in the order to build them

1. Settle DEC-89 (the firmware model), DEC-90 (the CLI), DEC-91 (the bundle ID) and DEC-92 (the version), which ARC-22 and UX-50 depend on; DEC-91 also has to be settled before the App Store Connect record is created.
2. **ARC-22** (M): the App Store build's own app target, an `AppStore` configuration in every project with the `REDLAMP_APP_STORE` flag, and an `--app-store` mode of the bundle check.
3. **UX-50** (S): the App Store build as a release of its own: no update commands, What's New after App Store updates, no Ko-fi link, no "alpha", no planned-feature entries, and no Experimental tab.
4. **ARC-26** (S): development switches read only in Debug and profiling builds.
5. **ARC-25** (S): licence notices, source offers and trademark notices in the app, for both builds.
6. **ARC-24** (S): the privacy manifest, the export-compliance key, a privacy policy and a support page on redlamp.app, linked from the app.
7. **UX-52** (S, this checklist's estimate): the activity log disclosed and switchable.
8. **ARC-17** (L): the App Sandbox, turned on in the App Store build first.
9. **INF-07** (M, the tracker's 2–3 engineer-weeks): Apple-hosted model packs, after the packs' shared-namespace collision is fixed.
10. **UX-51** (S): the tip jar.
11. **ARC-23** (S): signing, archive, export, validation, upload and TestFlight, with a pass on macOS 27 and 26.
12. **ARC-27** (S, this checklist's estimate, mostly the owner's own time): the App Store Connect record, the agreements, the listing, the review notes and the submission.

Items 2 to 7 change nothing in the direct download except ARC-25 and UX-52, which serve both builds, so they can land before the sandbox. App Store Connect refuses an unsandboxed upload, so the first TestFlight build waits for ARC-17. Two existing rows also need attention before the first submission: UX-44 (Tab through the Export dialog, checked on macOS 27) and RM-03 (Content Credentials, before the EU storefronts open, as DEC-100 decides).

### The owner's decisions

- **DEC-87** (accepted): sell Redlamp on the Mac App Store as a one-time purchase with a tip jar, the same app as the free download.
- **DEC-88:** the price, launch price and timing, the tip jar's tiers, Family Sharing, and universal purchase.
- **DEC-89:** the firmware film model in the App Store build (recommended: left out entirely).
- **DEC-90:** the `redlamp` CLI in the App Store build (recommended: left out).
- **DEC-91:** one bundle ID for both builds, or one of the App Store build's own.
- **DEC-92:** the version number and the alpha stage, and the Welcome page's "It's early" page.
- **DEC-93** *(counsel)*: the models' training-data exceptions for a paid product.
- **DEC-94** *(counsel)*: third-party names and trade dress in the app and the listing.
- **DEC-95:** public reports from a paid app, deletion on request, and the App Privacy answer.
- **DEC-96:** how the sandboxed app reaches cards, Adobe's profile folders and the Pictures folder.
- **DEC-97:** model delivery in the App Store build (recommended: Apple-hosted packs only).
- **DEC-98:** the Ko-fi link and what the listing says about the free download.
- **DEC-99** *(counsel)*: the seller's legal identity, the copyright line, the EU trader details and the licence agreement.
- **DEC-100** *(counsel)*: the EU storefronts and the AI Act's marking of generated fill.
- **DEC-101:** the activity log's consent: a switch or a first-run notice.
- **DEC-102:** keyboard focus shown to Full Keyboard Access users, against the house rule of no focus rings.
- **DEC-103:** the category, the age rating answers and the Accessibility Nutrition Labels.

## 1. App Review Guidelines

Read on 15 October 2026 from <https://developer.apple.com/app-store/review/guidelines/> ("Last Updated: June 8, 2026"); the text was identical to the Wayback Machine's capture of 30 September 2026. Quotes are Apple's.

| Item | Requirement | Applies | Status | Evidence | Fix or decision |
| --- | --- | --- | --- | --- | --- |
| Before You Submit: testing | "Test your app for crashes and bugs" (Before You Submit) | Yes | Fix | Open macOS 27 rows: ARC-19, LIB-50, UX-44, ARC-20; no TestFlight build has been tested | ARC-23: the regression suite and a manual pass on the TestFlight build, sandboxed, on macOS 27 and 26 |
| Before You Submit: metadata | "Ensure that all app information and metadata is complete and accurate" (Before You Submit) | Yes | Fix | No listing, privacy policy or support page yet | ARC-27 |
| Before You Submit: contact | "Update your contact information in case App Review needs to reach you" (Before You Submit) | Yes | Fix | Not entered | ARC-27 |
| Before You Submit: full access | "Provide App Review with full access to your app" and any resources needed (Before You Submit) | Yes | Fix | No accounts, but raw files, a Lightroom Classic catalog and model downloads are needed to see the features | ARC-27: sample raws (CC0) and a small `.lrcat` attached; Generative Remove's 16 GB guidance in the notes |
| Before You Submit: backends | "Enable backend services so that they're live and accessible during review" (Before You Submit) | Yes | Fix | The feedback relay answers 503 unless `FEEDBACK_ENABLED` is 1 (`web/lib/feedback.ts:47-49`, `web/app/api/feedback/route.ts:14`); the bench and What's New relays; the asset packs | ARC-27: relays, What's New and the packs live during review |
| Before You Submit: notes | "Include detailed explanations of non-obvious features and in-app purchases in the App Review notes" (Before You Submit) | Yes | Fix | Not written | ARC-27 |
| Before You Submit: other documentation | Follow the HIG, the marketing guidelines and Apple's trademark guidelines (Before You Submit) | Yes | Fix | Section 4 of this file | ARC-27 |
| 1.1 Objectionable Content | No content that is "offensive, insensitive, upsetting, intended to disgust" (1.1) | Partly: the app ships looks and icons, not content | Compliant | Bundled looks and icons only (build audit §1.1) | ARC-27 keeps screenshot photos suitable for everyone |
| 1.1.1 Defamatory content | No "defamatory, discriminatory, or mean-spirited content" (1.1.1) | No | Not applicable | The app ships no such content | — |
| 1.1.2 Realistic violence | No realistic portrayals of people or animals "being killed, maimed, tortured, or abused" (1.1.2) | No | Not applicable | The app ships no such content | — |
| 1.1.3 Weapons | No depictions that "encourage illegal or reckless use of weapons" (1.1.3) | No | Not applicable | The app ships no such content | — |
| 1.1.4 Sexual material | No "overtly sexual or pornographic material" (1.1.4) | No | Not applicable | The photographer's own photos aren't the app's content, and generative fill only removes, from fixed prompts (RM-10) | — |
| 1.1.5 Religious commentary | No "inflammatory religious commentary" (1.1.5) | No | Not applicable | The app ships no such content | — |
| 1.1.6 False information | No "false information and features, including inaccurate device data or trick/joke functionality" (1.1.6) | Partly: camera support claims and measurements | Compliant | The Camera Bench reports measurements as they are (`docs/camera-bench.md`) | — |
| 1.1.7 Current events | No "harmful concepts which capitalize or seek to profit on recent or current events" (1.1.7) | No | Not applicable | The app has no such content | — |
| 1.2 User-Generated Content | Apps with user-generated content need filtering, reporting, blocking and published contact information (1.2) | Partly: Report a Bug posts people's words and screenshots as public GitHub issues | Decision | "Reports are posted on GitHub, in Redlamp's public issues, where anyone can read them." (`FeedbackSheet.swift:55`). Assessment: a support channel, not user-generated content as the app's experience | DEC-95; ARC-27 says in the notes who moderates the issues and how a report is taken down; ARC-24's support page gives the contact |
| 1.2.1 Creator Content | Creator-content apps must be moderated (1.2.1) | No | Not applicable | The app features no creators' content | — |
| 1.2.1(a) Creator age gating | Creator apps must identify content beyond the age rating and restrict access by age (1.2.1(a)) | No | Not applicable | The app features no creators' content | — |
| 1.3 Kids Category | Kids Category apps must not include links out or purchases outside a parental gate (1.3) | No | Not applicable | Not submitted to the Kids Category | ARC-27 leaves Made for Kids unselected |
| 1.4 Physical Harm | Apps that risk physical harm may be rejected (1.4) | No | Not applicable | A photo editor does nothing physical | — |
| 1.4.1 Medical apps | Medical apps must not give inaccurate data (1.4.1) | No | Not applicable | Not a medical app | — |
| 1.4.2 Drug dosage | Dosage calculators must come from approved sources (1.4.2) | No | Not applicable | Not a dosage calculator | — |
| 1.4.3 Tobacco, drugs, alcohol | No encouragement of tobacco, illegal drugs or excessive alcohol (1.4.3) | No | Not applicable | The app has no such content | — |
| 1.4.4 DUI checkpoints | Only checkpoints published by law enforcement (1.4.4) | No | Not applicable | The app shows no checkpoints | — |
| 1.4.5 Risky activities | No urging of activities that risk physical harm (1.4.5) | No | Not applicable | The app has no such content | — |
| 1.5 Developer Information | "Make sure your app and its Support URL include an easy way to contact you" (1.5) | Yes | Fix | redlamp.app has no email address or contact page; `/support` and `/contact` returned 404 on 15 October 2026 | ARC-24: a support page with an email address, and an address and telephone number where local law requires, linked from Help and used as the Support URL |
| 1.6 Data Security | "Apps should implement appropriate security measures to ensure proper handling of user information" (1.6) | Yes: reports and bench results leave the Mac | Decision | HTTPS relays; file names become "Photo A" by default; screenshots carry no metadata (`Screenshots.swift:6-7`); attachments sit in a public repository's history | DEC-95 decides how a report is deleted; ARC-24 states it |
| 1.7 Reporting Criminal Activity | Crime-reporting apps must involve law enforcement (1.7) | No | Not applicable | Not a crime-reporting app | — |
| 2.1(a) App Completeness | Submissions "should be final versions with all necessary metadata and fully functional URLs"; "placeholder text … and other temporary content should be scrubbed" (2.1(a)) | Yes | Fix | Red Eye shows as "Phase 3" (`EditorTypes.swift:357-361`) and Virtual Copy as "Phase 2" (`ShortcutAction.swift:650-655`, titled by `MenuBarKeys.swift:49`); no privacy or support URL works yet | UX-50 hides planned features in the App Store build; ARC-24 the URLs |
| 2.1(b) In-app purchases complete | In-app purchases must be "complete, up-to-date, visible to the reviewer and functional" (2.1(b)) | Yes: the tip jar | Fix | Nothing imports StoreKit yet | UX-51; ARC-27 names its place in the notes |
| 2.2 Beta Testing | "Demos, betas, and trial versions of your app don't belong on the App Store – use TestFlight instead." (2.2) | Yes | Decision | `MARKETING_VERSION = 0.3.1-alpha` (`Version.xcconfig:2`); the Welcome page says "Redlamp is an alpha" (`WelcomeView.swift:99`); About shows the version (`SettingsView.swift:230-234`) | DEC-92; ARC-22 sets a numeric version, UX-50 removes the stage from what the build shows |
| 2.3 Accurate Metadata | Metadata, "including privacy information", must "accurately reflect the app's core experience" (2.3) | Yes | Fix | No listing or App Privacy answers yet | ARC-27; ARC-24 drafts the privacy answers |
| 2.3.1(a) Hidden features | "Don't include any hidden, dormant, or undocumented features"; new features described in the Notes for Review (2.3.1(a)) | Yes | Decision | The firmware film model behind Settings › Experimental on `main` (`SettingsView.swift:55-57`, TON-49, TON-50), which the App Store build compiles out, embedding no `RedlampAutomation.framework` (ARC-22, 66b3e7761, 5ab089dea), though its Experimental tab remains; engine variables, `REDLAMP_GENERATIVE_MODEL` (`RedlampEngine+GenerativeFill.swift:27`) and endpoint overrides read in Release (build audit §3.4) | DEC-89; ARC-26 the switches; UX-50 the Experimental tab; ARC-27 lists every downloadable model in the notes |
| 2.3.1(b) Egregious behaviour | "Egregious or repeated behavior is grounds for removal" (2.3.1(b)) | No | Not applicable | A consequence of breaking the other rules, not a requirement of its own | — |
| 2.3.2 In-app purchases in metadata | Metadata must "clearly indicate whether any featured items … require additional purchases" (2.3.2) | Yes | Fix | Not written | ARC-27: the description says tips are optional and unlock nothing |
| 2.3.3 Screenshots | "Screenshots should show the app in use"; App Review approves only sets where "more than half of screenshots show the app in use" (2.3.3 and its reference page) | Yes | Fix | Not made | ARC-27 |
| 2.3.4 Previews | "Previews may only use video screen captures of the app itself." (2.3.4) | Only if a preview is made | Fix | The promotional videos in `video/` are not screen captures | ARC-27: any preview made from screen recordings of the app |
| 2.3.5 Category | "Select the most appropriate category for your app" (2.3.5) | Yes | Fix | `LSApplicationCategoryType` is `public.app-category.photography` (`apps/RedlampMac/Project.swift:25`) | ARC-27 sets Photography as the primary category; DEC-103 the secondary |
| 2.3.6 Age rating | "Answer the age rating questions in App Store Connect honestly" (2.3.6) | Yes | Decision | Draft answers give 4+ (section 2) | DEC-103 |
| 2.3.7 Name and keywords | No "trademarked terms, popular app names, pricing information" in metadata; names of 30 characters or fewer; no prices (2.3.7) | Yes | Decision | Lightroom, Kodak, Fujifilm and film stock names appear in the app | DEC-94; ARC-27 keeps them, "free" and prices out of the name, subtitle, keywords and screenshots |
| 2.3.8 Metadata for all audiences | Icons, screenshots and previews "adhere to a 4+ age rating" (2.3.8) | Yes | Fix | Not made | ARC-27 |
| 2.3.9 Rights to materials | "You are responsible for securing the rights to use all materials in your app icons, screenshots, and previews" (2.3.9) | Yes | Fix | Not made | ARC-27: the owner's own or CC0 photos, with their source recorded |
| 2.3.10 Other platforms | No names or imagery of "other mobile platforms or alternative app marketplaces"; no irrelevant information (2.3.10) | Partly | Decision | The README describes Homebrew, GitHub releases and Sparkle | DEC-98; ARC-27 leaves Homebrew, GitHub releases and other stores out of the listing |
| 2.3.11 Pre-orders | Pre-order apps "must be complete and deliverable as submitted" (2.3.11) | No | Not applicable | No pre-order is planned; DEC-88's timing would reopen this row | — |
| 2.3.12 What's New | "Apps must clearly describe new features and product changes in their 'What's New' text" (2.3.12) | From the second version | Not applicable | App Store Connect offers no What's New for a first version | From the second release, written from `docs/releases/` |
| 2.3.13 In-app events | Featured events must fit App Store Connect's event types (2.3.13) | No | Not applicable | No in-app events | — |
| 2.4.1 iPhone apps on iPad | "iPhone apps should run on iPad whenever possible." (2.4.1) | No | Not applicable | A Mac app | — |
| 2.4.2 Power and resources | Apps "should not rapidly drain battery, generate excessive heat, or put unnecessary strain on device resources" (2.4.2) | Partly: masks and Generative Remove are heavy | Compliant | Models run only when the photographer uses them, and quitting stops them (`RedlampApp.swift:355-362`) | — |
| 2.4.3 Apple TV inputs | Apple TV apps work with the Siri remote (2.4.3) | No | Not applicable | Not an Apple TV app | — |
| 2.4.4 Restarts and settings | Never "suggest or require a restart of the device or modifications to system settings" unrelated to the app (2.4.4) | Yes | Compliant | No Full Disk Access or security prompts in the app's strings (guidelines audit) | — |
| 2.4.5(i) Sandbox | "They must be appropriately sandboxed, and follow macOS File System Documentation." (2.4.5(i)) | Yes | Fix | The app carries no entitlements (`codesign`, build audit §1.2); the README's Known limitations say it isn't sandboxed (`README.md:257`); the decode service is (`RedlampDecoder.entitlements`) | ARC-17, with DEC-90 and DEC-96 shaping it |
| 2.4.5(ii) Packaging | Packaged "using technologies provided in Xcode; no third-party installers"; "self-contained … and cannot install code or resources in shared locations" (2.4.5(ii)) | Yes | Fix | The App Store build has no CLI, and the Redlamp App Store scheme archives it with Xcode (ARC-22, 5ab089dea); the direct download's release assembles its bundle with `ditto` (`mise/tasks/release`); writes go to Application Support, Caches and the photo folders (build audit §2.7) | ARC-23 archives and exports through Xcode |
| 2.4.5(iii) Auto-launch | No code run "automatically at startup or login without consent", nor processes that "continue to run … after a user has quit" (2.4.5(iii)) | Yes | Compliant | No `SMAppService`, login item, launch agent or `NSStatusItem` in the sources; the decode service ends with the app; quitting stops models and closes the library (`RedlampApp.swift:355-362`) | — |
| 2.4.5(iv) Downloads | No downloads of "additional code, or resources to add functionality or significantly change the app from what we see during the review process" (2.4.5(iv)) | Yes | Decision | Models come from GitHub releases and Hugging Face unless asset packs are declared (`ModelStore.swift:102-108`); the firmware model from redlamp.app on `main` (TON-50) | DEC-89 and DEC-97; INF-07 builds the Apple-hosted packs; ARC-27 lists the downloads in the notes |
| 2.4.5(v) Root privileges | No "escalation to root privileges or use setuid attributes" (2.4.5(v)) | Yes | Compliant | No `AuthorizationExecute` or setuid in the sources | — |
| 2.4.5(vi) Licence screens, copy protection | No licence screen at launch, licence keys, or "their own copy protection" (2.4.5(vi)) | Yes | Decision | The firmware model's key is derived from "the Team ID of the app's own valid signature, so a patched or re-signed copy can't open the file" (TON-50) | DEC-89 |
| 2.4.5(vii) Updates | "They must use the Mac App Store to distribute updates; other update mechanisms are not allowed." (2.4.5(vii)) | Yes | Compliant | The App Store build links no Sparkle and has no `SUFeedURL` or `SUPublicEDKey`; it compiles `AppStore/Updates.swift`, whose updater is never made, so Check for Updates… and the automatic-check toggle, shown only with one, aren't (ARC-22, 5ab089dea) | ARC-22; UX-50 takes the commands out of the App Store build's code |
| 2.4.5(viii) Current OS | Apps "should run on the currently shipping OS and may not use deprecated or optionally installed technologies" (2.4.5(viii)) | Yes: macOS 27 shipped in September 2026 | Fix | UX-44: Tab may not move through the Export dialog on macOS 27; ARC-19 (higher decode memory) and LIB-50 (late previews under load) are not faults; ARC-20 reaches only the validation layer; MSK-33's ViTMatte crash is fixed on `main` by version 2 | UX-44, checked in the app on macOS 27 before submission; ARC-23's pass on macOS 27 |
| 2.4.5(ix) Localisation | "Apps must contain all language and localization support in a single app bundle." (2.4.5(ix)) | Yes | Compliant | English only, with no `.lproj` folders in the sources | — |
| 2.5.1 Public APIs and current OS | "Apps may only use public APIs and must run on the currently shipping OS." (2.5.1) | Yes | Fix | `nm -u` on all 25 Mach-O files of 0.3.1 found no private symbols, `strings` no private frameworks; `NSSelectorFromString` only on SwiftUI's public `menuAction:` (`MenuBarKeys.swift:110`); the current OS as in 2.4.5(viii) | UX-44; the scan is repeated on each App Store build (ARC-23) |
| 2.5.2 Self-contained, no downloaded code | Apps may not "read or write data outside the designated container area", nor download code that "introduces or changes features" (2.5.2) | Yes | Fix | Reads `~/Library/Logs/DiagnosticReports` (`MacCrashReport.swift:9`); Adobe's profile folders are planned (DEC-85, LNS-16); models are data, compiled by Core ML on the Mac | ARC-17: crash reports from MetricKit only, Adobe's folders by a grant as DEC-96 decides |
| 2.5.3 Harmful code | No transmission of code that may "harm or disrupt the normal operation of the operating system" (2.5.3) | No | Not applicable | The app transmits no code | — |
| 2.5.4 Background services | Multitasking apps use background services only "for their intended purposes" (2.5.4) | No | Not applicable | These are iOS's background modes; the Mac app declares none, and its Background Assets extension is 2.5.16's | — |
| 2.5.5 IPv6 | "Apps must be fully functional on IPv6-only networks." (2.5.5) | Yes | Unverified | `URLSession` throughout; never tested on IPv6 only | Settled by using the relays, What's New and the model downloads on a NAT64 network during ARC-23 |
| 2.5.6 WebKit | Apps that browse the web must use WebKit (2.5.6) | No | Not applicable | No web views: nothing imports WebKit | — |
| 2.5.7 | "Intentionally omitted." (2.5.7) | — | Not applicable | Omitted by Apple | — |
| 2.5.8 Alternate desktops | Apps that create alternate desktop environments will be rejected (2.5.8) | No | Not applicable | Not a desktop environment | — |
| 2.5.9 Standard switches and UI | Apps that "alter or disable the functions of standard switches … or other native user interface elements or behaviors will be rejected" (2.5.9) | Partly | Decision | `FocusRings` removes every focus ring in every window (`.cursor/rules/focus-rings.mdc`). Assessment: low risk, but Full Keyboard Access users rely on it | DEC-102 |
| 2.5.10 | "Intentionally omitted." (2.5.10) | — | Not applicable | Omitted by Apple | — |
| 2.5.11(i) SiriKit intents | Sign up only "for intents they can handle" (2.5.11(i)) | No | Not applicable | Nothing imports App Intents or SiriKit | — |
| 2.5.11(ii) Siri vocabulary | Vocabulary must pertain to the app (2.5.11(ii)) | No | Not applicable | No Siri vocabulary | — |
| 2.5.11(iii) Siri resolution | Resolve requests directly, without ads (2.5.11(iii)) | No | Not applicable | No Siri requests | — |
| 2.5.12 CallKit and SMS filters | Block only confirmed spam numbers (2.5.12) | No | Not applicable | No CallKit or SMS extension | — |
| 2.5.13 Facial recognition sign-in | Use LocalAuthentication for face sign-in (2.5.13) | No | Not applicable | Vision finds faces for masks, not for sign-in | — |
| 2.5.14 Recording activity | "Apps must request explicit user consent and provide a clear visual and/or audible indication when recording, logging, or otherwise making a record of user activity." (2.5.14) | Yes | Compliant | Settings › Privacy › Keep an activity log, on by default, says what the log holds, that it stays on this Mac and is sent only in a report; turning it off deletes what was kept and stops recording, and the Report a Bug sheet says what the activity part holds (UX-52, b29fd225e) | UX-52, in the form DEC-101 chooses; ARC-24 mentions it in the privacy policy |
| 2.5.15 Files and iCloud | File pickers "should include items from the Files app and the user's iCloud documents" (2.5.15) | Yes | Compliant | System open panels, and sidecars written under file coordination for iCloud Drive (README) | — |
| 2.5.16 Widgets and extensions | Extensions "should be related to the content and functionality of your app" (2.5.16) | Yes, once built: the Background Assets extension | Fix | Not built yet | INF-07: the extension downloads only the app's own model packs |
| 2.5.16(a) App Clips | App Clip features must be in the main binary (2.5.16(a)) | No | Not applicable | No App Clip | — |
| 2.5.17 Matter | Use Apple's framework for Matter (2.5.17) | No | Not applicable | No Matter support | — |
| 2.5.18 Advertising | Display advertising only in the main binary (2.5.18) | No | Not applicable | No advertising | — |
| 3 Business (introduction) | "If your business model isn't obvious, make sure to explain in its metadata and App Review notes"; no review manipulation (3) | Yes | Fix | Paid, with the same features as the open-source build, and tips that unlock nothing | ARC-27 says so in the notes |
| 3.1.1 In-App Purchase | Features are unlocked through in-app purchase; "Apps may use in-app purchase currencies to enable customers to 'tip' the developer"; a restore mechanism "for any restorable in-app purchases" (3.1.1) | Yes | Fix | Ko-fi links in Help and Settings (`AppCommands.swift:382`, `SettingsView.swift:9, 216`); no StoreKit code | UX-51: consumable tips that unlock nothing, which aren't restorable; UX-50 removes the Ko-fi links |
| 3.1.1 (Mac plug-ins) | Mac App Store apps "may host plug-ins or extensions that are enabled with mechanisms other than the App Store" (3.1.1) | No | Not applicable | No plug-ins | — |
| 3.1.1 (gifting, loot boxes, gift cards, trials, NFTs) | The rest of 3.1.1's paragraphs (3.1.1) | No | Not applicable | None of these is offered; the app is paid up front, with no trial | — |
| 3.1.1(a) Links to other purchase methods | Outside the United States storefront, apps and metadata "may not include buttons, external links, or other calls to action that direct customers to purchasing mechanisms other than in-app purchase" (3.1.1(a)) | Yes | Decision | `AppCommands.swift:382`, `SettingsView.swift:9, 216`; whether the United States exception covers Mac apps is unverified | DEC-98 (recommended: no Ko-fi in any storefront); UX-50 |
| 3.1.2 Subscriptions | Auto-renewable subscriptions are allowed on their terms (3.1.2) | No | Not applicable | No subscriptions | — |
| 3.1.2(a) Permissible uses | Subscriptions must provide ongoing value (3.1.2(a)) | No | Not applicable | No subscriptions | — |
| 3.1.2(b) Upgrades and downgrades | Seamless upgrades and downgrades (3.1.2(b)) | No | Not applicable | No subscriptions | — |
| 3.1.2(c) Subscription information | Describe what a subscription gives before asking (3.1.2(c)) | No | Not applicable | No subscriptions | — |
| 3.1.3 Other purchase methods | Apps "cannot, within the app, encourage users to use a purchasing method other than in-app purchase", except on the United States storefront (3.1.3) | Partly | Decision | As 3.1.1(a) | DEC-98; UX-50 |
| 3.1.3(a) Reader apps | Access to previously purchased magazines, books, music or video (3.1.3(a)) | No | Not applicable | Not a reader app | — |
| 3.1.3(b) Multiplatform services | Content bought elsewhere, if also offered as in-app purchase (3.1.3(b)) | No | Not applicable | Nothing bought elsewhere unlocks anything | — |
| 3.1.3(c) Enterprise services | Apps sold directly to organisations (3.1.3(c)) | No | Not applicable | Sold to individuals on the App Store | — |
| 3.1.3(d) Person-to-person services | Real-time services between two individuals (3.1.3(d)) | No | Not applicable | None offered | — |
| 3.1.3(e) Goods outside the app | Physical goods or services consumed outside the app (3.1.3(e)) | No | Not applicable | None offered | — |
| 3.1.3(f) Free stand-alone apps | Free companions to paid web tools (3.1.3(f)) | No | Not applicable | A paid app with no web tool | — |
| 3.1.3(g) Advertising management | Apps for managing advertising campaigns (3.1.3(g)) | No | Not applicable | Not an advertising app | — |
| 3.1.4 Hardware-specific content | Features tied to hardware may unlock without in-app purchase (3.1.4) | No | Not applicable | Tethering unlocks nothing | — |
| 3.1.5(i) Crypto wallets | Wallets only from organisations (3.1.5(i)) | No | Not applicable | No cryptocurrency | — |
| 3.1.5(ii) Crypto mining | No on-device mining (3.1.5(ii)) | No | Not applicable | No cryptocurrency | — |
| 3.1.5(iii) Crypto exchanges | Exchanges on approved services only (3.1.5(iii)) | No | Not applicable | No cryptocurrency | — |
| 3.1.5(iv) Initial coin offerings | ICOs from approved institutions only (3.1.5(iv)) | No | Not applicable | No cryptocurrency | — |
| 3.1.5(v) Crypto rewards | No currency for completing tasks (3.1.5(v)) | No | Not applicable | No cryptocurrency | — |
| 3.2.1(i) Own apps | Promoting your own apps is acceptable within limits (3.2.1(i)) | No | Not applicable | The app promotes no other apps | — |
| 3.2.1(ii) Third-party collections | Collections of third-party apps for a need (3.2.1(ii)) | No | Not applicable | No app collections | — |
| 3.2.1(iii) Rentals | Rental content may expire; nothing else may (3.2.1(iii)) | No | Not applicable | No rentals | — |
| 3.2.1(iv) Wallet passes | Wallet passes for payments and offers (3.2.1(iv)) | No | Not applicable | No Wallet passes | — |
| 3.2.1(v) Insurance | Insurance apps must be free (3.2.1(v)) | No | Not applicable | Not an insurance app | — |
| 3.2.1(vi) Nonprofits | Approved nonprofits may fundraise (3.2.1(vi)) | No | Not applicable | Not a nonprofit | — |
| 3.2.1(vii) Monetary gifts | A gift "connected to or associated at any point in time with receiving digital content or services must use in-app purchase" (3.2.1(vii)) | Partly: tips to the developer of the app in use | Fix | Assessment: tips go through in-app purchase, as 3.1.1 allows | UX-51: tips through StoreKit only |
| 3.2.1(viii) Financial apps | Trading apps from the financial institution (3.2.1(viii)) | No | Not applicable | Not a financial app | — |
| 3.2.2(i) Store-like interfaces | No interface "for displaying third-party apps, extensions, or plug-ins similar to the App Store" (3.2.2(i)) | No | Not applicable | None in the app | — |
| 3.2.2(ii) | "Intentionally omitted." (3.2.2(ii)) | — | Not applicable | Omitted by Apple | — |
| 3.2.2(iii) Ad fraud | No inflating of ad impressions (3.2.2(iii)) | No | Not applicable | No advertising | — |
| 3.2.2(iv) Charities | No collecting for charities without approval (3.2.2(iv)) | No | Not applicable | Tips aren't charity | ARC-27 doesn't describe tips as donations to a cause |
| 3.2.2(v) Arbitrary restriction | No "arbitrarily restricting who may use the app, such as by location or carrier" (3.2.2(v)) | Partly: Generative Remove on smaller Macs | Compliant | Macs under 16 GB are offered it with a note (README) | — |
| 3.2.2(vi) | "Intentionally omitted." (3.2.2(vi)) | — | Not applicable | Omitted by Apple | — |
| 3.2.2(vii) Rank manipulation | No manipulating rank on other services (3.2.2(vii)) | No | Not applicable | The app touches no other service's rankings | — |
| 3.2.2(viii) Binary options | Binary options trading is not permitted (3.2.2(viii)) | No | Not applicable | Not a trading app | — |
| 3.2.2(ix) Personal loans | Loan apps disclose all terms (3.2.2(ix)) | No | Not applicable | Not a loan app | — |
| 3.2.2(x) Forced store actions | Apps "must not force users to rate the app, review the app, download other apps" to access functionality (3.2.2(x)) | Yes | Compliant | No review or rating prompt in the sources; the GitHub star nudge is on the website (`web/components/site/StarNudge.tsx`) | — |
| 4 Design (introduction) | "Apps that stop working or offer a degraded experience may be removed" (4) | No | Not applicable | Describes removal; met through the other rows at each release | — |
| 4.1(a) Copycats | Don't "make some minor changes to another app's name or UI and pass it off as your own" (4.1(a)) | Partly: Lightroom's panel order and shortcuts | Decision | Lightroom Classic is the default keymap (`Keymap.swift:18`, `KeymapPreset.swift:15`). Assessment: moderate risk, mainly from presentation | DEC-94; ARC-27 leads with Redlamp's own design and never says "like Lightroom" |
| 4.1(b) Impersonation | Impersonating other apps violates the Code of Conduct (4.1(b)) | Yes | Compliant | Its own name, icon and brand (`docs/brand/README.md`) | — |
| 4.1(c) Others' icons and names | No other developer's "icon, brand, or product name in your app's icon or name" (4.1(c)) | Yes | Compliant | The icon is a safelight; the name is Redlamp | ARC-27 keeps third-party names out of the app's name in every language |
| 4.2 Minimum Functionality | Apps should "elevate it beyond a repackaged website" (4.2) | Yes | Compliant | A native raw editor in Swift and Metal | — |
| 4.2.1 ARKit | ARKit apps need rich AR experiences (4.2.1) | No | Not applicable | No ARKit | — |
| 4.2.2 Marketing materials | Apps shouldn't be "primarily … marketing materials, advertisements, web clippings, content aggregators, or a collection of links" (4.2.2) | Yes | Compliant | A raw editor | — |
| 4.2.3(i) Works on its own | "Your app should work on its own without requiring installation of another app to function." (4.2.3(i)) | Yes | Compliant | Lightroom Classic import is optional | — |
| 4.2.3(ii) Downloads at first launch | "Disclose the size of the download and prompt users before doing so." (4.2.3(ii)) | Partly: models download on first use, not at launch | Compliant | Prompts give the size and ask (`MaskingPanel.swift:272`, `HealToolPanel.swift:156`, `ModelsSettings.swift:94`); nothing downloads at launch | INF-07 keeps the prompts with Apple-hosted packs |
| 4.2.4 | "Intentionally omitted." (4.2.4) | — | Not applicable | Omitted by Apple | — |
| 4.2.5 | "Intentionally omitted." (4.2.5) | — | Not applicable | Omitted by Apple | — |
| 4.2.6 Template apps | Apps from commercial templates are rejected (4.2.6) | No | Not applicable | Not built from a template | — |
| 4.2.7 Remote desktop clients | Rules for remote desktop clients (4.2.7) | No | Not applicable | Not a remote desktop client | — |
| 4.2.7(a) User-owned host | Connect only to a user-owned host (4.2.7(a)) | No | Not applicable | Not a remote desktop client | — |
| 4.2.7(b) Execution on the host | Software runs on the host (4.2.7(b)) | No | Not applicable | Not a remote desktop client | — |
| 4.2.7(c) Accounts on the host | Accounts managed from the host (4.2.7(c)) | No | Not applicable | Not a remote desktop client | — |
| 4.2.7(d) Client interface | The client doesn't resemble an App Store view (4.2.7(d)) | No | Not applicable | Not a remote desktop client | — |
| 4.2.7(e) Thin clients | Thin clients for cloud apps aren't appropriate (4.2.7(e)) | No | Not applicable | Not a remote desktop client | — |
| 4.3(a) Multiple bundle IDs | "Don't create multiple Bundle IDs of the same app" (4.3(a)) | Partly | Compliant | One App Store record whichever bundle ID DEC-91 chooses; the Developer ID build isn't submitted | — |
| 4.3(b) Saturated categories | Don't submit apps "indistinguishable from what's already widely available" (4.3(b)) | No | Not applicable | Aimed at saturated categories of near-identical apps, which a raw editor with its own engine isn't | — |
| 4.4 Extensions | Extensions comply with the App Extension Programming Guide and include some functionality (4.4) | Yes, once built | Fix | The Background Assets extension isn't built | INF-07 |
| 4.4.1 Keyboard extensions | Keyboard extensions' rules (4.4.1) | No | Not applicable | No keyboard extension | — |
| 4.4.2 Safari extensions | Safari extensions run on current Safari (4.4.2) | No | Not applicable | No Safari extension | — |
| 4.4.3 | "Intentionally omitted." (4.4.3) | — | Not applicable | Omitted by Apple | — |
| 4.5.1 Apple sites and RSS | Approved Apple feeds only; no scraping of Apple sites (4.5.1) | No | Not applicable | The app reads no Apple site | — |
| 4.5.2(i) MusicKit playback | MusicKit's rules for playing Apple Music (4.5.2(i)) | No | Not applicable | No MusicKit | — |
| 4.5.2(ii) MusicKit licences | MusicKit doesn't replace music licences (4.5.2(ii)) | No | Not applicable | No MusicKit | — |
| 4.5.2(iii) Apple Music data | Disclose access to Apple Music data (4.5.2(iii)) | No | Not applicable | No MusicKit | — |
| 4.5.3 Spam through Apple services | "Do not use Apple Services to spam, phish, or send unsolicited messages" (4.5.3) | No | Not applicable | The app sends no messages through Apple's services | — |
| 4.5.4 Push notifications | Push notifications must not be required (4.5.4) | No | Not applicable | No push notifications | — |
| 4.5.5 Game Center | Game Center Player IDs per its terms (4.5.5) | No | Not applicable | No Game Center | — |
| 4.5.6 Apple emoji | Unicode emoji are allowed; "Apple emoji may not be used on other platforms or embedded directly in your app binary" (4.5.6) | Yes | Compliant | The sources use emoji only as Unicode text (★ in ratings, `PhotoPanelView.swift`); the app bundles no images but its icon and `Welcome.mp4` (build audit §1.1) | — |
| 4.6 | "Intentionally omitted." (4.6) | — | Not applicable | Omitted by Apple | — |
| 4.7 Mini apps, plug-ins, emulators | Rules for software offered outside the binary (4.7) | No | Not applicable | Looks, LUTs and presets are data, not software | — |
| 4.7.1 Their privacy and content rules | Such software follows 5.1, filtering and 3.1 (4.7.1) | No | Not applicable | No such software | — |
| 4.7.2 Native APIs | Such software may not be exposed to native APIs (4.7.2) | No | Not applicable | No such software | — |
| 4.7.3 Shared data | No sharing of data or permissions with such software (4.7.3) | No | Not applicable | No such software | — |
| 4.7.4 Index of software | An index of such software (4.7.4) | No | Not applicable | No such software | — |
| 4.7.5 Age restriction | Age restriction for such software (4.7.5) | No | Not applicable | No such software | — |
| 4.8 Login Services | Third-party sign-in requires an equivalent option (4.8) | No | Not applicable | No sign-in | — |
| 4.9 Apple Pay | Apple Pay apps disclose purchase information (4.9) | No | Not applicable | No Apple Pay | — |
| 4.10 Built-in capabilities | "You may not monetize built-in capabilities provided by the hardware or operating system" (4.10) | No | Not applicable | Nothing in the app charges for a hardware or system capability | — |
| 5 Legal (introduction) | "Apps must comply with all legal requirements in any location where you make them available" (5) | Yes | Decision | Section 5 of this file: GDPR, the AI Act, the Digital Services Act | DEC-99 and DEC-100 |
| 5.1 Privacy | Comply with "privacy best practices, applicable laws, and the terms of the Apple Developer Program License Agreement" (5.1) | Yes | Fix | No privacy policy or manifest | ARC-24 |
| 5.1.1(i) Privacy policies | "All apps must include a link to their privacy policy in the App Store Connect metadata field and within the app"; it identifies the data, third parties, retention and deletion (5.1.1(i)) | Yes | Fix | No policy: `redlamp.app/privacy` returned 404 on 15 October 2026, and no source mentions a privacy policy | ARC-24: a policy covering reports, crash and hang reports, the Camera Bench, model downloads, What's New, tips and the website, linked from Help, Settings › About, Report a Bug and the Camera Bench; DEC-95 shapes its deletion section |
| 5.1.1(ii) Permission | Collection needs consent, and "an easily accessible and understandable way to withdraw consent" (5.1.1(ii)) | Yes | Fix | Reports and bench results are previewed and sent by the person; nothing is sent automatically; the bench's contributor ID can be reset | ARC-24 says how to withdraw; DEC-95 how a sent report is deleted |
| 5.1.1(iii) Data minimisation | "Apps should only request access to data relevant to the core functionality of the app" (5.1.1(iii)) | Yes | Compliant | Location and serial numbers are never read into reports (`FeedbackContext.swift:8-9`); screenshots carry no metadata (`Screenshots.swift:6-7`); file names are redacted by default | — |
| 5.1.1(iv) Access | "Apps must respect the user's permission settings and not attempt to manipulate, trick, or force people to consent" (5.1.1(iv)) | Yes | Compliant | The app asks for no system permissions, and reports send only from their preview | — |
| 5.1.1(v) Account sign-in | "If your app doesn't include significant account-based features, let people use it without a login." (5.1.1(v)) | Yes | Compliant | No accounts | — |
| 5.1.1(vi) Surreptitious discovery | No surreptitious discovery of passwords (5.1.1(vi)) | No | Not applicable | The app asks for no passwords | — |
| 5.1.1(vii) SafariViewController | SafariViewController must be visible (5.1.1(vii)) | No | Not applicable | SafariViewController is iOS's, and the app has none | — |
| 5.1.1(viii) Compiling personal information | No compiling personal information without consent (5.1.1(viii)) | No | Not applicable | The app compiles no personal information | — |
| 5.1.1(ix) Regulated fields | Regulated services submitted by a legal entity (5.1.1(ix)) | No | Not applicable | Not a regulated service | — |
| 5.1.1(x) Basic contact information | Contact information "so long as the request is optional" (5.1.1(x)) | Partly | Compliant | "Name to credit (optional)" (`CameraBenchView.swift:212`); the GitHub username is optional (`FeedbackReport.swift:164`) | — |
| 5.1.2(i) Data use and sharing | "You must clearly disclose where personal data will be shared with third parties … and obtain explicit permission" (5.1.2(i)) | Yes: reports go to GitHub, publicly | Fix | The sheet says reports are public on GitHub (`FeedbackSheet.swift:55`) and shows them before sending; generative fill runs on the Mac | ARC-24 names GitHub, the website's host (Vercel) and Apple in the policy |
| 5.1.2(ii) Repurposing | "Data collected for one purpose may not be repurposed without further consent" (5.1.2(ii)) | Yes | Compliant | Reports serve support, bench results camera support | — |
| 5.1.2(iii) Profiles | No surreptitious user profiles (5.1.2(iii)) | Yes | Compliant | No analytics, advertising or tracking SDKs (build audit §9) | — |
| 5.1.2(iv) Contacts and Photos databases | No contact databases from Contacts or Photos (5.1.2(iv)) | No | Not applicable | The Mac app imports neither Contacts nor Photos (only the separate iPhone bench app imports Photos) | — |
| 5.1.2(v) Contacting people | No contacting people from Contacts or Photos (5.1.2(v)) | No | Not applicable | As 5.1.2(iv) | — |
| 5.1.2(vi) Depth and face data | Depth and face data not for marketing or data mining (5.1.2(vi)) | Partly: Vision faces, Portrait mattes and depth for masks | Compliant | Used on the Mac only, for masks | — |
| 5.1.2(vii) Apple Pay data | Apple Pay data shared only to process payments (5.1.2(vii)) | No | Not applicable | No Apple Pay | — |
| 5.1.3(i) Health data use | No disclosure of health research data (5.1.3(i)) | No | Not applicable | No health data | — |
| 5.1.3(ii) False health data | No false data into HealthKit (5.1.3(ii)) | No | Not applicable | No health data | — |
| 5.1.3(iii) Research consent | Consent for health research (5.1.3(iii)) | No | Not applicable | No health research | — |
| 5.1.3(iv) Ethics approval | Approval for health research (5.1.3(iv)) | No | Not applicable | No health research | — |
| 5.1.4(a) Kids' data | "Use care when dealing with personal data from kids", and comply with laws such as COPPA and GDPR (5.1.4(a)) | Partly: anyone may send a report | Fix | The app isn't directed at children, but reports may come from minors | ARC-24: the policy says reports from those under 16 need a parent's consent where local law requires |
| 5.1.4(b) Kids' data and a privacy policy | Apps that "have the capability to share personal information (e.g. … photos …) from a minor must include a privacy policy" (5.1.4(b)) | Partly | Fix | Covered by 5.1.1(i) | ARC-24 |
| 5.1.5 Location Services | Location Services only when directly relevant (5.1.5) | No | Not applicable | Nothing imports Core Location | — |
| 5.2 Intellectual Property | "Make sure your app only includes content that you created or that you have a license to use." (5.2) | Yes | Decision | Section 5 of this file | DEC-93 and DEC-94; ARC-25 |
| 5.2.1 Generally | "Don't use protected third-party material such as trademarks, copyrighted works, or patented ideas in your app without permission" (5.2.1) | Yes | Decision | Lightroom names (`ShortcutAction.swift:428`, `LibrarySettings.swift:40-42`); film stock names (`BaseLooks.json`, `FilmLookCatalog.swift`); the firmware model's data (DEC-84); Adobe's profiles (DEC-85); third-party licence notices absent from the app | DEC-89, DEC-93, DEC-94 and DEC-85; ARC-25 the notices |
| 5.2.2 Third-party services | Be "specifically permitted to do so under the service's terms of use" (5.2.2) | Partly: GitHub issues and release hosting, raw.pixls.us, Fujifilm's LUTs the photographer downloads | Unverified | `CameraBenchView.swift:200-205` links raw.pixls.us; LUT import reads the person's own files | Settled by reading GitHub's terms on issues filed by a GitHub App and on release hosting at App Store scale |
| 5.2.3 Audio and video downloading | No downloading of media from third-party sources (5.2.3) | No | Not applicable | The app downloads no media | — |
| 5.2.4(a) Apple endorsements | "Don't suggest or imply that Apple is a source or supplier of the App" (5.2.4(a)) | Yes | Fix | Nothing in the app implies it; the listing isn't written | ARC-27 follows section 4 |
| 5.2.4(b) Editor's Choice | Apple applies the badge itself (5.2.4(b)) | No | Not applicable | Nothing for the developer to do | — |
| 5.2.5 Apple products | Don't appear "confusingly similar to an existing Apple product" (5.2.5) | Partly | Compliant | Its own design (`docs/brand/README.md`) | — |
| 5.3 Gaming, gambling, lotteries | Rules for real-money gaming, contests and lotteries (5.3) | No | Not applicable | No games or contests in the app | — |
| 5.3.1 Sponsorship | Contests sponsored by the developer (5.3.1) | No | Not applicable | The ambassadors' picks happen outside the app | — |
| 5.3.2 Official rules | Official rules presented in the app (5.3.2) | No | Not applicable | No contests in the app | — |
| 5.3.3 In-app purchase for gambling | No in-app purchase for real-money gaming credit (5.3.3) | No | Not applicable | No gambling | — |
| 5.3.4 Real-money gaming | Licensing and free distribution for real-money gaming (5.3.4) | No | Not applicable | No gambling | — |
| 5.4 VPN apps | Use `NEVPNManager` (5.4) | No | Not applicable | Not a VPN | — |
| 5.5 Mobile Device Management | MDM capability from Apple (5.5) | No | Not applicable | Not an MDM app | — |
| 5.6 Developer Code of Conduct | Apps "should never prey on users or attempt to rip off customers, trick them into making unwanted purchases" (5.6) | Yes | Fix | The tip jar isn't built | UX-51: tips plainly optional |
| 5.6.1 App Store reviews | "Use the provided API to prompt users to review your app … we will disallow custom review prompts." (5.6.1) | Partly | Compliant | No review prompt: no `requestReview` or `SKStoreReviewController` in the sources | Any future prompt uses `requestReview`, and never one tied to a tip |
| 5.6.2 Developer Identity | "Your representation of yourself, your business, and your offerings on the App Store … must be accurate." (5.6.2) | Yes | Decision | The seller is Pedro Gomes, an individual account (team 3JP75Z3F98, DEC-99); the trader details and the support page are not yet set in App Store Connect | DEC-99 |
| 5.6.3 Discovery Fraud | No manipulating "charts, search, reviews, or referrals" (5.6.3) | Yes | Fix | The ambassador programme (DEC-86) asks for edits and feedback | ARC-27: the ambassadors' and supporters' terms say they're never asked for App Store ratings or reviews in return for anything |
| 5.6.4 App Quality | Excessive customer reports, negative reviews and refund requests indicate low quality (5.6.4) | Yes | Decision | The app is described as an alpha | DEC-92 |

## 2. App Store Connect requirements

Read on 15 October 2026 from App Store Connect Help and Apple's developer pages, as the guidelines audit cites them.

| Item | Requirement | Applies | Status | Evidence | Fix or decision |
| --- | --- | --- | --- | --- | --- |
| Program licence agreement | The Account Holder accepts the agreement revised on 13 October 2026 before creating apps or in-app purchases (Apple developer news, 13 October 2026) | Yes | Fix | Not confirmed: the Account Holder of team 3JP75Z3F98, the seller (DEC-99), accepts it at developer.apple.com/account; the team's App Store Connect API answered on 15 October 2026 without asking for an agreement | ARC-27 |
| Paid Apps Agreement | "To sell your apps on the App Store or offer In-App Purchases, the Account Holder must sign the Paid Apps Agreement." (Sign and update agreements) | Yes | Compliant | In effect for team 3JP75Z3F98, the seller (DEC-99): Lookout Station's in-app purchases were on sale under it on 15 October 2026 (App Store `id6761258688`), which needs this agreement, the tax form and banking | — |
| Tax forms | "All developers must complete a US tax form"; W-8BEN or similar outside the United States; it can't be changed once submitted (Provide tax information) | Yes | Compliant | Submitted for team 3JP75Z3F98, as the Paid Apps Agreement row shows | — |
| Banking | Banking follows the Paid Apps Agreement and the tax forms (Enter banking information) | Yes | Compliant | Entered for team 3JP75Z3F98, as the Paid Apps Agreement row shows | — |
| Small Business Program | 15% commission for developers new to the App Store or under 1 million USD; proceeds adjust from the month after approval (Small Business Program) | Yes | Fix | Not confirmed: enrolment is the account's, so it would cover Lookout Station's sales too; the Account Holder checks it or enrols | ARC-27 enrols before launch |
| App record and bundle ID | The record is created for one bundle ID, which can't be changed afterwards (build audit §3.13) | Yes | Decision | `app.redlamp.mac` today | DEC-91 |
| Name | "At least two characters and no more than 30 characters" (App information) | Yes | Unverified | "Redlamp" has 7 characters; App Store search finds no app of that name | Settled by reserving it when ARC-27 creates the record |
| Subtitle | "This can't be longer than 30 characters." (App information) | Yes | Fix | Not written | ARC-27, with no third-party names (DEC-94) |
| Category | The primary category "should match the category you set in Xcode" (App information) | Yes | Fix | `public.app-category.photography` (`apps/RedlampMac/Project.swift:25`) | ARC-27 sets Photography; DEC-103 the secondary |
| Privacy Policy URL | "Required for iOS and macOS apps." (App information) | Yes | Fix | `redlamp.app/privacy` returned 404 on 15 October 2026 | ARC-24 |
| Support URL | It "must lead to actual contact information (legal address, email address, telephone number), as may be required by local law" (Platform version information) | Yes | Fix | `redlamp.app/support` and `/contact` returned 404 on 15 October 2026 | ARC-24, with the contact details DEC-99 settles |
| Marketing URL | Optional (Platform version information) | Optional | Decision | The site offers the free download and Ko-fi | DEC-98 |
| Copyright | "The name of the person or entity that owns the exclusive rights to the app, preceded by the year" (Platform version information) | Yes | Decision | Today's string is "Redlamp contributors. MPL-2.0." (`apps/RedlampMac/Project.swift:26`) | DEC-99 |
| Content rights | Apps with third-party content "must have all the necessary rights to that content" (App information) | Yes: LibRaw, the downloadable models, film datasheet data | Decision | Section 5 of this file | DEC-93; ARC-25 |
| Licence agreement | Apple's standard EULA, or a custom one that supersedes it (App information) | Yes | Decision | Not chosen; how either sits with MPL-2.0 is for counsel | DEC-99 |
| Digital Services Act trader status | Traders' address, phone number and email address are verified and shown in the EU; a paid app or in-app purchases count towards trader status (DSA trader requirements) | Yes: a paid app with tips | Decision | The account declares no trader status: Lookout Station's EU product page says Pedro Gomes "has not identified itself as a trader for this app"; the status can be set for each app (DSA trader requirements) | DEC-99; ARC-27 enters it |
| Age rating | Answer the questionnaire; "An Unrated app can't be published"; its social media questions are required since September 2026 (Set an app age rating; news of 9 July 2026) | Yes | Decision | Draft answers: no to every capability and content descriptor, giving 4+ (guidelines audit §2.2) | DEC-103 |
| Price and availability | Up to 800 price points; equalised prices across 175 storefronts; a paid price needs the Paid Apps Agreement (Set a price) | Yes | Decision | Not set; the EU storefronts depend on the AI Act's marking | DEC-88 and DEC-100 |
| Apple silicon only | "To limit your app to Macs with Apple silicon, set your Xcode build architecture to arm64 only" (Apple developer news, 9 September 2026) | Yes | Compliant | `ARCHS = arm64` (`Tuist/ProjectDescriptionHelpers/Module.swift:112`) | — |
| App Privacy details | Disclose each data type collected, its purpose, whether it is linked to the user and whether it tracks; optional disclosure needs the user's name shown in the form (App privacy details) | Yes | Decision | Reports carry words, screenshots, the edit, activity, diagnostics and an optional GitHub username; the bench a per-Mac ID and an optional name; no tracking (guidelines audit §2.4, build audit §9) | DEC-95 (linked or not); ARC-24 drafts the answers, ARC-27 enters them |
| Accessibility Nutrition Labels | Voluntary to start; published only for devices with a live version (Overview of Accessibility Nutrition Labels) | Not yet | Not applicable | Voluntary today, and publishable only once the app is live | DEC-103 chooses which to publish then |
| Screenshots | At least one and up to 10, 16:10 at 1280 × 800 to 2880 × 1800, no alpha channel; more than half showing the app in use (Screenshot specifications; 2.3.3 reference) | Yes | Fix | Not made | ARC-27 |
| App previews | Optional; 1920 × 1080, 15 to 30 seconds, screen captures of the app (App preview specifications) | Optional | Not applicable | Optional; when made, 2.3.4's row applies | — |
| Product page and search assets | Optional headers and search result assets (Creative assets specifications) | Optional | Not applicable | Optional | — |
| Promotional text | Optional, up to 170 characters, changeable without a submission (Platform version information) | Optional | Not applicable | Optional; when written, the description's rules apply | — |
| Description | Up to 4,000 characters of plain text (Platform version information) | Yes | Fix | Not written | ARC-27: what the app does, open source under MPL-2.0, photos never uploaded, tips optional, the trademark notices; no prices, "alpha", Homebrew or GitHub release links |
| Keywords | Up to 100 bytes; "Names of other apps or companies aren't allowed" (Platform version information) | Yes | Fix | Not written | ARC-27 |
| What's New | Up to 4,000 characters; not available for the first version (Platform version information) | From the second version | Not applicable | Not available for a first version | — |
| In-app purchase products | Product IDs up to 100 characters, not editable once saved, separate for macOS; display names of 2 to 30 characters; descriptions of 45 or fewer (In-App Purchase information) | Yes | Fix | Not created | UX-51 defines them (for example `app.redlamp.mac.tip.small`); ARC-27 creates them |
| First in-app purchases with a version | "The first consumable … In-App Purchase of each type must be submitted with a new app version." (Submit an In-App Purchase) | Yes | Fix | Not submitted | ARC-27 submits the tips with the first version |
| In-app purchase review screenshot | A screenshot of each in-app purchase, for review only (In-App Purchase information) | Yes | Unverified | Apple describes it but doesn't say it is required | Settled by App Store Connect's state when ARC-27 creates the products; ARC-27 attaches one for each tip either way |
| In-app purchases working in review | "Paid In-App Purchases won't function in review until this agreement is active"; fetch products with StoreKit before showing them (Configure In-App Purchases for review) | Yes | Fix | Not built | UX-51 loads prices from StoreKit; ARC-27 has the agreement active |
| App Review contact | Name, email and phone number in international format (Platform version information) | Yes | Fix | Not entered | ARC-27 |
| Review notes | Up to 4,000 bytes (Platform version information) | Yes | Fix | Not written | ARC-27 |
| Review attachments | "Attach everything App Review will need", including the external services the app uses (Provide information for a complete review) | Yes | Fix | Not attached | ARC-27: sample raws, a small Lightroom Classic catalog, the list of services (GitHub, redlamp.app, Apple's asset packs) |
| Sign-in information | Required "if your app requires a login" (Platform version information) | No | Not applicable | No login | — |
| TestFlight | Mac builds from Xcode 13 or later; the first build added to a group goes to App Review; builds last 90 days (TestFlight overview) | Yes | Fix | No App Store build exists | ARC-23 |
| Apple-hosted asset packs | Packs are uploaded separately and submitted for review with the build (Creating managed asset packs) | Yes | Fix | `ModelStore` reads packs when `BAHasManagedAssetPacks` is set (`ModelStore.swift:45-46`); no packs exist in App Store Connect | INF-07 |
| Export compliance answer | Set `ITSAppUsesNonExemptEncryption` or answer the questionnaire for each build (Overview of export compliance) | Yes | Compliant | Set to NO in the App Store build, as section 3's row on the key says (ARC-22, 5ab089dea) | ARC-22 |
| Asset pack limits | 200 GB and 200 packs per app (Apple-hosted asset pack size limits) | Yes | Fix | Seven packs, about 4.3 GB in all (build audit §5.1) | INF-07 |

## 3. Technical checks at upload and review

| Item | Requirement | Applies | Status | Evidence | Fix or decision |
| --- | --- | --- | --- | --- | --- |
| Distribution certificate | The app is signed with an Apple Distribution certificate (build audit §3.13) | Yes | Fix | The release signs with Developer ID (`mise/tasks/release:198-205`) | ARC-23 |
| Installer certificate | The `.pkg` is signed with a Mac Installer Distribution certificate (build audit §3.13) | Yes | Fix | None | ARC-23 |
| App IDs and profiles | Explicit App IDs with In-App Purchase and App Groups, and Mac App Store Connect profiles for the app and the extension (build audit §3.13) | Yes | Fix | None | ARC-23 |
| Archive and export | Archived and exported through Xcode with the `app-store-connect` method (2.4.5(ii); build audit §3.13) | Yes | Fix | `mise run release` builds and assembles with `xcodebuild build` and `ditto` (`mise/tasks/release:211-214`) | ARC-23 (`mise run appstore`) |
| Validation | `xcrun altool --validate-app` passes before upload (build audit §3.13) | Yes | Fix | Never run | ARC-23 |
| Sandbox entitlement on the app | "To distribute a macOS app through the Mac App Store, you must enable the App Sandbox capability." (App Sandbox) | Yes | Fix | The app is signed with `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` (`mise/tasks/release:200`) and carries no entitlements | ARC-17, in the App Store build's entitlements file from ARC-22 |
| Every executable sandboxed | Validation refuses an upload with any executable lacking `com.apple.security.app-sandbox` (build audit §4.2; the exact error text is unverified) | Yes | Fix | The App Store build has no CLI (ARC-22, 5ab089dea), and its decoder service is sandboxed; `check-release-bundle.sh --app-store` finds only the app's own executable without the entitlement | ARC-17 |
| Decode service | An XPC service has its own sandbox and must not carry `com.apple.security.inherit` (build audit §4.2) | Yes | Compliant | `RedlampDecoder.entitlements` holds `com.apple.security.app-sandbox` alone; the service receives bytes, not paths | ARC-23 re-signs it with Apple Distribution |
| No temporary exceptions | Temporary exceptions need a justification App Review may question (App Sandbox Temporary Exception Entitlements) | Yes | Fix | None today; Adobe's profile folders would need one without a grant | ARC-17, with Adobe's folders by a grant (DEC-96) |
| No hardened-runtime exceptions | No `com.apple.security.cs.*` exceptions (build audit §4.1) | Yes | Compliant | The shipped app carries no entitlements at all; MLX compiles Metal kernels, not executable code | — |
| Network entitlement | `com.apple.security.network.client` for outgoing connections only, with no `network.server` (build audit §4.8) | Yes | Fix | Nothing in the app listens; only the CLI's bench server does (`BenchHTTPServer.swift`) | ARC-17 |
| User-selected files | `com.apple.security.files.user-selected.read-write`, with security-scoped bookmarks for every stored path (Accessing files from the macOS App Sandbox) | Yes | Fix | Paths are stored without bookmarks: the working set, the library's roots, export destinations, the Lightroom catalog's folders | ARC-17 |
| App-scope bookmarks entitlement | Whether `com.apple.security.files.bookmarks.app-scope` is still needed (build audit §4.1) | No | Not applicable | Not needed: Apple's DTS wrote in August 2025 that `files.user-selected.read-write` is accepted in its place, and ARC-17's spike made a security-scoped bookmark without it and resolved it in a later launch, on macOS 26.6.2 ([the study](../research/notes/ARC-17-app-sandbox.md#1-the-entitlements)) | — |
| App group ID format | The app and the Background Assets extension share an app group (Downloading Apple-hosted asset packs) | Yes | Unverified | The group ID format the extension needs on macOS is unverified | Settled when INF-07 adds the capability |
| Related items for sidecars | `NSIsRelatedItemType` for the sidecar types, so a photo opened on its own can write its sidecar (Accessing files from the macOS App Sandbox) | Yes | Fix | No `CFBundleDocumentTypes` (build audit §1.3) | ARC-17 |
| Full-name sidecar packages as related items | Whether related items cover `IMG_0001.ARW.redlamp`, the photo's full name plus an extension, and a package (build audit §4.4) | Yes | Fix | They don't: ARC-17's spike, on macOS 26.6.2, was refused `IMG_0001.ARW.redlamp` beside a photo opened on its own, for writing and for reading, and allowed a package named `IMG_0001.redlamp` and `IMG_0001.xmp` ([the study](../research/notes/ARC-17-app-sandbox.md#a-photo-on-its-own)) | ARC-17: a photo opened on its own keeps its edit beside it once its folder is granted, as the owner decides |
| Version string | "Three period-separated integers"; "only numeric characters (0-9) and periods" (`CFBundleShortVersionString`) | Yes | Compliant | In the AppStore configuration, the app's and the decoder service's `CFBundleShortVersionString` is `MARKETING_VERSION` without its stage, `0.3.2` for `0.3.2-alpha` (ARC-22, 5ab089dea); `check-release-bundle.sh --app-store` fails on any other | ARC-22, with the number DEC-92 chooses |
| Version below 1.0 | Whether App Store Connect accepts a version below 1.0 (build audit §3.3) | If DEC-92 keeps 0.x | Unverified | No Apple page found says either way | Settled by the first TestFlight upload (ARC-23) |
| Build number | "Increment the build version before you distribute a build" (`CFBundleVersion`) | Yes | Compliant | Release builds set it to the number of commits on `main` (`Version.xcconfig:3`) | — |
| Category key | `LSApplicationCategoryType` from Apple's list (LSApplicationCategoryType) | Yes | Compliant | `public.app-category.photography` (`apps/RedlampMac/Project.swift:25`) | — |
| Export compliance key | `ITSAppUsesNonExemptEncryption` = NO if the app uses only exempt encryption (ITSAppUsesNonExemptEncryption) | Yes | Compliant | NO in the App Store build's Info.plist (ARC-22, 5ab089dea). The firmware model's AES-GCM is compiled out of it (66b3e7761), and its binaries import only SHA-256 from CryptoKit and nothing from Security (`dyld_info -imports`), beside the system's HTTPS | ARC-22, as DEC-89 leaves the firmware model out |
| No update feed | No `SUFeedURL` or `SUPublicEDKey`, and no `Sparkle.framework` (2.4.5(vii)) | Yes | Compliant | The App Store build has no `Sparkle.framework`, `SUFeedURL` or `SUPublicEDKey` (ARC-22, 5ab089dea); `check-release-bundle.sh --app-store` fails on either | ARC-22 |
| The firmware model | No `RedlampFirmwareTablesURL`, `RedlampFirmwareKeyURL` or firmware model code (2.3.1(a), 2.4.5(iv), 2.4.5(vi)) | Yes | Compliant | The App Store build compiles out the firmware model, its host, keys, packing, signing check, looks, switch and controls, leaving an uninhabited `FirmwareFilmModel` so their call sites compile, and its Info.plist has no `RedlampFirmware…` key (ARC-22, 66b3e7761); `check-release-bundle.sh --app-store` fails on one | DEC-89; ARC-22 |
| Storyboard key | Info.plist names no storyboard the bundle lacks (build audit §3.11; no Apple rule is cited) | Yes | Compliant | Neither build's Info.plist has `NSMainStoryboardFile`: both are written whole rather than extending Tuist's default (ARC-22, 5ab089dea) | ARC-22 |
| No development frameworks | No `RedlampAutomation.framework` or `RedlampBench.framework` (2.3.1(a)) | Yes | Compliant | The App Store build links neither (ARC-22, 5ab089dea); `check-release-bundle.sh --app-store` fails on either | ARC-22 |
| Debug and profiling code | Debug drivers and probes compiled out of release builds (2.3.1(a)) | Yes | Compliant | All 13 `apps/RedlampMac/Sources/Debug*.swift` files open with the Debug and profiling guard on line 1, as do the automation sources; `REDLAMP_PROFILING` is set only by the test scripts (build audit §2.3) | — |
| Development switches | Engine variables, `REDLAMP_GENERATIVE_MODEL`, `REDLAMP_EVALUATION_MODELS` and endpoint overrides not read in the App Store build (2.3.1(a)) | Yes | Fix | `RedlampEngine+GenerativeFill.swift:27`; `ModelsSettings.swift:30`; `FeedbackClient.swift:65-68`, `CameraBenchRelay.swift:49-53`, `WhatsNewRelay.swift:30-33` | ARC-26 |
| Private API | Only public APIs (2.5.1) | Yes | Compliant | No private symbols in 4,943 undefined symbols across 25 Mach-O files of 0.3.1; no private frameworks or AppKit view names in its strings (build audit §1.5) | ARC-23 repeats the scan on each App Store build |
| No donation links in the binaries | No `ko-fi.com` in the App Store build (3.1.1(a)) | Yes | Fix | `SettingsView.swift:9`; `check-release-bundle.sh --app-store` finds it in `RedlampUI` and fails, unless `--allow-donation-link` lets it through until UX-50 (ARC-22, 053ae7f2d) | UX-50 |
| App Store bundle check | `scripts/check-release-bundle.sh` checks what the App Store build needs (build audit §2.6, §3.12) | Yes | Compliant | `--app-store` fails on Sparkle or its licence, the automation or bench framework, or the CLI in the bundle; a missing licence text; an executable without the sandbox entitlement; a version that isn't three integers; no privacy manifest or encryption key; an `SU…` or `RedlampFirmware…` key; and `ko-fi.com` (ARC-22, 053ae7f2d, 9e7bcc5da). Until ARC-17, ARC-24 and UX-50, `--allow-unsandboxed`, `--allow-no-privacy-manifest` and `--allow-donation-link` let their checks through with a warning | ARC-22 (`--app-store`) |
| Privacy manifest | `PrivacyInfo.xcprivacy` records "the types of data collected … on all platforms" (Privacy manifest files) | Yes | Fix | None in the repository or the bundle | ARC-24 |
| Required-reason APIs | Declared "on iOS, iPadOS, tvOS, visionOS, and watchOS" (Describing use of required reason API) | No | Not applicable | Not required on macOS; ARC-24 declares them anyway for the iPhone app to come | — |
| Third-party SDK manifests | Third-party SDKs carry their own manifests (Privacy manifest files) | No | Not applicable | The App Store build links no SDK that collects data; MLX ships none and needs none on macOS | — |
| Icon | The asset catalog's icon with its 1024 × 1024 image (build audit §3.8) | Yes | Unverified | `Assets.car` holds a 1024 × 1024 rendition with Aqua, Dark Aqua and tintable appearances; `CFBundleIconName` is set | Settled by `altool --validate-app` in ARC-23 |
| Architectures | arm64 only limits the app to Macs with Apple silicon (Apple developer news, 9 September 2026) | Yes | Compliant | `ARCHS = arm64` (`Module.swift:112`); the bundle check fails on any other slice (`check-release-bundle.sh:43`); every shipped Mach-O is arm64 | — |
| Model packs' namespace | Packs merge "into a shared namespace" on the device (Downloading Apple-hosted asset packs) | Yes | Fix | Five manifests have a top-level `LICENSE.txt` (vitmatte-base, owlv2-base, sam3, depth-anything-3-mono-large, flux2-klein-4b-fill), and FLUX's first file is `LICENSE.txt`; `location(of:)` resolves a pack's root from its first file (`ModelStore.swift:62-65`) | INF-07: each pack under `<id>/<version>/`, looked up by pack |
| No direct-download fallback | The App Store build fetches models only as Apple-hosted packs (2.4.5(iv)) | Yes | Decision | `ModelStore.swift:108` falls back to the publisher | DEC-97; INF-07 |
| Packs for cleared models only | Packs hold only cleared models, and ViTMatte version 2 only (build audit §5.3, §7) | Yes | Fix | Every manifest is `cleared`; `vitmatte-base.json` is version 2 on `main` (MSK-33) | INF-07 |
| Download progress | Progress follows `statusUpdates(forAssetPackWithID:)` (build audit §5.3) | Yes | Fix | `ensureLocalAvailability` reports none (`ModelStore.swift:103`) | INF-07 |
| Outdated packs removed | Older versions' packs removed with `remove(assetPackWithID:)` (build audit §5.3) | Yes | Fix | `removeOutdated` deletes only directly downloaded folders (`ModelStore.swift:129`) | INF-07 |
| Crash reports | Sandboxed apps read crash data through MetricKit (2.5.2) | Yes | Fix | `MacCrashReport.swift:9` reads `~/Library/Logs/DiagnosticReports` | ARC-17 |
| Lens Profiles folder | Files people add by hand reach the container (build audit §4.6) | Yes | Fix | `LCPProfileLibrary.swift` keeps them in `~/Library/Application Support/Redlamp/Lens Profiles`, which moves into the container | ARC-17: "Add Lens Profiles…" and "Show in Finder" |
| Licence texts in the bundle | Notices accompany binary distribution (section 5) | Yes | Compliant | Every component's licence ships in the app's resources, shown in Help › Acknowledgements… and Settings › About (ARC-25, f5c4b0520); tests fail when `LICENSES/` and the bundled copies drift apart | ARC-25 |

## 4. Apple's trademark rules for the listing

Read on 15 October 2026 from Apple's [Guidelines for Using Apple Trademarks and Copyrights](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html), the [App Store marketing guidelines](https://developer.apple.com/app-store/marketing/guidelines/) and the [Apple Trademark List](https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html). They apply to the listing, the screenshots and the site's App Store copy, none of which is written.

| Item | Requirement | Applies | Status | Evidence | Fix or decision |
| --- | --- | --- | --- | --- | --- |
| Referential use | Apple word marks only in a referential phrase such as "runs on" or "for", not part of the product name, less prominent than it, with no sense of endorsement (Trademark guidelines) | Yes | Fix | The name is Redlamp, with no Apple mark | ARC-27: "Redlamp for Mac" |
| "Mac" alone | "You may not use the Mac trademark standing alone except to denote or refer to the Apple Macintosh product line." (Trademark guidelines) | Yes | Fix | Not written | ARC-27 |
| Adjectives, no plurals | Trademarks "may not be used in the plural or possessive form" (Trademark guidelines) | Yes | Fix | The README, which the site reads, says "runs on Apple Silicon Macs" (`README.md:990`) | ARC-27: "requires a Mac with Apple silicon" in the listing and the site's App Store copy |
| Apple silicon | Apple's wording is "Mac computers with Apple silicon" (Apple Support 116943) | Yes | Fix | `README.md:990` capitalises "Silicon" | ARC-27 |
| Symbols and credit lines | Outside the United States, no trademark symbols; the credit notice "… is a trademark of Apple Inc., registered in the U.S. and other countries and regions" (Trademark guidelines) | Yes | Fix | Not written | ARC-27 |
| Badge artwork | "Use only the badge artwork provided"; not modified, angled or animated; at least 40 px high onscreen and 10 mm in print (Marketing guidelines) | Yes | Fix | The site has no badge yet | ARC-27 |
| Badge credit | "When the App Store badge is used, credit both Apple and the Apple Logo." (Marketing guidelines) | Yes | Fix | Not written | ARC-27 |
| "App Store" in English and its article | "The service mark App Store always appears in English"; "the App Store", "Mac App Store"; "on the App Store", not "at"; not "downloadable" (Marketing guidelines) | Yes | Fix | Not written | ARC-27 |
| OS names | "Avoid referring to iOS, macOS, tvOS, or watchOS in your marketing communications" (Marketing guidelines) | Yes | Fix | Not written | ARC-27 |
| Bezels and screens | "Use Apple-provided product bezels"; "Don't display a blank screen on an Apple product" (Marketing guidelines) | Yes | Fix | Not made | ARC-27 |
| No Apple Logo | The Apple Logo is never used in a referential phrase (Trademark guidelines) | Yes | Fix | Not made | ARC-27 |
| Apple's other marks | "macOS", "Metal", "ProRAW" and "App Store" are on Apple's trademark list, credited where used (Apple Trademark List) | Yes | Fix | The README names Metal 9 times and ProRAW 7 times | ARC-27: credit lines on the site where these appear |

## 5. Legal duties of a sale

These rows are engineering assessments for the owner and counsel, not legal advice.

| Item | Requirement | Applies | Status | Evidence | Fix or decision |
| --- | --- | --- | --- | --- | --- |
| LibRaw (CDDL-1.0) | Recipients of the executable are told how to get the source (CDDL 3.1) | Yes | Compliant | Its CDDL-1.0 text, copyright notice and a link to the source of the fork at the vendored commit, in Help › Acknowledgements… and Settings › About (ARC-25, f5c4b0520) | ARC-25 |
| libjxl, Highway, Brotli, skcms | Notices accompany binary distributions (BSD-3-Clause with libjxl's patent grant, BSD-3-Clause, MIT, BSD-3-Clause) | Yes | Compliant | Each text, with libjxl's patent grant, in Help › Acknowledgements… and Settings › About (ARC-25, f5c4b0520) | ARC-25 |
| MLX and Swift Numerics | MIT and Apache-2.0 notices | Yes | Compliant | MLX Swift with what it bundles (MLX, MLX C, metal-cpp, {fmt}, JSON for Modern C++, PocketFFT), and Swift Numerics, in Help › Acknowledgements… and Settings › About (ARC-25, f5c4b0520) | ARC-25 |
| Redlamp's MPL-2.0 | Executables tell recipients where the source is (MPL-2.0 §3.2) | Yes | Compliant | The MPL-2.0 notice and a link to the source on GitHub, in Help › Acknowledgements… and Settings › About (ARC-25, f5c4b0520) | ARC-25 |
| MPL-2.0 and the App Store's terms | How Apple's EULA, or a custom one, sits with MPL-2.0 | Yes | Decision | Not assessed by either audit | DEC-99 *(counsel)* |
| Sparkle (MIT) | Its notice where it ships | No | Not applicable | Not in the App Store build, nor is its licence text (ARC-22, 9e7bcc5da) | ARC-25 lists it in the direct download |
| SAM License | "You shall provide a copy of this Agreement with any such SAM Materials"; no uses subject to trade controls (`Sam3AppPrompts-LICENSE.txt:30-41`) | Yes | Compliant | The prompts' licence ships in `RedlampMasking.framework`, and `sam3.json` lists `LICENSE.txt` among the model's files (DEC-27) | — |
| Downloadable models' licences | Each model's licence travels with it once Apple hosts the packs | Yes | Fix | Five manifests carry a `LICENSE.txt`; Depth Anything V2 Small and SAM 2.1 tiny, from Apple's own Hugging Face repositories, carry none | ARC-25 lists each model's licence in Acknowledgements |
| Training-data exceptions | DEC-02 (Depth Anything V2 Small and 3), DEC-23 (FLUX.2 [klein] 4B), DEC-24 (OWLv2), DEC-27 (SAM 3) and DEC-35 (ViTMatte) rest on the owner's exceptions over non-commercial, research-only or unaudited data | Yes | Decision | `scripts/check-model-licenses.py:47` (`EXCEPTIONS`); Apple hosting the packs makes Apple a distributor too | DEC-93 *(counsel)* |
| Lensfun database | CC BY-SA 3.0 data in a paid bundle (DEC-04) | No | Not applicable | No lensfun data is in the bundle or the sources (build audit §6.3) | DEC-04 if LNS-03 adds it |
| Fujifilm's LUTs | Fujifilm's terms allow personal, non-commercial use; a paid app that sets them up adds a commercial party (DEC-73) | Yes | Decision | The app links to Fujifilm's page and imports the person's own files (`FujifilmLUT.swift:35`, `RecipeActions.swift:298-301`) | DEC-73 *(counsel)* |
| The firmware film model | DEC-84: "the firmware's licence and the study's own legal review caution against shipping anything derived from it"; a sale adds Apple as distributor | Yes, on `main` | Decision | TON-49, TON-50 | DEC-89 |
| Adobe's camera and lens profiles | Whether Adobe's terms let another app read the profiles its apps install (DEC-85) | Yes, once LNS-16 and TON-51 are built | Decision | DEC-85 is accepted, and still for counsel | DEC-85 *(counsel)*; DEC-96 for access under the sandbox |
| `Welcome.mp4` | Rights to the film and its score | Yes | Compliant | Redlamp's own film; its score is synthesised by `video/scripts/score.py` ("nothing in it is sampled", `video/README.md:60`); the stock names it shows follow DEC-94 | — |
| Lightroom, Adobe, Bridge, Photo Mechanic, Capture One | Nominative use of others' marks in menus and settings | Yes | Decision | `ShortcutAction.swift:428`; `KeymapPreset.swift:15-16`; `LibrarySettings.swift:40-49`. Assessment: nominative, kept with a notice | DEC-94 *(counsel)*; ARC-25 |
| Film stock and simulation names | Kodak, Ilford, CineStill and Fujifilm stock names, and Fujifilm's simulation names, as look names | Yes | Decision | `FilmLookCatalog.swift`, `BaseLooks.json`. Assessment: the highest-risk group; comparable App Store apps name stocks with a disclaimer; registrations not searched | DEC-94 *(counsel)* |
| Film icons | Icons "in the stock's familiar colours, with its speed. Redlamp's own drawing, not the makers' packaging." (`FilmIcon.swift:5-6`) | Yes | Decision | Assessment: a trade-dress risk alongside the names | DEC-94 *(counsel)* |
| Camera makers and models | Names of the cameras a file came from | Yes | Compliant | Nominative: the Metadata panel, the Camera Bench and LibRaw's camera table name the camera that made the file | — |
| Trademark notices | A notice in About and in the description for the third-party names used | Yes | Fix | In the app: Help › Acknowledgements… and Settings › About (ARC-25, f5c4b0520), worded as DEC-94 settles; the description's notice waits on ARC-27 | ARC-27 for the description; DEC-94 for the wording |
| Warranty of non-infringement | The seller warrants that nothing infringes "any patent, copyright, trademark, trade secret or other intellectual property" (DPLA Schedule 2, §5.1(b)) | Yes | Decision | As the rows above | DEC-89, DEC-93 and DEC-94 *(counsel)* |
| EU AI Act, Article 50(2) | Providers of systems generating synthetic images mark outputs "in a machine-readable format and detectable as artificially generated or manipulated", applying since 2 August 2026 | Yes, in EU storefronts | Decision | Generative Remove (RM-10) runs on the Mac; INF-11 §6.5 read that Redlamp may be its provider; Content Credentials export (RM-03) is not started | DEC-100 *(counsel)*: RM-03 before the EU storefronts open |
| Generated content labelled | The generated region is labelled as generated (DEC-23) | Yes | Compliant | `Label("Generated fill", …)` (`HealToolPanel.swift:192`) | — |
| Controller and contact | The privacy policy names the controller and a contact (GDPR Art. 13) | Yes | Fix | No policy | ARC-24, naming the seller DEC-99 settles |
| Lawful basis and withdrawal | Consent "for one or more specific purposes", withdrawable "at any time" (GDPR Art. 6(1)(a), 7(3)), or legitimate interests (Art. 6(1)(f)) | Yes | Fix | The person reviews a report and presses Send | ARC-24 |
| Erasure | Erasure "without undue delay" (GDPR Art. 17(1)) | Yes | Decision | Attachments are stored in a public Git repository (`web/lib/feedback.ts:4-13`), which keeps them in its history | DEC-95 |
| Children | Ages of digital consent from 13 to 16 (GDPR Art. 8) | Yes | Fix | The app isn't directed at children | ARC-24 |
| Transfers | GitHub and Vercel are in the United States; their Data Privacy Framework certification and processor terms | Yes | Unverified | Not checked by either audit | Settled by checking the Data Privacy Framework list and both companies' data processing terms |
| Request logs | Whether the website's host keeps IP addresses that Redlamp can read (What's New, the relays) | Yes | Unverified | The relay logs only error messages (`web/app/api/feedback/route.ts:39`) | Settled by reading Vercel's log retention for the project's plan |
| Camera Bench identifiers | The per-Mac random ID and the optional credit name are personal data | Yes | Fix | `CameraBenchRelay.swift:107-118` | ARC-24 |
| Establishment and representative | Where the seller is established decides whether an EU (GDPR Art. 27) or UK representative is needed | Yes | Decision | The seller is an individual whose account gives the United Kingdom as its country (DEC-99); whether a representative is needed is not settled (INF-11 §7.4) | DEC-99 *(counsel)* |
| Merchant | Apple is agent or commissionaire; the seller remains "solely responsible" for claims, warranties, assistance and support (DPLA Schedule 2, §1.1, §1.3, §6.1) | Yes | Fix | No support page | ARC-24's support page carries that responsibility |
| Refunds | The developer issues no refunds; Apple may refund within 90 days or on non-conformity, and the developer reimburses it (DPLA §3.4; Schedule 2, §6.3) | Yes | Compliant | The app has no purchase or refund code; UX-51's tips add none | — |
| EU trader certification | Traders certify that they "only offer products or services that comply with the applicable rules of EU law" (DSA trader requirements) | Yes | Decision | Not entered | DEC-99; ARC-27 |
| Tax reporting | Apple reports tax, sales and contact details to tax authorities (DPLA revision of 13 October 2026) | Yes | Fix | The account's tax forms are submitted (section 2); the 13 October revision's acceptance is not confirmed | ARC-27 |
| Export classification report | Exempt encryption may still call for a year-end self-classification report to the U.S. government (Complying with Encryption Export Regulations) | Yes | Unverified | Neither audit settled it | Settled by counsel or the Bureau of Industry and Security's rules once DEC-89 settles what encryption ships |

## Notes on the audits

**Where they disagree or overlap.**

- **Order.** The guidelines audit ranks its fixes by how likely each is to cause a rejection; the build audit gives the order to build them. This file uses the build audit's order, adds the rows only the guidelines audit found (ARC-27, UX-52, the support page in ARC-24, the trademark notices in ARC-25, the planned-feature entries in UX-50), and keeps both audits' existing rows.
- **ARC-22 and the sandbox.** The build audit's draft has ARC-22 depend on ARC-17, while saying that items 2 to 6 can land before the sandbox. This file follows the latter: ARC-22 depends only on its decisions, and ARC-17 depends on ARC-22, since the sandbox is turned on in the App Store build first.
- **Phases.** The build audit proposed P2 for ARC-25 and P3 for ARC-26, since both serve the direct download too. All new rows here are P4, as the owner asked for the App Store release; either can land earlier.
- **"See build audit."** The guidelines audit left 2.4.5(ii), 2.5.1 and 4.5.6 as unknown. The build audit settles 2.5.1's API half (no private API in 0.3.1) and 2.4.5(ii) (the CLI must leave the bundle). Neither covered 4.5.6: it is Compliant here, from a search of the sources for emoji and of the bundle's resources. The guidelines audit also points to the build audit for the licence agreement and MPL-2.0, which the build audit doesn't discuss; DEC-99 carries it.
- **Arm64 only.** The build audit found no Apple page on arm64-only apps and left it unverified. The guidelines audit quotes Apple's news of 9 September 2026, confirmed here: "To limit your app to Macs with Apple silicon, set your Xcode build architecture to arm64 only, then rebuild and resubmit." It is Compliant; the icon and the version below 1.0 stay unverified.
- **App Privacy answers.** The build audit suggests disclosing reports as not linked to the user except when a GitHub username is given, and leaves Device ID or User ID to the owner. The guidelines audit drafts a fuller label (adding Usage Data › Product Interaction and Contact Info › Name) and recommends "Linked to You" throughout, because the label can't vary per report. This file uses the guidelines audit's list and leaves linkage to DEC-95, recommending "Linked to You".
- **The firmware model.** Both audits recommend leaving it out. The build audit cites 5.2.1, 2.3.1(a) and 2.4.5(iv); only the guidelines audit adds 2.4.5(vi), since its key is bound to the app's signature. DEC-89 covers all four.
- **Content rights.** The guidelines audit lists Lensfun's database among the third-party content; the build audit found no lensfun data in the bundle or the sources. The latter is right today.
- **macOS 27.** The guidelines audit lists ARC-19, LIB-50, UX-44 and ARC-20 together; the build audit shows that only UX-44 is likely to be noticed in the shipped app, ARC-20 reaches only the validation layer, and MSK-33's ViTMatte crash in 0.3.1 is fixed on `main`, whose manifest is version 2.
- **Bundle ID.** The guidelines audit reads 4.3(a) as allowing the Developer ID build to share the bundle ID; the build audit raises what sharing it costs (one container for both builds, and a prompt when the other signature opens it). 4.3(a) is Compliant either way; DEC-91 decides.
- **The DEC header.** The tracker's decision table has the columns ID, Question, Recommended, Blocks, Decision and Source, so the drafted DEC rows fill Blocks rather than Depends on.

**Evidence checked.** 67 of the audits' line references, in 37 files, were read in the repository on 15 October 2026: `WelcomeView.swift:94, 99-101`; `SettingsView.swift:8-9, 55, 206-212, 216, 230-234`; `AppCommands.swift:49-52, 382`; `Version.xcconfig:2-3`; `apps/RedlampMac/Project.swift:25, 26, 31-32, 39-40, 63, 67, 68, 75-76`; `EditorTypes.swift:357-361`; `ShortcutAction.swift:428, 650-655`; `MenuBarKeys.swift:49, 110`; `MacCrashReport.swift:9`; `KeymapPreset.swift:15`; `Keymap.swift:18`; `FilmIcon.swift:5-6`; `ModelStore.swift:26-32, 45-46, 62-65, 102-108, 111-113, 129`; `CameraBenchRelay.swift:33-36`; `CameraBenchView.swift:212, 238`; `MaskingPanel.swift:272`; `HealToolPanel.swift:156`; `ModelsSettings.swift:30-37, 94`; `Module.swift:112`; `Tuist/Package.swift:7`; `LibrarySettings.swift:40-49`; `FeedbackSheet.swift:55`; `FeedbackClient.swift:52`; `SidecarLocator.swift:52`; `WorkingFolder.swift:67`; `check-release-bundle.sh:43`; `mise/tasks/release:200, 213-214, 227-229`; `RedlampApp.swift:255-257, 263, 355-362`; `FirmwareModelSettings.swift:16-20`; `check-model-licenses.py:47`; `SessionJournal.swift:110`; `FeedbackContext.swift:8-9`; `Screenshots.swift:6-7`; `RedlampEngine+GenerativeFill.swift:27`; `web/lib/feedback.ts:4-13, 47-49`; `README.md:257, 990, 1291, 1320`; `docs/plans/2026-10-01-releases-and-updates-design.md:22`; the decode service's entitlements; the seven model manifests; and the 13 `Debug*.swift` files' first lines. `redlamp.app/privacy`, `/support` and `/contact` were fetched and returned 404, and Apple's news of 9 September 2026 was fetched for its arm64 sentence.

**Corrections.**

- `MTL_DEBUG_LAYER` is set at `Tuist/ProjectDescriptionHelpers/Module.swift:196`, not lines 197-199 (build audit §7).
- The `FeedbackEndpoint` override is read at `FeedbackClient.swift:65-68`, not 63-67 (build audit §3.4).
- The release script preserves `entitlements,requirements,flags` (`mise/tasks/release:228`), not entitlements alone (build audit §1.2); the finding, that the app carries no entitlements, stands.
- The guidelines audit's 2.4.5(iv) row says models come "from GitHub releases"; two of the seven (Depth Anything V2 Small and SAM 2.1 tiny) come from Hugging Face (`ModelStore.swift:29-30`, build audit §5.1).
- The build audit's unverified arm64 question is settled by Apple's news of 9 September 2026, as above.

Everything else checked matched what the audits say.
