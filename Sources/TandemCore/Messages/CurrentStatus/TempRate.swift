import Foundation

/// Request the current temporary basal rate information.
public class TempRateRequest: Message {
    public static let props = MessageProps(
        opCode: 42,
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

/// Response containing temporary basal rate details.
public class TempRateResponse: Message {
    public static let props = MessageProps(
        opCode: 43,
        size: 10,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var active: Bool
    public var percentage: Int
    public var startTimeRaw: UInt32
    public var duration: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        active = cargo[0] != 0
        percentage = Int(cargo[1])
        startTimeRaw = Bytes.readUint32(cargo, 2)
        duration = Bytes.readUint32(cargo, 6)
    }

    public init(active: Bool, percentage: Int, startTimeRaw: UInt32, duration: UInt32) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(active ? 1 : 0),
            Bytes.firstByteLittleEndian(percentage),
            Bytes.toUint32(startTimeRaw),
            Bytes.toUint32(duration)
        )
        self.active = active
        self.percentage = percentage
        self.startTimeRaw = startTimeRaw
        self.duration = duration
    }

    /// Convenience accessor converting `startTimeRaw` to `Date`.
    public var startTime: Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(startTimeRaw))
    }
}
