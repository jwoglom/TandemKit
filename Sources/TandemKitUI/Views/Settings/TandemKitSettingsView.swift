import LoopKitUI
import SwiftUI
import TandemCore

struct TandemKitSettingsView: View {
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.guidanceColors) private var guidanceColors

    @State var isSharePresented: Bool = false
    @StateObject var viewModel: TandemKitSettingsViewModel

    var removePumpManagerActionSheet: ActionSheet {
        ActionSheet(
            title: Text(LocalizedString("Remove Pump", comment: "Title for Tandem PumpManager deletion action sheet."))
                .font(.headline),
            message: Text(LocalizedString(
                "Are you sure you want to remove the pump from this app? You will need to re-pair the device to reconnect with it which will require access to the charging pad.",
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

    var syncPumpTime: ActionSheet {
        ActionSheet(
            title: Text(LocalizedString("Time Change Detected", comment: "Title for pod sync time action sheet.")),
            message: Text(LocalizedString(
                "The time on your pump is different from the current time. Do you want to update the time on your pump to the current time?",
                comment: "Message for pod sync time action sheet"
            )),
            buttons: [
                .default(Text(LocalizedString("Yes, Sync to Current Time", comment: "Button text to confirm pump time sync"))) {
                    self.viewModel.syncPumpTime()
                },
                .cancel(Text(LocalizedString("No, Keep Pump As Is", comment: "Button text to cancel pump time sync")))
            ]
        )
    }

    private func errorSheetView(for failure: CommandFailure) -> some View {
        let content: ErrorSheetContent
        switch failure {
        case .resume:
            content = ErrorSheetContent(
                title: LocalizedString(
                    "Could not resume insulin delivery",
                    comment: "Title for failure to resume insulin delivery"
                ),
                message: LocalizedString(
                    "The pump rejected starting insulin delivery. Check \"View Notifications\" to see the pump's current status and swipe away all active pump notifications. This may have occurred due to active pump notifications, invalid settings, empty cartridge, or not filling the tubing.",
                    comment: "Message for failed to resume insulin delivery"
                )
            )
        case .suspend:
            content = ErrorSheetContent(
                title: LocalizedString(
                    "Could not suspend insulin delivery",
                    comment: "Title for failure to suspend insulin delivery"
                ),
                message: LocalizedString(
                    "The pump rejected suspending insulin delivery. Check \"View Notifications\" to see the pump's current status and swipe away all active pump notifications. This may have occurred due to an active bolus. To urgently suspend insulin delivery, detach from your site.",
                    comment: "Message for failed to suspend insulin delivery"
                )
            )
        case .controlIQ:
            content = ErrorSheetContent(
                title: LocalizedString(
                    "Could not change Control-IQ setting",
                    comment: "Title for failure to toggle Control-IQ"
                ),
                message: LocalizedString(
                    "The pump rejected the Control-IQ change. Check \"View Notifications\" to see the pump's current status.",
                    comment: "Message for failed to toggle Control-IQ"
                )
            )
        case .exerciseMode:
            content = ErrorSheetContent(
                title: LocalizedString(
                    "Could not change exercise mode",
                    comment: "Title for failure to toggle exercise mode"
                ),
                message: LocalizedString(
                    "The pump rejected the exercise mode change. Check \"View Notifications\" to see the pump's current status.",
                    comment: "Message for failed to toggle exercise mode"
                )
            )
        case .sleepMode:
            content = ErrorSheetContent(
                title: LocalizedString(
                    "Could not change sleep mode",
                    comment: "Title for failure to toggle sleep mode"
                ),
                message: LocalizedString(
                    "The pump rejected the sleep mode change. Check \"View Notifications\" to see the pump's current status.",
                    comment: "Message for failed to toggle sleep mode"
                )
            )
        case .stopTempRate:
            content = ErrorSheetContent(
                title: LocalizedString(
                    "Could not stop temp rate",
                    comment: "Title for failure to stop temp rate"
                ),
                message: LocalizedString(
                    "The pump rejected stopping the temp rate. Check \"View Notifications\" to see the pump's current status.",
                    comment: "Message for failed to stop temp rate"
                )
            )
        }
        return ErrorSheetView(content: content, tint: guidanceColors.critical)
    }

    var body: some View {
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

                HStack(alignment: .top) {
                    deliveryStatus
                    Spacer()
                    reservoirStatus
                }
                .padding(.bottom, 5)

                if viewModel.showPumpTimeSyncWarning {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedString("Time Change Detected", comment: "title for time change detected notice"))
                            .font(Font.subheadline.weight(.bold))
                        Text(LocalizedString(
                            "The time on your pump is different from the current time. Your pump’s time controls your scheduled therapy settings. Scroll down to Pump Time row to review the time difference and configure your pump.",
                            comment: "description for time change detected notice"
                        ))
                            .font(Font.footnote.weight(.semibold))
                    }.padding(.vertical, 8)
                }
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
                    .disabled(viewModel.isUpdatingPumpState || viewModel.isUpdatingTime)
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
                    .disabled(viewModel.isUpdatingPumpState || viewModel.isUpdatingTime)
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
                            .foregroundColor(.primary)
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
                "Pump Status",
                comment: "The title of the pump status section in TandemKit settings"
            ))) {
                HStack {
                    Text(LocalizedString("Control-IQ", comment: "Text for Control-IQ status"))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(viewModel.controlIQEnabled ? "Enabled" : "Disabled")
                        .foregroundColor(.secondary)
                }

                if let mode = viewModel.controlIQUserMode {
                    HStack {
                        Text(LocalizedString("User mode", comment: "Text for user mode"))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(userModeText(mode.rawValue))
                            .foregroundColor(.secondary)
                    }
                }

                if viewModel.tempRateActive,
                   let percentage = viewModel.tempRatePercentage,
                   let duration = viewModel.tempRateDuration
                {
                    HStack {
                        Text(LocalizedString("Temp rate", comment: "Text for temp rate"))
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(percentage)% (\(formatDuration(duration)))")
                            .foregroundColor(.secondary)
                    }
                }

                if let battery = viewModel.batteryPercentage {
                    HStack {
                        Text(LocalizedString("Battery percentage", comment: "Text for battery"))
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(battery)")
                            .foregroundColor(.secondary)
                    }
                }

                Button(action: {
                    viewModel.openInsulinType()
                }) {
                    Text(LocalizedString("Insulin type", comment: "Label for button to view insulin type of pump"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: UIFont.systemFontSize, weight: .medium))
                        .opacity(0.35)
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.openSoundSettings()
                }) {
                    Text(LocalizedString("Sound settings", comment: "Label for button to view sound settings of pump"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: UIFont.systemFontSize, weight: .medium))
                        .opacity(0.35)
                }
                .buttonStyle(.plain)
            }

            Section(header: SectionHeader(label: LocalizedString(
                "Cartridge Operations",
                comment: "The title of the cartridge operations section in TandemKit settings"
            ))) {
                NavigationLink(destination: TandemKitChangeCartridgeView(
                    viewModel: viewModel.createChangeCartridgeViewModel()
                )) {
                    Text(LocalizedString("Change Cartridge", comment: "Label for change cartridge"))
                        .foregroundColor(.primary)
                }

                NavigationLink(destination: TandemKitFillTubingView(
                    viewModel: viewModel.createFillTubingViewModel()
                )) {
                    Text(LocalizedString("Fill Tubing", comment: "Label for fill tubing"))
                        .foregroundColor(.primary)
                }

                NavigationLink(destination: TandemKitFillCannulaView(
                    viewModel: viewModel.createFillCannulaViewModel()
                )) {
                    Text(LocalizedString("Fill Cannula", comment: "Label for fill cannula"))
                        .foregroundColor(.primary)
                }
            }

            Section(header: SectionHeader(label: LocalizedString(
                "Pump time",
                comment: "The title of the pump time section in DanaKit settings"
            ))) {
                HStack {
                    Text(LocalizedString("Pump time", comment: "Text for pump time"))
                        .foregroundColor(Color.primary)
                    Spacer()
                    if viewModel.showPumpTimeSyncWarning {
                        Image(systemName: "clock.fill")
                            .foregroundColor(guidanceColors.warning)
                    }
                    Text(viewModel.currentPumpTime)
                        .foregroundColor(viewModel.showPumpTimeSyncWarning ? guidanceColors.warning : .secondary)
                }
                HStack {
                    Text(LocalizedString("Checked at", comment: "Text for pump time synced at"))
                        .foregroundColor(Color.primary)
                    Spacer()
                    Text(viewModel.pumpTimeCheckedAt)
                        .foregroundColor(.secondary)
                }

                Button(action: {
                    viewModel.showingTimeSyncConfirmation = true
                }) {
                    Text(LocalizedString("Manually sync Pump time", comment: "Label for syncing the time on the pump"))
                        .foregroundColor(.accentColor)
                }
                .disabled(viewModel.isUpdatingTime)
                .actionSheet(isPresented: $viewModel.showingTimeSyncConfirmation) {
                    syncPumpTime
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { viewModel.useSilentMode },
                    set: { viewModel.setSilentMode($0) }
                )) {
                    Text(LocalizedString("Silent Tones", comment: "Label for silent tones"))
                }
                Button(LocalizedString("Share Tandem pump logs", comment: "TandemKit share logs")) {
                    self.isSharePresented = true
                }
                .sheet(isPresented: $isSharePresented, onDismiss: {}, content: {
                    ActivityViewController(activityItems: viewModel.getLogs())
                })
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
        .sheet(item: $viewModel.commandFailure) { failure in
            errorSheetView(for: failure)
        }
        .navigationBarItems(trailing: doneButton)
        .navigationBarTitle(navigationTitle)
    }

    private var navigationTitle: String {
        guard let pumpState = viewModel.pumpState, pumpState.pumpModel == .MOBI else {
            return "Tandem pump"
        }

        guard let serial = pumpState.pumpSerial else {
            return "Tandem pump"
        }

        let serialString = String(serial)
        let serialSuffix = String(serialString.suffix(3))
        return serialSuffix.isEmpty ? "Tandem pump" : "Tandem Mobi \(serialSuffix)"
    }

    private var doneButton: some View {
        Button("Done", action: {
            dismiss()
        })
    }

    var reservoirStatus: some View {
        HStack(alignment: .center) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(LocalizedString("Insulin Remaining", comment: "Header for insulin remaining"))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                VStack(alignment: .trailing, spacing: 4) {
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
                    ProgressBar(value: viewModel.reservoirValue?.unitVolume ?? 0, total: 200)
                        .frame(maxWidth: 128)
                        .frame(height: 12)
                }
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
                    VStack(alignment: .center) {
                        if let percentage = viewModel.tempRatePercentage,
                           let rate = viewModel.tempRateAbsolute,
                           let duration = viewModel.tempRateDuration
                        {
                            Text(String(format: "%.2f U/hr", rate))
                                .fontWeight(.bold)
                                .font(.system(size: 24))
                            Text("\(percentage)% (for \(formatDuration(duration)))")
                                .foregroundColor(.secondary)
                                .font(.system(size: 16))
                        } else {
                            Text(viewModel.currentBasalRateForDisplay)
                                .fontWeight(.bold)
                                .font(.system(size: 24))
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

    private func formatDuration(_ seconds: Double) -> String {
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
        viewModel.controlIQEnabled
    }
}

private extension TandemKitSettingsViewModel {
    static var previewData: TandemKitSettingsViewModel {
        // TODO: Create mock TandemPumpManager with populated state for preview
        let viewModel = PreviewTandemKitSettingsViewModel(nextStep: {}, openInsulinType: {}, openSoundSettings: {})
        viewModel.reservoirValue = SimpleReservoirValue(startDate: Date(), unitVolume: 180)
        return viewModel
    }

    static var previewDataInProgress: TandemKitSettingsViewModel {
        let viewModel = PreviewTandemKitSettingsViewModel(nextStep: {}, openInsulinType: {}, openSoundSettings: {})
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
