import Foundation

/// User-facing wording for each way the pump can be out of reach.
///
/// Every detail says what is still happening to their insulin: losing the connection stops the app
/// from reading or commanding the pump, but not the pump itself, which goes on delivering from its
/// own settings. That is the first thing someone reading a red banner needs to know.
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
        case .handshakeFailing:
            return String(
                localized: "Pump Pairing Problem",
                comment: "Pump keeps ending the secure connection while the app connects, so the app stopped retrying"
            )
        case .noRecentSync:
            return String(
                localized: "No Recent Pump Data",
                comment: "Pump link is nominally up but nothing has synced recently"
            )
        }
    }

    /// What it means and what to do, for the screens with room for a sentence or two.
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
        case .handshakeFailing:
            return String(
                format: String(
                    localized: "%1$@ tried to connect to your pump several times in a row, but each time the pump ended the connection while it was being secured, so %1$@ stopped trying on its own. This can happen when another phone or app is also paired with your pump. Your pump keeps delivering insulin from its own settings. Close or turn off any other app or device connected to your pump, then give %1$@ a few minutes to connect again. An app connected to your pump can also change its settings, such as basal rates, so check that they are what you expect. If this keeps happening, you may need to remove the pump from %1$@ and pair it again.",
                    comment: "detail for the pump pairing problem notice; the placeholder is the app's name"
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
        case .bluetoothOff, .bluetoothUnauthorized, .bluetoothUnavailable, .handshakeFailing:
            return "exclamationmark.circle.fill"
        case .pumpUnreachable, .noRecentSync:
            return "antenna.radiowaves.left.and.right.slash"
        }
    }
}
