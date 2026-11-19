import Foundation

/// One slot of the pump's 64-bit software ID (jwoglom/pumpX2#152). Provisional name; `unknown*` fields are unidentified.
/// Written after every NewDay and per slot at boot; a slot logged at boot before it is filled has both words 0.
public class SoftwareIdHistoryLog: HistoryLog {
    public static let typeId = 449

    /// Raw; 0-3 on the Mobi, 0 and 2 on the t:slim X2. Every filled slot has carried the same ID so far.
    public let slot: Int
    /// Bytes 11-13, little endian.
    public let unknown11: Int
    /// Equals `VersionsAHistoryLog.armSwVersion`.
    public let armSwVersion: UInt32
    public let softwareIdLow: UInt32
    public let unknown22: UInt32

    public required init(cargo: Data) {
        slot = Int(cargo[cargo.startIndex + 10])
        unknown11 = Int(cargo[cargo.startIndex + 11])
            | (Int(cargo[cargo.startIndex + 12]) << 8)
            | (Int(cargo[cargo.startIndex + 13]) << 16)
        armSwVersion = Bytes.readUint32(cargo, 14)
        softwareIdLow = Bytes.readUint32(cargo, 18)
        unknown22 = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, slot: Int, unknown11: Int = 0, armSwVersion: UInt32, softwareIdLow: UInt32, unknown22: UInt32 = 0) {
        let payload = SoftwareIdHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            slot: slot,
            unknown11: unknown11,
            armSwVersion: armSwVersion,
            softwareIdLow: softwareIdLow,
            unknown22: unknown22
        )
        self.slot = slot
        self.unknown11 = unknown11
        self.armSwVersion = armSwVersion
        self.softwareIdLow = softwareIdLow
        self.unknown22 = unknown22
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, slot: Int, unknown11: Int, armSwVersion: UInt32, softwareIdLow: UInt32, unknown22: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([
                    UInt8(slot & 0xFF),
                    UInt8(unknown11 & 0xFF),
                    UInt8((unknown11 >> 8) & 0xFF),
                    UInt8((unknown11 >> 16) & 0xFF),
                ]),
                Bytes.toUint32(armSwVersion),
                Bytes.toUint32(softwareIdLow),
                Bytes.toUint32(unknown22)
            )
        )
    }

    public var isSoftwareIdKnown: Bool {
        armSwVersion != 0 || softwareIdLow != 0
    }

    /// The 16-hex-digit string `CommonSoftwareInfoResponse` returns; empty for a slot that is not yet filled.
    public var softwareId: String {
        guard isSoftwareIdKnown else { return "" }
        return String(format: "%08x%08x", armSwVersion, softwareIdLow)
    }

    override public var description: String {
        "SoftwareIdHistoryLog(cargo=\(cargo.hexadecimalString), slot=\(slot), unknown11=\(unknown11), armSwVersion=\(armSwVersion), softwareIdLow=\(softwareIdLow), unknown22=\(unknown22))"
    }
}
