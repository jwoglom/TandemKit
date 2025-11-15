import Foundation

/// Request to activate an insulin delivery profile.
public class SetActiveIDPRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-20)),
        size: 2,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var idpId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        idpId = Int(cargo[0])
    }

    public init(idpId: Int) {
        cargo = Bytes.combine(
            Data([UInt8(idpId & 0xFF)]),
            Data([1])
        )
        self.idpId = idpId
    }
}

/// Response indicating whether the profile was activated.
public class SetActiveIDPResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-19)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        supportedDevices: .mobiOnly
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
}
