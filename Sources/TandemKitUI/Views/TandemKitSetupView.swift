import LoopKit
import LoopKitUI
import SwiftUI

struct TandemKitSetupView: View {
    @Environment(\.dismissAction) private var dismiss

    let nextAction: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            title

            VStack(alignment: .leading, spacing: 20) {
                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    Text(LocalizedString("Before you begin:", comment: "Setup instructions header"))
                        .font(.headline)

                    Text(LocalizedString("• Ensure your pump is nearby", comment: "Setup instruction 1"))
                    Text(LocalizedString(
                        "• Ensure you have the Mobi wireless charger (or other Qi compatible wireless charger) plugged in",
                        comment: "Setup instruction 2"
                    ))
                    Text(LocalizedString("• Have your pump's pairing code ready", comment: "Setup instruction 3"))
                    Text(LocalizedString("• Make sure Bluetooth is enabled", comment: "Setup instruction 4"))
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.horizontal)

            ContinueButton(action: nextAction)
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(LocalizedString("Cancel", comment: "Cancel button title"), action: {
                    self.dismiss()
                })
            }
        }
    }

    @ViewBuilder private var title: some View {
        Text(LocalizedString("Tandem Pump Setup", comment: "Title for TandemKitSetupView"))
            .font(.largeTitle)
            .bold()
            .padding(.horizontal)
        Text(LocalizedString("Scan for your pump", comment: "Subtitle for TandemKitSetupView"))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)

        Divider()
    }
}

#Preview {
    TandemKitSetupView(nextAction: {})
}
