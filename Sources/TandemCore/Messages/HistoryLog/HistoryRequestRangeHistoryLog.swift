import Foundation

/// Two-hourly Mobi counters (jwoglom/pumpX2#151). Provisional name; `unknown*` fields are unidentified.
/// `minStartLog`/`maxStartLog` are the lowest and highest HistoryLogRequest startLog since the previous burst; `unknown10` is not a record count.
public class HistoryRequestRangeHistoryLog: HistoryLog {
    public static let typeId = 491

    public let unknown10: UInt32
    public let minStartLog: UInt32
    public let maxStartLog: UInt32
    public let unknown22: Int
    public let unknown24: Int

    public required init(cargo: Data) {
        unknown10 = Bytes.readUint32(cargo, 10)
        minStartLog = Bytes.readUint32(cargo, 14)
        maxStartLog = Bytes.readUint32(cargo, 18)
        unknown22 = Bytes.readShort(cargo, 22)
        unknown24 = Bytes.readShort(cargo, 24)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, unknown10: UInt32, minStartLog: UInt32, maxStartLog: UInt32, unknown22: Int, unknown24: Int) {
        let payload = HistoryRequestRangeHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            unknown10: unknown10,
            minStartLog: minStartLog,
            maxStartLog: maxStartLog,
            unknown22: unknown22,
            unknown24: unknown24
        )
        self.unknown10 = unknown10
        self.minStartLog = minStartLog
        self.maxStartLog = maxStartLog
        self.unknown22 = unknown22
        self.unknown24 = unknown24
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, unknown10: UInt32, minStartLog: UInt32, maxStartLog: UInt32, unknown22: Int, unknown24: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(unknown10),
                Bytes.toUint32(minStartLog),
                Bytes.toUint32(maxStartLog),
                Bytes.firstTwoBytesLittleEndian(unknown22),
                Bytes.firstTwoBytesLittleEndian(unknown24)
            )
        )
    }

    public var description: String {
        "HistoryRequestRangeHistoryLog(cargo=\(cargo.hexadecimalString), unknown10=\(unknown10), minStartLog=\(minStartLog), maxStartLog=\(maxStartLog), unknown22=\(unknown22), unknown24=\(unknown24))"
    }
}
