import Foundation
import SwiftData
import ReVoxCore

/// The SwiftData `TranscriptSink` for one session (§6.10). A context that is not `mainContext` has
/// `autosaveEnabled == false`, so every write is followed by an explicit `save()`, coalesced to at most
/// one per second while entries arrive faster than that; `close()` always saves.
///
/// The `@ModelActor` macro is deliberately not used: it synthesises `init(modelContainer:)`, which cannot
/// initialise this actor's own `metadata` and `recorder` and so fails to compile. Actor isolation gives the
/// context the serial access it needs — every use of `modelContext` below is isolated to this actor.
actor TranscriptStore: TranscriptSink {
    static let saveInterval: TimeInterval = 1

    nonisolated let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let metadata: SessionMetadata
    private let recorder: TranscriptRecorder
    /// The session row itself, not its `PersistentIdentifier`: the identifier of an unsaved model is temporary
    /// and stops resolving once the insert is saved, which traps in `model(for:)` (run 33771885792). The actor
    /// owns the context, so holding the model is safe and needs no re-fetch.
    private var session: Session?
    private var lastSaveAt: Date = .distantPast
    private var pendingSave: Task<Void, Never>?
    private(set) var lastSaveError: String?
    private(set) var saveCount = 0

    init(modelContainer: ModelContainer, metadata: SessionMetadata) {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        self.modelContainer = modelContainer
        self.modelContext = context
        self.metadata = metadata
        self.recorder = TranscriptRecorder(startedAt: metadata.startedAt)
    }

    /// Resolvable only after the first save; nil before the session row exists.
    var sessionIdentifier: PersistentIdentifier? { session?.persistentModelID }

    // MARK: TranscriptSink

    func add(_ entry: TranscriptEntry) async {
        let closed = await recorder.isClosed
        guard !closed else { return }
        await recorder.add(entry)
        let session = ensureSession()
        let row = Entry(timestamp: entry.timestamp, language: entry.language, original: entry.original, english: entry.english,
                        isDropMarker: false, isGuess: entry.isGuess)
        row.session = session
        modelContext.insert(row)
        scheduleSave()
    }

    /// The core recorder holds the Windows dedupe rule (`_last_was_drop`): a marker is stored only when the recorder kept it.
    func addDropMarker(at time: Date) async {
        let before = await recorder.items.count
        await recorder.addDropMarker(at: time)
        guard await recorder.items.count > before else { return }
        let session = ensureSession()
        let row = Entry(timestamp: time, language: "", original: "", english: "", isDropMarker: true)
        row.session = session
        modelContext.insert(row)
        scheduleSave()
    }

    func close() async {
        let closed = await recorder.isClosed
        guard !closed else { return }
        await recorder.close()
        let session = ensureSession()
        session.endedAt = Date()
        saveNow()
    }

    // MARK: Saves

    /// Saves immediately when the last save is older than `saveInterval`; otherwise one timer flushes later.
    private func scheduleSave() {
        if Date().timeIntervalSince(lastSaveAt) >= Self.saveInterval {
            saveNow()
            return
        }
        guard pendingSave == nil else { return }
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.saveInterval * 1_000_000_000))
            await self?.flushPending()
        }
    }

    private func flushPending() {
        pendingSave = nil
        saveNow()
    }

    private func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try modelContext.save()
            lastSaveAt = Date()
            lastSaveError = nil
            saveCount += 1
        } catch {
            lastSaveError = String(describing: error)   // retried on the next write
        }
    }

    /// Test and shutdown hook: forces the pending save.
    func flush() {
        saveNow()
    }

    private func ensureSession() -> Session {
        if let session { return session }
        let created = Session(
            startedAt: metadata.startedAt,
            captureMode: metadata.captureMode.rawValue,
            pinnedLanguage: metadata.pinnedLanguage,
            modelID: metadata.modelID,
            voice: metadata.voice,
            joinedInProgress: metadata.joinedInProgress
        )
        modelContext.insert(created)
        session = created
        return created
    }

    // MARK: Export (the M6 exporter reuses `items(from:)`)

    func exportText() async -> String {
        await recorder.exportText()
    }

    static func items(from entries: [Entry]) -> [TranscriptItem] {
        entries.map { row in
            if row.isDropMarker {
                return .dropMarker(row.timestamp)
            }
            return .entry(TranscriptEntry(timestamp: row.timestamp, language: row.language, original: row.original, english: row.english,
                                          isGuess: row.isGuess))
        }
    }
}
