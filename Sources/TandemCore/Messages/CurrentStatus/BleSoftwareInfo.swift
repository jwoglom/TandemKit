import Foundation

/// Request BLE software device firmware information.
public class BleSoftwareInfoRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-120)),
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
        "BleSoftwareInfoRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response with BLE soft device firmware version details.
///
/// Binary layout (14 bytes total, all little-endian):
///   offset 0,  2 bytes: softDeviceId
///   offset 2,  2 bytes: softDeviceMajorVersion
///   offset 4,  2 bytes: softDeviceMinorVersion
///   offset 6,  2 bytes: softDeviceBugfixVersion
///   offset 8,  4 bytes: softDeviceVersion
///   offset 12, 2 bytes: softDeviceSubVersion
public class BleSoftwareInfoResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-119)),
        size: 14,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var softDeviceId: Int
    public var softDeviceMajorVersion: Int
    public var softDeviceMinorVersion: Int
    public var softDeviceBugfixVersion: Int
    public var softDeviceVersion: UInt32
    public var softDeviceSubVersion: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        softDeviceId = Bytes.readShort(cargo, 0)
        softDeviceMajorVersion = Bytes.readShort(cargo, 2)
        softDeviceMinorVersion = Bytes.readShort(cargo, 4)
        softDeviceBugfixVersion = Bytes.readShort(cargo, 6)
        softDeviceVersion = Bytes.readUint32(cargo, 8)
        softDeviceSubVersion = Bytes.readShort(cargo, 12)
    }

    public init(
        softDeviceId: Int,
        softDeviceMajorVersion: Int,
        softDeviceMinorVersion: Int,
        softDeviceBugfixVersion: Int,
        softDeviceVersion: UInt32,
        softDeviceSubVersion: Int
    ) {
        cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(softDeviceId),
            Bytes.firstTwoBytesLittleEndian(softDeviceMajorVersion),
            Bytes.firstTwoBytesLittleEndian(softDeviceMinorVersion),
            Bytes.firstTwoBytesLittleEndian(softDeviceBugfixVersion),
            Bytes.toUint32(softDeviceVersion),
            Bytes.firstTwoBytesLittleEndian(softDeviceSubVersion)
        )
        self.softDeviceId = softDeviceId
        self.softDeviceMajorVersion = softDeviceMajorVersion
        self.softDeviceMinorVersion = softDeviceMinorVersion
        self.softDeviceBugfixVersion = softDeviceBugfixVersion
        self.softDeviceVersion = softDeviceVersion
        self.softDeviceSubVersion = softDeviceSubVersion
    }

    public var description: String {
        "BleSoftwareInfoResponse(cargo=\(cargo.hexadecimalString), softDeviceId=\(softDeviceId), softDeviceMajorVersion=\(softDeviceMajorVersion), softDeviceMinorVersion=\(softDeviceMinorVersion), softDeviceBugfixVersion=\(softDeviceBugfixVersion), softDeviceVersion=\(softDeviceVersion), softDeviceSubVersion=\(softDeviceSubVersion))"
    }
}
