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

/// The nonisolated twin of `waitUntil`, for state that lives behind a lock rather than on the main actor.
///
/// A fixed `Task.sleep` "long enough for the tick to have fired" is what makes a timing test flaky: it passes on
/// an idle machine and fails on a loaded CI runner, where a 20 ms monitor tick can take far longer than 80 ms to
/// come back round. Polling to a generous deadline is as fast on a quiet machine and does not lie on a busy one.
func waitFor(_ description: String = "condition", timeout: TimeInterval = 5,
             file: StaticString = #filePath, line: UInt = #line,
             _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            XCTFail("timed out waiting for \(description)", file: file, line: line)
            return
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}
