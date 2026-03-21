import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitCGMSettingsView: View {
    @ObservedObject var viewModel: TandemKitCGMSettingsViewModel
    @State private var showingStopConfirmation = false

    var body: some View {
        VStack(alignment: .leading) {
            Text(LocalizedString("CGM Settings", comment: "Title for CGM settings screen"))
                .font(.title)
                .bold()
                .padding(.horizontal)

            Text(LocalizedString(
                "Manage the CGM sensor connection on your pump. These CGM options are ONLY used with the pump's built-in Control-IQ algorithm when Trio or Loop are not being used.",
                comment: "Description for CGM settings"
            ))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            Divider()
                .padding(.vertical)

            if viewModel.isFetching {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding()
                    Text(LocalizedString("Loading CGM status...", comment: "Loading CGM status"))
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
                                showingStopConfirmation = true
                            }) {
                                HStack {
                                    Spacer()
                                    Text(LocalizedString("Stop Sensor", comment: "Button to stop sensor during startup"))
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
                .alert(isPresented: $showingStopConfirmation) {
                    Alert(
                        title: Text(LocalizedString("Stop CGM Sensor", comment: "Title for stop CGM confirmation")),
                        message: Text(LocalizedString(
                            "Are you sure you want to stop the CGM sensor session on your pump?",
                            comment: "Message for stop CGM confirmation"
                        )),
                        primaryButton: .destructive(Text(LocalizedString("Stop Sensor", comment: "Button to confirm stopping CGM"))) {
                            viewModel.stopCGMSensor()
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
        }
        .task {
            viewModel.fetchCGMStatus()
        }
        .alert(item: Binding(
            get: { viewModel.commandError.map { ErrorMessage(message: $0) } },
            set: { _ in viewModel.commandError = nil }
        )) { error in
            Alert(
                title: Text(LocalizedString("Error", comment: "Error alert title")),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - CGM Status Section

    private var cgmStatusSection: some View {
        Section(header: Text(LocalizedString("CGM Sensor", comment: "Header for CGM sensor section"))) {
            if let sensorType = viewModel.sensorTypeText {
                HStack {
                    Text(LocalizedString("Session Type", comment: "Label for CGM session type"))
                    Spacer()
                    Text(sensorType)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text(LocalizedString("Session Status", comment: "Label for CGM session status"))
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
                    Text(LocalizedString("Sensor Started", comment: "Label for sensor started date"))
                    Spacer()
                    Text(startedDate, style: .relative)
                        .foregroundColor(.secondary)
                    Text(LocalizedString("ago", comment: "Suffix for relative time"))
                        .foregroundColor(.secondary)
                }
            }

            if let duration = viewModel.sessionDuration {
                HStack {
                    Text(LocalizedString("Session Duration", comment: "Label for session duration"))
                    Spacer()
                    Text(duration)
                        .foregroundColor(.secondary)
                }
            }

            if let remaining = viewModel.sessionTimeRemaining {
                HStack {
                    Text(LocalizedString("Time Remaining", comment: "Label for session time remaining"))
                    Spacer()
                    Text(remaining)
                        .foregroundColor(.secondary)
                }
            }

            if let battery = viewModel.transmitterBattery {
                HStack {
                    Text(LocalizedString("Transmitter Battery", comment: "Label for transmitter battery"))
                    Spacer()
                    Text(battery)
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.gracePeriod {
                HStack {
                    Text(LocalizedString("Grace Period", comment: "Label for grace period"))
                    Spacer()
                    Text(LocalizedString("Active", comment: "Grace period is active"))
                        .foregroundColor(.orange)
                }
            }

            switch viewModel.cgmSessionState {
            case .stopped:
                NavigationLink(destination: TandemKitG6SetupWizardView(
                    viewModel: viewModel.createG6SetupViewModel()
                )) {
                    HStack {
                        Text(LocalizedString("Start Dexcom G6 Sensor", comment: "Dexcom G6 sensor option"))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }

                NavigationLink(destination: TandemKitG7SetupWizardView(
                    viewModel: viewModel.createG7SetupViewModel()
                )) {
                    HStack {
                        Text(LocalizedString("Start Dexcom G7 Sensor", comment: "Dexcom G7 sensor option"))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }

            case .active:
                Button(action: {
                    showingStopConfirmation = true
                }) {
                    HStack {
                        Spacer()
                        Text(LocalizedString("Stop CGM Sensor", comment: "Button to stop CGM sensor"))
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
                .disabled(viewModel.isLoading)

            case .startPending, .stopPending:
                Button(action: {
                    viewModel.fetchCGMStatus(force: true)
                }) {
                    HStack {
                        Spacer()
                        Text(LocalizedString("Refresh Status", comment: "Button to refresh CGM status"))
                        Spacer()
                    }
                }

            case .unknown:
                Button(action: {
                    viewModel.fetchCGMStatus(force: true)
                }) {
                    HStack {
                        Spacer()
                        Text(LocalizedString("Refresh Status", comment: "Button to refresh CGM status"))
                        Spacer()
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        switch viewModel.cgmSessionState {
        case .active: return .green
        case .stopped: return .secondary
        case .startPending, .stopPending: return .orange
        case .unknown: return .secondary
        }
    }
}

// MARK: - Helper

private struct ErrorMessage: Identifiable {
    let id = UUID()
    let message: String
}
