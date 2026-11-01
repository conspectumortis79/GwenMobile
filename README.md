# GwenMobile

A personal AI assistant for iPhone, iPad and Mac that does the work instead of only answering: it researches the web,
draws and edits pictures, creates videos, compares prices, books appointments, finds places, reads your files and
videos and listens to your voice — including a conversation mode that needs no wake word, stops speaking when you
interrupt and can be locked to your own voice — all from one chat box, with your own AI provider and no account,
server or subscription behind it.

- [Installation, step by step](#installation-step-by-step)
- [The 7-day limit of a free Apple ID](#the-7-day-limit-of-a-free-apple-id)
- [What you can do with it](#what-you-can-do-with-it)
- [How it works](#how-it-works)
- [What you need](#what-you-need)
- [Local models directly from Hugging Face](#local-models-directly-from-hugging-face)
- [First steps](#first-steps)
- [Settings at a glance](#settings-at-a-glance)
- [Privacy and costs](#privacy-and-costs)
- [Troubleshooting](#troubleshooting)
- [More documentation](#more-documentation)

## Installation, step by step

### 1. Prepare the Mac
Install Xcode from the App Store and open it once, so it can install its components. In Xcode, open
**Settings → Accounts** and sign in with your Apple ID. Then install XcodeGen, which creates the Xcode project:

```
brew install xcodegen
```

The scripts build from the terminal. On a Mac where the command line tools still point at Apple's standalone
*CommandLineTools* (the usual state after `xcode-select --install`), every `xcodebuild` and `xcrun` call fails with
*requires Xcode*; and before the Xcode licence is accepted, the first terminal build stops with *You have not
agreed to the Xcode license agreements*. Both are fixed once with:

```
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

### 2. Get the code

```
git clone https://github.com/pamo97/GwenMobile.git
cd GwenMobile
```

### 3. Choose your signing team
Apps on your own iPhone have to be signed with your Apple ID. This script lists the teams your Mac knows and
stores yours in `Config/Signing.xcconfig`:

```
python3 scripts/signing_config.py --detect
python3 scripts/signing_config.py --set <TEAMID>
```

`--show` prints the team currently in use. You never create the file by hand: the scripts copy
`Config/Signing.xcconfig.example` to `Config/Signing.xcconfig` on their own, and the team belongs in there —
setting it in Xcode's signing pane is thrown away by the next project generation.

`--detect` reads the signing profiles, the Apple Development certificates in the keychain and the Apple ID signed
into Xcode, so after step 1 it finds the team even on a fresh Mac, before any certificate exists. If it still finds
nothing (no Apple ID signed in), the ten-character team id is shown in Xcode under **Settings → Accounts** when you
select your Apple ID — a free one appears as *Personal Team*; paid members also find it under
[developer.apple.com/account](https://developer.apple.com/account) → *Membership Details*. Write it with
`--set <TEAMID>`; the first build creates the certificate and the profile by itself.

### 4. Prepare the iPhone
Connect the iPhone to the Mac with a cable, unlock it and confirm **Trust This Computer**. Then turn on
**Settings → Privacy & Security → Developer Mode** and let the iPhone restart. (If the switch is missing, it appears
after the iPhone has been connected to Xcode once — run step 5, then come back.)

### 5. Build and install

```
./scripts/deploy-iphone.py
```

This builds the app, installs it on the connected iPhone and starts it. After the first time, the iPhone can also be
reached over Wi-Fi. `--list` shows the devices it can see, `--device <name>` picks one.

### 6. Trust the developer
The first start of a self-signed app is blocked until you allow it once on the iPhone:
**Settings → General → VPN & Device Management →** your Apple ID **→ Trust**.

### 7. First start: connect your AI provider
Open GwenMobile and tap the gear icon at the top right:

1. **AI provider** — choose Qwen Cloud, OpenRouter, DeepSeek, an OpenAI-compatible service, a local model on
   your Mac or *Local (iPhone)*. For Qwen Cloud, also pick the billing type and region your key belongs to.
2. **API key** — paste your key.
3. **Test connection**, then **Load models from account**.
4. Check the chat, photo and picture models the app suggested.

For *Local (iPhone)* no key or account is needed: open the local model section, search Hugging Face, download an MLX
model that fits, and activate it. It then works offline; see [Local models directly from Hugging Face](#local-models-directly-from-hugging-face).

### 8. Allow what you use
iOS asks the first time a feature needs it. Each permission is only used for that feature:

| Permission | Used for |
|---|---|
| Microphone and speech recognition | Dictation, listening mode and Siri |
| Notifications | Answers, "listening stopped" and "listening mode switched off" while listening mode runs in the background, the price watch's hit, and the daily briefing |
| Camera and photos | Taking photos for the chat, scanning documents, saving pictures to Photos |
| Calendar | Creating, changing and deleting appointments |
| Location | "Nearest …" searches and prices where you are |
| Contacts | Finding the person you ask GwenMobile to call or to text |
| Media & Apple Music | Playing songs, artists, albums and playlists from your library and Apple Music |
| Local network | Only when you use a model on your own Mac |

### Install on the Mac

```
python3 scripts/build-mac-dmg.py
```

This writes `GwenMobile-<version>-<date>.dmg` to your Desktop; open it and drag the app into *Applications*. On
another Mac, open it the first time with right-click → *Open*. On the Mac, ⌘Q writes the pending chat save before
the app exits.

The script checks the Metal Toolchain before it builds and installs it when it is missing (about 840 MB, needs
internet). If that download cannot be made, it stops before the build with a readable message instead of the
eleven `CompileMetalFile` errors. To fetch the component by hand:

```
xcodebuild -downloadComponent MetalToolchain
```

## The 7-day limit of a free Apple ID

With a free Apple ID, iOS lets a self-signed app run for 7 days; after that it no longer opens until it is signed
and installed again. `./scripts/renew-gwenmobile.py --renew` does that: it has Xcode create fresh signing profiles
and reinstalls the app on the iPhone and the Mac.

```
./scripts/renew-gwenmobile.py                # what expires when, and whether the job is loaded
./scripts/renew-gwenmobile.py --renew        # renew whatever is due right now
```

To have it done without remembering it, install the renewal job once:

```
./scripts/renew-gwenmobile.py --install-schedule          # every day at 09:20
./scripts/renew-gwenmobile.py --install-schedule 18:30    # or at another time
```

That writes `~/Library/LaunchAgents/com.mortis.gwenmobile.renew-signing.plist` and loads it, so launchd starts
exactly one process per day at that time. The run is cheap and quiet: it reads the profile dates and rebuilds and
reinstalls only when fewer than 2 days are left (`--threshold`), so the first real renewal comes about five days
after the last one — not the next morning. Until then nothing happens, which is why the status and the install
output both name the **next run**; an empty `build/renew/` right after installing is normal.

Check it, or run it by hand:

```
./scripts/renew-gwenmobile.py                # "schedule: 09:20 daily, loaded" plus the next run
./scripts/renew-gwenmobile.py --start-now    # run the job now; it logs to build/renew/launchd.{out,err}.log
./scripts/renew-gwenmobile.py --remove-schedule
```

What the job needs:

- The Mac has to be **switched on and logged in** at 09:20 — it is a login item, not a system service. If the Mac
  is asleep at that moment, launchd runs the job when it wakes up; a day that was skipped is caught up on the next
  run, because the decision comes from the profile's remaining days, not from a timer.
- The iPhone has to be reachable (cable, or the same Wi-Fi network) — the job waits 20 minutes for it.
- Notification permission, once, for the popup: System Settings → Notifications.

In System Settings → General → *Login Items* → *Allow in the Background* the job is listed as **Xcode**, not under
its own name, because it starts with the `python3` that ships inside Xcode.app. That entry has to stay enabled.

If the iPhone asks again, trust the developer as in [step 6](#6-trust-the-developer). How it works in detail:
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#staying-inside-the-free-7-day-window).

## What you can do with it

| You type or say … | Feature | What GwenMobile does |
|---|---|---|
| "Write a short poem about autumn" | [Chat and conversations](docs/FEATURES.md#chat-and-conversations) | Streams answers with formatting, timestamps and day separators; auto-scroll pauses while you read higher up and *To the end* jumps back, one busy indicator names the stage, and a long press offers *Copy answer*, *Save as file* or *Delete message* |
| Tap **+** → *Help & examples* · Settings → *Help & status* | [Offline help center and local status](docs/FEATURES.md#help-and-local-status) | Opens a help sheet that works without provider, key or network: search, topic examples that go into the input with one tap, a local status check and a way into Settings; reachable from the empty chat, the **+** menu, Settings and error alerts |
| "Who won the Eurovision Song Contest 2026?" | [Live web research with sources](docs/FEATURES.md#research) | Searches the web, reads the pages and answers with tappable sources; an inline `[1]` opens the same source, and a long press or hover on a chip shows the full domain. Every source carries a check line with date, author, the page type it declares, imprint and paid links, and suspicious addresses such as punycode, bare IPs, userinfo or plain http are blocked or flagged; a source can be reported as wrong and reported sites stay out of later searches. Copies of one text count as one origin; when copies are found, a *Quellen-Netz* lists every origin with its copies; the optional citation check (Settings → AI & models → Research, off by default) names statements the sources do not back or contradict, marks them in the answer and lists only the warnings in a *Prüfbericht* |
| "Tell me more about each of them" | [Follow-up research in depth](docs/FEATURES.md#follow-ups-understand-the-conversation) | Goes deeper into the previous research answer, point by point |
| "Draw a flowchart of the onboarding process" | [Image generation from your wording](docs/FEATURES.md#images) | Draws the diagram as a normal picture with your image model |
| "Paint a lighthouse at night" · "Make this photo black and white" | [Image generation and photo editing](docs/FEATURES.md#images) | Creates a new picture, or edits one from the chat or your camera; follow-up edits use the previous result, up to ten pictures per message, and a long press on a picture puts it back into the input bar with *Edit* |
| "Show me pictures of the Eiffel Tower" | [Real photo search as a gallery](docs/FEATURES.md#images) | Shows a gallery of real photos you can save or share; a *+ N more* tile shows further hits and *+ N new* searches the next ones until *End of results*; pinch to zoom, double-tap, swipe or ← → to page, and on the Mac ⌘-click adds, ⇧-click picks a range, ⌥-click saves one and ⌘A/⌘S/Esc select all, save and cancel |
| "Create a 10-second video of the Eiffel Tower at sunset" | [Video generation from your wording](docs/FEATURES.md#videos) | Turns the description into an MP4 with the video generator picked under Settings → AI & models → Models: 2–15 seconds, 16:9, 9:16, 1:1, 4:3 or 3:4, with Qwen Cloud, OpenRouter or an OpenAI-compatible video endpoint; the finished video appears as a file card with *Save video* and opens in a player |
| Attach a video with **+** → *Attach video*, then say "Make it clay style" · "Only the woman should say …" | [Video editing from an attached video](docs/FEATURES.md#videos) | Sends the attached video to the video generator as the reference and applies your instruction: people, scene, motion and length stay as close as the model allows; it regenerates the clip, so a pixel-identical result is not guaranteed |
| Attach a video with **+** → *Attach video*: "What happens in this video?" · "Summarise it" | [Video understanding](docs/FEATURES.md#videos) | Sends an MP4, MOV, M4V, WEBM, MPEG or MPG up to 20 MB to a model confirmed for video input (Qwen Cloud or OpenRouter) and answers about the action, people, places, words or timeline; one video is active at a time, and a follow-up can still ask about it |
| Tap *Save video* under a generated video | [Saving videos](docs/FEATURES.md#videos) | Opens the system save panel — Files on the iPhone and iPad, a folder of your choice on the Mac — and leaves the video in the chat, where it opens in a player |
| "Compare the prices of a MacBook Pro 14″ and a MacBook Pro 16″" | [Price comparison across shops](docs/FEATURES.md#price-comparison) | Searches shops and lists the offers with their sources, one round per product; it reads up to six pages, keeps at most four offers — one per shop — and every offer stands under **Offers** |
| "Tell me when the PlayStation 5 falls below 400 €" | [Price watch in the background](docs/FEATURES.md#price-watch) | Watches the product with the same shop chain as the comparison and only accepts offers that name exactly the watched configuration (chip, memory, storage); every watch keeps its own interval (daily by default or the cadence you name), checks run in the background, the list lives under Settings → Services → *Price watch*, and one local notification comes when the target is reached — no account, no server |
| "What is on today?" · "Summarise my day" | [Daily briefing from the device](docs/FEATURES.md#daily-briefing) | One card for today or tomorrow: appointments, weather, travel time to the next one, open reminders and birthdays, plus a daily local notification at the time you choose and a *Read aloud* button on the card that speaks it — everything read from the device, nothing guessed |
| "Appointment tomorrow at 11 called Dentist, remind me an hour before" | [Calendar control (create, change, delete)](docs/FEATURES.md#calendar-control) | Creates, changes or deletes appointments in your calendar |
| "Remind me tomorrow at nine about the dentist" · "Put milk and bread on the shopping list" | [Reminders with time, repetition and place, plus shopping and to-do lists](docs/FEATURES.md#reminders-shopping-lists-timers-and-places) | Keeps reminders, shopping lists and to-do lists in the iOS Reminders app, with due dates, all-day, repetitions, priority, notes and places; lists them, ticks them off, moves or deletes them, and joins things for the same place and time into one reminder |
| "Set a timer for ten minutes" | [iPhone timer](docs/FEATURES.md#timers) | Starts the iPhone's own timer, which rings and lights up even when GwenMobile is closed |
| "Where is the nearest pharmacy?" · "Route me by bike to the city library" | [Nearby places and route hand-off](docs/FEATURES.md#places-and-routes) | Lists nearby places and hands the route to Apple Maps |
| "Play my playlist Sport" · "Play Hello by Adele on Spotify" · "Next song" · "Music off" | [Music playback and control](docs/FEATURES.md#music) | Plays and controls Apple Music (your library first, then the catalog) or Spotify |
| "Text mum that I will be late" · "Send Peter an SMS: on my way" | [Sending text messages](docs/FEATURES.md#text-messages) | Writes the message to the contact and sends it; the text keeps the language you used |
| "Please call family: mother" · "Call Peter Müller on his mobile" | [Phone calls from your contacts](docs/FEATURES.md#phone-calls) | Finds the person in your contacts on the device and starts the call; phone numbers in answers are tappable and dial the same way |
| Attach a PDF, photo, RTF, DOCX, TXT, MD, CSV or JSON: "Summarise this" · "Translate the sign" | [Reading files and photos (PDF, RTF, DOCX, TXT, MD, CSV, JSON, OCR)](docs/FEATURES.md#files-pdfs-word-documents-and-rtf) | Reads the file or photo on the device and answers about it; up to five files per message (20 MB each, 100 PDF pages), and recognised text can be shared as a file |
| "Scan this invoice" · "Scan the receipt" · "Scan the authority letter" · "Scan the deadline as a reminder" | [Document scanner (invoice, letter, authority letter, receipt, deadline as reminder)](docs/FEATURES.md#document-scanner) | Opens the document camera right away (the **+** menu also offers *Scan document*), reads the pages on the device, answers in the language of the request with a summary, every item of a receipt with a bill check, or a button that only saves the deadline as a reminder when tapped; very long scans are trimmed and more than a hundred pages are not taken over; every scan is also saved as a PDF under Files → GwenMobile → Downloads and shareable from the answer |
| Drag a PDF, RTF, DOCX, TXT, JPG, PNG or TIFF from Finder into the Mac window | [Drop to analyse on the Mac](docs/FEATURES.md#files-pdfs-word-documents-and-rtf) | Reads the file or picture on the device and asks the model for the analysis right away — no typing, no extra tap |
| "Write Tetris as a single HTML file" | [Code as a downloadable file](docs/FEATURES.md#code-as-a-file) | Writes the code as a file you can download, share, preview or copy |
| "Translate that into French" | [On-device translation](docs/FEATURES.md#translating) | Translates on the device, a bare *translate that* taking the previous answer; text inside a photo or file goes to the model instead, and the signature line says which of the two produced it |
| "What is the weather tomorrow in Munich?" · "Do I need an umbrella?" | [Live weather data with a forecast card and advice](docs/FEATURES.md#weather-and-everyday-advice) | Fetches the real forecast and draws a weather card with the temperature curve, rain, UV, wind and gusts, plus advice like umbrella, sun protection or a severe-weather warning — spoken too when read-aloud is on; day tabs follow the question, a tap on a bar shows that hour and a button exports the card as a PNG |
| "Remember that I don't eat meat" · "What do you know about me?" | [Long-term personal memory](docs/FEATURES.md#personal-memory) | Keeps durable facts about you in a local memory, uses only the fitting ones in answers and shows them as chips; a fact you only mentioned in passing is offered for saving first, routine check-ups can carry a due date and remind you once you switch the reminder on for that entry, and every entry can be seen, edited, pinned, exported or deleted under Settings → Memory & data → Memory |
| Long-press a generated picture · open the histories | [Saving pictures and managing histories](docs/FEATURES.md#sharing-histories-and-storage) | Long-press a generated picture for *Save to Photos*, AirDrop or *Edit*; *Save to Photos* under an answer saves all its pictures and AirDrop sends the stored JPEG. Histories lists date, message and picture count and size on disk, a swipe deletes one chat and a long press deletes a single message |
| "Delete the history" · your own delete word | [Deleting chat histories with undo](docs/FEATURES.md#sharing-histories-and-storage) | The router removes every saved chat and the open one, leaves an empty chat and offers undo; a saved chat that cannot be read is kept as a backup |
| "What time is it?" · "Which date is it today?" · "What time is it in Tokyo?" | [Local time and date, also in other time zones](docs/FEATURES.md#time-and-date) | Reads the clock of the device and answers at once, for other places in their own time zone |
| "Who is Natalie Portman? Show me pictures and draw her as a comic" | [Several tasks in one message](docs/FEATURES.md#several-tasks-in-one-message) | Splits one message into its tasks and keeps the order you wrote them in; tasks that only read or fetch and need nothing from the others run at the same time, dependent ones and everything that writes to the device or changes a picture wait their turn, and the stop button ends every task still running |
| Just start talking — no wake word | [Conversation mode without a signal word](docs/FEATURES.md#conversation-mode) | Keeps the microphone open while the AI streams and reads aloud; as soon as a sentence or a longer word is recognized, the answer stops at once, the part already streamed stays in the chat, and your sentence becomes the next turn after the silence set under *Silence before sending*. Say the configured cancel word to cancel the running answer at once; the cancel word is not sent and the app only speaks *Understood.* The stop word has no special meaning in this mode. Echo cancellation runs on the device for the speaker, headphones are the most reliable choice, and a single short word is ignored so the AI cannot interrupt itself. The optional *Only my voice* check compares a local voiceprint and ignores other voices before they can interrupt or send anything |
| "Hey Siri, Gwen listen" · "Hey Computer, …" | [Wake word and listening mode](docs/FEATURES.md#voice) | Starts listening after the wake word and shows a rainbow glow while a request is recorded; a Live Activity in the Dynamic Island or on the lock screen takes over in the background, the stop word sends the request, and during an answer or while it is read aloud only the cancel word is heard |
| "Read that to me" · "Schalte vorlesen ein" | [Read-aloud of answers](docs/FEATURES.md#voice) | Reads the last answer aloud or switches reading answers aloud on and off by voice |
| Settings → Voice & speech → *Personal Voice* | [Your own voice for read-aloud](docs/FEATURES.md#voice) | Uses a Personal Voice created in iOS after you allow it there; the voice stays on the device, is never sent to a provider and is not the Voice profile for *Only my voice* |
| Tap the stop button while a search, a picture or an answer runs | [Stopping a running task at once](docs/FEATURES.md#several-tasks-in-one-message) | Cancels the running task — the price lookup, the picture being generated or the streaming answer stops there — and leaves out the rest of the message |

### What the answers look like

The features that do something on the device draw their own card in the chat instead of leaving it to the model.
Every picture links to the feature's own section in [docs/FEATURES.md](docs/FEATURES.md).

**Research and pictures**

<a href="docs/FEATURES.md#research"><img src="docs/screenshots/01-chat.png" alt="Chat with a researched answer and its sources" width="200"></a> <a href="docs/FEATURES.md#research"><img src="docs/screenshots/37-research-source-check.png" alt="A research answer whose source check shows one origin instead of several chips, an unsupported and a contradicted statement tinted in the answer with a small warning sign next to each, warning triangles on the punycode and reported source and a Prüfbericht that lists only the warning statements" width="200"></a> <a href="docs/FEATURES.md#follow-ups-understand-the-conversation"><img src="docs/screenshots/18-research-followup.png" alt="Follow-up research: “Tell me more about each of them” answered point by point with its sources" width="200"></a> <a href="docs/FEATURES.md#images"><img src="docs/screenshots/19-image-generation.png" alt="Image generation: “Paint a lighthouse at night” and the generated picture with Save to Photos" width="200"></a> <a href="docs/FEATURES.md#images"><img src="docs/screenshots/20-photo-editing.png" alt="Photo editing: “Make this photo black and white” with the original and the edited picture" width="200"></a> <a href="docs/FEATURES.md#images"><img src="docs/screenshots/21-photo-gallery.png" alt="Photo search as a gallery: real photo tiles, the counter and the selection hint" width="200"></a>

**Shopping**

<a href="docs/FEATURES.md#price-comparison"><img src="docs/screenshots/22-price-comparison.png" alt="Price comparison: the offers under Offers with their shops and source chips" width="200"></a> <a href="docs/FEATURES.md#price-watch"><img src="docs/screenshots/15-price-watch.png" alt="A price watch for the PlayStation 5 Slim: the answer names the best price found so far and the card shows the target, the waiting status, the configuration the offer names and a button to the offer" width="200"></a> <a href="docs/FEATURES.md#price-watch"><img src="docs/screenshots/16-price-watch-hit.png" alt="The price alarm: the watch card turns green with target reached, the offer below the target and the link to the shop" width="200"></a>

**Your day**

<a href="docs/FEATURES.md#daily-briefing"><img src="docs/screenshots/17-daily-briefing.png" alt="A daily briefing card: greeting and date, weather with umbrella advice, the day tabs Today/Tomorrow, the next appointments with a button to each event, the travel time to the first one, open reminders, a birthday and the read-aloud and notification buttons" width="200"></a> <a href="docs/FEATURES.md#calendar-control"><img src="docs/screenshots/10-calendar.png" alt="An appointment answer with the chip that opens Apple's event sheet" width="200"></a> <a href="docs/FEATURES.md#reminders-shopping-lists-timers-and-places"><img src="docs/screenshots/09-reminders.png" alt="Reminder answers with the chips that open the iOS Reminders app" width="200"></a> <a href="docs/FEATURES.md#timers"><img src="docs/screenshots/23-timer.png" alt="iPhone timer: “Set a timer for ten minutes” and the timer answer" width="200"></a> <a href="docs/FEATURES.md#places-and-routes"><img src="docs/screenshots/11-places.png" alt="A nearby places answer with distance and the route hand-off" width="200"></a> <a href="docs/FEATURES.md#weather-and-everyday-advice"><img src="docs/screenshots/08-weather.png" alt="A weather answer with the app-drawn card: advice block, temperature curve, rain bars, UV, gusts and tiles, with the day tabs Today/Tomorrow and the asked day" width="200"></a>

**Messages, calls and music**

<a href="docs/FEATURES.md#music"><img src="docs/screenshots/24-music.png" alt="Music playback: “Play my playlist Sport” and the music answer" width="200"></a> <a href="docs/FEATURES.md#text-messages"><img src="docs/screenshots/25-message.png" alt="Sending text messages: “Text mum that I will be late” and the message answer" width="200"></a> <a href="docs/FEATURES.md#phone-calls"><img src="docs/screenshots/26-call.png" alt="Phone calls: “Call Peter Müller on his mobile” and the call answer" width="200"></a>

**Videos**

<a href="docs/FEATURES.md#videos"><img src="docs/screenshots/02-plus-menu.png" alt="The plus menu in GwenMobile: Camera, Scan document, Attach photo, Attach file, Attach video, Read aloud and Help & examples. Attach video opens the Files picker and lets the chat read a video." width="200"></a>

**Papers and content**

<a href="docs/FEATURES.md#files-pdfs-word-documents-and-rtf"><img src="docs/screenshots/27-files.png" alt="Reading files: an attached PDF with pages, size and the on-device extraction badge, plus the summary" width="200"></a> <a href="docs/FEATURES.md#document-scanner"><img src="docs/screenshots/13-scanner.png" alt="A scanned receipt with the summary lines, the saved PDF card with its share button and the note that it is stored under Files → GwenMobile → Downloads" width="200"></a> <a href="docs/FEATURES.md#document-scanner"><img src="docs/screenshots/14-scanner-reminder.png" alt="A scanned invoice with the summary, the shareable PDF card and the deadline offered as a button that only saves the reminder when tapped" width="200"></a> <a href="docs/FEATURES.md#code-as-a-file"><img src="docs/screenshots/12-code.png" alt="A code answer as a file card with preview, download, share and copy" width="200"></a> <a href="docs/FEATURES.md#translating"><img src="docs/screenshots/29-translation.png" alt="On-device translation: “Translate that into French” with the on-device signature" width="200"></a>

**Your data and the app**

<a href="docs/FEATURES.md#personal-memory"><img src="docs/screenshots/30-memory.png" alt="Personal memory: “Remember that I don't eat meat” and the saved fact as a chip" width="200"></a> <a href="docs/FEATURES.md#sharing-histories-and-storage"><img src="docs/screenshots/31-history-undo.png" alt="Deleting the history with undo: the empty chat and the undo bar with the freed space" width="200"></a> <a href="docs/FEATURES.md#time-and-date"><img src="docs/screenshots/32-time.png" alt="Local time and date: “What time is it in Tokyo?” and the answer from the device clock" width="200"></a> <a href="docs/FEATURES.md#several-tasks-in-one-message"><img src="docs/screenshots/33-multi-task.png" alt="Several tasks in one message: pictures of the Northern Lights and the appointment from one request" width="200"></a>

**Help and status**

<a href="docs/FEATURES.md#help-and-local-status"><img src="docs/screenshots/39-help-center.png" alt="Offline help center: a search field, Check status and Settings shortcuts, topic chips, and example prompts for research and pictures, each with a Use button" width="200"></a>

**Voice and control**

<a href="docs/FEATURES.md#conversation-mode"><img src="docs/screenshots/38-conversation.png" alt="Conversation mode: the waveform button is active in the header, the input bar says that a recognized sentence stops the answer" width="200"></a> <a href="docs/FEATURES.md#voice"><img src="docs/screenshots/34-listening.png" alt="Wake word and listening mode: the ear switched on with an answer that came from listening" width="200"></a> <a href="docs/FEATURES.md#voice"><img src="docs/screenshots/35-read-aloud.png" alt="Read-aloud: the plus menu with reading answers aloud switched on" width="200"></a> <a href="docs/FEATURES.md#several-tasks-in-one-message"><img src="docs/screenshots/36-stop.png" alt="Stopping a running task: a streaming answer with the stop button in the input bar" width="200"></a>



The full list, with every detail, is in [docs/FEATURES.md](docs/FEATURES.md).

## How it works

- **You bring the AI.** GwenMobile talks directly to the AI provider you choose — Qwen Cloud, OpenRouter, DeepSeek,
  any OpenAI-compatible service, a model running on your own Mac (Ollama, LM Studio), or an MLX model downloaded
  directly from Hugging Face and running inside GwenMobile on the device itself. Your key stays in the iPhone's
  Keychain.
- **Much of it happens on the device.** Scanning documents and reading PDFs and text in photos, translating chat
  text, speech recognition and read-aloud use Apple's built-in services. Places and routes come from Apple Maps,
  appointments go into the iOS Calendar, the weather from Open-Meteo (with Apple's geocoder correcting place names),
  reminders and shopping lists into the Reminders app and the timer into the iPhone's own one.
  The offline help center, its example search and the local status check also stay on the device and open even
  when the provider or network is down.
- **Nothing in between.** There is no GwenMobile server and no account. You pay your AI provider for what you use;
  Apple's on-device services cost nothing.

## What you need

- **A Mac** with [Xcode](https://apps.apple.com/app/xcode/id497799835) (free, about 40 GB) and
  [Homebrew](https://brew.sh).
- **The Metal Toolchain** (about 840 MB, one-off). Xcode 27 ships the Metal compiler that the local MLX models
  need as a separate component. Every build script — `scripts/build-mac-dmg.py`, `scripts/deploy-iphone.py`,
  `scripts/renew-gwenmobile.py` — checks for it and downloads it on the first build, so internet is needed once.
  No admin password, no Apple ID and no Xcode download session are required for this.
- **An Apple ID.** A free one is enough; the only catch is that the app then has to be reinstalled every 7 days —
  a script can do that for you (see [below](#the-7-day-limit-of-a-free-apple-id)). A paid Apple Developer Program
  membership removes the limit.
- **An iPhone or iPad with iOS 26 or later**, or a Mac with macOS 14 or later. Speech recognition runs on the
  device; the Mac build falls back to SFSpeechRecognizer.
- **An AI provider** and, except for local models, an API key:

| Provider | Good for | Where to get the key |
|---|---|---|
| **Qwen Cloud** (default) | The setup the app was built and tested with: `qwen3.8-flash` for chat, `qwen3.8-max` for photos, `wan2.7-image` for pictures and a video generator for videos | In the app: Settings → AI & models → AI provider → *Create a key in the QwenCloud console* ([home.qwencloud.com/api-keys](https://home.qwencloud.com/api-keys)) |
| **OpenRouter** | Many models from one account, including video generation models such as Seedance, Veo or Wan; the app shows your remaining credit | [openrouter.ai/settings/keys](https://openrouter.ai/settings/keys) |
| **DeepSeek** | Direct DeepSeek API with a fixed address; the app shows your available balance | [platform.deepseek.com/api_keys](https://platform.deepseek.com/api_keys) |
| **OpenAI-compatible** | OpenAI, Groq, Mistral, Together AI, or any other compatible address; video generation works where the endpoint offers the OpenAI videos API | The provider's own console |
| **Local** (Ollama, LM Studio) | Free and private, runs on your Mac | No key needed |
| **Local on the iPhone** | Private, serverless MLX models from Hugging Face; installed models plus a live search, with only a RAM-fit filter; text or vision depending on the model | Settings → AI & models → AI provider → *Local (iPhone)* → *Hugging Face MLX*; no key needed |

Chat works with every provider. Pictures and diagrams need Qwen Cloud or OpenRouter with a picture model; photo
understanding needs a model that accepts images — without one the app keeps a photo back and points to Settings →
AI & models → Models instead of sending it to a text model. A question about an attached video needs a model confirmed for video
input (Qwen Cloud or OpenRouter); creating a video needs a provider with a video generator (Qwen Cloud, OpenRouter
or an OpenAI-compatible endpoint). The *Features* row in
Settings shows for the chosen provider whether it offers chat, photos (*Vision*), pictures, video and video
generation, and the model lists only offer models confirmed for the job.

## Local models directly from Hugging Face

GwenMobile can download MLX models from Hugging Face and run them inside the app — no second app, no server and no
API key. The local model screen is not a fixed catalog: it shows the models installed on the device with their
`model.json`, and searches Hugging Face for MLX models that the app supports.

1. Open **Settings → AI & models → AI provider → Local (iPhone)**.
2. In **Hugging Face MLX**, start the search (it also runs when the section opens) and refresh it if needed.
3. Keep **Only models that fit the RAM** on, or switch it off to see the ones that are too large for the device.
4. Download a model, leave GwenMobile open while it downloads, then activate it for chat — or for vision if it
   supports images.

The search requires internet. The one filter is whether the model fits the iPhone's RAM; there are no parameter or
file-size switches. Only public, ungated MLX/safetensors chat checkpoints with a supported architecture and the
required `config.json`, tokenizer and chat template appear. GGUF, PyTorch, embeddings, rerankers and draft/MTP models
are not offered. Text-only models work for chat; only vision-capable models can read photos. Tool calling is
experimental for dynamic models.

After the download the model files stay in the app's storage and the model can be used offline. Installed models
survive a relaunch. On an 8 GB iPhone 16 the RAM filter shows, for example, Gemma 4 E2B, its QAT variant, small
0.5–4B models and Mistral 7B; E4B and Qwen 9B need a 12 GB device. The form keeps the existing E2B available while
it is installed, even when a search filter would hide it.

The technical details and the supported-architecture check are in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#hugging-face-mlx-browser).

## First steps

Try these in a new chat:

- "What's in the news in Berlin today?" — then "Tell me more about each of them".
- "Remind me when I am at REWE to buy milk" — then "What is on my shopping list?"
- "Paint a red ball on a white background, then make the new picture black and white."
- "Show me pictures of the Northern Lights and add an appointment tomorrow at 9 called Photo walk."
- "Create a 10-second video of the Eiffel Tower at sunset." — the finished MP4 appears in the chat with *Save video*.
- Attach a video with **+** → *Attach video*, then ask "What happens in this video?" or "Summarise it".
- "Where is the nearest supermarket, and what are its opening hours?"
- Take a photo of a price tag with **+** → *Camera*: "Can you find this cheaper?"
- "Tell me when the PlayStation 5 falls below 400 €" — the answer carries a watch card and GwenMobile reports the
  hit in the background; Settings → Services → *Price watch* lists, pauses and deletes the watches.
- Tap the microphone and say: "What time is it in Tokyo? Jetzt senden" — or, in English, "… Send it now".
- Tap the **waveform** button next to the ear at the top of the chat (or Settings → Voice & speech → *Voice control* → *Conversation mode without signal word*), then just talk: a recognized sentence stops the answer immediately, and the sentence becomes the next turn.
- Optional: open **Settings → Voice & speech → Voice control → Voice profile**, record three short samples and switch on
  **Only my voice**. Conversation mode then ignores other speakers before they can interrupt the answer or become a
  turn.

A message can hold as many tasks as you like. Tasks that only read or fetch and need nothing from the others run
at the same time — two questions, a web lookup beside a weather card, several separate pictures — while dependent
tasks and everything that writes to the device or changes a picture wait their turn. The visible order stays the one
you wrote. The stop button cancels everything that runs at that moment — a price search, a picture being generated
or a streaming answer stops there — and leaves out the tasks after it.

**Answers:** long-press an answer → *Copy answer*, *Save as file* (rendered HTML under Files → GwenMobile → answers,
plus the share sheet) or *Delete message*; the copy icon next to the signature line (model, seconds, thinking level)
takes the raw text.

**Voice:**
- The microphone button shows your words live. End with the **stop word** (*Jetzt senden* / *Send it now*) to send
  at once, or with the **cancel word** (*Jetzt abbrechen* / *Cancel that*) to discard; otherwise it sends after a
  short pause.
- **Conversation mode without a signal word** is switched in Settings → Voice & speech → *Voice control* or with the **waveform**
  button between the ear and the gear at the top of the chat. The microphone stays open while the AI streams and
  reads aloud. As soon as it recognizes a sentence or a longer word, the answer stops immediately, the part already
  streamed stays in the chat, and your sentence becomes the next turn after the silence set under *Silence before
  sending* (default 4 s). A single short word such as *Stop* or *Yes* alone is ignored and discarded, so the AI
  cannot interrupt itself; say a sentence or a longer word such as *Moment* or *Warte*. If you say the configured
  cancel word, the running answer or task is cancelled at once, the cancel word is not sent, and the app only speaks
  *Understood.* in the app language. The stop word has no special meaning in conversation mode. Echo
  cancellation runs on the device for speaker output, and
  headphones are the most reliable choice. The mode has no fixed listening time; it keeps listening until you
  switch it off, keeps working when you switch to another app, and pauses while Settings or the histories are open;
  the open app keeps the screen awake. Switching on the wake-word listening mode switches conversation mode off;
  the two modes stay separate.
- **Personal Voice — your own voice** (Settings → Voice & speech → *Personal Voice*):
  GwenMobile cannot create or import a voice; first create it in iOS under **Settings → Accessibility → Personal
  Voice → Create a Personal Voice**, turn on *Allow Apps to Request to Use* and allow GwenMobile in that panel.
  Then open Settings → Voice & speech, tap *Use Personal Voice* and confirm the iOS permission prompt: GwenMobile lists the
  voice with the output voices, selects it and offers *Hear a sample*. It is then used for read-aloud, spoken
  confirmations and briefings. Use *Check again* after creating the voice, after iOS has finished processing it or
  after turning the permission on; if the voice still does not appear, restart GwenMobile once. The voice stays on
  the device and is never sent to a provider; it is not the Voice profile for *Only my voice*. Apple currently
  supports English (U.S.), Mandarin Chinese (China mainland) and Spanish (Mexico), not German; if the voice language
  differs from the app language, the app shows a hint.
- **Only my voice** (Settings → Voice & speech → *Voice control* → *Only my voice*) adds a local speaker check to conversation mode.
  Record a **Voice profile** first: three prompts of about five seconds each, ideally with the microphone you will
  use later (iPhone or AirPods). After that, speech from anyone else is ignored before it can interrupt the answer,
  trigger the cancel word or become a new turn; your own speech works as before. The app computes the voiceprint on
  the device with a small speaker model bundled in the app (WeSpeaker ResNet34-LM, 14 MB) and compares it with the
  enrolled profile; no account, download or cloud service is involved. The profile stays in the Keychain on this
  device, is not migrated to another device or synced via iCloud, and can be deleted at any time; the raw
  enrollment recordings are discarded immediately. **Sensitivity** offers *Strict*, *Normal* and *Relaxed*: use
  *Strict* around other voices and *Relaxed* if your own voice is rejected too often — for example with a cold or
  a different microphone. The check is a probability, not a secure login: similar voices can pass, and a different
  microphone may require re-enrollment. It applies to conversation mode only; dictation and the wake-word listening
  mode are unchanged. Without a profile, conversation mode does not start while the setting is on.
- **Listening mode** (Settings → Voice & speech → *Voice control*, or the **ear** button at the top of the chat — tap on, tap off,
  always in step with the switch in Settings): say the **wake word** (*Hey Computer*) followed by your request;
  a randomly chosen spoken confirmation (*I hear you* / *Yes?*, localized) tells you it is listening, a falling
  tone that your request arrived — the request tone can be swapped for one of the system sounds of your iPhone or Mac
  in Settings → Voice & speech → *Voice control*. The confirmation is spoken in the app language and is not captured into the request;
  echo cancellation keeps GwenMobile's own confirmation and read-aloud out of the input, and headphones are the most
  reliable choice. The screen stays on while the app is open. Quiet speech triggers it too: the app lifts quiet microphone audio towards a comfortable level before the
  recognizer sees it, while loud speech and silence stay untouched.
- While listening mode is on, a rainbow glow along the screen edges appears when the wake word starts a request and
  stays while it is recorded; switching to another app or locking the iPhone ends it and hands over to a Live
  Activity in the Dynamic Island or on the lock screen. Returning to the app or switching the mode off dismisses it.
  During an answer or while it is read aloud only the cancel word is heard, and it cancels the answer.
- Saying only the **new-chat word** (*Neuer Chat* / *New chat*, or *Neue Session* / *New session*) after the wake
  word opens an empty chat instead of asking the AI. Saying only the **listening-off word** (*Zuhören beenden* /
  *Stop listening*, also *Zuhörmodus aus* / *Listening off*) after the wake word switches listening mode off — from
  the background as well; a notification then says so.
- Once the mode is on, it keeps listening when you switch to another app, reads every answer aloud — also when
  read-aloud is switched off — and sends it as a notification. With AirPods or a Bluetooth headset connected it
  listens through their microphone, so you can walk away from the iPhone; depending on the model, other audio sounds
  like a phone call while the mode is on.
  iOS cannot start the microphone from the background: after a phone call or Siri a notification may ask you to open
  GwenMobile, which then listens again.
- All five words — wake, stop, cancel, new chat and listening off — can be changed in Settings → Voice & speech → *Voice control*;
  the new-chat and the listening-off word take several variants separated by commas.
- **Siri:** "Hey Siri, Gwen hör zu" (English: "Hey Siri, Gwen listen") opens GwenMobile and starts listening. "Gwen"
  is registered as an alternative name for the app, so "Hey Siri, Gwen" is offered too — whether iOS then starts
  listening or only opens the app is up to Siri. Open the app once after installing so iOS learns the phrases.
  The URL `gwenmobile://listen` does the same from the Action button or Back Tap.
- **Your own Siri word:** iOS only allows an app built-in phrases that contain its name, but a shortcut can be called
  anything. In the **Shortcuts** app tap **+** → *Add Action*, search for *GwenMobile* and pick *Listen* (German:
  *Zuhören*); then tap the shortcut's name at the top and rename it — for example *Jarvis*. From then on
  "Hey Siri, Jarvis" starts listening. The button in Settings → Services → *Your own Siri command* opens Shortcuts for you. Pick
  a name Siri understands well and that is not already a Siri command.

**Phone calls:**
- Say or type whom to call — "Please call family: mother", "Ruf Mama an", "Call Peter Müller on his mobile". The
  AI only decides that you want a call and whom you mean; GwenMobile then looks the person up in your contacts on the
  device — by name, nickname, the relations on your own card ("mother: Maria …") and your contact groups — and
  dials. When several contacts fit or a name only sounds similar, it asks back instead of guessing.
- Phone numbers that appear in an answer are tappable: the AI marks them itself, the app finds unmarked ones too,
  and a tap dials the same way a spoken call request does — with the iOS prompt or hands-free as below. Dates,
  prices and postal codes stay plain text.
- With a free Apple ID iOS asks once before every call from another app: tap **Call** in that prompt.
- **Completely hands-free** — no prompt at all — needs a paid Apple Developer Program membership, iOS 26 and a
  device in the EU: write `GWEN_DIALER = YES` into `Config/Signing.xcconfig`, install again, and choose GwenMobile as
  the default dialer app in the iOS Settings under the default apps. According to Apple, calls from the default
  dialer app start without the prompt, so "Hey Computer, call mum" needs no tap at all. Details:
  [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#phone-calls-and-the-default-dialer).

**Text messages:**
- Say or type whom to write to and what — "Schreib Mama, dass ich später komme", "Send Peter an SMS: on my way".
  GwenMobile finds the contact like for a call (and asks back when two fit) and fills in the message.
- With a free Apple ID the Messages form opens ready to go and you tap **Send** — Apple lets only you send from it.
  The form needs GwenMobile open; asked from the background, the answer asks you to open the app and say it again.
- Sending **without a tap** needs a paid Apple Developer Program membership, iOS 26 and an account and device in
  the EU: write `GWEN_MESSAGING = YES` into `Config/Signing.xcconfig`, install again and choose GwenMobile as the
  default carrier messaging app in the iOS Settings. According to Apple, GwenMobile then also receives your SMS.

**Music:**
- Say or type what to play — "Play my playlist Sport", "Play songs by Adele", "Play Hello by Adele on Spotify" — or
  what to do: "Next song", "Previous song", "Pause the music", "Music on". The AI only decides that you mean music,
  what and where; GwenMobile finds it and plays it. Settings → Services → *Music* picks the default service.
- **Apple Music** looks in your own library first (playlists, artists, albums, songs) and then in the Apple Music
  catalog through Apple's public iTunes search; catalog titles need an Apple Music subscription. Nothing to set up
  besides allowing access to your library once.
- **Spotify** is controlled with Spotify's iOS SDK. Spotify requires the owner of a development app to have
  **Premium**. Once: create an app in the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard),
  add the redirect URI `gwenmobile://spotify-login-callback` and the iOS bundle ID `com.mortis.gwenmobile`, copy the
  client ID into Settings → Services → *Music* and tap *Connect to Spotify*. With GwenMobile open, Spotify is controlled
  directly (or opened for a moment if it is not running); from the background, for example in listening mode with
  the screen locked, GwenMobile uses Spotify's Web API, which plays on your *active* Spotify device — open Spotify
  once if it answers that there is none.
- While listening mode is on, other audio is no longer turned down all the time — Apple allows that only for a few
  seconds — so music keeps its volume while GwenMobile listens for the wake word.
- The Mac version controls neither: Spotify's SDK exists for iPhone and iPad only, and Apple Music control is left out
  there as well.

## Settings at a glance

The settings start page groups the configuration into six areas; each opens a short, focused page. *Test connection* sits at the bottom of the start page. Provider, models and the Mac settings are described in more detail in [docs/FEATURES.md](docs/FEATURES.md#settings).

| Area | What it holds |
|---|---|
| AI & models | AI provider and API key; chat, vision, image, video and video generator models; thinking depth; *Load models from account*; local MLX models on the iPhone; the optional citation check for research |
| Voice & speech | The voice that reads answers aloud, including a Personal Voice created in iOS after permission; listening mode with wake word; **conversation mode without a signal word**; *Only my voice* with a local voiceprint (three 5 s enrollment recordings, *Strict*/*Normal*/*Relaxed* sensitivity); wake word, stop word, cancel word, new-chat word, delete-history word, listening-off word; maximum dictation length; silence before sending; the sound for "request understood" |
| Language & appearance | German, English, Spanish or French interface; light or dark; on the Mac also *Open at login* |
| Memory & data | Your durable facts: master switch, suggestions, used-memory chips, retention (always, 12 or 3 months), check-up due dates with their reminders, the *About me* list and *Delete all memories*; automatic text recognition in photos; how much space chats, pictures, documents and exports take; *Delete all histories* (with undo) |
| Services | Default music service (Apple Music or Spotify), Spotify connection; the daily briefing with its time and sections; the price watches with pause, check now and delete; your own Siri command |
| Help & status | The offline help center with search, examples and a local status check that names what is ready and what needs attention |

The start page and three detail pages:

<a href="docs/FEATURES.md#settings"><img src="docs/screenshots/03-settings.png" alt="Settings start page with AI & models, Voice & speech, Language & appearance, Memory & data, Services and Help & status, plus Test connection" width="200"></a> <a href="docs/FEATURES.md#voice"><img src="docs/screenshots/05-voice-control.png" alt="Voice & speech detail page: voice control with conversation mode without a signal word, the only-my-voice check, listening mode and the wake and stop words" width="200"></a> <a href="docs/FEATURES.md#settings"><img src="docs/screenshots/06-models.png" alt="AI & models detail page: provider, chat, vision, image, video and video generator models, thinking depth and the citation check" width="200"></a> <a href="docs/FEATURES.md#music"><img src="docs/screenshots/07-music.png" alt="Services detail page: music service, Spotify connection and daily briefing" width="200"></a>

At the top of the chat, the pencil starts a new chat, the list icon opens older chats, the ear switches listening
mode, the waveform switches conversation mode without a signal word and the gear opens Settings. Read-aloud is
switched in the **+** menu, which also attaches videos. A tap on the GwenMobile symbol shows
when the installed build was made and its version; the ✕ closes the card again.

## Privacy and costs

- **Sent to your AI provider:** your message and the recent conversation (up to 30 messages and 10 pictures), the
  current date, time and time zone, the text read from attached files, a video you attached when you ask about it,
  the description you ask to turn into a video, the durable facts you stored about yourself
  — as a short catalog for the router on every request and, when they fit, as context for the answer — when
  you ask for an appointment, the titles and times of your upcoming appointments, so it can find or avoid them, and
  when a price watch checks, the watched product with its target and the shop pages the device fetched. After a
  researched answer, and only when Settings → AI & models → Research → *Verify citations against sources* is on, the answer and
  its cited sources go along once more for the citation check, which runs in the background while you keep chatting.
- **Sent to the web:** search terms to DuckDuckGo (research, prices) and Bing (photo galleries); the pages found are
  loaded directly by your device. What you ask to play goes to Apple's iTunes search when your own library has no
  match (Apple Music), or to Spotify's Web API. A weather question sends the place name — or, for "here", its
  coordinates — to Open-Meteo for the forecast; Apple's geocoder and local search correct a misspelled place before
  the forecast is fetched. Hugging Face receives the model search and serves the downloaded model files; no chat
  text, pictures or files are part of that request.
- **Stays on the device:** your key (Keychain), your chats, pictures and generated videos, the optional voiceprint
  for *Only my voice* (Keychain, device-only and not migrated to another device or synced via iCloud; raw enrollment
  audio is discarded; the bundled speaker model and the voiceprint are never sent to the provider), the Personal Voice
  you select (created and stored by iOS; GwenMobile only receives permission to use it and never sends it to a
  provider), your memory entries
  (`memory.json` in the app's storage), your price watches (`price_watches.json` with product, target and the last
  offer found), your reported sources and the duplicate comparison of the found pages, speech recognition, text
  recognition in
  photos and files, translation of chat text, downloaded MLX model files in `Library/Application Support/local-models`,
  your contacts and their numbers (the answer names the person
  called or written to, and like every answer it is part of the conversation later requests carry), your location
  (used for Apple Maps and to pick the country for prices). A request to translate text inside an attached photo or
  file goes to the AI model, since only it can read it.
- **Costs:** only what your AI provider charges for the requests; generated videos are billed according to the
  provider's pricing.
  The app itself is free (MIT license).

## Troubleshooting

| Problem | What to do |
|---|---|
| "Untrusted Developer" when opening the app | See [step 6](#6-trust-the-developer) |
| The app stopped opening after a week | The 7-day limit — run `./scripts/renew-gwenmobile.py --renew`, or set up the [renewal job](#the-7-day-limit-of-a-free-apple-id) |
| *Developer Mode* is missing on the iPhone | Connect it to the Mac and run step 5 once; the switch appears afterwards |
| The build fails because of signing | Check that you are signed in under Xcode → Settings → Accounts, then run `python3 scripts/signing_config.py --detect` and `--set` again |
| The build fails with `cannot execute tool 'metal' due to missing Metal Toolchain` | Xcode 27 keeps the Metal compiler in a separate component. The build scripts install it on their own; by hand it is `xcodebuild -downloadComponent MetalToolchain` (about 840 MB). No `sudo` needed. |
| The key is rejected or no models appear | Check provider, and for Qwen Cloud billing type and region; then *Test connection* and *Load models from account* |
| No pictures are created | Use Qwen Cloud or OpenRouter and choose a picture model — an OpenAI-compatible server or a local model cannot draw |
| No videos are created or edited | Video generation and editing need a provider with a *Video generator* chosen under Settings → AI & models → Models — Qwen Cloud, OpenRouter or an OpenAI-compatible endpoint with video support; load the models from the account first. Questions about an attached video need a *Video model* confirmed for video input (Qwen Cloud or OpenRouter) |
| The app closes or the iPhone restarts while a local model answers | Choose a model the RAM filter allows; on 8 GB, E4B and Qwen 9B are hidden. The local router and local web answers run without pictures; long file analyses also drop remembered pictures, because a multimodal prompt made MLX allocate a 4.8 GB logits buffer, above the 4 GB Metal limit. The app serializes local requests, keeps a prompt and generation budget and reports a memory error instead of loading twice — see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#local-models-on-the-iphone) |
| No local MLX models appear | Open Settings → AI & models → AI provider → *Local (iPhone)* and start the Hugging Face search; it needs internet. Only public MLX/safetensors models with a supported architecture appear. If nothing fits, switch *Only models that fit the RAM* off to see the rest, but they cannot run on this device. |
| A downloaded local model is not available for photos | Text-only models are chat-only. Choose a vision-capable model such as Gemma 4 E2B for photos and keep it as the vision model. |
| A model on the Mac is not reached | Use the Mac's name instead of `localhost` (e.g. `http://MyMac.local:11434/v1`), allow local network access, and pick a model that supports tools — see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#local-models-with-ollama) |
| You need help while the provider or network is down | Open **+** → *Help & examples* or Settings → *Help & status*; the help center, its search and the local status check work without provider, key or network |
| Speech is not recognised | Allow microphone and speech recognition; the very first use downloads Apple's speech model once |
| A Personal Voice is not listed | Create it in iOS under Settings → Accessibility → Personal Voice, turn on *Allow Apps to Request to Use* and allow GwenMobile in that panel, then open Settings → Voice & speech → *Personal Voice* and tap *Use Personal Voice* or *Check again*. iOS may need time to finish processing the voice; restart GwenMobile once if it still does not appear. Apple currently supports English (U.S.), Mandarin Chinese (China mainland) and Spanish (Mexico); German is not supported. |
| *Only my voice* rejects my own speech | Re-enroll under Settings → Voice & speech → *Voice control* → *Voice profile* with the microphone you actually use, speak through each 5 s prompt in a quiet room and set the sensitivity to *Relaxed* if needed |
| Other voices still trigger conversation mode | Set the sensitivity to *Strict* and re-enroll; similar voices can still pass — the check is a probability, not a secure login |
| Siri does not react | Open the app once after installing, then try "Hey Siri, Gwen hör zu" / "Hey Siri, Gwen listen"; for your own word, check that the shortcut's name is exactly what you say |
| A call asks "Call?" first | That is iOS for apps with a free Apple ID; for calls without the prompt see [Phone calls](#first-steps) |
| "No access to your contacts" | Allow Contacts under Settings → Privacy & Security → Contacts → GwenMobile |
| Listening stops in the background | Switch listening mode on while the app is open; after a phone call or Siri, open GwenMobile once and it listens again. Allow notifications to be told when that happens |

## More documentation

- [docs/FEATURES.md](docs/FEATURES.md) — every feature in detail
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — project structure, tests, device probes, scripts and the renewal job
- [LICENSE](LICENSE) — MIT
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) — the bundled speaker model and its CC BY 4.0 attribution
