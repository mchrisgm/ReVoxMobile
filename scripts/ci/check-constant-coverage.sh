#!/usr/bin/env bash
# Milestone 2 definition of done (design spec §10.3): every constant ported from the Windows
# ReVox sources must be asserted, by name and value, somewhere in ReVoxCoreTests. Each line of
# the table below is "<test file>|<literal that the assertion must contain>"; the check fails
# on the first missing literal so a renamed or dropped assertion cannot pass unnoticed.
#
# Usage: scripts/ci/check-constant-coverage.sh [path/to/ReVoxCoreTests]
set -euo pipefail

tests="${1:-ReVoxCore/Tests/ReVoxCoreTests}"
if [ ! -d "$tests" ]; then
  echo "::error::ReVoxCoreTests directory not found at $tests"
  exit 1
fi

missing=0
checked=0
while IFS='|' read -r file literal; do
  [ -z "$file" ] && continue
  case "$file" in \#*) continue ;; esac
  checked=$((checked + 1))
  path="$tests/$file"
  if [ ! -f "$path" ]; then
    echo "::error::missing test file $path (needed for: $literal)"
    missing=$((missing + 1))
    continue
  fi
  if ! grep -qF -- "$literal" "$path"; then
    echo "::error file=$path::constant not asserted: $literal"
    missing=$((missing + 1))
  fi
done <<'TABLE'
# Segmenter (segmenter.py: CHUNK_SAMPLES, SAMPLE_RATE, speech_threshold, padding_ms, PRESETS)
SegmenterTests.swift|XCTAssertEqual(Segmenter.chunkSamples, 512)
SegmenterTests.swift|XCTAssertEqual(Segmenter.sampleRate, 16_000)
SegmenterTests.swift|XCTAssertEqual(Segmenter.defaultSpeechThreshold, 0.5)
SegmenterTests.swift|XCTAssertEqual(Segmenter.defaultPaddingMs, 200)
SegmenterTests.swift|XCTAssertEqual(SegmenterPreset.balanced.silenceMs, 500)
SegmenterTests.swift|XCTAssertEqual(SegmenterPreset.balanced.maxSegmentSeconds, 10.0)
SegmenterTests.swift|XCTAssertEqual(SegmenterPreset.fast.silenceMs, 300)
SegmenterTests.swift|XCTAssertEqual(SegmenterPreset.fast.maxSegmentSeconds, 4.0)
SegmenterTests.swift|XCTAssertEqual(balanced.silenceChunks, 15)
SegmenterTests.swift|XCTAssertEqual(balanced.maxChunks, 312)
SegmenterTests.swift|XCTAssertEqual(balanced.paddingChunks, 6)
SegmenterTests.swift|XCTAssertEqual(fast.silenceChunks, 9)
SegmenterTests.swift|XCTAssertEqual(fast.maxChunks, 125)
SegmenterTests.swift|XCTAssertEqual(fast.paddingChunks, 6)
SegmenterTests.swift|XCTAssertEqual(SegmenterPreset.veryFast.silenceMs, 200)
SegmenterTests.swift|XCTAssertEqual(SegmenterPreset.veryFast.maxSegmentSeconds, 3.0)
SegmenterTests.swift|XCTAssertEqual(veryFast.silenceChunks, 6)
SegmenterTests.swift|XCTAssertEqual(veryFast.maxChunks, 93)
# SpeechGate (stt.py: NO_SPEECH_MAX, AVG_LOGPROB_MIN, LANGUAGE_PROB_MIN, HALLUCINATION_PHRASES, strip set)
SpeechGateTests.swift|XCTAssertEqual(SpeechGate.noSpeechMax, 0.85)
SpeechGateTests.swift|XCTAssertEqual(SpeechGate.averageLogProbMin, -1.2)
SpeechGateTests.swift|XCTAssertEqual(SpeechGate.languageProbMin, 0.4)
SpeechGateTests.swift|"", "you", "thanks for watching", "thank you for watching",
SpeechGateTests.swift|"subtitles by the amara.org community", "subscribe",
SpeechGateTests.swift|XCTAssertEqual(SpeechGate.hallucinationPhrases.count, 6)
SpeechGateTests.swift|XCTAssertEqual(set.count, 40)
# Pipeline (pipeline.py: max_pending) and the iOS holds (R8, R9)
BoundedSegmentQueueTests.swift|XCTAssertEqual(BoundedSegmentQueue<Int>.defaultCapacity, 3)
PipelineTypesTests.swift|XCTAssertEqual(configuration.maxPending, 3)
CaptureGateTests.swift|XCTAssertEqual(CaptureGate.defaultHoldFrames, 4_800)
DuckingCoordinatorTests.swift|XCTAssertEqual(DuckingCoordinator.defaultHoldNanoseconds, 250_000_000)
# Transcript (transcript.py: header, drop marker, file name)
TranscriptFormatterTests.swift|XCTAssertEqual(TranscriptFormatter.headerPrefix, "# ReVox session ")
TranscriptFormatterTests.swift|XCTAssertEqual(TranscriptFormatter.dropMarkerText, "… (skipped: falling behind)")
TranscriptFormatterTests.swift|XCTAssertEqual(TranscriptFormatter.dropMarkerText.unicodeScalars.first?.value, 0x2026)
TranscriptFormatterTests.swift|^\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2}-\\d{2}\\.txt$
TranscriptFormatterTests.swift|XCTAssertEqual(name, "2023-11-14_22-13-20.txt")
# AudioFormat (capture/base.py: PIPELINE_SAMPLE_RATE)
AudioFormatTests.swift|XCTAssertEqual(AudioFormat.pipelineSampleRate, 16_000)
# Ring bridge (R10)
RingBridgeTests.swift|XCTAssertEqual(layout.magic, "RVXRING1")
RingBridgeTests.swift|XCTAssertEqual(layout.headerBytes, 4_096)
RingBridgeTests.swift|XCTAssertEqual(layout.capacityFrames, 960_000)
RingBridgeTests.swift|XCTAssertEqual(layout.sampleRate, 16_000)
RingBridgeTests.swift|XCTAssertEqual(RingLayout.fileName, "audio-ring-v1.bin")
RingReaderTests.swift|XCTAssertEqual(RingReader.defaultGuardFrames, 16_000)
RingReaderTests.swift|XCTAssertEqual(RingReader.defaultCatchUpFrames, 32_000)
RingReaderTests.swift|XCTAssertEqual(RingReader.staleAfterSeconds, 3)
# Settings (config.py defaults that survive the port, R11)
SettingsTests.swift|XCTAssertEqual(settings.model, "small")
SettingsTests.swift|XCTAssertEqual(settings.voice, "alba")
SettingsTests.swift|XCTAssertTrue(settings.ducking)
SettingsTests.swift|XCTAssertEqual(settings.voiceVolume, 1.0)
SettingsTests.swift|XCTAssertEqual(settings.latencyMode, "balanced")
SettingsTests.swift|XCTAssertEqual(settings.captureMode, "microphone")
SettingsTests.swift|XCTAssertEqual(SettingsCodec.fileName, "settings.json")
# Model catalog (R4: folders, sizes, pinned revisions) and licences
ModelCatalogTests.swift|"openai_whisper-tiny", "openai_whisper-base", "openai_whisper-small",
ModelCatalogTests.swift|"openai_whisper-medium", "openai_whisper-large-v3_947MB",
ModelCatalogTests.swift|76_600_000, 146_700_000, 486_500_000, 1_528_000_000, 948_000_000,
ModelCatalogTests.swift|XCTAssertEqual(ModelCatalog.defaultWhisperModel, .small)
ModelCatalogTests.swift|XCTAssertNotEqual(revision, "main")
ModelCatalogTests.swift|^[0-9a-f]{40}$
ModelCatalogTests.swift|XCTAssertEqual(ModelCatalog.vad.approximateBytes, 950_000)
ModelCatalogTests.swift|XCTAssertEqual(ModelCatalog.pocketTTS.approximateBytes, 527_300_000)
ModelCatalogTests.swift|XCTAssertEqual(ModelCatalog.pocketTTS.offeredVoices, ["alba", "azelma", "cosette", "javert"])
# Device recommendation (R13 table)
DeviceRecommendationTests.swift|XCTAssertEqual(recommendation.recommended, .base)
DeviceRecommendationTests.swift|XCTAssertEqual(recommendation.suitable, [.tiny, .base, .small, .medium], "\(value)")
DeviceRecommendationTests.swift|XCTAssertEqual(recommendation.suitable, Set(WhisperModelID.allCases), "\(value)")
DeviceRecommendationTests.swift|XCTAssertEqual(DeviceRecommendation.heatWarning, "Long load time and heat")
DeviceRecommendationTests.swift|XCTAssertNil(DeviceRecommendation.pocketTTSAdvisory(memoryTierGB: 6))
TABLE

if [ "$missing" -ne 0 ]; then
  echo "::error::$missing of $checked ported constants are not asserted in $tests"
  exit 1
fi
echo "All $checked ported constants are asserted in $tests"
