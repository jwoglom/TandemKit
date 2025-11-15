import LoopKitUI
import SwiftUI

struct TandemKitScanView: View {
    @Environment(\.isPresented) var isPresented
    @Environment(\.dismissAction) private var dismiss

    @ObservedObject var viewModel: TandemKitScanViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Text(LocalizedString("Found Tandem pumps", comment: "Title for TandemKitScanView"))
                .font(.title)
                .bold()
                .padding(.horizontal)

            HStack(alignment: .center, spacing: 0) {
                Text(
                    !$viewModel.isConnecting.wrappedValue ?
                        LocalizedString("Scanning", comment: "Scanning text") :
                        LocalizedString("Connecting", comment: "Connecting text")
                )
                Spacer()
                ActivityIndicator(isAnimating: .constant(true), style: .medium)
            }
            .padding(.horizontal)

            Divider()
            content
        }

        .navigationBarHidden(false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(LocalizedString("Cancel", comment: "Cancel button title"), action: {
                    viewModel.stopScan()
                    self.dismiss()
                })
            }
        }
        .onChange(of: isPresented) { newValue in
            if !newValue {
                viewModel.stopScan()
            }
        }
        .alert(
            LocalizedString("Error while connecting to device", comment: "Connection error message"),
            isPresented: $viewModel.isConnectionError,
            presenting: $viewModel.connectionErrorMessage,
            actions: { _ in
                Button(LocalizedString("OK", comment: "OK button"), action: {})
            },
            message: { detail in Text(detail.wrappedValue ?? "") }
        )
        .alert(
            LocalizedString("Tandem Pump Found!", comment: "Tandem pump found"),
            isPresented: $viewModel.isPromptingPincode
        ) {
            Button(LocalizedString("Cancel", comment: "Cancel button title"), role: .cancel) {
                viewModel.cancelPinPrompt()
            }
            Button(LocalizedString("Pair", comment: "Pair button")) {
                viewModel.processPinPrompt()
            }

            TextField(LocalizedString("Pairing Code", comment: "Tandem pairing code prompt"), text: $viewModel.devicePinCode)
        } message: {
            if let message = $viewModel.pinCodePromptError.wrappedValue {
                Text(message)
            } else {
                Text(LocalizedString("Enter the pairing code from your pump", comment: "Tandem pairing code prompt message"))
            }
        }
    }

    @ViewBuilder private var content: some View {
        List($viewModel.scannedDevices) { $result in
            Button(action: { viewModel.connect($result.wrappedValue) }) {
                HStack {
                    Text($result.name.wrappedValue)
                    Spacer()
                    if !$viewModel.isConnecting.wrappedValue {
                        EmptyView()
                    } else if $result.name.wrappedValue == viewModel.connectingTo {
                        ActivityIndicator(isAnimating: .constant(true), style: .medium)
                    }
                }
                .padding(.horizontal)
            }
            .disabled($viewModel.isConnecting.wrappedValue)
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }
}

#Preview {
    TandemKitScanView(viewModel: TandemKitScanViewModel(nextStep: {}))
}
