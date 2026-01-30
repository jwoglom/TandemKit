import LoopKit
import LoopKitUI
import SwiftUI

struct TandemKitSetupView: View {
    @Environment(\.dismissAction) private var dismiss

    let nextAction: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            title
            List {
                Section {
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

                    VStack(alignment: .leading, spacing: 5) {
                        Spacer()
                        Text(LocalizedString(
                            "In the first step you will configure your insulin type and pump settings.",
                            comment: "welcome to TandemKit1"
                        ))
                        Spacer()
                        Text(LocalizedString(
                            "Before getting started, make sure to have the charging pad available.",
                            comment: "welcome to TandemKit2"
                        ))
                        Spacer()
                    }
                }
            }

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
        Text(LocalizedString("Ready to connect your Tandem Mobi?", comment: "Subtitle for TandemKitSetupView"))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)

        Divider()
    }
}

#Preview {
    TandemKitSetupView(nextAction: {})
}
