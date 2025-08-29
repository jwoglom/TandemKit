//
//  BasalRateChangeHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry indicating a basal rate change.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/BasalRateChangeHistoryLog.java
//
import Foundation

public class BasalRateChangeHistoryLog: HistoryLog {
    public static let typeId = 3

    public let commandBasalRate: Float
    public let baseBasalRate: Float
    public let maxBasalRate: Float
    public let insulinDeliveryProfile: Int
    public let changeTypeId: Int

    public required init(cargo: Data) {
        self.commandBasalRate = Bytes.readFloat(cargo, 10)
        self.baseBasalRate = Bytes.readFloat(cargo, 14)
        self.maxBasalRate = Bytes.readFloat(cargo, 18)
        self.insulinDeliveryProfile = Bytes.readShort(cargo, 22)
        self.changeTypeId = Int(cargo[24])
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, commandBasalRate: Float, baseBasalRate: Float, maxBasalRate: Float, insulinDeliveryProfile: Int, changeTypeId: Int) {
        let payload = BasalRateChangeHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, commandBasalRate: commandBasalRate, baseBasalRate: baseBasalRate, maxBasalRate: maxBasalRate, insulinDeliveryProfile: insulinDeliveryProfile, changeTypeId: changeTypeId)
        self.commandBasalRate = commandBasalRate
        self.baseBasalRate = baseBasalRate
        self.maxBasalRate = maxBasalRate
        self.insulinDeliveryProfile = insulinDeliveryProfile
        self.changeTypeId = changeTypeId
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, commandBasalRate: Float, baseBasalRate: Float, maxBasalRate: Float, insulinDeliveryProfile: Int, changeTypeId: Int) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toFloat(commandBasalRate),
                Bytes.toFloat(baseBasalRate),
                Bytes.toFloat(maxBasalRate),
                Bytes.firstTwoBytesLittleEndian(insulinDeliveryProfile),
                Data([UInt8(changeTypeId), 0])
            )
        )
    }

    public enum ChangeType: Int {
        case timedSegment = 1
        case newProfile = 2
        case tempRateStart = 4
        case tempRateEnd = 8
        case pumpSuspended = 16
        case pumpResumed = 32
        case pumpShutDown = 64
    }

    public var changeType: ChangeType? {
        ChangeType(rawValue: changeTypeId)
    }
}

