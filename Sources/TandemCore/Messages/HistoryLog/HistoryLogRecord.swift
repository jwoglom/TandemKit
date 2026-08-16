import Foundation

/// Base class representing a single 26-byte history log entry.
open class HistoryLog {
    public static let length = 26

    public let cargo: Data
    public let typeId: Int
    public let pumpTimeSec: UInt32
    public let sequenceNum: UInt32

    public required init(cargo: Data) {
        let filled = HistoryLog.fillCargo(cargo)
        self.cargo = filled
        typeId = Int(Bytes.readShort(filled, 0) & 0x0FFF)
        pumpTimeSec = Bytes.readUint32(filled, 2)
        sequenceNum = Bytes.readUint32(filled, 6)
    }

    /// Pads or truncates cargo to the standard 26-byte length.
    public static func fillCargo(_ cargo: Data) -> Data {
        if cargo.count == length {
            return cargo
        }
        var ret = Data(count: length)
        ret.replaceSubrange(0 ..< min(cargo.count, length), with: cargo.prefix(length))
        return ret
    }


    /// Returns a copy of this log whose header high nibble (top 4 bits of the little-endian
    /// uint16 at cargo offset 0) is set to `headerHighNibble`.
    ///
    /// Mirrors pumpX2's `HistoryLog.withHeaderHighNibble(int)`. The nibble's meaning is unknown
    /// and capture-dependent (records from some pumps carry 1, older fixtures carry 0), so
    /// serializers emit 0 and callers reproducing a captured record byte-exact apply the observed
    /// nibble with this method. Parsed fields are unaffected.
    public func withHeaderHighNibble(_ headerHighNibble: Int) -> Self {
        var updated = cargo
        updated[updated.startIndex + 1] = UInt8((Int(updated[updated.startIndex + 1]) & 0x0F) | ((headerHighNibble & 0x0F) << 4))
        return Self(cargo: updated)
    }

    /// Builds the two-byte little-endian header found at cargo offset 0.
    ///
    /// Mirrors pumpX2's `HistoryLog.typeIdBytes(int typeId, int headerHighNibble)`: the low 12
    /// bits carry `typeId`, and the top 4 bits carry an unknown "header high nibble" that some
    /// records reproduce byte-exact from real pump captures (e.g. Dexcom G7 uses 1). Building the
    /// header bytes by hand (e.g. `Data([UInt8(typeId), 0])`) truncates any `typeId` above 255,
    /// since it drops bits 8-11 entirely — always route through this helper instead.
    public static func typeIdBytes(_ typeId: Int, _ headerHighNibble: Int = 0) -> Data {
        Data([UInt8(typeId & 0xFF), UInt8(((typeId >> 8) & 0x0F) | ((headerHighNibble & 0x0F) << 4))])
    }
}
