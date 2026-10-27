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
    func detail(
        appName: String,
        lastKnownDelivery: LastKnownBasalDelivery? = nil,
        lastSync: Date? = nil,
        now: Date = Date()
    ) -> String {
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
            if let lastKnownDelivery {
                return lastKnownDelivery.localizedDescription(appName: appName, now: now)
            }
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
                    localized: "Your pump is rejecting connections from this device. This may be caused by a Bluetooth connection problem, pairing the pump to a different device, or running multiple apps that control the pump on the same device. Please disconnect the pump from all apps and re-pair to resume %@ controlling insulin delivery. Your pump's profile settings are used until this is resolved.",
                    comment: "detail for the pump pairing problem notice; the placeholder is the app's name"
                ),
                appName
            )
        case .noRecentSync:
            guard let lastSync else {
                return String(
                    format: String(
                        localized: "Your pump has not sent %@ an update recently, so the values shown may be out of date. Your pump keeps delivering insulin from its own settings.",
                        comment: "detail for the stale pump data notice"
                    ),
                    appName
                )
            }
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = abs(lastSync.timeIntervalSince(now)) < .hours(12) ? .none : .medium
            return String(
                format: String(
                    localized: "Your pump has not sent %1$@ an update since %2$@ (%3$@), so the values shown may be out of date. Your pump keeps delivering insulin from its own settings.",
                    comment: "detail for the stale pump data notice; the placeholders are the app's name, the time of the last update and how long ago that was"
                ),
                appName,
                formatter.string(from: lastSync),
                LastKnownBasalDelivery.elapsedDescription(now.timeIntervalSince(lastSync))
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
