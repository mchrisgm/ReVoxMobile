import Foundation
@testable import ReVoxCore

/// Counts `duck()` and every `restore()`, tolerates repeats, records the call order. With `holdRestore = true`
/// its `restore()` suspends on a continuation until `resumeRestore()` is called.
actor FakeDucker: Ducker {
    private(set) var ducked = 0
    private(set) var restored = 0
    private(set) var restoreEntered = 0
    private(set) var order: [String] = []
    private var holdRestore: Bool
    private var suspendedRestores: [CheckedContinuation<Void, Never>] = []

    init(holdRestore: Bool = false) {
        self.holdRestore = holdRestore
    }

    func duck() async {
        ducked += 1
        order.append("duck")
    }

    func restore() async {
        restoreEntered += 1
        order.append("restore")
        if holdRestore {
            await withCheckedContinuation { continuation in
                suspendedRestores.append(continuation)
            }
        }
        restored += 1
    }

    /// Number of `restore()` calls currently suspended.
    var suspendedCount: Int { suspendedRestores.count }

    func resumeRestore() {
        let pending = suspendedRestores
        suspendedRestores.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}
