import LoopKitUI
import SwiftUI

struct TandemKitSetupCompleteView: View {
    var finish: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading) {
            title
            VStack(alignment: .leading, spacing: 20) {
                Text(LocalizedString(
                    "Your Tandem pump is connected!",
                    comment: "Tandem setup complete message"
                ))
                    .padding(.horizontal)

                Spacer()

                HStack {
                    Spacer()
                    Image(imageName: "tandem_mobi")
                        .resizable()
                        .rotationEffect(.degrees(90))
                        .scaledToFit()
                        .padding(.horizontal)
                        .frame(height: 200)
                    Spacer()
                }

                Spacer()

                Text(String(format: LocalizedString(
                    "You can now use your Tandem pump with %@. Make sure to keep your pump nearby and within Bluetooth range.",
                    comment: "Tandem setup complete instructions"
                ), HostApp.current.appName))
                    .padding(.all)
            }

            Spacer()

            ContinueButton(
                text: LocalizedString("Finish", comment: "Text for finish button")
            ) {
                finish?()
            }
            .padding(.horizontal)
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
