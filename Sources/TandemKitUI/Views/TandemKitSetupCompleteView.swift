import LoopKitUI
import SwiftUI

struct TandemKitSetupCompleteView: View {
    var finish: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading) {
            title
            VStack(alignment: .leading, spacing: 20) {
                Text(LocalizedString(
                    "Your Tandem pump is ready to be used!",
                    comment: "Tandem setup complete message"
                ))
                    .padding(.horizontal)

                Spacer()

                Text(LocalizedString(
                    "You can now use your Tandem pump with this app. Make sure to keep your pump nearby and within Bluetooth range.",
                    comment: "Tandem setup complete instructions"
                ))
                    .padding(.horizontal)
            }

            Spacer()

            ContinueButton(
                text: LocalizedString("Finish", comment: "Text for finish button"),
                action: { finish?() }
            )
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
    }

    @ViewBuilder private var title: some View {
        Text(LocalizedString("Setup Complete", comment: "Title for setup complete"))
            .font(.title)
            .bold()
            .padding(.horizontal)

        Divider()
            .padding(.bottom)
    }
}

#Preview {
    TandemKitSetupCompleteView(finish: {})
}
