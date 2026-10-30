import LoopKitUI
import SwiftUI

struct TandemKitLoadHistoryView: View {
    @ObservedObject var viewModel: TandemKitLoadHistoryViewModel

    var body: some View {
        VStack(alignment: .leading) {
            List {
                Section {
                    HStack {
                        Spacer()
                        Image(imageName: "tandem_mobi")
                            .resizable()
                            .rotationEffect(.degrees(90))
                            .scaledToFit()
                            .padding(.horizontal)
                            .frame(height: 160)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(viewModel.introduction)
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.readings, id: \.self) { reading in
                                VStack(alignment: .leading, spacing: 2) {
                                    if let label = reading.label {
                                        Text(label).bold()
                                    }
                                    Text(reading.value)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 4)
                        Text(viewModel.question)
                    }
                }
            }

            VStack {
                ContinueButton(
                    text: Text(String(localized: "Do Not Load", comment: "Setup button that skips loading the pump's history")),
                    buttonStyle: .secondary
                ) {
                    viewModel.doNotLoad()
                }
                ContinueButton(text: Text(viewModel.loadButtonTitle)) {
                    viewModel.load()
                }
            }
            .padding(.horizontal)
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
        .navigationBarBackButtonHidden(true)
        .alert(
            String(localized: "Pump History Not Loaded", comment: "Title of the setup alert after the user chose not to load the pump's history"),
            isPresented: $viewModel.isShowingNotLoadedAlert,
            actions: {
                Button(String(localized: "OK", comment: "OK button")) {
                    viewModel.notLoadedAcknowledged()
                }
            },
            message: { Text(viewModel.notLoadedMessage) }
        )
    }
}
