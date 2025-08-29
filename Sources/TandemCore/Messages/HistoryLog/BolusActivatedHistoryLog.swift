//
//  BolusActivatedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry when a bolus is activated.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/BolusActivatedHistoryLog.java
//
import Foundation

public class BolusActivatedHistoryLog: HistoryLog {
    public static let typeId = 55

    public let bolusId: Int
    public let iob: Float
    public let bolusSize: Float

    public required init(cargo: Data) {
        self.bolusId = Bytes.readShort(cargo, 10)
        self.iob = Bytes.readFloat(cargo, 14)
        self.bolusSize = Bytes.readFloat(cargo, 18)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, bolusId: Int, iob: Float, bolusSize: Float) {
        let payload = BolusActivatedHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, bolusId: bolusId, iob: iob, bolusSize: bolusSize)
        self.bolusId = bolusId
        self.iob = iob
        self.bolusSize = bolusSize
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, bolusId: Int, iob: Float, bolusSize: Float) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(bolusId),
                Bytes.toFloat(iob),
                Bytes.toFloat(bolusSize)
            )
        )
    }
}

