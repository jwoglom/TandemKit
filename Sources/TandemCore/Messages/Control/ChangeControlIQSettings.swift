import Foundation

/// Request to enable or change Control-IQ settings.
public class ChangeControlIQSettingsRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-54)),
        size: 6,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var enabled: Bool
    public var weightLbs: Int
    public var totalDailyInsulinUnits: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        enabled = cargo[0] == 1
        weightLbs = Bytes.readShort(cargo, 1)
        totalDailyInsulinUnits = Int(cargo[4])
    }

    public init(enabled: Bool, weightLbs: Int, totalDailyInsulinUnits: Int) {
        cargo = Bytes.combine(
            Data([enabled ? 1 : 0]),
            Bytes.firstTwoBytesLittleEndian(weightLbs),
            Data([1, UInt8(totalDailyInsulinUnits & 0xFF), 1])
        )
        self.enabled = enabled
        self.weightLbs = weightLbs
        self.totalDailyInsulinUnits = totalDailyInsulinUnits
    }
}

/// Response with status after attempting to change Control-IQ settings.
public class ChangeControlIQSettingsResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-53)),
        size: 3,
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
        cargo = Data([UInt8(status & 0xFF), 0, 0])
        self.status = status
    }
}
