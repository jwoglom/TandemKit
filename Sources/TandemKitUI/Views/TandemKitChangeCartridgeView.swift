import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitChangeCartridgeView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.guidanceColors) private var guidanceColors
    @StateObject var viewModel: TandemKitChangeCartridgeViewModel
    @State private var didLoad = false

    var body: some View {
        WizardStepContainer(
            title: LocalizedString("Change Cartridge", comment: "Title for change cartridge"),
            currentStep: viewModel.currentStep.rawValue + 1,
            totalSteps: 7,
            canCancel: !viewModel.isProcessing,
            onCancel: handleCancel
        ) {
            currentStepView
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
                .id(viewModel.currentStep)
        }
        .actionSheet(isPresented: $viewModel.showingCancelConfirmation) {
            cancelOperationSheet
        }
        .task {
            print("TandemKit Change Cartridge: .task called, didLoad=\(didLoad)")
            guard !didLoad else {
                print("TandemKit Change Cartridge: .task skipped - already loaded")
                return
            }
            didLoad = true
            print("TandemKit Change Cartridge: Calling checkSuspendedStatus()")
            viewModel.checkSuspendedStatus()
        }
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch viewModel.currentStep {
        case .suspend:
            suspendStepContent
        case .enterMode:
            enterModeStepContent
        case .waitingForReady:
            waitingForReadyStepContent
        case .physicalChange:
            physicalChangeStepContent
        case .detecting:
            detectingStepContent
        case .completing:
            completingStepContent
        case .done:
            doneStepContent
        }
    }

    // MARK: - Step Content Views

    private var suspendStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Warning banner
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(guidanceColors.warning)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedString("Important", comment: "Important section header"))
                        .font(.headline)
                        .foregroundColor(guidanceColors.warning)
                    Text(LocalizedString(
                        "Changing your cartridge will require suspending insulin delivery.",
                        comment: "Warning message for cartridge change"
                    ))
                    .font(.subheadline)
                }
            }
            .padding()
            .background(guidanceColors.warning.opacity(0.1))
            .cornerRadius(12)

            // Step header
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString("Step 1: Suspend Insulin", comment: "Step header"))
                    .font(.title2)
                    .fontWeight(.bold)
                Text(LocalizedString("First, suspend insulin delivery", comment: "Step description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Step content
            if viewModel.isSuspended == true {
                Label(
                    LocalizedString("Insulin suspended", comment: "Status text"),
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundColor(.green)
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)

                ContinueButton(text: LocalizedString("Continue", comment: "Continue button")) {
                    withAnimation {
                        viewModel.currentStep = viewModel.currentStep.nextStep() ?? .done
                    }
                }
            } else {
                SaveButton(
                    text: LocalizedString("Suspend insulin delivery", comment: "Button to suspend"),
                    loading: $viewModel.loadingSuspend
                ) {
                    viewModel.showingSuspendConfirmation = true
                }
                .actionSheet(isPresented: $viewModel.showingSuspendConfirmation) {
                    suspendInsulinSheet
                }

                if viewModel.failedSuspend {
                    Label(
                        LocalizedString("Failed to suspend insulin. Please try again.", comment: "Error message"),
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .foregroundColor(guidanceColors.critical)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(guidanceColors.critical.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
    }

    private var enterModeStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString("Step 2: Prepare Pump", comment: "Step header"))
                    .font(.title2)
                    .fontWeight(.bold)
                Text(LocalizedString("Start cartridge change mode on the pump", comment: "Step description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            SaveButton(
                text: LocalizedString("Start cartridge change", comment: "Button text"),
                loading: $viewModel.loadingEnterMode
            ) {
                viewModel.enterChangeCartridgeMode()
            }

            if viewModel.failedEnterMode {
                Label(
                    LocalizedString(
                        "Failed to enter change mode. Ensure insulin delivery is suspended and check pump notifications.",
                        comment: "Error message"
                    ),
                    systemImage: "exclamationmark.circle.fill"
                )
                .foregroundColor(guidanceColors.critical)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(guidanceColors.critical.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    private var waitingForReadyStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString("Waiting for Pump", comment: "Step header"))
                    .font(.title2)
                    .fontWeight(.bold)
                Text(LocalizedString("The pump is preparing for cartridge change", comment: "Step description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if viewModel.changeCartridgeState == .readyToChange {
                Label(
                    LocalizedString("Pump is ready", comment: "Status text"),
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundColor(.green)
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            } else {
                HStack(spacing: 12) {
                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                    Text(LocalizedString("Preparing pump...", comment: "Status text"))
                        .font(.headline)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    private var physicalChangeStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString("Step 3: Replace Cartridge", comment: "Step header"))
                    .font(.title2)
                    .fontWeight(.bold)
                Text(LocalizedString("Follow these steps to replace your cartridge", comment: "Step description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                instructionRow(number: 1, text: LocalizedString(
                    "Remove the old cartridge from the pump",
                    comment: "Instruction"
                ))
                instructionRow(number: 2, text: LocalizedString(
                    "Insert a new cartridge",
                    comment: "Instruction"
                ))
                instructionRow(number: 3, text: LocalizedString(
                    "Press the button below when complete",
                    comment: "Instruction"
                ))
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)

            Button(action: {
                viewModel.cartridgeInserted()
            }) {
                Text(LocalizedString("New Cartridge Inserted", comment: "Button text"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
    }

    private var detectingStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString("Step 4: Detection", comment: "Step header"))
                    .font(.title2)
                    .fontWeight(.bold)
                Text(LocalizedString("The pump is detecting insulin in the cartridge", comment: "Step description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedString("Detecting insulin in cartridge...", comment: "Status text"))
                    .font(.headline)
                ProgressView(value: Double(viewModel.detectingProgress) / 100.0)
                    .progressViewStyle(LinearProgressViewStyle())
                Text("\(viewModel.detectingProgress)%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
    }

    private var completingStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString("Step 5: Finalize", comment: "Step header"))
                    .font(.title2)
                    .fontWeight(.bold)
                Text(LocalizedString("Complete the cartridge change process", comment: "Step description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            SaveButton(
                text: LocalizedString("Complete cartridge change", comment: "Button text"),
                loading: $viewModel.loadingExitMode
            ) {
                viewModel.exitChangeCartridgeMode()
            }

            if viewModel.failedExitMode {
                Label(
                    LocalizedString("Failed to complete. Please try again.", comment: "Error message"),
                    systemImage: "exclamationmark.circle.fill"
                )
                .foregroundColor(guidanceColors.critical)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(guidanceColors.critical.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    private var doneStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                VStack(spacing: 8) {
                    Text(LocalizedString("Cartridge change complete!", comment: "Success message"))
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text(LocalizedString("You can now use your pump normally", comment: "Success description"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)

            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Text(LocalizedString("Done", comment: "Button text"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
    }

    // MARK: - Helper Views

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number).")
                .font(.headline)
                .foregroundColor(.blue)
            Text(text)
                .font(.body)
        }
    }

    // MARK: - Actions

    private func handleCancel() {
        if viewModel.currentStep == .suspend || viewModel.currentStep == .done {
            presentationMode.wrappedValue.dismiss()
        } else {
            viewModel.showingCancelConfirmation = true
        }
    }

    // MARK: - Action Sheets

    var suspendInsulinSheet: ActionSheet {
        ActionSheet(
            title: Text(LocalizedString("Suspend insulin delivery?", comment: "Action sheet title")),
            message: Text(LocalizedString(
                "This will stop all insulin delivery until you resume.",
                comment: "Action sheet message"
            )),
            buttons: [
                .destructive(Text(LocalizedString("Yes, Suspend Insulin", comment: "Confirm button"))) {
                    viewModel.suspendPumping()
                },
                .cancel(Text(LocalizedString("Cancel", comment: "Cancel button")))
            ]
        )
    }

    var cancelOperationSheet: ActionSheet {
        ActionSheet(
            title: Text(LocalizedString("Cancel cartridge change?", comment: "Action sheet title")),
            message: Text(LocalizedString(
                "The cartridge change is not complete. The pump will attempt to exit change mode.",
                comment: "Action sheet message"
            )),
            buttons: [
                .destructive(Text(LocalizedString("Yes, Cancel", comment: "Confirm button"))) {
                    viewModel.cancelOperation()
                    presentationMode.wrappedValue.dismiss()
                },
                .cancel(Text(LocalizedString("No, Continue", comment: "Cancel button")))
            ]
        )
    }
}

// MARK: - Preview Helpers

private extension TandemKitChangeCartridgeViewModel {
    static func preview(step: CartridgeChangeStep, configure: (TandemKitChangeCartridgeViewModel) -> Void = { _ in
    }) -> TandemKitChangeCartridgeViewModel {
        let viewModel = TandemKitChangeCartridgeViewModel(pumpManager: nil)
        viewModel.currentStep = step
        configure(viewModel)
        return viewModel
    }

    static var previewSuspendPrompt: TandemKitChangeCartridgeViewModel {
        preview(step: .suspend) {
            $0.isSuspended = false
        }
    }

    static var previewEnterMode: TandemKitChangeCartridgeViewModel {
        preview(step: .enterMode) {
            $0.isSuspended = true
        }
    }

    static var previewWaitingForReady: TandemKitChangeCartridgeViewModel {
        preview(step: .waitingForReady) {
            $0.isSuspended = true
            $0.isProcessing = true
            $0.changeCartridgeState = .readyToChange
        }
    }

    static var previewPhysicalChange: TandemKitChangeCartridgeViewModel {
        preview(step: .physicalChange) {
            $0.isSuspended = true
        }
    }

    static var previewDetecting: TandemKitChangeCartridgeViewModel {
        preview(step: .detecting) {
            $0.isSuspended = true
            $0.isProcessing = true
            $0.isDetecting = true
            $0.detectingProgress = 45
        }
    }

    static var previewCompleting: TandemKitChangeCartridgeViewModel {
        preview(step: .completing) {
            $0.isSuspended = true
            $0.isProcessing = true
            $0.loadingExitMode = false
        }
    }

    static var previewCompleted: TandemKitChangeCartridgeViewModel {
        preview(step: .done) {
            $0.isSuspended = true
            $0.isProcessing = false
        }
    }
}

#Preview("Step 1 – Suspend") {
    NavigationView {
        TandemKitChangeCartridgeView(viewModel: .previewSuspendPrompt)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

#Preview("Step 2 – Enter Mode") {
    NavigationView {
        TandemKitChangeCartridgeView(viewModel: .previewEnterMode)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

#Preview("Step 3 – Waiting") {
    NavigationView {
        TandemKitChangeCartridgeView(viewModel: .previewWaitingForReady)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

#Preview("Step 4 – Physical Change") {
    NavigationView {
        TandemKitChangeCartridgeView(viewModel: .previewPhysicalChange)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

#Preview("Step 5 – Detecting") {
    NavigationView {
        TandemKitChangeCartridgeView(viewModel: .previewDetecting)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

#Preview("Step 6 – Completing") {
    NavigationView {
        TandemKitChangeCartridgeView(viewModel: .previewCompleting)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

#Preview("Step 7 – Done") {
    NavigationView {
        TandemKitChangeCartridgeView(viewModel: .previewCompleted)
    }
    .environment(\.guidanceColors, GuidanceColors())
}
