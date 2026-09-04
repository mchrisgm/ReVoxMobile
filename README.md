# ReVox Mobile

ReVox Mobile is the iPhone version of [ReVox](https://github.com/mchrisgm/ReVox). It listens to audio (the microphone, or other apps through a screen-broadcast extension), detects phrases with Silero VAD, translates them to English on-device with Whisper via WhisperKit, speaks the English with Kyutai pocket-tts (using the system voice until the pocket-tts voice is downloaded), and keeps a transcript of everything it heard. After the one-time model download it works fully offline: no audio, text or usage data ever leaves the phone.

## Status

| # | Milestone | Status |
|---|-----------|--------|
| 0 | Bootstrap: project skeleton, `ReVoxCore` package, CI, TestFlight workflow, docs | **Current** |
| 1 | Design spec and implementation plan | Planned |
| 2 | `ReVoxCore` port: Segmenter, SpeechGate, Pipeline, Transcript, Catalog, Settings, RingBuffer | Planned |
| 3 | Microphone mode end to end, first TestFlight build | Planned |
| 4 | pocket-tts, voices, ducking | Planned |
| 5 | Other-apps capture via the broadcast extension | Planned |
| 6 | History, export, About screen, HIG polish | Planned |
| 7 | Hardening | Planned |

Milestone 0 builds and ships a placeholder screen; the translation features arrive milestone by milestone.

## Requirements

**To run the app**

- iPhone 12 or newer.
- iOS 17 or later.
- Wi-Fi for the first launch, to download the Whisper model (and optionally the pocket-tts voice). Nothing is downloaded after that.

**To build the app**

- Xcode 26 on macOS.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
- The `ReVoxCore` package needs no Xcode at all: it also builds and tests with the Swift 6.3 toolchain on Linux.

## Building

```bash
xcodegen generate                 # writes ReVoxMobile.xcodeproj from project.yml
open ReVoxMobile.xcodeproj        # select the ReVoxMobile scheme, then build or run
```

To build and test the platform-independent package on its own (macOS or Linux):

```bash
cd ReVoxCore && swift test
```

Notes:

- `ReVoxMobile.xcodeproj` is generated from `project.yml` and is never committed (it is ignored by `.gitignore`). Re-run `xcodegen generate` whenever `project.yml` changes or files are added.
- `REVOX_BUNDLE_PREFIX` in `project.yml` (default `com.mchrisgm`) is the single place that defines every bundle identifier and the App Group: app `<prefix>.revox`, extension `<prefix>.revox.broadcast`, tests `<prefix>.revox.tests`, App Group `group.<prefix>.revox`. To build under your own team, override it on the command line (`xcodebuild ... REVOX_BUNDLE_PREFIX=com.example`) or set the `REVOX_BUNDLE_PREFIX` repository variable for CI; do not edit the ids anywhere else.
- **Signing.** Simulator builds need no signing. To run on a device you need a team: `project.yml` sets no `DEVELOPMENT_TEAM`, so either set your **Team** in **Signing & Capabilities** for both `ReVoxMobile` and `ReVoxBroadcast` in Xcode (and expect to do it again after every `xcodegen generate`, which discards that setting), or pass `DEVELOPMENT_TEAM=<team id> REVOX_BUNDLE_PREFIX=<your prefix>` to `xcodebuild`. The App Group `group.<prefix>.revox` must exist in your team; see step 1 of [docs/release.md](docs/release.md#one-time-apple-setup).

## Architecture

Three Xcode targets plus one Swift package:

- **`ReVoxMobile`** (application): the SwiftUI app that owns the user interface, the audio session, the downloaded models and the translation pipeline.
- **`ReVoxBroadcast`** (Broadcast Upload Extension, `com.apple.broadcast-services-upload`): receives other apps' audio during a system screen broadcast and hands it to the app through the shared App Group.
- **`ReVoxMobileTests`** (unit-test bundle): XCTest tests hosted by the app, run on an iPhone simulator in CI.
- **`ReVoxCore`** (local Swift package, Foundation only): the platform-independent pipeline pieces, so the same tests run on Linux and on the simulator.

Data flow through the pipeline:

```
capture → Segmenter → segment queue (max 3) → WhisperKitTranslator → transcript + text queue → speaker → AudioPlayer → speaking edge → AudioSessionController
```

## Platform limitations

These are iOS rules, not bugs, and they make the iPhone app behave differently from the Windows version:

- **iOS cannot set another app's volume.** Ducking therefore uses the `AVAudioSession` option `.duckOthers`, and iOS itself decides how much to lower the other audio. ReVox adds a slider for the volume of its own spoken voice. The Windows "ducked level" slider has no iOS equivalent and does not exist here.
- **Ducking ends by deactivating the audio session**, which iOS refuses while the engine is rendering. ReVox therefore pauses the engine for the length of that cycle after each spoken phrase — a few tens of milliseconds during which the microphone is not captured. The measured cycle times are in [docs/measurements/m4-pocket-tts-ducking.md](docs/measurements/m4-pocket-tts-ducking.md).
- **Capturing other apps' audio requires the user to start a system broadcast.** Apps cannot listen to each other on iOS. The user starts a screen broadcast from the broadcast picker inside ReVox or from Control Center's Screen Recording control, selects ReVox as the broadcast destination, and iOS then sends the other apps' audio to the `ReVoxBroadcast` extension.
- **The broadcast extension has a 50 MB memory cap.** The Whisper and pocket-tts models are far larger than that, so every model lives in the app; the extension only captures audio and forwards it.
- **Translation continues in the background** thanks to the `audio` background mode. You can lock the phone or switch to another app and ReVox keeps listening, translating and speaking.

## Delivery

- **CI on every push:** [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs `swift test` for `ReVoxCore` in a Linux container (job `core-linux`) and builds and tests the app and the extension on an iPhone simulator with Xcode 26 (job `ios-simulator`).
- **TestFlight on demand:** [`.github/workflows/testflight.yml`](.github/workflows/testflight.yml) runs the tests, archives, exports and uploads the build to App Store Connect (jobs `preflight` and `upload`). It is started by hand (`workflow_dispatch`) or by pushing a `v*` tag: a macOS runner bills at ten times the minute rate, so a release is a decision rather than a side effect of every merge. Until the Apple secrets are configured the upload is skipped with a notice and the workflow stays green.
- [docs/release.md](docs/release.md): one-time Apple setup, GitHub secrets, signing paths and troubleshooting for the repository owner.
- [docs/testing.md](docs/testing.md): how to install and try the app through TestFlight, for testers.

## Licences

- ReVox Mobile: [MIT](LICENSE).
- [WhisperKit](https://github.com/argmaxinc/WhisperKit): MIT.
- pocket-tts Core ML weights: CC-BY-4.0, attribution to [Kyutai](https://kyutai.org).
- [Silero VAD](https://github.com/snakers4/silero-vad): MIT.
