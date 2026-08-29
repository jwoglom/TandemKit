import CoreBluetooth
import Foundation

/// Why the app cannot talk to the pump right now.
///
/// The pump link is meant to be continuously up — `TandemBluetoothManager` reconnects on its own
/// after a drop — so any value here means pump readings have stopped refreshing and no command can
/// be delivered. Each case is a distinct thing to tell the user, because each has a different
/// remedy: turning the radio back on, granting permission, or moving the pump closer.
public enum PumpConnectionIssue: Equatable {
    /// The phone's Bluetooth radio is switched off, so nothing can reach the pump.
    case bluetoothOff
    /// Bluetooth permission was never granted to this app, or was revoked in Settings.
    case bluetoothUnauthorized
    /// Bluetooth is unusable for another reason: the stack is resetting, the hardware does not
    /// support it, or CoreBluetooth has not reported a state yet.
    case bluetoothUnavailable
    /// The radio is fine but there is no session with the pump — usually out of range, asleep, or
    /// powered off. The driver keeps retrying on its own.
    case pumpUnreachable
    /// CoreBluetooth still reports a link, but no sync has completed in long enough that the
    /// connection can no longer be trusted. A session that is up but no longer carrying traffic
    /// looks exactly like a healthy one from the link's point of view, so the age of the last
    /// completed sync is the only evidence that it is not.
    case noRecentSync
}

public extension TandemPumpManager {
    /// How long without a completed sync before a nominally-connected link is treated as lost, and
    /// how long a dropped link has to stay down before it is worth putting on the host app's home
    /// screen. Three of Loop's ~5-minute cycles: long enough that auto-reconnect has plainly
    /// failed, short enough that the user hears about it while it still matters.
    static let connectionStaleThreshold: TimeInterval = .minutes(15)

    /// Why the app cannot talk to the pump, or nil when the link is up and carrying traffic.
    ///
    /// This is the immediate truth, reported the moment it changes. It is what the pump's own
    /// settings and troubleshooting screens show, where the user has gone looking for exactly this.
    var connectionIssue: PumpConnectionIssue? {
        switch bluetooth.bluetoothState {
        case .poweredOff:
            return .bluetoothOff
        case .unauthorized:
            return .bluetoothUnauthorized
        case .unsupported, .resetting:
            return .bluetoothUnavailable
        case .poweredOn, .unknown:
            // `.unknown` is what CoreBluetooth reports until the central finishes starting up,
            // which is a normal transient at launch rather than a fault of its own. Either way the
            // link state below is the more specific answer.
            break
        @unknown default:
            break
        }

        guard state.isConnected else {
            return .pumpUnreachable
        }

        if let lastSync = state.lastReconciliation,
           Date.now.timeIntervalSince(lastSync) > Self.connectionStaleThreshold
        {
            return .noRecentSync
        }

        return nil
    }

    /// `connectionIssue` narrowed to what is worth interrupting the host app's home screen over.
    ///
    /// A radio-level problem qualifies immediately: it is definite, it is the user's to fix, and it
    /// will not clear on its own. A dropped link does not, until it has lasted long enough to cost
    /// loop cycles — auto-reconnect papers over brief drops in seconds, and flashing a red banner
    /// each time would teach the user to ignore the one that matters. A pump that has never synced
    /// is still being set up, so it does not qualify either.
    var sustainedConnectionIssue: PumpConnectionIssue? {
        guard let issue = connectionIssue else {
            return nil
        }

        switch issue {
        case .bluetoothOff, .bluetoothUnauthorized, .bluetoothUnavailable, .noRecentSync:
            return issue
        case .pumpUnreachable:
            guard let lastSync = state.lastReconciliation,
                  Date.now.timeIntervalSince(lastSync) > Self.connectionStaleThreshold
            else {
                return nil
            }
            return issue
        }
    }
}
