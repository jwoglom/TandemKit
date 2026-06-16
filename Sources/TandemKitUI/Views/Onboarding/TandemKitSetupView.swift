import LoopKit
import LoopKitUI
import SwiftUI

struct TandemKitSetupView: View {
    @Environment(\.dismissAction) private var dismiss

    let nextAction: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            List {
                Section(header: SectionHeader(label: String(
                    localized: "Ready to connect your Tandem Mobi?",
                    comment: "Subtitle for TandemKitSetupView"
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "In the first step you will configure your insulin type and pump settings.",
                            comment: "welcome to TandemKit1"
                        )
                        Text(
                            "Before getting started, make sure to have the charging pad available.",
                            comment: "welcome to TandemKit2"
                        )
                    }
                }
            }

            ContinueButton(action: nextAction)
                .padding(.horizontal)
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(String(localized: "Cancel", comment: "Cancel button title"), action: {
                    self.dismiss()
                })
            }
        }
    }
}

#Preview {
    TandemKitSetupView(nextAction: {})
}
