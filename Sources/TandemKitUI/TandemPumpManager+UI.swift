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
        // First, ahead of every therapy state below it: those are all read from the pump, so once
        // the link is gone they describe a pump we stopped hearing from rather than the pump the
        // user is wearing. Reconnecting is also the prerequisite for the app doing anything about
        // any of them. `sustainedConnectionIssue` (not `connectionIssue`) so a drop that
        // auto-reconnect clears in seconds never displaces a real therapy warning.
        if let issue = sustainedConnectionIssue {
            return PumpStatusHighlight(
                localizedMessage: issue.title,
                imageName: issue.imageName,
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
