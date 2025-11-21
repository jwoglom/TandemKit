import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitFillCannulaView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.guidanceColors) private var guidanceColors
    @ObservedObject var viewModel: TandemKitFillCannulaViewModel

    let unitText = LocalizedString("U", comment: "Insulin unit")

    var body: some View {
        List {
            // Warning section
            Section {
                Text(LocalizedString(
                    "Filling cannula requires suspending insulin delivery. Select the prime amount carefully.",
                    comment: "Warning message for cannula fill"
                ))
            } header: {
                Label(
                    LocalizedString("Important", comment: "Important section header"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundColor(guidanceColors.warning)
            }

            // Step 1: Suspend Insulin
            if viewModel.currentStep.rawValue >= CannulaFillStep.suspend.rawValue {
                suspendSection
            }

            // Step 2: Enter Amount
            if viewModel.currentStep.rawValue >= CannulaFillStep.enterAmount.rawValue {
                enterAmountSection
            }

            // Step 3: Filling
            if viewModel.currentStep.rawValue >= CannulaFillStep.filling.rawValue {
                fillingSection
            }

            // Step 4: Done
            if viewModel.currentStep == .done {
                doneSection
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarTitle(LocalizedString("Fill Cannula", comment: "Title for fill cannula"))
        .navigationBarBackButtonHidden(viewModel.isProcessing)
        .navigationBarItems(trailing: viewModel.isProcessing ? nil : cancelButton)
        .actionSheet(isPresented: $viewModel.showingSuspendConfirmation) {
            suspendInsulinSheet
        }
        .actionSheet(isPresented: $viewModel.showingCancelConfirmation) {
            cancelOperationSheet
        }
        .actionSheet(isPresented: $viewModel.showingResumeConfirmation) {
            resumeInsulinSheet
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

    var enterAmountSection: some View {
        Section {
            HStack {
                Text(LocalizedString("Prime amount", comment: "Label for prime amount"))
                    .foregroundColor(Color.primary)
                Spacer()
                Text(String(format: "%.1f", viewModel.primeAmount) + self.unitText)
            }
            .foregroundColor(viewModel.isEditingAmount ? Color.blue : Color.primary)
            .onTapGesture {
                withAnimation {
                    viewModel.isEditingAmount.toggle()
                }
            }

            if viewModel.isEditingAmount {
                Picker("Amount", selection: $viewModel.primeAmount) {
                    ForEach(Array(stride(from: 0.1, through: 2.0, by: 0.1)), id: \.self) { amount in
                        Text(String(format: "%.1f", amount) + self.unitText).tag(amount)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .padding(.horizontal)
            }

            SaveButton(
                text: LocalizedString("Fill cannula", comment: "Button text"),
                loading: $viewModel.loadingFill
            ) {
                viewModel.fillCannula()
            }

            if viewModel.failedFill {
                Label(
                    LocalizedString(
                        "Failed to fill cannula. Ensure insulin delivery is suspended and check pump notifications.",
                        comment: "Error message"
                    ),
                    systemImage: "exclamationmark.circle.fill"
                )
                .foregroundColor(guidanceColors.critical)
            }
        } header: {
            Text(LocalizedString("Step 2: Set Prime Amount", comment: "Step header"))
        }
    }

    var fillingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString("Delivering prime...", comment: "Status text"))
                ProgressView()
            }
        } header: {
            Text(LocalizedString("Step 3: Filling", comment: "Step header"))
        }
    }

    var doneSection: some View {
        Section {
            Label(
                LocalizedString("Cannula fill complete!", comment: "Success message"),
                systemImage: "checkmark.circle.fill"
            )
            .foregroundColor(.green)
            .font(.headline)

            Button(action: {
                viewModel.showingResumeConfirmation = true
            }) {
                Text(LocalizedString("Resume insulin delivery", comment: "Button text"))
            }

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

    var resumeInsulinSheet: ActionSheet {
        ActionSheet(
            title: Text(LocalizedString("Resume insulin delivery?", comment: "Action sheet title")),
            message: Text(LocalizedString(
                "This will restart your scheduled basal insulin.",
                comment: "Action sheet message"
            )),
            buttons: [
                .default(Text(LocalizedString("Yes, Resume Insulin", comment: "Confirm button"))) {
                    viewModel.resumePumping()
                    presentationMode.wrappedValue.dismiss()
                },
                .cancel(Text(LocalizedString("Not Yet", comment: "Cancel button")))
            ]
        )
    }

    var cancelOperationSheet: ActionSheet {
        ActionSheet(
            title: Text(LocalizedString("Cancel cannula fill?", comment: "Action sheet title")),
            message: Text(LocalizedString(
                "The cannula fill is not complete.",
                comment: "Action sheet message"
            )),
            buttons: [
                .destructive(Text(LocalizedString("Yes, Cancel", comment: "Confirm button"))) {
                    presentationMode.wrappedValue.dismiss()
                },
                .cancel(Text(LocalizedString("No, Continue", comment: "Cancel button")))
            ]
        )
    }
}

#Preview("Enter Amount") {
    NavigationView {
        TandemKitFillCannulaView(viewModel: .previewEnteringAmount)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

#Preview("Completed") {
    NavigationView {
        TandemKitFillCannulaView(viewModel: .previewCompleted)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

private extension TandemKitFillCannulaViewModel {
    static var previewEnteringAmount: TandemKitFillCannulaViewModel {
        let viewModel = TandemKitFillCannulaViewModel(pumpManager: nil)
        viewModel.isSuspended = true
        viewModel.currentStep = .enterAmount
        viewModel.isEditingAmount = true
        viewModel.primeAmount = 0.7
        return viewModel
    }

    static var previewCompleted: TandemKitFillCannulaViewModel {
        let viewModel = TandemKitFillCannulaViewModel(pumpManager: nil)
        viewModel.isSuspended = true
        viewModel.currentStep = .done
        return viewModel
    }
}
