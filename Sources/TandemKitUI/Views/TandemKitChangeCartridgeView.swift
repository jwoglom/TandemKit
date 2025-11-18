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
                    "Changing your cartridge will require suspending insulin delivery. Follow each step carefully.",
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
            if viewModel.currentStep.rawValue >= CartridgeChangeStep.suspend.rawValue {
                suspendSection
            }

            // Step 2: Enter Change Mode
            if viewModel.currentStep.rawValue >= CartridgeChangeStep.enterMode.rawValue {
                enterModeSection
            }

            // Step 3: Waiting for Ready
            if viewModel.currentStep.rawValue >= CartridgeChangeStep.waitingForReady.rawValue {
                waitingForReadySection
            }

            // Step 4: Physical Change
            if viewModel.currentStep.rawValue >= CartridgeChangeStep.physicalChange.rawValue {
                physicalChangeSection
            }

            // Step 5: Detecting
            if viewModel.currentStep.rawValue >= CartridgeChangeStep.detecting.rawValue {
                detectingSection
            }

            // Step 6: Completing
            if viewModel.currentStep.rawValue >= CartridgeChangeStep.completing.rawValue {
                completingSection
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
            if viewModel.isSuspended {
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
                    LocalizedString("Failed to enter change mode. Ensure pump is suspended.", comment: "Error message"),
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

#Preview("Active Flow") {
    NavigationView {
        TandemKitChangeCartridgeView(viewModel: .previewInProgress)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

#Preview("Completed") {
    NavigationView {
        TandemKitChangeCartridgeView(viewModel: .previewCompleted)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

private extension TandemKitChangeCartridgeViewModel {
    static var previewInProgress: TandemKitChangeCartridgeViewModel {
        let viewModel = TandemKitChangeCartridgeViewModel(pumpManager: nil)
        viewModel.isSuspended = true
        viewModel.currentStep = .detecting
        viewModel.isProcessing = true
        viewModel.changeCartridgeState = .readyToChange
        viewModel.isDetecting = true
        viewModel.detectingProgress = 60
        return viewModel
    }

    static var previewCompleted: TandemKitChangeCartridgeViewModel {
        let viewModel = TandemKitChangeCartridgeViewModel(pumpManager: nil)
        viewModel.isSuspended = true
        viewModel.currentStep = .done
        viewModel.isProcessing = false
        return viewModel
    }
}
