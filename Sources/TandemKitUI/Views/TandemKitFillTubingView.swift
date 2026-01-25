import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitFillTubingView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.guidanceColors) private var guidanceColors
    @StateObject var viewModel: TandemKitFillTubingViewModel
    @State private var didLoad = false

    var body: some View {
        WizardStepContainer(
            title: LocalizedString("Fill Tubing", comment: "Title for fill tubing"),
            currentStep: viewModel.currentStep.rawValue + 1,
            totalSteps: 5,
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
            guard !didLoad else { return }
            didLoad = true
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
        case .filling:
            fillingStepContent
        case .exiting:
            exitingStepContent
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
                        "Filling tubing requires suspending insulin delivery. You will use the pump button to fill.",
                        comment: "Warning message for tubing fill"
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
                Text(LocalizedString("Clear all pump notifications before continuing", comment: "Step description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Embedded notifications check
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(LocalizedString("Active Notifications", comment: "Notifications section header"))
                        .font(.headline)
                    Spacer()
                    Button(action: {
                        viewModel.notificationsViewModel.refreshNotifications()
                    }) {
                        if viewModel.notificationsViewModel.isRefreshing {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.notificationsViewModel.isRefreshing)
                }

                if viewModel.notificationsViewModel.isRefreshing && viewModel.notificationsViewModel.notifications.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                            Text(LocalizedString("Checking notifications...", comment: "Loading notifications message"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                } else if viewModel.notificationsViewModel.notifications.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.green)
                            Text(LocalizedString("No active notifications", comment: "No notifications message"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.notificationsViewModel.notifications) { item in
                            NotificationRow(
                                item: item,
                                onDismiss: {
                                    viewModel.notificationsViewModel.dismissNotification(item)
                                },
                                backgroundColor: Color(UIColor.tertiarySystemGroupedBackground)
                            )
                        }
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)

            SaveButton(
                text: LocalizedString("Start tubing fill", comment: "Button text"),
                loading: $viewModel.loadingEnterMode,
                disabled: Binding(
                    get: { viewModel.hasActiveNotifications },
                    set: { _ in }
                )
            ) {
                viewModel.enterFillTubingMode()
            }

            if viewModel.hasActiveNotifications {
                Label(
                    LocalizedString(
                        "Clear all notifications before starting tubing fill",
                        comment: "Warning message"
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundColor(guidanceColors.warning)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(guidanceColors.warning.opacity(0.1))
                .cornerRadius(12)
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
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(guidanceColors.critical.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .task {
            // Auto-refresh notifications when this step appears
            viewModel.notificationsViewModel.refreshNotifications()
        }
    }

    private var fillingStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString("Step 3: Fill Tubing", comment: "Step header"))
                    .font(.title2)
                    .fontWeight(.bold)
                Text(LocalizedString("Use your pump to fill the tubing with insulin", comment: "Step description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

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
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)

            if viewModel.buttonDown {
                HStack(spacing: 12) {
                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                    Text(LocalizedString("Filling tubing...", comment: "Status text"))
                        .font(.headline)
                }
                .foregroundColor(.accentColor)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(12)
            }

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
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(guidanceColors.critical.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    private var exitingStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString("Completing Fill", comment: "Step header"))
                    .font(.title2)
                    .fontWeight(.bold)
                Text(LocalizedString("Finalizing tubing fill process", comment: "Step description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                ActivityIndicator(isAnimating: .constant(true), style: .medium)
                Text(LocalizedString("Exiting fill mode...", comment: "Status text"))
                    .font(.headline)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
    }

    private var doneStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                VStack(spacing: 8) {
                    Text(LocalizedString("Tubing fill complete!", comment: "Success message"))
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

// MARK: - Preview Helpers

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
