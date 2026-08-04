import Foundation

/// Request to enable or change Control-IQ settings.
///
/// Cargo layout: `enabled(1) | weight(2, LE) | weightUnit(1) | totalDailyInsulin(1) | trailingFlag(1)`.
///
/// `weight` is unit-less on the wire — `weightUnit` is what gives it meaning, and
/// it must match the unit the weight was read in. Writing a weight that was read
/// from the pump in kilograms back as pounds (or the reverse) silently rewrites
/// the user's stored body weight, which Control-IQ uses to derive its dosing
/// constraints.
public class ChangeControlIQSettingsRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-54)),
        size: 6,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    /// Value observed in the trailing cargo byte of every captured request. Its
    /// meaning is not known; it is preserved rather than reinterpreted.
    public static let defaultTrailingFlag = 1

    public var cargo: Data
    public var enabled: Bool
    /// Body weight expressed in `weightUnit`.
    public var weight: Int
    public var weightUnitRaw: Int
    public var totalDailyInsulinUnits: Int
    /// Trailing cargo byte of unknown meaning. See `defaultTrailingFlag`.
    public var trailingFlag: Int

    public var weightUnit: ControlIQWeightUnit? { ControlIQWeightUnit(rawValue: weightUnitRaw) }

    public required init(cargo: Data) {
        self.cargo = cargo
        enabled = cargo[0] == 1
        weight = Bytes.readShort(cargo, 1)
        weightUnitRaw = Int(cargo[3])
        totalDailyInsulinUnits = Int(cargo[4])
        trailingFlag = Int(cargo[5])
    }

    public init(
        enabled: Bool,
        weight: Int,
        weightUnit: ControlIQWeightUnit,
        totalDailyInsulinUnits: Int,
        trailingFlag: Int = ChangeControlIQSettingsRequest.defaultTrailingFlag
    ) {
        cargo = Bytes.combine(
            Data([enabled ? 1 : 0]),
            Bytes.firstTwoBytesLittleEndian(weight),
            Data([
                UInt8(weightUnit.rawValue & 0xFF),
                UInt8(totalDailyInsulinUnits & 0xFF),
                UInt8(trailingFlag & 0xFF)
            ])
        )
        self.enabled = enabled
        self.weight = weight
        weightUnitRaw = weightUnit.rawValue
        self.totalDailyInsulinUnits = totalDailyInsulinUnits
        self.trailingFlag = trailingFlag
    }

    public var description: String {
        "ChangeControlIQSettingsRequest(cargo=\(cargo.hexadecimalString), enabled=\(enabled), weight=\(weight), weightUnitRaw=\(weightUnitRaw), totalDailyInsulinUnits=\(totalDailyInsulinUnits), trailingFlag=\(trailingFlag))"
    }
}

/// Response with status after attempting to change Control-IQ settings.
///
/// A non-zero `status` means the pump refused the change — most commonly because
/// Control-IQ was being enabled without a usable body weight or total daily
/// insulin on the pump. The individual status values have not been catalogued
/// yet, so callers should surface the raw value rather than translate it; the
/// debug message sender can be used to map codes against a real pump.
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
