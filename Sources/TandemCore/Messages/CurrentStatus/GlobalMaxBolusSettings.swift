import Foundation

/// Request the global maximum bolus settings.
public class GlobalMaxBolusSettingsRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-116)),
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

/// Response containing the global maximum bolus settings.
public class GlobalMaxBolusSettingsResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-115)),
        size: 4,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var maxBolus: Int
    public var maxBolusDefault: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        maxBolus = Bytes.readShort(cargo, 0)
        maxBolusDefault = Bytes.readShort(cargo, 2)
    }

    public init(maxBolus: Int, maxBolusDefault: Int) {
        cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(maxBolus),
            Bytes.firstTwoBytesLittleEndian(maxBolusDefault)
        )
        self.maxBolus = maxBolus
        self.maxBolusDefault = maxBolusDefault
    }
}
