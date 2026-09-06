# ReVox support

ReVox for iPhone is made by one independent developer. There is no support email or chat: help comes through the project's issue tracker on GitHub, which anyone can read.

## Before you report

- [docs/testing.md](testing.md) walks through installing the app, the first launch and its model download (about 487 MB for small), the Microphone and Other apps sources, the voices, History and the About screen, and ends with the known limits. Many questions are answered there.
- The README's [Platform limitations](../README.md#platform-limitations) section lists what iOS does not allow. ReVox cannot hear phone or FaceTime calls, cannot start or stop a broadcast itself, and some players (Safari, Music, some video apps) deliver silence to broadcasts.

## Report a problem

Open an issue at [github.com/mchrisgm/ReVoxMobile/issues](https://github.com/mchrisgm/ReVoxMobile/issues) and choose the **Bug report** template. Include:

- your iPhone model and iOS version;
- the app version, shown at the top of **Settings › About** (for example `0.1.0 (42)`);
- which source you were using, Microphone or Other apps, and for Other apps which app you were listening to;
- for Other apps, the numbers from **Settings › Diagnostics › Broadcast diagnostics** (write cursor, heartbeat age, levels, source format);
- what you expected, what happened instead, and a screenshot of the screen, the status line or the banner if there is one.

On a TestFlight build, **Share Beta Feedback** on a screenshot attaches the device, iOS version and build number for you; section 8 of [docs/testing.md](testing.md#8-send-feedback) shows how.

The tracker is public. Please do not post transcripts or anything private; describe them instead.

## Suggest a change

Use the **Feature request** template on the same tracker. ReVox contacts no server after the model download, so a feature that needs a network service, an account or telemetry is out of scope.

## Privacy

ReVox collects nothing. The [privacy policy](privacy.md) says what stays on the phone, what the one network use is, and how to delete all of it.
