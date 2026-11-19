import Foundation

/// BLE SoftDevice version stored twice, as (id, major, minor, bugfix) uint16 blocks at bytes 10-17 and 18-25 (jwoglom/pumpX2#152).
/// Provisional name; the two blocks have always been equal and what distinguishes them is unknown.
public class BleSoftDeviceVersionHistoryLog: HistoryLog {
    public static let typeId = 450

    public let softDeviceId: Int
    public let softDeviceMajorVersion: Int
    public let softDeviceMinorVersion: Int
    public let softDeviceBugfixVersion: Int
    public let softDeviceId2: Int
    public let softDeviceMajorVersion2: Int
    public let softDeviceMinorVersion2: Int
    public let softDeviceBugfixVersion2: Int

    public required init(cargo: Data) {
        softDeviceId = Bytes.readShort(cargo, 10)
        softDeviceMajorVersion = Bytes.readShort(cargo, 12)
        softDeviceMinorVersion = Bytes.readShort(cargo, 14)
        softDeviceBugfixVersion = Bytes.readShort(cargo, 16)
        softDeviceId2 = Bytes.readShort(cargo, 18)
        softDeviceMajorVersion2 = Bytes.readShort(cargo, 20)
        softDeviceMinorVersion2 = Bytes.readShort(cargo, 22)
        softDeviceBugfixVersion2 = Bytes.readShort(cargo, 24)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        softDeviceId: Int,
        softDeviceMajorVersion: Int,
        softDeviceMinorVersion: Int,
        softDeviceBugfixVersion: Int,
        softDeviceId2: Int,
        softDeviceMajorVersion2: Int,
        softDeviceMinorVersion2: Int,
        softDeviceBugfixVersion2: Int
    ) {
        let payload = BleSoftDeviceVersionHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            softDeviceId: softDeviceId,
            softDeviceMajorVersion: softDeviceMajorVersion,
            softDeviceMinorVersion: softDeviceMinorVersion,
            softDeviceBugfixVersion: softDeviceBugfixVersion,
            softDeviceId2: softDeviceId2,
            softDeviceMajorVersion2: softDeviceMajorVersion2,
            softDeviceMinorVersion2: softDeviceMinorVersion2,
            softDeviceBugfixVersion2: softDeviceBugfixVersion2
        )
        self.softDeviceId = softDeviceId
        self.softDeviceMajorVersion = softDeviceMajorVersion
        self.softDeviceMinorVersion = softDeviceMinorVersion
        self.softDeviceBugfixVersion = softDeviceBugfixVersion
        self.softDeviceId2 = softDeviceId2
        self.softDeviceMajorVersion2 = softDeviceMajorVersion2
        self.softDeviceMinorVersion2 = softDeviceMinorVersion2
        self.softDeviceBugfixVersion2 = softDeviceBugfixVersion2
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        softDeviceId: Int,
        softDeviceMajorVersion: Int,
        softDeviceMinorVersion: Int,
        softDeviceBugfixVersion: Int,
        softDeviceId2: Int,
        softDeviceMajorVersion2: Int,
        softDeviceMinorVersion2: Int,
        softDeviceBugfixVersion2: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(softDeviceId),
                Bytes.firstTwoBytesLittleEndian(softDeviceMajorVersion),
                Bytes.firstTwoBytesLittleEndian(softDeviceMinorVersion),
                Bytes.firstTwoBytesLittleEndian(softDeviceBugfixVersion),
                Bytes.firstTwoBytesLittleEndian(softDeviceId2),
                Bytes.firstTwoBytesLittleEndian(softDeviceMajorVersion2),
                Bytes.firstTwoBytesLittleEndian(softDeviceMinorVersion2),
                Bytes.firstTwoBytesLittleEndian(softDeviceBugfixVersion2)
            )
        )
    }

    /// False for the all-zero record a Mobi writes in its NewDay block during a restart, before the BLE processor reports; not version 0.0.0.
    public var isKnown: Bool {
        [
            softDeviceId, softDeviceMajorVersion, softDeviceMinorVersion, softDeviceBugfixVersion,
            softDeviceId2, softDeviceMajorVersion2, softDeviceMinorVersion2, softDeviceBugfixVersion2
        ].contains { $0 != 0 }
    }

    /// "major.minor.bugfix" of the first block, or nil if that block is all zero.
    public var versionString: String? {
        Self.versionString(softDeviceId, softDeviceMajorVersion, softDeviceMinorVersion, softDeviceBugfixVersion)
    }

    public var versionString2: String? {
        Self.versionString(softDeviceId2, softDeviceMajorVersion2, softDeviceMinorVersion2, softDeviceBugfixVersion2)
    }

    private static func versionString(_ id: Int, _ major: Int, _ minor: Int, _ bugfix: Int) -> String? {
        if id == 0, major == 0, minor == 0, bugfix == 0 {
            return nil
        }
        return "\(major).\(minor).\(bugfix)"
    }

    override public var description: String {
        "BleSoftDeviceVersionHistoryLog(cargo=\(cargo.hexadecimalString), softDeviceId=\(softDeviceId), softDeviceMajorVersion=\(softDeviceMajorVersion), softDeviceMinorVersion=\(softDeviceMinorVersion), softDeviceBugfixVersion=\(softDeviceBugfixVersion), softDeviceId2=\(softDeviceId2), softDeviceMajorVersion2=\(softDeviceMajorVersion2), softDeviceMinorVersion2=\(softDeviceMinorVersion2), softDeviceBugfixVersion2=\(softDeviceBugfixVersion2))"
    }
}
