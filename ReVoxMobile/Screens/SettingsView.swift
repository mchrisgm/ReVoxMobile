import SwiftUI
import ReVoxCore

struct SettingsView: View {
    @Bindable var model: SettingsViewModel
    let models: ModelsViewModel

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
                NavigationLink("Models") { ModelsView(model: models) }
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
