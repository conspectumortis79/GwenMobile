# GwenMobile (iOS)

Native SwiftUI chat app for your Qwen Cloud account (OpenAI-compatible API).
Swift 6, strict concurrency, iOS 17+.

## Features

### Chat & conversations
- Streaming chat answers with a selectable model (e.g. qwen3.8-flash) — already formatted
  while the tokens arrive, not only once the answer is finished
- Compact input bar: a "+" menu holds camera, photo and read-aloud (with visible
  ON/OFF state) — camera first, because the photo is only the fallback when you cannot aim;
  mic and send stay one tap away, so the text field is roughly twice as wide.
  All four round controls (+, mic, send/stop) are the same 34 × 34 pt circle, and while a dictation
  is running the send button turns into the stop control for it (see *Voice*)
- How much the model reasons before it answers is a setting, not a guess: Settings →
  **Thinking depth** (*Denktiefe*) offers exactly the levels your provider confirms for the chat model,
  from *Model default* (send nothing) down to *Off — fastest answer* — measured 11,9 s against 355 s
  on the same task. Every helper call the app fires beside the answer runs with thinking off, and the
  bubble signature shows which depth produced an answer (see *Thinking depth*)
- Multiple conversations, persisted locally (JSON + images in the app sandbox)
- Every request is sent in context: the conversation (its last 30 turns) plus the pictures it holds —
  attachments and AI-generated ones, newest last — so follow-up questions, diagrams, colour transfers and
  new pictures build on what came before
- API key stored in the Keychain, never in files
- Bilingual UI (German / English), day separators, timestamps, markdown-lite rendering
  (bold, inline code, links) applied to the live stream as well; a marker that is still open,
  like `**` without its partner, simply stays plain text until the closing token arrives
- Branded header: app icon beside the left-aligned "GwenMobile" title, actions right-aligned
- One waiting indicator everywhere the AI is busy and you have to wait — the word
  (`Processing`, or the specific task such as `Generating image`,
  `Handling the appointment`, `Searching the web`) plus three dots that count up
  0 → 1 → 2 → 3 every 2 s, in place of any spinning wheel
- Long-press any answer to store it as a file: the export is **rendered HTML**, not the raw
  markdown the model produced — bold, italics, inline code, lists, headings, links and the
  numbered source list all show up formatted, in light and dark appearance, and the file prints
  to PDF straight from the share sheet. The file is named after the **user's question**
  (letters and digits only, no `?`, `!`, quotes or emoji, first nine words), so
  `What is the capital of France?` becomes `What is the capital of France.html`;
  a name clash gets `… 2.html`, and a message without a question falls back to a
  timestamped name (`antwort-2026-09-11-133827.html`; `antwort` is the app's fixed fallback prefix).
- Files land in `Documents/answers` (visible in the Files app under *GwenMobile*, the app has file
  sharing enabled) and the iOS share sheet opens in the same tap, so they can go to Files, Mail,
  Notes or AirDrop — and whichever of them you use, the sheet is gone again by itself once the file
  is handed over, saved or cancelled (see *Sharing pictures and saving answers*)

<img src="docs/screenshots/01-chat.png" alt="GwenMobile after launch: empty conversation, header with app icon and title, input bar with plus, mic and send" width="270"> <img src="docs/screenshots/02-plus-menu.png" alt="The plus menu opened above the input bar: Camera first, then Attach photo, then Read aloud with its OFF state" width="270">

*After launch (left) and the "+" menu with photo, camera and read-aloud (right).*

### Data graphics from the web
- Ask in one sentence — "look up the population figures online and chart them",
  "look up the latest unemployment rates and plot them" — and the app runs the whole chain:
  web search → page text → the chat model distils a **chart plan** (kind, title, unit, 2–8 label/value
  pairs) from **the fetched numbers only** → that plan becomes the prompt for the image model → the
  picture arrives in the chat with the data listed as text and the sources as clickable chips.
- Two independent detection layers, so a chart wish is never missed and a plain question is never
  hijacked: `ChartIntent` decides deterministically on phrasing (needs an explicit chart word such as
  *chart/diagram/graph/plot* **plus** a data or research word, it honours rejections like
  "no chart", "just text", and `refersToExistingVisual` keeps it quiet when the chart word only
  *points at* a graphic already on screen — "the statistics you entered in the chart", "where did you get
  the numbers for the chart", "which values did you show in the chart" are questions answered in
  text, while the same sentence that also asks to produce one ("make the chart again with the 2025 numbers")
  still draws), and the chat model itself can answer with the protocol tokens
  `[[CHART]]` or `[[SEARCH]][[CHART]]` for everything the phrase lists cannot see. If only the marker
  fires, no search is done and the numbers come from the model's own knowledge; the system prompt
  spells out that a question about an already shown picture — including where its numbers or sources
  come from — is answered in text, never with a token.
- The plan is validated, not trusted: values survive `1,5`, `1.234,56`, `1,234.56`, `42 %` and `12,345`,
  broken points are dropped, fewer than two usable numbers aborts with a hint instead of drawing fiction.
  Every fetched page contributes to the `## DATA` block instead of the budget running out after the first
  two (`WebResearch.dataDigest` splits the limit per source), an unusable plan is asked for a second time,
  and the raw answer of both attempts lands in `Documents/flow_trace.txt` as `CHARTPLAN unbrauchbar …`
  so a refusal can be traced to the sources that caused it.

### Follow-ups understand the conversation
- "What are the main causes of global warming?" → answer → **"and in Germany?"** works in every
  flow, not just in plain chat. Before a web search or a chart is planned, `FollowUpResolver` decides
  deterministically whether the message can stand alone (anaphora such as *and in / out of that / about it /
  what about / your answer*, or a bare fragment), and only then asks the model for one standalone
  search query ("main causes of global warming in Germany"). That query is what
  `WebSearch.search`, `WebSearch.makeAnswerRequest` and `ChartPlanner` actually receive.
- "make a chart out of that" after a researched answer: the previous answer plus its source list become
  the `## DATA` block, so the chart is drawn from the numbers the app just showed — not from the model's
  memory. Without any prior research the planner still falls back to the model's own knowledge, and a
  rewrite that is unusable (too short, a refusal, identical to the original) is discarded in favour of
  the user's own words.
- **Every picture of the chat stays in the memory.** `ConversationMemory` rebuilds what the model receives on
  every turn: the last 30 messages plus the pictures of this conversation — your attachments and the pictures
  the app generated, each file counted once, oldest first, capped at `ImagePolicy.maxPicturesPerRequest` so
  one request cannot explode. When a chat holds more pictures than fit, the selection keeps **the very first
  picture of the chat** and the newest ones after it, so "the first photo" always means the picture you sent
  first. "Why is the sky grey there?" after a generated image and "and what is on the right of the
  photo?" after a photo therefore reach the vision model *with that picture*. A picture whose file
  vanished is left out of the message and out of the byte list at the same time, so text and image can
  never drift apart.
- **Any picture of the chat can be worked on.** Requests may address the pictures by position — "transfer
  the colour from the second photo onto the first one", "give the third photo the colour of the first",
  "make the object in photo 4 exactly as big as the one in photo 1", "take the background of the second
  photo for the fourth" — or point at the photo attached to the request itself ("the photo I am sending you
  now"). The numbering is spelled out twice so the model cannot guess: `memory_prompt` tells the chat model
  that image 1 is the oldest of the selection and the last one the newest (and that a question without a
  number means the newest), while `edit_frame_multi` tells the image model that the **first** image is the
  one to edit and the rest are templates only.
- **Pictures feed the diagram, not only the chat.** The diagram wish is decided before the image router, so
  "plot the values from the photo as a chart" or "make a line chart out of it" now lands at
  `ChartPlanner` with the picture attached: the planner reads labels and numbers off the image, and the
  researched `## DATA` block still wins wherever both are present. Nothing is estimated — the chart shows
  what was on screen.
- **Image wishes read the conversation.** "create a picture out of this information", "paint it again at
  night": `ImagePromptComposer` notices the reference and has the chat model turn the earlier answer
  into one self-contained prompt before the image model is called, because that model never sees the chat.
  A request that already stands on its own costs no extra call, and a refusal or a plain echo of your
  words is discarded in favour of what you typed.
- Rewrites and composed prompts are logged on device as `CTX rewrite …` and `CTX bild …` lines in
  `Documents/flow_trace.txt`.

### Images
- Attach photos from camera or gallery; the vision model (e.g. qwen3.8-max) sees them
- No switch, no toggle, no separate mode: what you type decides whether you get a
  picture. There is no image-AI on/off control anywhere in the UI.
- **AI image generation**: ask in plain text — "create a picture of …", "generate a
  picture of …", "draw a logo" — and the message goes to the image model
  (e.g. wan2.7-image); when your wording points back at the conversation ("of that", "from this
  information"), that conversation is folded into the prompt first. A message without attachments
  becomes an image request as soon as it pairs a creation verb with a picture noun (the German and English
  keyword lists live in `IntentHeuristics.imageCreation` and `IntentHeuristics.imageSubject`)
- **AI image editing**: attach an image and describe the change
  ("make the mouse blue") — the image is edited in place, not regenerated
- Smart intent router: every image + instruction is classified as
  EDIT / CREATE / CHAT by the text model, so plain questions about a
  photo still go to the vision chat; if the classifier returns no answer, a
  keyword fallback still routes obvious "create something new" requests to the
  image model and everything else to chat.
  An explicit diagram wish is never hijacked by that router — it goes to the chart flow, with the picture as
  its data source
- **Any picture can be worked on like that.** Because the memory carries the chat's pictures, a request may
  address them by position or point at the photo attached to the request itself. The image model never
  decides which picture to redraw: `PictureDirector` looks at the numbered pictures first (each one labelled
  `BILD n`, the freshly attached ones marked *just sent by the user*), answers
  `{"edit":n,"reference":n,"instruction":"…"}` and the app then sends **the target picture alone** to the
  generator, with that instruction. The director is told which place each shown picture has inside the chat, so
  counting from the first picture works even when a long chat dropped pictures out of the selection; if the
  picture the request names is not among the shown ones it answers `{"edit":null}` and the app says so instead
  of editing a random picture (`picture_out_of_memory`).
  **The counting itself is no longer left to the model.** `PictureOrdinals` reads the ordinals of the request
  ("das dritte Foto", "the second picture", "photo 2"), maps them onto the chat places and hands the director
  an authoritative line with the result (`HINWEIS DES PROGRAMMS: Chat-Platz 3 = BILD 2`); the answer is then
  checked against that mapping and the director is asked a second time when it named other numbers. Measured
  before this existed: in a chat whose picture budget had dropped one picture, "die Farbe des dritten Fotos"
  was taken as the third *shown* picture and the target came back in the wrong colour (`farbe_ok=false`).
  A size wish is written as a share of the canvas ("the object spans about 62 % of the canvas height") and
  the director may not name the template's outline, shape or colour in the instruction — the generator
  otherwise draws the template's object next to the target's (`fremde_formen_ok`).
  The template deliberately does not travel with it: two
  input images made the provider pick the wrong base now and then (measured on device — the template came back
  edited although the target was listed first), so the director has to write the taken property down in exact
  words instead ("the dark antracite grey of the template", "the object filling two thirds of the height", and
  always the property of the named *object*, not of its background) plus what must stay untouched (its own
  outline, shape, position, background). Only when the director cannot be understood does the request go out
  with all pictures, where `edit_frame_multi` states that the first image is the target.
- Follow-up edits: right after an image answer, just say "make it darker" —
  the previous result is picked up as the input image, no re-attaching. Attach or pick up to four pictures
  in one message (`+` → Photo) when you want to compare or merge them in a single run
- **Tap any picture** — attached or generated — and the full-screen viewer opens it: pinch to zoom,
  double-tap to jump straight to the detail (double-tap again to fit), drag to pan while zoomed, and
  page through the other pictures of that message with the arrows at the bottom. The viewer decodes
  the stored JPEG itself (up to 2000 px), so zooming reveals real detail instead of the bubble
  thumbnail, and closing the viewer leaves the chat exactly where it was
- Long-press any generated image → "Edit" to send it back into the input bar
- Save results to the Photos app (button or context menu)

### Sharing pictures and saving answers
- Long-press any picture in the chat — generated or attached — and choose
  **“Send via AirDrop”**: the system share sheet opens with AirDrop in the front row, so the
  image goes straight to another Mac, iPhone or iPad without first saving it to the photo library
  (the sheet also offers Messages, Mail, Notes, “Save to Files” and printing).
- What is handed over is the stored JPEG file itself, not a re-encoded thumbnail, so the
  receiver gets the same bytes the app shows. If the file has been cleaned away in the meantime,
  the app says so instead of sharing an empty attachment.
- Every share flow runs through the same closer, so the chat is in front again by itself: a picture
  to AirDrop, an answer saved as a file and a hand-over to WhatsApp, Mail, Notes, printing or
  “Save to Files” all tear the whole share presentation down — the sheet, plus whatever window
  the sheet opened above it.
- The instant the picture is handed over to AirDrop that happens. The transfer itself keeps running
  in the system: the file still arrives on the Mac although the app already shows the chat. iOS never
  reports an AirDrop delivery to the app (`completionWithItemsHandler` stays silent, measured on
  device), so the hand-over event of the activity item source is what closes the windows — no timer,
  no time window.
- Activities that keep their own picker inside the app (“Save to Files”, Mail, Notes, printing)
  must not be torn down while you are still choosing, so they close the sheet as soon as the system
  reports that activity back.
- Share extensions that switch to another app first — WhatsApp and friends — leave the sheet
  standing behind them, so that one closes the moment the app is back in the foreground, and only if
  a file was handed over before. Pulling down the notification centre mid-choice therefore keeps the
  sheet open.
- A sheet the system already tore down is never dismissed twice, and one share never closes twice.

### Histories and storage
- The header's list button opens "Histories": every conversation with its date, message
  and image count and its size on disk. Tap to open, swipe to delete one.
- Long-press any message → "Delete message" removes exactly that message.
- "Delete all histories" (in the history sheet or in Settings → Storage) removes every
  conversation, the one you are reading included, and immediately opens a fresh empty chat.
  The confirm dialog names the counts and the megabytes before anything happens, and
  "Undo" puts all chats back in their old order with the one you were reading open again.
- Deleted pictures are moved to `Documents/.trash` first, so the snackbar's "Undo" restores the
  conversation and the files. The snackbar times itself out after 5 s (`HistoryCleaner.defaultUndoWindow`)
  and the trash is emptied at that moment; anything still pending is erased on the next app start.
- A picture file is only freed when no remaining message references it any more.
- Settings → Storage shows the same numbers (images, histories) at a glance.

### Calendar control
- Create, change or delete appointments from chat:
  "Book a dentist appointment tomorrow at 2 pm, one hour, practice Am Markt",
  "move my dentist appointment to tomorrow 16:30", "delete the meeting with Karin"
- Real calendar notifications, not just notes: "first alert 1 hour before,
  second alert 2 hours before" adds matching alarms to the event; naming them
  on an existing appointment replaces them ("alerts every day at...",
  "remove the reminders")
- Relative dates ("tomorrow", "next Monday") are resolved against the device clock
- **Private or work**: "make the dentist appointment private", "book that in my work calendar",
  "book the appointment privately" — the app maps that onto the calendars that actually exist on your
  iPhone (Private, Work, Personal, Home, Homeoffice, …). Saying nothing
  files a new appointment in the **work** calendar, and an existing appointment keeps its calendar
  unless you ask to move it
- "set the calendar to private" on an appointment that already exists moves it there
- A calendar wish never ends up as a note: if the router files `privat` into the note field anyway,
  the app moves it into the calendar choice and drops the note — including a leftover note like
  `privat` from an older appointment, which is cleaned up while moving it
- A calendar you named that does not exist is reported instead of guessed, and the answer lists
  the calendars you have
- Asks for calendar permission on first use
- Every successful action is confirmed in chat with the full appointment data
  (title, day, start–end time, location, calendar)
- Questions about the calendar ("what's on tomorrow?") stay normal chat

### Voice
- Voice input (ASR): the mic button records, transcribes and sends in one step
- **Abort a dictation**: while the mic is recording — or while the recording is being transcribed — the
  send button on the right shows a stop square instead of the arrow. One tap discards the dictation:
  nothing is sent to the model, no message appears in the chat, and an attached picture stays in the
  input bar so it can be dictated again. A transcript that arrives *after* the abort is dropped as well
  (`VoiceTranscriber.cancel()` bumps a session counter the running hand-over is checked against), the
  temporary recording file is deleted and the countdown stops. Once the dictation is through — sent or
  discarded — the button is the normal send control again
- Read-aloud of answers (TTS), toggleable per chat
- German: uses the iOS system voice — the cloud audio model's German TTS is not
  good enough yet (its voices are Chinese/English only), so read-aloud falls
  back to AVSpeechSynthesizer and speaks with whichever German voice is
  configured on the device (Settings → Accessibility → Spoken Content →
  Voices → German); the gender shown in Settings mirrors that voice. Note:
  Siri voices (e.g. "Siri, Stimme 2") are not exposed to third-party apps by
  iOS — if one is selected, Apple substitutes the standard voice for the
  language (e.g. Anna). Pick a downloaded (enhanced/premium) non-Siri voice
  to have the app use exactly that voice.
- English: uses the cloud audio model voices (male daniel / female hannah)

#### Hands-free voice trigger (Action button)

Opening `gwenmobile://listen` (registered URL scheme) launches the app and
starts recording immediately. iOS does not let third-party apps listen for a
wake word in the background, so you bind the URL to a physical button once:

1. Create the shortcut: open the Shortcuts app → tap **+** → search for the
   "Open URL" action → add it → tap "URL" in the action and enter
   `gwenmobile://listen` → tap **Done** (top right). Optional: rename the
   shortcut to "Gwen listen".
2. Assign it to the Action button (the small button on the left edge above
   the volume keys, iPhone 16 and later): open Settings → search for
   "Action Button" → choose "Shortcuts" → "Select a Shortcut" → pick your
   shortcut.
3. Use it: press the Action button once → GwenMobile opens and records right
   away (orange mic dot in the status bar). Speak, then tap the red mic to
   send — or tap the stop button next to it to throw the dictation away.
   Recording stops and transcribes automatically after 28 s (the ASR
   server rejects longer audio) — a countdown appears over the input bar in
   the last 10 s.

No Action button on your device (iPhone 15 and earlier)? Use Settings →
Accessibility → Touch → Back Tap → Double Tap → Shortcuts instead, or just
the mic button in the app.

### Settings
- Endpoint picker (Token Plan, DashScope intl/US/CN, EU workspace) + custom base URL
- Model pickers (chat, vision, image, audio) populated from your account (GET /models) — the
  **vision** picker lists only the models whose image input the provider really confirms
  (see *Vision models that actually see*)
- **Thinking depth** for the chat model (*Denktiefe*) — the levels your provider actually confirms for it,
  plus *Model default*; the footer says how many levels were confirmed or points at "Load models from
  account" while they are still unknown (see *Thinking depth*)
- Language, read-aloud toggle, connection test

<img src="docs/screenshots/03-settings.png" alt="Settings sheet: language picker, Qwen Cloud API key field, endpoint picker with base URL and the model pickers" width="270">

*The settings sheet, reached through the gear in the header.*

## Requirements
1. Xcode from the App Store (~40 GB, one-time).
2. A Qwen Cloud account: create an API key at https://home.qwencloud.com/api-keys

## Build & run on your iPhone
```
cd ~/GwenMobile
xcodegen generate          # regenerate the project after file/project.yml changes
open GwenMobile.xcodeproj
```
- Target GwenMobile → Signing & Capabilities → Team = your Apple ID
  (free account is enough for your own device; provisioning expires after 7 days).
- Connect the iPhone, select it as destination (not a simulator), press Run.
- First launch: Settings (gear) → paste API key → "Test connection".
- From the terminal: `xcodebuild ... build` + `xcrun devicectl device install app ...`
  (needs `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).

## Tests
The `GwenMobileTests` target holds the unit tests (pure logic: audio codec, intent
heuristics, routing, request building, response decoding, error translation, localisation, storage, conversation store, conversation persistence, conversation memory, routing context, stream throttling, the
stream retry policy, the picture ordinal mapping, the research digest, answer export, the
waiting-indicator rhythm, the share presentation closer, thinking levels and the provider level probe,
the picture viewer (preview target, zoom geometry, page loading)).
No network, no device. The features that need a microphone, a camera or the real account are driven
by the device probes below instead.
```
xcodegen generate
xcodebuild test -scheme GwenMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Vision models that actually see
- Long-pressing the vision picker used to offer every text model of the account, and that is wrong:
  `deepseek-v4-pro`, `deepseek-v4-flash-0731` and `glm-5.2` **accept** an image part without complaining
  and simply never look at it. Measured with a 24×24 px solid-colour PNG and a one-word "what colour is this
  picture?" question: green picture → "black" (glm-5.2), "turquoise"
  (deepseek-v4-pro), "white" (deepseek-v4-flash-0731) — and the same answer or a shrug for the magenta
  picture. Their `usage.prompt_tokens` doesn't even grow when the picture is attached (18 vs 19,
  17 vs 10), i.e. zero image tokens were taken in. `qwen3.7-max` is stricter and refuses the request:
  400 "The provided messages input is invalid. The error info is [Unexpected item type in content.]".
- The detection therefore asks the provider instead of reading model names: one tiny request per text
  model with that picture attached, and the answer's `usage.prompt_tokens_details.image_tokens` decides.
  Measured on the account: **qwen3.8-flash, qwen3.8-max, qwen3.7-plus and qwen3.6-flash report 66 image
  tokens and name the colour correctly ("green", "magenta")** → `supported`; the blind ones report no
  `image_tokens` → `rejected`; `qwen3.7-max` answers 400 → `rejected`; a 500, a timeout or a missing
  answer stays `unknown` and hides nothing (a broken network must not remove working models from the list).
- Consequences in the UI: the vision picker offers only `supported` models, the section footer states
  how many of the account's models see pictures, and if the stored vision model turns out to be blind it
  is repaired to the first working one while the list is being probed. A model that was never probed is
  never hidden — until the first probe the picker still shows the whole text list.

### Thinking depth
- Every Qwen chat model on the account endpoint reasons before it answers, and it does so **without any
  limit** unless the app says otherwise: the same arithmetic task ran **355 s / 61 556 characters** of
  reasoning when nothing was sent, and **11,9 s** with the thinking switched off. Settings →
  **Thinking depth** is the dial for that.
- The app does not guess which levels exist. `GET /models` answers with `id`, `created`, `object` and
  `owned_by` only — no capability field, and there is no model-detail endpoint — so the levels are
  **probed** while the model list loads: a request with an impossible `reasoning_effort` is rejected
  before a single token is generated, and the rejection names the values that model accepts
  (`'none', 'minimal', 'low', 'medium', 'high', 'xhigh'` — plus `'max'` on qwen3.8, glm-5.2 and
  deepseek-v4, while deepseek-v4-pro has no `none`/`minimal` at all). A second token-free probe tries
  `enable_thinking: false` and only marks a model switchable when the answer really comes without a
  reasoning block.
- The picker therefore shows exactly the levels of the selected chat model, always plus *Model default*
  (send nothing). Until a model has been probed the list is limited to the four levels every
  account model was measured to accept (`Low` … `Extra high`), which keeps the setting useful on a
  fresh install without risking a rejected request.
- One choice, one key: the provider rejects `reasoning_effort` and `thinking_budget` in the same body
  ("cannot be set simultaneously") and demands `reasoning_effort: none` whenever
  `enable_thinking: false`, so the app builds the body from a single directive that can never emit two
  thinking keys — covered by `ThinkingLevelTests.testNeverBothThinkingKeysInOneBody`.
- Models that expose no thinking control at all (image generation, audio) simply keep *Model default*;
  nothing is hidden and nothing is promised. Those models cannot be picked for vision either
  (see *Vision models that actually see*).
- Every internal helper request the app fires beside the answer — image-route classification, follow-up
  rewriting, image-prompt composition, calendar planning, chart planning — runs with thinking off,
  because each of them expects a single word or one JSON object (measured 1,6 s instead of 10,7 s on
  qwen3.7-max). The chosen depth applies to the visible answer only.
- The bubble signature under an answer shows the depth that produced it
  (`qwen3.8-flash · 26.9 s · Medium`) and is stored with the message, so a re-read chat still tells
  you how each answer was made. A *Model default* turn shows no depth at all.

### Debug-only feature sweep
`sweep` runs every backend feature once against the real account and writes a report to
the app's Documents folder (`flow_sweep.txt`):

```
xcrun devicectl device process launch --device <UDID> --terminate-existing \
  --payload-url "gwenmobile://test/sweep" com.mortis.gwenmobile
xcrun devicectl device copy from --device <UDID> --domain-type appDataContainer \
  --domain-identifier com.mortis.gwenmobile --source Documents/flow_sweep.txt \
  --destination /tmp/flow_sweep.txt
```
Covered: model list, chat answer, `[[SEARCH]]` trigger, web search + page reads +
research answer, calendar permission status and plan JSON (read-only, no event is
written), image editing, text-to-image, cloud TTS, ASR transport
(silence), conversation persistence and counts. It needs a stored test image
(`img_0B85747A-BAA.jpg`) for the edit probes and skips them when absent.

### Debug-only UI flow tests
Debug builds answer the URL scheme `gwenmobile://test/<scenario>` and drive the real
chat UI on the device (perf regressions for typing, scrolling and image edit).
Scenarios: `typetest`, `scrolltest`, `camtypetest`, `camflow`, `followup`,
`tripleedit`, `bigedit`, `reopenbig`, `editbig`, `camtrans`, `chartprobe` (real web search,
follow-up rewrite and chart generation, report in `Documents/chart_probe.txt`) and
`searchonce` (one researched answer, then asserts the "Searching the web" capsule is gone —
report in `Documents/search_once.txt`, `kapsel=nil` is the passing state) and `exportprobe`
(real answer, then the rendered export: file name, `<strong>`/`<p>`/`<a href>` counts and whether any
raw `**` survived — report in `Documents/export_probe.txt`) and `airdropprobe`
(stored JPEG of the newest chat picture handed to the share sheet through the real `Presenter`
path, then the presentation chain is polled until it is gone — `Documents/airdrop_probe.txt`
reports every chain change and ends with `chatSichtbarWieder=true` once the AirDrop hand-over
closes the sheet and the AirDrop window by itself),
`menushow` (opens the "+" menu and leaves it open, for screenshots), `viewerprobe` (opens the picture
viewer for the largest stored chat picture, leaves it on screen and measures the real presentation —
decoded edge in px, fit/min/max scales, the centring gap in pt, the scale after a double-tap and after
the second one — into `Documents/viewer_probe.txt`, plus `viewer_probe_fit.jpg` and
`viewer_probe_zoom.jpg` grabbed from the live window), `capsprobe` (probes every text
model of the account the way the settings screen does — thinking levels, switchability and whether the
model really takes in a picture — and writes one line per model plus the resulting vision list to
`Documents/model_caps_probe.txt`), `chartguard` (real conversation: an answer, then the diagram request,
then the two follow-ups that only ask about the chart already on screen — where its statistics and its
values came from — and the positive control that asks to redraw the chart with the 2025 numbers; passing is
`bilder=0` for the two questions and
`bilder=1` for the control, report in `Documents/chart_guard.txt`), `picsweep` (the real picture matrix
against the real account: five probe pictures (distinct shape, object colour and background, drawn by the
probe itself into `Documents/images/` so no external file can be cleaned away) are posted into one fresh
chat, then each case runs
through the normal send path — colour transfer both ways, the photo that is attached to the request itself,
"make the object of photo 4 exactly as big as the one in photo 1", background transfer, the picture-budget
overflow, plus the negative control "what do you see on the first photo?" which must not produce a picture.
Every case is graded by two further vision calls over the finished JPEG (`form_ok`, `farbe_ok`,
`fremde_formen_ok` — the last one fails when an object of another picture leaked into the result) and by the
mean RGB and edge length measured on the device,
`Documents/picture_sweep.txt` holds one line per case and the
`flow` log holds the `BILDZIEL` line with the target and the template of every director decision, plus a bare
`gwenmobile://test/<attachment-file-name>` for a single image. They assume the conversations and image files of the reference
device exist in the app sandbox (`img_0B85747A-BAA.jpg`, `img_7924D952-6BF.jpg`) and
log to the `flow` os-log subsystem. Release builds contain none of this code
(`GwenMobile/DebugFlowTests.swift`, `GwenMobile/DebugSweep.swift` and `GwenMobile/DebugFeatureProbes.swift` are `#if DEBUG`).

### Debug-only feature probes
The same URL scheme starts the end-to-end probes that cover the paths no unit test can reach —
each writes its own report into `Documents/`:

| Scenario | Covers | Report |
|---|---|---|
| `webask` | the real send path with a research question ("Wer hat den Eurovision Song Contest 2026 gewonnen?"), its sources, the capsule gone | `web_ask.txt` |
| `webchart` | search → chart in one sentence (the case that used to refuse), picture + points + sources | `web_chart.txt` |
| `phototext` | a photographed text handed to the vision model and translated; asserts the router chose chat, not image edit | `photo_text.txt` |
| `editype` | **typing in the input field while an image edit is running** — per-keystroke milliseconds, render counters, job result | `edit_type.txt` |
| `typetest` / `scrolltest` / `camtypetest` | typing with the keyboard open, scrolling a heavy chat, typing with an attachment pending | `flow_trace.txt` |
| `historywipe` | delete one chat, one message, all chats — with the undo receipt, the file trash and the 5 s expiry | `history_wipe.txt` |
| `micrec` | the real microphone path: permission, recorder states, the countdown, an empty transcript as the honest result | `mic_rec.txt` |
| `micloop` | the device speaks its own TTS into its microphone — read-aloud **and** recognition in one run | `mic_loop.txt` |
| `ttsp` | cloud TTS through `AVAudioPlayer`: when playback starts, when the delegate ends it | `tts_play.txt` |
| `voiceabort` | the path behind the stop button: `cancel()` while recording and while the audio is handed to ASR — nothing in the chat, no late transcript, attachment kept | `voice_abort.txt` |
| `calwrite` | a real appointment created, changed and deleted again through the same `CalendarService.perform` the chat uses | `calendar_write.txt` |
| `tlsretry` | the streaming retry: a failing certificate is retried once, an unknown host is not | `tls_retry.txt` |

`micloop`, `ttsp`, `voiceabort` and `calwrite` touch the real world (microphone, speaker, calendar);
`calwrite` removes its own appointment again. `historywipe` deletes every conversation and, once the
undo window has passed, the picture files that no chat references any more.

Every scenario and probe can also be started without the URL scheme, which is useful when
`devicectl` is unavailable and the app has to be launched through `dvt launch`:

```
python3 -m pymobiledevice3 developer dvt launch "com.mortis.gwenmobile -gwenflowtest scrolltest"
```

Debug builds additionally write a main-thread trace to `Documents/flow_trace.txt`
(`MARK` = flow events, `STALL`/`STALL_END` = main-thread blocks longer than 400 ms with
render counters, `STATS` = counters every 2 s). The stall heartbeat is a `Timer` in
`.common` run-loop modes, so it keeps reporting while a touch is tracked:

```
python3 -m pymobiledevice3 apps pull com.mortis.gwenmobile Documents/flow_trace.txt /tmp/flow_trace.txt
```

### Measured on the device (12.09.2026, iPhone 16)
Everything above was run against the real account on the reference device, not only in the simulator:

- **No main-thread stall in any run.** Every probe was started and its `flow_trace.txt` pulled before the
  next launch: `STALL` never appeared — 0 hits across all runs, including 150 keystrokes with the keyboard
  open (three rounds of a 50-character sentence), a 42-message chat scrolled to the end and back three
  times, and an image edit that took 57,6 s while 28 characters were typed into the field next to it
  (`schritt_max_ms=0`, the heartbeat counter kept running).
- **Picture matrix 8/8** through `picsweep`: colour transfer both ways, the freshly attached photo, the
  size transfer, the background transfer, the budget overflow, the negative control that must not draw.
  Two of those cases failed before the ordinal mapping and the size wording above were introduced
  (`fremde_formen_ok=false`, `farbe_ok=false`) and pass with them.
- **Voice round trip**: `micloop` had the phone play its own TTS sentence into its microphone and the
  provider returned "Die Kernfusion verbindet leichte Atomkerne" as "The can fusion verbindet leichte
  atomkerne" — recognition and read-aloud in one measurement; `ttsp` shows playback ending after 5,5 s.
- **Input bar geometry**, measured off a device screenshot at @3x: mic circle 102 px = 34,0 pt,
  send/stop circle 102 px = 34,0 pt.
- One caveat worth knowing: a transient `secureConnectionFailed` from the provider still surfaces as a
  friendly error when both attempts fail (measured 2 of 4 attempts of one research question), and the app
  then stores the translated hint instead of an answer — retrying is one tap away.

## Notes
- `GwenMobile/Info.plist` is the single source of truth for bundle configuration  (privacy texts, URL scheme). It is not generated — edit the file, `project.yml`
  only points at it via `INFOPLIST_FILE`.
- Default base URL: https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1
  (Token Plan account, live-tested: chat, vision, image edit, calendar routing).
- Models: qwen3.8-flash (chat/routing), qwen3.8-max (vision), wan2.7-image
  (generation/editing), qwen-audio-3.0-realtime-plus (ASR + English TTS).
  Exact names must exist in your account — check via GET /models; API errors
  are surfaced in the app's error dialogs.
- Image editing is framed with an explicit "edit only, keep composition" instruction (and, for several
  pictures, "the first image is the target") so the model edits your photo instead of generating a new one.
- All API errors run through one translator: a short message in the app
  language (invalid/expired key, unknown model — named —, rate limit, offline)
  plus the raw code as a small detail line; key/model errors add an
  "Open Settings" button to the alert.
- Camera and calendar permission dialogs only work on real devices (not simulator).
- Generated image URLs expire after ~24 h; the app downloads and stores them
  immediately into its sandbox.
- Nothing heavy runs on the main actor: picture payload encoding, response decoding, conversation
  persistence, HTML stripping of web pages and audio conversion all go through `Offload.run`, which
  executes the work on a detached task. Deliberate exceptions that stay on the caller's thread because
  the result is needed before the next user-visible step: `AnswerExporter.write` (before the share sheet
  opens), `HistoryCleaner`'s trash bookkeeping (before the undo receipt is published), the keychain
  round trip in `AppSettings`, the launch decode in `ChatStore.init` and `AVAudioSession`
  configuration around playback.
- Conversation storage lives in its own unit (`ConversationPersisting` /
  `ConversationFilePersistence`): the debounced write runs off the main actor, serialised through a
  write chain so an older snapshot can never land after a newer one, while `flushPendingSave()` keeps
  writing synchronously when nothing is in flight — the history is on disk before the app is backgrounded.
- A connection that dies during the TLS handshake is retried **once** after 1200 ms — on the plain
  requests (`HTTP.data`) and, since the same policy was pulled into `HTTP.isConnectionReset`, on the
  streaming answer too (`QwenAPI.streamReset`). Never once the first token has arrived: a half-streamed
  answer is not restarted, and cancellation, timeouts and offline stay untouched (measured with
  `tlsretry`: 1941 ms for a failing certificate, no retry for an unknown host).
