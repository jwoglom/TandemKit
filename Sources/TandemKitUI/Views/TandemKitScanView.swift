import LoopKitUI
import SwiftUI

struct TandemKitScanView: View {
    @Environment(\.isPresented) var isPresented
    @Environment(\.dismissAction) private var dismiss

    @ObservedObject var viewModel: TandemKitScanViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Text(LocalizedString("Searching...", comment: "Searching text in TandemKitScanView"))
                .font(.title)
                .bold()
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 20) {
                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedString("To place the pump in pairing mode:", comment: "Pairing mode instructions header"))
                        .font(.headline)

                    Text(LocalizedString("• Set the pump on the charger", comment: "Pairing instruction 1"))
                    Text(LocalizedString("• Wait for it to begin charging", comment: "Pairing instruction 2"))
                    Text(LocalizedString(
                        "• Pick up the pump and wait 3 seconds",
                        comment: "Pairing instruction 3"
                    ))
                    Text(LocalizedString("• Press and release the pump button", comment: "Pairing instruction 4"))
                    Text(LocalizedString("• Wait 1 second and press the button again", comment: "Pairing instruction 5"))
                    Text(LocalizedString("• When complete, the pump should beep twice", comment: "Pairing instruction 6"))
                }
                .padding(.horizontal)

                Spacer()
            }

            HStack(alignment: .center, spacing: 0) {
                Text(
                    !$viewModel.isConnecting.wrappedValue ?
                        LocalizedString("Scanning", comment: "Scanning text") :
                        LocalizedString("Connecting", comment: "Connecting text")
                )
                Spacer()
                ActivityIndicator(isAnimating: .constant(true), style: .medium)
            }
            .padding(.all)

            Divider()
            content
        }
        .onAppear {
            viewModel.startScan()
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
                VStack {
                    Text(LocalizedString("Enter the pairing code from your pump", comment: "Tandem pairing code prompt message"))
                    Text(LocalizedString(
                        "The pairing code is located on the inside of the cartridge area labeled as 'PIN' and consists of six numbers.",
                        comment: "Tandem instructions for finding pairing code"
                    )).font(.caption)
                }
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

#Preview("Scanning With Results") {
    NavigationView {
        TandemKitScanView(viewModel: .previewWithDeviceList)
    }
}

#Preview("Prompting For PIN") {
    NavigationView {
        TandemKitScanView(viewModel: .previewRequestingPin)
    }
}

private extension TandemKitScanViewModel {
    static var previewWithDeviceList: TandemKitScanViewModel {
        let viewModel = TandemKitScanViewModel(nextStep: {})
        viewModel.scannedDevices = [
            ScanResultItem(name: "t:slim X2 2345", bleIdentifier: "ABCDEF01-2345"),
            ScanResultItem(name: "Tandem Mobi 999", bleIdentifier: "ABCDEF01-9999")
        ]
        viewModel.isScanning = true
        viewModel.isConnecting = false
        viewModel.connectingTo = nil
        return viewModel
    }

    static var previewRequestingPin: TandemKitScanViewModel {
        let viewModel = TandemKitScanViewModel(nextStep: {})
        viewModel.scannedDevices = [
            ScanResultItem(name: "Tandem Mobi 9999", bleIdentifier: "ABCDEF01-9999")
        ]
        viewModel.isConnecting = true
        viewModel.connectingTo = "Tandem Mobi 9999"
        viewModel.isPromptingPincode = true
        viewModel.devicePinCode = ""
        return viewModel
    }
}
