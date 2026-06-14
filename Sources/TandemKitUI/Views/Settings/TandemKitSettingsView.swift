import LoopKitUI
import SwiftUI

private enum SettingsAlertType: Identifiable {
    case switchToCIQ
    case switchToDIY
    case diyRestored
    case noCGMConnected
    case findPump
    case stopTempRate
    case stopTempRateClosedLoopWarning

    var id: String {
        switch self {
        case .switchToCIQ: return "switchToCIQ"
        case .switchToDIY: return "switchToDIY"
        case .diyRestored: return "diyRestored"
        case .noCGMConnected: return "noCGMConnected"
        case .findPump: return "findPump"
        case .stopTempRate: return "stopTempRate"
        case .stopTempRateClosedLoopWarning: return "stopTempRateClosedLoopWarning"
        }
    }
}

struct TandemKitSettingsView: View {
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.guidanceColors) private var guidanceColors
    @Environment(\.insulinTintColor) var insulinTintColor

    @State var isSharePresented: Bool = false
    @State fileprivate var activeAlert: SettingsAlertType?
    @StateObject var viewModel: TandemKitSettingsViewModel

    var removePumpManagerActionSheet: ActionSheet {
        ActionSheet(
            title: Text("Remove Pump", comment: "Title for Tandem PumpManager deletion action sheet.")
                .font(.headline),
            message: Text(String(format: String(
                localized:
                "Are you sure you want to remove the pump from %@? You will need to re-pair the device to reconnect with it which will require access to the charging pad.",
                comment: "Message for Tandem PumpManager deletion action sheet"
            ), viewModel.appName)),
            buttons: [
                .destructive(Text(
                    "Delete Pump",
                    comment: "Button text to confirm Tandem PumpManager deletion"
                )) {
                    viewModel.removePump()
                },
                .cancel()
            ]
        )
    }

    var syncPumpTime: ActionSheet {
        ActionSheet(
            title: Text("Time Change Detected", comment: "Title for pod sync time action sheet."),
            message: Text(
                "The time on your pump is different from the current time. Do you want to update the time on your pump to the current time?",
                comment: "Message for pod sync time action sheet"
            ),
            buttons: [
                .default(Text("Yes, Sync to Current Time", comment: "Button text to confirm pump time sync")) {
                    self.viewModel.syncPumpTime()
                },
                .cancel(Text("No, Keep Pump As Is", comment: "Button text to cancel pump time sync"))
            ]
        )
    }

    private func errorSheetView(for failure: CommandFailure) -> some View {
        let content: ErrorSheetContent
        switch failure {
        case .resume:
            content = ErrorSheetContent(
                title: String(
                    localized: "Could not resume insulin delivery",
                    comment: "Title for failure to resume insulin delivery"
                ),
                message: String(
                    localized:
                    "The pump rejected starting insulin delivery. Check \"View Notifications\" to see the pump's current status and swipe away all active pump notifications. This may have occurred due to active pump notifications, invalid settings, empty cartridge, or not filling the tubing.",
                    comment: "Message for failed to resume insulin delivery"
                )
            )
        case .suspend:
            content = ErrorSheetContent(
                title: String(
                    localized: "Could not suspend insulin delivery",
                    comment: "Title for failure to suspend insulin delivery"
                ),
                message: String(
                    localized:
                    "The pump rejected suspending insulin delivery. Check \"View Notifications\" to see the pump's current status and swipe away all active pump notifications. This may have occurred due to an active bolus. To urgently suspend insulin delivery, detach from your site.",
                    comment: "Message for failed to suspend insulin delivery"
                )
            )
        case .controlIQ:
            content = ErrorSheetContent(
                title: String(
                    localized: "Could not change Control-IQ setting",
                    comment: "Title for failure to toggle Control-IQ"
                ),
                message: String(
                    localized: "The pump rejected the Control-IQ change. Check \"View Notifications\" to see the pump's current status.",
                    comment: "Message for failed to toggle Control-IQ"
                )
            )
        case .exerciseMode:
            content = ErrorSheetContent(
                title: String(
                    localized: "Could not change exercise mode",
                    comment: "Title for failure to toggle exercise mode"
                ),
                message: String(
                    localized: "The pump rejected the exercise mode change. Check \"View Notifications\" to see the pump's current status.",
                    comment: "Message for failed to toggle exercise mode"
                )
            )
        case .sleepMode:
            content = ErrorSheetContent(
                title: String(
                    localized: "Could not change sleep mode",
                    comment: "Title for failure to toggle sleep mode"
                ),
                message: String(
                    localized: "The pump rejected the sleep mode change. Check \"View Notifications\" to see the pump's current status.",
                    comment: "Message for failed to toggle sleep mode"
                )
            )
        case .stopTempRate:
            content = ErrorSheetContent(
                title: String(
                    localized: "Could not stop temp rate",
                    comment: "Title for failure to stop temp rate"
                ),
                message: String(
                    localized: "The pump rejected stopping the temp rate. Check \"View Notifications\" to see the pump's current status.",
                    comment: "Message for failed to stop temp rate"
                )
            )
        case .playSound:
            content = ErrorSheetContent(
                title: String(
                    localized: "Could not play sound",
                    comment: "Title for failure to play pump sound"
                ),
                message: String(
                    localized: "The pump did not respond to the sound request. Check your pump connection.",
                    comment: "Message for failed to play pump sound"
                )
            )
        case .alertSnooze:
            content = ErrorSheetContent(
                title: String(
                    localized: "Could not update alert snooze",
                    comment: "Title for failure to set alert snooze"
                ),
                message: String(
                    localized: "The pump rejected the alert snooze setting change. Check \"View Notifications\" to see the pump's current status.",
                    comment: "Message for failed to set alert snooze"
                )
            )
        }
        return ErrorSheetView(content: content, tint: guidanceColors.critical)
    }

    var body: some View {
        List {
            Section {
                ZStack {
                    Image(imageName: "tandem_mobi")
                        .resizable()
                        .rotationEffect(.degrees(90))
                        .scaledToFit()
                        .frame(height: 200)
                        .padding(.top, -25)
                        .padding(.bottom, -25)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading) {
                        if let battery = viewModel.batteryPercentage {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: batteryIconName(battery))
                                    .font(.system(size: 16))
                                    .foregroundColor(batteryColor(battery))
                                Text("\(battery)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                HStack(alignment: .firstTextBaseline) {
                    deliveryStatus

                    if let dose = viewModel.basalDose, dose.type == .suspend {
                        Spacer()
                    } else {
                        algorithmStatus
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                activeAlert = viewModel.useControlIQ ? .switchToDIY : .switchToCIQ
                            }
                    }

                    reservoirStatus
                }
                .padding(.bottom, 5)

                if !viewModel.isConnected {
                    statusBanner(
                        title: String(localized: "Pump Disconnected", comment: "title for pump disconnected notice"),
                        color: .red
                    )
                } else if viewModel.useControlIQ && !viewModel.isCGMActiveOnPump {
                    statusBanner(
                        title: String(localized: "No CGM connected to pump", comment: "title for CIQ no CGM notice"),
                        subtitle: String(
                            format: String(
                                localized: "%@ closed-loop is disabled with your pump's Control-IQ algorithm on, but no CGM is connected, so you are in open-loop.",
                                comment: "subtitle for CIQ no CGM notice"
                            ),
                            viewModel.algorithmName
                        ),
                        color: .orange
                    )
                } else if viewModel.useControlIQ {
                    statusBanner(
                        title: String(localized: "Control-IQ pump algorithm enabled", comment: "title for CIQ active notice"),
                        subtitle: String(
                            format: String(localized: "%@ closed-loop is not in use.", comment: "subtitle for CIQ active notice"),
                            viewModel.algorithmName
                        ),
                        color: .orange
                    )
                } else if !viewModel.isClosedLoopEnabled {
                    statusBanner(
                        title: String(localized: "Open loop mode", comment: "title for open loop notice"),
                        color: .orange
                    )
                    .contentShape(Rectangle())
                }

                if viewModel.showPumpTimeSyncWarning {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Time Change Detected", comment: "title for time change detected notice")
                            .font(Font.subheadline.weight(.bold))
                        Text(
                            "The time on your pump is different from the current time. Your pump’s time controls your scheduled therapy settings. Scroll down to Pump Time row to review the time difference and configure your pump.",
                            comment: "description for time change detected notice"
                        )
                        .font(Font.footnote.weight(.semibold))
                    }.padding(.vertical, 8)
                }
            }

            Section(header: SectionHeader(label: String(
                localized:
                "Actions",
                comment: "The title of the actions section in TandemKit settings"
            ))) {
                navigationLink(
                    label: Text("Pump notifications", comment: "Label for pump notifications"),
                    value: {
                        HStack {
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
                    },
                    action: { viewModel.openNotifications() }
                )

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

                Button(action: { viewModel.refreshPumpStatus() }) {
                    HStack {
                        Text("Sync Pump Data", comment: "refresh pump data")
                        Spacer()
                        if viewModel.isRefreshing {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                        }
                    }
                }
                .disabled(viewModel.isRefreshing)

                Button(action: {
                    activeAlert = .findPump
                }) {
                    HStack {
                        Text("Find My Pump", comment: "Tandem find my pump")
                        Spacer()
                        if viewModel.isPlayingSound {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                        }
                    }
                }
                .disabled(viewModel.isPlayingSound)
            }
            Section(header: SectionHeader(label: String(
                localized:
                "Pump Settings",
                comment: "The title of the pump settings section in TandemKit settings"
            ))) {
                navigationLink(
                    label: Text("Pump Information", comment: "Title for pump information"),
                    action: { viewModel.openPumpInformation() }
                )

                if viewModel.controlIQEnabled, let mode = viewModel.controlIQUserMode {
                    HStack {
                        Text("Control-IQ User mode", comment: "Text for Control-IQ user mode")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(userModeText(mode.rawValue))
                            .foregroundColor(.secondary)
                    }
                }

                navigationLink(
                    label: Text("Insulin type", comment: "Label for button to view insulin type of pump"),
                    action: { viewModel.openInsulinType() }
                )

                navigationLink(
                    label: Text("Sound settings", comment: "Label for button to view sound settings of pump"),
                    action: { viewModel.openSoundSettings() }
                )

                navigationLink(
                    label: Text("Control-IQ Settings", comment: "Label for Control-IQ settings"),
                    action: { viewModel.openControlIQSettings() }
                )

                navigationLink(
                    label: Text("CGM Settings", comment: "Label for CGM settings"),
                    action: { viewModel.openCgmSettings() }
                )

                navigationLink(
                    label: Text("Quick Bolus Settings", comment: "Label for quick bolus settings"),
                    action: { viewModel.openQuickBolus() }
                )

                navigationLink(
                    label: Text("Alert Settings", comment: "Label for alert settings"),
                    action: { viewModel.openAlertSettings() }
                )
            }

            Section(header: SectionHeader(label: String(
                localized:
                "Cartridge Operations",
                comment: "The title of the cartridge operations section in TandemKit settings"
            ))) {
                if let insulinAge = viewModel.insulinAge {
                    HStack {
                        Text("Insulin Age", comment: "Text for time since last cartridge change")
                        Spacer()
                        Text(insulinAge)
                            .foregroundStyle(.secondary)
                    }
                }

                if let cannulaAge = viewModel.cannulaAge {
                    HStack {
                        Text("Cannula Age", comment: "Text for time since last cannula fill")
                        Spacer()
                        Text(cannulaAge)
                            .foregroundStyle(.secondary)
                    }
                }

                navigationLink(
                    label: Text("Change Cartridge", comment: "Label for change cartridge"),
                    action: { viewModel.openCartridgeChange() }
                )

                navigationLink(
                    label: Text("Fill Tubing", comment: "Label for fill tubing"),
                    action: { viewModel.openFillTubing() }
                )

                navigationLink(
                    label: Text("Fill Cannula", comment: "Label for fill cannula"),
                    action: { viewModel.openFillCannula() }
                )
            }

            Section(header: SectionHeader(label: String(
                localized: "Pump time",
                comment: "The title of the pump time section in DanaKit settings"
            ))) {
                HStack {
                    Text("Pump time", comment: "Text for pump time")
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
                    Text("Checked at", comment: "Text for pump time synced at")
                        .foregroundColor(Color.primary)
                    Spacer()
                    Text(viewModel.pumpTimeCheckedAt)
                        .foregroundColor(.secondary)
                }

                Button(action: {
                    viewModel.showingTimeSyncConfirmation = true
                }) {
                    Text("Manually sync Pump time", comment: "Label for syncing the time on the pump")
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
                    Text("Silent Tones", comment: "Label for silent tones")
                }
                Button(String(localized: "Share Tandem pump logs", comment: "TandemKit share logs")) {
                    self.isSharePresented = true
                }
                .sheet(isPresented: $isSharePresented, onDismiss: {}, content: {
                    ActivityViewController(activityItems: viewModel.getLogs())
                })
                Button(action: {
                    viewModel.showingDeleteConfirmation = true
                }) {
                    Text("Delete Pump", comment: "Label for PumpManager deletion button")
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
        .alert(item: $activeAlert) { alertType in
            switch alertType {
            case .switchToCIQ:
                return Alert(
                    title: Text(String(
                        format: String(
                            localized: "Disable %@ Algorithm",
                            comment: "Title for alert to switch from DIY to Control-IQ"
                        ),
                        viewModel.algorithmName
                    )),
                    message: Text(String(
                        format: String(
                            localized: "This will DISABLE %@ in favor of the Control-IQ algorithm built-in to your pump.\n\n%@ will stop issuing temp basals and boluses. Are you sure?",
                            comment: "Message for alert to switch from DIY to Control-IQ"
                        ),
                        viewModel.appName,
                        viewModel.appName
                    )),
                    primaryButton: .default(Text(
                        "Switch to Control-IQ",
                        comment: "Button to confirm switching to Control-IQ algorithm"
                    )) {
                        viewModel.switchAlgorithmToControlIQ()
                    },
                    secondaryButton: .cancel()
                )
            case .switchToDIY:
                return Alert(
                    title: Text(String(
                        format: String(
                            localized: "Enable %@ Algorithm",
                            comment: "Title for alert to switch from Control-IQ to DIY"
                        ),
                        viewModel.algorithmName
                    )),
                    message: Text(String(
                        format: String(
                            localized: "This will disable Control-IQ on your pump and allow %@ to resume %@ closed-loop dosing.",
                            comment: "Message for alert to switch from Control-IQ to DIY"
                        ),
                        viewModel.appName,
                        viewModel.algorithmName
                    )),
                    primaryButton: .default(Text(String(
                        format: String(
                            localized: "Switch to %@",
                            comment: "Button to confirm switching to DIY algorithm"
                        ),
                        viewModel.algorithmName
                    ))) {
                        viewModel.switchAlgorithmToDIY()
                    },
                    secondaryButton: .cancel()
                )
            case .diyRestored:
                return Alert(
                    title: Text(String(format: String(
                        localized: "%@ Mode Restored",
                        comment: "Title for DIY mode restored notice"
                    ), viewModel.algorithmName)),
                    message: Text(String(format: String(
                        localized:
                        "Control-IQ has been disabled and you are currently in open-loop. To re-enable %@ closed-loop, go to your app's Algorithm settings.",
                        comment: "Message for DIY mode restored notice"
                    ), viewModel.algorithmName)),
                    dismissButton: .default(Text("OK"))
                )
            case .noCGMConnected:
                return Alert(
                    title: Text("No CGM Connected", comment: "Title for no CGM connected warning"),
                    message: Text(
                        "Control-IQ was enabled but no CGM is connected to the pump.\n\nUntil a CGM sensor is connected, your configured profile rates will be used. To connect a sensor, go to CGM Settings below.",
                        comment: "Message for no CGM connected warning after enabling Control-IQ"
                    ),
                    dismissButton: .default(Text("OK"))
                )
            case .findPump:
                return Alert(
                    title: Text("Find my pump", comment: "Find pump alert title"),
                    message: Text(
                        "The pump will vibrate and make sounds to help you identify its location.",
                        comment: "Find pump alert message"
                    ),
                    primaryButton: .default(
                        Text("Continue", comment: "Continue button"),
                        action: { viewModel.playSound() }
                    ),
                    secondaryButton: .cancel()
                )
            case .stopTempRate:
                return Alert(
                    title: Text("Temp Basal Active", comment: "Stop temp rate alert title"),
                    message: Text(stopTempRateMessage),
                    primaryButton: .destructive(
                        Text("Stop Temp Rate", comment: "Stop temp rate button"),
                        action: {
                            if viewModel.isClosedLoopEnabled {
                                DispatchQueue.main.async {
                                    activeAlert = .stopTempRateClosedLoopWarning
                                }
                            } else {
                                viewModel.stopTempRate()
                            }
                        }
                    ),
                    secondaryButton: .cancel()
                )
            case .stopTempRateClosedLoopWarning:
                return Alert(
                    title: Text("WARNING", comment: "Closed loop temp rate warning title"),
                    message: Text(
                        "Closed loop is currently enabled. Cancelling the active temp rate on the pump will NOT place you in open-loop mode, and the next run of the oref algorithm will set a new temp rate.",
                        comment: "Closed loop temp rate warning message"
                    ),
                    primaryButton: .destructive(
                        Text("I Understand", comment: "Closed loop temp rate warning confirm button"),
                        action: { viewModel.stopTempRate() }
                    ),
                    secondaryButton: .cancel()
                )
            }
        }
        .onChange(of: viewModel.showReenableClosedLoopPrompt) { show in
            if show {
                activeAlert = .diyRestored
                viewModel.showReenableClosedLoopPrompt = false
            }
        }
        .onChange(of: viewModel.showNoCGMWarning) { show in
            if show {
                activeAlert = .noCGMConnected
                viewModel.showNoCGMWarning = false
            }
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
        Button(String(localized: "Done", comment: "button text")) {
            dismiss()
        }
    }

    var reservoirStatus: some View {
        VStack(alignment: .center, spacing: 5) {
            Text("Cartridge", comment: "Header for insulin remaining")
                .foregroundColor(Color(UIColor.secondaryLabel))

            if let unitsText = viewModel.reservoirUnitsText, let reservoirLevel = viewModel.reservoirValue?.unitVolume {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    ReservoirView(reservoirLevel: reservoirLevel, fillColor: reservoirColor(reservoirLevel))
                        .frame(width: 19, height: 26)

                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(unitsText)
                            .font(.system(size: 28))
                            .fontWeight(.heavy)
                            .fixedSize()
                        Text("U")
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("--")
                    .font(.system(size: 28))
                    .fontWeight(.heavy)
            }
        }
    }

    var algorithmStatus: some View {
        VStack(alignment: .center, spacing: 5) {
            Text("Algorithm", comment: "Header for algorithm status")
                .foregroundColor(Color(UIColor.secondaryLabel))
            Text(viewModel.algorithmModeText)
                .font(.system(size: 28))
                .fontWeight(.regular)
                .foregroundColor(viewModel.useControlIQ ? .orange : .secondary)
                .fixedSize()
        }
    }

    var deliveryStatus: some View {
        VStack(alignment: .center, spacing: 5) {
            Text(deliverySectionTitle)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)

            if let dose = viewModel.basalDose {
                switch dose.type {
                case .suspend:
                    HStack(alignment: .center) {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 34))
                            .fixedSize()
                            .foregroundColor(guidanceColors.warning)
                        Text("Insulin\nSuspended", comment: "Text shown when insulin suspended")
                            .fontWeight(.bold)
                            .fixedSize()
                    }
                default:
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.2f", dose.value))
                            .font(.system(size: 28))
                            .fontWeight(.heavy)
                            .fixedSize()

                        Text("U/hr")
                            .foregroundColor(.secondary)
                            .fixedSize()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if dose.type == .tempBasal {
                            activeAlert = .stopTempRate
                        }
                    }
                }
            }
        }
    }

    var stopTempRateMessage: String {
        let rateText = String(format: "%.2f U/hr", viewModel.basalDose?.value ?? 0)

        let durationText: String
        if let start = viewModel.basalDose?.startDate, let end = viewModel.basalDose?.estimatedEndDate {
            let minutes = Int(end.timeIntervalSince(start)) / 60
            let hours = minutes / 60
            let mins = minutes % 60
            if hours > 0 {
                durationText = "\(hours) hour\(hours == 1 ? "" : "s") \(mins) minute\(mins == 1 ? "" : "s")"
            } else {
                durationText = "\(mins) minute\(mins == 1 ? "" : "s")"
            }
        } else {
            durationText = "an unknown duration"
        }

        return "The current temp rate is \(rateText) for the next \(durationText). Would you like to revert to your scheduled basal rate?"
    }

    var deliverySectionTitle: String {
        guard let dose = viewModel.basalDose else {
            return ""
        }

        switch dose.type {
        case .tempBasal:
            return String(localized: "Temp Basal", comment: "Title for temp rate")
        case .suspend:
            return String(localized: "Insulin Delivery", comment: "Title of insulin delivery section")
        default:
            return String(localized: "Profile Basal", comment: "Title of insulin delivery section")
        }
    }

    private func navigationLink(label: Text, action: @escaping () -> Void) -> some View {
        navigationLink(label: label, value: (() -> EmptyView)?.none, action: action)
    }

    @ViewBuilder private func navigationLink<V: View>(
        label: Text,
        value: (() -> V)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                label.foregroundStyle(.primary)

                Spacer()

                if let value {
                    value()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: UIFont.systemFontSize, weight: .medium))
                    .opacity(0.35)
                    .padding(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reservoirColor(_ reservoirLevel: Double) -> Color {
        if reservoirLevel > 25 {
            return insulinTintColor
        }

        if reservoirLevel > 0 {
            return guidanceColors.warning
        }

        return guidanceColors.critical
    }

    private func statusBanner(title: String, subtitle: String? = nil, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Font.subheadline.weight(.bold))
                .foregroundColor(color)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(Font.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func batteryIconName(_ percentage: String) -> String {
        guard let value = Int(percentage.replacingOccurrences(of: "%", with: "")) else {
            return "battery.0"
        }
        switch value {
        case 75 ... 100: return "battery.100"
        case 50 ..< 75: return "battery.75"
        case 25 ..< 50: return "battery.50"
        case 1 ..< 25: return "battery.25"
        default: return "battery.0"
        }
    }

    private func batteryColor(_ percentage: String) -> Color {
        guard let value = Int(percentage.replacingOccurrences(of: "%", with: "")) else {
            return .secondary
        }
        if value <= 10 { return .red }
        if value <= 25 { return .orange }
        return .green
    }

    private func userModeText(_ mode: Int) -> String {
        switch mode {
        case 0,
             1:
            return String(localized: "Standard", comment: "user mode standard")
        case 2:
            return String(localized: "Sleep", comment: "user mode sleep")
        case 3:
            return String(localized: "Exercise", comment: "user mode exercise")
        default:
            return String(localized: "Unknown", comment: "user mode unknown")
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
        let viewModel = PreviewTandemKitSettingsViewModel(
            nextStep: {},
            openPumpInformation: {},
            openNotifications: {},
            openInsulinType: {},
            openSoundSettings: {},
            openCartridgeChange: {},
            openFillTubing: {},
            openFillCannula: {},
            openCgmSettings: {},
            openControlIQSettings: {},
            openQuickBolus: {},
            openAlertSettings: {}
        )
        viewModel.reservoirValue = SimpleReservoirValue(startDate: Date(), unitVolume: 180)
        return viewModel
    }

    static var previewDataInProgress: TandemKitSettingsViewModel {
        let viewModel = PreviewTandemKitSettingsViewModel(
            nextStep: {},
            openPumpInformation: {},
            openNotifications: {},
            openInsulinType: {},
            openSoundSettings: {},
            openCartridgeChange: {},
            openFillTubing: {},
            openFillCannula: {},
            openCgmSettings: {},
            openControlIQSettings: {},
            openQuickBolus: {},
            openAlertSettings: {}
        )
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
