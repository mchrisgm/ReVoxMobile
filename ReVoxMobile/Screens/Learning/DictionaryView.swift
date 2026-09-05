import SwiftUI
import UIKit

/// A word in the iPhone's own dictionaries (M11 §2). No API returns definition text, so this is the system view,
/// in a sheet the popover opens after it has dismissed itself. Only the dictionaries the user has downloaded in
/// Settings › General › Dictionary answer; the popover offers the sheet only when `dictionaryHasDefinition` said so.
struct DictionaryTerm: Identifiable, Equatable {
    let term: String
    var id: String { term }
}

struct DictionaryView: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}
