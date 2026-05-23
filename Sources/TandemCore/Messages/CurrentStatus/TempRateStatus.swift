import Foundation

/// Request the current temporary basal rate status with extended fields.
public class TempRateStatusRequest: Message {
    public static let props = MessageProps(
        opCode: 30,
        size: 0,
        type: .Request,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "TempRateStatusRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response with temporary basal rate status including pump reset timing.
///
/// Binary layout (16 bytes):
///   byte  0:     active (bool)
///   bytes 1-2:   tempRateId (uint16 LE)
///   byte  3:     percentage (uint8)
///   bytes 4-7:   startTimeRaw (uint32 LE, seconds since pump epoch)
///   bytes 8-11:  secondsSincePumpReset (uint32 LE)
///   bytes 12-15: duration (uint32 LE)
public class TempRateStatusResponse: Message {
    public static let props = MessageProps(
        opCode: 31,
        size: 16,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var active: Bool
    public var tempRateId: Int
    public var percentage: Int
    public var startTimeRaw: UInt32
    public var secondsSincePumpReset: UInt32
    public var duration: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        active = cargo[0] != 0
        tempRateId = Bytes.readShort(cargo, 1)
        percentage = Int(cargo[3])
        startTimeRaw = Bytes.readUint32(cargo, 4)
        secondsSincePumpReset = Bytes.readUint32(cargo, 8)
        duration = Bytes.readUint32(cargo, 12)
    }

    public init(
        active: Bool,
        tempRateId: Int,
        percentage: Int,
        startTimeRaw: UInt32,
        secondsSincePumpReset: UInt32,
        duration: UInt32
    ) {
        cargo = Bytes.combine(
            Data([active ? 1 : 0]),
            Bytes.firstTwoBytesLittleEndian(tempRateId),
            Bytes.firstByteLittleEndian(percentage),
            Bytes.toUint32(startTimeRaw),
            Bytes.toUint32(secondsSincePumpReset),
            Bytes.toUint32(duration)
        )
        self.active = active
        self.tempRateId = tempRateId
        self.percentage = percentage
        self.startTimeRaw = startTimeRaw
        self.secondsSincePumpReset = secondsSincePumpReset
        self.duration = duration
    }

    public var startTime: Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(startTimeRaw))
    }

    public var description: String {
        "TempRateStatusResponse(cargo=\(cargo.hexadecimalString), active=\(active), tempRateId=\(tempRateId), percentage=\(percentage), startTimeRaw=\(startTimeRaw), secondsSincePumpReset=\(secondsSincePumpReset), duration=\(duration))"
    }
}
