import LoopKit
import LoopKitUI
import SwiftUI

struct TandemKitSetupView: View {
    @Environment(\.dismissAction) private var dismiss

    let nextAction: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            List {
                Section {
                    HStack {
                        Spacer()
                        Image(imageName: "tandem_mobi")
                            .resizable()
                            .scaledToFit()
                            .padding(.horizontal)
                            .frame(height: 200)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(LocalizedString(
                            "You will start by setting up your insulin type and pump settings before pairing your pump.",
                            comment: "welcome to TandemKit1"
                        ))
                        Text(LocalizedString(
                            "Make sure you have your Tandem Mobi, charging pad and PIN ready for getting started",
                            comment: "welcome to TandemKit2"
                        ))
                    }
                }
            }

            Spacer()

            ContinueButton(action: nextAction)
                .padding(.horizontal)
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
        .navigationBarTitle("Tandem Mobi")
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
