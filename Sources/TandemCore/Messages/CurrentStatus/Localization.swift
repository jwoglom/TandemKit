import Foundation

/// Request pump localization settings.
public class LocalizationRequest: PumpRequest {
    public typealias Response = LocalizationResponse

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-90)),
        size: 0,
        type: .Request,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "LocalizationRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response containing localization preferences.
public class LocalizationResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-89)),
        size: 7,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var glucoseUOM: Int
    public var languageSelected: Int
    public var regionSetting: Int
    public var languagesAvailableBitmask: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        glucoseUOM = Int(cargo[0])
        languageSelected = Int(cargo[1])
        regionSetting = Int(cargo[2])
        languagesAvailableBitmask = Bytes.readUint32(cargo, 3)
    }

    public init(glucoseUOM: Int, languageSelected: Int, regionSetting: Int, languagesAvailableBitmask: UInt32) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(glucoseUOM),
            Bytes.firstByteLittleEndian(languageSelected),
            Bytes.firstByteLittleEndian(regionSetting),
            Bytes.toUint32(languagesAvailableBitmask)
        )
        self.glucoseUOM = glucoseUOM
        self.languageSelected = languageSelected
        self.regionSetting = regionSetting
        self.languagesAvailableBitmask = languagesAvailableBitmask
    }

    public var description: String {
        "LocalizationResponse(cargo=\(cargo.hexadecimalString), glucoseUOM=\(glucoseUOM), languageSelected=\(languageSelected), regionSetting=\(regionSetting), languagesAvailableBitmask=\(languagesAvailableBitmask))"
    }
}
