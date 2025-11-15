import Foundation

/// Request pump localization settings.
public class LocalizationRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-90)),
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

/// Response containing localization preferences.
public class LocalizationResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-89)),
        size: 7,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var glucoseOUM: Int
    public var regionSetting: Int
    public var languageSelected: Int
    public var languagesAvailableBitmask: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        glucoseOUM = Int(cargo[0])
        regionSetting = Int(cargo[1])
        languageSelected = Int(cargo[2])
        languagesAvailableBitmask = Bytes.readUint32(cargo, 3)
    }

    public init(glucoseOUM: Int, regionSetting: Int, languageSelected: Int, languagesAvailableBitmask: UInt32) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(glucoseOUM),
            Bytes.firstByteLittleEndian(regionSetting),
            Bytes.firstByteLittleEndian(languageSelected),
            Bytes.toUint32(languagesAvailableBitmask)
        )
        self.glucoseOUM = glucoseOUM
        self.regionSetting = regionSetting
        self.languageSelected = languageSelected
        self.languagesAvailableBitmask = languagesAvailableBitmask
    }
}
