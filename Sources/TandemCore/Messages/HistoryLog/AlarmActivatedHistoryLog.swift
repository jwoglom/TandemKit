//
//  AlarmActivatedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry indicating an alarm was activated.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/AlarmActivatedHistoryLog.java
//

import Foundation

public class AlarmActivatedHistoryLog: HistoryLog {
    public static let typeId = 5

    public let alarmId: UInt32

    public required init(cargo: Data) {
        self.alarmId = Bytes.readUint32(cargo, 10)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, alarmId: UInt32) {
        let payload = AlarmActivatedHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, alarmId: alarmId)
        self.alarmId = alarmId
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, alarmId: UInt32) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(alarmId)
            )
        )
    }

    public var alarmResponseType: AlarmStatusResponse.AlarmResponseType? {
        AlarmStatusResponse.AlarmResponseType(rawValue: Int(alarmId))
    }
}

