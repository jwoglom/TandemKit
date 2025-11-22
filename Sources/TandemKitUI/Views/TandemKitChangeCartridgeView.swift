import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitChangeCartridgeView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.guidanceColors) private var guidanceColors
    @ObservedObject var viewModel: TandemKitChangeCartridgeViewModel

    var body: some View {
        List {
            // Warning section
            Section {
                Text(LocalizedString(
                    "Changing your cartridge will require suspending insulin delivery.",
                    comment: "Warning message for cartridge change"
                ))
            } header: {
                Label(
                    LocalizedString("Important", comment: "Important section header"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundColor(guidanceColors.warning)
            }

            // Step 1: Suspend Insulin
            if viewModel.currentStep == .suspend {
                suspendSection
            } else if viewModel.currentStep.rawValue > CartridgeChangeStep.suspend.rawValue {
                completedStepSection(
                    title: LocalizedString("Step 1: Suspend Insulin", comment: "Step header"),
                    message: LocalizedString("Insulin suspended", comment: "Status text")
                )
            }

            // Step 2: Enter Change Mode
            if viewModel.currentStep == .enterMode {
                enterModeSection
            } else if viewModel.currentStep.rawValue > CartridgeChangeStep.enterMode.rawValue {
                completedStepSection(
                    title: LocalizedString("Step 2: Prepare Pump", comment: "Step header"),
                    message: LocalizedString("Cartridge change mode started", comment: "Status text")
                )
            }

            // Step 3: Waiting for Ready
            if viewModel.currentStep == .waitingForReady {
                waitingForReadySection
            } else if viewModel.currentStep.rawValue > CartridgeChangeStep.waitingForReady.rawValue {
                completedStepSection(
                    title: LocalizedString("Waiting for Pump", comment: "Step header"),
                    message: LocalizedString("Pump ready", comment: "Status text")
                )
            }

            // Step 4: Physical Change
            if viewModel.currentStep == .physicalChange {
                physicalChangeSection
            } else if viewModel.currentStep.rawValue > CartridgeChangeStep.physicalChange.rawValue {
                completedStepSection(
                    title: LocalizedString("Step 3: Replace Cartridge", comment: "Step header"),
                    message: LocalizedString("Cartridge replaced", comment: "Status text")
                )
            }

            // Step 5: Detecting
            if viewModel.currentStep == .detecting {
                detectingSection
            } else if viewModel.currentStep.rawValue > CartridgeChangeStep.detecting.rawValue {
                completedStepSection(
                    title: LocalizedString("Step 4: Detection", comment: "Step header"),
                    message: LocalizedString("Cartridge detected", comment: "Status text")
                )
            }

            // Step 6: Completing
            if viewModel.currentStep == .completing {
                completingSection
            } else if viewModel.currentStep.rawValue > CartridgeChangeStep.completing.rawValue {
                completedStepSection(
                    title: LocalizedString("Step 5: Finalize", comment: "Step header"),
                    message: LocalizedString("Change completed", comment: "Status text")
                )
            }

            // Step 7: Done
            if viewModel.currentStep == .done {
                doneSection
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarTitle(LocalizedString("Change Cartridge", comment: "Title for change cartridge"))
        .navigationBarBackButtonHidden(viewModel.isProcessing)
        .navigationBarItems(trailing: viewModel.isProcessing ? nil : cancelButton)
        .actionSheet(isPresented: $viewModel.showingSuspendConfirmation) {
            suspendInsulinSheet
        }
        .actionSheet(isPresented: $viewModel.showingCancelConfirmation) {
            cancelOperationSheet
        }
    }

    var suspendSection: some View {
        Section {
            if viewModel.isSuspended == true {
                HStack {
                    Label(
                        LocalizedString("Insulin suspended", comment: "Status text"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundColor(.green)
                    Spacer()
                }
            } else {
                Button(action: {
                    viewModel.showingSuspendConfirmation = true
                }) {
                    HStack {
                        Text(LocalizedString("Suspend insulin delivery", comment: "Button to suspend"))
                        Spacer()
                        if viewModel.loadingSuspend {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                        }
                    }
                }
                .disabled(viewModel.loadingSuspend)

                if viewModel.failedSuspend {
                    Label(
                        LocalizedString("Failed to suspend insulin. Please try again.", comment: "Error message"),
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .foregroundColor(guidanceColors.critical)
                }
            }
        } header: {
            Text(LocalizedString("Step 1: Suspend Insulin", comment: "Step header"))
        }
    }

    var enterModeSection: some View {
        Section {
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
            }
        } header: {
            Text(LocalizedString("Step 2: Prepare Pump", comment: "Step header"))
        }
    }

    var waitingForReadySection: some View {
        Section {
            if viewModel.changeCartridgeState == .readyToChange {
                Label(
                    LocalizedString("Pump is ready", comment: "Status text"),
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundColor(.green)
            } else {
                HStack {
                    Text(LocalizedString("Preparing pump...", comment: "Status text"))
                    Spacer()
                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                }
            }
        } header: {
            Text(LocalizedString("Waiting for Pump", comment: "Step header"))
        }
    }

    var physicalChangeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString(
                    "1. Remove the old cartridge from the pump\n2. Insert a new cartridge\n3. Press the button below when complete",
                    comment: "Instructions"
                ))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            Button(action: {
                viewModel.cartridgeInserted()
            }) {
                Text(LocalizedString("New Cartridge Inserted", comment: "Button text"))
            }
        } header: {
            Text(LocalizedString("Step 3: Replace Cartridge", comment: "Step header"))
        }
    }

    var detectingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString("Detecting insulin in cartridge...", comment: "Status text"))
                ProgressView(value: Double(viewModel.detectingProgress) / 100.0) {
                    Text("\(viewModel.detectingProgress)%")
                }
            }
        } header: {
            Text(LocalizedString("Step 4: Detection", comment: "Step header"))
        }
    }

    var completingSection: some View {
        Section {
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
            }
        } header: {
            Text(LocalizedString("Step 5: Finalize", comment: "Step header"))
        }
    }

    var doneSection: some View {
        Section {
            Label(
                LocalizedString("Cartridge change complete!", comment: "Success message"),
                systemImage: "checkmark.circle.fill"
            )
            .foregroundColor(.green)
            .font(.headline)

            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Text(LocalizedString("Done", comment: "Button text"))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    var cancelButton: some View {
        Button(LocalizedString("Cancel", comment: "Cancel button")) {
            if viewModel.currentStep == .suspend || viewModel.currentStep == .done {
                presentationMode.wrappedValue.dismiss()
            } else {
                viewModel.showingCancelConfirmation = true
            }
        }
    }

    func completedStepSection(title: String, message: String) -> some View {
        Section {
            HStack {
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Spacer()
            }
        } header: {
            Text(title)
        }
    }

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
