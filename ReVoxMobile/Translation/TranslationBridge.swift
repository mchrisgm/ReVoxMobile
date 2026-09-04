import Foundation
import os
import ReVoxCore

/// The seam Apple's on-device translator reaches the pipeline through (M8, §8.2).
///
/// Whisper's translate task emits English and nothing else, so the second direction of a two-way conversation —
/// the ignored language out to the other person's language — needs a text-to-text engine. Apple's session is
/// created by SwiftUI's `translationTask` and is valid only inside that task, so it is never handed across:
/// the Live screen takes a stream of phrases from here, answers each one with its session, and the pipeline
/// simply awaits its answer. Nothing serving the pair it asks for is `nil`, which the routing already reads as
/// "keep it in the transcript, say nothing".
actor TranslationBridge: SecondaryTranslator {
    struct Request: Sendable, Equatable {
        let id: UUID
        let text: String
    }

    /// What one serving session holds: the phrases to answer, and the token that ends exactly this serving.
    struct Serving: Sendable {
        let token: Int
        let requests: AsyncStream<Request>
    }

    private static let logger = Logger(subsystem: "revox", category: "translation")

    private var servedSource: String?
    private var servedTarget: String?
    private var outbox: AsyncStream<Request>.Continuation?
    private var waiting: [UUID: CheckedContinuation<String?, Never>] = [:]
    private var token = 0

    /// The pair currently served. nil while nothing is attached.
    var servedPair: (source: String, target: String)? {
        guard let servedSource, let servedTarget else { return nil }
        return (servedSource, servedTarget)
    }

    /// Replaces whatever was serving before — a changed pair takes over, and the phrases the old session never
    /// answered are released rather than left waiting.
    func serve(from source: String, to target: String) -> Serving {
        release()
        token &+= 1
        servedSource = source
        servedTarget = target
        let (stream, continuation) = AsyncStream.makeStream(of: Request.self)
        outbox = continuation
        return Serving(token: token, requests: stream)
    }

    func complete(_ id: UUID, with translated: String?) {
        waiting.removeValue(forKey: id)?.resume(returning: translated)
    }

    /// The session went away. A serving that has already been replaced withdraws nothing, so a task ending after
    /// its successor started cannot take the successor down with it.
    func withdraw(_ token: Int) {
        guard token == self.token else { return }
        release()
    }

    private func release() {
        servedSource = nil
        servedTarget = nil
        outbox?.finish()
        outbox = nil
        let pending = waiting
        waiting = [:]
        for continuation in pending.values {
            continuation.resume(returning: nil)   // transcript-only, never a phrase left hanging
        }
    }

    /// nil rather than a throw for every failure: an engine that cannot produce this phrase must not put the
    /// pipeline into `.error` — the phrase belongs in the transcript either way (§8.2).
    func translate(_ text: String, from source: String, to target: String) async throws -> String? {
        guard let outbox, servedSource == source, servedTarget == target else { return nil }
        let request = Request(id: UUID(), text: text)
        let translated = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            waiting[request.id] = continuation
            outbox.yield(request)
        }
        guard let translated else {
            Self.logger.info("no second direction for \(source, privacy: .public)->\(target, privacy: .public)")
            return nil
        }
        return translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : translated
    }
}
