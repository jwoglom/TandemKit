import Foundation

/// Request to configure a Control-IQ sleep schedule slot.
public class SetSleepScheduleRequest: PumpRequest {
    public typealias Response = SetSleepScheduleResponse

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-50)),
        size: 8,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var slot: Int
    public var rawSchedule: Data
    public var changedFields: SleepScheduleFields

    public required init(cargo: Data) {
        self.cargo = cargo
        slot = Int(cargo[0])
        rawSchedule = Bytes.dropLastN(Bytes.dropFirstN(cargo, 1), 1)
        changedFields = SleepScheduleFields(rawValue: cargo[7])
    }

    /// `changedFields` always carries `.base`, as every request the Mobi app sends does.
    public convenience init(slot: Int, schedule: ControlIQSleepScheduleResponse.SleepSchedule, changedFields: SleepScheduleFields) {
        self.init(cargo: Bytes.combine(
            Data([UInt8(slot & 0xFF)]),
            schedule.build(),
            Data([changedFields.union(.base).rawValue])
        ))
    }

    /// Flags the fields that differ from `previous`, the slot as last read from the pump, as the
    /// Mobi app does.
    public convenience init(
        slot: Int,
        previous: ControlIQSleepScheduleResponse.SleepSchedule,
        updated: ControlIQSleepScheduleResponse.SleepSchedule
    ) {
        self.init(slot: slot, schedule: updated, changedFields: SleepScheduleFields.between(previous, updated))
    }

    public var schedule: ControlIQSleepScheduleResponse.SleepSchedule {
        ControlIQSleepScheduleResponse.SleepSchedule(data: rawSchedule, index: 0)
    }

    public var description: String {
        "SetSleepScheduleRequest(cargo=\(cargo.hexadecimalString), slot=\(slot), rawSchedule=\(rawSchedule.hexadecimalString), changedFields=\(changedFields.rawValue))"
    }
}

/// The fields of a `SetSleepScheduleRequest` the pump applies. The pump writes one
/// `AaSleepScheduleChangeHistoryLog` per flagged field.
public struct SleepScheduleFields: OptionSet, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Set by the Mobi app on every request; its meaning is unknown.
    public static let base = SleepScheduleFields(rawValue: 0x01)
    public static let enabled = SleepScheduleFields(rawValue: 0x02)
    public static let activeDays = SleepScheduleFields(rawValue: 0x04)
    public static let startTime = SleepScheduleFields(rawValue: 0x08)
    public static let endTime = SleepScheduleFields(rawValue: 0x10)

    /// The fields that differ, not including `.base`.
    public static func between(
        _ previous: ControlIQSleepScheduleResponse.SleepSchedule,
        _ updated: ControlIQSleepScheduleResponse.SleepSchedule
    ) -> SleepScheduleFields {
        var fields: SleepScheduleFields = []
        if previous.enabled != updated.enabled { fields.insert(.enabled) }
        if previous.activeDays != updated.activeDays { fields.insert(.activeDays) }
        if previous.startTime != updated.startTime { fields.insert(.startTime) }
        if previous.endTime != updated.endTime { fields.insert(.endTime) }
        return fields
    }
}

/// Response indicating whether the sleep schedule was saved.
public class SetSleepScheduleResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-49)),
        size: 1,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
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

    public var description: String {
        "SetSleepScheduleResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
