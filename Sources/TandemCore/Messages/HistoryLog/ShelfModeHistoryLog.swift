import Foundation

/// History log entry capturing shelf mode battery telemetry.
public class ShelfModeHistoryLog: HistoryLog {
    public static let typeId = 53

    public let msecSinceReset: UInt32
    public let lipoIbc: Int
    public let lipoAbc: Int
    public let lipoCurrent: Int
    public let lipoRemCap: UInt32
    public let lipoMv: UInt32

    public required init(cargo: Data) {
        msecSinceReset = Bytes.readUint32(cargo, 10)
        lipoIbc = Int(cargo[14])
        lipoAbc = Int(cargo[15])
        lipoCurrent = Int(Bytes.readShort(cargo, 16))
        lipoRemCap = Bytes.readUint32(cargo, 18)
        lipoMv = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, msecSinceReset: UInt32, lipoIbc: Int, lipoAbc: Int, lipoCurrent: Int, lipoRemCap: UInt32, lipoMv: UInt32) {
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
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(msecSinceReset),
                Data([UInt8(lipoIbc & 0xFF)]),
                Data([UInt8(lipoAbc & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(lipoCurrent),
                Bytes.toUint32(lipoRemCap),
                Bytes.toUint32(lipoMv)
            )
        )
    }
}

public extension ShelfModeHistoryLog {
    var description: String {
        "ShelfModeHistoryLog(cargo=\(cargo.hexadecimalString), msecSinceReset=\(msecSinceReset), lipoIbc=\(lipoIbc), lipoAbc=\(lipoAbc), lipoCurrent=\(lipoCurrent), lipoRemCap=\(lipoRemCap), lipoMv=\(lipoMv))"
    }
}
