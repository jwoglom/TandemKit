import Foundation

/// Opcode 227 (no Tandem name; provisional): Control-IQ's state for one 5-minute cycle, written even with Control-IQ off. pumpX2#146
/// Pump-internal algorithm values; do not use them for dosing or as the IOB.
public class ControlIQCycleHistoryLog: HistoryLog {
    public static let typeId = 227

    /// Milliunits per 5 min; floor(max(0, next BasalDelivery algorithmRate - profileBasalRate) / 12).
    public let basalIncreaseMilliunits: Int
    /// Milliunits; floor(algorithmRate / 12) plus any Control-IQ auto-bolus started this cycle.
    public let cycleInsulinMilliunits: Int
    /// mg/dL x 100, floored at 2000; horizon not confirmed.
    public let predictedGlucoseX100: Int
    /// Milliunits/hr; the running temp rate, else the profile rate, capped at 3000.
    public let programmedBasalRate: Int
    /// Milliunits; boluses plus (delivered - programmed) basal on a 2-compartment curve, tau 34 min, floored at 0. Not the displayed IOB.
    public let netIobMilliunits: Int
    /// mg/dL, saturates at 255; frozen near a fixed value when no CGM is paired to the pump.
    public let glucoseEstimate: Int
    /// mg/dL per unit; min(floor(1800 / TDI estimate), profile correction factor), 1500 instead of 1800 in older records.
    public let correctionFactor: Int
    /// Whole units/day; the integer part of the preceding AaTdiEstChange (332) estimate.
    public let tdiEstimate: Int
    /// 0-200; floor(200 / (1 + 2.5 * Kovatchev low-BG risk of the prediction)), 0 below 70 mg/dL. 200 = no attenuation.
    public let hypoBrake: Int
    /// Rises 40/hr to 200 in sleep mode and falls after it ends; meaning unknown.
    public let sleepRamp: Int
    /// mg/dL; 160 in normal and exercise mode, 120 in sleep, ramping between them.
    public let upperTarget: Int

    public required init(cargo: Data) {
        basalIncreaseMilliunits = Bytes.readShort(cargo, 10)
        cycleInsulinMilliunits = Bytes.readShort(cargo, 12)
        predictedGlucoseX100 = Bytes.readShort(cargo, 14)
        programmedBasalRate = Bytes.readShort(cargo, 16)
        netIobMilliunits = Bytes.readShort(cargo, 18)
        glucoseEstimate = Int(cargo[20])
        correctionFactor = Int(cargo[21])
        tdiEstimate = Int(cargo[22])
        hypoBrake = Int(cargo[23])
        sleepRamp = Int(cargo[24])
        upperTarget = Int(cargo[25])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        basalIncreaseMilliunits: Int,
        cycleInsulinMilliunits: Int,
        predictedGlucoseX100: Int,
        programmedBasalRate: Int,
        netIobMilliunits: Int,
        glucoseEstimate: Int,
        correctionFactor: Int,
        tdiEstimate: Int,
        hypoBrake: Int,
        sleepRamp: Int,
        upperTarget: Int
    ) {
        let payload = ControlIQCycleHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            basalIncreaseMilliunits: basalIncreaseMilliunits,
            cycleInsulinMilliunits: cycleInsulinMilliunits,
            predictedGlucoseX100: predictedGlucoseX100,
            programmedBasalRate: programmedBasalRate,
            netIobMilliunits: netIobMilliunits,
            glucoseEstimate: glucoseEstimate,
            correctionFactor: correctionFactor,
            tdiEstimate: tdiEstimate,
            hypoBrake: hypoBrake,
            sleepRamp: sleepRamp,
            upperTarget: upperTarget
        )
        self.basalIncreaseMilliunits = basalIncreaseMilliunits
        self.cycleInsulinMilliunits = cycleInsulinMilliunits
        self.predictedGlucoseX100 = predictedGlucoseX100
        self.programmedBasalRate = programmedBasalRate
        self.netIobMilliunits = netIobMilliunits
        self.glucoseEstimate = glucoseEstimate
        self.correctionFactor = correctionFactor
        self.tdiEstimate = tdiEstimate
        self.hypoBrake = hypoBrake
        self.sleepRamp = sleepRamp
        self.upperTarget = upperTarget
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        basalIncreaseMilliunits: Int,
        cycleInsulinMilliunits: Int,
        predictedGlucoseX100: Int,
        programmedBasalRate: Int,
        netIobMilliunits: Int,
        glucoseEstimate: Int,
        correctionFactor: Int,
        tdiEstimate: Int,
        hypoBrake: Int,
        sleepRamp: Int,
        upperTarget: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(basalIncreaseMilliunits),
                Bytes.firstTwoBytesLittleEndian(cycleInsulinMilliunits),
                Bytes.firstTwoBytesLittleEndian(predictedGlucoseX100),
                Bytes.firstTwoBytesLittleEndian(programmedBasalRate),
                Bytes.firstTwoBytesLittleEndian(netIobMilliunits),
                Data([UInt8(glucoseEstimate & 0xFF)]),
                Data([UInt8(correctionFactor & 0xFF)]),
                Data([UInt8(tdiEstimate & 0xFF)]),
                Data([UInt8(hypoBrake & 0xFF)]),
                Data([UInt8(sleepRamp & 0xFF)]),
                Data([UInt8(upperTarget & 0xFF)])
            )
        )
    }

    public var predictedGlucoseMgdl: Double { Double(predictedGlucoseX100) / 100.0 }

    /// 0.0 = full brake, 1.0 = none.
    public var hypoBrakeFraction: Double { Double(hypoBrake) / 200.0 }

    override public var description: String {
        "ControlIQCycleHistoryLog(cargo=\(cargo.hexadecimalString), basalIncreaseMilliunits=\(basalIncreaseMilliunits), cycleInsulinMilliunits=\(cycleInsulinMilliunits), predictedGlucoseX100=\(predictedGlucoseX100), programmedBasalRate=\(programmedBasalRate), netIobMilliunits=\(netIobMilliunits), glucoseEstimate=\(glucoseEstimate), correctionFactor=\(correctionFactor), tdiEstimate=\(tdiEstimate), hypoBrake=\(hypoBrake), sleepRamp=\(sleepRamp), upperTarget=\(upperTarget))"
    }
}
