import Foundation

public class UnknownMobiOpcodeNeg124Request: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-124)),
        size: 0,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = Bytes.dropLastN(cargo, 20) // remove trailer if present
    }

    public init() {
        cargo = Data()
    }
}

public class UnknownMobiOpcodeNeg124Response: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-123)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var status: Int

    public required init(cargo: Data) {
        self.cargo = Bytes.dropLastN(cargo, 20)
        status = Int(self.cargo[0])
    }

    public init(status: Int) {
        cargo = Bytes.firstByteLittleEndian(status)
        self.status = status
    }
}
