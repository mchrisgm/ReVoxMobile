import Foundation
import os
import ReVoxCore

/// §9 row 2: one unload/reload retry after a Whisper failure mid-run before the error reaches the pipeline.
/// The wrapped `WhisperKitTranslator` is an actor, so no transcribe is in flight while the model is reloaded
/// (§6.4: never unload mid-transcribe). The budget is one reload per pipeline run — a permanently broken model
/// therefore surfaces on the second failure instead of reloading forever, and the pipeline enters `.error` with
/// the Windows semantics.
actor RecoveringTranslator: Translator, LanguageDetector {
    static let maxReloads = 1

    enum RecoveryEvent: Equatable, Sendable {
        case reloaded
        case reloadFailed(String)
        case gaveUp(String)
    }

    private static let logger = Logger(subsystem: "revox", category: "translation")

    private let inner: any Translator & LanguageDetector
    private let whisper: WhisperKitTranslator
    private let model: WhisperModelID
    private let onEvent: @Sendable (RecoveryEvent) -> Void
    private var reloads = 0

    init(_ inner: any Translator & LanguageDetector, reloading whisper: WhisperKitTranslator, model: WhisperModelID,
         onEvent: @escaping @Sendable (RecoveryEvent) -> Void = { _ in }) {
        self.inner = inner
        self.whisper = whisper
        self.model = model
        self.onEvent = onEvent
    }

    var reloadCount: Int { reloads }

    func detectLanguage(in audio: [Float]) async throws -> LanguageDetection {
        do {
            return try await inner.detectLanguage(in: audio)
        } catch {
            try await reload(after: error)
            return try await inner.detectLanguage(in: audio)
        }
    }

    func translate(_ audio: [Float], language: String) async throws -> TranslationCandidate {
        do {
            return try await inner.translate(audio, language: language)
        } catch {
            try await reload(after: error)
            return try await inner.translate(audio, language: language)
        }
    }

    /// Unloads and reloads the model once. Rethrows the **original** error when the budget is spent, when the caller
    /// was cancelled (the pipeline is stopping) or when the reload itself fails, so the pipeline sees what Windows saw.
    private func reload(after error: Error) async throws {
        if error is CancellationError { throw error }
        guard reloads < Self.maxReloads else {
            onEvent(.gaveUp(String(describing: error)))
            Self.logger.error("whisper failed again after a reload model=\(self.model.rawValue, privacy: .public)")
            throw error
        }
        reloads += 1
        Self.logger.notice("reloading whisper after a failure model=\(self.model.rawValue, privacy: .public)")
        await whisper.unload()
        do {
            try await whisper.load(progress: { _ in })
        } catch let reloadError {
            // The pipeline is told what actually failed first; the reload failure goes to the event and the log.
            onEvent(.reloadFailed(String(describing: reloadError)))
            Self.logger.error("whisper reload failed model=\(self.model.rawValue, privacy: .public)")
            throw error
        }
        onEvent(.reloaded)
    }
}

/// A late-bound, thread-safe sink for `RecoveringTranslator` events. `PipelineAssembler` owns one for the app's
/// lifetime and installs it on every translator it builds; `AppEnvironment` fills in the handler once the
/// `DegradationCoordinator` exists, which is after the assembler and its supplier were created. Until then —
/// and in every test that builds a pipeline — an event is simply dropped.
final class WhisperRecoverySink: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (RecoveringTranslator.RecoveryEvent) -> Void)?

    func set(_ handler: @escaping @Sendable (RecoveringTranslator.RecoveryEvent) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func send(_ event: RecoveringTranslator.RecoveryEvent) {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        handler?(event)
    }
}
