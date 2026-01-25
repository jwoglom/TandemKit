import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitCGMSettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.guidanceColors) private var guidanceColors
    @StateObject var viewModel: TandemKitCGMSettingsViewModel
    @State private var didLoad = false

    var body: some View {
        List {
            // Warning section
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(guidanceColors.warning)
                    Text(LocalizedString(
                        "These settings control the Tandem pump's built-in CGM connection features, which are separate from the CGM used by Trio.",
                        comment: "Warning message for CGM settings"
                    ))
                }
            }

            // Current Status
            Section(header: SectionHeader(label: LocalizedString(
                "Current Status",
                comment: "The title of the current status section"
            ))) {
                HStack {
                    Text(LocalizedString("Session State", comment: "Label for session state"))
                        .foregroundColor(Color.primary)
                    Spacer()
                    Text(viewModel.sessionStateText)
                        .foregroundColor(.secondary)
                }

                if let status = viewModel.cgmStatus {
                    HStack {
                        Text(LocalizedString("Transmitter Battery", comment: "Label for transmitter battery"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(transmitterBatteryText(status.transmitterBatteryStatus))
                            .foregroundColor(.secondary)
                    }

                    if status.sessionState == .sessionActive {
                        HStack {
                            Text(LocalizedString("Sensor Started", comment: "Label for sensor started time"))
                                .foregroundColor(Color.primary)
                            Spacer()
                            Text(formatDate(status.sensorStartedDate))
                                .foregroundColor(.secondary)
                        }

                        if status.lastCalibrationTimestamp > 0 {
                            HStack {
                                Text(LocalizedString("Last Calibration", comment: "Label for last calibration time"))
                                    .foregroundColor(Color.primary)
                                Spacer()
                                Text(formatDate(status.lastCalibrationDate))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Button(action: {
                    viewModel.refreshCGMStatus()
                }) {
                    HStack {
                        Text(LocalizedString("Refresh", comment: "Button to refresh CGM status"))
                        Spacer()
                        if viewModel.isRefreshing {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                        }
                    }
                }
                .disabled(viewModel.isRefreshing)
            }

            // Dexcom G6 Section
            Section(header: SectionHeader(label: LocalizedString(
                "Dexcom G6",
                comment: "The title of the Dexcom G6 section"
            ))) {
                // Transmitter ID
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedString("Transmitter ID", comment: "Label for transmitter ID"))
                        .font(.headline)

                    TextField(
                        LocalizedString("Enter 6-character ID", comment: "Placeholder for transmitter ID"),
                        text: $viewModel.g6TransmitterId
                    )
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)

                    ContinueButton(
                        text: LocalizedString("Set Transmitter ID", comment: "Button to set transmitter ID"),
                        loading: $viewModel.isSettingG6Transmitter
                    ) {
                        viewModel.setG6TransmitterId()
                    }

                    if let info = viewModel.g6TransmitterInfo {
                        Group {
                            if !info.transmitterBleHardwareId.isEmpty {
                                Text("Hardware ID: \(info.transmitterBleHardwareId)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if !info.transmitterFirmwareVersion.isEmpty {
                                Text("Firmware: \(info.transmitterFirmwareVersion)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)

                // Sensor Session
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedString("Sensor Session", comment: "Label for sensor session"))
                        .font(.headline)

                    if viewModel.isSessionActive {
                        Button(action: {
                            viewModel.showingStopConfirmation = true
                        }) {
                            HStack {
                                Text(LocalizedString("Stop Sensor Session", comment: "Button to stop sensor"))
                                Spacer()
                                if viewModel.isStoppingSession {
                                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                                }
                            }
                        }
                        .disabled(viewModel.isStoppingSession)
                        .foregroundColor(guidanceColors.critical)
                    } else {
                        TextField(
                            LocalizedString(
                                "Sensor Code",
                                comment: "Placeholder for sensor code"
                            ),
                            text: $viewModel.g6SensorCode
                        )
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)

                        ContinueButton(
                            text: LocalizedString("Start G6 Sensor", comment: "Button to start G6 sensor"),
                            loading: $viewModel.isStartingG6Session
                        ) {
                            viewModel.showingStartG6Confirmation = true
                        }

                        Text(LocalizedString(
                            "Enter the sensor code from your G6 sensor. Leave blank or enter 0000 to reconnect to an existing session.",
                            comment: "Help text for G6 sensor code"
                        ))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // Dexcom G7 Section
            Section(header: SectionHeader(label: LocalizedString(
                "Dexcom G7",
                comment: "The title of the Dexcom G7 section"
            ))) {
                if viewModel.isSessionActive {
                    // Show stop button when session is active
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedString("Sensor Session", comment: "Label for sensor session"))
                            .font(.headline)

                        Button(action: {
                            viewModel.showingStopConfirmation = true
                        }) {
                            HStack {
                                Text(LocalizedString("Stop Sensor Session", comment: "Button to stop sensor"))
                                Spacer()
                                if viewModel.isStoppingSession {
                                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                                }
                            }
                        }
                        .disabled(viewModel.isStoppingSession)
                        .foregroundColor(guidanceColors.critical)
                    }
                    .padding(.vertical, 4)
                } else {
                    // Pairing Code input when no session is active
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedString("Pairing Code", comment: "Label for pairing code"))
                            .font(.headline)

                        TextField(
                            LocalizedString("Enter pairing code", comment: "Placeholder for pairing code"),
                            text: $viewModel.g7PairingCodeInput
                        )
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)

                        HStack(spacing: 8) {
                            ContinueButton(
                                text: LocalizedString("Start G7 Sensor", comment: "Button to start G7 sensor"),
                                loading: $viewModel.isSettingG7PairingCode
                            ) {
                                viewModel.showingStartG7Confirmation = true
                            }

                            Button(action: {
                                viewModel.getSavedG7PairingCode()
                            }) {
                                HStack {
                                    Text(LocalizedString("Get Saved", comment: "Button to get saved pairing code"))
                                    if viewModel.isGettingG7PairingCode {
                                        ActivityIndicator(isAnimating: .constant(true), style: .medium)
                                    }
                                }
                            }
                            .disabled(viewModel.isGettingG7PairingCode)
                        }

                        if let pairingCode = viewModel.g7SavedPairingCode, pairingCode.pairingCode > 0 {
                            Text("Saved pairing code: \(pairingCode.pairingCode)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text(LocalizedString(
                            "Enter the 4-digit pairing code from your G7 sensor to start a new sensor session.",
                            comment: "Help text for G7 pairing code"
                        ))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Error message
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .foregroundColor(guidanceColors.critical)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarTitle(LocalizedString("CGM Settings", comment: "Title for CGM settings"))
        .task {
            guard !didLoad else { return }
            didLoad = true
            viewModel.refreshCGMStatus()
        }
        .actionSheet(isPresented: $viewModel.showingStartG6Confirmation) {
            startG6SensorSheet
        }
        .actionSheet(isPresented: $viewModel.showingStartG7Confirmation) {
            startG7SensorSheet
        }
        .actionSheet(isPresented: $viewModel.showingStopConfirmation) {
            stopSensorSheet
        }
    }

    var startG6SensorSheet: ActionSheet {
        ActionSheet(
            title: Text(LocalizedString("Start Dexcom G6 Sensor?", comment: "Action sheet title")),
            message: Text(LocalizedString(
                "This will start a new sensor session on the pump.",
                comment: "Action sheet message"
            )),
            buttons: [
                .default(Text(LocalizedString("Start Sensor", comment: "Confirm button"))) {
                    viewModel.startG6SensorSession()
                },
                .cancel()
            ]
        )
    }

    var startG7SensorSheet: ActionSheet {
        ActionSheet(
            title: Text(LocalizedString("Start Dexcom G7 Sensor?", comment: "Action sheet title")),
            message: Text(LocalizedString(
                "This will set the pairing code and start a new sensor session on the pump.",
                comment: "Action sheet message"
            )),
            buttons: [
                .default(Text(LocalizedString("Start Sensor", comment: "Confirm button"))) {
                    viewModel.setG7PairingCode()
                },
                .cancel()
            ]
        )
    }

    var stopSensorSheet: ActionSheet {
        ActionSheet(
            title: Text(LocalizedString("Stop CGM Sensor?", comment: "Action sheet title")),
            message: Text(LocalizedString(
                "This will stop the active sensor session on the pump.",
                comment: "Action sheet message"
            )),
            buttons: [
                .destructive(Text(LocalizedString("Stop Sensor", comment: "Confirm button"))) {
                    viewModel.stopCGMSession()
                },
                .cancel()
            ]
        )
    }

    private func transmitterBatteryText(_ status: CGMStatusResponse.TransmitterBatteryStatus?) -> String {
        switch status {
        case .ok:
            return "OK"
        case .expired:
            return "Expired"
        case .error:
            return "Error"
        case .unavailable:
            return "Unavailable"
        case .outOfRange:
            return "Out of Range"
        case .none:
            return "Unknown"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview("Active Session") {
    NavigationView {
        TandemKitCGMSettingsView(viewModel: .previewActive)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

#Preview("Stopped Session") {
    NavigationView {
        TandemKitCGMSettingsView(viewModel: .previewStopped)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

private extension TandemKitCGMSettingsViewModel {
    static var previewActive: TandemKitCGMSettingsViewModel {
        let viewModel = TandemKitCGMSettingsViewModel(pumpManager: nil)
        viewModel.cgmStatus = CGMStatusResponse(
            sessionStateId: CGMStatusResponse.SessionState.sessionActive.rawValue,
            lastCalibrationTimestamp: UInt32(Date().timeIntervalSince1970 - 3600),
            sensorStartedTimestamp: UInt32(Date().timeIntervalSince1970 - 86400),
            transmitterBatteryStatusId: CGMStatusResponse.TransmitterBatteryStatus.ok.rawValue
        )
        viewModel.g6TransmitterInfo = GetG6TransmitterHardwareInfoResponse(
            transmitterFirmwareVersion: "1.2.3",
            transmitterHardwareRevision: "A1",
            transmitterBleHardwareId: "8F3A2B",
            transmitterSoftwareNumber: "SW001"
        )
        return viewModel
    }

    static var previewStopped: TandemKitCGMSettingsViewModel {
        let viewModel = TandemKitCGMSettingsViewModel(pumpManager: nil)
        viewModel.cgmStatus = CGMStatusResponse(
            sessionStateId: CGMStatusResponse.SessionState.sessionStopped.rawValue,
            lastCalibrationTimestamp: 0,
            sensorStartedTimestamp: 0,
            transmitterBatteryStatusId: CGMStatusResponse.TransmitterBatteryStatus.unavailable.rawValue
        )
        return viewModel
    }
}
