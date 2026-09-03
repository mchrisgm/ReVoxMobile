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

1. On **Live**, the source picker shows **Microphone** (the other-apps source arrives in a later build).
2. Tap **Start**. iOS asks for microphone access the first time; allow it. If you refused, the screen shows a banner with **Open Settings**.
3. Speak a sentence in Spanish, French, German or any other language. After a short pause the English text appears with the detected language badge, and the system voice reads it aloud. The status line shows the model ("small · ready") and the voice ("System voice — pocket-tts not downloaded").
4. Long phrases are cut at about 10 seconds; if translation falls behind, a **Falling behind** badge appears and the transcript shows "… skipped: falling behind".
5. The speaker icon in the toolbar mutes the voice; the transcript keeps running. **Settings** has the same toggle, the latency mode (Balanced / Fast) and a source-language pin for when auto-detect picks the wrong language.
6. Lock the phone or switch apps: translation keeps running until you tap **Stop**.

## 5. Translate other apps (broadcast)

ReVox can also translate audio from other apps: a video, a call in another app, a podcast, a game. Because of how iOS works, you must start a **screen broadcast** that sends the other apps' audio to ReVox:

1. In ReVox choose the **Other apps** source and tap the **broadcast picker** button. iOS shows a small sheet; make sure **ReVox** is selected and tap **Start Broadcast**. After a three-second countdown the status bar (or the Dynamic Island) turns red or shows a red indicator: the broadcast is running.
2. Switch to the app you want to listen to and play the audio. ReVox translates in the background and speaks the English over it, turning the other app's sound down while it speaks.
3. The same broadcast can also be started from **Control Center**: press and hold the **Screen Recording** control (the circle within a circle), choose **ReVox** in the list, and tap **Start Broadcast**. If the control is not in your Control Center, add it under **Settings** → **Control Center**.

Only the audio is used. The screen contents are not saved or looked at.

## 6. Stop

- **Microphone:** tap the **Stop** button in ReVox.
- **Broadcast:** tap the red status bar or Dynamic Island indicator and confirm **Stop**, or open ReVox and tap **Stop**, or use the Screen Recording control in Control Center again.

When ReVox is stopped it does not listen, and the red indicator disappears.

## 7. Transcripts

Everything ReVox translated is kept on the phone. In the app, open **History** (the clock symbol) to see past sessions: each shows the time, the English text and, where available, the original words. From there you can share or delete a transcript. Transcripts are stored only on your iPhone and are never uploaded anywhere.

## 8. Send feedback

The easiest way is a screenshot:

1. Take a screenshot while the problem is on screen (press the side button and the volume-up button together).
2. Tap the screenshot preview in the corner, then tap **Share** and choose **Share Beta Feedback**.
3. Describe what you expected and what happened, and send it. The screenshot, your iPhone model, iOS version and the ReVox build number are attached automatically.

You can also open the TestFlight app, tap **ReVox**, and tap **Send Beta Feedback** for feedback without a screenshot. If the app crashes, TestFlight asks whether to send the crash report the next time you open it; please say yes.

Helpful details to include: what you were listening to (the microphone or which app), the language spoken, whether the translation was wrong, late or missing, and whether the phone was locked at the time.

## Tips and known limits

- Translation quality depends on the audio: a clear voice close to the phone works best. Music, several people talking at once or heavy background noise reduce accuracy.
- The phone gets warmer and uses more battery while translating; this is expected for on-device translation.
- ReVox cannot change other apps' volume directly. While it speaks, iOS lowers the other audio by an amount that iOS decides; use the voice volume slider to make ReVox itself louder or quieter.
- Translating other apps requires the screen broadcast to be running. If ReVox goes quiet while a video plays, check that the red indicator is still there.
