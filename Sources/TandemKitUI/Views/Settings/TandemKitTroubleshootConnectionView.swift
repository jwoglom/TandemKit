import LoopKitUI
import SwiftUI

struct TandemKitTroubleshootConnectionView: View {
    @Environment(\.guidanceColors) private var guidanceColors
    @StateObject var viewModel: TandemKitTroubleshootConnectionViewModel

    var body: some View {
        List {
            if let connectionIssue = viewModel.connectionIssue {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(connectionIssue.title)
                            .font(Font.subheadline.weight(.bold))
                            .foregroundColor(guidanceColors.critical)
                        TimelineView(.everyMinute) { context in
                            Text(connectionIssue.detail(
                                appName: viewModel.appName,
                                lastKnownDelivery: viewModel.lastKnownBasalDelivery,
                                now: context.date
                            ))
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section(header: Text("Status", comment: "Header for connection status section")) {
                statusRow(
                    label: String(localized: "Pump connection", comment: "Label for pump connection status"),
                    value: viewModel.isConnected ?
                        String(localized: "Connected", comment: "Pump is connected") :
                        String(localized: "Disconnected", comment: "Pump is disconnected"),
                    ok: viewModel.isConnected
                )

                statusRow(
                    label: String(localized: "Phone Bluetooth", comment: "Label for phone bluetooth status"),
                    value: viewModel.bluetoothStatusText,
                    ok: viewModel.isBluetoothPoweredOn
                )

                if let savedPumpText = viewModel.savedPumpText {
                    detailRow(
                        label: String(localized: "Saved pump", comment: "Label for saved pump"),
                        value: savedPumpText
                    )
                    statusRow(
                        label: String(localized: "Recognized by iOS Bluetooth", comment: "Label for iOS knowing the pump"),
                        value: viewModel.isSavedPumpKnownToSystem ?
                            String(localized: "Yes", comment: "Yes") :
                            String(localized: "No", comment: "No"),
                        ok: viewModel.isSavedPumpKnownToSystem
                    )
                } else {
                    detailRow(
                        label: String(localized: "Saved pump", comment: "Label for saved pump"),
                        value: String(localized: "None", comment: "No pump saved")
                    )
                }

                detailRow(
                    label: String(localized: "Last connected", comment: "Label for last connected time"),
                    value: viewModel.lastConnectedText
                )
            }

            Section {
                Button {
                    viewModel.attemptReconnect()
                } label: {
                    HStack {
                        Label(
                            String(localized: "Reconnect to pump", comment: "Button to retry the pump connection"),
                            systemImage: "arrow.clockwise"
                        )
                        Spacer()
                        if viewModel.isAttemptingReconnect {
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isAttemptingReconnect)

                if let reconnectResultText = viewModel.reconnectResultText {
                    Text(reconnectResultText)
                        .font(.footnote)
                        .foregroundColor(viewModel.isConnected ? .secondary : guidanceColors.critical)
                }
            } footer: {
                Text(
                    "Retries a connection to your pump. Keep your pump nearby and powered on.",
                    comment: "Footer explaining the reconnect button"
                )
            }

            Section(header: Text("Troubleshooting steps", comment: "Header for troubleshooting steps section")) {
                stepRow(
                    number: 1,
                    text: String(
                        localized: "Make sure your pump is nearby and powered on.",
                        comment: "Troubleshooting step: pump nearby"
                    )
                )
                stepRow(
                    number: 2,
                    text: String(
                        localized: "Turn Bluetooth off and back on in your phone's Settings app, then return here and tap Reconnect to pump.",
                        comment: "Troubleshooting step: toggle bluetooth"
                    )
                )
                stepRow(
                    number: 3,
                    text: String(
                        format: String(
                            localized: "Force-quit and reopen %@. The app reconnects to your pump automatically on launch.",
                            comment: "Troubleshooting step: restart app"
                        ),
                        HostApp.current.appName
                    )
                )
                stepRow(
                    number: 4,
                    text: String(
                        format: String(
                            localized: "Re-pairing the pump will require a wireless charging pad. DO NOT remove the pump from %@ unless you have a pump charger available.",
                            comment: "Troubleshooting step: re-pairing charger caveat"
                        ),
                        HostApp.current.appName
                    )
                )
            }
        }
        .navigationBarTitle(
            String(localized: "Troubleshoot connection", comment: "Title for troubleshoot connection screen"),
            displayMode: .inline
        )
        .onAppear {
            viewModel.refresh()
        }
    }

    private func statusRow(label: String, value: String, ok: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(ok ? .green : guidanceColors.critical)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.accentColor)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
