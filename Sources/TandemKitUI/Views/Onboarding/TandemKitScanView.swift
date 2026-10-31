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
            viewModel.startCheckingForConnectedPump()
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
            String(localized: "Pump Already Connected", comment: "Title of the warning when the pump is connected to the phone"),
            isPresented: $viewModel.isConnectedElsewhere,
            actions: {
                Button(String(localized: "OK", comment: "OK button")) {
                    viewModel.connectedElsewhereDismissed()
                }
            },
            message: { Text(viewModel.connectedElsewhereMessage) }
        )
        .alert(
            String(localized: "Multiple Pumps Found", comment: "Title of the notice when more than one pump is advertising"),
            isPresented: $viewModel.isMultiplePumpsFound,
            actions: {
                Button(String(localized: "OK", comment: "OK button")) {
                    viewModel.multiplePumpsDismissed()
                }
            },
            message: { Text(viewModel.multiplePumpsMessage) }
        )
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
        .sheet(isPresented: $viewModel.isPromptingPincode) {
            PairingCodePrompt(viewModel: viewModel)
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
                .multilineTextAlignment(.center)

            Image(imageName: "mobi_on_pad")
                .resizable()
                .scaledToFit()
                .padding(.horizontal)
                .frame(height: 150)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder var DoubleTapView: some View {
        VStack(alignment: .center, spacing: 40) {
            VStack(alignment: .center, spacing: 10) {
                Text(
                    "Pick up your pump, wait a second, then double-press the T button",
                    comment: "Double-tap explanation"
                )
                .font(.headline)
                .bold()
                .multilineTextAlignment(.center)

                Text(String(localized: "Found device ", comment: "Found device prefix text") + (viewModel.connectingTo ?? ""))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Image(imageName: "mobi_double_tap")
                .resizable()
                .scaledToFit()
                .padding(.horizontal)
                .frame(height: 150)

            Spacer()

            Text("You should hear two beeps after double-pressing the button.", comment: "Beep explanation")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
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

private struct PairingCodePrompt: View {
    @Environment(\.guidanceColors) private var guidanceColors
    @ObservedObject var viewModel: TandemKitScanViewModel

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text(viewModel.pinPromptHeading)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                PairingCodeField(code: $viewModel.devicePinCode, length: TandemKitScanViewModel.pairingCodeLength)

                if let message = viewModel.pinCodePromptError, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(guidanceColors.critical)
                        .multilineTextAlignment(.center)
                }

                Text(String(
                    localized:
                    "The pairing code is located on the inside of the cartridge area labeled as 'PIN' and consists of six numbers.",
                    comment: "Tandem instructions for finding pairing code"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                Spacer()

                ContinueButton(
                    text: Text("Pair", comment: "Pair button"),
                    disabled: .constant(!viewModel.isPinCodeComplete)
                ) {
                    viewModel.processPinPrompt()
                }
            }
            .padding()
            .navigationTitle(String(localized: "Enter Pairing code", comment: "Enter Pairing code instruction"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Cancel button title")) {
                        viewModel.cancelPinPrompt()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled()
    }
}

/// The invisible field under the boxes takes the typing, pasting and VoiceOver.
struct PairingCodeField: View {
    @Binding var code: String
    let length: Int

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .foregroundColor(.clear)
                .tint(.clear)
                .focused($isFocused)
                .accessibilityLabel(Text("PIN", comment: "Tandem pairing code prompt"))

            HStack(spacing: 8) {
                ForEach(0 ..< length, id: \.self) { index in
                    digitBox(at: index)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: 360)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onAppear {
            // Focus set while the sheet is still animating in is dropped.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isFocused = true }
        }
    }

    private func digitBox(at index: Int) -> some View {
        let digits = Array(code)
        let isCurrent = isFocused && (index == digits.count || (digits.count == length && index == length - 1))
        return Text(verbatim: index < digits.count ? String(digits[index]) : "")
            .font(.title.weight(.semibold).monospacedDigit())
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isCurrent ? Color.accentColor : Color(UIColor.systemGray4), lineWidth: isCurrent ? 2 : 1)
            )
    }
}
