import SwiftUI
import ReVoxCore

struct ModelRowView: View {
    let row: ModelRow
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(row.name).font(.headline)
                if row.isRecommended {
                    Text("Recommended")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                Spacer()
                Text(row.sizeText).font(.subheadline).foregroundStyle(.secondary)
            }
            if !row.isSuitable {
                Text(ModelsViewModel.notRecommendedText).font(.caption).foregroundStyle(.secondary)
            }
            if let warning = row.warning {
                Label(warning, systemImage: "thermometer.medium").font(.caption).foregroundStyle(.secondary)
            }
            if let note = row.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            stateView
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var stateView: some View {
        switch row.state.phase {
        case .idle:
            Button("Download", action: onDownload).buttonStyle(.bordered).frame(minHeight: 44)
        case .listing, .downloading, .compiling, .verifying:
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: row.state.fraction ?? 0)
                    .accessibilityValue(LiveStatusAccessibility.percentText(row.state.fraction))
                HStack {
                    Text(ModelsViewModel.phaseText(row.state.phase)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", role: .cancel, action: onCancel)
                        .font(.caption)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .accessibilityAddTraits(.updatesFrequently)
        case .paused:
            HStack {
                Text("Paused").font(.caption).foregroundStyle(.secondary)
                Text(ModelsViewModel.keepOpenText).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Resume", action: onDownload).buttonStyle(.bordered).frame(minHeight: 44)
            }
        case .installed:
            HStack {
                if row.isSelected {
                    Label("Selected", systemImage: "checkmark.circle.fill").font(.subheadline)
                } else {
                    Text("Installed").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Select", action: onSelect).buttonStyle(.bordered).frame(minHeight: 44)
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Failed", systemImage: "exclamationmark.triangle").font(.subheadline)
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                Button("Retry", action: onDownload).buttonStyle(.bordered).frame(minHeight: 44)
            }
        }
    }

    private var accessibilityText: String {
        var parts = ["Model \(row.name)", row.sizeText, ModelsViewModel.phaseText(row.state.phase)]
        if row.isRecommended { parts.append("Recommended") }
        if !row.isSuitable { parts.append(ModelsViewModel.notRecommendedText) }
        if row.isSelected { parts.append("Selected") }
        if let fraction = row.state.fraction, row.state.phase.isActive { parts.append("\(Int(fraction * 100)) percent") }
        return parts.joined(separator: ". ")
    }
}

struct VADRowView: View {
    let row: VADRow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.headline)
                Text("Installed automatically with the first Whisper model").font(.caption).foregroundStyle(.secondary)
                if let notice = row.noticeText {
                    Label(notice, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.sizeText).font(.subheadline).foregroundStyle(.secondary)
                Text(ModelsViewModel.phaseText(row.state.phase)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
