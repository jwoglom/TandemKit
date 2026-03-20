import Foundation

/// Request to set a missed meal bolus reminder configuration.
///
/// Cargo layout (8 bytes, little-endian):
///   [0]   reminderIndex    uint8   - reminder slot index
///   [1]   enabledReminder  uint8   - 0=disabled, 1=enabled
///   [2-3] startTime        uint16  - start time in minutes since midnight
///   [4-5] endTime          uint16  - end time in minutes since midnight
///   [6]   selectedDays     uint8   - days-of-week bitmask (bit 0=Mon, 1=Tue, ..., 6=Sun)
///   [7]   bitmask          uint8   - change bitmask (bits: 0=enabled, 1=startTime, 2=endTime, 3=selectedDays)
public class SetMissedMealBolusReminderRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-38)),
        size: 8,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var reminderIndex: Int
    public var enabledReminder: Bool
    public var startTime: Int
    public var endTime: Int
    public var selectedDays: Int
    public var bitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        reminderIndex = Int(cargo[0])
        enabledReminder = cargo[1] != 0
        startTime = Bytes.readShort(cargo, 2)
        endTime = Bytes.readShort(cargo, 4)
        selectedDays = Int(cargo[6])
        bitmask = Int(cargo[7])
    }

    public init(reminderIndex: Int, enabledReminder: Bool, startTime: Int, endTime: Int, selectedDays: Int, bitmask: Int) {
        cargo = SetMissedMealBolusReminderRequest.buildCargo(
            reminderIndex: reminderIndex,
            enabledReminder: enabledReminder,
            startTime: startTime,
            endTime: endTime,
            selectedDays: selectedDays,
            bitmask: bitmask
        )
        self.reminderIndex = reminderIndex
        self.enabledReminder = enabledReminder
        self.startTime = startTime
        self.endTime = endTime
        self.selectedDays = selectedDays
        self.bitmask = bitmask
    }

    public static func buildCargo(reminderIndex: Int, enabledReminder: Bool, startTime: Int, endTime: Int, selectedDays: Int, bitmask: Int) -> Data {
        Bytes.combine(
            Data([UInt8(reminderIndex & 0xFF)]),
            Data([enabledReminder ? 1 : 0]),
            Bytes.firstTwoBytesLittleEndian(startTime),
            Bytes.firstTwoBytesLittleEndian(endTime),
            Data([UInt8(selectedDays & 0xFF)]),
            Data([UInt8(bitmask & 0xFF)])
        )
    }

    public var description: String {
        "SetMissedMealBolusReminderRequest(cargo=\(cargo.hexadecimalString), reminderIndex=\(reminderIndex), enabledReminder=\(enabledReminder), startTime=\(startTime), endTime=\(endTime), selectedDays=\(selectedDays), bitmask=\(bitmask))"
    }
}

/// Response after setting a missed meal bolus reminder.
public class SetMissedMealBolusReminderResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-37)),
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
        "SetMissedMealBolusReminderResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
