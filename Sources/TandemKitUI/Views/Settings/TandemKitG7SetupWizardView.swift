import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitG7SetupWizardView: View {
    @StateObject var viewModel: TandemKitG7SetupViewModel
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        WizardStepContainer(
            title: LocalizedString("Dexcom G7 Setup", comment: "Title for G7 setup wizard"),
            currentStep: 1,
            totalSteps: 1,
            canCancel: !viewModel.isLoading,
            onCancel: {
                presentationMode.wrappedValue.dismiss()
            }
        ) {
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
}

private struct ErrorMessage: Identifiable {
    let id = UUID()
    let message: String
}
