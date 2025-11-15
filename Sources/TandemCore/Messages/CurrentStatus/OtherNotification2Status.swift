import Foundation

/// Request additional notification status codes.
public class OtherNotification2StatusRequest: Message {
    public static let props = MessageProps(
        opCode: 118,
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

/// Response containing two additional notification codes.
public class OtherNotification2StatusResponse: Message {
    public static let props = MessageProps(
        opCode: 119,
        size: 8,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var codeA: UInt32
    public var codeB: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        codeA = Bytes.readUint32(cargo, 0)
        codeB = Bytes.readUint32(cargo, 4)
    }

    public init(codeA: UInt32, codeB: UInt32) {
        cargo = Bytes.combine(
            Bytes.toUint32(codeA),
            Bytes.toUint32(codeB)
        )
        self.codeA = codeA
        self.codeB = codeB
    }
}
