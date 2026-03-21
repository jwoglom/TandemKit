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
                "Manage the CGM sensor connection on your pump. These CGM options are ONLY used with the pump's built-in Control-IQ algorithm.",
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
                }
                .listStyle(InsetGroupedListStyle())
            }
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

                HStack {
                    Text(LocalizedString("Start Dexcom G7 Sensor", comment: "Dexcom G7 sensor option"))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(LocalizedString("Coming soon", comment: "Dexcom G7 not yet supported"))
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                .alert(isPresented: $showingStopConfirmation) {
                    Alert(
                        title: Text(LocalizedString("Stop CGM Sensor", comment: "Title for stop CGM confirmation")),
                        message: Text(LocalizedString(
                            "Are you sure you want to stop the CGM sensor session?",
                            comment: "Message for stop CGM confirmation"
                        )),
                        primaryButton: .destructive(Text(LocalizedString("Stop Sensor", comment: "Button to confirm stopping CGM"))) {
                            viewModel.stopCGMSensor()
                        },
                        secondaryButton: .cancel()
                    )
                }

            case .startPending, .stopPending:
                Button(action: {
                    viewModel.fetchCGMStatus()
                }) {
                    HStack {
                        Spacer()
                        Text(LocalizedString("Refresh Status", comment: "Button to refresh CGM status"))
                        Spacer()
                    }
                }

            case .unknown:
                Button(action: {
                    viewModel.fetchCGMStatus()
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
