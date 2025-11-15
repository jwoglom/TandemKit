import Foundation

public class UnknownMobiOpcodeNeg66Request: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-66)),
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

public class UnknownMobiOpcodeNeg66Response: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-65)),
        size: 20,
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
