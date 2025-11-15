import Foundation

/// Request details about the last delivered bolus.
public class LastBolusStatusRequest: Message {
    public static let props = MessageProps(
        opCode: 48,
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .apiFuture
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }
}

/// Response with information on the last bolus delivered.
public class LastBolusStatusResponse: Message {
    public static let props = MessageProps(
        opCode: 49,
        size: 20,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var status: Int
    public var bolusId: Int
    public var unknown: Data
    public var timestamp: UInt32
    public var deliveredVolume: UInt32
    public var bolusStatusId: Int
    public var bolusSourceId: Int
    public var bolusTypeBitmask: Int
    public var extendedBolusDuration: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        status = Int(cargo[0])
        bolusId = Bytes.readShort(cargo, 1)
        unknown = cargo.subdata(in: 3 ..< 5)
        timestamp = Bytes.readUint32(cargo, 5)
        deliveredVolume = Bytes.readUint32(cargo, 9)
        bolusStatusId = Int(cargo[13])
        bolusSourceId = Int(cargo[14])
        bolusTypeBitmask = Int(cargo[15])
        extendedBolusDuration = Bytes.readUint32(cargo, 16)
    }

    public init(
        status: Int,
        bolusId: Int,
        timestamp: UInt32,
        deliveredVolume: UInt32,
        bolusStatusId: Int,
        bolusSourceId: Int,
        bolusTypeBitmask: Int,
        extendedBolusDuration: UInt32,
        unknown: Data = Data([0, 0])
    ) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(status),
            Bytes.firstTwoBytesLittleEndian(bolusId),
            unknown,
            Bytes.toUint32(timestamp),
            Bytes.toUint32(deliveredVolume),
            Bytes.firstByteLittleEndian(bolusStatusId),
            Bytes.firstByteLittleEndian(bolusSourceId),
            Bytes.firstByteLittleEndian(bolusTypeBitmask),
            Bytes.toUint32(extendedBolusDuration)
        )
        self.status = status
        self.bolusId = bolusId
        self.unknown = unknown
        self.timestamp = timestamp
        self.deliveredVolume = deliveredVolume
        self.bolusStatusId = bolusStatusId
        self.bolusSourceId = bolusSourceId
        self.bolusTypeBitmask = bolusTypeBitmask
        self.extendedBolusDuration = extendedBolusDuration
    }

    public var bolusSource: BolusSource? { BolusSource.fromId(bolusSourceId) }
    public var bolusTypes: Set<BolusType> { BolusType.fromBitmask(bolusTypeBitmask) }
    public var timestampDate: Date { Dates.fromJan12008EpochSecondsToDate(TimeInterval(timestamp)) }
}
