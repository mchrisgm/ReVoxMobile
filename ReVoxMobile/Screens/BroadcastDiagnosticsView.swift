import SwiftUI
import ReVoxCore

/// Settings → Diagnostics. Read-only numbers straight from the ring header and the App Group record (§6.8 spike).
struct BroadcastDiagnosticsView: View {
    let model: BroadcastDiagnosticsModel

    var body: some View {
        List {
            Section("Ring") {
                if let snapshot = model.snapshot {
                    row("Generation", "\(snapshot.generation)")
                    row("State", "\(snapshot.state)")
                    row("Write cursor", "\(snapshot.writeCursor) frames (\(String(format: "%.1f", snapshot.writtenSeconds)) s)")
                    row("Rate", "\(Int(snapshot.framesPerSecond)) frames/s")
                    row("Heartbeat age", String(format: "%.2f s", snapshot.heartbeatAge))
                    row("Level", String(format: "rms %.1f dBFS · peak %.1f dBFS", snapshot.rmsDB, snapshot.peakDB))
                    row("Source format", snapshot.sourceFormat)
                    row("Format changes", "\(snapshot.asbdChangeCount)")
                    row("Dropped input frames", "\(snapshot.droppedInputFrames)")
                    row("Mic buffers seen", "\(snapshot.micBuffersSeen)")
                    row("Overruns", "\(snapshot.overrunCount)")
                    row("Writer PID", "\(snapshot.writerPID)")
                } else {
                    Text(model.ringPresent ? "Ring present, header unreadable" : "No ring file: start a broadcast first")
                        .foregroundStyle(.secondary)
                }
            }
            Section("broadcast.state record") {
                if let record = model.record {
                    row("Generation", "\(record.generation)")
                    row("State", record.state.rawValue)
                    row("Started", Date(timeIntervalSince1970: record.startedAt).formatted(date: .omitted, time: .standard))
                    row("Finish reason", record.finishReason ?? "—")
                    row("Annotated app", record.annotatedBundleID ?? "—")
                } else {
                    Text("No record").foregroundStyle(.secondary)
                }
            }
            Section("Keep-alive") {
                row("Engine running", model.engineRunning ? "yes" : "no")
                row("Last heartbeat", model.lastHeartbeat.map { String(format: "position %lld at %.1f", $0.position, $0.at) } ?? "—")
                row("Gaps > 3 s", "\(model.gapCount)")
                Toggle("Hold broadcast session (no pipeline)", isOn: Binding(
                    get: { model.isHoldingSession },
                    set: { on in Task { await model.setHoldingSession(on) } }
                ))
            }
        }
        .navigationTitle("Broadcast diagnostics")
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
