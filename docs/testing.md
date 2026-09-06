# Testing ReVox Mobile

Thank you for trying ReVox. This page explains how to install the app through TestFlight, what to expect the first time it runs, how to use it and how to send feedback. No technical knowledge is needed.

**What ReVox does:** it listens to speech (from the microphone, or from other apps on your phone) and translates it into English on the phone itself. It shows the translation as text, reads it aloud, and keeps a transcript. Nothing you say or listen to leaves the phone.

**What you need:** an iPhone 12 or newer running iOS 17 or later, and Wi-Fi for the first launch.

**A note on early builds:** ReVox is being built in stages. A build may not yet include every feature described here; the notes shown in TestFlight for each build ("What to Test") say what is new and what to focus on.

## 1. Install TestFlight

TestFlight is Apple's free app for trying apps before they reach the App Store. Install it from the App Store: [TestFlight](https://apps.apple.com/app/testflight/id899247664).

## 2. Get ReVox

You were invited in one of two ways:

- **Email invitation (internal testers).** Open the email from TestFlight on your iPhone and tap **View in TestFlight** (or **Start Testing**). If TestFlight asks for a redeem code, it is in the same email. Accept, then tap **Install**.
- **Public link (external testers).** Open the link you were sent on your iPhone. It opens in TestFlight; tap **Accept**, then **Install**.

From now on new builds arrive automatically. TestFlight shows a notification when there is a new one; you can also open TestFlight and tap **Update** next to ReVox. Each build expires 90 days after it was uploaded, so keep updating.

## 3. First launch

ReVox opens on the **Live** tab with "Ready to translate". Before the first translation it needs a Whisper model: go to **Settings → Models**, tap **Download** on **small** (about 487 MB; the row shows a progress bar and the phase). Keep ReVox open until the row says **Installed** — a download interrupted by leaving the app shows **Paused** and resumes when you come back. The **Voice detector** row installs by itself with the first model. Nothing else is downloaded afterwards; the app works in airplane mode from here on.

## 4. Translate from the microphone

1. On **Live**, the source picker shows **Microphone**; **Other apps** is covered in section 5.
2. Tap **Start**. iOS asks for microphone access the first time; allow it. If you refused, the screen shows a banner with **Open Settings**.
3. Speak a sentence in Spanish, French, German or any other language. After a short pause the English text appears with the detected language badge, and the system voice reads it aloud. The status line shows the model ("small · ready") and the voice ("System voice — pocket-tts not downloaded").
4. Long phrases are cut at about 10 seconds; if translation falls behind, a **Falling behind** badge appears and the transcript shows "… skipped: falling behind".
5. The speaker icon in the toolbar mutes the voice; the transcript keeps running. **Settings** has the same toggle, the latency mode (Balanced / Fast) and a source-language pin for when auto-detect picks the wrong language.
6. Lock the phone or switch apps: translation keeps running until you tap **Stop**.

## 5. Translate other apps (broadcast)

ReVox can also translate audio from other apps: a video, a podcast, a game (not phone or FaceTime calls, which iOS does not share). Because of how iOS works, you must start a **screen broadcast** that sends the other apps' audio to ReVox:

1. On the **Live** tab choose **Other apps** and tap **Start**. A box with a round broadcast button appears with the text "Tap to choose ReVox and start the broadcast."
2. Tap the round button. iOS shows a small sheet; make sure **ReVox** is selected and tap **Start Broadcast**. After a three-second countdown the status bar (or the Dynamic Island) shows a red indicator: the broadcast is running, and the box disappears.
3. Switch to the app you want to listen to and play the audio. ReVox translates in the background and speaks the English over it, turning the other app's sound down while it speaks. If the status line says "No audio from the app (some players are not captured)", that app's player does not deliver audio to broadcasts (Safari, Music and some video players); try another app.
4. The same broadcast can also be started from **Control Center**: press and hold the **Screen Recording** control (the circle within a circle), choose **ReVox** in the list, and tap **Start Broadcast**. If you do this while ReVox is closed, open ReVox within a minute: it joins the broadcast and shows "Joined a broadcast in progress".
5. Locking the iPhone with the side button ends the broadcast (iOS behaviour, not ReVox's); the status line then says "Broadcast ended". Locking by waiting for auto-lock keeps it running.

Only the audio is used. The screen contents are not saved or looked at. **Settings → Diagnostics → Broadcast diagnostics** shows the numbers a bug report may ask for (write cursor, heartbeat age, levels, source format).

## 6. Stop

- **Microphone:** tap the **Stop** button in ReVox.
- **Broadcast:** tap the red status bar or Dynamic Island indicator and confirm **Stop**, or open ReVox and tap **Stop**, or use the Screen Recording control in Control Center again.

When ReVox is stopped it does not listen, and the red indicator disappears.

## 7. Transcripts

Everything ReVox translated is kept on the phone. Open **History** (the clock symbol) to see past sessions: each row shows the time, the source (Microphone or Other apps), how long it ran, how many lines were translated and the first English line. Type in the search field to find sessions by an English word; the matching line is shown under each session. Tap a session to read the whole transcript; the **Share** button (the square with the arrow) sends it as a text file to Files, Mail, AirDrop or any other app; the **Delete** button removes it after a confirmation. Swipe a row in History to delete just that session, or use **Clear All**. Transcripts contain the translation, and the words as spoken when **Learning** was on; they are stored only on your iPhone and are never uploaded anywhere.

## 8. Send feedback

The easiest way is a screenshot:

1. Take a screenshot while the problem is on screen (press the side button and the volume-up button together).
2. Tap the screenshot preview in the corner, then tap **Share** and choose **Share Beta Feedback**.
3. Describe what you expected and what happened, and send it. The screenshot, your iPhone model, iOS version and the ReVox build number are attached automatically.

You can also open the TestFlight app, tap **ReVox**, and tap **Send Beta Feedback** for feedback without a screenshot. If the app crashes, TestFlight asks whether to send the crash report the next time you open it; please say yes.

Helpful details to include: what you were listening to (the microphone or which app), the language spoken, whether the translation was wrong, late or missing, and whether the phone was locked at the time.

## 9. Voices and ducking (milestone 4 checks)

1. **Download the pocket-tts voice.** Settings → **Voices** → **Download** (about 527 MB; keep ReVox open until the row says Installed). The four voices alba, azelma, cosette and javert appear; tap one to select it, then tap **Play sample** — you should hear "This is ReVox." in that voice. On iPhones with less than 6 GB of memory a note explains that ReVox may switch back to the system voice when memory runs low.
2. **System voices.** Below the pocket-tts section, tap any English system voice to use it instead; **Play sample** works there too. Until pocket-tts is downloaded, and whenever it fails, ReVox uses this voice automatically and the Live status line says why ("System voice — pocket-tts not downloaded", "… failed to load").
3. **Ducking.** Play music in another app, go to **Live**, tap **Start** and speak a foreign-language sentence. While ReVox speaks the English, the music should get quieter and a **Ducking** pill shows in the status line; about a quarter of a second after ReVox stops, the music returns. Tell us whether the music dropped at all, how quickly it came back, and which output you used (speaker, wired, Bluetooth headphones, car).
4. **Settings → Ducking.** Turn the toggle off, tap Start again: the music no longer drops and the status line shows **Ducking off**. Move **Voice volume** while ReVox speaks: the next sentence is louder or quieter. The note under the slider explains that iOS chooses the ducking amount (the Windows ducked-level slider does not exist on iOS).
5. **Mute in the middle of a sentence** (the speaker icon): the voice stops at once, the music comes back to full volume, and the transcript keeps running.
6. **Lock the phone** with music playing and keep speaking for a few minutes: translation and ducking should continue until you tap Stop.

Please report the iPhone model and iOS version with every observation from this section.

## 10. History, export and About checks

1. Translate a few phrases from the microphone, tap **Stop**, open **History**. Expected: one row with the time, "Microphone", the duration, the number of lines and the first English line.
2. Tap the row. Expected: the header (started, source, duration, model, voice, source language) and the same lines you saw on the Live screen, in order.
3. Tap **Share** and choose **Save to Files**. Open the file in Files. Expected: the name looks like `2026-09-14_10-32-05.txt`; the first line starts with `# ReVox session`; each translated line appears after a `→` arrow.
4. Back in History, type one English word from the transcript in the search field, then a word in a different case (for example the same word in capitals). Expected: the session appears with the matching line under it; report whether the capitalised search also finds it.
5. Search for a word that was never translated. Expected: a "No Results" screen, no crash.
6. Swipe a row to the left and tap Delete. Expected: the row disappears with no question. Tap **Clear All**. Expected: a confirmation naming the number of sessions; after Delete, the "No Transcripts" screen.
7. Open **Settings → About**. Expected: the app version, the privacy paragraph, five licence links (WhisperKit, FluidAudio, pocket-tts Core ML weights with the Kyutai attribution, Silero VAD, Whisper weights) that open in Safari, and the two project links.
8. With the microphone permission switched off in iOS Settings, tap **Start**. Expected: a yellow banner with **Open Settings**, no pop-up; after allowing access and coming back, the banner disappears and nothing starts until you tap **Start** again.
9. With VoiceOver on, swipe through the Live screen while translating. Expected: the status line reads as sentences ("Model small ready. Using system voice…") and does not repeat itself every second; a download's progress reads a percentage.

## Tips and known limits

- Translation quality depends on the audio: a clear voice close to the phone works best. Music, several people talking at once or heavy background noise reduce accuracy.
- The phone gets warmer and uses more battery while translating; this is expected for on-device translation.
- ReVox cannot change other apps' volume directly. While it speaks, iOS lowers the other audio by an amount that iOS decides; use the voice volume slider to make ReVox itself louder or quieter.
- Translating other apps requires the screen broadcast to be running. If ReVox goes quiet while a video plays, check that the red indicator is still there.
