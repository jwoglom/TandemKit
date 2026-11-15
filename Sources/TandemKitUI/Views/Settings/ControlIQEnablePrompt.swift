import SwiftUI

/// What the user is shown on the way to Control-IQ, the same whether the switch is asked for on the
/// settings screen's Algorithm row or by saving the Control-IQ screen.
enum ControlIQEnablePrompt: String, Identifiable {
    case confirm
    case cgmRequired
    case valuesRequired

    var id: String { rawValue }

    /// The prompt for the outcome of `TandemPumpManager.checkControlIQCanBeEnabled`.
    init(_ blocker: ControlIQEnableBlocker?) {
        switch blocker {
        case nil:
            self = .confirm
        case .cgmRequired?:
            self = .cgmRequired
        case .valuesRequired?:
            self = .valuesRequired
        }
    }

    func alert(
        confirm: @escaping () -> Void,
        openCgmSettings: @escaping () -> Void,
        openControlIQSettings: @escaping () -> Void
    ) -> Alert {
        let appName = HostApp.current.appName
        let algorithmName = HostApp.current.diyAlgorithmName

        switch self {
        case .confirm:
            return Alert(
                title: Text(String(
                    format: String(
                        localized: "Disable %@ Algorithm",
                        comment: "Title for alert to switch from DIY to Control-IQ"
                    ),
                    algorithmName
                )),
                message: Text(String(
                    format: String(
                        localized: "This will DISABLE %@ in favor of the Control-IQ algorithm built-in to your pump.\n\n%@ will stop issuing temp basals and boluses. Are you sure?",
                        comment: "Message for alert to switch from DIY to Control-IQ"
                    ),
                    appName,
                    appName
                )),
                primaryButton: .default(Text(
                    "Switch to Control-IQ",
                    comment: "Button to confirm switching to Control-IQ algorithm"
                ), action: confirm),
                secondaryButton: .cancel()
            )
        case .cgmRequired:
            return Alert(
                title: Text(
                    "Connect a CGM First",
                    comment: "Title for alert blocking the switch to Control-IQ when no CGM is connected"
                ),
                message: Text(
                    "Control-IQ needs a CGM connected to your pump to work. No active CGM sensor session was found on your pump, so switching to Control-IQ has been blocked.\n\nStart a CGM sensor from Mobi CGM settings, then try switching again.",
                    comment: "Message for alert blocking the switch to Control-IQ when no CGM is connected"
                ),
                primaryButton: .default(
                    Text("Mobi CGM settings", comment: "Button to open Mobi CGM settings from the no-CGM Control-IQ alert"),
                    action: openCgmSettings
                ),
                secondaryButton: .cancel(Text("OK", comment: "Button to dismiss an alert"))
            )
        case .valuesRequired:
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
                    action: openControlIQSettings
                ),
                secondaryButton: .cancel(Text("OK", comment: "Button to dismiss an alert"))
            )
        }
    }
}
