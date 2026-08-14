import LoopKitUI
import SwiftUI

struct TandemKitFillTubingView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.guidanceColors) private var guidanceColors
    @StateObject var viewModel: TandemKitFillTubingViewModel

    @State private var didLoad = false
    @State private var actionSheet: TubingActionSheet?
    @State private var isConfirmingFillTubing = false

    var body: some View {
        WizardStepContainer(
            currentStep: viewModel.currentStep.rawValue + 1,
            totalSteps: 5,
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
        .actionSheet(item: $actionSheet) { sheet in
            switch sheet {
            case .cancel: return cancelOperationSheet
            case .resume: return resumeOperationSheet
            case .suspend: return suspendInsulinSheet
            }
        }
        .alert(
            String(localized: "Fill Tubing", comment: "Title for the fill tubing disconnect confirmation alert"),
            isPresented: $isConfirmingFillTubing
        ) {
            Button(String(localized: "Cancel", comment: "Cancel button"), role: .cancel) { }
            Button(String(localized: "Begin Fill Tubing", comment: "Confirm button to begin filling tubing")) {
                viewModel.enterFillTubingMode()
            }
        } message: {
            Text(
                "Have you disconnected the pump from your body?",
                comment: "Fill tubing safety confirmation asking the user to confirm the pump is disconnected from their body"
            )
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
        case .filling:
            fillingStepContent
        case .exiting:
            exitingStepContent
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
                text: Text("Start tubing fill", comment: "Button text"),
                loading: $viewModel.loadingEnterMode,
                disabled: Binding(
                    get: { viewModel.hasActiveNotifications },
                    set: { _ in }
                )
            ) {
                isConfirmingFillTubing = true
            }
        case .filling:
            ZStack {
                if viewModel.buttonDown {
                    InsulinFlowIndicator()
                        .transition(.opacity)
                } else if viewModel.hasDisplayedFlow {
                    ContinueButton(
                        text: Text("Complete tubing fill", comment: "Button text"),
                        loading: $viewModel.loadingExitMode,
                        disabled: Binding(
                            get: { !viewModel.canCompleteFill },
                            set: { _ in }
                        )
                    ) {
                        viewModel.tubingFilled()
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.buttonDown)
            .frame(maxWidth: .infinity)
        case .exiting:
            EmptyView()
        case .done:
            VStack {
                Button(action: { viewModel.toFillingCannula() }) {
                    Text("Fill Cannula", comment: "Label for fill cannula")
                }
                .buttonStyle(ActionButtonStyle())

                ContinueButton(
                    text: Text("Done", comment: "Button text"),
                    loading: $viewModel.loadingResume,
                    buttonStyle: .secondary
                ) {
                    actionSheet = .resume
                }
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
                        "Filling tubing requires suspending insulin delivery. You will use the pump button to fill.",
                        comment: "Warning message for tubing fill"
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
                Text("Clear all pump notifications before continuing", comment: "Step description")
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
                    String(
                        localized:
                        "Failed to enter fill mode. Ensure insulin delivery is suspended, the active cartridge contains insulin, and check pump notifications.",
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
                Text("Step 3: Fill Tubing", comment: "Step header")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Use your pump to fill the tubing with insulin", comment: "Step description")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !viewModel.hasActiveNotifications {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        "Press and hold the button on your pump to fill tubing.",
                        comment: "Instructions"
                    )
                    .font(.body)

                    Text(
                        "Watch the tubing for insulin and release the button when you see it.",
                        comment: "Instructions"
                    )
                    .font(.body)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }

            // The pump may have stopped the fill and be waiting to be confirmed; until this read
            // lands we cannot say whether there is anything for the user to acknowledge.
            if viewModel.isCheckingNotifications {
                HStack(spacing: 12) {
                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                    Text("Checking pump status...", comment: "Status text shown while re-reading pump notifications")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }

            // Show active notifications warning during fill
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
                        "Clear all notifications before completing tubing fill",
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

            if viewModel.failedExitMode {
                Label(
                    String(localized: "Failed to complete. Please try again.", comment: "Error message"),
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
            // Start periodic notification checking when this step appears
            await viewModel.startPeriodicNotificationCheck()
        }
        .onDisappear {
            // Stop checking when leaving this step
            viewModel.stopPeriodicNotificationCheck()
        }
    }

    private var exitingStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Completing Fill", comment: "Step header")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Finalizing tubing fill process", comment: "Step description")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                ActivityIndicator(isAnimating: .constant(true), style: .medium)
                Text("Exiting fill mode...", comment: "Status text")
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
                    Text("Tubing fill complete!", comment: "Success message")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("You can now fill your cannula and resume insulin", comment: "Success description")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }

    // MARK: - Actions

    private func handleCancel() {
        if viewModel.currentStep == .suspend || viewModel.currentStep == .done {
            presentationMode.wrappedValue.dismiss()
        } else {
            actionSheet = .cancel
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

    var cancelOperationSheet: ActionSheet {
        ActionSheet(
            title: Text("Cancel tubing fill?", comment: "Action sheet title"),
            message: Text(
                "The tubing fill is not complete. The pump will attempt to exit fill mode.",
                comment: "Action sheet message"
            ),
            buttons: [
                .destructive(Text("Yes, Cancel", comment: "Confirm button")) {
                    viewModel.cancelOperation()
                    presentationMode.wrappedValue.dismiss()
                },
                .cancel(Text("No, Continue", comment: "Cancel button"))
            ]
        )
    }

    var resumeOperationSheet: ActionSheet {
        ActionSheet(
            title: Text("Resume insulin delivery?", comment: "Action sheet title"),
            message: Text(
                "The tubing fill is complete. The pump will attempt to exit fill mode.",
                comment: "Action sheet message"
            ),
            buttons: [
                .default(Text("Yes, Resume delivery", comment: "Confirm button")) {
                    viewModel.resumeDelivery()
                },
                .cancel(Text("No, Go back", comment: "Cancel button"))
            ]
        )
    }
}

enum TubingActionSheet: Identifiable {
    case cancel
    case resume
    case suspend
    var id: Self { self }
}

// MARK: - Insulin Flow Indicator

struct InsulinFlowIndicator: View {
    @State private var heldSeconds: CGFloat = 0
    @State private var repetitionCount: Int = 0
    @State private var animationStart: Date = .init()
    private let baseDropletWidth: CGFloat = 200
    private let dropletHeight: CGFloat = 50
    private let animationDuration: TimeInterval = 2.0
    private let widthIncreasePerRepetition: CGFloat = 25

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geometry in
                let elapsed = context.date.timeIntervalSince(animationStart)
                let repetitions = max(0, Int(elapsed / animationDuration))
                let progress = elapsed.truncatingRemainder(dividingBy: animationDuration) / animationDuration
                let currentDropletWidth = baseDropletWidth + CGFloat(repetitions) * widthIncreasePerRepetition
                let travelDistance = geometry.size.width + currentDropletWidth
                let offsetX = progress * travelDistance - currentDropletWidth
                let opacity = 1.0

                ZStack(alignment: .leading) {
                    // Background - matches blue button style
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)

                    // Animated insulin droplet
                    Capsule()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue.opacity(0.7), Color.blue.opacity(1)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: currentDropletWidth, height: dropletHeight)
                        .opacity(opacity)
                        .offset(x: offsetX)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onChange(of: repetitions) { newValue in
                    repetitionCount = newValue
                }
            }
        }
        .frame(height: dropletHeight)
        .onAppear {
            animationStart = Date()
            repetitionCount = 0
        }
    }
}

// MARK: - Preview Helpers

private extension TandemKitFillTubingViewModel {
    static var previewFilling: TandemKitFillTubingViewModel {
        let viewModel = TandemKitFillTubingViewModel(pumpManager: nil, done: {}, toFillingCannula: {})
        viewModel.currentStep = .filling
        viewModel.isSuspended = true
        viewModel.isProcessing = true
        viewModel.buttonDown = true
        viewModel.hasDisplayedFlow = true
        return viewModel
    }

    static var previewCompleted: TandemKitFillTubingViewModel {
        let viewModel = TandemKitFillTubingViewModel(pumpManager: nil, done: {}, toFillingCannula: {})
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
