# First steps

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
- Tap the **waveform** button next to the ear at the top of the chat (or Settings → Voice & voice control → *Voice control* → *Conversation mode without signal word*), then just talk: a recognized sentence stops the answer immediately, and the sentence becomes the next turn.
- Optional: open **Settings → Voice & voice control → Voice control → Voice profile**, record three short samples and switch on
  **Only my voice**. Conversation mode then ignores other speakers before they can interrupt the answer or become a
  turn.

## Several tasks in one message

A message can hold as many tasks as you like. Tasks that only read or fetch and need nothing from the others run
at the same time — two questions, a web lookup beside a weather card, several separate pictures — while dependent
tasks and everything that writes to the device or changes a picture wait their turn. The visible order stays the one
you wrote. The stop button cancels everything that runs at that moment — a price search, a picture being generated
or a streaming answer stops there — and leaves out the tasks after it.

## Answers

Long-press an answer → *Copy answer*, *Save as file* (rendered HTML under Files → GwenMobile → answers, plus the
share sheet) or *Delete message*; the copy icon next to the signature line (model, seconds, thinking level) takes the
raw text.

## Voice

- The microphone button shows your words live. End with the **stop word** (*Jetzt senden* / *Send it now*) to send
  at once, or with the **cancel word** (*Jetzt abbrechen* / *Cancel that*) to discard; otherwise it sends after a
  short pause.
- **Conversation mode without a signal word** is switched in Settings → Voice & voice control → *Voice control* or with the **waveform**
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
- **Personal Voice — your own voice** (Settings → Voice & voice control → *Personal Voice*):
  GwenMobile cannot create or import a voice; first create it in iOS under **Settings → Accessibility → Personal
  Voice → Create a Personal Voice**, turn on *Allow Apps to Request to Use* and allow GwenMobile in that panel.
  Then open Settings → Voice & voice control, tap *Use Personal Voice* and confirm the iOS permission prompt: GwenMobile lists the
  voice with the output voices, selects it and offers *Hear a sample*. It is then used for read-aloud, spoken
  confirmations and briefings. Use *Check again* after creating the voice, after iOS has finished processing it or
  after turning the permission on; if the voice still does not appear, restart GwenMobile once. The voice stays on
  the device and is never sent to a provider; it is not the Voice profile for *Only my voice*. Apple currently
  supports English (U.S.), Mandarin Chinese (China mainland) and Spanish (Mexico), not German; if the voice language
  differs from the app language, the app shows a hint.
- **Only my voice** (Settings → Voice & voice control → *Voice control* → *Only my voice*) adds a local speaker check to conversation mode.
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
- **Listening mode** (Settings → Voice & voice control → *Voice control*, or the **ear** button at the top of the chat — tap on, tap off,
  always in step with the switch in Settings): say the **wake word** (*Hey Computer*) followed by your request;
  a randomly chosen spoken confirmation (*I hear you* / *Yes?*, localized) tells you it is listening, a falling
  tone that your request arrived — the request tone can be swapped for one of the system sounds of your iPhone or Mac
  in Settings → Voice & voice control → *Voice control*. The confirmation is spoken in the app language and is not captured into the request;
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
- The six words — wake, stop, cancel, new chat, delete-history and listening off — can be changed in Settings → Voice & voice control → *Voice control*;
  the new-chat and the listening-off word take several variants separated by commas. The delete-history word is only a hint for the router, not a fixed signal.
- **Siri:** "Hey Siri, Gwen hör zu" (English: "Hey Siri, Gwen listen") opens GwenMobile and starts listening. "Gwen"
  is registered as an alternative name for the app, so "Hey Siri, Gwen" is offered too — whether iOS then starts
  listening or only opens the app is up to Siri. Open the app once after installing so iOS learns the phrases.
  The URL `gwenmobile://listen` does the same from the Action button or Back Tap.
- **Your own Siri word:** iOS only allows an app built-in phrases that contain its name, but a shortcut can be called
  anything. In the **Shortcuts** app tap **+** → *Add Action*, search for *GwenMobile* and pick *Listen* (German:
  *Zuhören*); then tap the shortcut's name at the top and rename it — for example *Jarvis*. From then on
  "Hey Siri, Jarvis" starts listening. The button in Settings → Services → *Your own Siri command* opens Shortcuts for you. Pick
  a name Siri understands well and that is not already a Siri command.

## Phone calls

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
  [DEVELOPMENT.md](DEVELOPMENT.md#phone-calls-and-the-default-dialer).

## Text messages

- Say or type whom to write to and what — "Schreib Mama, dass ich später komme", "Send Peter an SMS: on my way".
  GwenMobile finds the contact like for a call (and asks back when two fit) and fills in the message.
- With a free Apple ID the Messages form opens ready to go and you tap **Send** — Apple lets only you send from it.
  The form needs GwenMobile open; asked from the background, the answer asks you to open the app and say it again.
- Sending **without a tap** needs a paid Apple Developer Program membership, iOS 26 and an account and device in
  the EU: write `GWEN_MESSAGING = YES` into `Config/Signing.xcconfig`, install again and choose GwenMobile as the
  default carrier messaging app in the iOS Settings. According to Apple, GwenMobile then also receives your SMS.

## Music

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

More detail: [FEATURES.md](FEATURES.md) · Back to [README](../README.md).
