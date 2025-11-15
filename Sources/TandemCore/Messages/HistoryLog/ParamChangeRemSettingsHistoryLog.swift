//
//  ParamChangeRemSettingsHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry for reminder parameter changes.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/ParamChangeRemSettingsHistoryLog.java
//
import Foundation

public class ParamChangeRemSettingsHistoryLog: HistoryLog {
    public static let typeId = 97

    public let modification: Int
    public let status: Int
    public let lowBgThreshold: Int
    public let highBgThreshold: Int
    public let siteChangeDays: Int

    public required init(cargo: Data) {
        modification = Int(cargo[10])
        status = Int(cargo[11])
        lowBgThreshold = Bytes.readShort(cargo, 14)
        highBgThreshold = Bytes.readShort(cargo, 16)
        siteChangeDays = Int(cargo[18])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        modification: Int,
        status: Int,
        lowBgThreshold: Int,
        highBgThreshold: Int,
        siteChangeDays: Int
    ) {
        let payload = ParamChangeRemSettingsHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            modification: modification,
            status: status,
            lowBgThreshold: lowBgThreshold,
            highBgThreshold: highBgThreshold,
            siteChangeDays: siteChangeDays
        )
        self.modification = modification
        self.status = status
        self.lowBgThreshold = lowBgThreshold
        self.highBgThreshold = highBgThreshold
        self.siteChangeDays = siteChangeDays
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        modification: Int,
        status: Int,
        lowBgThreshold: Int,
        highBgThreshold: Int,
        siteChangeDays: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(truncatingIfNeeded: modification)]),
                Data([UInt8(truncatingIfNeeded: status)]),
                Bytes.firstTwoBytesLittleEndian(lowBgThreshold),
                Bytes.firstTwoBytesLittleEndian(highBgThreshold),
                Data([UInt8(truncatingIfNeeded: siteChangeDays)])
            )
        )
    }
}
