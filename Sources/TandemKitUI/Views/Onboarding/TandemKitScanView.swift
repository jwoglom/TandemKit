import LoopKitUI
import SwiftUI

struct TandemKitScanView: View {
    @Environment(\.isPresented) var isPresented
    @Environment(\.dismissAction) private var dismiss

    @StateObject var viewModel: TandemKitScanViewModel

    var body: some View {
        WizardStepContainer(
            title: LocalizedString("Tandem Mobi Pairing", comment: "Title for Mobi pairing"),
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
                        Text(LocalizedString("If your pump is not being detected:", comment: "If pump not detected help"))
                            .bold()
                        Text(
                            LocalizedString(
                                "Make sure you've unpaired the pump from any other apps, removed it from your saved Bluetooth device list, and placed it on the charging pad.",
                                comment: "If pump not detected instruction 1"
                            )
                        )
                        .foregroundStyle(.secondary)
                        Spacer()
                        Text(
                            LocalizedString(
                                "If the charging pad and pump don't light up, try a different USB cord or charger. If the pump is off, hold down the T button while placed on the pad to wake it up.",
                                comment: "If pump not detected instruction 2"
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
            LocalizedString("Enter Pairing code", comment: "Enter Pairing code instruction"),
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
            if let message = $viewModel.pinCodePromptError.wrappedValue, !message.isEmpty {
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
            Text(LocalizedString("Place your Mobi on the charging pad", comment: "Place on charging pad explanation"))
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
                    "Pick up your pump, wait a second, then double-press the T button",
                    comment: "Double-tap explanation"
                ))
                .font(.headline)
                .bold()

                Text(LocalizedString("Found the ", comment: "Found device prefix text") + (viewModel.connectingTo ?? ""))
                    .foregroundStyle(.secondary)
            }

            Image(imageName: "mobi_double_tap")
                .resizable()
                .scaledToFit()
                .padding(.horizontal)
                .frame(height: 150)

            Spacer()

            Text(LocalizedString("You should hear two beeps after double-pressing the button.", comment: "Beep explanation"))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder var AuthenticatingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedString(
                "Pairing with ",
                comment: "Pairing with device prefix text"
            ) + (viewModel.connectingTo ?? "Tandem Mobi"))
                .font(.headline)
                .bold()

            Text(LocalizedString("Please be patient while we authenticate with the pump.", comment: "Pump authenticating explanation"))
                .foregroundStyle(.secondary)

            Spacer()

            Text(LocalizedString("This can take up to 60 seconds to complete.", comment: "Pump authenticating wait message"))
                .foregroundStyle(.secondary)
        }
    }
}
