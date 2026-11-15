import LoopKitUI
import SwiftUI

struct TandemKitSetupCompleteView: View {
    @ObservedObject var viewModel: TandemKitSetupCompleteViewModel
    var finish: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading) {
            List {
                Section(header: SectionHeader(label: viewModel.header)) {
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

            if viewModel.isFinished {
                Text(viewModel.stepMessage)
                    .padding(.all)

                ContinueButton(
                    text: Text("Finish", comment: "Text for finish button")
                ) {
                    finish?()
                }
                .padding(.horizontal)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.stepMessage)
                    ProgressView(value: viewModel.progress)
                        .animation(.default, value: viewModel.progress)
                    HStack {
                        Text(String(localized: "Keep the pump near your phone.", comment: "Setup caption while setup writes to the pump and reads it"))
                        Spacer()
                        Text(viewModel.progress, format: .percent.precision(.fractionLength(0)))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.all)
            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarHidden(false)
        .navigationBarBackButtonHidden(true)
        // A flow dismissed while it still owns the manager runs abandonSetup, dropping the pump link mid-setup.
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
