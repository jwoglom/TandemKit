import Foundation

/// Request the most recent Basal-IQ alert info from the pump.
public class BasalIQAlertInfoRequest: Message {
    public static let props = MessageProps(
        opCode: 102,
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }
}

/// Response containing the Basal-IQ alert identifier.
public class BasalIQAlertInfoResponse: Message {
    public static let props = MessageProps(
        opCode: 103,
        size: 4,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var alertId: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        alertId = Bytes.readUint32(cargo, 0)
    }

    public init(alertId: UInt32) {
        cargo = Bytes.toUint32(alertId)
        self.alertId = alertId
    }

    /// The enum alert associated with the alertId, if known.
    public var alert: BasalIQAlert? {
        BasalIQAlert(rawValue: alertId)
    }

    /// Basal-IQ alert types.
    public enum BasalIQAlert: UInt32, CaseIterable {
        case NO_ALERT = 0
        case INSULIN_SUSPENDED_ALERT = 24576
        case INSULIN_RESUMED_ALERT = 24577
        case INSULIN_RESUMED_TIMEOUT = 24578
    }
}
