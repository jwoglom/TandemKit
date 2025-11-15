import Foundation

/// Request to update profile-wide settings on an insulin delivery profile.
public class SetIDPSettingsRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-84)),
        size: 6,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var idpId: Int
    public var profileInsulinDuration: Int
    public var profileCarbEntry: Int
    public var changeTypeId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        idpId = Int(cargo[0])
        profileInsulinDuration = Bytes.readShort(cargo, 2)
        profileCarbEntry = Int(cargo[4])
        changeTypeId = Int(cargo[5])
    }

    public init(idpId: Int, profileInsulinDuration: Int, profileCarbEntry: Int, changeType: ChangeType) {
        cargo = SetIDPSettingsRequest.buildCargo(
            idpId: idpId,
            profileInsulinDuration: profileInsulinDuration,
            profileCarbEntry: profileCarbEntry,
            changeTypeId: changeType.rawValue
        )
        self.idpId = idpId
        self.profileInsulinDuration = profileInsulinDuration
        self.profileCarbEntry = profileCarbEntry
        changeTypeId = changeType.rawValue
    }

    public static func buildCargo(idpId: Int, profileInsulinDuration: Int, profileCarbEntry: Int, changeTypeId: Int) -> Data {
        Bytes.combine(
            Data([UInt8(idpId & 0xFF), 1]),
            Bytes.firstTwoBytesLittleEndian(profileInsulinDuration),
            Data([UInt8(profileCarbEntry & 0xFF), UInt8(changeTypeId & 0xFF)])
        )
    }

    public enum ChangeType: Int {
        case changeInsulinDuration = 1
        case changeCarbEntry = 4
    }

    public var changeType: ChangeType? { ChangeType(rawValue: changeTypeId) }
}

/// Response confirming profile settings update.
public class SetIDPSettingsResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-83)),
        size: 2,
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
        cargo = Bytes.combine(Data([UInt8(status & 0xFF)]), Data([2]))
        self.status = status
    }
}
