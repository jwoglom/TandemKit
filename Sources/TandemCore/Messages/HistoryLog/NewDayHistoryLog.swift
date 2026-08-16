//
//  NewDayHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//  Migrated from PumpX2's NewDayHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/NewDayHistoryLog.java
//
import Foundation

/// History log entry marking the start of a new day.
public class NewDayHistoryLog: HistoryLog {
    public static let typeId = 90

    public let commandedBasalRate: Float
    public let featuresBitmask: UInt32
    public let featureBitmaskIndex: UInt32

    public required init(cargo: Data) {
        commandedBasalRate = Bytes.readFloat(cargo, 10)
        featuresBitmask = Bytes.readUint32(cargo, 14)
        featureBitmaskIndex = Bytes.readUint32(cargo, 18)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, commandedBasalRate: Float, featuresBitmask: UInt32, featureBitmaskIndex: UInt32) {
        let payload = NewDayHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            commandedBasalRate: commandedBasalRate,
            featuresBitmask: featuresBitmask,
            featureBitmaskIndex: featureBitmaskIndex
        )
        self.commandedBasalRate = commandedBasalRate
        self.featuresBitmask = featuresBitmask
        self.featureBitmaskIndex = featureBitmaskIndex
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, commandedBasalRate: Float, featuresBitmask: UInt32, featureBitmaskIndex: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toFloat(commandedBasalRate),
                Bytes.toUint32(featuresBitmask),
                Bytes.toUint32(featureBitmaskIndex)
            )
        )
    }

    public var description: String {
        "NewDayHistoryLog(cargo=\(cargo.hexadecimalString), commandedBasalRate=\(commandedBasalRate), featuresBitmask=\(featuresBitmask), featureBitmaskIndex=\(featureBitmaskIndex))"
    }
}
