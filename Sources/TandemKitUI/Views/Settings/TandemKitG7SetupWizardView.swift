import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitG7SetupWizardView: View {
    @StateObject var viewModel: TandemKitG7SetupViewModel
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        WizardStepContainer(
            title: LocalizedString("Dexcom G7 Setup", comment: "Title for G7 setup wizard"),
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
            case .pairingCode:
                pairingCodeStep
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
                "Your Dexcom G7 sensor can be connected to a maximum of three devices:",
                comment: "G7 setup landing info header"
            ))
            .font(.body)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .frame(width: 24)
                    Text(LocalizedString("One phone", comment: "G7 setup: one phone"))
                }
                HStack(spacing: 8) {
                    Image(systemName: "applewatch")
                        .frame(width: 24)
                    Text(LocalizedString("One watch", comment: "G7 setup: one watch"))
                }
                HStack(spacing: 8) {
                    Image(systemName: "cross.case")
                        .frame(width: 24)
                    Text(LocalizedString("One pump", comment: "G7 setup: one pump"))
                }
            }
            .font(.body)
            .padding(.leading, 8)

            (Text(LocalizedString(
                "This page configures the connection between your pump and Dexcom G7. ",
                comment: "G7 setup explanation prefix"
            )) + Text(String(format: LocalizedString(
                "It is not used by %@ for algorithm dosing decisions.",
                comment: "G7 setup explanation bold part, parameter is app name"
            ), HostApp.current.appName)).bold())
            .font(.body)

            Text(LocalizedString(
                "When configured, the pump can vibrate or beep to deliver CGM notifications at all times. When Control-IQ is on, it will be used for automated insulin delivery with the built-in pump algorithm.",
                comment: "G7 setup explanation CGM notification info"
            ))
            .font(.body)

            Divider()

            Button(action: {
                viewModel.goToPairingCode()
            }) {
                HStack {
                    Spacer()
                    Text(LocalizedString("Continue", comment: "Button to continue to G7 pairing code entry"))
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Step 2: Pairing Code

    private var pairingCodeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedString("Pairing Code", comment: "Label for G7 pairing code"))
                    .font(.headline)

                TextField(
                    LocalizedString("Enter pairing code", comment: "Placeholder for G7 pairing code"),
                    text: $viewModel.pairingCode
                )
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.numberPad)

                Text(LocalizedString(
                    "The pairing code is displayed on the sensor applicator.",
                    comment: "Help text for G7 pairing code"
                ))
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()
                .frame(height: 10)

            Button(action: {
                viewModel.startG7Sensor()
            }) {
                HStack {
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.trailing, 5)
                    }
                    Text(LocalizedString("Start G7 Sensor", comment: "Button to start G7 sensor"))
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding()
                .background(viewModel.isPairingCodeValid ? Color.accentColor : Color(UIColor.systemGray4))
                .foregroundColor(viewModel.isPairingCodeValid ? .white : .secondary)
                .cornerRadius(10)
            }
            .disabled(!viewModel.isPairingCodeValid || viewModel.isLoading)
        }
    }
}

// MARK: - Helper

private struct ErrorMessage: Identifiable {
    let id = UUID()
    let message: String
}
