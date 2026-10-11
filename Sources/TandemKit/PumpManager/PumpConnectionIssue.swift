import CoreBluetooth
import Foundation

/// Why the app cannot talk to the pump right now. Cases are kept distinct because their remedies
/// are: turning the radio back on, granting permission, or moving the pump closer.
public enum PumpConnectionIssue: Equatable {
    case bluetoothOff
    case bluetoothUnauthorized
    /// Resetting, unsupported hardware, or no state reported yet.
    case bluetoothUnavailable
    /// Radio is fine, but there is no session with the pump. The driver keeps retrying.
    case pumpUnreachable
    /// The pump has ended the secure handshake several times in a row, and the driver has stopped
    /// reconnecting on its own. Retrying faster does not help; something about the pairing does.
    case handshakeFailing
    /// A link that is up but no longer carrying traffic looks healthy from the link's point of
    /// view; the age of the last completed sync is the only evidence that it is not.
    case noRecentSync
}

public extension TandemPumpManager {
    /// Three of Loop's ~5-minute cycles.
    static let connectionStaleThreshold: TimeInterval = .minutes(15)

    /// The immediate truth, as shown on the pump's own settings and troubleshooting screens.
    var connectionIssue: PumpConnectionIssue? {
        switch bluetooth.bluetoothState {
        case .poweredOff:
            return .bluetoothOff
        case .unauthorized:
            return .bluetoothUnauthorized
        case .unsupported, .resetting:
            return .bluetoothUnavailable
        case .poweredOn, .unknown:
            // `.unknown` is the normal transient before the central starts up, not a fault; the
            // link state below is the more specific answer either way.
            break
        @unknown default:
            break
        }

        if bluetooth.isJpakeFailureLimitReached {
            return .handshakeFailing
        }

        guard state.isConnected else {
            return .pumpUnreachable
        }

        if let lastSync = state.lastReconciliation,
           now.timeIntervalSince(lastSync) > Self.connectionStaleThreshold
        {
            return .noRecentSync
        }

        return nil
    }

    /// `connectionIssue` narrowed to what is worth the host app's home screen. Radio problems
    /// qualify immediately — they will not clear on their own, and neither will a handshake the pump
    /// keeps ending, since the driver has stopped retrying it. A dropped link waits until it has
    /// cost loop cycles, so the drops auto-reconnect clears in seconds do not teach the user to
    /// ignore the banner. A pump that has never synced is still being set up.
    var sustainedConnectionIssue: PumpConnectionIssue? {
        guard let issue = connectionIssue else {
            return nil
        }

        switch issue {
        case .bluetoothOff, .bluetoothUnauthorized, .bluetoothUnavailable, .handshakeFailing, .noRecentSync:
            return issue
        case .pumpUnreachable:
            guard let lastSync = state.lastReconciliation,
                  now.timeIntervalSince(lastSync) > Self.connectionStaleThreshold
            else {
                return nil
            }
            return issue
        }
    }
}
