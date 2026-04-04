import Foundation

/// Request the currently active insulin delivery profile values.
public class CurrentActiveIdpValuesRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-106)),
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

    public var description: String {
        "CurrentActiveIdpValuesRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response with the currently active IDP parameter values based on the active time segment.
///
/// Binary layout (10 bytes):
///   bytes 0-3:  currentCarbRatio (uint32 LE) - carb ratio in 1000-increments
///   byte  4:    unknown/padding
///   bytes 5-6:  currentTargetBg (uint16 LE) - target BG in mg/dL
///   bytes 6-7:  currentInsulinDuration (uint16 LE) - insulin duration in minutes
///   bytes 8-9:  currentIsf (uint16 LE) - insulin sensitivity factor in mg/dL per unit
///
/// Note: bytes 5-6 and 6-7 overlap at byte 6. In practice currentTargetBg < 256 so
/// its high byte at position 6 is always 0, which also serves as the low byte of
/// currentInsulinDuration.
public class CurrentActiveIdpValuesResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-105)),
        size: 10,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    /// Carb ratio in 1000-increments (e.g. 10000 = 10 g/U).
    public var currentCarbRatio: UInt32
    /// Target blood glucose in mg/dL.
    public var currentTargetBg: Int
    /// Insulin duration in minutes (e.g. 300 = 5 hours).
    public var currentInsulinDuration: Int
    /// Insulin sensitivity factor in mg/dL per unit.
    public var currentIsf: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        currentCarbRatio = Bytes.readUint32(cargo, 0)
        // byte 4 is unknown/padding
        currentTargetBg = Bytes.readShort(cargo, 5)
        currentInsulinDuration = Bytes.readShort(cargo, 6)
        currentIsf = Bytes.readShort(cargo, 8)
    }

    public init(
        currentCarbRatio: UInt32,
        currentTargetBg: Int,
        currentInsulinDuration: Int,
        currentIsf: Int
    ) {
        // Build the overlapping 3-byte region [5,6,7]:
        //   byte 5 = targetBg low byte
        //   byte 6 = targetBg high byte (0 since targetBg < 256) = insulinDuration low byte
        //   byte 7 = insulinDuration high byte
        let byte5 = UInt8(currentTargetBg & 0xFF)
        let byte6 = UInt8(currentInsulinDuration & 0xFF)
        let byte7 = UInt8((currentInsulinDuration >> 8) & 0xFF)

        cargo = Bytes.combine(
            Bytes.toUint32(currentCarbRatio),
            Data([0]),
            Data([byte5, byte6, byte7]),
            Bytes.firstTwoBytesLittleEndian(currentIsf)
        )
        self.currentCarbRatio = currentCarbRatio
        self.currentTargetBg = currentTargetBg
        self.currentInsulinDuration = currentInsulinDuration
        self.currentIsf = currentIsf
    }

    public var description: String {
        "CurrentActiveIdpValuesResponse(cargo=\(cargo.hexadecimalString), currentCarbRatio=\(currentCarbRatio), currentTargetBg=\(currentTargetBg), currentInsulinDuration=\(currentInsulinDuration), currentIsf=\(currentIsf))"
    }
}
