import Foundation

/// Request to perform a secondary factory reset on the pump.
public class FactoryResetBRequest: Message {
    public static let props = MessageProps(
        opCode: 124,
        size: 0,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "FactoryResetBRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response after requesting a secondary factory reset.
public class FactoryResetBResponse: Message {
    public static let props = MessageProps(
        opCode: 125,
        size: 0,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public var description: String {
        "FactoryResetBResponse(cargo=\(cargo.hexadecimalString))"
    }
}
