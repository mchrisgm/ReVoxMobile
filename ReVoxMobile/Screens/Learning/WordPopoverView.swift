import SwiftUI

/// The word popover's content (M11 §2): the word and its language with a 44 pt Close; Pronunciation (the Latin
/// form, the Say button or the voice note); Meaning (progress, the text or a note, then the dictionary button or
/// its note); In this sentence (the original with the word highlighted, and the English). A popover on iPhone at
/// the regular text sizes, a medium/large sheet at the accessibility sizes, where a 300 pt column would be one
/// narrow strip. Hostable on its own, which is how the tests and the screenshots render it.
struct WordPopoverView: View {
    let model: WordPopoverModel
    var onLookUp: (String) -> Void = { _ in }
    var onClose: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static let idealWidth: CGFloat = 300
    static let maximumWidth: CGFloat = 360
    /// The frame sits inside each button's label, so the hit area is the 44 pt the audit records, not the border.
    static let buttonHeight: CGFloat = 44

    var body: some View {
        let content = model.content
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(content)
                pronunciation(content)
                meaning(content)
                example(content)
            }
            .padding(16)
        }
        .frame(idealWidth: Self.idealWidth, maxWidth: Self.maximumWidth)
        .presentationCompactAdaptation(dynamicTypeSize.isAccessibilitySize ? .sheet : .popover)
        .presentationDetents([.medium, .large])
        .modifier(WordTranslation(word: model.translationRequest, language: model.language,
                                  onResult: { model.receiveMeaning($0) }))
        .task { await model.load() }
    }

    private func header(_ content: WordPopoverContent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(content.word).font(.title3.weight(.semibold))
                Text(content.languageName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.buttonHeight, height: Self.buttonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WordPopoverContent.closeLabel)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func pronunciation(_ content: WordPopoverContent) -> some View {
        sectionHeader(WordPopoverContent.pronunciationHeader)
        if let latin = content.latin {
            Text(latin).font(.body)
        }
        if let speaker = model.speaker, content.hasVoice {
            Button {
                model.speak()
            } label: {
                Label(speaker.isSpeaking ? WordPopoverContent.speakingTitle : WordPopoverContent.speakTitle(content.word),
                      systemImage: speaker.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                    .frame(minHeight: Self.buttonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .disabled(!content.canSpeak)
            .accessibilityLabel(WordPopoverContent.speakAccessibilityLabel(word: content.word, languageName: content.languageName))
            .accessibilityHint(content.canSpeak ? WordPopoverContent.speakHint(languageName: content.languageName)
                                                : WordPopoverContent.microphoneNote)
            if let note = content.speakDisabledNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        } else if let note = content.voiceNote {
            Text(note).font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func meaning(_ content: WordPopoverContent) -> some View {
        sectionHeader(WordPopoverContent.meaningHeader)
        switch content.meaning {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text(WordPopoverContent.translatingText).font(.callout).foregroundStyle(.secondary)
            }
        case .found(let text):
            Text(text).font(.body)
        case .note(let note):
            Text(note).font(.callout).foregroundStyle(.secondary)
        }
        if content.showsDictionaryButton {
            Button {
                onLookUp(content.word)
            } label: {
                Label(WordPopoverContent.dictionaryButtonTitle, systemImage: "book")
                    .frame(minHeight: Self.buttonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .accessibilityHint(WordPopoverContent.dictionaryHint)
        } else if let note = content.dictionaryNote {
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func example(_ content: WordPopoverContent) -> some View {
        sectionHeader(WordPopoverContent.exampleHeader)
        Self.highlightedSentence(content.example).font(.body).foregroundStyle(.secondary)
        Text(content.example.english).font(.body)
    }

    /// The sentence with the word bold and underlined — two cues beside the chip's colour, never colour alone.
    static func highlightedSentence(_ example: WordPopoverContent.Example) -> Text {
        let sentence = example.original
        let before = String(sentence[sentence.startIndex..<example.range.lowerBound])
        let word = String(sentence[example.range])
        let after = String(sentence[example.range.upperBound..<sentence.endIndex])
        return Text(before) + Text(word).bold().underline() + Text(after)
    }
}
