//
//  PumpingResumedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry indicating pumping was resumed.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/PumpingResumedHistoryLog.java
//
import Foundation

public class PumpingResumedHistoryLog: HistoryLog {
    public static let typeId = 12

    /// Pump state before the resume. Observed as 100 in every record captured so far, on both
    /// t:slim X2 and Mobi; no other value has been seen (pumpX2 issue 40).
    public let preResumeState: UInt32

    /// Insulin remaining in the reservoir at the instant of the resume, in whole units, exactly as
    /// the pump reports it: byte-identical to `InsulinStatusResponse.currentInsulinAmount` polled
    /// within two seconds in 4/4 resumes (and 4/4 suspends) of a Mobi capture. It is the remaining
    /// amount, not a fill level and not insulin on board. After a tubing fill on the same cartridge
    /// it read 90 where the paired suspend read 110; after a cartridge change it read 185 (equal to
    /// `CartridgeFilledHistoryLog.insulinDisplay` in the same second) where the paired suspend read
    /// 8. Resolves the field's open question in pumpX2 issue 40.
    public let insulinAmount: Int

    public required init(cargo: Data) {
        preResumeState = Bytes.readUint32(cargo, 10)
        insulinAmount = Bytes.readShort(cargo, 14)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, preResumeState: UInt32, insulinAmount: Int) {
        let payload = PumpingResumedHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            preResumeState: preResumeState,
            insulinAmount: insulinAmount
        )
        self.preResumeState = preResumeState
        self.insulinAmount = insulinAmount
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, preResumeState: UInt32, insulinAmount: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(preResumeState),
                Bytes.firstTwoBytesLittleEndian(insulinAmount)
            )
        )
    }

    override public var description: String {
        "PumpingResumedHistoryLog(cargo=\(cargo.hexadecimalString), preResumeState=\(preResumeState), insulinAmount=\(insulinAmount))"
    }
}
