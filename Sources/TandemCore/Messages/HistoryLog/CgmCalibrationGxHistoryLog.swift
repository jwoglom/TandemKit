//
//  CgmCalibrationGxHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//  Migrated from PumpX2's CgmCalibrationGxHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/CgmCalibrationGxHistoryLog.java
//

import Foundation

/// History log entry for GX CGM calibration value.
public class CgmCalibrationGxHistoryLog: HistoryLog {
    public static let typeId = 210

    public let value: Int

    public required init(cargo: Data) {
        self.value = Bytes.readShort(cargo, 10)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, value: Int) {
        let payload = CgmCalibrationGxHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, value: value)
        self.value = value
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, value: Int) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(value)
            )
        )
    }
}

