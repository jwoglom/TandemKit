import Foundation

/// Request the settings for a specific insulin delivery profile ID.
public class IDPSettingsRequest: Message {
    public static let props = MessageProps(
        opCode: 64,
        size: 1,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var idpId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        idpId = Int(cargo[0])
    }

    public init(idpId: Int) {
        cargo = Bytes.firstByteLittleEndian(idpId)
        self.idpId = idpId
    }
}

/// Response describing the insulin delivery profile settings.
public class IDPSettingsResponse: Message {
    public static let props = MessageProps(
        opCode: 65,
        size: 23,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var idpId: Int
    public var name: String
    public var numberOfProfileSegments: Int
    public var insulinDuration: Int
    public var maxBolus: Int
    public var carbEntry: Bool

    public required init(cargo: Data) {
        self.cargo = cargo
        idpId = Int(cargo[0])
        name = Bytes.readString(cargo, 1, 16)
        numberOfProfileSegments = Int(cargo[17])
        insulinDuration = Bytes.readShort(cargo, 18)
        maxBolus = Bytes.readShort(cargo, 20)
        carbEntry = cargo[22] != 0
    }

    public init(idpId: Int, name: String, numberOfProfileSegments: Int, insulinDuration: Int, maxBolus: Int, carbEntry: Bool) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(idpId),
            Bytes.writeString(name, 16),
            Bytes.firstByteLittleEndian(numberOfProfileSegments),
            Bytes.firstTwoBytesLittleEndian(insulinDuration),
            Bytes.firstTwoBytesLittleEndian(maxBolus),
            Bytes.firstByteLittleEndian(carbEntry ? 1 : 0)
        )
        self.idpId = idpId
        self.name = name
        self.numberOfProfileSegments = numberOfProfileSegments
        self.insulinDuration = insulinDuration
        self.maxBolus = maxBolus
        self.carbEntry = carbEntry
    }
}
