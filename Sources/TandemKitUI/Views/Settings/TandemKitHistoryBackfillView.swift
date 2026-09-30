import SwiftUI

struct TandemKitHistoryBackfillView: View {
    @StateObject var viewModel: TandemKitHistoryBackfillViewModel

    var body: some View {
        List {
            if let report = viewModel.report {
                Section {
                    if report.findings.isEmpty {
                        Text("Nothing to flag.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(report.findings) { finding in
                        FindingRow(finding: finding)
                    }
                } header: {
                    Text("Findings")
                } footer: {
                    Text(verbatim: "Captured \(report.capturedText)")
                }

                actionsSection

                ForEach(report.sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            ReportRow(row: row)
                        }
                    } header: {
                        Text(section.title)
                    } footer: {
                        if let footer = section.footer {
                            Text(footer)
                        }
                    }
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarTitle("History Backfill", displayMode: .inline)
        .alert("Reset Resolution Counts?", isPresented: $viewModel.showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                viewModel.resetCounts()
            }
        } message: {
            Text("Clears the dose resolution counts, the recent resolutions and this session's tick totals. The read position and the report ledger are not changed.")
        }
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                viewModel.readPumpStatus()
            } label: {
                HStack {
                    Label("Read Pump History Status", systemImage: "number")
                    Spacer()
                    if viewModel.isReadingStatus {
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isReadingStatus)

            if viewModel.statusReadFailed {
                Text("The pump didn't answer the history log status request.")
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            Button {
                viewModel.runTick()
            } label: {
                HStack {
                    Label("Run Backfill Tick Now", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if viewModel.isRunningTick {
                        ProgressView()
                    }
                }
            }
            .disabled(!viewModel.isBackfillEnabled || viewModel.isRunningTick)

            Button {
                viewModel.copyReport()
            } label: {
                Label("Copy Report", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                viewModel.showingResetConfirmation = true
            } label: {
                Label("Reset Resolution Counts", systemImage: "arrow.counterclockwise")
            }
        } footer: {
            Text("Refreshes every few seconds. A tick run here is the same one each sync runs, so with History Dose Reporting on it can report boluses to the app. The copied report leaves out the pump serial but contains dosing history.")
        }
    }
}

private struct FindingRow: View {
    let finding: HistoryBackfillReport.Finding

    var body: some View {
        Label {
            Text(finding.message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: finding.tone.symbolName)
                .foregroundColor(finding.tone.color ?? .accentColor)
        }
        .textSelection(.enabled)
    }
}

private struct ReportRow: View {
    let row: HistoryBackfillReport.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.label)
                Spacer()
                Text(row.value)
                    .foregroundColor(row.tone.color ?? .secondary)
                    .multilineTextAlignment(.trailing)
            }
            if let detail = row.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
        .padding(.vertical, 2)
    }
}

private extension HistoryBackfillReport.Tone {
    var color: Color? {
        switch self {
        case .normal:
            return nil
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    var symbolName: String {
        switch self {
        case .normal:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .critical:
            return "exclamationmark.octagon"
        }
    }
}

#Preview {
    NavigationView {
        TandemKitHistoryBackfillView(viewModel: TandemKitHistoryBackfillViewModel(pumpManager: nil))
    }
}
