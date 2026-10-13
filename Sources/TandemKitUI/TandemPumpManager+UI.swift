import LoopKit
import LoopKitUI
import SwiftUI

extension TandemPumpManager: PumpManagerUI {
    public static func setupViewController(
        initialSettings settings: LoopKitUI.PumpManagerSetupSettings,
        bluetoothProvider _: any LoopKit.BluetoothProvider,
        colorPalette: LoopKitUI.LoopUIColorPalette,
        allowDebugFeatures: Bool,
        prefersToSkipUserInteraction _: Bool,
        allowedInsulinTypes: [LoopKit.InsulinType]
    ) -> LoopKitUI.SetupUIResult<any LoopKitUI.PumpManagerViewController, any LoopKitUI.PumpManagerUI> {
        let vc = TandemUICoordinator(
            colorPalette: colorPalette,
            pumpManagerSettings: settings,
            allowDebugFeatures: allowDebugFeatures,
            allowedInsulinTypes: allowedInsulinTypes
        )
        return .userInteractionRequired(vc)
    }

    public func settingsViewController(
        bluetoothProvider _: BluetoothProvider,
        colorPalette: LoopUIColorPalette,
        allowDebugFeatures: Bool,
        allowedInsulinTypes: [InsulinType]
    ) -> PumpManagerViewController {
        TandemUICoordinator(
            pumpManager: self,
            colorPalette: colorPalette,
            allowDebugFeatures: allowDebugFeatures,
            allowedInsulinTypes: allowedInsulinTypes
        )
    }

    public func deliveryUncertaintyRecoveryViewController(
        colorPalette: LoopUIColorPalette,
        allowDebugFeatures: Bool
    ) -> (UIViewController & CompletionNotifying) {
        TandemUICoordinator(pumpManager: self, colorPalette: colorPalette, allowDebugFeatures: allowDebugFeatures)
    }

    public func hudProvider(
        bluetoothProvider: BluetoothProvider,
        colorPalette: LoopUIColorPalette,
        allowedInsulinTypes: [InsulinType]
    ) -> HUDProvider? {
        TandemKitHUDProvider(
            pumpManager: self,
            bluetoothProvider: bluetoothProvider,
            colorPalette: colorPalette,
            allowedInsulinTypes: allowedInsulinTypes
        )
    }

    public static func createHUDView(rawValue: [String: Any]) -> BaseHUDView? {
        TandemKitHUDProvider.createHUDView(rawValue: rawValue)
    }

    public static var onboardingImage: UIImage? {
        UIImage(
            named: "tandem_mobi",
            in: Bundle(for: TandemUICoordinator.self),
            compatibleWith: nil
        )
    }

    public var smallImage: UIImage? {
        UIImage(
            named: "tandem_mobi",
            in: Bundle(for: TandemUICoordinator.self),
            compatibleWith: nil
        )
    }

    public var pumpStatusHighlight: DeviceStatusHighlight? {
        buildPumpStatusHighlight()
    }

    // Not needed
    public var pumpLifecycleProgress: DeviceLifecycleProgress? {
        nil
    }

    public var pumpStatusBadge: DeviceStatusBadge? {
        state.showPumpTimeSyncWarning ? TandemKitStatusBadge.timeSyncNeeded : nil
    }
}

extension TandemPumpManager {
    private enum TandemKitStatusBadge: DeviceStatusBadge {
        case timeSyncNeeded

        public var image: UIImage? {
            switch self {
            case .timeSyncNeeded:
                return UIImage(systemName: "clock.fill")
            }
        }

        public var state: DeviceStatusBadgeState {
            switch self {
            case .timeSyncNeeded:
                return .warning
            }
        }
    }

    private func buildPumpStatusHighlight() -> DeviceStatusHighlight? {
        // Ahead of the therapy highlights below: those are all read from a pump we have stopped
        // hearing from, and reconnecting is the prerequisite for acting on any of them.
        if let issue = sustainedConnectionIssue {
            return PumpStatusHighlight(
                localizedMessage: issue.title,
                imageName: issue.imageName,
                state: .critical
            )
        }

        // Trio does not act on `deliveryIsUncertain`, so this is where its user learns of it.
        if status.deliveryIsUncertain {
            return PumpStatusHighlight(
                localizedMessage: String(
                    localized: "Bolus Not Confirmed",
                    comment: "Status highlight that the pump never answered a bolus command, so whether it is delivering that bolus is not yet known."
                ),
                imageName: "exclamationmark.circle.fill",
                state: .critical
            )
        }

        // Before the suspend, reservoir and Control-IQ highlights, because it means the basal rates
        // the app shows are not what the pump is running.
        if state.basalProfileUpdateStatus == .failed {
            return PumpStatusHighlight(
                localizedMessage: String(
                    localized: "Basal Profile Not Updated",
                    comment: "Status highlight that the driver could not write the app's basal rates to the pump."
                ),
                imageName: "exclamationmark.circle.fill",
                state: .critical
            )
        }

        if state.basalDose.type == .suspend {
            return PumpStatusHighlight(
                localizedMessage: String(
                    localized: "Insulin Suspended",
                    comment: "Status highlight that insulin delivery was suspended."
                ),
                imageName: "pause.circle.fill",
                state: .warning
            )
        }

        if let reservoirLevel = reservoirLevel, reservoirLevel.unitVolume < 1 {
            return PumpStatusHighlight(
                localizedMessage: String(
                    localized: "No Insulin",
                    comment: "Status highlight that a pump is out of insulin."
                ),
                imageName: "exclamationmark.circle.fill",
                state: .critical
            )
        }

        if state.basalProfileUpdateStatus == .updating {
            return PumpStatusHighlight(
                localizedMessage: String(
                    localized: "Syncing Basal Profiles",
                    comment: "Status highlight that the pump's basal rates are being updated to match the app's."
                ),
                imageName: "arrow.triangle.2.circlepath",
                state: .warning
            )
        }

        if state.isPumpClockSkewed {
            return PumpStatusHighlight(
                localizedMessage: String(
                    localized: "Pump Time Is Off",
                    comment: "Status highlight that the pump's clock differs from the phone's by more than a few minutes."
                ),
                imageName: "clock.fill",
                state: .warning
            )
        }

        // Control-IQ owning delivery is a standing condition, not a one-off failure: while it is on
        // the driver refuses every automatic bolus and temp basal, so without this the only trace of
        // it in the host app is a loop failure once a cycle, worded by the host rather than by us.
        if state.useControlIQ {
            return PumpStatusHighlight(
                localizedMessage: String(
                    localized: "Control-IQ On",
                    comment: "Status highlight that the pump's Control-IQ algorithm is controlling delivery."
                ),
                imageName: "exclamationmark.circle.fill",
                state: .warning
            )
        }

        return nil
    }
}
