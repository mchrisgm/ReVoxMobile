import Foundation

/// One row of the source-language picker; `code == nil` is "Auto-detect" (§8.5).
struct LanguageOption: Identifiable, Equatable, Sendable {
    let code: String?
    let displayName: String

    var id: String { code ?? "auto" }
}
