//
//  DateChangeHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//  Migrated from PumpX2's DateChangeHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/DateChangeHistoryLog.java
//
import Foundation

/// History log entry recording a change in the pump's date.
public class DateChangeHistoryLog: HistoryLog {
    public static let typeId = 14

    public let datePrior: UInt32
    public let dateAfter: UInt32
    public let rawRTCTime: UInt32

    public required init(cargo: Data) {
        datePrior = Bytes.readUint32(cargo, 10)
        dateAfter = Bytes.readUint32(cargo, 14)
        rawRTCTime = Bytes.readUint32(cargo, 18)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, datePrior: UInt32, dateAfter: UInt32, rawRTCTime: UInt32) {
        let payload = DateChangeHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            datePrior: datePrior,
            dateAfter: dateAfter,
            rawRTCTime: rawRTCTime
        )
        self.datePrior = datePrior
        self.dateAfter = dateAfter
        self.rawRTCTime = rawRTCTime
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        datePrior: UInt32,
        dateAfter: UInt32,
        rawRTCTime: UInt32
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(datePrior),
                Bytes.toUint32(dateAfter),
                Bytes.toUint32(rawRTCTime),
                Data(count: 4)
            )
        )
    }
}
