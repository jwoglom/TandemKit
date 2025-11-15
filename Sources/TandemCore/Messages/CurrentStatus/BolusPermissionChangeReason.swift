import Foundation

/// Request information on why bolus permission changed for a given bolus.
public class BolusPermissionChangeReasonRequest: Message {
    public static let props = MessageProps(
        opCode: 168,
        size: 2,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .apiFuture
    )

    public var cargo: Data
    public var bolusId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        bolusId = Bytes.readShort(cargo, 0)
    }

    public init(bolusId: Int) {
        cargo = Bytes.firstTwoBytesLittleEndian(bolusId)
        self.bolusId = bolusId
    }
}

/// Response with details on bolus permission change reason.
public class BolusPermissionChangeReasonResponse: Message {
    public static let props = MessageProps(
        opCode: 169,
        size: 5,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .apiFuture
    )

    public var cargo: Data
    public var bolusId: Int
    public var isAcked: Bool
    public var lastChangeReasonId: Int
    public var currentPermissionHolder: Bool

    public required init(cargo: Data) {
        self.cargo = cargo
        bolusId = Bytes.readShort(cargo, 0)
        isAcked = cargo[2] != 0
        lastChangeReasonId = Int(cargo[3])
        currentPermissionHolder = cargo[4] != 0
    }

    public init(bolusId: Int, isAcked: Bool, lastChangeReasonId: Int, currentPermissionHolder: Bool) {
        cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(bolusId),
            Bytes.firstByteLittleEndian(isAcked ? 1 : 0),
            Bytes.firstByteLittleEndian(lastChangeReasonId),
            Bytes.firstByteLittleEndian(currentPermissionHolder ? 1 : 0)
        )
        self.bolusId = bolusId
        self.isAcked = isAcked
        self.lastChangeReasonId = lastChangeReasonId
        self.currentPermissionHolder = currentPermissionHolder
    }

    /// Convenience accessor mapping `lastChangeReasonId` to `ChangeReason`.
    public var lastChangeReason: ChangeReason? {
        ChangeReason(rawValue: lastChangeReasonId)
    }

    /// Reasons a bolus permission may change.
    public enum ChangeReason: Int, CaseIterable {
        case GRANTED = 0
        case RELEASED = 1
        case REVOKED_PRIORITY = 2
        case REVOKED_TIMEOUT = 3
        case REVOKED_SETTINGS_CHANGED = 4
        case REVOKED_PUMP_SUSPEND = 5
        case REVOKED_INVALID_REQUEST = 6
        case UNKNOWN = 7
    }
}
