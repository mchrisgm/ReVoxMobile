import SwiftUI

/// LANGUAGES: Two-way and Learning, and — only while Two-way is on — the full-width pair line "You speak" /
/// "They speak" beneath them (M11 §1). The pair has its own flow, so long names wrap inside the pair line and never
/// into the toggles' row. The tutorial hosts this group as it is (§6).
struct LiveLanguagesGroup: View {
    let model: any LiveControlsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLocked: Bool { LiveControlStrip.locksControls(in: model.state) }

    var body: some View {
        VStack(alignment: .leading, spacing: LiveControlStrip.pillSpacing) {
            LiveControlGroup(caption: LiveControlStrip.languagesCaption) {
                twoWayPill
                learningPill
            }
            if model.isTwoWay {
                PillFlowLayout(spacing: LiveControlStrip.pillSpacing) {
                    youSpeakPill
                    theySpeakPill
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LiveControlStrip.languagesCaption)
        .animation(reduceMotion ? nil : .default, value: model.isTwoWay)
    }

    private var twoWayPill: some View {
        Toggle(isOn: Binding(get: { model.isTwoWay }, set: { model.isTwoWay = $0 })) {
            LiveControlPill(systemImage: "arrow.left.arrow.right",
                            title: LiveControlStrip.togglePillTitle(LiveControlStrip.twoWayPillName, isOn: model.isTwoWay), isOn: model.isTwoWay)
        }
        .toggleStyle(LivePillToggleStyle())
        .disabled(isLocked)
        .accessibilityLabel("Two-way conversation")
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : LiveView.twoWayHintText)
    }

    private var learningPill: some View {
        Toggle(isOn: Binding(get: { model.isLearning }, set: { model.isLearning = $0 })) {
            LiveControlPill(systemImage: model.isLearning ? "text.book.closed.fill" : "text.book.closed",
                            title: LiveControlStrip.togglePillTitle(LiveControlStrip.learningPillName, isOn: model.isLearning), isOn: model.isLearning)
        }
        .toggleStyle(LivePillToggleStyle())
        .disabled(isLocked)
        .accessibilityLabel("Learning mode")
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : LiveControlStrip.learningHelpText)
    }

    /// Backed by `Settings.ignoredLanguage`, the same setting as Settings › Your language. No "Not set" row here:
    /// the pill says "Choose…" until one is chosen, and unsetting lives in Settings. Disabled while a source
    /// language is pinned, with the note that says why and where.
    private var youSpeakPill: some View {
        let name = model.ignoredLanguage.map { LanguageCatalog.displayName($0, whenNil: LiveView.noLanguageTitle) }
        return Menu {
            Picker(LiveControlStrip.youSpeakTitle, selection: Binding(get: { model.ignoredLanguage }, set: { model.ignoredLanguage = $0 })) {
                ForEach(LanguageCatalog.concrete) { option in
                    Text(option.displayName).tag(option.code)
                }
            }
        } label: {
            LiveControlPill(systemImage: nil, title: LiveControlStrip.youSpeakTitle, value: name ?? LiveControlStrip.chooseLanguageTitle)
        }
        .disabled(isLocked || !model.canChooseYourLanguage)
        .accessibilityLabel(LiveControlStrip.youSpeakTitle)
        .accessibilityValue(name ?? LiveView.noLanguageTitle)
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : (model.pinnedSourceNote ?? LiveControlStrip.youSpeakHintText))
    }

    /// Backed by `Settings.twoWayLanguage` through `theySpeak`: English is a real, ticked row, never "None".
    private var theySpeakPill: some View {
        let name = LanguageCatalog.displayName(model.theySpeak, whenNil: LiveView.noLanguageTitle)
        let hasVoice = model.twoWayVoiceNote == nil
        return Menu {
            Picker(LiveControlStrip.theySpeakTitle, selection: Binding(get: { model.theySpeak }, set: { model.theySpeak = $0 })) {
                ForEach(LanguageCatalog.concrete) { option in
                    Text(option.displayName).tag(option.code ?? "en")
                }
            }
        } label: {
            LiveControlPill(systemImage: hasVoice ? nil : "speaker.slash", title: LiveControlStrip.theySpeakTitle, value: name)
        }
        .disabled(isLocked)
        .accessibilityLabel(LiveControlStrip.theySpeakTitle)
        .accessibilityValue(LiveControlStrip.theySpeakAccessibilityValue(name: name, hasVoice: hasVoice))
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : (model.twoWayVoiceNote ?? LiveControlStrip.theySpeakHintText))
    }
}
