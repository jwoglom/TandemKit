import Foundation

/// Request to configure the G6 transmitter ID on Mobi.
public class SetG6TransmitterIdRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-80)),
        size: 16,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public static let txIdLength = 6

    public var cargo: Data
    public var txId: String

    public required init(cargo: Data) {
        self.cargo = cargo
        txId = Bytes.readString(cargo, 0, Self.txIdLength)
    }

    public init(txId: String) {
        cargo = Bytes.combine(
            Bytes.writeString(txId, Self.txIdLength),
            Data(repeating: 0, count: 10)
        )
        self.txId = txId
    }
}

/// Response after setting the G6 transmitter ID.
public class SetG6TransmitterIdResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-79)),
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
        self.cargo = cargo
        status = Int(cargo[0])
    }

    public init(status: Int) {
        cargo = Data([UInt8(status & 0xFF)])
        self.status = status
    }
}
