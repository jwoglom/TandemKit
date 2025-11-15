import Foundation

/// Possibly related to Face ID authentication.
public class UnknownMobiOpcode20Request: Message {
    public static let props = MessageProps(
        opCode: 20,
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }
}

/// Response to UnknownMobiOpcode20.
public class UnknownMobiOpcode20Response: Message {
    public static let props = MessageProps(
        opCode: 21,
        size: 3,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var status: Int
    public var unknown: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        status = Int(cargo[0])
        unknown = Bytes.readShort(cargo, 1)
    }

    public init(status: Int, unknown: Int) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(status),
            Bytes.firstTwoBytesLittleEndian(unknown)
        )
        self.status = status
        self.unknown = unknown
    }
}
