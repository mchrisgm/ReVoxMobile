import SwiftUI
import ReVoxCore

struct SettingsView: View {
    @Bindable var model: SettingsViewModel
    let models: ModelsViewModel
    let voices: VoicesViewModel
    var diagnostics: BroadcastDiagnosticsModel? = nil

    var body: some View {
        Form {
            Section("Latency mode") {
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
            } footer: {
                Text("Auto-detect runs Whisper's language detection on every phrase and drops phrases it is unsure about.")
            }

            Section("Voice") {
                Toggle("Mute voice", isOn: $model.isMuted)
                    .accessibilityHint("Silences the English voice while the transcript keeps running")
            }

            Section {
                Toggle("Duck other audio while speaking", isOn: $model.ducking)
                    .accessibilityHint("Lowers other apps' audio while the English voice plays")
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
            } header: {
                Text("Ducking")
            } footer: {
                Text("\(SettingsViewModel.duckingHelpText)\n\(SettingsViewModel.duckingAppliesOnStartText)")
            }

            Section {
                NavigationLink("Models") { ModelsView(model: models) }
                NavigationLink("Voices") { VoicesView(model: voices) }
            }

            if let diagnostics {
                Section("Diagnostics") {
                    NavigationLink("Broadcast diagnostics") { BroadcastDiagnosticsView(model: diagnostics) }
                }
            }
        }
        .navigationTitle("Settings")
    }

    static func title(for preset: SegmenterPreset) -> String {
        switch preset {
        case .balanced: return "Balanced"
        case .fast: return "Fast"
        }
    }
}
