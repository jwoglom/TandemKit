import SwiftUI

/// A progress bar that shows the user's progress through a step-by-step wizard flow.
struct WizardProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step \(current) of \(total)", comment: "Wizard progress above the step (1: current step, 2: total steps)")
                .font(.caption)
                .foregroundColor(.secondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                        .cornerRadius(2)

                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * CGFloat(current) / CGFloat(total), height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)
        }
        .wizardHorizontalPadding()
        .padding(.vertical, WizardLayout.verticalPadding)
    }
}

#Preview("Step 1 of 7") {
    WizardProgressBar(current: 1, total: 7)
}

#Preview("Step 4 of 7") {
    WizardProgressBar(current: 4, total: 7)
}

#Preview("Step 7 of 7") {
    WizardProgressBar(current: 7, total: 7)
}
