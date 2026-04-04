import Foundation

/// Request to rename an insulin delivery profile.
public class RenameIDPRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-88)),
        size: 19,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var idpId: Int
    public var profileIndex: Int
    public var profileName: String

    public required init(cargo: Data) {
        self.cargo = cargo
        idpId = Int(cargo[0])
        profileIndex = Int(cargo[1])
        profileName = Bytes.readString(cargo, 2, 16)
    }

    public init(idpId: Int, profileIndex: Int = 0, profileName: String) {
        cargo = Bytes.combine(
            Data([UInt8(idpId & 0xFF)]),
            Data([UInt8(profileIndex & 0xFF)]),
            Bytes.writeString(profileName, 16),
            Data([0])
        )
        self.idpId = idpId
        self.profileIndex = profileIndex
        self.profileName = profileName
    }

    public var description: String {
        "RenameIDPRequest(cargo=\(cargo.hexadecimalString), idpId=\(idpId), profileIndex=\(profileIndex), profileName=\(profileName))"
    }
}

/// Response to a rename profile command.
public class RenameIDPResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-87)),
        size: 2,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var status: Int
    public var numberOfProfiles: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        status = Int(cargo[0])
        numberOfProfiles = Int(cargo[1])
    }

    public init(status: Int, numberOfProfiles: Int) {
        cargo = Bytes.combine(
            Data([UInt8(status & 0xFF)]),
            Data([UInt8(numberOfProfiles & 0xFF)])
        )
        self.status = status
        self.numberOfProfiles = numberOfProfiles
    }

    public var description: String {
        "RenameIDPResponse(cargo=\(cargo.hexadecimalString), status=\(status), numberOfProfiles=\(numberOfProfiles))"
    }
}
