//
//  BolusRequestedMsg3HistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Third part of a multi-message bolus request log.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/BolusRequestedMsg3HistoryLog.java
//
import Foundation

public class BolusRequestedMsg3HistoryLog: HistoryLog {
    public static let typeId = 66

    public let bolusId: Int
    public let spare: Int
    public let foodBolusSize: Float
    public let correctionBolusSize: Float
    public let totalBolusSize: Float

    public required init(cargo: Data) {
        self.bolusId = Bytes.readShort(cargo, 10)
        self.spare = Bytes.readShort(cargo, 12)
        self.foodBolusSize = Bytes.readFloat(cargo, 14)
        self.correctionBolusSize = Bytes.readFloat(cargo, 18)
        self.totalBolusSize = Bytes.readFloat(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, bolusId: Int, spare: Int, foodBolusSize: Float, correctionBolusSize: Float, totalBolusSize: Float) {
        let payload = BolusRequestedMsg3HistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, bolusId: bolusId, spare: spare, foodBolusSize: foodBolusSize, correctionBolusSize: correctionBolusSize, totalBolusSize: totalBolusSize)
        self.bolusId = bolusId
        self.spare = spare
        self.foodBolusSize = foodBolusSize
        self.correctionBolusSize = correctionBolusSize
        self.totalBolusSize = totalBolusSize
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, bolusId: Int, spare: Int, foodBolusSize: Float, correctionBolusSize: Float, totalBolusSize: Float) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(bolusId),
                Bytes.firstTwoBytesLittleEndian(spare),
                Bytes.toFloat(foodBolusSize),
                Bytes.toFloat(correctionBolusSize),
                Bytes.toFloat(totalBolusSize)
            )
        )
    }
}

