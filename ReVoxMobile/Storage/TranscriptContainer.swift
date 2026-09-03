import Foundation
import SwiftData

/// The transcript store lives in the app container, never the App Group, and never syncs (§6.10, §11).
enum TranscriptContainer {
    static let storeName = "ReVoxTranscripts"

    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([Session.self, Entry.self])
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
