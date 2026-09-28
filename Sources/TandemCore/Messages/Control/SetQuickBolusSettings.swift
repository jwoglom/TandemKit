import Foundation

/// Request to configure quick bolus button behavior. The pump applies only the fields named in
/// `changedFields`; the Tandem app fills the rest with the pump's current values (#428).
public class SetQuickBolusSettingsRequest: PumpRequest {
    public typealias Response = SetQuickBolusSettingsResponse

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-46)),
        size: 7,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    public static let supportedIncrementUnits = [500, 1000, 2000, 5000]
    public static let supportedIncrementCarbs = [2000, 5000, 10000, 15000]

    public var cargo: Data
    public var enabled: Bool
    public var modeRaw: Int
    /// Milliunits.
    public var incrementUnits: Int
    /// Milligrams.
    public var incrementCarbs: Int
    public var changedFields: QuickBolusSettingsFields

    public required init(cargo: Data) {
        self.cargo = cargo
        enabled = cargo[0] == 1
        modeRaw = Int(cargo[1])
        incrementUnits = Bytes.readShort(cargo, 2)
        incrementCarbs = Bytes.readShort(cargo, 4)
        changedFields = QuickBolusSettingsFields(rawValue: cargo[6])
    }

    public init(
        enabled: Bool,
        mode: QuickBolusMode,
        incrementUnits: Int,
        incrementCarbs: Int,
        changedFields: QuickBolusSettingsFields
    ) {
        cargo = Bytes.combine(
            Data([UInt8(enabled ? 1 : 0)]),
            Data([UInt8(mode.rawValue)]),
            Bytes.firstTwoBytesLittleEndian(incrementUnits),
            Bytes.firstTwoBytesLittleEndian(incrementCarbs),
            Data([changedFields.rawValue])
        )
        self.enabled = enabled
        modeRaw = mode.rawValue
        self.incrementUnits = incrementUnits
        self.incrementCarbs = incrementCarbs
        self.changedFields = changedFields
    }

    public var mode: QuickBolusMode? { QuickBolusMode(rawValue: modeRaw) }

    public var description: String {
        "SetQuickBolusSettingsRequest(cargo=\(cargo.hexadecimalString), enabled=\(enabled), mode=\(String(describing: mode)), incrementUnits=\(incrementUnits), incrementCarbs=\(incrementCarbs), changedFields=\(changedFields.rawValue))"
    }
}

/// Supported quick bolus modes.
public enum QuickBolusMode: Int {
    case units = 0
    case carbs = 1
}

public struct QuickBolusSettingsFields: OptionSet, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let enabled = QuickBolusSettingsFields(rawValue: 0x01)
    public static let mode = QuickBolusSettingsFields(rawValue: 0x02)
    public static let incrementUnits = QuickBolusSettingsFields(rawValue: 0x04)
    public static let incrementCarbs = QuickBolusSettingsFields(rawValue: 0x08)
}

/// Response indicating if quick bolus settings were updated.
public class SetQuickBolusSettingsResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-45)),
        size: 1,
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
        cargo = Data([UInt8(status & 0xFF)])
        self.status = status
    }

    public var description: String {
        "SetQuickBolusSettingsResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
