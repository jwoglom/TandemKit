import Foundation

/// Request to activate shelf mode on the pump.
public class ActivateShelfModeRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-70)),
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
        "ActivateShelfModeRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response after requesting shelf mode activation.
public class ActivateShelfModeResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-69)),
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
        "ActivateShelfModeResponse(cargo=\(cargo.hexadecimalString))"
    }
}
