//
//  TempRateActivatedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//  Migrated from PumpX2's TempRateActivatedHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/TempRateActivatedHistoryLog.java
//
import Foundation

/// History log entry for activation of a temporary basal rate.
public class TempRateActivatedHistoryLog: HistoryLog {
    public static let typeId = 2

    public let percent: Float
    public let duration: Float
    public let tempRateId: Int

    public required init(cargo: Data) {
        self.percent = Bytes.readFloat(cargo, 10)
        self.duration = Bytes.readFloat(cargo, 14)
        self.tempRateId = Bytes.readShort(cargo, 20)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, percent: Float, duration: Float, tempRateId: Int) {
        let payload = TempRateActivatedHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, percent: percent, duration: duration, tempRateId: tempRateId)
        self.percent = percent
        self.duration = duration
        self.tempRateId = tempRateId
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, percent: Float, duration: Float, tempRateId: Int) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toFloat(percent),
                Bytes.toFloat(duration),
                Bytes.firstTwoBytesLittleEndian(tempRateId)
            )
        )
    }
}

