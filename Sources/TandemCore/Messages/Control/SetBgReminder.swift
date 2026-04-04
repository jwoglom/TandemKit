import Foundation

/// Request to set a blood glucose reminder configuration.
///
/// Cargo layout (9 bytes, little-endian):
///   [0]   reminderType        uint8   - 0=HIGH, 1=LOW, 2=AFTER_BOLUS
///   [1]   enabledBGReminder   uint8   - 0=disabled, 1=enabled
///   [2-3] reminderThreshold   uint16  - BG threshold in mg/dL
///   [4-7] reminderMinutes     uint32  - reminder time in minutes
///   [8]   bitmask             uint8   - change bitmask (bits: 0=enabled, 1=threshold, 2=minutes)
public class SetBgReminderRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-40)),
        size: 9,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public enum ReminderType: Int {
        case high = 0
        case low = 1
        case afterBolus = 2
    }

    public var cargo: Data
    public var reminderType: Int
    public var enabledBGReminder: Bool
    public var reminderThreshold: Int
    public var reminderMinutes: UInt32
    public var bitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        reminderType = Int(cargo[0])
        enabledBGReminder = cargo[1] != 0
        reminderThreshold = Bytes.readShort(cargo, 2)
        reminderMinutes = Bytes.readUint32(cargo, 4)
        bitmask = Int(cargo[8])
    }

    public init(reminderType: Int, enabledBGReminder: Bool, reminderThreshold: Int, reminderMinutes: UInt32, bitmask: Int) {
        cargo = SetBgReminderRequest.buildCargo(
            reminderType: reminderType,
            enabledBGReminder: enabledBGReminder,
            reminderThreshold: reminderThreshold,
            reminderMinutes: reminderMinutes,
            bitmask: bitmask
        )
        self.reminderType = reminderType
        self.enabledBGReminder = enabledBGReminder
        self.reminderThreshold = reminderThreshold
        self.reminderMinutes = reminderMinutes
        self.bitmask = bitmask
    }

    public static func buildCargo(reminderType: Int, enabledBGReminder: Bool, reminderThreshold: Int, reminderMinutes: UInt32, bitmask: Int) -> Data {
        Bytes.combine(
            Data([UInt8(reminderType & 0xFF)]),
            Data([enabledBGReminder ? 1 : 0]),
            Bytes.firstTwoBytesLittleEndian(reminderThreshold),
            Bytes.toUint32(reminderMinutes),
            Data([UInt8(bitmask & 0xFF)])
        )
    }

    public var description: String {
        "SetBgReminderRequest(cargo=\(cargo.hexadecimalString), reminderType=\(reminderType), enabledBGReminder=\(enabledBGReminder), reminderThreshold=\(reminderThreshold), reminderMinutes=\(reminderMinutes), bitmask=\(bitmask))"
    }
}

/// Response after setting a BG reminder.
public class SetBgReminderResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-39)),
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
        "SetBgReminderResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
