import Foundation

/// Request to set a site change reminder configuration.
///
/// Cargo layout (7 bytes, little-endian):
///   [0]   enable       uint8   - 0=disabled, 1=enabled
///   [1]   dayCount     uint8   - number of days between site changes
///   [2-5] timeOfDay    uint32  - time of day in minutes since midnight
///   [6]   bitmask      uint8   - change bitmask (bits: 0=enable, 1=dayCount, 2=timeOfDay)
public class SetSiteChangeReminderRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-36)),
        size: 7,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var enable: Bool
    public var dayCount: Int
    public var timeOfDayMinutes: UInt32
    public var bitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        enable = cargo[0] != 0
        dayCount = Int(cargo[1])
        timeOfDayMinutes = Bytes.readUint32(cargo, 2)
        bitmask = Int(cargo[6])
    }

    public init(enable: Bool, dayCount: Int, timeOfDayMinutes: UInt32, bitmask: Int) {
        cargo = SetSiteChangeReminderRequest.buildCargo(
            enable: enable,
            dayCount: dayCount,
            timeOfDayMinutes: timeOfDayMinutes,
            bitmask: bitmask
        )
        self.enable = enable
        self.dayCount = dayCount
        self.timeOfDayMinutes = timeOfDayMinutes
        self.bitmask = bitmask
    }

    public static func buildCargo(enable: Bool, dayCount: Int, timeOfDayMinutes: UInt32, bitmask: Int) -> Data {
        Bytes.combine(
            Data([enable ? 1 : 0]),
            Data([UInt8(dayCount & 0xFF)]),
            Bytes.toUint32(timeOfDayMinutes),
            Data([UInt8(bitmask & 0xFF)])
        )
    }

    public var description: String {
        "SetSiteChangeReminderRequest(cargo=\(cargo.hexadecimalString), enable=\(enable), dayCount=\(dayCount), timeOfDayMinutes=\(timeOfDayMinutes), bitmask=\(bitmask))"
    }
}

/// Response after setting a site change reminder.
public class SetSiteChangeReminderResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-35)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var status: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        status = Int(cargo[0])
    }

    public init(status: Int) {
        cargo = Data([UInt8(status & 0xFF)])
        self.status = status
    }

    public var description: String {
        "SetSiteChangeReminderResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
