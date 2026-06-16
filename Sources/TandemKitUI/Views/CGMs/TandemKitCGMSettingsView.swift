import LoopKitUI
import SwiftUI

private enum CGMAlertType: Identifiable {
    case stopConfirmation
    case error(String)

    var id: String {
        switch self {
        case .stopConfirmation: return "stop"
        case let .error(msg): return "error:\(msg)"
        }
    }
}

struct TandemKitCGMSettingsView: View {
    @StateObject var viewModel: TandemKitCGMSettingsViewModel
    @State private var activeAlert: CGMAlertType?

    var body: some View {
        VStack(alignment: .leading) {
            if viewModel.isFetching {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding()
                    Text("Loading CGM status...", comment: "Loading CGM status")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                List {
                    cgmStatusSection

                    if viewModel.cgmSessionState == .startPending {
                        Section {
                            Button(action: {
                                activeAlert = .stopConfirmation
                            }) {
                                HStack {
                                    Spacer()
                                    Text("Stop Sensor", comment: "Button to stop sensor during startup")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.red)
                                    Spacer()
                                }
                            }
                            .disabled(viewModel.isLoading)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
        .onAppear {
            viewModel.fetchCGMStatus()
        }
        .alert(item: $activeAlert) { alertType in
            switch alertType {
            case .stopConfirmation:
                return Alert(
                    title: Text("Stop CGM Sensor", comment: "Title for stop CGM confirmation"),
                    message: Text(
                        "Are you sure you want to stop the CGM sensor session on your pump?",
                        comment: "Message for stop CGM confirmation"
                    ),
                    primaryButton: .destructive(Text("Stop Sensor", comment: "Button to confirm stopping CGM")) {
                        viewModel.stopCGMSensor()
                    },
                    secondaryButton: .cancel()
                )
            case let .error(message):
                return Alert(
                    title: Text("Error", comment: "Error alert title"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .onChange(of: viewModel.commandError) { error in
            if let error = error {
                activeAlert = .error(error)
                viewModel.commandError = nil
            }
        }
    }

    // MARK: - CGM Status Section

    private var cgmStatusSection: some View {
        Section {
            if viewModel.cgmSessionState != .stopped, let sensorType = viewModel.sensorTypeText {
                HStack {
                    Text("Session Type", comment: "Label for CGM session type")
                    Spacer()
                    Text(sensorType)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("Session Status", comment: "Label for CGM session status")
                Spacer()
                if viewModel.cgmSessionState.isPending {
                    ProgressView()
                        .padding(.trailing, 5)
                }
                Text(viewModel.cgmSessionState.displayText)
                    .foregroundColor(statusColor)
            }

            if let startedDate = viewModel.sensorStartedDate {
                HStack {
                    Text("Sensor Started", comment: "Label for sensor started date")
                    Spacer()
                    Text(startedDate, style: .relative)
                        .foregroundColor(.secondary)
                    Text("ago", comment: "Suffix for relative time")
                        .foregroundColor(.secondary)
                }
            }

            if let duration = viewModel.sessionDuration {
                HStack {
                    Text("Session Duration", comment: "Label for session duration")
                    Spacer()
                    Text(duration)
                        .foregroundColor(.secondary)
                }
            }

            if let remaining = viewModel.sessionTimeRemaining {
                HStack {
                    Text("Time Remaining", comment: "Label for session time remaining")
                    Spacer()
                    Text(remaining)
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.cgmSessionState != .stopped, let battery = viewModel.transmitterBattery {
                HStack {
                    Text("Transmitter Battery", comment: "Label for transmitter battery")
                    Spacer()
                    Text(battery)
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.gracePeriod {
                HStack {
                    Text("Grace Period", comment: "Label for grace period")
                    Spacer()
                    Text("Active", comment: "Grace period is active")
                        .foregroundColor(.orange)
                }
            }

            switch viewModel.cgmSessionState {
            case .stopped:
                NavigationLink(destination: TandemKitG6SetupWizardView(
                    viewModel: viewModel.createG6SetupViewModel()
                )) {
                    HStack {
                        Text("Start Dexcom G6 Sensor", comment: "Dexcom G6 sensor option")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }

                NavigationLink(destination: TandemKitG7SetupWizardView(
                    viewModel: viewModel.createG7SetupViewModel()
                )) {
                    HStack {
                        Text("Start Dexcom G7 Sensor", comment: "Dexcom G7 sensor option")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }

            case .active:
                Button(action: {
                    activeAlert = .stopConfirmation
                }) {
                    HStack {
                        Spacer()
                        Text("Stop CGM Sensor", comment: "Button to stop CGM sensor")
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
                .disabled(viewModel.isLoading)

            case .startPending,
                 .stopPending:
                Button(action: {
                    viewModel.fetchCGMStatus(force: true)
                }) {
                    HStack {
                        Spacer()
                        Text("Refresh Status", comment: "Button to refresh CGM status")
                        Spacer()
                    }
                }

            case .unknown:
                Button(action: {
                    viewModel.fetchCGMStatus(force: true)
                }) {
                    HStack {
                        Spacer()
                        Text("Refresh Status", comment: "Button to refresh CGM status")
                        Spacer()
                    }
                }
            }
        } header: {
            Text("CGM Sensor", comment: "Header for CGM sensor section")
        } footer: {
            Text(
                "Manage the CGM sensor connection on your pump. These CGM options are ONLY used with the pump's built-in Control-IQ algorithm when this app is not being used.",
                comment: "Description for CGM settings"
            )
            .font(.footnote)
        }
    }

    private var statusColor: Color {
        switch viewModel.cgmSessionState {
        case .active: return .green
        case .stopped: return .secondary
        case .startPending,
             .stopPending: return .orange
        case .unknown: return .secondary
        }
    }
}
