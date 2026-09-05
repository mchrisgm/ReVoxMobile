import SwiftUI
import ReVoxCore

/// Settings › Models › Benchmark this iPhone (M11 §5): a Run button with progress per model, the results table
/// with the verdicts, Share results as the report text, and the date and device of the last run.
struct BenchmarkView: View {
    @Bindable var model: BenchmarkViewModel

    var body: some View {
        List {
            Section {
                Text(BenchmarkViewModel.introText)
                switch model.state {
                case .idle:
                    Button(BenchmarkViewModel.runButtonTitle) { model.start() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityHint(BenchmarkViewModel.runButtonHint)
                case .running(let status):
                    progressRow(status)
                case .stopping:
                    progressRow(BenchmarkViewModel.stoppingText)
                }
                SettingExample(symbol: "gauge.with.needle", text: BenchmarkViewModel.exampleText)
            } footer: {
                if model.isRunning {
                    Text(BenchmarkViewModel.keepOpenText)
                } else if let reason = model.whyNotText {
                    Text(reason)
                }
            }

            Section {
                if model.rows.isEmpty {
                    Text(BenchmarkViewModel.noResultsText).foregroundStyle(.secondary)
                } else {
                    ForEach(model.rows) { row in
                        BenchmarkRowView(row: row)
                    }
                    if let text = model.shareText {
                        ShareLink(item: text) {
                            Label(BenchmarkViewModel.shareTitle, systemImage: "square.and.arrow.up")
                        }
                        .frame(minHeight: 44)
                        .accessibilityHint(BenchmarkViewModel.shareHint)
                    }
                }
            } header: {
                Text(BenchmarkViewModel.resultsHeader)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let lastRun = model.lastRunText { Text(lastRun) }
                    if let footer = model.resultsFooterText { Text(footer) }
                    if let notice = model.notice { Text(notice) }
                }
            }
        }
        .navigationTitle(BenchmarkViewModel.title)
        .alert(BenchmarkViewModel.refusedAlertTitle, isPresented: Binding(get: { model.refusedAlert != nil }, set: { if !$0 { model.refusedAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.refusedAlert ?? "")
        }
        .alert(BenchmarkViewModel.failedAlertTitle, isPresented: Binding(get: { model.failureAlert != nil }, set: { if !$0 { model.failureAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.failureAlert ?? "")
        }
    }

    private func progressRow(_ status: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                Text(status).font(.subheadline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
            Button(BenchmarkViewModel.cancelTitle, role: .cancel) { model.cancel() }
                .frame(minHeight: 44)
                .disabled(model.state == .stopping)
                .accessibilityHint(BenchmarkViewModel.cancelHint)
        }
    }
}

/// One result row: the model name, a word verdict with its symbol (never a colour alone), and the verdict line.
struct BenchmarkRowView: View {
    let row: BenchmarkRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.name).font(.headline)
            Label(row.summary, systemImage: row.symbol).font(.subheadline)
            if let detail = row.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenText)
    }
}
