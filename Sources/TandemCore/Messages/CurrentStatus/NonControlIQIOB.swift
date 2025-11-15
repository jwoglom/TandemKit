import Foundation

/// Request insulin on board information when Control-IQ is not supported.
public class NonControlIQIOBRequest: Message {
    public static let props = MessageProps(
        opCode: 38,
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

/// Response providing IOB information when Control-IQ is not supported.
public class NonControlIQIOBResponse: Message {
    public static let props = MessageProps(
        opCode: 39,
        size: 12,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var iob: UInt32
    public var timeRemaining: UInt32
    public var totalIOB: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        iob = Bytes.readUint32(cargo, 0)
        timeRemaining = Bytes.readUint32(cargo, 4)
        totalIOB = Bytes.readUint32(cargo, 8)
    }

    public init(iob: UInt32, timeRemaining: UInt32, totalIOB: UInt32) {
        cargo = Bytes.combine(
            Bytes.toUint32(iob),
            Bytes.toUint32(timeRemaining),
            Bytes.toUint32(totalIOB)
        )
        self.iob = iob
        self.timeRemaining = timeRemaining
        self.totalIOB = totalIOB
    }
}
