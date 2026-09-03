import XCTest

/// Polls a main-actor condition until it holds or the timeout elapses (view models publish asynchronously).
///
/// `details` is read only when the wait times out, so a failure says what the state actually was instead of
/// only what it was supposed to be.
@MainActor
func waitUntil(_ description: String = "condition", timeout: TimeInterval = 2, file: StaticString = #filePath, line: UInt = #line,
               details: (@MainActor () -> String)? = nil,
               _ condition: @MainActor () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            let suffix = details.map { " — \($0())" } ?? ""
            XCTFail("timed out waiting for \(description)\(suffix)", file: file, line: line)
            return
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}
