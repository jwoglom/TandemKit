import Foundation

/// Request metadata about the pump's history log.
public class HistoryLogStatusRequest: Message {
    public static let props = MessageProps(
        opCode: 58,
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

/// Response containing counts for entries in the history log.
public class HistoryLogStatusResponse: Message {
    public static let props = MessageProps(
        opCode: 59,
        size: 12,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var numEntries: UInt32
    public var firstSequenceNum: UInt32
    public var lastSequenceNum: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        numEntries = Bytes.readUint32(cargo, 0)
        firstSequenceNum = Bytes.readUint32(cargo, 4)
        lastSequenceNum = Bytes.readUint32(cargo, 8)
    }

    public init(numEntries: UInt32, firstSequenceNum: UInt32, lastSequenceNum: UInt32) {
        cargo = Bytes.combine(
            Bytes.toUint32(numEntries),
            Bytes.toUint32(firstSequenceNum),
            Bytes.toUint32(lastSequenceNum)
        )
        self.numEntries = numEntries
        self.firstSequenceNum = firstSequenceNum
        self.lastSequenceNum = lastSequenceNum
    }
}
