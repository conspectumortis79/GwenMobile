# Developing GwenMobile

Native SwiftUI app for iOS 26+ and the Mac through Catalyst, Swift 6 with strict concurrency. For installation as a
user see the [README](../README.md); for the feature list see [FEATURES.md](FEATURES.md).

- [Project layout](#project-layout)
- [Build and run in Xcode](#build-and-run-in-xcode)
- [Tests](#tests)
- [Quality gate](#quality-gate)
- [Response times](#response-times)
- [Texts: localization and prompts](#texts-localization-and-prompts)
- [Scripts](#scripts)
- [Staying inside the free 7-day window](#staying-inside-the-free-7-day-window)
- [Local models with Ollama](#local-models-with-ollama)
- [Local models on the iPhone](#local-models-on-the-iphone)
- [Phone calls and the default dialer](#phone-calls-and-the-default-dialer)
- [Music](#music)
- [Text messages](#text-messages)
- [Research answers](#research-answers)
- [Time and date](#time-and-date)
- [Reminders, shopping lists and timers](#reminders-shopping-lists-and-timers)
- [Timers](#timers)
- [Personal memory](#personal-memory)
- [Deleting the history by voice](#deleting-the-history-by-voice)
- [Weather](#weather)
- [Document scanner](#document-scanner)
- [Price watch](#price-watch)
- [Daily briefing](#daily-briefing)
- [Conversation mode](#conversation-mode)
- [Parallel wishes](#parallel-wishes)
- [Stopping a run](#stopping-a-run)
- [Notes](#notes)

## Project layout

| Path | Content |
|---|---|
| `GwenMobile/` | The app code, one folder per feature (see below): `GwenMobileKit` holds the self-contained foundation (API errors, storage, logging, text and synchronization helpers) and `GwenMobileFeatureCore` holds the features and views; `Info.plist`, `Assets.xcassets` and the `*.lproj` folders stay in the app target and are only referenced by it |
| `GwenMobileShell/` | The app executable: a `@main` shell that installs the probe hooks (Debug) and starts `GwenMobileApp` from `GwenMobileDevice` |
| `GwenMobileProbes/` | Debug-only end-to-end probes, built as the separate `GwenMobileProbes` framework; Debug links and embeds it, Release links it weakly and removes it from the app bundle (every file starts with `#if DEBUG`) |
| `GwenMobileKit` / `GwenMobileFeatureCore` | The source frameworks from `GwenMobile/`: `GwenMobileKit` is the measured foundation and `GwenMobileFeatureCore` contains the feature and UI implementation |
| `GwenMobileSystem/` | The fully covered system/UI helper framework: shared controls, Mac helpers and the small presentation pieces that the unit-test gate measures at 100 % |
| `GwenMobileAdapters/` | The fully covered UI helper framework: chat/source/file cards, pager views and the small presentation pieces that the adapter gate measures at 100 % |
| `GwenMobileDevice/` | The device/UI adapter framework: timer/notification scheduling, message composition, microphone/SFSpeech/SpeechAnalyzer sources, media library, scanner, translation and the large SwiftUI screens; not part of the unit-test gate and exercised by the probes |
| `GwenMobileLiveActivity/` | The WidgetKit extension for the listening Live Activity in the Dynamic Island and on the lock screen |
| `GwenMobileTests/` | Unit tests — pure logic, no network, no device — in the same feature folders |
| `Localization/` | The four `*.strings` files with every app text; `scripts/generate_l10n.py` turns them into `GwenMobile/Shared/L10nTable.swift` |
| `GwenMobile/Resources/Prompts/` | Every model-facing prompt text (`router_*`, `tool_<name>`, `args_<name>` and the builders' texts); `PromptLibrary` loads them from the bundle |
| `scripts/` | Build, install, device-test and renewal scripts (Python standard library only) |
| `project.yml` | XcodeGen definition; `GwenMobile.xcodeproj` is generated from it and never committed |
| `Config/Signing.xcconfig` | Your team id, written by `scripts/signing_config.py`, gitignored |

`GwenMobile/Info.plist` is the single source of truth for bundle configuration; a team id never goes into
`project.yml`.

| Feature folder | Holds |
|---|---|
| `App/` | App entry, appearance, Mac-only helpers, performance marks |
| `Chat/` | Chat screen, messages and bubbles, answers, conversation memory, history list, and the offline help center (`HelpCenterView.swift` with catalog, search, examples and the local status sheet); the screen is split into `ChatView.swift` plus `ChatView+Scaffold/Send/Answers/Stream/Files/Voice/Pictures.swift`, the parts `ChatHeaderView.swift`, `ChatThreadView.swift` and `ChatInputBar.swift`, and one `ChatView+…Flows.swift` per feature (the probe extensions `ChatView+Probes/Fixtures/Sweep.swift` live in `GwenMobileProbes/`), the bubble into `Bubble.swift` plus `Bubble+Sections/Text/Sources/Pictures/Files/Calendar.swift` |
| `Routing/` | Tool router (names in `ToolRouter.swift`, schemas in `ToolSchemas.swift`, request building in `ToolRouterRequest.swift`, decision mapping in `ToolDecisions.swift`, planning in `ToolRouterPlan.swift`), send plan, wish splitting, router prompts, `PromptLibrary` |
| `Memory/` | Durable facts about the user: local store, categories, suggestions, due dates, *About me* list |
| `Voice/` | Dictation, listening mode, conversation mode with voice processing and barge-in, microphone and audio session, read-aloud, Siri, tones |
| `Contacts/` | Contact cards, reading the address book, matching a person, shared contact texts |
| `Calls/` · `Messages/` · `Music/` · `Clock/` | Phone calls, text messages, music, time and date |
| `Calendar/` · `Places/` · `Pictures/` | Appointments, places and routes, pictures and galleries |
| `Scans/` | Document scanner: VisionKit capture, on-device OCR, PDF storage, reminder offer, sharing |
| `Research/` · `Prices/` · `Files/` · `Code/` · `Translation/` | Web research with source checks (syndication, origins, citation review) and answer length, price comparison, attached files, code files, translation |
| `Providers/` | AI providers, models, thinking levels, API errors; the API client is split into `QwenAPI.swift` plus `QwenAPIChat/Images/Models/Calendar/Stream.swift` |
| `Settings/` · `Storage/` | Settings and their migration; files on disk, histories, undo; the store is split into `AppSettings.swift` plus `AppSettings+Keys/Persistence/Models/Seeds.swift` with `Voice/Memory/Briefing/MusicSettings.swift` as the grouped values; the history is one JSON file per conversation under `conversations/` (the old single `conversations.json` is imported once and stays as a fallback) |
| `Shared/` | Helpers every feature uses: texts (`L10n`), formatting, networking, build flags, presenting, `ScaledTypography` |

XcodeGen takes the folders recursively, so a new file only has to be placed in its feature folder. Swift does not
care about folders — every target is one module — they only keep 400 files findable.

## Build and run in Xcode

```
python3 scripts/signing_config.py
xcodegen generate
open GwenMobile.xcodeproj
```

- `signing_config.py` writes `Config/Signing.xcconfig` with your Apple team id (`--show`, `--set <TEAMID>`,
  `--detect`); without that file `xcodegen generate` stops. Change the team there, never in Xcode's signing pane —
  the next generate throws it away.
- Run `xcodegen generate` again after adding or removing files or changing `project.yml`.
- The simulator needs no team; a free Apple ID is enough for your own device, whose profile expires after 7 days.

## Tests

```
xcodegen generate
xcodebuild test -scheme GwenMobile -skipMacroValidation -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

The simulator name must exist (`xcrun simctl list devices`); a paired iPhone works as the destination instead
(`-destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates`, the UDID comes from `xcrun devicectl list devices`).

Microphone, camera, calendar or the real account are covered by the debug-only probes: debug builds answer
`gwenmobile://test/<scenario>` and write their reports into the app's `Documents/`.

### One scenario at a time on the device
`./scripts/device-test.py` reads every scenario out of `GwenMobileProbes/`, runs the chosen one on the paired iPhone
and pulls every touched file into `build/reports/<time>-<scenario>/`.

| Flag | Effect |
|---|---|
| `--list` | Show the scenarios, grouped |
| `--build` | Rebuild and reinstall first |
| `--scenario a,b` | Run these scenarios without the menu |
| `--group g1,…` / `all` | Run whole groups |
| `--plan` | Show what would run, without a device |
| `--timeout`, `--stale` | Budget per scenario, and seconds without a new trace line before a run counts as broken |
| `--listen-release` | Seconds before the runner releases `listenroute` early (default 20; `0` = never) |

If the console connection to the device drops, for example during a long image upload over Wi-Fi, the runner no
longer aborts: it reads the finish signal `FLOWTEST finished cmd=<name>` from `Documents/flow_trace.txt` over the
file service, keeps polling until the app really stopped writing or the budget runs out, and then pulls the reports
as usual.

The app only writes its trace while it runs — in the background only while listening mode holds the microphone —
so the device must stay untouched during a run; `historywipe` demands a typed `YES`. On the Mac, `open /Applications/GwenMobile.app --args -gwenflowtest <name>`
starts one scenario, and the report lines appear in the `flow` log category as `BERICHT <file> <line>`.

`listenroute` is interactive: it waits for a spoken word. The runner releases it after 20 s so a batch continues
on its own; manually the release comes from `gwenmobile://test/listenrelease` or the marker file
`Documents/listen_release`.

`airdropprobe` needs no human handover: it opens the share sheet, invokes the AirDrop item-source callback on the
device, and checks that the sheet closes. The report names the simulated callback and the sheet state.

The `shot*` scenarios (`shotchat`, `shotplusmenu`, `shotsettings`, `shothistories`, `shotsettingsvoice`,
`shotsettingsmodels`, `shotsettingsmusic`, `shotconversation`, `shotweather`, `shotreminders`, `shotcalendar`,
`shotplaces`, `shotcode`, `shotscan`, `shotscanreminder`, `shotpricewatch`, `shotpricewatchhit`, `shotbriefing`,
`shotresearchfollowup`, `shotresearchsourcecheck`, `shotimagegeneration`, `shotphotoediting`, `shotphotogallery`,
`shotpricecomparison`, `shottimer`, `shotmusic`, `shotmessage`, `shotcall`, `shotfiles`, `shottranslation`,
`shotmemory`, `shottime`, `shotmultitask`, `shotreadaloud`, `shothistoryundo`, `shotlistening`, `shotstop`,
`shothelp`) are
screenshot fixtures for the README: they open a fresh conversation, most fill it with fixed, generic data — no
location and no provider — show the requested view and then poll for the release signal, so
`xcrun simctl io booted screenshot` can capture it. The release comes from `gwenmobile://test/shotrelease` or the marker file `Documents/shot_release`;
`./scripts/device-test.py` writes the marker on its own after capturing the screen, and a hold without a release ends
after two minutes. The chat fixtures remove their conversation again after the release and flush the pending save;
the history and undo fixtures run on a temporary store, and the settings fixtures restore appearance, language and
voice settings. They never touch the user's own chats on the device.

## Quality gate

The repository has no CI pipeline (`.github/` is gitignored); run both groups locally before a commit:

| Group | Steps |
|---|---|
| `lint` | `python3 scripts/generate_l10n.py --check`, `python3 scripts/test_check_l10n_usage.py`, `python3 scripts/check_l10n_usage.py`, `python3 scripts/test_check_l10n_placeholders.py`, `python3 scripts/check_l10n_placeholders.py`, `python3 scripts/test_sync_infoplist_strings.py`, `python3 scripts/sync-infoplist-strings.py --check`, `python3 scripts/test_check_markdown_links.py`, `python3 scripts/check_markdown_links.py`, `python3 scripts/test_device_test.py`, `python3 scripts/test_renew_signing.py`, `python3 scripts/test_xcode_teams.py`, `swiftformat GwenMobile GwenMobileTests GwenMobileProbes GwenMobileSystem GwenMobileAdapters GwenMobileDevice GwenMobileLiveActivity GwenMobileShell --lint`, `swiftlint lint --strict --quiet` |
| `test` | generate the project from `project.yml`, pick an installed iPhone simulator with iOS 26 or newer, `scripts/grant_test_permissions.sh <UDID>`, `xcodebuild test -enableCodeCoverage YES`, `python3 scripts/coverage_gate.py --result … --min 100`, `python3 scripts/coverage_gate.py --result … --target GwenMobileFeatureCore --source-lines --min 100`, `python3 scripts/coverage_core.py --result …`, `python3 scripts/coverage_system.py --result … --min 100`, `python3 scripts/coverage_gate.py --result … --target GwenMobileAdapters --min 100` |

- `.swiftlint.yml` keeps the correctness and hygiene rules enabled; the code carries no comments, names and small
  functions carry the intent.
- `.swiftformat` disables the default rule set and enables the rules the code already follows, so the linter
  catches future drift without reformatting the existing 55k lines.
- The coverage gate fails below 100 % line coverage of the `GwenMobileKit.framework` target. The foundation
  currently sits at 100 % (520/520 lines); the report comes out of the `.xcresult` bundle through `xcrun xccov`.
  `GwenMobileProbes` is a target of its own and never counts as app code, so the probe tooling cannot dilute the
  metric. `GwenMobileFeatureCore` is gated with `--source-lines`: it counts executable source lines, skips closing
  braces/compiler-generated implicit closures and excludes `GwenMobile/Local/`, whose MLX model loading and
  download integration is exercised on the device and through the probes instead. It currently sits at 100 %
  (12 355/12 355). The raw xccov metric still lists the compiler thunks separately, which is why the feature layer
  uses the source-line gate. The app shell is at 100 % (9/9).
- `python3 scripts/coverage_core.py --result <bundle.xcresult>` is the second gate: it measures the files of the
  foundation that live under `Routing`, `Storage`, `Code`, `Shared`, `Calls`, `Contacts`, `Places`,
  `Translation` and `Scans` and fails below 100 % of those lines. The measured set is currently 455/455 lines over
  14 files; a run with `--list` prints every file and its coverage.
- The split is deliberate: the live system adapters need a real Spotify app, a Messages/Telephony entitlement,
  installed Speech/Translation assets, a microphone or a camera, the TCC prompts need a human, and the actions
  inside `contextMenu`/`toolbar`/`alert` builders are only built and fired by a running UI. The live implementations
  move step by step into `GwenMobileDevice` behind the ports in `GwenMobileFeatureCore`; the app installs them in
  `GwenMobileShell` only outside the XCTest host. The measured foundation has no such seams and is therefore
  genuinely at 100 %. `GwenMobileFeatureCore` is at 100 % of the unit-testable source lines (12 355/12 355,
  excluding `GwenMobile/Local/`); its raw xccov metric still counts compiler-generated implicit closures
  separately, which is why the feature gate uses `--source-lines`.
  Tests that only exercise code paths without asserting behavior carry the `testSmoke` name prefix; every other
  test contains an explicit assertion. The suite runs 3 001 tests with 0 failures and up to five skips; the unsigned
  simulator skips the real-keychain test, whose logic is covered through the keychain seams, and environments
  without a runnable CoreML backend skip the bundled voice-model test. `GwenMobileDevice` holds the device/UI adapters and is not gated; the
  device-only paths (Telephony entitlement, `PhotosPickerItem`, AlarmKit/notification prompts, SpeechAnalyzer
  assets, media-library content, real camera capture) plus UI builder branches that only a running app builds are
  the job of the probes (`./scripts/device-test.py`), not of the simulator suite. `GwenMobileSystem` and
  `GwenMobileAdapters` contain only fully covered helpers. `GwenMobileSystem` is gated by
  `python3 scripts/coverage_system.py --result … --min 100`: 100 % over 10 files (182/182 lines).
  `GwenMobileAdapters` is gated by `python3 scripts/coverage_gate.py --result … --target GwenMobileAdapters --min 100`:
  100 % (1 119/1 119 raw lines). Both targets have no exclusion list; every remaining file is measured.
- The live permission tests need pre-granted TCC entries; otherwise they skip instead of blocking on a system
  prompt. `scripts/grant_test_permissions.sh [UDID]` grants calendar, contacts, photos, media library, microphone,
  reminders and location explicitly (the blanket `all` action leaves denied rows in place), adds the
  speech-recognition entry directly to the simulator TCC database, which `simctl` does not expose, and sets
  `GWEN_LIVE_PERMISSIONS=1` in the booted simulator. Run it once per fresh simulator before a coverage run.
- The checks need SwiftLint, SwiftFormat and XcodeGen (Homebrew) and an Xcode whose SDK has SpeechAnalyzer,
  AlarmKit and LiveCommunicationKit (iOS 26+).
- The signing config is created from `Config/Signing.xcconfig.example`; the simulator test runs without
  `CODE_SIGNING_ALLOWED=NO`, so no Apple ID or team is needed for the simulator run. Disabling code signing makes `SecItemAdd`
  fail, the keychain tests skip and `GwenMobileFeatureCore` stays below the 100 % gate — that is why the flag is
  not used.
- `GwenMobileKit` exposes a public API and is built without `ENABLE_TESTABILITY`; the remaining framework targets
  are built with `ENABLE_TESTABILITY = YES`, including Release, because their cross-module symbols are `internal`
  and reached with `@testable import`. Turning testability off for those targets needs their module boundaries
  turned into a `public`/`package` API first.

## Response times

The measured starting point and the ordered list of latency changes live in
the internal performance notes: the router prompt is roughly 11 000 tokens per message (2 328 tokens of
rules plus 8 368 tokens of tool descriptions), the current date sits in the first line of that prompt so provider-side prefix
caching never hits, the router runs before the answer, the SSE reader buffers 50 ms and the UI throttle another 60 ms, and a
picture is uploaded twice (router and answer) at up to 800 kB of base64 each. The report also lists which `flowMark` lines
already measure the path (`ROUTER dauer_ms`, `QUELLENFILTER dauer_ms`, `WEBANTWORT dauer_ms`, `FETCH dauer_ms`) and the three
values that are still missing: time to first visible token, total answer time and request payload size.

## Texts: localization and prompts

- Every app text lives in `Localization/de.strings`, `en.strings`, `es.strings`, `fr.strings` (old-style
  `.strings`, one entry per line, sorted by key). `python3 scripts/generate_l10n.py` writes
  `GwenMobile/Shared/L10nTable.swift` from them; the app keeps its own runtime table (`L.t`), so the in-app
  language switch does not depend on the system language. After editing a `.strings` file run the generator;
  `--check` fails when the table is out of date and is part of the quality gate.
- `GwenMobileTests/Shared/LocalizationTests.swift` checks that every key exists in all four languages and that the
  `%@`/`%d` placeholders match across them.
- Every model-facing prompt lives as `*.md` in `GwenMobile/Resources/Prompts/`: the router's system-block
  fragments (`router_*`), one description per tool (`tool_<name>`), the argument descriptions of every tool
  (`args_<name>`, one `key=value` line per property) and the texts of the prompt builders (calendar router,
  research answers with its source check, price checker, picture director, files, memory, translation). `PromptLibrary` reads them
  from the bundle and replaces `{{placeholders}}`; `PromptLibrary.field` reads a `key=value` line.
  `ToolRouter.promptValues` names the tool placeholders, dynamic values (`now`, catalog, transcript,
  delete-history word) come from the call.
- `Prompts.swift`, `SystemPrompt.swift` and the feature files only assemble these texts with runtime values.
- `GwenMobileTests/Routing/PromptLibraryTests.swift` checks that every prompt loads, that no placeholder stays
  open and that the system block carries the dynamic blocks.

## Scripts

### Install on the iPhone
`./scripts/deploy-iphone.py` builds the current working copy and installs it on the connected iPhone, by cable or
Wi-Fi. Flags: `--list`, `--device <UDID|Name>`, `--skip-build`, `--no-launch`, `--build-only`, `--open <URL|scenario>`
(start into a probe), `--console`, `--plan`, `--configuration`, `--clean`. `xcodegen` and the team-id script run
inside it.

### Mac build as an installable disk image
`./scripts/build-mac-dmg.py` writes a drag-install `~/Desktop/GwenMobile-<version>-<date>.dmg` for Apple Silicon
(arm64 only, no x86_64 slice). Flags: `--configuration`, `--out`, `--name`, `--no-verify`, `--clean-build`. The build
is incremental and reuses `build/MacDMG`; `--clean-build` deletes it first. It is signed `Apple Development`, so another
Mac needs right-click → Open once (`xattr -dr com.apple.quarantine /Applications/GwenMobile.app`).

The iOS chat carries the offline help center: `HelpCenterView`, `HelpCatalog` and `HelpRequests` open from the
empty chat, the **+** menu, Settings and error alerts; its *Check status* action uses `AppStatusReader` directly,
without the tool router. The Mac menu bar additionally carries **Help → GwenMobile Help** (⌘?), which opens
`MacHelpView` as a sheet with the most important Mac features and shortcuts. `MacHelpCommands`, `MacHelpView` and
`MacHelpRequests` sit behind `#if targetEnvironment(macCatalyst)`; the mobile help center is shared by both builds.

Settled chat bubbles render their text on the Mac through `MacSelectableAnswerText`: a `UITextView` whose
`textContainerInset` carries the bubble padding, so a selection drag can start anywhere in the bubble - including
the padding around the glyphs - and not only on a character. It also converts the answer's `AttributedString`
(markdown traits, citation colours, claim highlights) into UIKit attributes and routes `gwen-source`, `gwen-claim`
and `tel` links through `Bubble.handleAnswerURL`. iOS keeps the SwiftUI `Text` with `.textSelection(.enabled)`.

### Smaller helpers
- `python3 scripts/generate_l10n.py` writes `GwenMobile/Shared/L10nTable.swift` out of the four `Localization/*.strings`
  sources (`--check` only verifies that the generated file is current).
- `python3 scripts/coverage_gate.py --result <bundle.xcresult> --min <percent>` reads the coverage out of a test
  result bundle and fails below the given line coverage of the measured target (default `GwenMobileKit`).
- `python3 scripts/coverage_core.py --result <bundle.xcresult>` does the same for the logic core (default `--min 100`,
  `--list` for the per-file report). The measured set and the excluded views/adapters are defined at the top of the
  script; new pure logic belongs in one of the nine folders and is measured automatically.
- `python3 scripts/check_l10n_usage.py` fails when a key from `Localization/de.strings` is referenced nowhere in the
  Swift sources; enum-derived families (`memory_cat_*`, `scan_task_*`, …) and the four contact keys built from a
  `keyPrefix` are allowed explicitly in the script. `python3 scripts/test_check_l10n_usage.py` runs its unit tests.
- `python3 scripts/check_l10n_placeholders.py` fails when `L.fmt`, `L.fmt2` or `L.n` is called with a key whose
  translations do not carry the matching number of `%@`/`%d` slots; for `L.counted(_:one:many:)` the `one` text must
  not carry a placeholder and the `many` text needs `%d`. Keys assembled from a variable at runtime are skipped.
  `python3 scripts/test_check_l10n_placeholders.py` runs its unit tests.
- `python3 scripts/check_markdown_links.py` checks every relative file link and every `#anchor` in the repository's
  Markdown documents (README, `docs/`, the idea report) against the files and GitHub heading slugs; prompt resources
  under `GwenMobile/Resources/Prompts/` are not documents and stay out. `python3 scripts/test_check_markdown_links.py`
  runs its unit tests.
- `python3 scripts/sync-infoplist-strings.py` copies the English permission texts and the display name from
  `GwenMobile/Info.plist` into `GwenMobile/en.lproj/InfoPlist.strings`; the German ones in `de.lproj` stay untouched.
  `--check` verifies that every language carries every usage description and the display name without writing
  anything, and the sync itself fails when a translation is missing. `python3 scripts/test_sync_infoplist_strings.py`
  runs its unit tests.
- `python3 scripts/test_renew_signing.py` runs the unit tests of the signing and renewal scripts (standard
  `unittest`, no device, no Xcode).

## Staying inside the free 7-day window

Without a paid Apple Developer Program every profile lives exactly 7 days (creation and expiry are seven days apart,
on the iOS and on the Catalyst profile), and then the app has to be reinstalled on both targets.
`./scripts/renew-gwenmobile.py` renews that window: it moves the cached profiles out of the way (into a backup under
`build/renew/`), lets Xcode create fresh ones, reinstalls on the iPhone and into `/Applications/GwenMobile.app`, and
reports how many days you now have again.

| Command | Effect |
|---|---|
| `./scripts/renew-gwenmobile.py` | Status: what expires when, is the job loaded |
| `--renew` | Renew whatever is below the threshold |
| `--renew --force` | Renew both targets right now |
| `--renew --targets mac` | Only the Mac app |
| `--install-schedule 09:20` | Install the daily launchd job |
| `--start-now` | Run that job by hand |
| `--remove-schedule` | Delete the job again |

Further flags: `--targets iphone,mac,all`, `--threshold <days>` (renew when fewer days are left, default 2),
`--device <UDID|Name>`, `--wait-minutes <n>` (the scheduled job waits 20 for the iPhone to appear),
`--configuration <Debug|Release>` (default: each target keeps its own build — Debug on the iPhone, Release on the
Mac), `--clean`, `--no-launch`, `--restart-mac`, `--plan`, `--notify`/`--no-notify`.

- The job is not a background service: it is a calendar entry in
  `~/Library/LaunchAgents/com.mortis.gwenmobile.renew-signing.plist` that starts exactly one process at the chosen
  time — a run that finds nothing to do is finished in a few seconds, a renewal takes the build time.
  `./scripts/renew-gwenmobile.py` and the install output both name the next run; `--start-now` runs the job
  immediately. Because the agent starts with the `python3` inside Xcode.app, macOS lists it under *Login Items* →
  *Allow in the Background* as **Xcode**.
- A run writes `build/renew/history.log` plus `build/renew/launchd.{out,err}.log` and posts a macOS notification when
  no terminal is attached (it comes from `osascript`, so it appears once System Settings → Notifications allows it).
  Backups of every replaced profile stay under `build/renew/profile-backup-<target>-<time>/`.
- One step stays manual: the iPhone only runs a free-team app after **Settings → General → VPN & Device Management →
  Apple ID → Trust**. Nothing on the Mac can press that button, so the script notices the refusal
  (`profile has not been explicitly trusted`), installs anyway and tells you — with a sound — which taps are left.
- The deadline that counts is the one on the **device**: every successful run stamps `build/renew/installs.json`, and
  7 days minus that stamp is compared against the cached profile — the earlier of the two decides. A target whose
  install failed stays pending and is retried on every later run, so a single missed evening cannot silently carry
  the app past its expiry.
- `devicectl list devices` reports `state = disconnected` for a Wi-Fi-paired iPhone that is perfectly reachable; the
  scripts therefore probe `devicectl device info lockState` instead of trusting that field.

## Local models with Ollama

Ollama listens on `*:11434` by default. Pull a chat model that can call tools (`ollama pull qwen3:8b`; embedding
models are filtered out of the picker), then Settings → AI & models → AI provider → *OpenAI-compatible server* → *Ollama (local)*,
with the Mac's Bonjour name instead of `localhost` (for example `http://MyMac.local:11434/v1`). No key is needed; iOS
asks once for local-network permission. **Debug builds only** also apply a `Documents/seed_provider.json`.

## Local models on the iPhone

`ProviderID.local` runs MLX Swift LM models inside the app: no second app, no server and no key. The models live
under `Library/Application Support/local-models/<repo>`; the local form lists every installed model from its
`model.json` and searches Hugging Face for new MLX models. The form has an installed list, the **Hugging Face MLX**
search, a detail card for download, progress, delete and activation, and the storage overview. The only user-facing
search filter is whether the model fits the RAM. Discovery uses `LocalMemory.canHost`, which reserves 3.6 GB for iOS
and the generation floor; actual loading uses `LocalMemory.canFit` with the 700 MB/1.5 GB headroom. The app carries
`com.apple.developer.kernel.increased-memory-limit` (`Config/LocalModels.entitlements`, also in the dialer and
messaging entitlements); without it an 8 GB device cannot load E2B, and `LocalEngine` fails with a memory error instead
of hanging.

`LocalEngine` owns the model and serializes every request (`acquire`/`release`), so only one `load` runs at a time.
`LocalModelConfigurations` selects the VLM registry entry for Gemma (with the Gemma reasoning config) and the
`ModelConfiguration` for `mlx-community/Qwen3.5-9B-MLX-4bit` (`extraEOSTokens: ["<|im_end|>"]`, Qwen's own reasoning
and `.qwen35` tool format resolved by the factory).
The gate is required: the send flow starts the follow-up resolver (`max_tokens` 4000) and the tool router
(`max_tokens` 700) concurrently. Without it both entered `load` before `loadedModel` was set, loaded the model twice
and iOS killed the app for `vm-pageshortage` with about 6.2 GB resident. `LocalEngine.memoryReport()`,
`modelSnapshot()`, the Debug-only `queueState()` and the `localprobe` and `localquestion` scenarios measure loaded
model, active requests, queue, free memory and MLX memory.

### Prompt budget and the Metal buffer limit

The local tool router never receives picture data: it gets the picture flags in its system block, not the image
bytes. Gemma 4 runs the multimodal prefill unchunked and computes the logits for the whole prompt in one
`asyncEval` (`[1, promptTokens, 262144]`). With the full 25-tool schema and one remembered picture the router prompt
reached 9166 tokens; MLX then asked Metal for a 4.8 GB buffer, above the 4 GB per-buffer limit, and aborted inside
`TokenIterator.prepare`. The repeated allocation pressure ended in
`memorystatus: all vm-pageshortage victims exhausted`. The router now uses the compact schemas, runs without
pictures, and local web answers drop pictures as well. A direct local chat keeps at most one picture and only when
the question names a picture. `LocalEngine.localRequest` keeps the system message plus two recent messages, the
local answer budget is 700 tokens, `Memory.memoryLimit` is set to `LocalMemory.mlxLimit`, and generation stops below
`LocalMemory.generationFloor`. When the kept local prompt text is longer than 4,000 characters—for example a 41 KB text
file—remembered pictures are dropped even if the file text happens to contain the word "image"; the file analysis then
uses the chunked text-only prefill. On the iPhone 16 the fixed router prompt is 6224 tokens and finishes in 17-22 s; the
web answer prompt is 4852 tokens for 136 output tokens in 17 s with an MLX peak of 3.55 GB and the app alive.

### Hugging Face MLX browser

The local model form has a **Hugging Face MLX** section. When the section opens, or when refresh is tapped, it queries
`https://huggingface.co/api/models?author=mlx-community&filter=mlx&sort=downloads&limit=100&full=true`, then loads
`/api/models/<repo>?blobs=true` for the candidates. A candidate is offered only when the repository is public and
ungated, is `library_name=mlx` with `safetensors` weights, has `config.json`, `tokenizer.json`, a `.safetensors`
weight and a supported architecture in `VLMTypeRegistry` or `LLMTypeRegistry`. The download uses the existing
`LocalModelDownloader`; the model manifest stores the choice metadata, so a downloaded dynamic model survives a
relaunch and is resolved through `LocalCatalog`/`LocalModelFiles`. `LocalCatalog` itself has no model list: it is a
registry filled by the Hugging Face search and by installed `model.json` manifests. The three IDs in
`LocalModelConfigurations` are compatibility overrides for Gemma reasoning, Qwen EOS tokens and the Qwen thinking
filter; they are not a displayed catalog and every other MLX model uses the default configuration.

The only user-facing filter is **only models that fit the RAM**; there is no parameter-range or file-size switch.
The list still keeps only MLX/safetensors chat checkpoints with a supported architecture and the required
`config.json`, `tokenizer.json` and chat template. The parameter count comes from the model name (`E2B`/`4B`/`9B`)
for display, not from `safetensors.total`, because quantized MLX checkpoints count packed `U32` values there.
`LocalMemory.canHost` reserves 3.6 GB for iOS and the generation floor; `LocalEngine` unloads the current model
before loading another one. On the 8 GB iPhone 16 the fitting list includes the installed E2B, its QAT variant, small
0.5–4B models and Mistral 7B; E4B and Qwen 9B are hidden by the RAM filter. Dynamic models
are experimental: text-only models load through `LLMModelFactory`, vision models through `VLMModelFactory`, and tool
calling is not guaranteed for every Hub repository.

`reasoning_effort: none` becomes `enable_thinking: false`; `LocalThinkingFilter` removes a
`<|channel>thought ... <channel|>` span or a Qwen `<think> ... </think>` span from the streamed text. MLX needs a
Metal device, so the iOS simulator cannot run a model; test on the iPhone or the Catalyst build. The increased-memory
entitlement is also why E2B loads at all on a free Personal Team; the profile keeps the entitlement when Xcode manages
signing. The UI proposal is in `docs/mockups/local-models.html`.

## Phone calls and the default dialer

The `call_contact` tool of `ToolRouter` becomes `SendRoute.call(ContactRequest)`; `CallFlowRunner` asks a
`ContactDirectory` (live: `LiveContactDirectory`, Contacts framework) for the cards, `ContactMatching` picks exactly
one target or asks back, and a `CallPlacing` starts the call. `CallDesk` holds both for `ChatView`.

| Way | When | Prompt |
|---|---|---|
| `PhoneLinkDialer` (`tel:`) | always available, the only way with a free Apple ID | iOS asks once |
| `CellularDialer` (LiveCommunicationKit, `TelephonyConversationManager`) | iOS 26+, `com.apple.developer.dialing-app` | none once GwenMobile is the default dialer app |

- The dialer entitlement is only granted to the paid Apple Developer Program (Xcode's capability list names
  `APPLE_DEVELOPER_PROGRAM` as the only team type), and Apple lets it be tested only with an account registered in the
  EU and a device in the EU. It is therefore off by default: `Config/DefaultDialer.entitlements` is only signed in when
  `Config/Signing.xcconfig` holds `GWEN_DIALER = YES`, which also sets the `GwenDefaultDialer` key in `Info.plist`
  that `DialerChoice` reads. With a free team leave it off — the profile cannot carry the entitlement and the build
  would fail to sign.
- LiveCommunicationKit is weak-linked (iOS 26+), and the Mac build never uses it.
- Numbers in an answer are detected on the device (`PhoneLinks`), shown as `tel:` links and on a tap handed to the
  same `CallDesk` dialer through `ChatView.placeCall`; the tap posts the usual call answer line. The chat prompt
  (`phone_link_hint`) also asks the model to write every phone number as `[text](tel:number)`, which `Bubble
  .telNumber` routes the same way; `AnswerHTML` keeps `tel:` in the export and `SpeechSynthesizer.stripForSpeech`
  reads the label instead of the target.
- **No probe can call anybody:** every `gwenmobile://test/<scenario>` run swaps a `ProbeDialer` into the `CallDesk`
  that only records the number, and puts the live dialer back afterwards. The unit tests use their own recorders.

| Probe | What it measures |
|---|---|
| `callroute` | Real router: call wishes become `call_contact` with the right relation and group, questions about calls and other wishes (pictures, places, routes, appointments) stay what they were — `call_route.txt` |
| `callflow` | Whole chat flow with fixture contacts and the recording dialer: which number would have been dialled, and the answer text — `call_flow.txt` |
| `calllink` | Which numbers in answer texts become `tel:` links and which stay plain, and that a tapped number reaches the `CallDesk` — `call_links.txt` |
| `callcontacts` | Reads the real address book (read only) and resolves "Mutter", "Mama", "Papa"; numbers masked — `call_contacts.txt` |
| `calldialer` | Build flag, iOS version, which way a live call would take, and that the probe lock is in place — `call_dialer.txt` |

## Music

`control_music` becomes `SendRoute.music(MusicRequest)`; `MusicFlowRunner` picks the service (`MusicServiceChoice`)
and hands the request to its `MusicSource`: `AppleMusicSource` (library via `MediaLibraryReader`, catalog via
`ITunesCatalogSearch`, playback via `SystemMusicApp`) or `SpotifySource` (`SpotifyLink` with `SpotifyAuthorizer` and
`SpotifyRemote` from the SDK, `SpotifyWebClient` for search and background control). `MusicDesk` holds the sources
for `ChatView`.

- The Spotify SDK comes as Swift package `https://github.com/spotify/ios-sdk` (5.0.1, binary `SpotifyiOS.xcframework`
  with slices for iPhone and simulator only). `project.yml` links it with `destinationFilters: [iOS]` — the value is
  case-sensitive, `ios` is silently dropped and the Mac build then fails on the missing slice. The Spotify code is
  compiled only when `canImport(SpotifyiOS)` and not on Mac Catalyst.
- `RecordingSetup` mixes with other audio (`.mixWithOthers`) instead of ducking it: the session of listening mode
  stays active for hours, and Apple documents ducking as lasting until the session is deactivated and to be used for
  a few seconds only.
- **No probe plays music:** every probe run swaps silent `ProbeMusic` sources into the `MusicDesk` and restores the
  live ones afterwards; the unit tests use their own fakes.

| Probe | What it measures |
|---|---|
| `musicroute` | Real router: music wishes and commands become `control_music` with the right action, kind and service; questions about songs, pictures of artists, the time and calls stay what they were — `music_route.txt` |
| `musicflow` | Whole chat flow with silent sources: which service receives which request — `music_flow.txt` |
| `musiclibrary` | Library access and how many playlists, artists, albums and songs the device holds, with timings (read only) — `music_library.txt` |
| `musiccatalog` | Live iTunes search for a song, an artist and an album, without playing — `music_catalog.txt` |
| `spotifycheck` | SDK, client ID, login, token and one Web API search, without playing — `spotify_check.txt` |
| `musicmix` | The session options while the microphone records: mixes, does not duck — `music_mix.txt` |

## Text messages

`send_message` becomes `SendRoute.message(MessageRequest)`; `MessageFlowRunner` finds the recipient through the
shared `ContactLookup` (the same matching as for calls, preferring the mobile number) and hands the text to a
`MessageSending`.

| Way | When | Sends without a tap |
|---|---|---|
| `ComposeMessageSender` (`MFMessageComposeViewController`) | always, the only way with a free Apple ID; needs GwenMobile in the foreground | no — Apple lets only the person send |
| `CarrierMessageSender` (`TelephonyMessagingKit`, `TelephonyMessagingSession.shared.smsService`) | iOS 26+, `com.apple.developer.carrier-messaging-app`, GwenMobile chosen as default carrier messaging app | yes |

- `GWEN_MESSAGING = YES` in `Config/Signing.xcconfig` signs in `Config/CarrierMessaging.entitlements` (or
  `Config/DialerAndMessaging.entitlements` together with `GWEN_DIALER = YES`) and sets `GwenCarrierMessaging` in
  `Info.plist`, which `MessagingChoice` reads. Xcode's capability list grants the entitlement to the paid Apple
  Developer Program only, and Apple requires an account registered in the EU and a device in the EU. According to
  Apple the app then also serves incoming SMS, MMS and RCS.
- The direct way is only replaced by the form when it is not set up (`unavailable`), never after a failure, so a
  message can never leave twice.
- Language guard (`MessageLanguageCheck`, one of the router's `DecisionConfirming` checks next to the place check):
  the model translated English messages into German in 3 of 6 measured runs while the tool carried German examples.
  With English examples it kept the language, and the device now compares the language of the user's sentence and of
  the message text (`NaturalLanguage`): on a clear mismatch the router is asked once more, naming the language; a text
  that still differs is marked `needsReview` and always goes through the Messages form, even when direct sending is
  set up. Measured afterwards: 36 of 36 English and German messages kept their language (`smslanguage`). `TelephonyMessagingKit` is weak-linked; the Mac build never uses it.
- **No probe sends anything:** every probe run swaps a `ProbeMessenger` into the `MessageDesk`. The text of a
  message never appears in the trace, only its length.

| Probe | What it measures |
|---|---|
| `smsroute` | Real router: message wishes become `send_message` with recipient and text; questions about SMS, other texts, calls, music and the time stay what they were — `sms_route.txt` |
| `smsflow` | Whole chat flow with fixture contacts and the recording sender — `sms_flow.txt` |
| `smscheck` | Build flag, direct way, whether the form can send on this device, and the probe lock — `sms_check.txt` |
| `smslanguage` | English and German messages, three rounds each, through the whole router: does the text keep its language — `sms_language.txt` |

## Research answers

`WebSearch.makeAnswerRequest` takes an `AnswerLength`. It is `.compact` (at most 150 words) unless the router's
`search_web` call sets `detail: true` - the model decides that when the latest user message asks to go deeper into
an earlier research answer instead of naming a new topic. `ToolRouter.map` turns the argument into
`ToolDecision.detailWish`, and `AnswerLengthPlan.fitting(history, detailWish:)` serves that wish: `AnswerItems`
counts the list lines of the previous
answer (`- `, `* `, `• `, `1. `, `1) `), and `AnswerLength.detailed(items:)` allows 80 words per item, clamped to
300–700; `Prompt.Research.answerLength` asks for one list point per earlier item in the same order and forbids
padding a point the sources say nothing new about. The `WEBANTWORT` trace line carries `länge=`, `detail=` and
`punkte=`.

- `ConversationTranscript` — the conversation seen by the router, the follow-up rewrite (`FollowUpResolver`), the
  research answer, the price round and the calendar planner — holds the last six messages, each cut to 400
  characters except the latest answer, which keeps up to 6,000, so a "more on each of them" rewrite sees every item.
- The follow-up rewrite is a forced `resolve_search_query` tool call: `FollowUpResolver.resolvedQuery` reads
  `status` and `query` from the call, and an unresolved or missing call leaves the user's question unchanged. The
  image-prompt writer works the same way with `compose_image_prompt` and `ImagePromptComposer.prompt`; the network
  translation uses `report_translation` and `ModelTranslation.translation`. No refusal or label word lists are
  compared in the app for these steps.
- Every forced tool call (`tool_choice: required`) goes out with `thinkingOffDirective`. With thinking on, a reasoning
  model spends the small `max_tokens` of these steps on its reasoning, and the answer ends with
  `finish_reason: length`, without text and without a call. `toolprobe` sends every variant with the directive of the
  app and `WAHL_required_mit_denken` once without it, and reports `ende=` and `denken_zeichen=`.
- The length only applies to researched answers (`runWebSearch`); only the router's `search_web` step can mark the
  wish as `detail`, so a chat answer that only replies `[[SEARCH]]` stays compact, and a follow-up the chat model
  answers from the conversation keeps the chat prompt.
- A chat or code step of a message the wish splitter cut into several wishes answers only its own wish:
  `WishRouting.answerFocus` adds `wish_answer` to the system prompt, which lists the wishes and tells the model that
  the others run in their own steps and never justify a web search. When such a step still replies `[[SEARCH]]`, the
  follow-up rewrite and the research use that wish, not the whole message, and a picture on the request is always
  named through `resolve_search_query`, also on the first message, so "what device is in the photo?" never goes
  into the search engine as it stands.
- Every router counts relative days with the same rule (`router_relative_days`, in the main router and in the
  calendar planner): tomorrow +1, the day after tomorrow +2, the day after the day after tomorrow +3, and every
  further "after" one more day, also where a language joins these words into one. The app matches no day word.

`gatherWebHits` assembles the sources before the answer model runs: `WebResearch` searches and fetches the pages,
then `ToolRouter.keptSources` asks the router model which of them address the question. The router sometimes drops
a place from its search text (for example it may search only "aktuelle nachrichten" for a question that names a
place or a subject), the fetched pages then do not fit, and the filter keeps none. Because an empty selection
used to fail the whole research with `web_no_results`, `WebSourceGathering` repeats the research once with the
user's own words as the search text and filters again; only when both attempts keep nothing does `runWebSearch`
report "no usable results".

### Source check

The citation check is optional. `ResearchSettings.verifySources` (Settings → AI & models → Research, key
`researchVerifySources`, default off) lets `runWebSearch` commit the researched answer right after the stream and
then hand a background task the `AnswerPlacement` of exactly that message: on, the answer stands immediately, the
bubble shows `web_check_sources` under the sources while the check runs, and the review lands later in the same
message through `ChatStore.updateSourceReview` (in a chain the carried piece is updated and flushed, so a later
step cannot lose it). Because the check no longer blocks the run, further questions can be sent while it runs;
`sourceChecks` holds one message ID per open check, so several reviews can be in flight at once and each one only
touches its own answer. Off, the check does not run at all. When it runs, `reviewSources` analyses the answer on
the device first (`SourceReview.analyze`, and stops without a model call when no statement carries a source
number) and then asks the answering model once for one verdict per cited statement. That extra call carries the
answer and only the cited sources; it runs in the background and does not delay the answer.

Before the answer is written, `SourceSimilarity` compares the fetched page texts on the device: it normalises the
text, builds 5-word shingles and groups pages whose Jaccard similarity reaches `duplicateThreshold` (0.4); texts
under 12 words are never called copies. `clusters` finds text copies, `independentGroups` additionally treats pages
of one website as one publisher, and `originNumber`/`originAssignment` map a source index to its origin.
`SourceReview.analyze` stores `sourceDomains` and `sourceGroups` and counts the cited claims, cited sources and
cited origins; the copy note (`web_source_meta.duplicate`) and the single-origin note
(`research_source_note.single_origin`) travel inside the source blocks, so both the answer model and the citation
checker see them. `SourceReview` decodes with `LenientFields`, so stored answers from before the source check still
load.

`SourceMetadata.from(html:)` builds the check line from what the page itself declares: date and author from the
structured data and meta tags, the page types, imprint and paid links. It parses every `application/ld+json` block
and takes the `@type` of its top-level entities — also inside an `@graph` and as a list — and falls back to
`og:type`; the names are passed through unchanged (only length and character shape are checked), so no list of
accepted kinds sits in the app. The answer model reads the declared types in the check line and judges them
itself.

`SourceVerifier` asks per cited statement for `verdict` (`supported`, `unsupported`, `contradicted`) and
`contradicts`; the `research_verify` prompt asks for the statement copied word for word, forbids entries for
statements without a source number and rules that a statement which reports a missing detail (for example a source
without a date) is supported when the source block really lacks it. `applying` stores the verdicts as `results`
and fills `unsupported` and `contradicted`, but keeps only verdicts that carry at least one source number, so
statements without a citation never inflate the warning count. An unknown verdict
string becomes `.unknown` and is skipped instead of dropping the whole check. `SourceReview.warnings` keeps only
the statements that are not fully backed. The UI draws three parts under the sources: `SourceReviewLine` (the
summary, red for contradictions), `SourceNetworkView` (origins and their copies, only when copies exist) and
`SourceClaimListView` (the warning-only report).

`SourceReview.marks(in:)` finds every warning statement in the answer text: it splits the answer into the cited
sentences and list items (`citedSpans`), matches a warning word for word or by word overlap (`matchOverlap`), never
uses a sentence twice and returns the ranges. Inside a multi-sentence list item it narrows the range to the
sentence that matches the named statement (`sentenceMatch`/`sentenceSpans`) and falls back to the whole item when
the statement spans sentences. `Bubble.markedAnswer` tints those ranges and appends a warning sign
(an orange triangle for *unsupported*, a red cross for *contradicted*, both text glyphs with a variation selector)
that links to `gwen-claim://<result index>`; the bubble's `answerOpener` opens the verdict and its cited sources
as an alert. The rendered bubble caches its attributed text, so the review signature is part of the cache key.

| Probe | What it measures |
|---|---|
| `detailfollowup` | Asks for the news from Berlin, then "bitte je Meldung mehr Information dazu": route, chosen length, transcript size and whether it carries the whole previous answer, words, list points and sources of both answers — `detail_followup.txt` (measured: search both times, 131 → 232 words, 4 → 4 points, length 320) |
| `sourcetrust` | The whole source check on the device: local gate, metadata dossier, reports, syndication of one agency text (origins, copies, duplicate note in the prompt), contradiction verdicts and a live research with its review — `source_trust.txt` |
| `sourcecheckbg` | The background check: deterministic placements (direct, chain, two messages) plus a live research where a second question goes out while the first review still runs — both answers must keep their IDs and texts and receive their own review — `source_check_bg.txt` |
| `sourceretry` | Simulates the empty source filter for a shortened query ("aktuelle nachrichten") and proves the retry with the user's own words ("Aktuelle Nachrichten aus Berlin") finds and keeps the sources — `source_retry.txt` |
| `citationreview` | The citation review output: drops an uncited verdict, marks only the warned sentence inside a multi-sentence list item, and asks the real verifier prompt whether a "source gives no date" statement is handled as supported — `citation_review.txt` |

## Time and date

`tell_time` becomes `SendRoute.clock(ClockRequest)` with an IANA `timeZone` and a `place`; a time zone the device
does not know, or a place without a time zone, turns the step into a chat answer. `ClockAnswer` renders the device
clock in that zone (or the device's own) in the app language — no network and no model between the clock and the
answer. `SystemPrompt` also hands every chat request the current date, the local time and the time zone identifier,
so date arithmetic stays an answer.

| Probe | What it measures |
|---|---|
| `clockroute` | Real router: questions for the time, date and weekday become `tell_time` with the right time zone, date arithmetic and reminders do not — `clock_route.txt` |
| `clockflow` | Whole chat flow: the answer carries the minute of the device clock, here and in Tokyo — `clock_flow.txt` |

## Reminders, shopping lists and timers

`plan_reminder` becomes `SendRoute.reminder(ReminderRequest)`; `ReminderFlowRunner` resolves the list
(`ReminderListChoice`, the same title matching as the calendar) and the existing reminder (`ReminderMatching`),
and `EventKitReminderStore` performs the action on the device: `EKReminder` with `dueDateComponents`,
`EKRecurrenceRule` for repetitions and an `EKAlarm` with an `EKStructuredLocation` for a place, whose
coordinates come from `ReminderPlaceLookupChain`: `NearbyReminderPlaceLookup` finds the nearest real match
through the Places search (`LivePlaceSearch`, Apple Maps - the next post office, the next REWE), 
`CoreLocationPlaceLookup` (`CLGeocoder`) covers cities and addresses, and `ReminderPlaceRadius` clamps the
region (150 m for a shop, up to 10 km for a city). `ReminderDesk` holds both for `ChatView`.

- The model fills the tool with title, list, `due` (local `YYYY-MM-DD HH:MM` or a day alone), `minutes` or
`seconds` for a timer, `repeat`/`repeatInterval`, `priority`, `location`/`proximity`, `notes` and `find`; the app
converts minutes or seconds into `now + …` and defaults a timer without a title to "Timer". `SendPlan.forming`
joins reminder
creates that share the same place, due time, list, repetition and priority into one reminder (`ReminderTitle`),
so one place visit never produces one notification per article.
- The list comes only from the model's tool call: `ReminderListChoice` maps the requested name onto the real list
titles, reports an unknown name and falls back to the default list when the model names none. The app never
searches the sentence for list or calendar names itself — the router decides.
- A wish answered with both a calendar appointment and a reminder goes back to the router once:
`AppointmentReminderCheck` spots the pair among the decisions of one wish (different wishes stay untouched) and
re-asks with the rule that a due time without an end is a reminder and a start with an end keeps its notifications
in `alerts`; what the model then chooses is kept, so the app matches no keyword. If the re-ask cannot be reached,
the original calls stay.
- The tool description takes reminders, to-dos, shopping items, timers and "when I am there" wishes away from
`plan_calendar`, which now creates appointments with a start and an end only.
- **No probe touches your own reminders:** every probe run swaps a `ProbeReminderStore` (and a fixture place
lookup) into the `ReminderDesk` and removes the conversations it ran in afterwards; `reminderlists` only reads
and creates the default list when the device has none; `reminderlive` creates its own test reminder and deletes
it again. The unit tests use their own recorder.

| Probe | What it measures |
|---|---|
| `reminderroute` | Real router: reminder, shopping and place wishes become `plan_reminder` with the right action and fields; an appointment stays `plan_calendar`, the time stays `tell_time`, a timer stays `set_timer` — `reminder_route.txt` |
| `reminderflow` | Whole chat flow with the recording store: which reminder, list and place would have been written; the probe deletes the conversations it ran in afterwards — `reminder_flow.txt` |
| `reminderlive` | The real store on the device: creates its own test reminder, reads it back and deletes it again — `reminder_live.txt` |
| `reminderdecode` | Fixed tool calls through decoding, request mapping and flow runner without a provider: create, two items, place, timer, complete, update, delete, list — `reminder_decode.txt` |
| `reminderlists` | Reminders access, how many lists, open reminders, dates and places the device holds, and — when no list exists at all — it creates the default one (the same repair the first reminder does); no reminder is written — `reminder_lists.txt` |

## Timers

`set_timer` becomes `SendRoute.timer(TimerRequest)`; `TimerDesk` holds a `TimerSetting` for `ChatView`.
`SystemTimerSetter` schedules an AlarmKit timer (`AlarmManager.schedule` with `.timer`, iOS 26+, needs
`NSAlarmKitUsageDescription` and the user's alarm permission) and falls back to a local `UNUserNotification`
with a time-interval trigger on older iOS; `cancel(handle:)` removes either again. The model fills only
`minutes`, `seconds` and an optional title — every reminder wish stays `plan_reminder`, so the app never has to
read the sentence.

| Probe | What it measures |
|---|---|
| `timerroute` | Real router: explicit timer wishes become `set_timer` with the right duration; "remind me in ten minutes", the time and an appointment stay with their own tools — `timer_route.txt` |
| `timerflow` | Whole chat flow with a recording setter: which timer with which duration would have been started, and that a reminder wish never reaches it — `timer_flow.txt` |
| `timerlive` | The real timer on the device: schedules its own 8-second timer and cancels it again — `timer_live.txt` |

## Places and routes

`find_nearby_place` and `route_to_place` become `SendRoute.nearbyPlace` and `SendRoute.routeToPlace`; `PlaceFlowRunner`
searches through `LivePlaceSearch` (MapKit, Apple Maps, no key, no quota) and the answer carries the hits as chips.
A chip goes through `ChatView.openRoute(to:)` into the `RouteDesk`: `RouteHitRegistry` resolves the recorded place
(with its distance and travel mode) and hands it to the opener, `AppleMapsOpener` gives it to `MKMapItem.openInMaps`
with the travel mode and falls back to the `maps.apple.com` URL.

- **No probe opens Maps:** every `gwenmobile://test/<scenario>` run swaps a `ProbeRouteOpener` into the `RouteDesk`
and restores the live opener afterwards (the same way `ProbeDialer`, `ProbeMusic` and `ProbeMessenger` stand in).
It records the target, the mode and the `maps.apple.com` URL and only checks `UIApplication.canOpenURL` instead of
launching Maps, so a batch never waits behind Apple Maps in the foreground.

| Probe | What it measures |
|---|---|
| `mapnearby` | The real nearby search (REWE, around the current location) and the chip hand-off through the desk: hit count, the first place with distance and mode, the hand-off target and the openable `maps.apple.com` URL — `map_mode.txt` |
| `mapplace` | The same hand-off for a route searched by name (REWE, no location) — `map_mode.txt` |

## Personal memory

`remember_fact` becomes `SendRoute.memory(MemoryRequest)`; the `MemoryStore` actor keeps the entries in
`Library/Application Support/memory.json` with file protection. Nothing in the app reads a meaning out of the
sentence: the router decides the action — `create` for a fact the user explicitly wants kept, `suggest` for one they
only stated in passing (the app asks before storing), `forget` with a catalog key, `list` — writes the fact as one
timeless sentence, turns relative time into an absolute `date` and may set `intervalMonths` for a routine check-up;
the store derives the due date and the app labels it as a rule of thumb, never as medical advice.

Every router call carries a compact MEMORY CATALOG from `MemoryStore.catalog()` (pinned first, then most recently
used, `[#key]` per entry); `answer_in_chat` copies the keys whose facts help into its `memory` field. Only those
entries reach the answering model, as a PERSONAL MEMORY block from `MemoryStore.block(keys:)`; the answer carries
them as chips (`ChatMessage.memoryRefs`) and `markUsed` counts the use. Due reminders are checked when the app comes
to the foreground and only become a local notification after the user switched *Reminder for the due date* on for
that entry (`MemoryNotifier`). Settings → Memory & data → *Memory* holds the master switch, suggestions, chips, retention and the
*About me* list (`MemoryView`), which edits the same store.

| Probe | What it measures |
|---|---|
| `memoryroute` | Fixed tool calls through decoding: create, suggest, forget, list, a broken call, the chosen answer keys, the plan shape and the catalog inside the system block — `memory_route.txt` |
| `memorystore` | A temporary store on the device: persistence, due date and reminder, block, catalog, unknown keys, usage counter and delete — `memory_store.txt` |

## Deleting the history by voice

`delete_history` becomes `SendRoute.history`, with no parameters: one call deletes every saved conversation and the
one that is open right now. `HistoryCleaner.deleteAllConversations()` does it through the same path as the history
list — the fresh empty conversation comes from `ChatStore.removeAllConversations()`, and the deletion can be undone
for 5 seconds from the bar above the chat input. The app matches no signal word: Settings → Voice & speech → Voice control lets the
user set a delete-history phrase, and it only travels into the router prompt as a hint
(`ToolRouter.systemBlock(..., eraseHistoryWord:)`).

| Probe | What it measures |
|---|---|
| `historyroute` | Fixed calls through decoding: the tool maps onto the history route, a provided scope is ignored, the configured phrase reaches the system block and the phrase is no local spoken command — `history_route.txt` |

## Weather

`tell_weather` becomes `SendRoute.weather(WeatherRequest)`; the model fills only `place` (the user's own words,
empty for here) and the day: `date` as the absolute `YYYY-MM-DD`, computed from the current date, for every named
day, relative or fixed (a weekday, "12. Oktober"); `dayOffset` as whole days from today (heute 0, morgen 1,
übermorgen 2, überübermorgen 3, "in four days" 4) is filled next to it as the cross-check; `day`
(today/tomorrow/dayAfter) is only the fallback when no day is named. `date` wins, and the app derives the offset
from it and logs when the two disagree, so the whole app works on one calendar day and an absurd model `dayOffset`
is bounded to ±366 days; `WeatherDayCheck` asks the router once more when neither `date` nor `dayOffset` was filled,
and also when `date` lies a different number of days ahead than `dayOffset` says (`check_weather_day_conflict`
names both values); the renewed call only replaces the first one when it names a day. The card builds its tabs from `WeatherDayTabs`: today, the asked day and the day after it (three
consecutive near days otherwise), and the answer text names the real date through `WeatherAnswers.dayTitle`, so the
read-aloud speaks the asked day and not always "tomorrow". `WeatherService` resolves the place through
Open-Meteo geocoding or `LocationFix` for "here"; if Open-Meteo finds nothing, `CLGeocoder` and `MKLocalSearch`
correct the spelling ("Buxdehude" becomes "Buxtehude", which the answer names) before it fetches
the forecast
(`hourly=temperature_2m,precipitation_probability,precipitation,wind_speed_10m,wind_gusts_10m,uv_index,weather_code`,
`timezone=auto`, `start_date`/`end_date`) and keeps the hours 6–22 in a `WeatherRef` on the chat message, so the
card also renders from the history. `WeatherAdviceRules` turns the values into the advice block with fixed
thresholds and time windows: severe weather (thunderstorm codes, gusts ≥ 90 km/h or rain ≥ 25 mm), wind ≥ 60 km/h,
heat ≥ 30 °C, and sun protection from UV index 3 with the window and intensity (3–5, 6–7, 8+) — never from the
temperature. Rain arrives in two steps, always with the hours it applies to: the umbrella from a probability ≥ 40 %
or ≥ 1 mm expected rain with ≥ 30 %, and otherwise a softer "Regen möglich" from ≥ 25 % or ≥ 0.3 mm; a dry day
with 0 % and no expected rain gets no rain advice at all. The UV thresholds follow the official index: uv-index.de (BfS/DWD/UBA) marks 0–2 as "keine bis gering /
nicht erforderlich" and 3–5 as "mittel / erforderlich", 8–10 as "sehr hoch / unbedingt erforderlich"; the US EPA
scale names 1–2 "No protection needed" and 3–7 "Protection needed". `WeatherAnswers` writes
the answer, which starts with the first advice so the existing read-aloud path speaks the warning. The card in
`WeatherCard` draws curve, bars, tiles and symbols; its day switch refetches through the same service and updates
the message in place, and the export renders with `ImageRenderer` and shares through `Presenter`. The app matches
no keyword: the router decides, the app only fetches and draws.

| Probe | What it measures |
|---|---|
| `weatherroute` | Real router: weather questions become `tell_weather` with the right place and day (also three days ahead in German, English, French and Spanish), "here" stays empty and a clock question keeps its own tool — `weather_route.txt` |
| `weatherdecode` | Fixed forecast JSON through decoding, advice and answer text without the network — `weather_decode.txt` |
| `weatherflow` | The real forecast through `WeatherService` on the device: hours, timezone, advice and answer text for München and Hamburg — `weather_flow.txt` |
| `weatherchat` | The whole chat flow on the device: the real question goes through the router and the forecast service, and the probe checks the `weatherRef` on the answer (place, day, hours, advice, text); it deletes the conversations it ran in afterwards — `weather_chat.txt` |

## Document scanner

`scan_document` becomes `SendRoute.scanDocument(ScanRequest)`; `ScanRequest` carries only `kind` (invoice,
authority, receipt, letter, other) and `remind`, both decided by the router from the user's own words — the app
matches no scan signal word. `DocumentScanner` opens VisionKit's `VNDocumentCameraViewController` right away
(multi-page); on hardware without VisionKit, on the Mac and in the simulator it falls back to the single-shot
`CameraPresenter`. `ScanWorkflow` recognises every page on the device with `TextRecognizing`, renders the pages
into a PDF with `UIGraphicsPDFRenderer`, stores it through the `DocumentStore` and writes the recognised text as
the sidecar. Pages and text are capped like an attached file (`FilePolicy.maxPDFPages`, `maxTextChars`), the
attachment is marked `truncated` when something was left out, and an over-budget block leaves an omission notice in
the context instead of silence (`FileContext`). The unit tests inject the recogniser, so the whole path runs
without a camera.

The scan is attached to the message that asked for it (`ChatStore.attachScan`), so the chat shows the file card
with pages, size and OCR badge. `ChatStore.attachScanRef` copies the same PDF onto the answer as
`ChatMessage.scanRef`, which renders a **Share** button in the bubble (`Presenter.share`, the stored PDF never a
thumbnail). `ScanSaver` additionally copies the PDF into `Documents/Downloads`; `UIFileSharingEnabled` and
`LSSupportsOpeningDocumentsInPlace` are on in `Info.plist`, so the Files app shows it under *On My iPhone →
GwenMobile → Downloads*. That copy stays when the chat is deleted, and `ScanSaver.uniqueURL` appends `-2`, `-3`
instead of overwriting an existing file.

- The second router pass runs with `SendContext(scannedDocument: true)` and the recognised text as a SCANNED
  DOCUMENT block; `ScanPlan.analysisActions` removes every `scan` step — the camera must never reopen — and, when
  the user asked for a reminder, every `reminder` step as well. `ScanAnswers.instruction(for:)` carries the
  kind-specific task into the answering model: invoice summary with amount and due date, authority letter with all
  deadlines and remedies, receipt with every position and a bill check, letter as a summary. A reminder wish
  without its own date, time or place directly behind a scan is absorbed into that scan
  (`SendPlan.absorbingReminderIntoScan`), so even "scan the authority letter and keep the deadline as a reminder"
  lands on the button instead of a half-filled reminder.
- The chat names every waiting phase: `scan_reading` while the device recognises the text and `scan_analyzing`
  while that second router pass runs, so the seconds between the camera and the first answer token are never
  silent; the answer stream then shows the usual processing bubble.
- "Frist als Erinnerung scannen" saves nothing by itself. `ToolRouter.scanReminderRequest` asks the router once
  with only the reminder tool and `tool_choice` forced and reads title and due date out of the recognised text;
  the answer then carries a `ScanReminderOffer` (title, due, list, notes) and renders it as a button. Only the tap
  runs `ReminderFlowRunner` (`ChatView.createScanReminder`) and `ChatStore.settleReminderOffer` swaps the button
  for the usual reminder chip. `ScanReminderOffer` is `Codable`, so the offer survives a relaunch.

The unit tests cover the kind mapping, `ScanPlan`, `ScanReminderOffer` (offer, day-only deadline, store
round-trip) and the PDF plus `Documents/Downloads` path. On the device, three scenarios cover the feature alone.

| Probe | What it measures |
|---|---|
| `scanroute` | Real router: scan wishes in German, English and Spanish become `scan_document` with the right kind and remind flag; questions about documents stay chat — `scan_route.txt` |
| `scanflow` | The real scanner path on the device: VisionKit and camera availability, Vision OCR, the PDF with its page count, the text sidecar and the copy under `Documents/Downloads` — `scan_flow.txt` |
| `scanchat` | The whole post-scan chain on the device: the second router pass keeps the camera closed, the answer lists the receipt positions and checks the bill, the reminder offer appears without an automatic reminder, a simulated tap creates the reminder (and deletes it again), and the answer carries the shareable PDF — `scan_chat.txt` |

## One picture with several changes

Several changes to the same picture belong in one `edit_picture` call: one image shows all of them. The wish
splitter keeps such changes in one wish, and `PictureChainCheck` merges consecutive picture steps into a single
`create_picture` (fresh picture) or `edit_picture` (picture already in the chat) when the router confirms that they
describe one picture. When the user wants results of their own — several pictures, variants, alternatives or one
picture per change — the splitter keeps separate wishes and `PictureChainCheck` keeps the separate calls. Both
decisions come from the router with the whole message and the chain hint (`check_picture_chain.md`); the app matches
no word.

The router only receives the newest picture of the chat (`turn.images.last`); the picture director picks target and
template among all of them afterwards. `router_picture_remembered` therefore tells the router that the picture sent
along is only the newest one and that a wish to change any picture of the chat is `edit_picture`, also when the
newest picture does not show what the wish names. Without that rule, "Übertrage die Farbe des blauen Quadrats auf den
roten Kreis" with a yellow star as the newest picture became `answer_in_chat` and no picture was made.

| Probe | What it measures |
|---|---|
| `picturedit` | The splitter and the chain check with the real model: four changes to one picture become one edit step, four requested variants stay four edit steps — `picture_edit_chain.txt` |
| `picturesteps` | The whole router for both sentences: wish count, chosen steps and the complete instruction of the single edit — `picture_edit_steps.txt` |
| `piceditroute` | The raw router call for change wishes with four pictures in the chat, sent with the newest picture (as the app does), without a picture and with the first one, three rounds each — `picture_edit_route.txt` |

## Price watch

`watch_price` becomes `SendRoute.priceWatch(PriceWatchRequest)`; `PriceWatchStore` (an actor over
`price_watches.json` in Application Support) keeps the watches and `PriceWatchFlowRunner` runs the action. The router
fills the product terms, the target price, an optional country, the interval and a catalog key; the app matches no
word.

- `LivePriceWatchChecker` reuses the price path: `WebPriceLookup` (search, read, one page per shop) fetches the
  sources, and a forced `report_price` tool call reads the cheapest offer for exactly the product out of them
  (`tool_report_price.md`, `Prompt.Price.watch()`); the app compares that number with the goal. The model names the
  **number of the SOURCE** the price comes from - the app takes the address from the page it really fetched, so no
  link can be invented - and it must name the exact configuration (chip, memory size, storage size); when the sources
  only show a different configuration, the call stays away and the watch reports no offer instead of a false hit.
- Two watch wishes the wish splitter cuts out of one sentence for the same product and goal are merged into one watch
  with the union of their terms (`SendPlan.mergingPriceWatches`), so one sentence can never create two watches with
  half a configuration each.
- The router carries a PRICE WATCH CATALOG (`PriceWatchStore.catalog()`, `router_watch_catalog.md`), so update,
  delete and check can name a watch by its key, the same way the memory catalog works.
- `BGAppRefreshTask` (`com.mortis.gwenmobile.pricecheck`; `Info.plist` `BGTaskSchedulerPermittedIdentifiers` plus
  `fetch` in `UIBackgroundModes`) checks the due watches and schedules the next run from `PriceWatchStore.nextDueDate`;
  the app also catches up due watches when it comes to the foreground. `LocalPriceWatchNotifier` posts the local
  notification only when the price reached the goal and only once per price (`notifiedPrice`).
- Settings → Services → *Price watch* (`PriceWatchView`) lists, pauses, checks and deletes watches. The chat card is
  `PriceWatchCardView`, rendered from `ChatMessage.priceWatchRef`.

| Probe | What it measures |
|---|---|
| `pricewatch` | Real router on nine sentences (create, list, check, delete, update, a one-off comparison and a prize question that must stay away from both price tools), the store round-trip on the device (persistence, interval, pause, catalog, delete), the whole chat flow with a live price round and a recorded notification, and the real local notification — `price_watch.txt` |

## Daily briefing

`day_briefing` becomes `SendRoute.dayBriefing(DayBriefingRequest)`; `DayBriefingService` assembles the day out of
`DayBriefingSources` and `DayBriefingCard` draws it from `ChatMessage.dayBriefingRef`. The router fills only the day
(today, tomorrow, dayAfter); the app matches no word.

- The sources are small protocols so probes and tests can stand in for the device: `LiveBriefingCalendar`
  (`CalendarService.events(on:)`), `LiveBriefingReminders` (the same `ReminderStoring` the reminder flow uses),
  `LiveContactDirectory` (birthdays now travel on `ContactCard.birthday`), `LiveBriefingWeather` (the same
  `WeatherService`) and `LiveBriefingTravel`, which fixes the next appointment with a place through `CLGeocoder` and
  reads car and bike times from `MKDirections`. Every source is optional: what fails or is not allowed is left out.
- The card's tabs refetch through `ChatView.switchBriefingDay(message:day:)` and replace the message in place; an
  appointment row opens the existing `CalendarEventView`, **Read aloud** uses the existing `SpeechSynthesizer` and
  **Notification** posts the briefing through `DayBriefingNotifier`.
- `DayBriefingNotifier` keeps one repeating `UNCalendarNotificationTrigger` (`gwen.briefing.daily`) at the time from
  Settings → Services → *Daily briefing*. The content is rebuilt when the app comes to the foreground, at most once a day
  (`briefingRefreshedDay`), and only from calendar and reminders unless location and contacts are already allowed —
  a silent refresh never prompts. The footer toggles switch weather, reminders, birthdays and travel time.

| Probe | What it measures |
|---|---|
| `daybriefing` | Real router on nine sentences (briefing today, summary, tomorrow, the day after tomorrow, and weather, reminder, calendar, price and chat wishes that must stay away from it), the assembly from fixture sources (sections, order, limits, gating, text and notification body), the whole chat flow through the real router with a fixture day, the card's day switch, the read-only live assembly from the device and the real planned and posted notification — `day_briefing.txt` |

## Conversation mode

Conversation mode is the second speech mode next to the wake-word listening mode. `VoiceSettings.conversationMode`
lives in Settings → Voice & speech → *Voice control* and in the waveform button of the chat header; `toggleConversationMode()`
switches the wake-word mode off and read-aloud on. `ListenGate.conversation` lets `mayListen` stay true while a run
is streaming or the read-aloud voice speaks; Settings and the histories still pause it. `ChatView` starts the
session with `VoiceTranscriber.converse(onText:onSpeech:onCancel:)` and
`VoiceTiming.conversation(silence: TimeInterval(settings.voice.dictationSilenceSeconds))`; the configured *Silence
before sending* therefore controls how quickly a recognized utterance becomes the next turn. There is no idle
timeout: the conversation session has no `nothingSaid`/maximum stop, and the mode restarts after each utterance
until the user switches it off, the microphone is lost or the echo protection fails. The optional *Only my voice*
check is described below.

`VoiceTranscriber` reports the first transcript through `onSpeech` only after `confirmsConversationSpeech` accepts
it: at least two words or one word of five letters or more. A single short fragment is ignored; after the
configured silence it is discarded instead of being sent. This threshold came out of the device tests: the
recognizer turned the app's own TTS residue or silence into single words such as "Und", "Ich" and "Bist", which
stopped the answer and sent a nonsense turn. The echo and level probes are `conversation` and
`conversationsilence`; the interruption and the following turn are `conversationbarge` and `conversationturn`.

The configured cancel word is handled before the confirmation threshold: `VoiceTranscriber` checks the capture
against `signals.cancel` on every change, sets `cancelRequested`, calls the `onCancel` closure and delivers nothing.
`ChatView.handleVoiceCancel()` sets `voiceCancelFeedback`, stops the read-aloud voice, cancels chain, send task and
`ChatRunner`, and speaks `conversation_stopped` in the app language. It then waits for the cancelled run
(`settleInterruptedRun(stopSpeech: false)`) and for the feedback to finish before it clears the flag and starts the
conversation session or normal listening again. `voiceCancelFeedback` keeps `followListenGate` from restarting
while the feedback is audible; the cancel word never reaches the input or the model. The same handler serves the
cancel-only session of listening mode. The configured stop word is not a signal in conversation mode; it is treated
like any other utterance.

### Only my voice

Settings → Voice & speech → *Voice control* → *Only my voice* (`VoiceSettings.onlyMyVoice`, default off) enables a local speaker
check for conversation mode. The bundled `WeSpeakerResNet34LM_2s.mlpackage` is a Core ML conversion of
`pyannote/wespeaker-voxceleb-resnet34-LM` (CC BY 4.0); `scripts/speaker_model/convert.py` downloads the checkpoint,
fuses the Kaldi-compatible 80-bin fbank frontend, fixes the input to 2 s / 16 kHz mono and writes the model under
`GwenMobile/Resources/Models/`. The attribution is in `THIRD_PARTY_NOTICES.md` and in the model directory's
`NOTICE.md`; the enrollment screen shows the model license. To regenerate it, create a Python 3.9+ virtual
environment under `build/speaker-model/venv`, install `scripts/speaker_model/requirements.txt` and run
`build/speaker-model/venv/bin/python scripts/speaker_model/convert.py`. The script downloads the public checkpoint
from Hugging Face; no account or token is required.

`SpeakerEmbedder` loads the compiled `mlmodelc` from the app bundle and returns a 256-dimensional L2-normalized
embedding. `SpeakerAudioWindows` normalizes a 2 s window to a 0.25 peak and rejects windows below an RMS floor;
enrollment uses 5 s recordings with 2 s windows and a 1 s hop, runtime uses the last 2 s and a 750 ms analysis
cadence. `SpeakerProfileBuilder` normalizes and caps the enrolled embeddings; `SpeakerProfile` stores up to 16
embeddings with a base threshold of 0.55. `SpeakerSensitivity` moves that threshold by ±0.08 (strict/normal/relaxed).

`SpeakerAwareFeed` wraps the existing `HeldMicrophone` and forwards every PCM buffer to `SpeakerGate.worker` before
the recognizer sees it; no second audio engine tap is opened. `SpeakerGateWorker` converts to 16 kHz mono, keeps an
8 s ring buffer and computes the best cosine score against the enrolled embeddings. Early verdicts use the last
2 s window (`allowed` at threshold + 0.03, `rejected` only after two windows below threshold - 0.08); the final
verdict uses the maximum over the last 4 s. The worker reports on a `UserInitiated` queue and never blocks the audio
tap.

`VoiceTranscriber` keeps `onSpeech`, `onCancel` and the delivery behind the gate: `take()` only sets
`pendingSpeech`/`pendingCancel`, and `resolveSpeakerActions()` fires the callbacks once `SpeakerGate.verdict` is
`allowed`. At silence `requestDelivery()` awaits `finalVerdict()`; a rejected turn calls
`rejectConversationTurn()`, which cancels the session and lets `ChatView.followListenGate()` restart conversation
mode, so the read-aloud answer keeps running and nothing reaches the input or the model. The cancel word uses the
same gate. `ChatView.startConversationListening()` refuses to start when *Only my voice* is on without a profile or
without the bundled model and switches conversation mode off with a notice; there is no permissive fallback.

`SpeakerProfileStore` keeps the profile in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and
`kSecAttrSynchronizable = false`; raw enrollment audio is only held in memory for the 5 s recording and is discarded.
The application privacy text lists the voiceprint as on-device data. Enrollment records three 5 s prompts, checks
the within-recording consistency and the match against earlier recordings, and saves only embeddings.

| Probe | What it measures |
|---|---|
| `speaker` | Loads the bundled model, synthesizes the same sentence with two system voices, builds a profile from the first voice, reports same/different cosine scores and runs the gate against both: the own voice must be allowed, the foreign voice rejected — `speaker.txt` |

`ChatView.userStartedSpeaking()` stops `SpeechSynthesizer`, sets `speechInterrupted` (so a late answer from the old
run is neither spoken nor notified), and cancels the chain, the send task and `ChatRunner`. `settleInterruptedRun()`
waits for the cancelled task, stops a late read-aloud and keeps the partial answer that `finishCancelled` wrote.
`conversationDidHear()` then appends the transcript to the input and starts a new send; `send()` clears
`speechInterrupted` before the new answer. The partial answer is already in the store when the new request is
routed, so it travels into the next turn's history.

Echo protection is `MicrophoneTap.setVoiceProcessing(_:)`: it sets the flag and restarts the running tap when it
changes, and `AudioEngineSetup.start` calls `inputNode.setVoiceProcessingEnabled(true)` before the engine starts.
The mode keeps the normal `.default`/`.measurement` recording setups. A separate `.voiceChat` setup was measured on
the iPhone 16 and caused repeated receiver/speaker route changes and an `AVAudioEngine` tap race
(`required condition is false: nullptr == Tap()`), so the mode uses the normal session with input-node voice
processing. The microphone stays held, so `HeldMicrophone` keeps the tap and read-aloud shares the
`playAndRecord` session. On Mac Catalyst voice processing reports nine input channels; `AudioBufferConversion` maps
the first channel onto the mono target before resampling, because `AVAudioConverter` otherwise produces silence for
that layout. If voice processing cannot be enabled, `startConversationListening` switches the mode off and shows
`conversation_echo_failed`.

| Probe | What it measures |
|---|---|
| `conversation` | Enables conversation mode, speaks a TTS sentence and checks that the recognizer hears none of it; reports the echo protection, transcript and self-interruptions — `conversation_echo.txt` |
| `conversationsilence` | Keeps the conversation session open for 20 s without TTS or speech and reports transcripts and input peaks — `conversation_silence.txt` |
| `conversationbarge` | Plays a long TTS answer and waits for a voice from outside the phone; reports when the interruption fires, whether the TTS stopped, whether the microphone stayed live and whether the echo protection stayed on — `conversation_barge.txt` |
| `conversationturn` | The same interruption, then lets the new turn send; reports the transcribed user sentence, the answer or alert and the message count — `conversation_turn.txt` |
| `conversationcancelword` | Plays a long TTS answer and waits for the configured cancel word; reports whether the cancel was recognized, whether the feedback was spoken, whether the cancel word was sent and that the message count stayed unchanged — `conversation_cancelword.txt` |
| `listencancel` | The same cancel word in listening mode: starts a normal wake-word session, plays a long TTS answer, waits for the cancel-only session and reports whether the word was recognized, whether the feedback was spoken, whether the TTS stopped and that no message was added — `listen_cancelword.txt` |
| `conversationkeep` · `conversationcleanup` | Remove test conversations again: `conversationkeep` keeps the conversation named in `Documents/keep_conversation.txt` and flushes the save, `conversationcleanup` removes the known test markers — `conversation_keep.txt`, `conversation_cleanup.txt` |
| `modeflip` | Switches eight times between listening and conversation mode, each after 1.2 s; reports mode, voice state and echo protection per step — `mode_flip.txt` |

For `conversationcancelword`, `listencancel`, `conversationbarge` and `conversationturn`, `device-test.py` watches the
console for `CANCELWORD_TTS_START`, `LISTENCANCEL_TTS_START`, `BARGE_TTS_START` or `TURN_TTS_START` and plays the
matching phrase through the Mac speakers via macOS `say` and `afplay` after two seconds. The cancel phrase is repeated
three times at four-second intervals;
the barge-in and turn phrases are played once. The phone must be able to hear the Mac speakers. The cancel-word probe
uses the configured word "abbrechen"; the barge-in and turn probes use "Moment, ich habe eine Frage".

Measured on the iPhone 16 (iOS 27.0.1): 20 s of silence produced no trigger; a 42 s TTS answer without a user
spoke did not interrupt itself after the threshold; the external Mac speaker phrase "Moment, ich habe eine Frage"
stopped the TTS after about 3 s and left the microphone live; the new turn was transcribed as "Moment, ich habe eine
Frage ." and sent. The cancel-word probe uses the configured word "abbrechen"; it reports whether the cancel was recognized,
whether the feedback was spoken, whether the cancel word was sent and that the message count stayed unchanged. One
test turn could not get an AI answer because the stored provider key was rejected with HTTP 401; the send path itself
worked.

## Personal Voice

`PersonalVoiceAccess` wraps `AVSpeechSynthesizer.personalVoiceAuthorizationStatus` and
`requestPersonalVoiceAuthorization`; no Info.plist entry or entitlement is required. `VoiceCatalog.options(for:)`
maps every `AVSpeechSynthesisVoice` to a `VoiceOption` with `isPersonal` from
`voiceTraits.contains(.isPersonalVoice)` and keeps personal voices even when their language differs from the app
language; system voices stay filtered by the app language and `sorted` puts personal voices first. The existing
`outputVoice` string stores the voice identifier, so no new settings key or migration is needed. `Settings.language`
does not reset a selected personal voice; `SpeechSynthesizer` resolves it per utterance through
`VoiceCatalog.voice(identifier:language:)` and falls back to the system default if it is unavailable.

`ModelsSettingsView` shows a compact *Personal Voice* row directly above the output voice picker and a detailed
section below it; it shows the status, requests permission, selects the first personal voice after authorization,
previews it and refreshes on `AVSpeechSynthesizer.availableVoicesDidChangeNotification`, on scene activation and
with *Check again*. `loadVoices` reads the list on the main actor, and the debug `voicelist` probe reports the
personal-voice authorization status and the personal trait of every listed voice. The voice must be created by the user in iOS; the app cannot create or import one. Personal
Voice cannot be exercised in the simulator (`.unsupported`), so verify it on a device with a created voice. Apple
supports English (U.S.), Mandarin Chinese (China mainland) and Spanish (Mexico) at the time of writing, not German;
the UI shows a language hint when the voice language differs from the app language.

## Parallel wishes

`SendPlan.forming` keeps the wishes in the user's order; the wish splitter additionally names the wishes that
need nothing an earlier wish of the same message finds, says or makes (`{"wishes": […], "independent": [1, 2]}`,
one-based; an unreadable or missing list means no wish is independent). `WishRouting.routed` carries that onto the
decision as `ToolDecision.standalone`, and the later confirmation calls copy the flag onto what they return.

`ChainSchedule.stages` turns the plan into stages: a step may run beside another only when it is `standalone`
and its kind is pure network or device-local work (`chat`, `search`, `gallery`, `code`, `weather`, `clock`,
`price`, `briefing`, `status`, `create` and a `translate` that does not translate the chat). Such steps are
collected into the first stages of their run — in the user's order, `inFlight` at a time — and the barriers follow
one per stage. An independent picture therefore runs beside a create-and-edit chain instead of behind it, and the
ordered gate below still keeps every bubble in the user's order. `history` closes the run, because it replaces the
conversation the later answers belong to (`.history` is the only cut; other barriers do not stop the independent
steps). `ImageDelivery` repeats an image call that the provider throttles (`RateLimitRetry` attempts) so a burst of
three is not cut short. Everything else — an appointment, reminder, timer, scan, call, message, music, route,
read-aloud, the history, memory, price watch and every picture change (`edit`, it can take up a picture of the same
message) — is a barrier of its own. `runsConcurrently` states that rule in one
place, `inFlight` caps a stage at three (a local model gets one step at a time, `ChatView.chainParallelSteps`) and
`stagger` spreads the starts by 350 ms like the routing already does.

`ChatView.run` walks the stages: it builds one `RoutedSend` per stage from the carry so far, hands the steps to
`ChainStageJob` (a `@MainActor` job that survives the sendable-task boundary) and waits for the whole stage before
the next one starts, so a barrier always sees every earlier result. `ChainMessageWriter` keeps the visible order
nevertheless: `commit(step:_:)` queues a step's writes, `finish(step:)` releases them and `close(upTo:)` does the
same for a stopped chain. A later wish that finishes first therefore waits for the earlier one, and a step that
writes nothing blocks nobody. A picture is the exception: `finishAnswer(…, preview: true)` shows it through
`ChainMessageWriter.showNow` the moment it exists and keeps it in `arrived` until the ordered write puts it into the
carry (`forget(step:)` drops the preview then, so it never appears twice). The bubble therefore grows while the
chain still runs, and only the order inside it is decided when the step's turn comes. Pieces carry their step
(`AnswerPiece.step`), so a source check finds its piece by the wish it belongs to
(`AnswerCarry.setSourceReview(_:forStep:)`) and `AnswerPlacement` hands its message id out as soon as the write
really happened (`resolvedMessageID()`).

Two view-side boards keep the flow readable while two steps run: `StreamLease` lets the first streaming step own
the visible answer text and counts the others as busy without writing into it, and `StatusLedger` shows the label
of the earliest step that is still working. `ChatRunner.cancelAll()` cancels every live stream, so the stop button
still ends a whole parallel stage.

| Test | What it covers |
|---|---|
| `ChainScheduleTests` | which kinds run beside another, the stages with barriers and the limits |
| `WishIndependenceTests` | the `independent` list from the splitter and the flag on the decision |
| `ChainGateTests` | the ordered gate, the early picture preview and its single appearance, step-addressed pieces and placements, the two boards, `cancelAll` |
| `ChainParallelTests` | the faster wish waiting for the earlier one, a finished picture already in the bubble while the chain still runs, no cross-reading between independent wishes, the dependent wish still reading its predecessor, the local limit |

| Probe | What it measures |
|---|---|
| `chainparallel` | The whole path on the device: the real splitter marks two unrelated wishes as independent (2 wishes, `unabhaengig=2`), both run in one stage, the fast app-status answer still lands behind the slow model answer, three chat wishes take 7.2 s one after another but 3.4 s together, three pictures take 34.6 s while one alone takes 32.5 s (all three requests overlap), a create → edit chain with one independent picture runs the independent one beside the chain (`stufen=[2, 1]`) and shows both ready pictures at 32 s while the change lands at 48 s (`ankunft=[32493, 32812, 48475]`), and cancelling a parallel stage ends all three streams without an error bubble — `chain_parallel.txt` |

## Stopping a run

The send button becomes the stop button whenever something runs (`ChatView.stoppable`: streaming, dictation, a chain
or a live `runTask`). `ChatView.stopRun()` requests the chain stop, cancels the send task, cancels `ChatRunner` and
aborts dictation. The cancelled task lets every awaited network call fail, `RunStop.isCancellation` recognises the
cancellation (a `CancellationError`, `URLError.cancelled` or any error inside an already cancelled task), and the
guards in `appendAnswerFailure` and `appendModelFailure` keep a stopped flow from writing an error bubble. What a
flow already produced is never thrown away: a streamed answer stays as the answer (without a warning; if the stream
already finished just before the stop, the finished answer stays too), while a price lookup or a picture generation
that had no result ends without one. `startSend()` and `sendNow()` own the task, so every entry point - input field,
voice, dropped file - can be stopped the same way. Conversation mode uses the same cancellation path from a
different trigger: `ChatView.userStartedSpeaking()` stops the read-aloud voice, cancels the chain, the send task and
`ChatRunner`, and `settleInterruptedRun()` waits for the task before the new turn is sent. Listening mode uses the
same cancellation path through a cancel-only session: while `ListenGate.mayCancel` is true (a run is active or the
read-aloud voice speaks), `ChatView.startListening(forCancel: true)` starts `VoiceTranscriber.listenForCancel`, which
ignores every other word and ends on `signals.cancel`; the callback is `ChatView.handleVoiceCancel()`.

| Probe | What it measures |
|---|---|
| `cancelrun` | Starts a real price search, a real picture generation and a real stream, waits for each phase, taps stop and measures how fast the run is idle again, that no error bubble and no picture appear and that nothing keeps running — `cancel_run.txt` |

## Notes

- Default base URL: `https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1`. Reference models:
  `qwen3.8-flash` (chat and routing), `qwen3.8-max` (vision), `wan2.7-image` (images).
- All API errors run through one translator: an app-language message plus the raw code as a detail line (an error
  that arrives framed as an SSE `data:` line is unwrapped before it is read, so the bubble never shows transport
  text); key and model errors add "Open Settings", and simultaneous failures stack into one alert each.
- Camera and calendar permissions only work on real devices, generated image URLs expire after about 24 h, and
  nothing heavy runs on the main actor (`Offload.run`).
- Listening in the background relies on `UIBackgroundModes` → `audio` in `Info.plist` and on never stopping the
  microphone between two requests: `HeldMicrophone` keeps one `MicrophoneTap` running while the mode is on, each
  recognition session only attaches to it, and read-aloud answers play through the same `playAndRecord` session.
  A fresh microphone start from the background fails (measured: `AVAudioSession` error `'what'`), so `ListenGate`
  only listens in the background while the held microphone is live. The `backgroundlisten` probe switches
  listening mode on and reports microphone hold, session and buffer flow in the foreground and, after you switch to
  another app or lock the screen, the refused fresh microphone start in `background_listen.txt`. It speaks nothing
  itself: the app's own speech is no reliable input for its recogniser, because a connected headset routes the
  audio away from the microphone and room audio drowns it out.
- The recording session comes from `RecordingSetup.preferred`: from iOS 26 (not on the Mac) mode `.default` with
  `.bluetoothHighQualityRecording` — the SDK allows that option only in the default mode — then `.measurement` as the
  fallback; both allow `.allowBluetoothHFP`, so AirPods are the microphone when connected. Every microphone start
  and every route change writes `MIKRO weg …` into the trace: input and output port, and for Bluetooth microphones
  `qualitaet=voll|moeglich|keine`. The `listenroute` probe speaks nothing itself: it switches listening mode on for
  five minutes and records route, wake words and requests in `listen_route.txt` while you talk — for tests with a
  headset away from the iPhone.
- When the audio hardware changes while the microphone is held (a headset connects or leaves, another device takes
  the AirPods, the codec renegotiates), iOS stops the engine and keeps the old tap format on the input node's output
  bus. `MicrophoneTap.reconnect()` therefore reinstalls the tap with `inputFormat(forBus: 0)` — the hardware format —
  and does not touch the audio session; only the end of an interruption re-activates it (`resume()`). Reading
  `outputFormat(forBus: 0)` there crashed with `Failed to create tap due to format mismatch`. The `routeswitch`
  probe switches the input between the iPhone microphone and a connected headset three times while listening and
  reports sample rate, buffers and state per step in `route_switch.txt`.
- While the microphone is held, every restart with `.allowBluetoothHFP` lets iOS pick the AirPods again — even when
  the Mac has just taken them, so they bounced back every few seconds. `HeadsetHandover` therefore releases
  Bluetooth once a headset leaves the route (`oldDeviceUnavailable`): preferred input iPhone microphone and output
  overridden to the speaker; the preferred input alone keeps the AirPods busy as output (measured with the
  `routeyield` probe, which also shows that a category without Bluetooth hides the headsets from
  `availableInputs`). The decision is `HeadsetHandoverPolicy`. A headset that went to another device stays listed
  in `availableInputs` (measured), so iOS reporting it again says nothing: measured on the iPhone, every
  `newDeviceAvailable` while the AirPods were running on the Mac made the iPhone grab them back. The release
  therefore only ends when the headset was absent from `availableInputs` in between and comes back — a real
  disconnect and reconnect, like AirPods that go into the case and come out again — and iOS reports the new device
  or routes to it. The released headset is then set as the preferred input, so a second connected headset such as
  other Bluetooth headphones does not win; while only the released headset is pushed away, another headset that iOS
  routes to is left alone. The trace marks it as `MIKRO headset freigegeben` /
  `MIKRO headset zurueck bevorzugt=…`; every `MIKRO wegwechsel` line lists `vorher=[…]` and `verfuegbar=`, and
  `MIKRO pegel spitze_db=` reports the loudest input level every 10 s (−120 means digital silence). Right after the
  meter, `SpeechLevelBoost` lifts quiet buffers towards half scale (at most twelve times, room noise below −54 dBFS
  stays untouched) before they reach the recognizer, so the wake word also triggers at quieter speech. The
  `voicequiet` probe synthesizes the wake sentence, scales it down to 50, 20, 8 and 3 % and reports wake word and
  request with and without the boost in `voice_quiet.txt`.
- Recognition starts fresh after a device change or a return to the foreground: every successful recovery of the
  held microphone bumps `HeldMicrophone.engineRecoveries`, and `ChatView` answers it (and the `scenePhase` change to
  `.active`) with `VoiceTranscriber.restartListening()`, which cancels the waiting session and listens again with the
  current input format. Measured on the iPhone: without this restart a session that survived a switch from a
  Bluetooth headset to the built-in microphone kept metering loud speech but delivered no recognition result for
  minutes, so the wake word never fired.
- The listening-off word works like the new-chat word: `VoiceCommand.command` returns `.stopListening` when the whole
  request after the wake word is one of its variants, and `ChatView` switches listening mode off, which releases the
  held microphone. The `voiceoff` probe lets the iPhone speak every default variant in German and English through the
  real recognizer (measured 7 of 7, plus a decoy per language that must not switch off); it showed that the English
  recognizer turns "Zuhören beenden" into "Zahar and Beenden", so that variant is German only. The `voiceoffflow`
  probe switches the mode on, sends the command and reports mode, recognizer and microphone, then restores your
  setting.
- Reading answers aloud is switched through the tool router as well: `set_read_aloud` becomes
  `SendRoute.readAloud(ReadAloudRequest)` and flips `AppSettings.speakAnswers`, so no command word lives in the
  code; `read_answer` becomes `SendRoute.readAnswer` and has `ChatView` speak the last assistant message once via
  `SpeechSynthesizer`, without touching the setting. `readaloudroute` measures both tools, `readaloudflow`
  switches the real setting, asks for the previous answer, hears `SpeechSynthesizer.isSpeaking` and restores the
  setting afterwards.
- The two cue tones are `ChimePlayer` tones unless Settings names a system sound: `SystemSoundCatalog` lists the
  first readable folder of `/System/Library/Audio/UISounds` (iPhone) and `/System/Library/Sounds` (Mac), and
  `ChosenCue` plays the chosen file and falls back to the tone when it does not play. The `soundcatalog` probe
  reports whether the system sound folders are readable on the device, how many sounds the catalog lists and whether
  each of them loads — `sound_catalog.txt`.
- Siri phrases come from `ListenIntent.swift` (App Shortcuts) with the German variants in
  `GwenMobile/de.lproj/AppShortcuts.strings`; the alternative app name "Gwen" is the `INAlternativeAppNames` entry in
  `Info.plist`.
