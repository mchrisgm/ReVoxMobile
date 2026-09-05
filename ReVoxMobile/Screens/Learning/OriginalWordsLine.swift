import SwiftUI

/// The original line of a Learning row as tappable words (M11 §2): chips tiled by `WordFlowLayout`, each a
/// Button at least 44 pt tall with no minimum width (the chips tile the line, so every touch lands on a word,
/// and a Japanese particle stays one character wide); the selected word under a rounded accent highlight in
/// `Color.primary` — two cues, constant weight, so nothing shifts under the finger; one popover per row through
/// the row's `lookup` state; and the dictionary sheet the popover hands over to after it has dismissed.
///
/// One VoiceOver element labelled with the sentence, so the combined row reads exactly as it does without chips;
/// the words are reached through `WordLookUpActions` on the row.
struct OriginalWordsLine: View {
    let original: String
    let language: String
    let english: String
    let words: [OriginalWord]
    @Binding var lookup: WordPopoverModel?

    @Environment(\.wordLookup) private var wordLookup
    @State private var dictionaryTerm: DictionaryTerm?
    @State private var pendingDictionaryTerm: String?

    /// The HIG target height (docs/hig-audit/checks.json, `learning-word-chip`).
    static let chipMinimumHeight: CGFloat = 44
    static let chipCornerRadius: CGFloat = 6
    /// Accent (#12788C) at 22 % over white ≈ #CBE1E6 — `learning-word-selected` in checks.json.
    static let selectedFillOpacity = 0.22
    static let chipHorizontalPadding: CGFloat = 3   // 6 pt between words: a space, not a gap (CI run 123)
    static let chipVerticalPadding: CGFloat = 2
    /// VoiceOver custom actions per row: a long row would otherwise put thirty actions before the row's own.
    static let customActionLimit = 12

    var body: some View {
        WordFlowLayout {
            ForEach(words) { word in
                chip(word)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(original)
        .sheet(item: $dictionaryTerm) { term in
            DictionaryView(term: term.term)
                .presentationDragIndicator(.visible)
                .ignoresSafeArea()
        }
    }

    static func actionWords(_ words: [OriginalWord]) -> [OriginalWord] {
        Array(words.prefix(customActionLimit))
    }

    /// The row's tap and its VoiceOver action. An open popover is closed first and the new model staged on the
    /// next run-loop turn: UIKit refuses to present while a dismissal is in flight, and flipping two
    /// `isPresented` bindings in one update would leave `lookup` pointing at a word with no popover.
    @MainActor
    static func select(_ word: OriginalWord, language: String, original: String, english: String,
                       lookup service: WordLookup, into binding: Binding<WordPopoverModel?>) {
        let model = WordPopoverModel(word: word, language: language, original: original, english: english, lookup: service)
        guard binding.wrappedValue != nil else {
            binding.wrappedValue = model
            return
        }
        binding.wrappedValue = nil
        Task { @MainActor in
            binding.wrappedValue = model
        }
    }

    private func chip(_ word: OriginalWord) -> some View {
        let isSelected = lookup?.word == word
        return Button {
            Self.select(word, language: language, original: original, english: english, lookup: wordLookup, into: $lookup)
        } label: {
            Text(word.text)
                .font(.body)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, Self.chipHorizontalPadding)
                .padding(.vertical, Self.chipVerticalPadding)
                .background(isSelected ? Color.accentColor.opacity(Self.selectedFillOpacity) : Color.clear,
                            in: RoundedRectangle(cornerRadius: Self.chipCornerRadius))
                .frame(minHeight: Self.chipMinimumHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(LivePillButtonStyle())
        .popover(isPresented: isPresented(word)) {
            if let model = lookup, model.word == word {
                WordPopoverView(
                    model: model,
                    onLookUp: { term in
                        // The sheet is presented from `onDisappear`, never while the popover is still animating away.
                        pendingDictionaryTerm = term
                        lookup = nil
                    },
                    onClose: { lookup = nil }
                )
                .onDisappear {
                    if let term = pendingDictionaryTerm {
                        pendingDictionaryTerm = nil
                        dictionaryTerm = DictionaryTerm(term: term)
                    }
                }
            }
        }
    }

    private func isPresented(_ word: OriginalWord) -> Binding<Bool> {
        Binding(
            get: { lookup?.word == word },
            set: { shown in
                if !shown, lookup?.word == word { lookup = nil }
            }
        )
    }
}

/// The row's VoiceOver custom actions, "Look up ‹word›" for the first `customActionLimit` words (M11 §2). The
/// row view applies it to its combined entry element beside the `OriginalWordsLine` it renders, so the actions
/// are on the row itself and certain to appear.
struct WordLookUpActions: ViewModifier {
    let words: [OriginalWord]
    let language: String
    let original: String
    let english: String
    @Binding var lookup: WordPopoverModel?
    @Environment(\.wordLookup) private var wordLookup

    func body(content: Content) -> some View {
        content.accessibilityActions {
            ForEach(OriginalWordsLine.actionWords(words)) { word in
                Button(WordPopoverContent.lookUpActionTitle(word.text)) {
                    OriginalWordsLine.select(word, language: language, original: original, english: english,
                                             lookup: wordLookup, into: $lookup)
                }
            }
        }
    }
}
