//
//  DailyBasalHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//  Migrated from PumpX2's DailyBasalHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/DailyBasalHistoryLog.java
//
import Foundation

/// History log entry summarizing daily basal delivery.
public class DailyBasalHistoryLog: HistoryLog {
    public static let typeId = 81

    public let dailyTotalBasal: Float
    public let lastBasalRate: Float
    public let iob: Float
    public let finalEventForDay: Bool
    public let batteryChargeRaw: Int
    public let lipoMv: Int

    public required init(cargo: Data) {
        dailyTotalBasal = Bytes.readFloat(cargo, 10)
        lastBasalRate = Bytes.readFloat(cargo, 14)
        iob = Bytes.readFloat(cargo, 18)
        finalEventForDay = cargo[22] == 1
        batteryChargeRaw = Int(cargo[23])
        lipoMv = Bytes.readShort(cargo, 24)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        dailyTotalBasal: Float,
        lastBasalRate: Float,
        iob: Float,
        finalEventForDay: Bool,
        batteryChargeRaw: Int,
        lipoMv: Int
    ) {
        let payload = DailyBasalHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            dailyTotalBasal: dailyTotalBasal,
            lastBasalRate: lastBasalRate,
            iob: iob,
            finalEventForDay: finalEventForDay,
            batteryChargeRaw: batteryChargeRaw,
            lipoMv: lipoMv
        )
        self.dailyTotalBasal = dailyTotalBasal
        self.lastBasalRate = lastBasalRate
        self.iob = iob
        self.finalEventForDay = finalEventForDay
        self.batteryChargeRaw = batteryChargeRaw
        self.lipoMv = lipoMv
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        dailyTotalBasal: Float,
        lastBasalRate: Float,
        iob: Float,
        finalEventForDay: Bool,
        batteryChargeRaw: Int,
        lipoMv: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toFloat(dailyTotalBasal),
                Bytes.toFloat(lastBasalRate),
                Bytes.toFloat(iob),
                Data([finalEventForDay ? 1 : 0]),
                Data([UInt8(batteryChargeRaw & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(lipoMv)
            )
        )
    }
}
