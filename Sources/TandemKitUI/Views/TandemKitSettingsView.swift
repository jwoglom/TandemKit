import LoopKitUI
import SwiftUI

struct TandemKitSettingsView: View {
    @Environment(\.dismissAction) private var dismiss
    @ObservedObject var viewModel: TandemKitSettingsViewModel

    var body: some View {
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
            }

            Section(header: SectionHeader(label: LocalizedString(
                "Pump information",
                comment: "The title of the pump information section in TandemKit settings"
            ))) {
                Button(action: {
                    viewModel.timeSinceReset = viewModel.sendMessage(message: TimeSinceResetRequest()) as! TimeSinceResetResponse?
                }) {
                    HStack {
                        Text("TimeSinceReset: \(viewModel.timeSinceReset)")
                        Spacer()
                    }
                }
                Spacer()

                Button(action: {
                    viewModel.mirrorDetail = viewModel
                        .sendMessage(message: HomeScreenMirrorRequest()) as! HomeScreenMirrorResponse?
                }) {
                    HStack {
                        Text("\(String(describing: viewModel.mirrorDetail))")
                        Spacer()
                    }
                }
                Spacer()

                Button(action: {
                    print("triggering ResumePumpingRequest")
                    viewModel.sendMessage(message: ResumePumpingRequest())
                }) {
                    HStack {
                        Text("ResumePumpingRequest")
                        Spacer()
                    }
                }
                Spacer()

                Button(action: {
                    print("triggering SuspendPumpingRequest")
                    viewModel.sendMessage(message: SuspendPumpingRequest())
                }) {
                    HStack {
                        Text("SuspendPumpingRequest")
                        Spacer()
                    }
                }
                Spacer()

                Button(action: {
                    print("triggering TempRate")
                    viewModel.sendMessage(message: SetTempRateRequest(minutes: 5, percent: 10))
                }) {
                    HStack {
                        Text("TempRate(5 minutes, 10 percent)")
                        Spacer()
                    }
                }
            }

            Section(header: SectionHeader(label: LocalizedString(
                "Debug",
                comment: "The title of the debug section in TandemKit settings"
            ))) {
                VStack {
                    Button(action: {}) {
                        HStack {
                            Text("Peripheral UUID: \(viewModel.pumpState?.peripheralUuid ?? "No peripheral UUID")")
                            Spacer()
                        }
                    }
                    Button(action: {}) {
                        HStack {
                            Text(
                                "Derived secret: \(viewModel.pumpState?.derivedSecret?.base64EncodedString() ?? "No derived secret")"
                            )
                            Spacer()
                        }
                    }
                    Button(action: {}) {
                        HStack {
                            Text("Server nonce: \(viewModel.pumpState?.serverNonce?.base64EncodedString() ?? "Server nonce")")
                            Spacer()
                        }
                    }
                    Button(action: {}) {
                        HStack {
                            Text("PumpState Valid: \(String(describing: viewModel.pumpState?.valid))")
                            Spacer()
                        }
                    }
                }
            }

            Section(header: SectionHeader(label: LocalizedString(
                "Configuration",
                comment: "The title of the configuration section in TandemKit settings"
            ))) {
                Spacer()
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarItems(trailing: doneButton)
        .navigationBarTitle("Tandem pump")
    }

    private var doneButton: some View {
        Button("Done", action: {
            dismiss()
        })
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
