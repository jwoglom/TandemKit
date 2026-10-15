import Foundation

/// Request to perform a factory reset on the pump.
public class FactoryResetRequest: PumpRequest {
    public typealias Response = FactoryResetResponse

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-24)),
        size: 0,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true,
        dangerousDoNotInvoke: true,
        dangerousRequireExplicitConfirmation: true
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "FactoryResetRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response after requesting a factory reset.
public class FactoryResetResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-23)),
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
        "FactoryResetResponse(cargo=\(cargo.hexadecimalString))"
    }
}
