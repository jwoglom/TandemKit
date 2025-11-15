import Foundation

/// Request to configure a Control-IQ sleep schedule slot.
public class SetSleepScheduleRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-50)),
        size: 8,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var slot: Int
    public var rawSchedule: Data
    public var flag: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        slot = Int(cargo[0])
        rawSchedule = Bytes.dropLastN(Bytes.dropFirstN(cargo, 1), 1)
        flag = Int(cargo[7])
    }

    public init(slot: Int, rawSchedule: Data, flag: Int) {
        cargo = Bytes.combine(
            Data([UInt8(slot & 0xFF)]),
            rawSchedule,
            Data([UInt8(flag & 0xFF)])
        )
        self.slot = slot
        self.rawSchedule = rawSchedule
        self.flag = flag
    }

    public convenience init(slot: Int, schedule: ControlIQSleepScheduleResponse.SleepSchedule, flag: Int) {
        self.init(slot: slot, rawSchedule: schedule.build(), flag: flag)
    }

    public var schedule: ControlIQSleepScheduleResponse.SleepSchedule {
        ControlIQSleepScheduleResponse.SleepSchedule(data: rawSchedule, index: 0)
    }
}

/// Response indicating whether the sleep schedule was saved.
public class SetSleepScheduleResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-49)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
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
}
