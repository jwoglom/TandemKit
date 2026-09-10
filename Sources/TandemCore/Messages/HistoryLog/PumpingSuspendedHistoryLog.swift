//
//  PumpingSuspendedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry indicating pumping was suspended.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/PumpingSuspendedHistoryLog.java
//
import Foundation

public class PumpingSuspendedHistoryLog: HistoryLog {
    public static let typeId = 11

    /// Pump state before the suspend. 106 in every record observed so far, across t:slim X2 and
    /// Mobi captures and both user-initiated and alarm-triggered suspends, so no variation has
    /// been seen yet.
    public let preSuspendState: UInt32
    /// Insulin remaining in the reservoir as the pump reports it at the instant of the suspend,
    /// in whole units. Byte-identical to `InsulinStatusResponse.currentInsulinAmount` polled
    /// within two seconds in 4/4 suspends (and 4/4 paired resumes) of a Mobi capture
    /// (pumpX2 issue #39). It is not the cartridge fill level (it dropped 110 to 90 across a
    /// tubing fill on the same cartridge) and it is not insulin on board.
    public let insulinAmount: Int
    /// Raw suspend reason; see `SuspendReason` / `reason` for the decoded value.
    public let reasonId: Int
    /// Resume-pump alert timeout in minutes. 15 on every observed suspend; suspensions lasting
    /// longer than 15 minutes raised RESUME_PUMP_ALARM (18) and RESUME_PUMP_ALARM2 (23) at
    /// 15 min 1 s after the suspend.
    public let rpaTimeout: Int

    public required init(cargo: Data) {
        preSuspendState = Bytes.readUint32(cargo, 10)
        insulinAmount = Bytes.readShort(cargo, 14)
        reasonId = Int(cargo[16])
        rpaTimeout = Int(cargo[17])
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, preSuspendState: UInt32, insulinAmount: Int, reasonId: Int, rpaTimeout: Int) {
        let payload = PumpingSuspendedHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            preSuspendState: preSuspendState,
            insulinAmount: insulinAmount,
            reasonId: reasonId,
            rpaTimeout: rpaTimeout
        )
        self.preSuspendState = preSuspendState
        self.insulinAmount = insulinAmount
        self.reasonId = reasonId
        self.rpaTimeout = rpaTimeout
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, preSuspendState: UInt32, insulinAmount: Int, reasonId: Int, rpaTimeout: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(preSuspendState),
                Bytes.firstTwoBytesLittleEndian(insulinAmount),
                Data([UInt8(reasonId)]),
                Data([UInt8(rpaTimeout)])
            )
        )
    }

    public enum SuspendReason: Int {
        case userAborted = 0
        case alarm = 1
        case malfunction = 2
        case autoSuspendPredictiveLowGlucose = 6
    }

    public var reason: SuspendReason? {
        SuspendReason(rawValue: reasonId)
    }

    public var description: String {
        "PumpingSuspendedHistoryLog(cargo=\(cargo.hexadecimalString), preSuspendState=\(preSuspendState), insulinAmount=\(insulinAmount), reason=\(String(describing: reason)), reasonId=\(reasonId), rpaTimeout=\(rpaTimeout))"
    }
}
