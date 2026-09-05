import Foundation

/// The text a failure shows the user: a model row's "Failed: …", the download alert, the Live banner's reason,
/// the speaker fallback reason.
///
/// `String(describing:)` is right for ReVox's own errors — `CustomStringConvertible`, a sentence for a description —
/// and wrong for everything Foundation bridges: a `URLError` describes itself as
/// `URLError(_nsError: Error Domain=NSURLErrorDomain Code=-1009 "…" UserInfo={…})`, which is what a download row
/// read after airplane mode. `localizedDescription` is the reverse: right for the bridged errors and, for a plain
/// Swift error, "The operation couldn't be completed. (ReVoxMobile.X error 0.)". One rule, applied per error.
enum UserFacingErrorText {
    static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let text = localized.errorDescription, !text.isEmpty {
            return text
        }
        // Before the description check, not after: an `NSError` describes itself as
        // `Error Domain=NSURLErrorDomain Code=-1009 "(null)"`, and `URLError`, `CocoaError` and every other
        // `CustomNSError` reach `CustomStringConvertible` through that bridge (CI run 106 showed the domain line).
        if error is CustomNSError || type(of: error) is NSError.Type {
            return (error as NSError).localizedDescription
        }
        if let described = error as? CustomStringConvertible {
            return described.description
        }
        return String(describing: error)
    }
}
