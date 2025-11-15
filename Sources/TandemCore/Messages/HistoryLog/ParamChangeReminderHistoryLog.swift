//
//  ParamChangeReminderHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry for time-based reminder parameter changes.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/ParamChangeReminderHistoryLog.java
//
import Foundation

public class ParamChangeReminderHistoryLog: HistoryLog {
    public static let typeId = 96

    public let modification: Int
    public let reminderId: Int
    public let status: Int
    public let enable: Int
    public let frequencyMinutes: UInt32
    public let startTime: Int
    public let endTime: Int
    public let activeDays: Int

    public required init(cargo: Data) {
        modification = Int(cargo[10])
        reminderId = Int(cargo[11])
        status = Int(cargo[12])
        enable = Int(cargo[13])
        frequencyMinutes = Bytes.readUint32(cargo, 14)
        startTime = Bytes.readShort(cargo, 18)
        endTime = Bytes.readShort(cargo, 20)
        activeDays = Int(cargo[22])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        modification: Int,
        reminderId: Int,
        status: Int,
        enable: Int,
        frequencyMinutes: UInt32,
        startTime: Int,
        endTime: Int,
        activeDays: Int
    ) {
        let payload = ParamChangeReminderHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            modification: modification,
            reminderId: reminderId,
            status: status,
            enable: enable,
            frequencyMinutes: frequencyMinutes,
            startTime: startTime,
            endTime: endTime,
            activeDays: activeDays
        )
        self.modification = modification
        self.reminderId = reminderId
        self.status = status
        self.enable = enable
        self.frequencyMinutes = frequencyMinutes
        self.startTime = startTime
        self.endTime = endTime
        self.activeDays = activeDays
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        modification: Int,
        reminderId: Int,
        status: Int,
        enable: Int,
        frequencyMinutes: UInt32,
        startTime: Int,
        endTime: Int,
        activeDays: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(truncatingIfNeeded: modification)]),
                Data([UInt8(truncatingIfNeeded: reminderId)]),
                Data([UInt8(truncatingIfNeeded: status)]),
                Data([UInt8(truncatingIfNeeded: enable)]),
                Bytes.toUint32(frequencyMinutes),
                Bytes.firstTwoBytesLittleEndian(startTime),
                Bytes.firstTwoBytesLittleEndian(endTime),
                Data([UInt8(truncatingIfNeeded: activeDays)])
            )
        )
    }
}
