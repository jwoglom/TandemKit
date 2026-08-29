import Foundation

/// User-facing wording for each way the pump can be out of reach.
///
/// Every case names what is wrong in the user's terms and what they can do about it, because the
/// remedies are not interchangeable: "Bluetooth Off" is fixed in the Settings app, "Pump
/// Disconnected" by moving the pump closer. A driver that only ever said the second is one the user
/// learns to ignore.
///
/// Each detail also says what is still happening to their insulin. Losing the connection stops the
/// app from reading or commanding the pump; it does not stop the pump, which goes on delivering
/// from its own settings. That is the first thing someone reading a red banner needs to know.
extension PumpConnectionIssue {
    /// Short label, for the home-screen status highlight and as the banner heading.
    var title: String {
        switch self {
        case .bluetoothOff:
            return String(localized: "Bluetooth Off", comment: "Pump unreachable because the phone's Bluetooth is off")
        case .bluetoothUnauthorized:
            return String(
                localized: "Bluetooth Not Allowed",
                comment: "Pump unreachable because the app has no Bluetooth permission"
            )
        case .bluetoothUnavailable:
            return String(
                localized: "Bluetooth Unavailable",
                comment: "Pump unreachable because Bluetooth is otherwise unusable"
            )
        case .pumpUnreachable:
            return String(localized: "Pump Disconnected", comment: "title for pump disconnected notice")
        case .noRecentSync:
            return String(
                localized: "No Recent Pump Data",
                comment: "Pump link is nominally up but nothing has synced recently"
            )
        }
    }

    /// What it means and what to do about it, for the screens with room for a sentence or two.
    func detail(appName: String) -> String {
        switch self {
        case .bluetoothOff:
            return String(
                format: String(
                    localized: "%@ cannot reach your pump while Bluetooth is off. Your pump keeps delivering insulin from its own settings. Turn Bluetooth on in your phone's Settings app.",
                    comment: "detail for the Bluetooth off notice"
                ),
                appName
            )
        case .bluetoothUnauthorized:
            return String(
                format: String(
                    localized: "%@ does not have permission to use Bluetooth, so it cannot reach your pump. Your pump keeps delivering insulin from its own settings. Allow Bluetooth for the app in your phone's Settings app.",
                    comment: "detail for the Bluetooth permission notice"
                ),
                appName
            )
        case .bluetoothUnavailable:
            return String(
                localized: "Your phone's Bluetooth is not usable right now, so your pump cannot be reached. Your pump keeps delivering insulin from its own settings.",
                comment: "detail for the Bluetooth unavailable notice"
            )
        case .pumpUnreachable:
            return String(
                format: String(
                    localized: "%@ is not connected to your pump, so it cannot read from it or send it anything. Your pump keeps delivering insulin from its own settings. Keep the pump nearby and powered on — reconnection is automatic.",
                    comment: "detail for the pump disconnected notice"
                ),
                appName
            )
        case .noRecentSync:
            return String(
                format: String(
                    localized: "Your pump has not sent %@ an update recently, so the values shown may be out of date. Your pump keeps delivering insulin from its own settings.",
                    comment: "detail for the stale pump data notice"
                ),
                appName
            )
        }
    }

    /// SF Symbol for the home-screen status highlight.
    var imageName: String {
        switch self {
        case .bluetoothOff, .bluetoothUnauthorized, .bluetoothUnavailable:
            return "exclamationmark.circle.fill"
        case .pumpUnreachable, .noRecentSync:
            return "antenna.radiowaves.left.and.right.slash"
        }
    }
}
