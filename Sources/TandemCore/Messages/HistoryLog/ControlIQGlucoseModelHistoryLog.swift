import Foundation

/// Five-minute Control-IQ model record, written right after 227 in the same second (jwoglom/pumpX2#146). Provisional name; `unknown*` bytes were always 0.
/// Pump-internal Control-IQ values: never use them for dosing or IOB.
public class ControlIQGlucoseModelHistoryLog: HistoryLog {
    public static let typeId = 327

    /// Whole units/day; floor of the 332 TDI estimate on Mobis, restarts from the TDI setting after a reboot.
    public let tdiEstimate: Int
    public let unknown11: Int
    public let unknown12: Int
    /// mg/dL x 100; shorter horizon than 227's prediction, floor 2000.
    public let shortTermPredictedGlucoseRaw: Int
    /// mg/dL, not capped at 255 (227 byte 20 is this capped).
    public let filteredGlucose: Int
    public let unknown18: Int
    /// mg/dL per unit, floor(1800 / TDI estimate) in 2026 data; 0 unless Control-IQ is disabled on a Control-IQ+ Mobi.
    public let correctionFactor: Int
    public let unknown21: Int
    public let unknown22: Int
    public let unknown24: Int

    public required init(cargo: Data) {
        tdiEstimate = Int(cargo[10])
        unknown11 = Int(cargo[11])
        unknown12 = Bytes.readShort(cargo, 12)
        shortTermPredictedGlucoseRaw = Bytes.readShort(cargo, 14)
        filteredGlucose = Bytes.readShort(cargo, 16)
        unknown18 = Bytes.readShort(cargo, 18)
        correctionFactor = Int(cargo[20])
        unknown21 = Int(cargo[21])
        unknown22 = Bytes.readShort(cargo, 22)
        unknown24 = Bytes.readShort(cargo, 24)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, tdiEstimate: Int, unknown11: Int, unknown12: Int, shortTermPredictedGlucoseRaw: Int, filteredGlucose: Int, unknown18: Int, correctionFactor: Int, unknown21: Int, unknown22: Int, unknown24: Int) {
        let payload = ControlIQGlucoseModelHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            tdiEstimate: tdiEstimate,
            unknown11: unknown11,
            unknown12: unknown12,
            shortTermPredictedGlucoseRaw: shortTermPredictedGlucoseRaw,
            filteredGlucose: filteredGlucose,
            unknown18: unknown18,
            correctionFactor: correctionFactor,
            unknown21: unknown21,
            unknown22: unknown22,
            unknown24: unknown24
        )
        self.tdiEstimate = tdiEstimate
        self.unknown11 = unknown11
        self.unknown12 = unknown12
        self.shortTermPredictedGlucoseRaw = shortTermPredictedGlucoseRaw
        self.filteredGlucose = filteredGlucose
        self.unknown18 = unknown18
        self.correctionFactor = correctionFactor
        self.unknown21 = unknown21
        self.unknown22 = unknown22
        self.unknown24 = unknown24
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, tdiEstimate: Int, unknown11: Int, unknown12: Int, shortTermPredictedGlucoseRaw: Int, filteredGlucose: Int, unknown18: Int, correctionFactor: Int, unknown21: Int, unknown22: Int, unknown24: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(tdiEstimate & 0xFF)]),
                Data([UInt8(unknown11 & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(unknown12),
                Bytes.firstTwoBytesLittleEndian(shortTermPredictedGlucoseRaw),
                Bytes.firstTwoBytesLittleEndian(filteredGlucose),
                Bytes.firstTwoBytesLittleEndian(unknown18),
                Data([UInt8(correctionFactor & 0xFF)]),
                Data([UInt8(unknown21 & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(unknown22),
                Bytes.firstTwoBytesLittleEndian(unknown24)
            )
        )
    }

    public var shortTermPredictedGlucoseMgdl: Double {
        Double(shortTermPredictedGlucoseRaw) / 100.0
    }

    override public var description: String {
        "ControlIQGlucoseModelHistoryLog(cargo=\(cargo.hexadecimalString), tdiEstimate=\(tdiEstimate), unknown11=\(unknown11), unknown12=\(unknown12), shortTermPredictedGlucoseRaw=\(shortTermPredictedGlucoseRaw), filteredGlucose=\(filteredGlucose), unknown18=\(unknown18), correctionFactor=\(correctionFactor), unknown21=\(unknown21), unknown22=\(unknown22), unknown24=\(unknown24))"
    }
}
