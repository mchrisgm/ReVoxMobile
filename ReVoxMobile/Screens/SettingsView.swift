import SwiftUI
import ReVoxCore

struct SettingsView: View {
    @Bindable var model: SettingsViewModel
    let models: ModelsViewModel
    let voices: VoicesViewModel
    var diagnostics: BroadcastDiagnosticsModel? = nil
    /// M10: "Show the tutorial" resets it; the root presents it. nil (tests, previews) hides the row.
    var onboarding: OnboardingViewModel? = nil

    var body: some View {
        Form {
            Section {
                Picker("Latency mode", selection: $model.latencyMode) {
                    ForEach(SegmenterPreset.allCases, id: \.self) { preset in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.title(for: preset))
                            Text(SettingsViewModel.presetDescription(preset)).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(preset)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                SettingExample(symbol: "waveform.path", text: SettingExamples.latency(model.latencyMode)) {
                    LatencyTimeline(preset: model.latencyMode)
                }
            } header: {
                Text("Latency mode")
            }

            Section {
                Picker("Source language", selection: $model.language) {
                    ForEach(model.languageOptions) { option in
                        HStack {
                            Text(option.displayName)
                            if let code = option.code {
                                Spacer()
                                Text(code).foregroundStyle(.secondary)
                            }
                        }
                        .tag(option.code)
                    }
                }
                SettingExample(symbol: "globe",
                               text: model.language.map { SettingExamples.sourceLanguagePinned(LanguageCatalog.displayName($0, whenNil: "")) }
                                     ?? SettingExamples.sourceLanguageAuto)
            } footer: {
                Text(SettingsViewModel.sourceLanguageHelpText)
            }

            Section {
                Picker("You speak", selection: $model.ignoredLanguage) {
                    ForEach(model.ignoredLanguageOptions) { option in
                        Text(option.displayName).tag(option.code)
                    }
                }
                .disabled(!model.canIgnoreLanguage)
                SettingExample(symbol: "person.wave.2",
                               text: SettingExamples.skipLanguageText(ignored: model.ignoredLanguage.map { LanguageCatalog.displayName($0, whenNil: "") },
                                                                      pinned: model.language.map { LanguageCatalog.displayName($0, whenNil: "") }))
            } header: {
                Text("Your language")
            } footer: {
                Text(model.language == nil
                     ? SettingsViewModel.ignoredLanguageHelpText
                     : "\(SettingsViewModel.ignoredLanguageHelpText)\n\(SettingsViewModel.ignoredLanguageNeedsAutoDetectText)")
            }

            Section {
                Toggle("Learning", isOn: $model.learning)
                    .accessibilityHint("Shows the words as spoken above the translation")
                SettingExample(symbol: "text.book.closed", text: SettingExamples.learning(model.learning)) {
                    LiveTranscriptRowView(row: SettingExamples.sampleRow(original: SettingExamples.spanishOriginal),
                                          showsOriginal: model.learning)
                }
                Toggle("Romanize", isOn: $model.romanize)
                    .disabled(!model.learning)
                    .accessibilityHint("Adds how the original sounds in Latin letters")
                SettingExample(symbol: "character.phonetic", text: SettingExamples.romanizeText(on: model.romanize, learning: model.learning)) {
                    // The row shows what the Live screen would show: no original at all while Learning is off.
                    LiveTranscriptRowView(row: SettingExamples.japaneseRow, showsOriginal: model.learning, romanizes: model.romanize)
                }
            } header: {
                Text("Learning")
            } footer: {
                Text("\(SettingsViewModel.learningHelpText)\n\(SettingsViewModel.romanizeHelpText)")
            }

            Section {
                Picker("Show", selection: $model.timeDisplay) {
                    ForEach(Settings.TimeDisplay.allCases, id: \.self) { mode in
                        Text(SettingsViewModel.timeDisplayTitle(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                SettingExample(symbol: "clock", text: SettingExamples.timeDisplay(model.timeDisplay)) {
                    LiveTranscriptRowView(row: SettingExamples.sampleRow(),
                                          now: SettingExamples.sampleTime.addingTimeInterval(12),
                                          timeDisplay: model.timeDisplay)
                }
            } header: {
                Text("Time on the Live screen")
            } footer: {
                Text(SettingsViewModel.timeDisplayHelpText)
            }

            Section("Voice") {
                Toggle("Mute voice", isOn: $model.isMuted)
                    .accessibilityHint("Silences the English voice while the transcript keeps running")
                if model.isMuted {
                    SettingExample(symbol: "speaker.slash", text: SettingExamples.mute)
                }
            }

            Section {
                Toggle("Duck other audio while speaking", isOn: $model.ducking)
                    .accessibilityHint("Lowers other apps' audio while the English voice plays")
                SettingExample(symbol: "speaker.wave.2", text: SettingExamples.ducking(model.ducking)) {
                    DuckingBars(ducking: model.ducking)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Voice volume")
                    Slider(value: $model.voiceVolume, in: 0...1, step: 0.05) {
                        Text("Voice volume")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill").accessibilityHidden(true)
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill").accessibilityHidden(true)
                    }
                    .accessibilityValue("\(Int((model.voiceVolume * 100).rounded())) percent")
                }
                .frame(minHeight: 44)
                SettingExample(symbol: "speaker.wave.1", text: SettingExamples.voiceVolume(model.voiceVolume))
            } header: {
                Text("Ducking")
            } footer: {
                Text("\(SettingsViewModel.duckingHelpText)\n\(SettingsViewModel.duckingAppliesOnStartText)")
            }

            Section {
                Toggle("Keep my model when hot", isOn: $model.keepModelWhenHot)
                    .accessibilityHint("Keeps the chosen model through a hot iPhone instead of switching to a smaller one")
                SettingExample(symbol: "thermometer.medium",
                               text: SettingExamples.keepModelWhenHot(model.keepModelWhenHot, model: model.selectedModel))
            } header: {
                Text("Heat")
            } footer: {
                Text(SettingsViewModel.keepModelWhenHotHelpText)
            }

            Section {
                NavigationLink("Models") { ModelsView(model: models) }
                NavigationLink("Voices") { VoicesView(model: voices) }
                NavigationLink("About") { AboutView(info: AboutInfo.current()) }
                if let onboarding {
                    Button(Self.showTutorialTitle) { onboarding.reset() }
                        .accessibilityHint("Opens the first-run tutorial again")
                }
            }

            if let diagnostics {
                Section("Diagnostics") {
                    NavigationLink("Broadcast diagnostics") { BroadcastDiagnosticsView(model: diagnostics) }
                }
            }
        }
        .navigationTitle("Settings")
    }

    static let showTutorialTitle = "Show the tutorial"

    static func title(for preset: SegmenterPreset) -> String {
        switch preset {
        case .balanced: return "Balanced"
        case .fast: return "Fast"
        case .veryFast: return "Very fast"
        }
    }

    static func title(for mode: Settings.TimeDisplay) -> String { SettingsViewModel.timeDisplayTitle(mode) }
}

/// Speech, then the silence the preset waits for, then the phrase: the three presets side by side in one glance.
struct LatencyTimeline: View {
    let preset: SegmenterPreset

    var body: some View {
        HStack(spacing: 6) {
            Capsule().fill(Color.accentColor).frame(width: 56, height: 8)
                .accessibilityLabel("speech")
            Capsule().fill(Color.secondary.opacity(0.35)).frame(width: CGFloat(preset.silenceMs) / 6, height: 8)
                .accessibilityLabel("\(preset.silenceMs) milliseconds of silence")
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
            Text("phrase ready · \(preset.silenceMs) ms, max \(Int(preset.maxSegmentSeconds)) s")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}

/// Other apps' level while ReVox speaks: the dip in the middle is the duck.
struct DuckingBars: View {
    let ducking: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<12, id: \.self) { index in
                let speaking = (4...7).contains(index)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(speaking ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: speaking && ducking ? 6 : 14)
            }
            Text(ducking ? "other apps duck while ReVox speaks" : "other apps unchanged")
                .font(.caption2).foregroundStyle(.secondary).padding(.leading, 4)
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }
}
