import LoopKitUI
import SwiftUI

struct TandemKitSetupCompleteView: View {
    var finish: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading) {
            List {
                Section(header: SectionHeader(label: String(
                    localized: "Your Tandem pump is connected!",
                    comment: "Tandem setup complete message"
                ))) {
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

                    Text(
                        "You can now use your Tandem pump with this app. Make sure to keep your pump nearby and within Bluetooth range.",
                        comment: "Tandem setup complete instructions"
                    )
                }
            }

            Spacer()

            Text(String(format: String(
                localized:
                "You can now use your Tandem pump with %@. Make sure to keep your pump nearby and within Bluetooth range.",
                comment: "Tandem setup complete instructions"
            ), HostApp.current.appName))
                .padding(.all)

            ContinueButton(
                text: Text("Finish", comment: "Text for finish button")
            ) {
                finish?()
            }
            .padding(.horizontal)
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
    }
}

#Preview {
    TandemKitSetupCompleteView(finish: {})
}
