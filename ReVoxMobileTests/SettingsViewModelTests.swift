import XCTest
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private func makeStore() -> SettingsStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxSettingsVM-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SettingsStore(fileURL: directory.appendingPathComponent(SettingsCodec.fileName))
    }

    func testRoundTripsSettings() {
        let store = makeStore()
        let model = SettingsViewModel(store: store, mute: PlaybackMute())
        XCTAssertEqual(model.latencyMode, .balanced)
        XCTAssertNil(model.language)

        model.latencyMode = .fast
        model.language = "fr"
        let reread = SettingsStore(fileURL: store.fileURL)
        XCTAssertEqual(reread.settings.latencyMode, "fast")
        XCTAssertEqual(reread.settings.language, "fr")

        model.language = nil
        XCTAssertNil(SettingsStore(fileURL: store.fileURL).settings.language, "Auto-detect stores nil")
    }

    func testVoiceAndModelLists() {
        XCTAssertTrue(SettingsViewModel.voiceNames.contains("alba"))
        XCTAssertTrue(SettingsViewModel.voiceNames.contains("system"))
        XCTAssertTrue(SettingsViewModel.modelNames.contains("large-v3"))
        XCTAssertEqual(SettingsViewModel.modelNames, ["tiny", "base", "small", "medium", "large-v3"])
        XCTAssertFalse(SettingsViewModel.modelNames.contains { $0.contains("turbo") || $0.contains("distil") })
    }

    func testLanguageOptionsSortedWithAutoDetectFirstAndCodeFallback() {
        let options = SettingsViewModel.languageOptions(codes: ["es", "de", "haw", "zz"], locale: Locale(identifier: "en_US"))
        XCTAssertEqual(options.first?.code, nil)
        XCTAssertEqual(options.first?.displayName, SettingsViewModel.autoDetectTitle)
        let names = options.dropFirst().map(\.displayName)
        XCTAssertEqual(names, names.sorted())
        XCTAssertTrue(names.contains("German"))
        XCTAssertTrue(names.contains("Spanish"))
        XCTAssertTrue(names.contains("zz"), "unknown code falls back to the code itself")
        XCTAssertEqual(options.map(\.id).count, Set(options.map(\.id)).count)
    }

    func testLiveLanguageListComesFromWhisperKit() {
        let model = SettingsViewModel(store: makeStore(), mute: PlaybackMute(), locale: Locale(identifier: "en_US"))
        XCTAssertGreaterThan(model.languageOptions.count, 90)
        XCTAssertTrue(model.languageOptions.contains { $0.code == "es" })
        XCTAssertTrue(model.languageOptions.contains { $0.code == "ja" })
    }

    func testMuteMirrorsTheSharedState() {
        let mute = PlaybackMute()
        let model = SettingsViewModel(store: makeStore(), mute: mute)
        model.isMuted = true
        XCTAssertTrue(mute.isMuted)
        mute.isMuted = false
        XCTAssertFalse(model.isMuted)
    }

    func testPresetDescriptionsAreTheWindowsValues() {
        XCTAssertEqual(SettingsViewModel.presetDescription(.balanced), "Silence 500 ms, max 10 s")
        XCTAssertEqual(SettingsViewModel.presetDescription(.fast), "Silence 300 ms, max 4 s")
        XCTAssertEqual(SettingsViewModel.presetDescription(.veryFast), "Silence 200 ms, max 3 s")
    }

    /// Every preset and every time mode has a title (07d1eed shipped a switch that did not know Very fast).
    func testEveryPresetAndTimeModeHasATitle() {
        XCTAssertEqual(SegmenterPreset.allCases.map(SettingsView.title(for:)), ["Balanced", "Fast", "Very fast"])
        XCTAssertEqual(Settings.TimeDisplay.allCases.map(SettingsView.title(for:)), ["Time", "How long ago", "Both"])
        XCTAssertEqual(Settings.TimeDisplay.allCases.map(SettingsViewModel.timeDisplayTitle), ["Time", "How long ago", "Both"])
        XCTAssertEqual(Set(SegmenterPreset.allCases.map(SettingsView.title(for:))).count, SegmenterPreset.allCases.count, "no two presets share a title")
    }

    func testLanguageDisplayNameFallsBackToTheCodeAndTheCallersNilWord() {
        XCTAssertEqual(LanguageCatalog.displayName(nil, whenNil: "Auto-detect"), "Auto-detect")
        XCTAssertEqual(LanguageCatalog.displayName(nil, whenNil: "None"), "None")
        XCTAssertNotEqual(LanguageCatalog.displayName("es", whenNil: ""), "es", "a code the locale knows is named")
        XCTAssertFalse(LanguageCatalog.displayName("es", whenNil: "").isEmpty)
        XCTAssertEqual(LanguageCatalog.displayName("zz", whenNil: ""), "zz", "a code Whisper does not know is shown as it is")
        XCTAssertEqual(LanguageCatalog.concrete.count, LanguageCatalog.options.count - 1, "the two-way lists drop only Auto-detect")
        XCTAssertFalse(LanguageCatalog.concrete.contains { $0.code == nil })
        XCTAssertEqual(LanguageCatalog.options.first?.displayName, LanguageCatalog.autoDetectTitle)
    }

    // MARK: ducking toggle, voice volume, help text (§8.5, C1)

    func testDuckingAndVoiceVolumeRoundTripAndReachThePlayersBox() {
        let store = makeStore()
        let box = VoiceVolume(1)
        let model = SettingsViewModel(store: store, mute: PlaybackMute(), voiceVolume: box)
        XCTAssertTrue(model.ducking, "R11 default")
        XCTAssertEqual(model.voiceVolume, 1.0)

        model.ducking = false
        model.voiceVolume = 0.4
        XCTAssertEqual(box.current, 0.4, accuracy: 0.0001, "the players read the box at enqueue time")
        let reread = SettingsStore(fileURL: store.fileURL)
        XCTAssertFalse(reread.settings.ducking)
        XCTAssertEqual(reread.settings.voiceVolume, 0.4, accuracy: 0.0001)

        model.voiceVolume = 1.7
        XCTAssertEqual(model.voiceVolume, 1.0, "clamped")
        XCTAssertEqual(box.current, 1)
        model.voiceVolume = -0.2
        XCTAssertEqual(model.voiceVolume, 0)
    }

    func testSavedVoiceVolumeSeedsTheBoxAtLaunch() {
        let store = makeStore()
        store.update { $0.voiceVolume = 0.25 }
        let box = VoiceVolume(1)
        _ = SettingsViewModel(store: store, mute: PlaybackMute(), voiceVolume: box)
        XCTAssertEqual(box.current, 0.25, accuracy: 0.0001)
    }

    func testDuckingHelpTextNamesTheWindowsSlider() {
        XCTAssertEqual(SettingsViewModel.duckingHelpText,
                       "While ReVox speaks, iOS lowers other audio by an amount iOS decides. The Windows ducked-level slider has no iOS equivalent; use Voice volume to balance ReVox's own voice.")
        XCTAssertEqual(SettingsViewModel.duckingAppliesOnStartText, "A change to the ducking toggle takes effect the next time you tap Start.")
    }


    // MARK: M9

    func testTheM9BindingsWriteTheStore() {
        let store = makeStore()
        let model = SettingsViewModel(store: store, mute: PlaybackMute())
        model.keepModelWhenHot = true
        model.learning = true
        model.romanize = true
        model.timeDisplay = .both
        XCTAssertTrue(store.settings.keepModelWhenHot)
        XCTAssertTrue(store.settings.learning)
        XCTAssertTrue(store.settings.romanize)
        XCTAssertEqual(store.settings.timeDisplayMode, .both)
        XCTAssertEqual(SettingsViewModel.timeDisplayTitle(.age), "How long ago")
    }

    /// Every setting has an example that changes with its value: the reader sees what it does, not only what it is.
    func testEveryExampleChangesWithItsValue() {
        XCTAssertNotEqual(SettingExamples.latency(.balanced), SettingExamples.latency(.veryFast))
        XCTAssertTrue(SettingExamples.latency(.veryFast).contains("0.2 s"))
        XCTAssertNotEqual(SettingExamples.ducking(true), SettingExamples.ducking(false))
        XCTAssertEqual(SettingExamples.voiceVolume(0.35), "ReVox's own voice plays at 35 %. Other apps are not affected.")
        XCTAssertNotEqual(SettingExamples.keepModelWhenHot(true, model: .small), SettingExamples.keepModelWhenHot(false, model: .small))
        XCTAssertTrue(SettingExamples.keepModelWhenHot(true, model: .small).contains("small"))
        XCTAssertNotEqual(SettingExamples.learning(true), SettingExamples.learning(false))
        XCTAssertNotEqual(SettingExamples.romanize(true), SettingExamples.romanize(false))
        XCTAssertNotEqual(SettingExamples.timeDisplay(.time), SettingExamples.timeDisplay(.age))
        XCTAssertTrue(SettingExamples.skipLanguage("English").contains("English"))
        XCTAssertTrue(SettingExamples.sourceLanguagePinned("French").contains("French"))
        XCTAssertEqual(SettingExamples.sampleRow().kind, .entry(language: "es", original: "", english: SettingExamples.spanishEnglish))
        XCTAssertEqual(Romanizer.romanize(SettingExamples.japaneseOriginal), "ohayou",
                       "the example is kana on purpose: ICU reads kanji by their Chinese readings")
    }

    /// M11 §2: the Learning copy says the words are tappable — on the example, which is the live demonstration
    /// (the same row view), and in the footer.
    func testTheLearningCopySaysWordsAreTappable() {
        XCTAssertEqual(SettingExamples.learning(true),
                       "The words as spoken appear above the translation. Tap a word to hear it and see what it means.")
        XCTAssertEqual(SettingExamples.learning(false), "Only the translation is shown.")
        XCTAssertTrue(SettingsViewModel.learningHelpText.hasPrefix("Shows the words as they were spoken above the translation."))
        XCTAssertTrue(SettingsViewModel.learningHelpText.hasSuffix(" Tap any word for its pronunciation and meaning."))
    }

    /// M10: the skip example must say what actually happens while Source language is pinned. The core never detects
    /// a pinned language, so nothing is skipped — unless the pinned language *is* the skipped one, when every
    /// phrase is left alone. The old example promised a skip in both cases.
    func testTheSkipLanguageExampleFollowsThePinnedSourceLanguage() {
        XCTAssertEqual(SettingExamples.skipLanguageText(ignored: nil, pinned: nil), SettingExamples.skipLanguageNone)
        XCTAssertEqual(SettingExamples.skipLanguageText(ignored: nil, pinned: "French"), SettingExamples.skipLanguageNone)
        XCTAssertEqual(SettingExamples.skipLanguageText(ignored: "English", pinned: nil), SettingExamples.skipLanguage("English"))
        let pinnedElsewhere = SettingExamples.skipLanguageText(ignored: "English", pinned: "French")
        XCTAssertEqual(pinnedElsewhere, SettingExamples.skipLanguageWhilePinned(ignored: "English", pinned: "French"))
        XCTAssertTrue(pinnedElsewhere.contains("French"))
        XCTAssertTrue(pinnedElsewhere.contains("English"))
        XCTAssertTrue(pinnedElsewhere.contains("Auto-detect"), "the way out is named")
        XCTAssertFalse(pinnedElsewhere.contains("left alone"), "nothing is skipped while the source language is pinned elsewhere")
        let pinnedToItself = SettingExamples.skipLanguageText(ignored: "English", pinned: "English")
        XCTAssertTrue(pinnedToItself.contains("every phrase"))
        XCTAssertNotEqual(pinnedToItself, pinnedElsewhere)
    }

    /// M10: with Learning off no original is shown at all, so the Romanize example cannot claim "the original is
    /// shown in its own script"; it says what to turn on instead, next to the disabled toggle.
    func testTheRomanizeExampleNeedsLearning() {
        XCTAssertEqual(SettingExamples.romanizeText(on: true, learning: true), SettingExamples.romanize(true))
        XCTAssertEqual(SettingExamples.romanizeText(on: false, learning: true), SettingExamples.romanize(false))
        XCTAssertEqual(SettingExamples.romanizeText(on: true, learning: false), SettingExamples.romanizeNeedsLearning)
        XCTAssertEqual(SettingExamples.romanizeText(on: false, learning: false), SettingExamples.romanizeNeedsLearning)
        XCTAssertTrue(SettingExamples.romanizeNeedsLearning.contains("Learning"))
    }

    /// M10: the skip picker is disabled while a source language is pinned (a pinned language is never detected).
    func testTheSkipPickerNeedsAutoDetect() {
        let store = makeStore()
        let model = SettingsViewModel(store: store, mute: PlaybackMute())
        XCTAssertTrue(model.canIgnoreLanguage)
        model.language = "es"
        XCTAssertFalse(model.canIgnoreLanguage)
        model.language = nil
        XCTAssertTrue(model.canIgnoreLanguage)
    }

    // MARK: M11 — Your language, You speak

    func testTheYourLanguageCopyNamesThePeopleNotTheMechanism() {
        XCTAssertEqual(SettingsViewModel.noIgnoredLanguageTitle, "Not set")
        XCTAssertEqual(SettingsViewModel.noIgnoredLanguageTitle, LiveView.noLanguageTitle, "one word on both screens")
        XCTAssertEqual(SettingsViewModel.ignoredLanguageHelpText,
                       "ReVox translates everything it hears into English except the language you speak, which it neither translates nor transcribes. With Two-way on (Live tab), what you say is spoken to the other person in their language instead.")
        XCTAssertEqual(SettingsViewModel.ignoredLanguageNeedsAutoDetectText,
                       "This needs Source language set to Auto-detect, because a pinned language is never detected.")
        XCTAssertEqual(SettingExamples.skipLanguageNone,
                       "Everything is translated into English, including you. Choose the language you speak so a conversation is not echoed back at you.")
        XCTAssertEqual(SettingExamples.skipLanguage("English"),
                       "“Where is the station?” said in English is not translated and not transcribed. Turn on Two-way on the Live tab to have it spoken to the other person in their language instead.")
        XCTAssertEqual(SettingExamples.skipLanguageWhilePinned(ignored: "English", pinned: "English"),
                       "Source language is pinned to English and English is the language you speak, so every phrase counts as yours and nothing is translated. Change one of the two.")
        XCTAssertEqual(SettingExamples.skipLanguageWhilePinned(ignored: "English", pinned: "French"),
                       "Source language is pinned to French, so nothing is ever heard as English and everything is translated, including you. Set Source language to Auto-detect for You speak to work.")
        let model = SettingsViewModel(store: makeStore(), mute: PlaybackMute())
        XCTAssertEqual(model.ignoredLanguageOptions.first?.displayName, "Not set")
        for text in [SettingsViewModel.ignoredLanguageHelpText, SettingsViewModel.ignoredLanguageNeedsAutoDetectText,
                     SettingExamples.skipLanguageText(ignored: nil, pinned: nil), SettingExamples.skipLanguageText(ignored: "English", pinned: nil),
                     SettingExamples.skipLanguageText(ignored: "English", pinned: "English"), SettingExamples.skipLanguageText(ignored: "English", pinned: "French")] {
            for retired in ["left alone", "Leave alone", "Reply in", "Don't translate", "Skip a language", "ignored", "skipped"] {
                XCTAssertFalse(text.contains(retired), "\(retired) in: \(text)")
            }
        }
    }

    func testTheSourceLanguageCopyKeepsUnsurePhrasesInsteadOfDroppingThem() {
        XCTAssertEqual(SettingsViewModel.sourceLanguageHelpText,
                       "Auto-detect runs Whisper's language detection on every phrase. A phrase it is unsure about is shown greyed and marked Unsure, and is never spoken.")
        XCTAssertEqual(SettingExamples.sourceLanguageAuto,
                       "Auto-detect hears “¿Dónde está la estación?” as Spanish and translates it. A phrase it cannot place is shown greyed and marked Unsure, and is not spoken.")
        XCTAssertFalse(SettingExamples.sourceLanguageAuto.contains("dropped"))
    }

    func testLiveAndSettingsWriteTheSameYourLanguage() {
        let store = makeStore()
        let settings = SettingsViewModel(store: store, mute: PlaybackMute())
        let live = LiveViewModel(settings: store, mute: PlaybackMute(), permission: .fixed(.granted),
                                 modelReady: { _ in true }, supplier: { _, _ in FakeLivePipeline() })
        live.ignoredLanguage = "en"
        XCTAssertEqual(settings.ignoredLanguage, "en", "the Live pill and the Settings row are one setting")
        settings.ignoredLanguage = "es"
        XCTAssertEqual(live.ignoredLanguage, "es")
        settings.ignoredLanguage = nil
        XCTAssertNil(live.ignoredLanguage)
        XCTAssertNil(store.settings.ignoredLanguage, "Not set stores nil, the key the Windows app reads")
    }
}
