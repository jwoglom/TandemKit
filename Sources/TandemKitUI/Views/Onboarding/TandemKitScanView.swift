import LoopKitUI
import SwiftUI

struct TandemKitScanView: View {
    @Environment(\.isPresented) var isPresented
    @Environment(\.dismissAction) private var dismiss

    @StateObject var viewModel: TandemKitScanViewModel

    var body: some View {
        WizardStepContainer(
            title: LocalizedString("Tandem Mobi Pairing", comment: "Title for fill tubing"),
            currentStep: viewModel.currentPhase.rawValue + 1,
            totalSteps: 3,
            canCancel: false,
            disableInteractiveDismiss: true,
            lockModalWhenCantCancel: true,
            onCancel: {}
        ) {
            currentStepView
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
                .id(viewModel.currentPhase)
        }
        .onAppear {
            viewModel.startScan()
        }
        .safeAreaInset(edge: .bottom) {
            VStack {
                if viewModel.currentPhase == .mobiOnPad {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(LocalizedString("Troubles detecting your Tandem Mobi?", comment: ""))
                            .bold()
                        Text(
                            LocalizedString(
                                "Try to forget the mobi in your Bluetooth settings and make sure the Tandem Mobi app is closed.",
                                comment: ""
                            )
                        )
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
                ActivityIndicator(isAnimating: .constant(true), style: .medium)
                    .padding()
            }
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
            LocalizedString("Enter Pairing code", comment: "Tandem pump found"),
            isPresented: $viewModel.isPromptingPincode
        ) {
            Button(LocalizedString("Cancel", comment: "Cancel button title"), role: .cancel) {
                viewModel.cancelPinPrompt()
            }
            Button(LocalizedString("Pair", comment: "Pair button")) {
                viewModel.processPinPrompt()
            }

            TextField(LocalizedString("PIN", comment: "Tandem pairing code prompt"), text: $viewModel.devicePinCode)
                .keyboardType(.numberPad)
                .onChange(of: viewModel.devicePinCode) { newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue {
                        viewModel.devicePinCode = filtered
                    }
                }
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

    @ViewBuilder var currentStepView: some View {
        switch viewModel.currentPhase {
        case .mobiOnPad:
            PlaceMobiOnPadView
        case .doubleTap:
            DoubleTapView
        case .pairing:
            AuthenticatingView
        }
    }

    @ViewBuilder var PlaceMobiOnPadView: some View {
        VStack(alignment: .center, spacing: 20) {
            Text(LocalizedString("Place your Tandem Mobi on the chargerpad", comment: ""))
                .font(.headline)
                .bold()

            Image(imageName: "mobi_on_pad")
                .resizable()
                .scaledToFit()
                .padding(.horizontal)
                .frame(height: 150)
        }
    }

    @ViewBuilder var DoubleTapView: some View {
        VStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizedString(
                    "Remove your Tandem Mobi from the pad, wait a second, then double press the T-button",
                    comment: ""
                ))
                    .font(.headline)
                    .bold()

                Text(LocalizedString("Found the ", comment: "") + (viewModel.connectingTo ?? ""))
                    .foregroundStyle(.secondary)
            }

            Image(imageName: "mobi_double_tap")
                .resizable()
                .scaledToFit()
                .padding(.horizontal)
                .frame(height: 150)
        }
    }

    @ViewBuilder var AuthenticatingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedString(
                "Authenticating your Tandem Mobi...",
                comment: ""
            ))
                .font(.headline)
                .bold()

            Text(LocalizedString("Please be patient while your Tandem Mobi is being configured", comment: ""))
                .foregroundStyle(.secondary)
        }
    }
}
