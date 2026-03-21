import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitG6SetupWizardView: View {
    @StateObject var viewModel: TandemKitG6SetupViewModel
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        WizardStepContainer(
            title: LocalizedString("Dexcom G6 Setup", comment: "Title for G6 setup wizard"),
            currentStep: min(viewModel.currentStep.rawValue + 1, 2),
            totalSteps: 2,
            canCancel: !viewModel.isLoading,
            onCancel: {
                presentationMode.wrappedValue.dismiss()
            }
        ) {
            switch viewModel.currentStep {
            case .landing:
                landingStep
            case .sensorDetails:
                sensorDetailsStep
            case .connectExisting:
                connectExistingStep
            }
        }
        .alert(item: Binding(
            get: { viewModel.error.map { ErrorMessage(message: $0) } },
            set: { _ in viewModel.error = nil }
        )) { error in
            Alert(
                title: Text(LocalizedString("Error", comment: "Error alert title")),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: viewModel.didComplete) { completed in
            if completed {
                DispatchQueue.main.async {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }

    // MARK: - Step 1: Landing

    private var landingStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(LocalizedString(
                "Your Dexcom G6 transmitter can be connected to a maximum of two devices:",
                comment: "G6 setup landing info header"
            ))
            .font(.body)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .frame(width: 24)
                    Text(LocalizedString("One phone", comment: "G6 setup: one phone"))
                }
                HStack(spacing: 8) {
                    Image(systemName: "cross.case")
                        .frame(width: 24)
                    Text(LocalizedString("One pump", comment: "G6 setup: one pump"))
                }
            }
            .font(.body)
            .padding(.leading, 8)

            (Text(LocalizedString(
                "This page configures the connection between your pump and Dexcom G6. ",
                comment: "G6 setup explanation prefix"
            )) + Text(String(format: LocalizedString(
                "It is not used by %@ for algorithm dosing decisions.",
                comment: "G6 setup explanation bold part, parameter is app name"
            ), HostApp.current.appName)).bold())
            .font(.body)

            Text(LocalizedString(
                "When configured, the pump can vibrate or beep to deliver CGM notifications at all times. When Control-IQ is on, it will be used for automated insulin delivery with the built-in pump algorithm.",
                comment: "G6 setup explanation CGM notification info"
            ))
            .font(.body)

            Divider()

            Text(LocalizedString(
                "Are you starting a new sensor or connecting to an existing session?",
                comment: "G6 setup prompt"
            ))
            .font(.body)

            Button(action: {
                viewModel.goToSensorDetails()
            }) {
                HStack {
                    Spacer()
                    Text(LocalizedString("Start new sensor", comment: "Button to start new G6 sensor"))
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
            }

            Button(action: {
                viewModel.goToConnectExisting()
            }) {
                HStack {
                    Spacer()
                    Text(LocalizedString("Connect to existing session", comment: "Button to connect to existing G6 session"))
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding()
                .background(Color(UIColor.systemGray5))
                .foregroundColor(.primary)
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Step 2: Sensor Details

    private var sensorDetailsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Transmitter ID
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedString("Transmitter ID", comment: "Label for G6 transmitter ID"))
                    .font(.headline)

                TextField(
                    "XXXXXX",
                    text: $viewModel.transmitterId
                )
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)

                Text(LocalizedString(
                    "The transmitter ID is a 6-character code shown on the back of the transmitter.",
                    comment: "Help text for G6 transmitter ID"
                ))
                .font(.caption)
                .foregroundColor(.secondary)
            }

            // Sensor Code
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedString("Sensor Code", comment: "Label for G6 sensor code"))
                    .font(.headline)

                TextField(
                    "0000",
                    text: $viewModel.sensorCode
                )
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.numberPad)

                Text(LocalizedString(
                    "The sensor code is a 4-digit code shown on the paper lining of the sensor.",
                    comment: "Help text for G6 sensor code"
                ))
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()
                .frame(height: 10)

            // Start button
            Button(action: {
                viewModel.startNewSensor()
            }) {
                HStack {
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.trailing, 5)
                    }
                    Text(LocalizedString("Start G6 Sensor", comment: "Button to start G6 sensor"))
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding()
                .background(viewModel.canStartSensor ? Color.accentColor : Color(UIColor.systemGray4))
                .foregroundColor(viewModel.canStartSensor ? .white : .secondary)
                .cornerRadius(10)
            }
            .disabled(!viewModel.canStartSensor || viewModel.isLoading)
        }
    }

    // MARK: - Step 2b: Connect to Existing Session

    private var connectExistingStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedString("Transmitter ID", comment: "Label for G6 transmitter ID"))
                    .font(.headline)

                TextField(
                    "XXXXXX",
                    text: $viewModel.transmitterId
                )
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)

                Text(LocalizedString(
                    "The transmitter ID is a 6-character code shown on the back of the transmitter.",
                    comment: "Help text for G6 transmitter ID"
                ))
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()
                .frame(height: 10)

            Button(action: {
                viewModel.connectToExistingSession()
            }) {
                HStack {
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.trailing, 5)
                    }
                    Text(LocalizedString("Connect to Transmitter", comment: "Button to connect to existing G6 transmitter"))
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding()
                .background(viewModel.canConnectExisting ? Color.accentColor : Color(UIColor.systemGray4))
                .foregroundColor(viewModel.canConnectExisting ? .white : .secondary)
                .cornerRadius(10)
            }
            .disabled(!viewModel.canConnectExisting || viewModel.isLoading)
        }
    }
}

// MARK: - Helper

private struct ErrorMessage: Identifiable {
    let id = UUID()
    let message: String
}
