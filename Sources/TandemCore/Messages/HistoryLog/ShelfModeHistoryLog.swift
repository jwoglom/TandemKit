import Foundation

public class ShelfModeHistoryLog: HistoryLog {
    public static let typeId = 53

    public let msecSinceReset: UInt32
    /// Battery internal capacity, in percent.
    public let lipoIbc: Int
    /// Battery available capacity, in percent.
    public let lipoAbc: Int
    /// Signed battery current, in mA.
    public let lipoCurrent: Int
    public let lipoRemCap: UInt32
    public let lipoMv: UInt32

    public required init(cargo: Data) {
        msecSinceReset = Bytes.readUint32(cargo, 10)
        // Layout per the Tandem Source event schema: LiPoCurrent int16 @14, LiPo_ABC u8 @16, LiPo_IBC u8 @17.
        lipoCurrent = Int(Int16(bitPattern: UInt16(truncatingIfNeeded: Bytes.readShort(cargo, 14))))
        lipoAbc = Int(cargo[cargo.startIndex + 16])
        lipoIbc = Int(cargo[cargo.startIndex + 17])
        lipoRemCap = Bytes.readUint32(cargo, 18)
        lipoMv = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        msecSinceReset: UInt32,
        lipoIbc: Int,
        lipoAbc: Int,
        lipoCurrent: Int,
        lipoRemCap: UInt32,
        lipoMv: UInt32
    ) {
        let payload = ShelfModeHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            msecSinceReset: msecSinceReset,
            lipoIbc: lipoIbc,
            lipoAbc: lipoAbc,
            lipoCurrent: lipoCurrent,
            lipoRemCap: lipoRemCap,
            lipoMv: lipoMv
        )
        self.msecSinceReset = msecSinceReset
        self.lipoIbc = lipoIbc
        self.lipoAbc = lipoAbc
        self.lipoCurrent = lipoCurrent
        self.lipoRemCap = lipoRemCap
        self.lipoMv = lipoMv
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        msecSinceReset: UInt32,
        lipoIbc: Int,
        lipoAbc: Int,
        lipoCurrent: Int,
        lipoRemCap: UInt32,
        lipoMv: UInt32
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(msecSinceReset),
                Bytes.firstTwoBytesLittleEndian(lipoCurrent & 0xFFFF),
                Data([UInt8(truncatingIfNeeded: lipoAbc)]),
                Data([UInt8(truncatingIfNeeded: lipoIbc)]),
                Bytes.toUint32(lipoRemCap),
                Bytes.toUint32(lipoMv)
            )
        )
    }

    override public var description: String {
        "ShelfModeHistoryLog(cargo=\(cargo.hexadecimalString), msecSinceReset=\(msecSinceReset), lipoIbc=\(lipoIbc), lipoAbc=\(lipoAbc), lipoCurrent=\(lipoCurrent), lipoRemCap=\(lipoRemCap), lipoMv=\(lipoMv))"
    }
}
