import Foundation

/// Request to enable or change Control-IQ settings.
public class ChangeControlIQSettingsRequest: PumpRequest {
    public typealias Response = ChangeControlIQSettingsResponse

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-54)),
        size: 6,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var enabled: Bool
    public var weightLbs: Int
    public var totalDailyInsulinUnits: Int
    public var changedFields: ControlIQSettingsFields

    public required init(cargo: Data) {
        self.cargo = cargo
        enabled = cargo[0] == 1
        weightLbs = Bytes.readShort(cargo, 1)
        totalDailyInsulinUnits = Int(cargo[4])
        changedFields = ControlIQSettingsFields(rawValue: cargo[5])
    }

    public init(
        enabled: Bool,
        weightLbs: Int,
        totalDailyInsulinUnits: Int,
        changedFields: ControlIQSettingsFields = .enabled
    ) {
        cargo = Bytes.combine(
            Data([enabled ? 1 : 0]),
            Bytes.firstTwoBytesLittleEndian(weightLbs),
            Data([1, UInt8(totalDailyInsulinUnits & 0xFF), changedFields.rawValue])
        )
        self.enabled = enabled
        self.weightLbs = weightLbs
        self.totalDailyInsulinUnits = totalDailyInsulinUnits
        self.changedFields = changedFields
    }

    public var description: String {
        "ChangeControlIQSettingsRequest(cargo=\(cargo.hexadecimalString), enabled=\(enabled), weightLbs=\(weightLbs), totalDailyInsulinUnits=\(totalDailyInsulinUnits), changedFields=\(changedFields.rawValue))"
    }
}

public struct ControlIQSettingsFields: OptionSet, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let enabled = ControlIQSettingsFields(rawValue: 0x01)
    public static let weight = ControlIQSettingsFields(rawValue: 0x02)
    public static let totalDailyInsulin = ControlIQSettingsFields(rawValue: 0x04)
}

/// Response with status after attempting to change Control-IQ settings.
public class ChangeControlIQSettingsResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-53)),
        size: 3,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var status: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        status = Int(cargo[0])
    }

    public init(status: Int) {
        cargo = Data([UInt8(status & 0xFF), 0, 0])
        self.status = status
    }

    public var description: String {
        "ChangeControlIQSettingsResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
