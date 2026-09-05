import Foundation
@testable import ReVoxCore

struct FakeTranslatorError: Error {}

/// The Windows `FakeTranslator`: a gate that blocks `translate` until opened, a `fail` flag, records of every call.
/// Returns "text-N" for the N-th call unless explicit segments were given. M11: `segmentsPerCall` scripts the
/// segments call by call (consumed in order, then `segments` / "text-N" as before).
actor FakeTranslator: Translator {
    private let language: String
    private let segments: [TranslationSegment]?
    private var segmentsPerCall: [[TranslationSegment]]
    private let fail: Bool
    private var open: Bool
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private(set) var calls: [[Float]] = []
    private(set) var languages: [String] = []

    init(language: String = "es", segments: [TranslationSegment]? = nil, segmentsPerCall: [[TranslationSegment]]? = nil,
         fail: Bool = false, blocked: Bool = false) {
        self.language = language
        self.segments = segments
        self.segmentsPerCall = segmentsPerCall ?? []
        self.fail = fail
        open = !blocked
    }

    /// Opens the gate (`translator.gate.set()`).
    func openGate() {
        open = true
        let pending = waiters
        waiters.removeAll()
        waiterIDs.removeAll()   // keeps the two arrays parallel; a cancellation landing after the gate opens finds no id
        for waiter in pending {
            waiter.resume()
        }
    }

    func translate(_ audio: [Float], language requested: String) async throws -> TranslationCandidate {
        try await waitForGate()
        if fail {
            throw FakeTranslatorError()
        }
        calls.append(audio)
        languages.append(requested)
        let produced: [TranslationSegment]
        if !segmentsPerCall.isEmpty {
            produced = segmentsPerCall.removeFirst()
        } else {
            produced = segments ?? [TranslationSegment(text: "text-\(calls.count)", noSpeechProbability: 0, averageLogProbability: 0)]
        }
        return TranslationCandidate(language: language, languageProbability: nil, segments: produced)
    }

    private func waitForGate() async throws {
        guard !open else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                register(continuation, id: id)
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    private var waiterIDs: [UUID] = []

    private func register(_ continuation: CheckedContinuation<Void, Error>, id: UUID) {
        if open || Task.isCancelled {
            open ? continuation.resume() : continuation.resume(throwing: CancellationError())
            return
        }
        waiters.append(continuation)
        waiterIDs.append(id)
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiterIDs.firstIndex(of: id), index < waiters.count else { return }
        let continuation = waiters.remove(at: index)
        waiterIDs.remove(at: index)
        continuation.resume(throwing: CancellationError())
    }
}
