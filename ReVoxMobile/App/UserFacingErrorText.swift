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
        if let described = error as? CustomStringConvertible {
            return described.description
        }
        // A native Swift error bridges to an `NSError` whose domain is its qualified type name; an `NSError`, a
        // `URLError`, a `CocoaError` or any `CustomNSError` carries a Foundation domain and a localized sentence.
        let bridged = error as NSError
        if bridged.domain != String(reflecting: type(of: error)) {
            return bridged.localizedDescription
        }
        return String(describing: error)
    }
}
