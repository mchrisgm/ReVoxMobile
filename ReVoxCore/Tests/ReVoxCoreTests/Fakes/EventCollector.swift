import Foundation
@testable import ReVoxCore

/// Drains a pipeline's event stream into a snapshot the test can inspect at any time.
final class EventCollector: @unchecked Sendable {
    private let box = LockedBox<[PipelineEvent]>([])
    private var task: Task<Void, Never>?

    func start(_ pipeline: TranslationPipeline) {
        let box = box
        task = Task {
            for await event in pipeline.events {
                box.update { $0.append(event) }
            }
        }
    }

    var events: [PipelineEvent] { box.value }

    var states: [PipelineState] {
        events.compactMap {
            if case .state(let state) = $0 { return state }
            return nil
        }
    }

    var speakingEdges: [Bool] {
        events.compactMap {
            if case .speaking(let speaking) = $0 { return speaking }
            return nil
        }
    }

    var hasLag: Bool { events.contains(.lag) }
    var hasEntry: Bool { events.contains { if case .entry = $0 { return true }; return false } }
    var hasError: Bool { events.contains { if case .error = $0 { return true }; return false } }

    func stop() {
        task?.cancel()
    }
}
