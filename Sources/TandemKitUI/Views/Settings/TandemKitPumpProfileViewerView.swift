import LoopKitUI
import SwiftUI

private struct PumpProfileExportFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct TandemKitPumpProfileViewerView: View {
    @StateObject var viewModel: TandemKitPumpProfileViewerViewModel

    @Environment(\.guidanceColors) private var guidanceColors
    @State private var exportFile: PumpProfileExportFile?

    var body: some View {
        List {
            Section {
                if viewModel.isReading {
                    ProgressView(String(localized: "Reading profiles…", comment: "Pump profile viewer progress while reading"))
                } else {
                    Button(viewModel.readout == nil ? Self.readTitle : Self.readAgainTitle) {
                        viewModel.read()
                    }
                }

                if let failure = viewModel.readout?.failure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundColor(guidanceColors.critical)
                }
            }

            if let status = viewModel.statusRow {
                Section(header: Text(status.title)) {
                    ExchangeView(exchange: status.exchange)
                }
            }

            ForEach(viewModel.profileSections) { section in
                Section(header: Text(section.title)) {
                    ForEach(section.rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.title)
                                .font(.headline)
                            ExchangeView(exchange: row.exchange)
                        }
                    }
                }
            }
        }
        .navigationBarTitle(
            String(localized: "Pump Profile Viewer", comment: "Title for the pump profile viewer screen"),
            displayMode: .inline
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if let url = viewModel.exportFileURL() {
                        exportFile = PumpProfileExportFile(url: url)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(viewModel.readout == nil || viewModel.isReading)
                .accessibilityLabel(String(
                    localized: "Export all profile responses",
                    comment: "Accessibility label for the pump profile viewer share button"
                ))
            }
        }
        .sheet(item: $exportFile) { file in
            ActivityViewController(activityItems: [file.url])
        }
        .onAppear {
            viewModel.readIfNeeded()
        }
    }

    private static let readTitle = String(localized: "Read Profiles", comment: "Pump profile viewer button to read the pump's profiles")
    private static let readAgainTitle = String(localized: "Read Again", comment: "Pump profile viewer button to read the pump's profiles again")
}

private struct ExchangeView: View {
    @Environment(\.guidanceColors) private var guidanceColors
    let exchange: PumpProfileReadout.Exchange

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MessageView(message: exchange.request)
            Divider()
            if let response = exchange.response {
                MessageView(message: response)
            } else {
                Text("No response", comment: "Pump profile viewer placeholder for a request the pump did not answer")
                    .font(.footnote)
                    .foregroundColor(guidanceColors.critical)
            }
        }
        .textSelection(.enabled)
    }
}

private struct MessageView: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(PumpProfileReadout.messageName(message))
                .font(.system(.footnote, design: .monospaced).bold())
            FieldRow(label: "cargo", value: message.cargo.hexadecimalString)
            ForEach(Array(PumpProfileReadout.fields(of: message).enumerated()), id: \.offset) { _, field in
                FieldRow(label: field.label, value: field.value)
            }
        }
    }
}

private struct FieldRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(.caption, design: .monospaced))
    }
}

#Preview {
    NavigationView {
        TandemKitPumpProfileViewerView(viewModel: TandemKitPumpProfileViewerViewModel(pumpManager: nil))
    }
}
