import SwiftUI
import SwiftData
import ReVoxCore

/// The History tab (§8.6): sessions newest first, search over the English text, swipe-to-delete, confirmed Clear All.
struct HistoryView: View {
    static let emptyTitle = "No Transcripts"
    static let emptyDescription = "Sessions you translate appear here."
    static let searchPrompt = "Search English text"

    /// The environment's exporter, handed on to every pushed `SessionDetailView` so the whole tab writes
    /// into one export directory — the one that is pruned at launch, and a per-root one under test.
    let exporter: TranscriptExporter

    @Environment(\.modelContext) private var context
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @State private var query: String
    @State private var result = SearchResult(hits: [], usedFallback: false)
    @State private var searchError: String?
    @State private var confirmingClearAll = false
    @State private var actionError: String?

    init(initialQuery: String = "", exporter: TranscriptExporter = TranscriptExporter()) {
        _query = State(initialValue: initialQuery)
        self.exporter = exporter
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(Self.emptyTitle, systemImage: "text.bubble", description: Text(Self.emptyDescription))
            } else if isSearching {
                searchResults
            } else {
                sessionList
            }
        }
        .navigationTitle("History")
        .searchable(text: $query, prompt: Self.searchPrompt)
        .task(id: query) { runSearch() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(HistoryActions.clearAllTitle) { confirmingClearAll = true }
                    .disabled(sessions.isEmpty)
                    .accessibilityHint("Deletes every session after a confirmation")
            }
        }
        .confirmationDialog(HistoryActions.clearAllConfirmationTitle(count: sessions.count), isPresented: $confirmingClearAll, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(HistoryActions.clearAllMessage)
        }
        .alert("Couldn't delete", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var sessionList: some View {
        List {
            ForEach(sessions) { session in
                NavigationLink {
                    SessionDetailView(session: session, exporter: exporter)
                } label: {
                    SessionRowView(summary: SessionSummary(session: session))
                }
            }
            .onDelete(perform: deleteRows)   // unconfirmed: a common single-row action (§8.6)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if let searchError {
            ContentUnavailableView("Search failed", systemImage: "exclamationmark.triangle", description: Text(searchError))
        } else if result.hits.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List(result.hits) { hit in
                NavigationLink {
                    SessionDetailView(session: hit.session, exporter: exporter)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(hit.session.startedAt, format: SessionRowView.dateStyle).font(.headline)
                            Spacer()
                            Text(hit.matchTimestamp, format: Date.FormatStyle(date: .omitted, time: .standard)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text(hit.matchingLine).font(.body).lineLimit(2)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Session \(hit.session.startedAt.formatted(SessionRowView.dateStyle)). \(hit.matchingLine).")
                }
            }
        }
    }

    private func runSearch() {
        guard isSearching else {
            result = SearchResult(hits: [], usedFallback: false)
            searchError = nil
            return
        }
        do {
            result = try TranscriptSearch.hits(query: query, in: context)
            searchError = nil
        } catch {
            result = SearchResult(hits: [], usedFallback: false)
            searchError = String(describing: error)
        }
    }

    private func deleteRows(at offsets: IndexSet) {
        let actions = HistoryActions(context: context)
        for index in offsets {
            do {
                try actions.delete(sessions[index])
            } catch {
                actionError = String(describing: error)
            }
        }
    }

    private func clearAll() {
        do {
            try HistoryActions(context: context).deleteAll()
            query = ""
        } catch {
            actionError = String(describing: error)
        }
    }
}
