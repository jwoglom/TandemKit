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
            VStack(spacing: WizardLayout.verticalPadding) {
                bottomWarnings
                bottomActionView
            }
            .wizardHorizontalPadding()
            .padding(.vertical, WizardLayout.verticalPadding)
        }
        .confirmationAlert(item: $actionSheet) { sheet in
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
        case .disconnect:
            disconnectStepContent
        case .connectTubing:
            connectTubingStepContent
        case .filling:
            fillingStepContent
        case .exiting:
            exitingStepContent
        case .done:
            doneStepContent
        }
    }

    @ViewBuilder private var bottomWarnings: some View {
        switch viewModel.currentStep {
        case .suspend:
            if !viewModel.isCheckingSuspendStatus {
                WizardWarning(text: String(
                    localized: "Filling tubing requires suspending insulin delivery.",
                    comment: "Warning message for tubing fill"
                ))
            }
        case .disconnect, .connectTubing:
            if viewModel.hasActiveNotifications {
                WizardWarning(text: String(
                    localized: "Dismiss all notifications before starting tubing fill",
                    comment: "Warning message"
                ))
            } else {
                disconnectInfusionSetWarning
            }
        case .filling:
            // Stays up with a notification to dismiss: the pump still fills while its button is held.
            disconnectInfusionSetWarning
            if viewModel.hasActiveNotifications {
                WizardWarning(text: String(
                    localized: "Dismiss all notifications before completing tubing fill",
                    comment: "Warning message"
                ))
            }
        case .exiting, .done:
            EmptyView()
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
        case .disconnect:
            ContinueButton(
                text: Text("Continue", comment: "Continue button"),
                disabled: Binding(
                    get: { !viewModel.canStartFill },
                    set: { _ in }
                )
            ) {
                withAnimation {
                    viewModel.currentStep = viewModel.currentStep.nextStep() ?? .done
                }
            }
        case .connectTubing:
            ContinueButton(
                text: Text("Start Tubing Fill", comment: "Button text"),
                loading: $viewModel.loadingEnterMode,
                disabled: Binding(
                    get: { !viewModel.canStartFill },
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
            // Step header
            VStack(alignment: .leading, spacing: 8) {
                Text("Suspend Insulin", comment: "Step header")
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
                .wizardCard(background: Color.green.opacity(0.1))
            } else {
                if viewModel.failedSuspend {
                    Label(
                        String(localized: "Failed to suspend insulin. Please try again.", comment: "Error message"),
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .foregroundColor(guidanceColors.critical)
                    .wizardCard(background: guidanceColors.critical.opacity(0.1))
                }
            }
        }
    }

    private var disconnectStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Disconnect Pump", comment: "Step header")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(
                    viewModel.hasActiveNotifications
                        ? dismissNotificationsText
                        : String(localized: "Disconnect before filling the tubing.", comment: "Step description")
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            if viewModel.hasActiveNotifications {
                WizardNotificationsPanel(viewModel: viewModel.notificationsViewModel)
            } else if viewModel.showsGraphics {
                WizardGraphic(graphic: .disconnectInfusionSet)
            }
        }
        .task {
            viewModel.checkNotificationsBeforeFill()
        }
    }

    private var connectTubingStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect tubing", comment: "Step header")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(
                    viewModel.hasActiveNotifications
                        ? dismissNotificationsText
                        : String(
                            localized: "Attach the tubing's lock connector to your cartridge. Do not connect to your body.",
                            comment: "Step description"
                        )
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            if viewModel.hasActiveNotifications {
                WizardNotificationsPanel(viewModel: viewModel.notificationsViewModel)
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
                .wizardCard(background: guidanceColors.critical.opacity(0.1))
            }
        }
    }

    private var dismissNotificationsText: String {
        String(
            localized: "Please dismiss the active notifications on your pump before filling the tubing.",
            comment: "Step description shown while the pump has notifications to dismiss"
        )
    }

    private var disconnectInfusionSetWarning: some View {
        WizardWarning(text: String(
            localized: "Ensure you have disconnected the infusion set from your body before filling tubing.",
            comment: "Warning shown before and during the tubing fill"
        ))
    }

    private var fillingStepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Fill Tubing", comment: "Step header")
                    .font(.title2)
                    .fontWeight(.bold)
                if viewModel.hasActiveNotifications {
                    Text(dismissNotificationsText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if !viewModel.hasActiveNotifications, viewModel.showsGraphics {
                WizardGraphic(graphic: viewModel.fillingGraphic)
            }

            if !viewModel.hasActiveNotifications, !(viewModel.hasDisplayedFlow && viewModel.isCheckingNotifications) {
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
                .wizardCard(background: Color(.secondarySystemGroupedBackground))
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
                .wizardCard(background: Color(.secondarySystemGroupedBackground))
            }

            if viewModel.hasActiveNotifications {
                WizardNotificationsPanel(viewModel: viewModel.notificationsViewModel)
            }

            if viewModel.failedExitMode {
                Label(
                    String(localized: "Failed to complete. Please try again.", comment: "Error message"),
                    systemImage: "exclamationmark.circle.fill"
                )
                .foregroundColor(guidanceColors.critical)
                .wizardCard(background: guidanceColors.critical.opacity(0.1))
            }
        }
        .alert(
            String(localized: "Release the Pump Button", comment: "Title of the prompt shown when the pump pauses a tubing fill"),
            isPresented: $viewModel.isShowingFillPausedPrompt
        ) {
            Button(String(localized: "OK", comment: "OK button")) {
                viewModel.acknowledgeFillPause()
            }
        } message: {
            Text(
                "Filling has been paused. Do you see insulin dripping from the cannula? Press OK to continue with or complete the fill.",
                comment: "Message of the prompt shown when the pump pauses a tubing fill"
            )
        }
        .task {
            await viewModel.startPeriodicNotificationCheck()
        }
        .onDisappear {
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
            .wizardCard(background: Color.blue.opacity(0.1))
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
            title: Text("Cancel tubing fill?", comment: "Confirmation dialog title"),
            message: Text(
                "The tubing fill is not complete. The pump will attempt to exit fill mode.",
                comment: "Confirmation dialog message"
            ),
            actions: [
                .destructive(Text("Yes, Cancel", comment: "Confirm button")) {
                    viewModel.cancelOperation()
                    presentationMode.wrappedValue.dismiss()
                },
                .cancel(Text("No, Continue", comment: "Cancel button"))
            ]
        )
    }

    var resumeOperationSheet: ConfirmationDialogContent {
        ConfirmationDialogContent(
            title: Text("Resume insulin delivery?", comment: "Confirmation dialog title"),
            message: Text(
                "The tubing fill is complete. The pump will attempt to exit fill mode.",
                comment: "Confirmation dialog message"
            ),
            actions: [
                .primary(Text("Resume delivery", comment: "Confirm button")) {
                    viewModel.resumeDelivery()
                },
                // Leaves delivery suspended, as closing the wizard from this step already does.
                .cancel(Text("Done", comment: "Button that closes the tubing fill without resuming insulin delivery")) {
                    viewModel.done()
                }
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
