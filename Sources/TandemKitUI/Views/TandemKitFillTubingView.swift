import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitFillTubingView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.guidanceColors) private var guidanceColors
    @ObservedObject var viewModel: TandemKitFillTubingViewModel
    @State private var didLoad = false

    var body: some View {
        List {
            // Warning section
            Section {
                Text(LocalizedString(
                    "Filling tubing requires suspending insulin delivery. You will use the pump button to fill.",
                    comment: "Warning message for tubing fill"
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
            } else if viewModel.currentStep.rawValue > TubingFillStep.suspend.rawValue {
                completedStepSection(
                    title: LocalizedString("Step 1: Suspend Insulin", comment: "Step header"),
                    message: LocalizedString("Insulin suspended", comment: "Status text")
                )
            }

            // Step 2: Enter Fill Mode
            if viewModel.currentStep == .enterMode {
                enterModeSection
            } else if viewModel.currentStep.rawValue > TubingFillStep.enterMode.rawValue {
                completedStepSection(
                    title: LocalizedString("Step 2: Prepare Pump", comment: "Step header"),
                    message: LocalizedString("Fill mode started", comment: "Status text")
                )
            }

            // Step 3: Filling
            if viewModel.currentStep == .filling {
                fillingSection
            } else if viewModel.currentStep.rawValue > TubingFillStep.filling.rawValue {
                completedStepSection(
                    title: LocalizedString("Step 3: Fill Tubing", comment: "Step header"),
                    message: LocalizedString("Tubing filled", comment: "Status text")
                )
            }

            // Step 4: Done
            if viewModel.currentStep == .done {
                doneSection
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarTitle(LocalizedString("Fill Tubing", comment: "Title for fill tubing"))
        .navigationBarBackButtonHidden(viewModel.isProcessing)
        .navigationBarItems(trailing: viewModel.isProcessing ? nil : cancelButton)
        .task {
            guard !didLoad else { return }
            didLoad = true
            viewModel.checkSuspendedStatus()
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
                .actionSheet(isPresented: $viewModel.showingSuspendConfirmation) {
                    suspendInsulinSheet
                }

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
                text: LocalizedString("Start tubing fill", comment: "Button text"),
                loading: $viewModel.loadingEnterMode
            ) {
                viewModel.enterFillTubingMode()
            }

            if viewModel.failedEnterMode {
                Label(
                    LocalizedString(
                        "Failed to enter fill mode. Ensure insulin delivery is suspended and check pump notifications.",
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

    var fillingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedString(
                    "Press and hold the button on your pump to fill tubing.",
                    comment: "Instructions"
                ))
                    .font(.body)

                Text(LocalizedString(
                    "Watch the tubing for insulin and release the button when you see it.",
                    comment: "Instructions"
                ))
                    .font(.body)

                if viewModel.buttonDown {
                    HStack {
                        Text(LocalizedString("Filling tubing...", comment: "Status text"))
                        Spacer()
                        ActivityIndicator(isAnimating: .constant(true), style: .medium)
                    }
                    .foregroundColor(.accentColor)
                }
            }
            .padding(.vertical, 4)

            SaveButton(
                text: LocalizedString("Tubing filled", comment: "Button text"),
                loading: $viewModel.loadingExitMode
            ) {
                viewModel.tubingFilled()
            }

            if viewModel.failedExitMode {
                Label(
                    LocalizedString("Failed to complete. Please try again.", comment: "Error message"),
                    systemImage: "exclamationmark.circle.fill"
                )
                .foregroundColor(guidanceColors.critical)
            }
        } header: {
            Text(LocalizedString("Step 3: Fill Tubing", comment: "Step header"))
        }
    }

    var doneSection: some View {
        Section {
            Label(
                LocalizedString("Tubing fill complete!", comment: "Success message"),
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
        .actionSheet(isPresented: $viewModel.showingCancelConfirmation) {
            cancelOperationSheet
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
            title: Text(LocalizedString("Cancel tubing fill?", comment: "Action sheet title")),
            message: Text(LocalizedString(
                "The tubing fill is not complete. The pump will attempt to exit fill mode.",
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

#Preview("Filling") {
    NavigationView {
        TandemKitFillTubingView(viewModel: .previewFilling)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

#Preview("Completed") {
    NavigationView {
        TandemKitFillTubingView(viewModel: .previewCompleted)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

private extension TandemKitFillTubingViewModel {
    static var previewFilling: TandemKitFillTubingViewModel {
        let viewModel = TandemKitFillTubingViewModel(pumpManager: nil)
        viewModel.currentStep = .filling
        viewModel.isSuspended = true
        viewModel.isProcessing = true
        viewModel.buttonDown = true
        return viewModel
    }

    static var previewCompleted: TandemKitFillTubingViewModel {
        let viewModel = TandemKitFillTubingViewModel(pumpManager: nil)
        viewModel.currentStep = .done
        viewModel.isSuspended = true
        viewModel.exitState = .tubingFilled
        return viewModel
    }
}
