import LoopKitUI
import SwiftUI

struct TandemKitScanView: View {
    @Environment(\.isPresented) var isPresented
    @Environment(\.dismissAction) private var dismiss

    @StateObject var viewModel: TandemKitScanViewModel

    @State var isHelpSheetPresented: Bool = false

    var body: some View {
        WizardStepContainer(
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
                            String(localized: "Pump not detected?", comment: "Button text for help when pump not found"),
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
                Button(String(localized: "Cancel", comment: "Cancel button title"), action: {
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
            viewModel.connectionErrorTitle,
            isPresented: $viewModel.isConnectionError,
            presenting: $viewModel.connectionErrorMessage,
            actions: { _ in
                Button(String(localized: "OK", comment: "OK button"), action: {
                    viewModel.connectionErrorDismissed()
                })
            },
            message: { detail in Text(detail.wrappedValue ?? "") }
        )
        .alert(
            String(localized: "Control-IQ Is On", comment: "Title of the setup prompt when the paired pump is running Control-IQ"),
            isPresented: $viewModel.isPromptingControlIQOff,
            actions: {
                Button(String(localized: "OK", comment: "OK button")) {
                    viewModel.turnOffControlIQ()
                }
            },
            message: { Text(viewModel.controlIQOffPromptMessage) }
        )
        .alert(
            String(localized: "Control-IQ Not Turned Off", comment: "Title of the setup error when turning Control-IQ off failed"),
            isPresented: $viewModel.isControlIQOffError,
            presenting: $viewModel.controlIQOffErrorMessage,
            actions: { _ in
                Button(String(localized: "Try Again", comment: "Retry button")) {
                    viewModel.turnOffControlIQ()
                }
                Button(String(localized: "Continue Anyway", comment: "Continue button"), role: .destructive) {
                    viewModel.continueWithControlIQOn()
                }
            },
            message: { detail in Text(detail.wrappedValue ?? "") }
        )
        .alert(
            String(localized: "Pump Settings Not Saved", comment: "Onboarding settings write failure"),
            isPresented: $viewModel.isSettingsError,
            presenting: $viewModel.settingsErrorMessage,
            actions: { _ in
                Button(String(localized: "Try Again", comment: "Retry button")) {
                    viewModel.applyOnboardingSettings()
                }
                Button(String(localized: "Continue Anyway", comment: "Continue button"), role: .destructive) {
                    viewModel.continueWithoutOnboardingSettings()
                }
            },
            message: { detail in Text(detail.wrappedValue ?? "") }
        )
        .alert(
            String(localized: "Enter Pairing code", comment: "Enter Pairing code instruction"),
            isPresented: $viewModel.isPromptingPincode
        ) {
            Button(String(localized: "Cancel", comment: "Cancel button title"), role: .cancel) {
                viewModel.cancelPinPrompt()
            }
            Button(String(localized: "Pair", comment: "Pair button")) {
                viewModel.processPinPrompt()
            }

            TextField(String(localized: "PIN", comment: "Tandem pairing code prompt"), text: $viewModel.devicePinCode)
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
                    Text(String(
                        localized: "Enter the pairing code from your pump",
                        comment: "Tandem pairing code prompt message"
                    ))
                    Text(String(
                        localized:
                        "The pairing code is located on the inside of the cartridge area labeled as 'PIN' and consists of six numbers.",
                        comment: "Tandem instructions for finding pairing code"
                    )).font(.caption)
                }
            }
        }
        .sheet(isPresented: $isHelpSheetPresented, onDismiss: {}, content: {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "If your pump is not being detected, make sure you've:",
                    comment: "If pump not detected help"
                )
                .bold()
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 5, trailing: 0))

                Text(
                    "Unpaired the pump from any other apps",
                    comment: "Pump not detected tip 1"
                ).foregroundStyle(.secondary)

                Text(
                    "Removed the pump from your saved Bluetooth device list",
                    comment: "Pump not detected tip 2"
                ).foregroundStyle(.secondary)

                Text(
                    "Placed the pump on the center of the charging pad",
                    comment: "Pump not detected tip 3"
                ).foregroundStyle(.secondary)

                Text(
                    "If the charging pad and pump don't light up, try a different USB cord or charger. Don't use a USB-C to USB-C cable or high-wattage charger.",
                    comment: "Pump not detected tip 4"
                ).foregroundStyle(.secondary)

                Text(
                    "If the pump is off or out of battery, hold down the T button while placed on the pad for 30 seconds to wake it up.",
                    comment: "Pump not detected tip 5"
                ).foregroundStyle(.secondary)
            }
            .padding(.all)

            Spacer()

            ContinueButton(text: Text("OK", comment: "OK button title")) {
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
            Text("Place your Mobi on the charging pad", comment: "Place on charging pad explanation")
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
                Text(
                    "Pick up your pump, wait a second, then double-press the T button",
                    comment: "Double-tap explanation"
                )
                .font(.headline)
                .bold()

                Text(String(localized: "Found the ", comment: "Found device prefix text") + (viewModel.connectingTo ?? ""))
                    .foregroundStyle(.secondary)
            }

            Image(imageName: "mobi_double_tap")
                .resizable()
                .scaledToFit()
                .padding(.horizontal)
                .frame(height: 150)

            Spacer()

            Text("You should hear two beeps after double-pressing the button.", comment: "Beep explanation")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder var AuthenticatingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(
                localized:
                "Pairing with ",
                comment: "Pairing with device prefix text"
            ) + (viewModel.connectingTo ?? "Tandem Mobi"))
                .font(.headline)
                .bold()

            Text(
                "Please be patient while we authenticate with the pump.",
                comment: "Pump authenticating explanation"
            )
            .foregroundStyle(.secondary)

            Spacer()

            Text("This can take up to 60 seconds to complete.", comment: "Pump authenticating wait message")
                .foregroundStyle(.secondary)
        }
    }
}
