import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitFillCannulaView: View {
    @Environment(\.guidanceColors) private var guidanceColors
    @Environment(\.dismissAction) private var dismiss
    @StateObject var viewModel: TandemKitFillCannulaViewModel
    @State private var didLoad = false

    let unitText = String(localized: "U", comment: "Insulin unit")

    var body: some View {
        WizardStepContainer(
            title: String(localized: "Fill Cannula", comment: "Title for fill cannula"),
            currentStep: viewModel.currentStep.rawValue + 1,
            totalSteps: 3,
            canCancel: !viewModel.isProcessing && viewModel.currentStep != .done,
            disableInteractiveDismiss: true,
            lockModalWhenCantCancel: true,
            onCancel: handleCancel
        ) {
            currentStepView
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
                .id(viewModel.currentStep)
        }
        .safeAreaInset(edge: .bottom) {
            bottomActionView
                .padding()
        }
        .actionSheet(item: $viewModel.activeActionSheet) { sheet in
            switch sheet {
            case .suspend:
                return suspendInsulinSheet
            case .resume:
                return resumeInsulinSheet
            case .cancel:
                return cancelOperationSheet
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            viewModel.checkSuspendedStatus()
        }
        .onChange(of: viewModel.resumeSucceeded) { succeeded in
            if succeeded {
                dismiss()
            }
        }
    }

    @ViewBuilder private var currentStepView: some View {
        switch viewModel.currentStep {
        case .suspend:
            suspendStepContent
        case .enterAmount:
            enterAmountStepContent
        case .done:
            doneStepContent
        }
    }

    @ViewBuilder private var bottomActionView: some View {
        switch viewModel.currentStep {
        case .suspend:
            if viewModel.isSuspended == true {
                ContinueButton(text: Text("Continue", comment: "Continue button")) {
                    withAnimation {
                        viewModel.currentStep = viewModel.currentStep.nextStep() ?? .done
                    }
                }
            } else {
                ContinueButton(
                    text: Text("Suspend insulin delivery", comment: "Button to suspend"),
                    loading: $viewModel.loadingSuspend
                ) {
                    viewModel.activeActionSheet = .suspend
                }
            }
        case .enterAmount:
            ContinueButton(
                text: Text("Fill Cannula", comment: "Button text"),
                loading: $viewModel.loadingFill
            ) {
                viewModel.fillCannula()
            }
        case .done:
            ContinueButton(
                text: Text("Resume insulin delivery", comment: "Button text"),
                loading: $viewModel.loadingResume
            ) {
                viewModel.activeActionSheet = .resume
            }
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
                    Text("Important", comment: "Important section header")
                        .font(.headline)
                        .foregroundColor(guidanceColors.warning)
                    Text(
                        "Filling cannula requires suspending insulin delivery. Select the prime amount carefully.",
                        comment: "Warning message for cannula fill"
                    )
                    .font(.subheadline)
                }
            }
            .padding()
            .background(guidanceColors.warning.opacity(0.1))
            .cornerRadius(12)

            // Step header
            VStack(alignment: .leading, spacing: 8) {
                Text("Step 1: Suspend Insulin", comment: "Step header")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("First, suspend insulin delivery", comment: "Step description")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Step content
            if viewModel.isSuspended == true {
                Label(
                    String(localized: "Insulin suspended", comment: "Status text"),
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundColor(.green)
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            } else {
                if viewModel.failedSuspend {
                    Label(
                        String(localized: "Failed to suspend insulin. Please try again.", comment: "Error message"),
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

    private var enterAmountStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Step 2: Set Prime Amount", comment: "Step header")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Select how much insulin to prime the cannula", comment: "Step description")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 16) {
                HStack {
                    Text("Prime amount", comment: "Label for prime amount")
                        .font(.headline)
                        .foregroundColor(Color.primary)
                    Spacer()
                    Text(String(format: "%.1f", viewModel.primeAmount) + self.unitText)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(viewModel.isEditingAmount ? Color.blue : Color.primary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
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
                    .frame(height: 150)
                    .clipped()
                }
            }

            if viewModel.failedFill {
                Label(
                    String(
                        localized:
                        "Failed to fill cannula. Ensure insulin delivery is suspended, the active cartridge contains insulin, the tubing has been filled, and check pump notifications.",
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

    private var doneStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                VStack(spacing: 8) {
                    Text("Cannula fill complete!", comment: "Success message")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text(String(format: String(localized: "%.1f U primed", comment: "Status text"), viewModel.primeAmount))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)

            if viewModel.failedResume {
                Label(
                    String(localized: "Failed to resume insulin. Please try again.", comment: "Error message"),
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

    // MARK: - Actions

    private func handleCancel() {
        if viewModel.currentStep == .suspend || viewModel.currentStep == .done {
            viewModel.done()
        } else {
            viewModel.activeActionSheet = .cancel
        }
    }

    // MARK: - Action Sheets

    var suspendInsulinSheet: ActionSheet {
        ActionSheet(
            title: Text("Suspend insulin delivery?", comment: "Action sheet title"),
            message: Text(
                "This will stop all insulin delivery until you resume.",
                comment: "Action sheet message"
            ),
            buttons: [
                .destructive(Text("Yes, Suspend Insulin", comment: "Confirm button")) {
                    viewModel.suspendPumping()
                },
                .cancel(Text("Cancel", comment: "Cancel button"))
            ]
        )
    }

    var resumeInsulinSheet: ActionSheet {
        ActionSheet(
            title: Text("Resume insulin delivery?", comment: "Action sheet title"),
            message: Text(
                "This will restart your scheduled basal insulin.",
                comment: "Action sheet message"
            ),
            buttons: [
                .default(Text("Yes, Resume Insulin", comment: "Confirm button")) {
                    viewModel.resumePumping()
                },
                .destructive(Text("Cancel", comment: "Cancel button"))
            ]
        )
    }

    var cancelOperationSheet: ActionSheet {
        ActionSheet(
            title: Text("Cancel cannula fill?", comment: "Action sheet title"),
            message: Text(
                "The cannula fill is not complete.",
                comment: "Action sheet message"
            ),
            buttons: [
                .destructive(Text("Yes, Cancel", comment: "Confirm button")) {
                    viewModel.done()
                },
                .cancel(Text("No, Continue", comment: "Cancel button"))
            ]
        )
    }
}

// MARK: - Preview Helpers

private extension TandemKitFillCannulaViewModel {
    static var previewEnteringAmount: TandemKitFillCannulaViewModel {
        let viewModel = TandemKitFillCannulaViewModel(pumpManager: nil, done: {})
        viewModel.isSuspended = true
        viewModel.currentStep = .enterAmount
        viewModel.isEditingAmount = true
        viewModel.primeAmount = 0.7
        return viewModel
    }

    static var previewCompleted: TandemKitFillCannulaViewModel {
        let viewModel = TandemKitFillCannulaViewModel(pumpManager: nil, done: {})
        viewModel.isSuspended = true
        viewModel.currentStep = .done
        return viewModel
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
