import LoopKitUI
import SwiftUI

struct TandemKitSetupCompleteView: View {
    @ObservedObject var viewModel: TandemKitSetupCompleteViewModel
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
                }
            }

            Spacer()

            if viewModel.isLoadingHistory {
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.loadingMessage)
                    ProgressView(value: viewModel.progress)
                    Text(viewModel.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

            Text(String(format: String(
                localized:
                "You can now use your Tandem pump with %@. Make sure to keep your pump nearby and within Bluetooth range.",
                comment: "Tandem setup complete instructions"
            ), HostApp.current.appName))
                .padding(.all)

            if viewModel.isFinished {
                ContinueButton(
                    text: Text("Finish", comment: "Text for finish button")
                ) {
                    finish?()
                }
                .padding(.horizontal)
            } else {
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
        .preventsSheetDismissal(!viewModel.isFinished)
        .onAppear {
            viewModel.start()
        }
        .alert(
            String(localized: "Control-IQ Is On", comment: "Title of the setup prompt when the paired pump is running Control-IQ"),
            isPresented: $viewModel.isPromptingControlIQOff,
            actions: {
                Button(String(localized: "OK", comment: "OK button")) {
                    viewModel.turnOffControlIQ()
                }
            },
            message: { Text(viewModel.controlIQOffPromptMessage) }
        )
        .alert(
            String(localized: "Control-IQ Not Turned Off", comment: "Title of the setup error when turning Control-IQ off failed"),
            isPresented: $viewModel.isControlIQOffError,
            presenting: $viewModel.controlIQOffErrorMessage,
            actions: { _ in
                Button(String(localized: "Try Again", comment: "Retry button")) {
                    viewModel.turnOffControlIQ()
                }
            },
            message: { detail in Text(detail.wrappedValue ?? "") }
        )
        .alert(
            String(localized: "Delivery Records Processed", comment: "Title of the setup alert after the pump's history loaded"),
            isPresented: $viewModel.isShowingLoadSummary,
            presenting: $viewModel.loadSummaryMessage,
            actions: { _ in
                Button(String(localized: "OK", comment: "OK button")) {
                    viewModel.loadSummaryAcknowledged()
                }
            },
            message: { detail in Text(detail.wrappedValue ?? "") }
        )
        .alert(
            String(localized: "Pump History Not Loaded Yet", comment: "Title of the setup error when the pump's history could not be read"),
            isPresented: $viewModel.isShowingLoadFailedAlert,
            presenting: $viewModel.loadFailedMessage,
            actions: { _ in
                Button(String(localized: "Try Again", comment: "Retry button")) {
                    viewModel.loadHistory()
                }
            },
            message: { detail in Text(detail.wrappedValue ?? "") }
        )
        .alert(
            String(localized: "Pump Settings Not Saved", comment: "Onboarding settings write failure"),
            isPresented: $viewModel.isSettingsError,
            presenting: $viewModel.settingsErrorMessage,
            actions: { _ in
                Button(String(localized: "Try Again", comment: "Retry button")) {
                    viewModel.applyOnboardingSettings()
                }
                Button(String(localized: "Continue Anyway", comment: "Continue button"), role: .destructive) {
                    viewModel.continueWithoutOnboardingSettings()
                }
            },
            message: { detail in Text(detail.wrappedValue ?? "") }
        )
    }
}
