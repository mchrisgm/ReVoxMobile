import XCTest

/// Polls a main-actor condition until it holds or the timeout elapses (view models publish asynchronously).
@MainActor
func waitUntil(_ description: String = "condition", timeout: TimeInterval = 2, file: StaticString = #filePath, line: UInt = #line,
               _ condition: @MainActor () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            XCTFail("timed out waiting for \(description)", file: file, line: line)
            return
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}
