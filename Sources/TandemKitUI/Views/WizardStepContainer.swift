import SwiftUI

/// Layout metrics shared by every screen in the change-cartridge / fill-tubing /
/// fill-cannula wizards, so the progress bar, the scrolling step content and the
/// pinned bottom action all sit on the same left and right gutter.
enum WizardLayout {
    /// Horizontal gutter between the screen edge and wizard content.
    static let horizontalPadding: CGFloat = 16
    /// Vertical padding above and below the pinned bottom action.
    static let verticalPadding: CGFloat = 16
    /// Corner radius shared by every wizard card.
    static let cardCornerRadius: CGFloat = 12
    /// Inset between a wizard card's edge and its content.
    static let cardPadding: CGFloat = 16
    /// Spacing between the stacked elements of a step.
    static let stepSpacing: CGFloat = 20
}

extension View {
    /// The standard wizard card: uniform inner inset, full available width, and a
    /// leading-aligned body. Every card in the wizards uses this so their edges
    /// line up with each other and with the step headers.
    func wizardCard(background: Color) -> some View {
        padding(WizardLayout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .cornerRadius(WizardLayout.cardCornerRadius)
    }

    /// Applies the wizard's shared horizontal gutter.
    func wizardHorizontalPadding() -> some View {
        padding(.horizontal, WizardLayout.horizontalPadding)
    }
}

/// A container view for wizard-style flows that displays step progress and manages navigation.
struct WizardStepContainer<Content: View>: View {
    let title: String?
    let currentStep: Int
    let totalSteps: Int
    let canCancel: Bool
    let disableInteractiveDismiss: Bool
    let lockModalWhenCantCancel: Bool
    let onCancel: () -> Void
    @ViewBuilder let content: () -> Content

    init(
        title: String? = nil,
        currentStep: Int,
        totalSteps: Int,
        canCancel: Bool,
        disableInteractiveDismiss: Bool = false,
        lockModalWhenCantCancel: Bool = false,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.canCancel = canCancel
        self.disableInteractiveDismiss = disableInteractiveDismiss
        self.lockModalWhenCantCancel = lockModalWhenCantCancel
        self.onCancel = onCancel
        self.content = content
    }

    var body: some View {
        if let title {
            steps.navigationBarTitle(title, displayMode: .inline)
        } else {
            steps
        }
    }

    private var steps: some View {
        VStack(spacing: 0) {
            WizardProgressBar(current: currentStep, total: totalSteps)

            ScrollView {
                VStack(spacing: WizardLayout.stepSpacing) {
                    content()
                }
                // Without an explicit full-width frame the step column collapses to
                // its content's ideal width and is centred by the ScrollView, so a
                // step whose views all size to fit ends up with wider (and different)
                // side margins than a step containing a full-width card.
                .frame(maxWidth: .infinity, alignment: .leading)
                .wizardHorizontalPadding()
                .padding(.vertical, WizardLayout.verticalPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(modalLocker)
        .navigationBarBackButtonHidden(!canCancel)
        .navigationBarItems(trailing: canCancel ? cancelButton : nil)
        .interactiveDismissDisabled(disableInteractiveDismiss || !canCancel)
    }

    @ViewBuilder private var modalLocker: some View {
        if lockModalWhenCantCancel {
            ModalInPresentationSetter(isModalInPresentation: !canCancel)
        }
    }

    private var cancelButton: some View {
        Button(String(localized: "Cancel", comment: "Cancel button")) {
            onCancel()
        }
    }
}

#Preview("Step 1") {
    NavigationView {
        WizardStepContainer(
            title: "Change Cartridge",
            currentStep: 1,
            totalSteps: 7,
            canCancel: true,
            onCancel: {}
        ) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Step Content")
                    .font(.title)
                Text("This is where the step content would go")
            }
        }
    }
}

#Preview("Step 4 - Cannot Cancel") {
    NavigationView {
        WizardStepContainer(
            title: "Fill Tubing",
            currentStep: 4,
            totalSteps: 5,
            canCancel: false,
            onCancel: {}
        ) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Processing...")
                    .font(.title)
                ProgressView()
            }
        }
    }
}
