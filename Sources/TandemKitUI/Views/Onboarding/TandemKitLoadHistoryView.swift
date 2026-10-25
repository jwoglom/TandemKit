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

                    switch viewModel.phase {
                    case .choosing:
                        VStack(alignment: .leading, spacing: 10) {
                            Text(viewModel.explanation)
                            Text(viewModel.guidance)
                        }
                    case .loading:
                        VStack(alignment: .leading, spacing: 10) {
                            Text(viewModel.loadingMessage)
                            ProgressView(value: viewModel.progress)
                            Text(viewModel.progress, format: .percent.precision(.fractionLength(0)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            switch viewModel.phase {
            case .choosing:
                VStack {
                    ContinueButton(text: Text(viewModel.loadButtonTitle)) {
                        viewModel.load()
                    }
                    ContinueButton(
                        text: Text(String(localized: "Do Not Load", comment: "Setup button that skips loading the pump's history")),
                        buttonStyle: .secondary
                    ) {
                        viewModel.doNotLoad()
                    }
                }
                .padding(.horizontal)
            case .loading:
                HStack {
                    Spacer()
                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                    Spacer()
                }
                .padding()
            }
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
        .alert(
            String(localized: "Pump History Not Loaded Yet", comment: "Title of the setup error when the pump's history could not be read"),
            isPresented: $viewModel.isShowingLoadFailedAlert,
            presenting: $viewModel.loadFailedMessage,
            actions: { _ in
                Button(String(localized: "Try Again", comment: "Retry button")) {
                    viewModel.load()
                }
            },
            message: { detail in Text(detail.wrappedValue ?? "") }
        )
    }
}
