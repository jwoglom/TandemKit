import Foundation

/// Request information on the current extended bolus.
public class ExtendedBolusStatusRequest: Message {
    public static let props = MessageProps(
        opCode: 46,
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

/// Response describing details of the current extended bolus.
public class ExtendedBolusStatusResponse: Message {
    public static let props = MessageProps(
        opCode: 47,
        size: 18,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var bolusStatus: Int
    public var bolusId: Int
    public var timestamp: UInt32
    public var requestedVolume: UInt32
    public var duration: UInt32
    public var bolusSource: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        bolusStatus = Int(cargo[0])
        bolusId = Bytes.readShort(cargo, 1)
        timestamp = Bytes.readUint32(cargo, 5)
        requestedVolume = Bytes.readUint32(cargo, 9)
        duration = Bytes.readUint32(cargo, 13)
        bolusSource = Int(cargo[17])
    }

    public init(bolusStatus: Int, bolusId: Int, timestamp: UInt32, requestedVolume: UInt32, duration: UInt32, bolusSource: Int) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(bolusStatus),
            Bytes.firstTwoBytesLittleEndian(bolusId),
            Bytes.toUint32(timestamp),
            Bytes.toUint32(requestedVolume),
            Bytes.toUint32(duration),
            Bytes.firstByteLittleEndian(bolusSource),
            Data([0, 0])
        )
        self.bolusStatus = bolusStatus
        self.bolusId = bolusId
        self.timestamp = timestamp
        self.requestedVolume = requestedVolume
        self.duration = duration
        self.bolusSource = bolusSource
    }
}
