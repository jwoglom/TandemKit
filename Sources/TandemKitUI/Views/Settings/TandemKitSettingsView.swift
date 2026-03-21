import LoopKitUI
import SwiftUI
import TandemCore

private enum AlgorithmAlertType: Identifiable {
    case switchToCIQ
    case switchToDIY
    case diyRestored
    case noCGMConnected
    case enableClosedLoop

    var id: String {
        switch self {
        case .switchToCIQ: return "switchToCIQ"
        case .switchToDIY: return "switchToDIY"
        case .diyRestored: return "diyRestored"
        case .noCGMConnected: return "noCGMConnected"
        case .enableClosedLoop: return "enableClosedLoop"
        }
    }
}

struct TandemKitSettingsView: View {
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.guidanceColors) private var guidanceColors
    @Environment(\.insulinTintColor) var insulinTintColor

    @State var isSharePresented: Bool = false
    @State var showingFindPumpConfirmation: Bool = false
    @State var showingStopTempRateConfirmation: Bool = false
    @State fileprivate var activeAlgorithmAlert: AlgorithmAlertType?
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
        case .playSound:
            content = ErrorSheetContent(
                title: LocalizedString(
                    "Could not play sound",
                    comment: "Title for failure to play pump sound"
                ),
                message: LocalizedString(
                    "The pump did not respond to the sound request. Check your pump connection.",
                    comment: "Message for failed to play pump sound"
                )
            )
        case .alertSnooze:
            content = ErrorSheetContent(
                title: LocalizedString(
                    "Could not update alert snooze",
                    comment: "Title for failure to set alert snooze"
                ),
                message: LocalizedString(
                    "The pump rejected the alert snooze setting change. Check \"View Notifications\" to see the pump's current status.",
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

                    VStack {
                        HStack {
                            if let battery = viewModel.batteryPercentage {
                                HStack(spacing: 4) {
                                    Image(systemName: batteryIconName(battery))
                                        .font(.system(size: 16))
                                        .foregroundColor(batteryColor(battery))
                                    Text("\(battery)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Button(action: {
                                viewModel.refreshPumpStatus()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.accentColor)
                                    .opacity(viewModel.isRefreshing ? 0 : 1)
                                    .overlay {
                                        if viewModel.isRefreshing {
                                            ProgressView()
                                        }
                                    }
                            }
                            .buttonStyle(.borderless)
                            .disabled(!viewModel.isConnected || viewModel.isRefreshing)
                            .opacity(viewModel.isConnected ? 1.0 : 0.4)
                        }
                        .padding(.top, 4)
                        Spacer()
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    deliveryStatus
                        .frame(maxWidth: .infinity)
                    if viewModel.isSuspended != true {
                        algorithmStatus
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                activeAlgorithmAlert = viewModel.useControlIQ ? .switchToDIY : .switchToCIQ
                            }
                    }
                    reservoirStatus
                        .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 5)
                .alert(item: $activeAlgorithmAlert) { alertType in
                    switch alertType {
                    case .switchToCIQ:
                        return Alert(
                            title: Text(LocalizedString("Disable DIY Algorithm", comment: "Title for alert to switch from DIY to Control-IQ")),
                            message: Text(LocalizedString("This will DISABLE this app in favor of the Control-IQ algorithm built-in to your pump.\n\nThis app will stop issuing temp basals and boluses. Are you sure?", comment: "Message for alert to switch from DIY to Control-IQ")),
                            primaryButton: .default(Text(LocalizedString("Switch to Control-IQ", comment: "Button to confirm switching to Control-IQ algorithm"))) {
                                viewModel.switchAlgorithmToControlIQ()
                            },
                            secondaryButton: .cancel()
                        )
                    case .switchToDIY:
                        return Alert(
                            title: Text(LocalizedString("Enable DIY Algorithm", comment: "Title for alert to switch from Control-IQ to DIY")),
                            message: Text(LocalizedString("This will disable Control-IQ on your pump and allow this app to resume DIY closed-loop dosing.", comment: "Message for alert to switch from Control-IQ to DIY")),
                            primaryButton: .default(Text(LocalizedString("Switch to DIY", comment: "Button to confirm switching to DIY algorithm"))) {
                                viewModel.switchAlgorithmToDIY()
                            },
                            secondaryButton: .cancel()
                        )
                    case .diyRestored:
                        return Alert(
                            title: Text(LocalizedString("DIY Mode Restored", comment: "Title for DIY mode restored notice")),
                            message: Text(LocalizedString(
                                "Control-IQ has been disabled and you are currently in open-loop. To re-enable DIY closed-loop, go to your app's Algorithm settings.",
                                comment: "Message for DIY mode restored notice"
                            )),
                            dismissButton: .default(Text("OK"))
                        )
                    case .noCGMConnected:
                        return Alert(
                            title: Text(LocalizedString("No CGM Connected", comment: "Title for no CGM connected warning")),
                            message: Text(LocalizedString(
                                "Control-IQ was enabled but no CGM is connected to the pump.\n\nUntil a CGM sensor is connected, your configured profile rates will be used. To connect a sensor, go to CGM Settings below.",
                                comment: "Message for no CGM connected warning after enabling Control-IQ"
                            )),
                            dismissButton: .default(Text("OK"))
                        )
                    case .enableClosedLoop:
                        return Alert(
                            title: Text(LocalizedString("Enable Closed Loop", comment: "Title for enable closed loop prompt")),
                            message: Text(LocalizedString(
                                "Would you like to enable DIY closed loop?",
                                comment: "Message for enable closed loop prompt"
                            )),
                            primaryButton: .default(Text(LocalizedString("Enable", comment: "Button to enable closed loop"))) {
                                viewModel.enableClosedLoop()
                            },
                            secondaryButton: .cancel()
                        )
                    }
                }
                .onChange(of: viewModel.showReenableClosedLoopPrompt) { show in
                    if show {
                        activeAlgorithmAlert = .diyRestored
                        viewModel.showReenableClosedLoopPrompt = false
                    }
                }
                .onChange(of: viewModel.showNoCGMWarning) { show in
                    if show {
                        activeAlgorithmAlert = .noCGMConnected
                        viewModel.showNoCGMWarning = false
                    }
                }

                if !viewModel.isConnected {
                    statusBanner(
                        title: LocalizedString("Pump Disconnected", comment: "title for pump disconnected notice"),
                        color: .red
                    )
                } else if viewModel.useControlIQ && !viewModel.isCGMActiveOnPump {
                    statusBanner(
                        title: LocalizedString("No CGM connected to pump", comment: "title for CIQ no CGM notice"),
                        subtitle: LocalizedString("DIY closed-loop is disabled with your pump's Control-IQ algorithm on, but no CGM is connected, so you are in open-loop.", comment: "subtitle for CIQ no CGM notice"),
                        color: .orange
                    )
                } else if viewModel.useControlIQ {
                    statusBanner(
                        title: LocalizedString("Control-IQ pump algorithm enabled", comment: "title for CIQ active notice"),
                        subtitle: LocalizedString("DIY closed-loop is not in use.", comment: "subtitle for CIQ active notice"),
                        color: .orange
                    )
                } else if !viewModel.isClosedLoopEnabled {
                    statusBanner(
                        title: LocalizedString("Open loop mode", comment: "title for open loop notice"),
                        color: .orange
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        activeAlgorithmAlert = .enableClosedLoop
                    }
                }

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
                NavigationLink(destination: TandemKitNotificationsView(
                    viewModel: viewModel.createNotificationsViewModel()
                )) {
                    HStack {
                        Text(LocalizedString("Pump notifications", comment: "Label for pump notifications"))
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


                Button(action: {
                    showingFindPumpConfirmation = true
                }) {
                    HStack {
                        Text(LocalizedString("Find my pump", comment: "Tandem find my pump"))
                        Spacer()
                        if viewModel.isPlayingSound {
                            ActivityIndicator(isAnimating: .constant(true), style: .medium)
                        }
                    }
                }
                .disabled(viewModel.isPlayingSound)
                .alert(isPresented: $showingFindPumpConfirmation) {
                    Alert(
                        title: Text(LocalizedString("Find my pump", comment: "Find pump alert title")),
                        message: Text(LocalizedString(
                            "The pump will vibrate and make sounds to help you identify its location.",
                            comment: "Find pump alert message"
                        )),
                        primaryButton: .default(
                            Text(LocalizedString("Continue", comment: "Continue button")),
                            action: { viewModel.playSound() }
                        ),
                        secondaryButton: .cancel()
                    )
                }

            }
            Section(header: SectionHeader(label: LocalizedString(
                "Pump Settings",
                comment: "The title of the pump settings section in TandemKit settings"
            ))) {

                if viewModel.controlIQEnabled, let mode = viewModel.controlIQUserMode {
                    HStack {
                        Text(LocalizedString("Control-IQ User mode", comment: "Text for Control-IQ user mode"))
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

                if viewModel.useControlIQ {
                    NavigationLink(destination: TandemKitControlIQSettingsView(
                        viewModel: viewModel.createControlIQSettingsViewModel()
                    )) {
                        HStack {
                            Text(LocalizedString("Control-IQ Settings", comment: "Label for Control-IQ settings"))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                }

                NavigationLink(destination: TandemKitCGMSettingsView(
                    viewModel: viewModel.createCGMSettingsViewModel()
                )) {
                    HStack {
                        Text(LocalizedString("CGM Settings", comment: "Label for CGM settings"))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }

                NavigationLink(destination: TandemKitQuickBolusSettingsView(
                    viewModel: viewModel.createQuickBolusSettingsViewModel()
                )) {
                    HStack {
                        Text(LocalizedString("Quick Bolus settings", comment: "Label for quick bolus settings"))
                            .foregroundColor(.primary)
                        Spacer()
                        if let summary = viewModel.quickBolusSummary {
                            Text(summary)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                NavigationLink(destination: TandemKitAlertSettingsView(viewModel: viewModel)) {
                    HStack {
                        Text(LocalizedString("Alert Settings", comment: "Label for alert settings"))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
            }

            Section(header: SectionHeader(label: LocalizedString(
                "Delivery Limits",
                comment: "The title of the delivery limits section in TandemKit settings"
            ))) {
                NavigationLink(destination: TandemKitDeliveryLimitsView(
                    viewModel: viewModel.createDeliveryLimitsViewModel()
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(LocalizedString("Max Basal Rate", comment: "Label for max basal rate"))
                                .foregroundColor(.primary)
                            Spacer()
                            if let text = viewModel.maxBasalRateText {
                                Text(text)
                                    .foregroundColor(.secondary)
                            }
                        }
                        HStack {
                            Text(LocalizedString("Max Bolus", comment: "Label for max bolus"))
                                .foregroundColor(.primary)
                            Spacer()
                            if let text = viewModel.maxBolusText {
                                Text(text)
                                    .foregroundColor(.secondary)
                            }
                        }
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
        VStack(alignment: .center, spacing: 5) {
            Text(LocalizedString("Cartridge", comment: "Header for insulin remaining"))
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
            Text(LocalizedString("Algorithm", comment: "Header for algorithm status"))
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
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if let rate = viewModel.tempRateAbsolute {
                        Text(String(format: "%.2f", rate))
                            .font(.system(size: 28))
                            .fontWeight(.heavy)
                            .fixedSize()
                    } else {
                        Text(viewModel.currentBasalRateForDisplay)
                            .font(.system(size: 28))
                            .fontWeight(.heavy)
                            .fixedSize()
                    }

                    Text("U/hr")
                        .foregroundColor(.secondary)
                        .fixedSize()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if viewModel.tempRateActive {
                        showingStopTempRateConfirmation = true
                    }
                }
                .alert(isPresented: $showingStopTempRateConfirmation) {
                    Alert(
                        title: Text(LocalizedString("Temp Basal Active", comment: "Stop temp rate alert title")),
                        message: Text(stopTempRateMessage),
                        primaryButton: .destructive(
                            Text(LocalizedString("Stop Temp Rate", comment: "Stop temp rate button")),
                            action: { viewModel.stopTempRate() }
                        ),
                        secondaryButton: .cancel()
                    )
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

    var stopTempRateMessage: String {
        let rateText: String
        if let rate = viewModel.tempRateAbsolute {
            rateText = String(format: "%.2f U/hr", rate)
        } else {
            rateText = "unknown"
        }

        let durationText: String
        if let remaining = viewModel.tempRateRemainingSeconds {
            let minutes = Int(remaining) / 60
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
        if viewModel.isSuspended == true {
            return LocalizedString("Insulin Delivery", comment: "Title of insulin delivery section")
        } else if viewModel.tempRateActive {
            return LocalizedString("Temp Basal", comment: "Title for temp rate")
        } else {
            return LocalizedString("Profile Basal", comment: "Title of insulin delivery section")
        }
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

    // TODO(jwoglom): replace with consts from TandemCore
    private func statusBanner(title: String, subtitle: String? = nil, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Font.subheadline.weight(.bold))
                    .foregroundColor(color)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Font.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func batteryIconName(_ percentage: String) -> String {
        guard let value = Int(percentage.replacingOccurrences(of: "%", with: "")) else {
            return "battery.0"
        }
        switch value {
        case 75...100: return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        case 1..<25: return "battery.25"
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
