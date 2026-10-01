import LoopKitUI
import SwiftUI

private enum SettingsAlertType: Identifiable {
    case switchToCIQ
    case switchToDIY
    case cgmRequiredForCIQ
    case controlIQValuesRequired
    case diyRestored
    case noCGMConnected
    case stopTempRate
    case stopTempRateClosedLoopWarning
    case suspendDelivery
    case resumeDelivery

    var id: String {
        switch self {
        case .switchToCIQ: return "switchToCIQ"
        case .switchToDIY: return "switchToDIY"
        case .cgmRequiredForCIQ: return "cgmRequiredForCIQ"
        case .controlIQValuesRequired: return "controlIQValuesRequired"
        case .diyRestored: return "diyRestored"
        case .noCGMConnected: return "noCGMConnected"
        case .stopTempRate: return "stopTempRate"
        case .stopTempRateClosedLoopWarning: return "stopTempRateClosedLoopWarning"
        case .suspendDelivery: return "suspendDelivery"
        case .resumeDelivery: return "resumeDelivery"
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

    var removePumpManagerActionSheet: ConfirmationDialogContent {
        ConfirmationDialogContent(
            title: Text("Remove Pump", comment: "Title for Tandem PumpManager deletion confirmation dialog."),
            message: Text(String(format: String(
                localized:
                "Are you sure you want to remove the pump from %@? You will need to re-pair the device to reconnect with it which will require access to the charging pad.",
                comment: "Message for Tandem PumpManager deletion confirmation dialog"
            ), viewModel.appName)),
            actions: [
                .destructive(Text(
                    "Delete Pump",
                    comment: "Button text to confirm Tandem PumpManager deletion"
                )) {
                    viewModel.removePump()
                },
                .cancel(Text("Cancel", comment: "Cancel button"))
            ]
        )
    }

    var syncPumpTime: ConfirmationDialogContent {
        ConfirmationDialogContent(
            title: Text("Time Change Detected", comment: "Title for pod sync time confirmation dialog."),
            message: Text(
                "The time on your pump is different from the current time. Do you want to update the time on your pump to the current time?",
                comment: "Message for pod sync time confirmation dialog"
            ),
            actions: [
                .standard(Text("Yes, Sync to Current Time", comment: "Button text to confirm pump time sync")) {
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
                ZStack(alignment: .topLeading) {
                    Image(imageName: "tandem_mobi")
                        .resizable()
                        .rotationEffect(.degrees(90))
                        .scaledToFit()
                        .frame(height: 200)
                        .padding(.top, -25)
                        .padding(.bottom, -25)
                        .frame(maxWidth: .infinity)

                    // Centered so the percentage sits level with the battery, and the battery
                    // sits level with the sound button across from it.
                    HStack(alignment: .center) {
                        if let battery = viewModel.batteryPercentage {
                            HStack(alignment: .center, spacing: 4) {
                                BatteryIndicatorView(
                                    chargeRemaining: viewModel.batteryChargeRemaining,
                                    isCharging: viewModel.batteryIsCharging
                                )
                                Text("\(battery)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(
                                        BatteryIndicatorView.tintColor(
                                            chargeRemaining: viewModel.batteryChargeRemaining,
                                            isCharging: viewModel.batteryIsCharging,
                                            guidanceColors: guidanceColors
                                        )
                                    )
                            }
                        }

                        Spacer()

                        Button(action: { viewModel.playSound() }) {
                            Group {
                                if viewModel.isPlayingSound {
                                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                                } else {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            // Fixed footprint so swapping in the spinner doesn't shift the row.
                            .frame(width: 24, height: 20)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isPlayingSound)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .padding(.horizontal, 4)
                }

                HStack(alignment: .firstTextBaseline) {
                    deliveryStatus

                    if let dose = viewModel.basalDose, dose.type == .suspend {
                        Spacer()
                    } else {
                        algorithmStatus
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .overlay(
                                Group {
                                    if viewModel.isCheckingCGMForCIQ {
                                        ActivityIndicator(isAnimating: .constant(true), style: .medium)
                                    }
                                }
                            )
                            // Require a deliberate long press (not a single tap) to open the
                            // algorithm-switch confirmation, so it can't be triggered inadvertently.
                            .onLongPressGesture(minimumDuration: 0.5) {
                                if viewModel.useControlIQ {
                                    activeAlert = .switchToDIY
                                } else if viewModel.controlIQSupportEnabled {
                                    // Switching to Control-IQ requires a CGM connected to the pump;
                                    // verify one is configured before offering the confirmation.
                                    viewModel.attemptSwitchToControlIQ()
                                }
                            }
                    }

                    reservoirStatus
                }
                .padding(.bottom, 5)

                if let connectionIssue = viewModel.connectionIssue {
                    Button(action: { viewModel.openTroubleshootConnection() }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(connectionIssue.title)
                                    .font(Font.subheadline.weight(.bold))
                                    .foregroundColor(guidanceColors.critical)
                                Text(connectionIssue.detail(appName: viewModel.appName))
                                    .font(Font.footnote.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Troubleshoot connection", comment: "subtitle linking to the connection troubleshooter")
                                    .font(Font.caption)
                                    .foregroundColor(.accentColor)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(Font.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else if viewModel.showsNoCGMConnectedBanner {
                    statusBanner(
                        title: String(localized: "No CGM connected to pump", comment: "title for CIQ no CGM notice"),
                        subtitle: String(
                            format: String(
                                localized: "%@ closed-loop is disabled with your pump's Control-IQ algorithm on, but no CGM is connected, so you are in open-loop.",
                                comment: "subtitle for CIQ no CGM notice"
                            ),
                            viewModel.algorithmName
                        ),
                        color: guidanceColors.warning,
                        actionLabel: disableControlIQLabel,
                        action: { activeAlert = .switchToDIY }
                    )
                } else if viewModel.useControlIQ {
                    statusBanner(
                        title: String(localized: "Control-IQ pump algorithm enabled", comment: "title for CIQ active notice"),
                        subtitle: String(
                            format: String(localized: "%@ closed-loop is not in use.", comment: "subtitle for CIQ active notice"),
                            viewModel.algorithmName
                        ),
                        color: guidanceColors.warning,
                        actionLabel: disableControlIQLabel,
                        action: { activeAlert = .switchToDIY }
                    )
                } else if !viewModel.isClosedLoopEnabled {
                    statusBanner(
                        title: String(localized: "Open loop mode", comment: "title for open loop notice"),
                        color: guidanceColors.warning
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
                                        .fill(guidanceColors.critical)
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
                        activeAlert = viewModel.isDeliverySuspended ? .resumeDelivery : .suspendDelivery
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

                if viewModel.controlIQSupportEnabled {
                    navigationLink(
                        label: Text("Control-IQ Settings", comment: "Label for Control-IQ settings"),
                        action: { viewModel.openControlIQSettings() }
                    )
                }

                navigationLink(
                    label: Text("CGM Settings", comment: "Label for CGM settings"),
                    action: { viewModel.openCgmSettings() }
                )

                if viewModel.quickBolusButtonSupportEnabled {
                    navigationLink(
                        label: Text("Quick Bolus Settings", comment: "Label for quick bolus settings"),
                        action: { viewModel.openQuickBolus() }
                    )
                }

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
                .confirmationAlert(isPresented: $viewModel.showingTimeSyncConfirmation) {
                    syncPumpTime
                }
            }

            Section {
                Button(String(localized: "Share Tandem pump logs", comment: "TandemKit share logs")) {
                    self.isSharePresented = true
                }
                .sheet(isPresented: $isSharePresented, onDismiss: {}, content: {
                    ActivityViewController(activityItems: viewModel.getLogs())
                })
                if viewModel.allowDebugFeatures {
                    Button(String(localized: "View Debug Options", comment: "Label for button to open TandemKit debug options")) {
                        viewModel.openDebug()
                    }
                }
                Button(action: {
                    viewModel.showingDeleteConfirmation = true
                }) {
                    Text("Delete Pump", comment: "Label for PumpManager deletion button")
                        .foregroundColor(guidanceColors.critical)
                }
                .confirmationAlert(isPresented: $viewModel.showingDeleteConfirmation) {
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
            case .cgmRequiredForCIQ:
                return Alert(
                    title: Text(
                        "Connect a CGM First",
                        comment: "Title for alert blocking the switch to Control-IQ when no CGM is connected"
                    ),
                    message: Text(
                        "Control-IQ needs a CGM connected to your pump to work. No active CGM sensor session was found on your pump, so switching to Control-IQ has been blocked.\n\nStart a CGM sensor from CGM Settings, then try switching again.",
                        comment: "Message for alert blocking the switch to Control-IQ when no CGM is connected"
                    ),
                    primaryButton: .default(
                        Text("CGM Settings", comment: "Button to open CGM settings from the no-CGM Control-IQ alert"),
                        action: { viewModel.openCgmSettings() }
                    ),
                    secondaryButton: .cancel(Text("OK"))
                )
            case .controlIQValuesRequired:
                return Alert(
                    title: Text(
                        "Control-IQ Setup Needed",
                        comment: "Title for alert blocking the switch to Control-IQ when weight/TDI are unset"
                    ),
                    message: Text(
                        "Control-IQ uses your weight and total daily insulin to dose, and your pump does not have them yet.\n\nEnter them in Control-IQ Settings, then try switching again.",
                        comment: "Message for alert blocking the switch to Control-IQ when weight/TDI are unset"
                    ),
                    primaryButton: .default(
                        Text(
                            "Control-IQ Settings",
                            comment: "Button to open Control-IQ settings from the missing-values alert"
                        ),
                        action: { viewModel.openControlIQSettings() }
                    ),
                    secondaryButton: .cancel(Text("OK"))
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
                // Control-IQ without a CGM is open-loop on both sides, so turning it straight back
                // off is a reasonable answer to this warning -- offer it here rather than making
                // the user find the banner's button afterwards.
                return Alert(
                    title: Text("No CGM Connected", comment: "Title for no CGM connected warning"),
                    message: Text(
                        "Control-IQ was enabled but no CGM is connected to the pump.\n\nUntil a CGM sensor is connected, your configured profile rates will be used. To connect a sensor, go to CGM Settings below.",
                        comment: "Message for no CGM connected warning after enabling Control-IQ"
                    ),
                    primaryButton: .default(Text(disableControlIQLabel)) {
                        viewModel.switchAlgorithmToDIY()
                    },
                    secondaryButton: .cancel(Text("OK"))
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
            case .suspendDelivery:
                return Alert(
                    title: Text("Suspend Insulin Delivery", comment: "Title for confirm suspend insulin delivery alert"),
                    message: Text(
                        "Are you sure you want to suspend insulin delivery? No basal or bolus insulin will be delivered until you resume delivery.",
                        comment: "Message for confirm suspend insulin delivery alert"
                    ),
                    primaryButton: .destructive(
                        Text("Suspend Delivery", comment: "Button to confirm suspending insulin delivery"),
                        action: { viewModel.suspendResumeButtonPressed() }
                    ),
                    secondaryButton: .cancel()
                )
            case .resumeDelivery:
                return Alert(
                    title: Text("Resume Insulin Delivery", comment: "Title for confirm resume insulin delivery alert"),
                    message: Text(
                        "Are you sure you want to resume insulin delivery? Your scheduled basal delivery will restart.",
                        comment: "Message for confirm resume insulin delivery alert"
                    ),
                    primaryButton: .default(
                        Text("Resume Delivery", comment: "Button to confirm resuming insulin delivery"),
                        action: { viewModel.suspendResumeButtonPressed() }
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
        .onChange(of: viewModel.showSwitchToCIQConfirm) { show in
            if show {
                activeAlert = .switchToCIQ
                viewModel.showSwitchToCIQConfirm = false
            }
        }
        .onChange(of: viewModel.showCGMRequiredForCIQ) { show in
            if show {
                activeAlert = .cgmRequiredForCIQ
                viewModel.showCGMRequiredForCIQ = false
            }
        }
        .onChange(of: viewModel.showControlIQValuesRequired) { show in
            if show {
                activeAlert = .controlIQValuesRequired
                viewModel.showControlIQValuesRequired = false
            }
        }
        .navigationBarItems(trailing: doneButton)
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
                .foregroundColor(viewModel.useControlIQ ? guidanceColors.warning : .secondary)
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
        let rateText = String(
            format: String(localized: "%.2f U/hr", comment: "Temp basal rate in the stop temp rate alert"),
            viewModel.basalDose?.value ?? 0
        )

        let durationFormatter = DateComponentsFormatter()
        durationFormatter.unitsStyle = .full
        durationFormatter.allowedUnits = [.hour, .minute]

        // Rounded up, so a temp rate with seconds left still reads "1 minute", not "0 minutes".
        let durationText: String
        if let end = viewModel.basalDose?.estimatedEndDate,
           let formatted = durationFormatter.string(from: (max(0, end.timeIntervalSinceNow) / 60).rounded(.up) * 60)
        {
            durationText = formatted
        } else {
            durationText = String(
                localized: "an unknown duration",
                comment: "Stands in for the temp basal duration in the stop temp rate alert when it is not known"
            )
        }

        return String(
            localized: "The current temp rate is \(rateText) for the next \(durationText). Would you like to revert to your scheduled basal rate?",
            comment: "Stop temp rate alert message (1: rate, 2: duration)"
        )
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

    /// Turning Control-IQ off is never gated on the `controlIQSupport` feature flag: the flag only
    /// governs handing dosing *to* Control-IQ, so a pump found running it can always be taken back.
    private var disableControlIQLabel: String {
        String(localized: "Disable Control-IQ", comment: "Button on a status banner to turn Control-IQ off on the pump")
    }

    /// `actionLabel`/`action` add a button under the text. The button is `.borderless` so the list
    /// row does not swallow the tap, and it is disabled while a pump command is already in flight.
    private func statusBanner(
        title: String,
        subtitle: String? = nil,
        color: Color,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Font.subheadline.weight(.bold))
                .foregroundColor(color)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(Font.caption)
                    .foregroundColor(.secondary)
            }
            if let actionLabel = actionLabel, let action = action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(Font.footnote.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isUpdatingPumpState)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
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
        viewModel.batteryPercentage = "100%"
        viewModel.batteryChargeRemaining = 1.0
        return viewModel
    }

    static var previewDataLowBattery: TandemKitSettingsViewModel {
        let viewModel = previewData
        viewModel.batteryPercentage = "15%"
        viewModel.batteryChargeRemaining = 0.15
        return viewModel
    }

    static var previewDataCharging: TandemKitSettingsViewModel {
        let viewModel = previewData
        viewModel.batteryPercentage = "62%"
        viewModel.batteryChargeRemaining = 0.62
        viewModel.batteryIsCharging = true
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

#Preview("Low Battery") {
    NavigationView {
        TandemKitSettingsView(viewModel: .previewDataLowBattery)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

#Preview("Charging") {
    NavigationView {
        TandemKitSettingsView(viewModel: .previewDataCharging)
    }
    .environment(\.guidanceColors, GuidanceColors())
}

#Preview("In Progress") {
    NavigationView {
        TandemKitSettingsView(viewModel: .previewDataInProgress)
    }
    .environment(\.guidanceColors, GuidanceColors())
}
