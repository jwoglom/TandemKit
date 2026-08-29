import Foundation

/// Request information on the current extended bolus (V2).
public class ExtendedBolusStatusV2Request: PumpRequest {
    public typealias Response = ExtendedBolusStatusV2Response

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-74)),
        size: 0,
        type: .Request,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "ExtendedBolusStatusV2Request(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response describing details of the current extended bolus (V2).
/// Equivalent to ExtendedBolusStatusResponse but adds secondsSincePumpReset.
///
/// Binary layout (22 bytes):
///   byte  0:     bolusStatus (uint8)
///   bytes 1-2:   bolusId (uint16 LE)
///   bytes 3-4:   reserved
///   bytes 5-8:   timestamp (uint32 LE)
///   bytes 9-12:  requestedVolume (uint32 LE)
///   bytes 13-16: duration (uint32 LE, seconds)
///   byte  17:    bolusSource (uint8)
///   bytes 18-21: secondsSincePumpReset (uint32 LE)
public class ExtendedBolusStatusV2Response: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-73)),
        size: 22,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var bolusStatus: Int
    public var bolusId: Int
    public var timestamp: UInt32
    public var requestedVolume: UInt32
    public var duration: UInt32
    public var bolusSource: Int
    public var secondsSincePumpReset: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        bolusStatus = Int(cargo[0])
        bolusId = Bytes.readShort(cargo, 1)
        // bytes 3-4 are reserved/skipped
        timestamp = Bytes.readUint32(cargo, 5)
        requestedVolume = Bytes.readUint32(cargo, 9)
        duration = Bytes.readUint32(cargo, 13)
        bolusSource = Int(cargo[17])
        secondsSincePumpReset = Bytes.readUint32(cargo, 18)
    }

    public init(
        bolusStatus: Int,
        bolusId: Int,
        timestamp: UInt32,
        requestedVolume: UInt32,
        duration: UInt32,
        bolusSource: Int,
        secondsSincePumpReset: UInt32
    ) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(bolusStatus),
            Bytes.firstTwoBytesLittleEndian(bolusId),
            Data([0, 0]),
            Bytes.toUint32(timestamp),
            Bytes.toUint32(requestedVolume),
            Bytes.toUint32(duration),
            Bytes.firstByteLittleEndian(bolusSource),
            Bytes.toUint32(secondsSincePumpReset)
        )
        self.bolusStatus = bolusStatus
        self.bolusId = bolusId
        self.timestamp = timestamp
        self.requestedVolume = requestedVolume
        self.duration = duration
        self.bolusSource = bolusSource
        self.secondsSincePumpReset = secondsSincePumpReset
    }

    public var description: String {
        "ExtendedBolusStatusV2Response(cargo=\(cargo.hexadecimalString), bolusStatus=\(bolusStatus), bolusId=\(bolusId), timestamp=\(timestamp), requestedVolume=\(requestedVolume), duration=\(duration), bolusSource=\(bolusSource), secondsSincePumpReset=\(secondsSincePumpReset))"
    }
}
