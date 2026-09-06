# ReVox privacy policy

Effective 6 September 2026.

ReVox for iPhone is made by one independent developer, [mchrisgm](https://github.com/mchrisgm). This policy covers the app and its screen-broadcast extension, both open source at [github.com/mchrisgm/ReVoxMobile](https://github.com/mchrisgm/ReVoxMobile), so everything here can be checked against the code.

## What ReVox collects

Nothing. There is no account, no analytics, no crash reporter, no advertising, no tracking and no third-party software reporting to anyone. The developer does not receive, and cannot see, what you say, translate or read.

Apple, not ReVox, may pass crash reports and feedback to the developer if you use TestFlight or turned on "Share with App Developers" in iOS Settings, under Apple's terms.

## What stays on your iPhone

Everything lives in the app's own storage:

- **Transcripts.** A session records when it started and ended, whether it listened to the microphone or a broadcast, the model and voice, and for each phrase the time, its language label and the text shown: the English translation or, with Two-way on, your own phrase as spoken to the other person in their language (or as you said it when the iPhone cannot translate it), plus the words as spoken when Learning mode was on. No audio is saved.
- **Settings**, benchmark results (iPhone model and iOS version), which models loaded, a broadcast status record (when the last broadcast started and ended, its audio format and, while it is live, the identifier of the app being broadcast; no audio, no text), and a keep-alive log written once a second during every session (the time and how much audio has been captured; no audio, no text), overwritten by the next session, capped at 512 KB and excluded from backups.
- **Downloaded models**: Whisper, the voice detector and, optionally, the pocket-tts voices, excluded from backups: they are large and can be downloaded again.

Transcripts, settings and benchmark results are ordinary app data, so iCloud Backup or a computer backup includes them; ReVox uses no iCloud and no sync.

To delete:

- One transcript: swipe it in History, or open it and tap Delete. All of them: **History › Clear All**.
- A model or the pocket-tts voices: **Settings › Models** or **Settings › Voices**, swipe the row, tap Delete.
- Everything: delete the app. iOS removes its storage, including the shared broadcast buffer.

**Share** on a session hands a `.txt` file to the iOS share sheet; where it goes is your choice. The temporary copy is deleted at the next launch once it is a day old; iOS may clear it sooner. **Share** on the Benchmark screen hands its report to the share sheet as text; ReVox keeps no copy.

## The one network use: model downloads

ReVox has no server. It uses the network only when you tap **Download** on the Models or Voices screen. WhisperKit and FluidAudio then fetch the files from `huggingface.co` (and the download hosts it redirects to): the Whisper models and their tokenizers, the voice detector and the pocket-tts voices. The small Whisper model is about 487 MB.

It is an ordinary web request, without an account or token. Hugging Face sees your IP address, the time, the files requested and the standard headers iOS sends (app name and version, iOS version). ReVox adds nothing that identifies you; Hugging Face's privacy policy covers its logs. After the download ReVox makes no further connection.

On iOS 18, Two-way replies and Learning-mode word meanings use Apple's built-in translator, which runs on the iPhone once its language pack is installed. If a Two-way session needs a missing pack, iOS offers to download it from Apple, under Apple's privacy policy; tapping a word never starts a download. **Look up in the dictionary** opens the iPhone's dictionary.

## Microphone and screen broadcast

ReVox asks for the microphone at your first Start in microphone mode, explaining: "ReVox listens to speech so it can translate it to English on this iPhone. Audio never leaves the device." It is on only between Start and Stop; the audio is processed in memory, never written to a file; only the text remains, in History. Withdraw access in **Settings › Privacy & Security › Microphone**.

To translate another app you start a system screen broadcast yourself, from the picker on the Live screen or Control Center, and choose ReVox; ReVox cannot start one itself. You end it from the red status indicator or Control Center. The extension keeps only the other app's audio, ignoring the screen video and the microphone. It passes audio to the app through a 60-second rolling buffer in the app's shared container: overwritten continuously, wiped when the broadcast ends or the next one starts, and excluded from backups. Nothing from a broadcast is sent anywhere; the text lands in History.

## Children

ReVox collects no data from anyone, children included, and is not directed at children.

## Your rights

Data protection law lets you access, correct, export and delete personal data an organisation holds about you. The developer holds none and so sells, shares and discloses nothing; what is on your phone you control as above. Questions go to the contact below.

## Changes to this policy

A change to how ReVox handles data gets a new effective date here and a line in the release notes; earlier versions stay in the repository's history.

## Contact

Open an issue at [github.com/mchrisgm/ReVoxMobile/issues](https://github.com/mchrisgm/ReVoxMobile/issues). It is public, so please do not post transcripts or anything private.
