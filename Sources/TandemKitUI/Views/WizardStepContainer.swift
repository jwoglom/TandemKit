import SwiftUI

/// A container view for wizard-style flows that displays step progress and manages navigation.
struct WizardStepContainer<Content: View>: View {
    let title: String
    let currentStep: Int
    let totalSteps: Int
    let canCancel: Bool
    let onCancel: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            WizardProgressBar(current: currentStep, total: totalSteps)

            ScrollView {
                VStack(spacing: 20) {
                    content()
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationBarTitle(title, displayMode: .inline)
        .navigationBarBackButtonHidden(!canCancel)
        .navigationBarItems(trailing: canCancel ? cancelButton : nil)
        .interactiveDismissDisabled(!canCancel)
    }

    private var cancelButton: some View {
        Button(LocalizedString("Cancel", comment: "Cancel button")) {
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
