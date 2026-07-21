import SwiftUI

struct TandemKitHistoryLogViewerView: View {
    @StateObject var viewModel: TandemKitHistoryLogViewerViewModel

    private typealias NavMode = TandemKitHistoryLogViewerViewModel.NavigationMode

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

    // MARK: - Fetch section

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
                calibrationRow
                modePicker

                if viewModel.navigationMode == .aroundTime {
                    aroundTimeControls
                } else {
                    dateRangeControls
                }

                if viewModel.isLargeSelection {
                    largeSelectionWarning
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

                fetchButton

            case .fetching:
                fetchingControls
            }
        }
    }

    private var calibrationRow: some View {
        HStack(spacing: 6) {
            if case .running = viewModel.calibrationState {
                ProgressView()
                    .scaleEffect(0.7)
            }
            Text(viewModel.calibrationSummary)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var modePicker: some View {
        Picker("Navigate by", selection: $viewModel.navigationMode) {
            Text("Around a time").tag(NavMode.aroundTime)
            Text("Date range").tag(NavMode.dateRange)
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 2)
    }

    // MARK: Around-a-time controls

    @ViewBuilder private var aroundTimeControls: some View {
        HStack {
            Text("Start ID")
            Spacer()
            TextField("Start ID", text: startIdText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
            Button("Newest") {
                viewModel.resetStartToNewest()
            }
            .font(.footnote)
            .buttonStyle(.borderless)
        }

        DatePicker("Jump to", selection: pickerDate, displayedComponents: [.date, .hourAndMinute])
            .disabled(!viewModel.isCalibrated)

        Stepper(value: daysAgo, in: 0 ... 365) {
            Text("\(viewModel.daysAgo) day\(viewModel.daysAgo == 1 ? "" : "s") ago")
        }
        .disabled(!viewModel.isCalibrated)

        Picker("Number of logs", selection: $viewModel.selectedCount) {
            ForEach(viewModel.countOptions, id: \.self) { count in
                Text("\(count)").tag(count)
            }
        }

        if let summary = viewModel.aroundWindowSummary {
            Text(summary)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    // MARK: Date-range controls

    @ViewBuilder private var dateRangeControls: some View {
        DatePicker("From", selection: rangeStart, displayedComponents: [.date, .hourAndMinute])
            .disabled(!viewModel.isCalibrated)
        DatePicker("To", selection: rangeEnd, displayedComponents: [.date, .hourAndMinute])
            .disabled(!viewModel.isCalibrated)

        if !viewModel.isCalibrated {
            Text("Date navigation becomes available once calibration finishes.")
                .font(.footnote)
                .foregroundColor(.secondary)
        } else if let resolved = viewModel.resolvedRangeSummary {
            Text(resolved)
                .font(.footnote)
                .foregroundColor(.secondary)
        } else if let estimate = viewModel.estimatedRangeCount {
            Text("≈ \(estimate) log\(estimate == 1 ? "" : "s") in range (estimate)")
                .font(.footnote)
                .foregroundColor(.secondary)
        }

        Button {
            viewModel.resolveRange()
        } label: {
            HStack {
                Text("Find exact range")
                if viewModel.isResolvingRange {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(!viewModel.isCalibrated || viewModel.isResolvingRange)
    }

    private var largeSelectionWarning: some View {
        Label(
            "This selection is large and may take several minutes to fetch.",
            systemImage: "exclamationmark.triangle"
        )
        .font(.footnote)
        .foregroundColor(.orange)
    }

    // MARK: Fetch buttons

    @ViewBuilder private var fetchButton: some View {
        Button("Fetch history logs") {
            viewModel.startFetch()
        }
        .disabled(viewModel.firstSequenceNum == nil || viewModel.isResolvingRange)
    }

    @ViewBuilder private var fetchingControls: some View {
        if viewModel.isResolvingRange {
            HStack(spacing: 8) {
                ProgressView()
                Text("Resolving time range…")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: viewModel.progressFraction)
                Text(viewModel.progressSummary)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }

        Button("Cancel") {
            viewModel.cancelFetch()
        }
        .foregroundColor(.red)
    }

    // MARK: - Logs section

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

    // MARK: - Bindings

    /// Start ID as editable text, sanitized back into the view model.
    private var startIdText: Binding<String> {
        Binding(
            get: { String(viewModel.startId) },
            set: { viewModel.setStartId(fromText: $0) }
        )
    }

    /// Picking a date estimates and applies a Start ID; programmatic changes don't loop back.
    private var pickerDate: Binding<Date> {
        Binding(
            get: { viewModel.pickerDate },
            set: {
                viewModel.pickerDate = $0
                viewModel.applyPickerDate()
            }
        )
    }

    private var daysAgo: Binding<Int> {
        Binding(
            get: { viewModel.daysAgo },
            set: {
                viewModel.daysAgo = $0
                viewModel.applyDaysAgo()
            }
        )
    }

    private var rangeStart: Binding<Date> {
        Binding(
            get: { viewModel.rangeStart },
            set: {
                viewModel.rangeStart = $0
                viewModel.invalidateResolvedRange()
            }
        )
    }

    private var rangeEnd: Binding<Date> {
        Binding(
            get: { viewModel.rangeEnd },
            set: {
                viewModel.rangeEnd = $0
                viewModel.invalidateResolvedRange()
            }
        )
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
