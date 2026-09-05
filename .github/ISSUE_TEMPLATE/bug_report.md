---
name: Bug report
about: Something ReVox did that it should not have, or did not do that it should
title: "fix: "
labels: bug
---

## What happened

<!-- One or two sentences. What did you expect, and what did ReVox do instead? -->

## Steps to reproduce

1.
2.
3.

## Where it happened

- **iPhone model:**
- **iOS version:**
- **ReVox build:** <!-- TestFlight build number, or the commit if you built it yourself -->
- **Source:** Microphone / Other apps (which app?)
- **Model and voice:** <!-- e.g. small, system voice / pocket-tts alba -->
- **Two-way:** off / on (You speak: …, They speak: …)
- **Phone locked or ReVox in the background at the time?**

## Evidence

<!-- A screenshot of the screen, the status line or the banner. For a TestFlight build, "Share Beta Feedback" on a screenshot attaches the device and build for you (docs/testing.md §8). -->
<!-- If you can read the log: Console.app, subsystem `revox`, or `log stream --predicate 'subsystem == "revox"'`. Paste the relevant lines. -->
<!-- For a broadcast problem: Settings → Diagnostics → Broadcast diagnostics (write cursor, heartbeat age, levels, source format). -->

## Is it a platform limitation?

<!-- Check the README's "Platform limitations" and "How ReVox handles failure" first; if the behaviour is listed there, say so — it may still be worth an issue, but it changes what a fix can be. -->
