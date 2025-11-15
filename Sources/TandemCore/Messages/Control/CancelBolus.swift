import Foundation

/// Request to cancel an in-progress bolus.
public class CancelBolusRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-96)),
        size: 4,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .apiV2_5
    )

    public var cargo: Data
    public var bolusId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        bolusId = Bytes.readShort(cargo, 0)
    }

    public init(bolusId: Int) {
        cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(bolusId),
            Data([0, 0])
        )
        self.bolusId = bolusId
    }
}

/// Response after attempting to cancel a bolus.
public class CancelBolusResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-95)),
        size: 5,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .apiV2_5
    )

    public var cargo: Data
    public var statusId: Int
    public var bolusId: Int
    public var reasonId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        statusId = Int(cargo[0])
        bolusId = Bytes.readShort(cargo, 1)
        reasonId = Bytes.readShort(cargo, 3)
    }

    public init(statusId: Int, bolusId: Int, reasonId: Int) {
        cargo = Bytes.combine(
            Data([UInt8(statusId & 0xFF)]),
            Bytes.firstTwoBytesLittleEndian(bolusId),
            Bytes.firstTwoBytesLittleEndian(reasonId)
        )
        self.statusId = statusId
        self.bolusId = bolusId
        self.reasonId = reasonId
    }

    public enum CancelStatus: Int {
        case success = 0
        case failed = 1
    }

    public enum CancelReason: Int {
        case noError = 0
        case invalidOrAlreadyDelivered = 2
    }

    public var status: CancelStatus? { CancelStatus(rawValue: statusId) }
    public var reason: CancelReason? { CancelReason(rawValue: reasonId) }

    /// Returns true when the bolus was cancelled successfully without error.
    public var wasCancelled: Bool {
        status == .success && reason == .noError
    }
}
