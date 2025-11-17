import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitSettingsView: View {
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.guidanceColors) private var guidanceColors
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

                HStack(alignment: .top) {
                    deliveryStatus
                    Spacer()
                    reservoirStatus
                }
                .padding(.bottom, 5)
            }

            Section(header: SectionHeader(label: LocalizedString(
                "Actions",
                comment: "The title of the actions section in TandemKit settings"
            ))) {
                Button(action: {
                    viewModel.suspendResumeButtonPressed()
                }) {
                    HStack {
                        Text(viewModel.basalButtonText)
                        Spacer()
                        if viewModel.isUpdatingPumpState {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                        }
                    }
                }
                .disabled(viewModel.isUpdatingPumpState)

                Button(action: {
                    viewModel.toggleExerciseMode()
                }) {
                    HStack {
                        Text(viewModel.exerciseModeText)
                        Spacer()
                        if viewModel.isUpdatingPumpState {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                        }
                    }
                }
                .disabled(viewModel.isUpdatingPumpState)

                Button(action: {
                    viewModel.toggleSleepMode()
                }) {
                    HStack {
                        Text(viewModel.sleepModeText)
                        Spacer()
                        if viewModel.isUpdatingPumpState {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                        }
                    }
                }
                .disabled(viewModel.isUpdatingPumpState)

                if let tempRate = viewModel.tempRateStatus, tempRate.active {
                    Button(action: {
                        viewModel.stopTempRate()
                    }) {
                        HStack {
                            Text(LocalizedString("Stop temp rate", comment: "Tandem settings stop temp rate"))
                            Spacer()
                            if viewModel.isUpdatingPumpState {
                                ActivityIndicator(isAnimating: .constant(true), style: .medium)
                            }
                        }
                    }
                    .disabled(viewModel.isUpdatingPumpState)
                }

                Button(action: {
                    viewModel.refreshPumpStatus()
                }) {
                    HStack {
                        Text(LocalizedString("Refresh pump status", comment: "Tandem refresh pump"))
                        Spacer()
                    }
                }
            }

            Section(header: SectionHeader(label: LocalizedString(
                "Pump Status",
                comment: "The title of the pump status section in TandemKit settings"
            ))) {
                if let controlIQ = viewModel.controlIQInfo {
                    HStack {
                        Text(LocalizedString("Control-IQ", comment: "Text for Control-IQ status"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(controlIQ.closedLoopEnabled ? "Enabled" : "Disabled")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(LocalizedString("User mode", comment: "Text for user mode"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(userModeText(controlIQ.currentUserModeTypeRaw))
                            .foregroundColor(.secondary)
                    }
                }

                if let tempRate = viewModel.tempRateStatus, tempRate.active {
                    HStack {
                        Text(LocalizedString("Temp rate", comment: "Text for temp rate"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text("\(tempRate.percentage)% (\(formatDuration(tempRate.duration)))")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: SectionHeader(label: LocalizedString(
                "Cartridge Operations",
                comment: "The title of the cartridge operations section in TandemKit settings"
            ))) {
                NavigationLink(destination: TandemKitChangeCartridgeView(
                    viewModel: viewModel.createChangeCartridgeViewModel()
                )) {
                    Text(LocalizedString("Change Cartridge", comment: "Label for change cartridge"))
                        .foregroundColor(Color.primary)
                }

                NavigationLink(destination: TandemKitFillTubingView(
                    viewModel: viewModel.createFillTubingViewModel()
                )) {
                    Text(LocalizedString("Fill Tubing", comment: "Label for fill tubing"))
                        .foregroundColor(Color.primary)
                }

                NavigationLink(destination: TandemKitFillCannulaView(
                    viewModel: viewModel.createFillCannulaViewModel()
                )) {
                    Text(LocalizedString("Fill Cannula", comment: "Label for fill cannula"))
                        .foregroundColor(Color.primary)
                }
            }

            Section(header: SectionHeader(label: LocalizedString(
                "Pump Information",
                comment: "The title of the pump information section in TandemKit settings"
            ))) {
                if let mirror = viewModel.mirrorDetail {
                    HStack {
                        Text(LocalizedString("Basal status", comment: "Text for basal status"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(basalStatusText(mirror.basalStatusIconId))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(LocalizedString("Bolus status", comment: "Text for bolus status"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(bolusStatusText(mirror.bolusStatusIconId))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(LocalizedString("CGM status", comment: "Text for CGM status"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(cgmStatusText(mirror.cgmAlertIconId))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: SectionHeader(label: LocalizedString(
                "Debug",
                comment: "The title of the debug section in TandemKit settings"
            ))) {
                HStack {
                    Text("Peripheral UUID")
                        .foregroundColor(Color.primary)
                    Spacer()
                    Text(viewModel.pumpState?.peripheralUuid ?? "N/A")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Text("PumpState Valid")
                        .foregroundColor(Color.primary)
                    Spacer()
                    Text(String(describing: viewModel.pumpState?.valid ?? false))
                        .foregroundColor(.secondary)
                }
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

    var reservoirStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedString("Insulin Remaining", comment: "Header for insulin remaining"))
                .foregroundColor(Color(UIColor.secondaryLabel))
            if let insulin = viewModel.insulinStatus {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text("\(insulin.currentInsulinAmount / 100)")
                        .font(.system(size: 28))
                        .fontWeight(.heavy)
                        .fixedSize()
                    Text("U")
                        .foregroundColor(.secondary)
                }
            } else {
                Text("--")
                    .font(.system(size: 28))
                    .fontWeight(.heavy)
            }
        }
    }

    var deliveryStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(deliverySectionTitle)
                .foregroundColor(Color(UIColor.secondaryLabel))
            if viewModel.isSuspended {
                HStack(alignment: .center) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 34))
                        .fixedSize()
                        .foregroundColor(guidanceColors.warning)
                    Text(LocalizedString("Insulin\nSuspended", comment: "Text shown when insulin suspended"))
                        .fontWeight(.bold)
                        .fixedSize()
                }
            } else {
                HStack(alignment: .center) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 34))
                        .fixedSize()
                        .foregroundColor(.accentColor)
                    Text(LocalizedString("Active", comment: "Text shown when insulin active"))
                        .fontWeight(.bold)
                        .fixedSize()
                }
            }
        }
    }

    var deliverySectionTitle: String {
        if viewModel.isSuspended {
            return LocalizedString("Insulin Delivery", comment: "Title of insulin delivery section")
        } else if let tempRate = viewModel.tempRateStatus, tempRate.active {
            return LocalizedString("Temp Rate", comment: "Title for temp rate")
        } else {
            return LocalizedString("Insulin Delivery", comment: "Title of insulin delivery section")
        }
    }

    private func userModeText(_ mode: Int) -> String {
        switch mode {
        case 0, 1:
            return "Standard"
        case 2:
            return "Sleep"
        case 3:
            return "Exercise"
        default:
            return "Unknown"
        }
    }

    private func basalStatusText(_ iconId: Int) -> String {
        switch iconId {
        case 12:
            return "Suspended"
        case 13:
            return "Temp rate"
        default:
            return "Active"
        }
    }

    private func bolusStatusText(_ iconId: Int) -> String {
        switch iconId {
        case 0:
            return "None"
        case 11:
            return "In progress"
        default:
            return "Unknown"
        }
    }

    private func cgmStatusText(_ iconId: Int) -> String {
        switch iconId {
        case 0:
            return "OK"
        case 1:
            return "Alert"
        default:
            return "Unknown"
        }
    }

    private func formatDuration(_ seconds: UInt32) -> String {
        let minutes = Int(seconds) / 60
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }
}

#Preview {
    TandemKitSetupCompleteView(finish: {})
}
