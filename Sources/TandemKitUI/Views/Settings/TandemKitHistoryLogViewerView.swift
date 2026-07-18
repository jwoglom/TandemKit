import SwiftUI

struct TandemKitHistoryLogViewerView: View {
    @StateObject var viewModel: TandemKitHistoryLogViewerViewModel

    private enum Tab: Int {
        case byType
        case byTime
    }

    private struct ExportFile: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    @State private var selectedTab: Tab = .byType
    @State private var detailEntry: TandemKitHistoryLogViewerViewModel.LogEntry?
    @State private var exportFile: ExportFile?

    var body: some View {
        List {
            fetchSection

            if viewModel.hasLogs || viewModel.phase == .fetching {
                logsSection
            }
        }
        .navigationBarTitle("History Log Viewer", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if let url = viewModel.exportFileURL() {
                        exportFile = ExportFile(url: url)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(!viewModel.hasLogs)
                .accessibilityLabel("Export history logs")
            }
        }
        .sheet(item: $detailEntry) { entry in
            HistoryLogDetailView(
                title: "\(entry.log.sequenceNum)",
                contents: viewModel.prettyDescription(for: entry.log)
            )
        }
        .sheet(item: $exportFile) { file in
            ActivityViewController(activityItems: [file.url])
        }
        .onAppear {
            viewModel.loadStatus()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    @ViewBuilder private var fetchSection: some View {
        Section(header: Text("Fetch History Logs")) {
            if let status = viewModel.pumpStatusDescription {
                Text(status)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            switch viewModel.phase {
            case .loadingStatus:
                ProgressView("Reading history log status…")

            case .statusUnavailable:
                Button("Retry") {
                    viewModel.loadStatus()
                }

            case .ready,
                 .complete,
                 .failed:
                Picker("Number of logs", selection: $viewModel.selectedCount) {
                    ForEach(viewModel.countOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }

                if case let .failed(message) = viewModel.phase {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.red)
                }

                if viewModel.hasLogs {
                    Text(viewModel.progressSummary)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Button("Fetch history logs") {
                    viewModel.startFetch()
                }

            case .fetching:
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: viewModel.progressFraction)
                    Text(viewModel.progressSummary)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Button("Cancel") {
                    viewModel.cancelFetch()
                }
                .foregroundColor(.red)
            }
        }
    }

    @ViewBuilder private var logsSection: some View {
        Section(header: tabPicker) {
            if selectedTab == .byType {
                ForEach(viewModel.typeCounts) { typeCount in
                    HStack {
                        Text("\(typeCount.count) log\(typeCount.count == 1 ? "" : "s"):")
                            .foregroundColor(.secondary)
                        Text(typeCount.name)
                            .font(.system(.footnote, design: .monospaced))
                    }
                }
            } else {
                ForEach(viewModel.logsDescending) { entry in
                    Button {
                        detailEntry = entry
                    } label: {
                        HStack {
                            Text("\(entry.log.sequenceNum):")
                                .foregroundColor(.secondary)
                            Text(entry.typeName)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
        }
    }

    private var tabPicker: some View {
        Picker("View", selection: $selectedTab) {
            Text("By Type").tag(Tab.byType)
            Text("By Time").tag(Tab.byTime)
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 4)
        .textCase(nil)
    }
}

/// Full pretty-printed contents of a single history log entry.
private struct HistoryLogDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let contents: String

    var body: some View {
        NavigationView {
            ScrollView {
                Text(contents)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.leading, .trailing, .top])
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        TandemKitHistoryLogViewerView(viewModel: TandemKitHistoryLogViewerViewModel(pumpManager: nil))
    }
}
