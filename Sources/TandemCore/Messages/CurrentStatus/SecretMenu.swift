import Foundation

/// Request debug/diagnostic secret menu information.
public class SecretMenuRequest: PumpRequest {
    public typealias Response = SecretMenuResponse

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-68)),
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
        "SecretMenuRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response with debug/diagnostic information from the secret menu.
///
/// Binary layout (8 bytes):
///   bytes 0-3: timeOfLastConnectionTimestampSeconds (uint32 LE)
///   bytes 4-7: reservedValue (uint32 LE)
public class SecretMenuResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-67)),
        size: 8,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var timeOfLastConnectionTimestampSeconds: UInt32
    public var reservedValue: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        timeOfLastConnectionTimestampSeconds = Bytes.readUint32(cargo, 0)
        reservedValue = Bytes.readUint32(cargo, 4)
    }

    public init(timeOfLastConnectionTimestampSeconds: UInt32, reservedValue: UInt32) {
        cargo = Bytes.combine(
            Bytes.toUint32(timeOfLastConnectionTimestampSeconds),
            Bytes.toUint32(reservedValue)
        )
        self.timeOfLastConnectionTimestampSeconds = timeOfLastConnectionTimestampSeconds
        self.reservedValue = reservedValue
    }

    public var timeOfLastConnectionDate: Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(timeOfLastConnectionTimestampSeconds))
    }

    public var description: String {
        "SecretMenuResponse(cargo=\(cargo.hexadecimalString), timeOfLastConnectionTimestampSeconds=\(timeOfLastConnectionTimestampSeconds), reservedValue=\(reservedValue))"
    }
}
