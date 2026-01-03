import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitSettingsView: View {
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.guidanceColors) private var guidanceColors
    @StateObject var viewModel: TandemKitSettingsViewModel

    var removePumpManagerActionSheet: ActionSheet {
        ActionSheet(
            title: Text(LocalizedString("Remove Pump", comment: "Title for Tandem PumpManager deletion action sheet.")),
            message: Text(LocalizedString(
                "Are you sure you want to remove the pump from Trio? You will need to re-pair the device.",
                comment: "Message for Tandem PumpManager deletion action sheet"
            )),
            buttons: [
                .destructive(Text(LocalizedString(
                    "Delete pump",
                    comment: "Button text to confirm Tandem PumpManager deletion"
                ))) {
                    viewModel.removePump()
                },
                .cancel()
            ]
        )
    }

    var debugDetailsPopover: some View {
        List {
            Section(header: SectionHeader(label: LocalizedString("State", comment: "Debug state header"))) {
                Text("Basal Icon: \(String(describing: viewModel.basalStatusIcon))").font(.system(size: 12))
                Text("Bolus Icon: \(String(describing: viewModel.bolusStatusIcon))").font(.system(size: 12))
                Text("CGM Alert Icon: \(String(describing: viewModel.cgmAlertIcon))").font(.system(size: 12))
                Text("ControlIQ Enabled: \(viewModel.controlIQEnabled ? "Yes" : "No")").font(.system(size: 12))
                Text("ControlIQ Mode: \(String(describing: viewModel.controlIQUserMode))").font(.system(size: 12))
                Text("Temp Rate Active: \(viewModel.tempRateActive ? "Yes" : "No")").font(.system(size: 12))
                if viewModel.tempRateActive {
                    Text("Temp Rate: \(viewModel.tempRatePercentage ?? 0)% for \(viewModel.tempRateDuration ?? 0)s").font(.system(size: 12))
                }
                Text("Current Basal Rate: \(viewModel.currentBasalRateForDisplay)").font(.system(size: 12))
            }

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
                if let suspendResumeText = viewModel.suspendResumeText {
                    Button(action: {
                        viewModel.suspendResumeButtonPressed()
                    }) {
                        HStack {
                            Text(suspendResumeText)
                            Spacer()
                            if viewModel.isUpdatingPumpState {
                                ActivityIndicator(isAnimating: .constant(true), style: .medium)
                            }
                        }
                    }
                    .disabled(viewModel.isUpdatingPumpState)
                } else {
                    Button(action: {}) {
                        HStack {
                            Text("Insulin delivery status unknown")
                        }
                    }.disabled(true)
                }

                if viewModel.tempRateActive {
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
                "Notifications",
                comment: "The title of the notifications section in TandemKit settings"
            ))) {
                NavigationLink(destination: TandemKitNotificationsView(
                    viewModel: viewModel.createNotificationsViewModel()
                )) {
                    HStack {
                        Text(LocalizedString("View Notifications", comment: "Label for viewing notifications"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        if viewModel.notificationCount > 0 {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 24, height: 24)
                                Text("\(viewModel.notificationCount)")
                                    .foregroundColor(.white)
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                    }
                }

                Toggle(isOn: Binding(
                    get: { viewModel.autoAcknowledgeBasalAlerts },
                    set: { viewModel.setAutoAcknowledgeBasalAlerts($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedString(
                            "Auto-Acknowledge Basal Alerts",
                            comment: "Label for auto-acknowledge basal alerts toggle"
                        ))
                        Text(LocalizedString(
                            "Automatically dismiss min/max basal rate alerts during looping",
                            comment: "Description for auto-acknowledge basal alerts toggle"
                        ))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: SectionHeader(label: LocalizedString(
                "CGM Configuration",
                comment: "The title of the CGM configuration section in TandemKit settings"
            ))) {
                NavigationLink(destination: TandemKitCGMSettingsView(
                    viewModel: viewModel.createCGMSettingsViewModel()
                )) {
                    Text(LocalizedString("CGM Settings", comment: "Label for CGM settings"))
                        .foregroundColor(Color.primary)
                }
            }

            Section(header: SectionHeader(label: LocalizedString(
                "Pump Status",
                comment: "The title of the pump status section in TandemKit settings"
            ))) {
                HStack {
                    Text(LocalizedString("Control-IQ", comment: "Text for Control-IQ status"))
                        .foregroundColor(Color.primary)
                    Spacer()
                    Text(viewModel.controlIQEnabled ? "Enabled" : "Disabled")
                        .foregroundColor(.secondary)
                }

                if let mode = viewModel.controlIQUserMode {
                    HStack {
                        Text(LocalizedString("User mode", comment: "Text for user mode"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(userModeText(mode.rawValue))
                            .foregroundColor(.secondary)
                    }
                }

                if viewModel.tempRateActive,
                   let percentage = viewModel.tempRatePercentage,
                   let duration = viewModel.tempRateDuration {
                    HStack {
                        Text(LocalizedString("Temp rate", comment: "Text for temp rate"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text("\(percentage)% (\(formatDuration(duration)))")
                            .foregroundColor(.secondary)
                    }
                }

                Button(action: {
                    viewModel.showingDebugDetails = true
                }) {
                    Text(LocalizedString("View Debug Status", comment: "Label for button to view debug status of the pump"))
                }
                .popover(isPresented: $viewModel.showingDebugDetails) {
                    debugDetailsPopover
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
                "ControlIQ Settings",
                comment: "The title of the ControlIQ settings section in TandemKit settings"
            ))) {
                Button(action: {
                    viewModel.toggleControlIQMode()
                }) {
                    HStack {
                        Text(viewModel.controlIqModeText)
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
                .disabled(viewModel.isUpdatingPumpState || !isControlIQClosedLoopEnabled)

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
                .disabled(viewModel.isUpdatingPumpState || !isControlIQClosedLoopEnabled)
            }

            Section(header: SectionHeader(label: LocalizedString(
                "Pump Information",
                comment: "The title of the pump information section in TandemKit settings"
            ))) {
                if let basal = viewModel.basalStatusIcon {
                    HStack {
                        Text(LocalizedString("Basal status", comment: "Text for basal status"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(basalStatusText(basal))
                            .foregroundColor(.secondary)
                    }
                }

                if let bolus = viewModel.bolusStatusIcon {
                    HStack {
                        Text(LocalizedString("Bolus status", comment: "Text for bolus status"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(bolusStatusText(bolus))
                            .foregroundColor(.secondary)
                    }
                }

                if let cgm = viewModel.cgmAlertIcon {
                    HStack {
                        Text(LocalizedString("CGM status", comment: "Text for CGM status"))
                            .foregroundColor(Color.primary)
                        Spacer()
                        Text(cgmStatusText(cgm))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Button(action: {
                    viewModel.showingDeleteConfirmation = true
                }) {
                    Text(LocalizedString("Delete Pump", comment: "Label for PumpManager deletion button"))
                        .foregroundColor(guidanceColors.critical)
                }
                .actionSheet(isPresented: $viewModel.showingDeleteConfirmation) {
                    removePumpManagerActionSheet
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarItems(trailing: doneButton)
        .navigationBarTitle("Tandem pump")
        .onAppear {
            viewModel.refreshNotificationCount()
        }
    }

    private var doneButton: some View {
        Button("Done", action: {
            dismiss()
        })
    }

    var reservoirStatus: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading) {
                Text(LocalizedString("Insulin Remaining", comment: "Header for insulin remaining"))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                if let unitsText = viewModel.reservoirUnitsText {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(unitsText)
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
                
                // fixed cartridge size for Mobi
                ProgressBar(value: (viewModel.reservoirValue?.unitVolume ?? 0), total: 200)
                    .frame(maxWidth: 128)
                    .frame(height: 12)
            }
        }
    }

    var deliveryStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(deliverySectionTitle)
                .foregroundColor(Color(UIColor.secondaryLabel))
            if viewModel.isUpdatingPumpState {
                HStack(alignment: .center) {
                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                    Text(LocalizedString("Updating...", comment: "Text shown when updating pump state"))
                        .fontWeight(.bold)
                        .fixedSize()
                }
            } else if viewModel.isSuspended == true {
                HStack(alignment: .center) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 34))
                        .fixedSize()
                        .foregroundColor(guidanceColors.warning)
                    Text(LocalizedString("Insulin\nSuspended", comment: "Text shown when insulin suspended"))
                        .fontWeight(.bold)
                        .fixedSize()
                }
            } else if viewModel.isSuspended == false {
                HStack(alignment: .center) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 34))
                        .fixedSize()
                        .foregroundColor(.accentColor)
                    if viewModel.currentBasalRate != nil {
                        VStack(alignment: .center) {
                            Text(viewModel.currentBasalRateForDisplay)
                                .fontWeight(.bold)
                                .font(.system(size: 24))
                            if viewModel.tempRateActive,
                               let percentage = viewModel.tempRatePercentage,
                               let duration = viewModel.tempRateDuration {
                                Text("\(percentage)% (\(formatDuration(duration)))")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16))
                            } else {
                                Text("No Temp Rate")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16))

                            }
                        }
                    } else {
                        VStack(alignment: .center) {
                            Text(LocalizedString("Unknown", comment: "Text shown when insulin active"))
                                .fontWeight(.bold)
                                .fixedSize()
                            Text("No Temp Rate")
                                .foregroundColor(.secondary)
                                .font(.system(size: 16))
                        }
                        
                    }
                }
            } else {
                HStack(alignment: .center) {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.system(size: 34))
                        .fixedSize()
                        .foregroundColor(.accentColor)
                    Text(LocalizedString("Unknown", comment: "Text shown when insulin status unknown"))
                        .fontWeight(.bold)
                        .fixedSize()
                }
            }
        }
    }

    var deliverySectionTitle: String {
        if viewModel.isSuspended == true {
            return LocalizedString("Insulin Delivery", comment: "Title of insulin delivery section")
        } else if viewModel.tempRateActive {
            return LocalizedString("Temp Rate", comment: "Title for temp rate")
        } else {
            return LocalizedString("Insulin Delivery", comment: "Title of insulin delivery section")
        }
    }

    // TODO(jwoglom): replace with consts from TandemCore
    private func userModeText(_ mode: Int) -> String {
        switch mode {
        case 0,
             1:
            return "Standard"
        case 2:
            return "Sleep"
        case 3:
            return "Exercise"
        default:
            return "Unknown"
        }
    }

    private func basalStatusText(_ status: TandemPumpManagerState.HomeScreenBasalStatus) -> String {
        switch status {
        case .active:
            return "Active"
        case .tempRate:
            return "Temp rate"
        case .suspended:
            return "Suspended"
        }
    }

    private func bolusStatusText(_ status: TandemPumpManagerState.HomeScreenBolusStatus) -> String {
        switch status {
        case .none:
            return "None"
        case .bolus:
            return "In progress"
        }
    }

    private func cgmStatusText(_ status: TandemPumpManagerState.HomeScreenCGMAlert) -> String {
        switch status {
        case .noError:
            return "OK"
        case .low:
            return "Low"
        case .high:
            return "High"
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
    
    private var isControlIQClosedLoopEnabled: Bool {
        return viewModel.controlIQEnabled
    }
}

private extension TandemKitSettingsViewModel {
    static var previewData: TandemKitSettingsViewModel {
        // TODO: Create mock TandemPumpManager with populated state for preview
        let viewModel = PreviewTandemKitSettingsViewModel(nextStep: {})
        viewModel.reservoirValue = SimpleReservoirValue(startDate: Date(), unitVolume: 180)
        return viewModel
    }

    static var previewDataInProgress: TandemKitSettingsViewModel {
        let viewModel = PreviewTandemKitSettingsViewModel(nextStep: {})
        viewModel.reservoirValue = SimpleReservoirValue(startDate: Date(), unitVolume: 180)
        viewModel.isUpdatingPumpState = true
        return viewModel
    }
}

private final class PreviewTandemKitSettingsViewModel: TandemKitSettingsViewModel {
    override func refreshPumpStatus() {
        // Disable background refresh for previews so mocked data stays visible
    }
}

#Preview("Overview") {
    NavigationView {
        TandemKitSettingsView(viewModel: .previewData)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

#Preview("In Progress") {
    NavigationView {
        TandemKitSettingsView(viewModel: .previewDataInProgress)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

