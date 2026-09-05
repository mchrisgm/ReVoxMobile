import SwiftUI
import SwiftData
import ReVoxCore

/// The History tab (§8.6): sessions newest first, search over the English text, swipe-to-delete, confirmed Clear
/// All, and (M9) an edit mode that selects sessions to merge into one or delete together.
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
    @State private var confirmingMerge = false
    @State private var confirmingDeleteSelected = false
    @State private var actionError: String?
    @State private var selection = Set<PersistentIdentifier>()
    @State private var editMode: EditMode

    init(initialQuery: String = "", exporter: TranscriptExporter = TranscriptExporter(), editing: Bool = false) {
        _query = State(initialValue: initialQuery)
        _editMode = State(initialValue: editing ? .active : .inactive)
        self.exporter = exporter
    }

    /// The sessions behind the selection, in the list's order.
    private var selectedSessions: [Session] { sessions.filter { selection.contains($0.persistentModelID) } }

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
        .onChange(of: editMode) { _, mode in
            if !mode.isEditing { selection.removeAll() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton().disabled(sessions.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(HistoryActions.clearAllTitle) { confirmingClearAll = true }
                    .disabled(sessions.isEmpty)
                    .accessibilityHint("Deletes every session after a confirmation")
            }
            ToolbarItemGroup(placement: .bottomBar) {
                // Hidden while searching: the results list has no selection, so the bar would act on rows the
                // reader cannot see.
                if editMode.isEditing && !isSearching {
                    Button(Self.mergeButtonTitle(count: selection.count)) { confirmingMerge = true }
                        .disabled(selection.count < 2)
                        .accessibilityHint("Combines the selected sessions into one, in time order")
                    Spacer()
                    Button(Self.deleteButtonTitle(count: selection.count), role: .destructive) { confirmingDeleteSelected = true }
                        .disabled(selection.isEmpty)
                        .accessibilityHint("Deletes the selected sessions after a confirmation")
                }
            }
        }
        .confirmationDialog(HistoryActions.mergeConfirmationTitle(count: selection.count), isPresented: $confirmingMerge, titleVisibility: .visible) {
            Button(HistoryActions.mergeTitle) { mergeSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(HistoryActions.mergeMessage)
        }
        // M10: a bulk delete is confirmed like Clear All is; only the single-row swipe stays unconfirmed (§8.6).
        .confirmationDialog(HistoryActions.clearAllConfirmationTitle(count: selection.count), isPresented: $confirmingDeleteSelected, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.deleteSelectedMessage(count: selection.count))
        }
        .confirmationDialog(HistoryActions.clearAllConfirmationTitle(count: sessions.count), isPresented: $confirmingClearAll, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(HistoryActions.clearAllMessage)
        }
        .alert("Couldn't change the transcripts", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        // Outermost on purpose: the toolbar's EditButton and the list both read this binding, and a modifier only
        // reaches the views inside it.
        .environment(\.editMode, $editMode)
    }

    private var sessionList: some View {
        List(selection: $selection) {
            ForEach(sessions) { session in
                NavigationLink {
                    SessionDetailView(session: session, exporter: exporter)
                } label: {
                    SessionRowView(summary: SessionSummary(session: session))
                }
                .tag(session.persistentModelID)
            }
            .onDelete(perform: deleteRows)   // unconfirmed: a common single-row action (§8.6)
        }
    }

    static func mergeButtonTitle(count: Int) -> String { count > 0 ? "Merge (\(count))" : "Merge" }
    static func deleteButtonTitle(count: Int) -> String { count > 0 ? "Delete (\(count))" : "Delete" }

    static func deleteSelectedMessage(count: Int) -> String {
        count == 1
            ? "The selected session and its transcript will be deleted. You cannot undo this action."
            : "The \(count) selected sessions and their transcripts will be deleted. You cannot undo this action."
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
        let targets = offsets.map { sessions[$0] }   // resolved before the first save re-orders the query
        for session in targets {
            do {
                try actions.delete(session)
            } catch {
                actionError = String(describing: error)
            }
        }
    }

    private func mergeSelected() {
        do {
            try HistoryActions(context: context).merge(selectedSessions)
            selection.removeAll()
            editMode = .inactive
        } catch {
            actionError = String(describing: error)
        }
    }

    private func deleteSelected() {
        let actions = HistoryActions(context: context)
        for session in selectedSessions {
            do {
                try actions.delete(session)
            } catch {
                actionError = String(describing: error)
            }
        }
        selection.removeAll()
        editMode = .inactive
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
