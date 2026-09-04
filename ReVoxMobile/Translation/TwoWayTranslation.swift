import SwiftUI
import Translation

/// Attaches Apple's on-device translator to the Live screen while two-way translation is on (M8, §8.2).
///
/// The framework is iOS 18; ReVox runs on iOS 17, where this modifier does nothing and the second direction stays
/// transcript-only — the same outcome as an iPhone with no model for the pair, which is already handled.
struct TwoWayTranslation: ViewModifier {
    /// The language coming in that ReVox is not translating to English — the second direction's source.
    let source: String?
    let target: String?
    let bridge: TranslationBridge?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.modifier(AppleTranslation(source: source, target: target, bridge: bridge))
        } else {
            content
        }
    }
}

@available(iOS 18, *)
private struct AppleTranslation: ViewModifier {
    let source: String?
    let target: String?
    let bridge: TranslationBridge?

    /// nil takes the session down; a changed pair replaces it. `Configuration` is `Equatable`, so SwiftUI restarts
    /// the task only when the pair actually changes.
    private var configuration: TranslationSession.Configuration? {
        guard bridge != nil, let source, let target, source != target else { return nil }
        return TranslationSession.Configuration(source: Locale.Language(identifier: source),
                                                target: Locale.Language(identifier: target))
    }

    func body(content: Content) -> some View {
        content.translationTask(configuration) { session in
            guard let bridge, let source, let target else { return }
            // Downloads the pair if the user agrees; a decline throws and nothing is served, so the second
            // direction stays transcript-only rather than failing the run.
            do {
                try await session.prepareTranslation()
            } catch {
                return
            }
            // The session never leaves this task: the bridge hands over phrases, and each answer goes back by id.
            let serving = await bridge.serve(from: source, to: target)
            for await request in serving.requests {
                let translated = try? await session.translate(request.text).targetText
                await bridge.complete(request.id, with: translated)
            }
            await bridge.withdraw(serving.token)
        }
    }
}
