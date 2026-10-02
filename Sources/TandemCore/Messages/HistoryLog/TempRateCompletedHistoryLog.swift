//
//  TempRateCompletedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//  Migrated from PumpX2's TempRateCompletedHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/TempRateCompletedHistoryLog.java
//
import Foundation

/// History log entry for completion of a temporary basal rate.
public class TempRateCompletedHistoryLog: HistoryLog {
    public static let typeId = 15

    public let tempRateId: Int
    public let timeLeft: UInt32

    public required init(cargo: Data) {
        tempRateId = Bytes.readShort(cargo, 12)
        timeLeft = Bytes.readUint32(cargo, 14)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, tempRateId: Int, timeLeft: UInt32) {
        let payload = TempRateCompletedHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            tempRateId: tempRateId,
            timeLeft: timeLeft
        )
        self.tempRateId = tempRateId
        self.timeLeft = timeLeft
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, tempRateId: Int, timeLeft: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                // Unparsed; `init(cargo:)` reads tempRateId after it, at 12.
                Data([0, 0]),
                Bytes.firstTwoBytesLittleEndian(tempRateId),
                Bytes.toUint32(timeLeft)
            )
        )
    }

    public var description: String {
        "TempRateCompletedHistoryLog(cargo=\(cargo.hexadecimalString), tempRateId=\(tempRateId), timeLeft=\(timeLeft))"
    }
}
