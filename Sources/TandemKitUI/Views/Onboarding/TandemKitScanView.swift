import LoopKitUI
import SwiftUI

struct TandemKitScanView: View {
    @Environment(\.isPresented) var isPresented
    @Environment(\.dismissAction) private var dismiss

    @StateObject var viewModel: TandemKitScanViewModel

    @State var isHelpSheetPresented: Bool = false

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
                        Button(
                            LocalizedString("Pump not detected?", comment: "Button text for help when pump not found"),
                            action: {
                                isHelpSheetPresented = true
                            }
                        )
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
        .sheet(isPresented: $isHelpSheetPresented, onDismiss: {}, content: {
            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizedString("If your pump is not being detected, make sure you've:", comment: "If pump not detected help"))
                    .bold()
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 5, trailing: 0))

                Text(
                    LocalizedString("Unpaired the pump from any other apps",
                                    comment: "Pump not detected tip 1")
                ).foregroundStyle(.secondary)

                Text(
                    LocalizedString("Removed the pump from your saved Bluetooth device list",
                                    comment: "Pump not detected tip 2")
                ).foregroundStyle(.secondary)

                Text(
                    LocalizedString("Placed the pump on the center of the charging pad",
                                    comment: "Pump not detected tip 3")
                ).foregroundStyle(.secondary)

                Text(LocalizedString(
                    "If the charging pad and pump don't light up, try a different USB cord or charger. Don't use a USB-C to USB-C cable or high-wattage charger.",
                    comment: "Pump not detected tip 4"
                )
                ).foregroundStyle(.secondary)

                Text(LocalizedString(
                    "If the pump is off or out of battery, hold down the T button while placed on the pad for 30 seconds to wake it up.",
                    comment: "Pump not detected tip 5"
                )
                ).foregroundStyle(.secondary)
            }
            .padding(.all)

            Spacer()

            ContinueButton(text: LocalizedString("OK", comment: "OK button title")) {
                isHelpSheetPresented = false
            }
        })
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
