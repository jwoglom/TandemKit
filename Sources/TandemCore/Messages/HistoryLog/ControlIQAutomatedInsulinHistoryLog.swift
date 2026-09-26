import Foundation

/// Every 15 min: insulin Control-IQ commanded over the last 24 five-minute cycles, in units (jwoglom/pumpX2#146). Provisional name; `unknown22` is unidentified.
/// Pump-internal Control-IQ state: not for dosing or IOB. Zero until closed loop has run since pump start; float residue (< 2e-5 U) once it stops.
public class ControlIQAutomatedInsulinHistoryLog: HistoryLog {
    public static let typeId = 237
    public static let residueThresholdUnits: Float = 0.001

    /// Algorithm basal (rate x 5 min per cycle in control) plus automatic correction boluses; user boluses excluded.
    public let totalInsulin: Float
    /// Sum of max(0, commanded - profile rate) x 5 min.
    public let basalAboveProfileInsulin: Float
    /// Booked at the deciding Control-IQ cycle, before BolusDelivery's STARTED record, and dropped 2 h later.
    public let autoBolusInsulin: Float
    public let unknown22: UInt32

    public var basalInsulin: Float { totalInsulin - autoBolusInsulin }

    public var hasAutomatedInsulin: Bool {
        abs(totalInsulin) >= Self.residueThresholdUnits
            || abs(basalAboveProfileInsulin) >= Self.residueThresholdUnits
            || abs(autoBolusInsulin) >= Self.residueThresholdUnits
    }

    public required init(cargo: Data) {
        totalInsulin = Bytes.readFloat(cargo, 10)
        basalAboveProfileInsulin = Bytes.readFloat(cargo, 14)
        autoBolusInsulin = Bytes.readFloat(cargo, 18)
        unknown22 = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, totalInsulin: Float, basalAboveProfileInsulin: Float, autoBolusInsulin: Float, unknown22: UInt32) {
        let payload = ControlIQAutomatedInsulinHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            totalInsulin: totalInsulin,
            basalAboveProfileInsulin: basalAboveProfileInsulin,
            autoBolusInsulin: autoBolusInsulin,
            unknown22: unknown22
        )
        self.totalInsulin = totalInsulin
        self.basalAboveProfileInsulin = basalAboveProfileInsulin
        self.autoBolusInsulin = autoBolusInsulin
        self.unknown22 = unknown22
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, totalInsulin: Float, basalAboveProfileInsulin: Float, autoBolusInsulin: Float, unknown22: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toFloat(totalInsulin),
                Bytes.toFloat(basalAboveProfileInsulin),
                Bytes.toFloat(autoBolusInsulin),
                Bytes.toUint32(unknown22)
            )
        )
    }

    public var description: String {
        "ControlIQAutomatedInsulinHistoryLog(cargo=\(cargo.hexadecimalString), totalInsulin=\(totalInsulin), basalAboveProfileInsulin=\(basalAboveProfileInsulin), autoBolusInsulin=\(autoBolusInsulin), unknown22=\(unknown22))"
    }
}
