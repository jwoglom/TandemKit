import Foundation

public class UnknownMobiOpcodeNeg70Request: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-70)),
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }
}

public class UnknownMobiOpcodeNeg70Response: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-69)),
        size: 53,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }
}
