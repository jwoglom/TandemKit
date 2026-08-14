import LoopKitUI
import SwiftUI

struct TandemKitChangeCartridgeView: View {
    @Environment(\.guidanceColors) private var guidanceColors
    @StateObject var viewModel: TandemKitChangeCartridgeViewModel

    @State private var didLoad = false
    @State private var actionSheet: CartridgeActionSheet?

    var body: some View {
        WizardStepContainer(
            currentStep: viewModel.currentStep.rawValue + 1,
            totalSteps: 6,
            canCancel: !viewModel.isProcessing,
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
        .confirmationDialog(item: $actionSheet) { sheet in
            switch sheet {
            case .cancel: return cancelOperationSheet
            case .suspend: return suspendInsulinSheet
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            viewModel.checkSuspendedStatus()
        }
    }

    @ViewBuilder private var currentStepView: some View {
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
                    actionSheet = .suspend
                }
            }
        case .enterMode:
            ContinueButton(
                text: Text("Start cartridge change", comment: "Button text"),
                loading: $viewModel.loadingEnterMode,
                disabled: Binding(
                    get: { viewModel.hasActiveNotifications },
                    set: { _ in }
                )
            ) {
                viewModel.enterChangeCartridgeMode()
            }
        case .waitingForReady:
            EmptyView()
        case .physicalChange:
            Button(action: {
                viewModel.cartridgeInserted()
            }) {
                Text("New Cartridge Inserted", comment: "Button text")
            }
            .disabled(viewModel.hasActiveNotifications)
            .buttonStyle(ActionButtonStyle())
        case .detecting:
            if viewModel.failedExitMode {
                ContinueButton(
                    text: Text("Retry", comment: "Retry button"),
                    loading: $viewModel.loadingExitMode
                ) {
                    viewModel.retryExitCartridgeMode()
                }
            } else {
                EmptyView()
            }
        case .done:
            VStack {
                Button(action: { viewModel.toFillTubing() }) {
                    Text("Fill Tubing", comment: "Button text")
                }
                .buttonStyle(ActionButtonStyle())

                Button(action: { viewModel.done() }) {
                    Text("Done", comment: "Button text")
                }
                .buttonStyle(ActionButtonStyle(.secondary))
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
                        "Changing your cartridge will require suspending insulin delivery.",
                        comment: "Warning message for cartridge change"
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

    private var enterModeStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Step 2: Prepare Pump", comment: "Step header")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Swipe away any active pump notifications below", comment: "Step description")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Embedded notifications check
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Active Notifications", comment: "Notifications section header")
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
                            Text("Checking notifications...", comment: "Loading notifications message")
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
                            Text("No active notifications", comment: "No notifications message")
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

            if viewModel.hasActiveNotifications {
                Label(
                    String(
                        localized:
                        "Clear all notifications before starting cartridge change",
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
                    String(
                        localized:
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
        .task {
            // Auto-refresh notifications when this step appears
            viewModel.notificationsViewModel.refreshNotifications()
        }
    }

    private var waitingForReadyStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Waiting for Pump", comment: "Step header")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("The pump is preparing for cartridge change", comment: "Step description")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if viewModel.changeCartridgeState == .readyToChange {
                Label(
                    String(localized: "Pump is ready", comment: "Status text"),
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
                    Text("Preparing pump...", comment: "Status text")
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
                Text("Step 3: Replace Cartridge", comment: "Step header")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Follow these steps to replace your cartridge", comment: "Step description")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                instructionRow(number: 1, text: String(
                    localized:
                    "Remove the old cartridge from the pump by twisting it off",
                    comment: "Instruction"
                ))
                instructionRow(number: 2, text: String(
                    localized:
                    "Insert a new cartridge and ensure it is securely in place",
                    comment: "Instruction"
                ))
                instructionRow(number: 3, text: String(
                    localized:
                    "Press the button below when complete",
                    comment: "Instruction"
                ))
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)

            // Show active notifications warning during cartridge change
            if viewModel.hasActiveNotifications {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Active Notifications", comment: "Notifications section header")
                            .font(.headline)
                        Spacer()
                    }

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
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)

                Label(
                    String(
                        localized:
                        "Clear all notifications before continuing",
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
        }
        .task {
            // Start periodic notification checking when this step appears
            await viewModel.startPeriodicNotificationCheck()
        }
        .onDisappear {
            // Stop checking when leaving this step
            viewModel.stopPeriodicNotificationCheck()
        }
    }

    private var detectingStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Step 4: Detection", comment: "Step header")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("The pump is detecting insulin in the cartridge", comment: "Step description")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if viewModel.loadingExitMode {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ActivityIndicator(isAnimating: .constant(true), style: .medium)
                        Text("Completing cartridge change...", comment: "Status text")
                            .font(.headline)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Detecting insulin in cartridge...", comment: "Status text")
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

            if viewModel.failedExitMode {
                Label(
                    String(localized: "Failed to complete cartridge change. Please try again.", comment: "Error message"),
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
                    Text("Cartridge change complete!", comment: "Success message")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("You can now fill your tubing and cannula", comment: "Success description")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
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
            viewModel.done()
        } else {
            actionSheet = .cancel
        }
    }

    // MARK: - Confirmation Dialogs

    var suspendInsulinSheet: ConfirmationDialogContent {
        ConfirmationDialogContent(
            title: Text("Suspend insulin delivery?", comment: "Confirmation dialog title"),
            message: Text(
                "This will stop all insulin delivery until you resume.",
                comment: "Confirmation dialog message"
            ),
            actions: [
                .destructive(Text("Yes, Suspend Insulin", comment: "Confirm button")) {
                    viewModel.suspendPumping()
                },
                .cancel(Text("Cancel", comment: "Cancel button"))
            ]
        )
    }

    var cancelOperationSheet: ConfirmationDialogContent {
        ConfirmationDialogContent(
            title: Text("Cancel cartridge change?", comment: "Confirmation dialog title"),
            message: Text(
                "The cartridge change is not complete. The pump will attempt to exit change mode.",
                comment: "Confirmation dialog message"
            ),
            actions: [
                .destructive(Text("Yes, Cancel", comment: "Confirm button")) {
                    viewModel.cancelOperation()
                    viewModel.done()
                },
                .cancel(Text("No, Continue", comment: "Cancel button"))
            ]
        )
    }
}

enum CartridgeActionSheet: Identifiable {
    case cancel
    case suspend
    var id: Self { self }
}

// MARK: - Preview Helpers

private extension TandemKitChangeCartridgeViewModel {
    static func preview(step: CartridgeChangeStep, configure: (TandemKitChangeCartridgeViewModel) -> Void = { _ in
    }) -> TandemKitChangeCartridgeViewModel {
        let viewModel = TandemKitChangeCartridgeViewModel(pumpManager: nil, done: {}, toFillTubing: {})
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

#Preview("Step 6 – Done") {
    NavigationView {
        TandemKitChangeCartridgeView(viewModel: .previewCompleted)
    }
    .environment(\.guidanceColors, GuidanceColors())
}
