//
//  BolexActivatedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry when an extended bolus is activated.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/BolexActivatedHistoryLog.java
//
import Foundation

public class BolexActivatedHistoryLog: HistoryLog {
    public static let typeId = 59

    public let bolusId: Int
    public let iob: Float
    public let bolexSize: Float

    public required init(cargo: Data) {
        bolusId = Bytes.readShort(cargo, 10)
        iob = Bytes.readFloat(cargo, 14)
        bolexSize = Bytes.readFloat(cargo, 18)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, bolusId: Int, iob: Float, bolexSize: Float) {
        let payload = BolexActivatedHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            bolusId: bolusId,
            iob: iob,
            bolexSize: bolexSize
        )
        self.bolusId = bolusId
        self.iob = iob
        self.bolexSize = bolexSize
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, bolusId: Int, iob: Float, bolexSize: Float) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(bolusId),
                Bytes.toFloat(iob),
                Bytes.toFloat(bolexSize)
            )
        )
    }
}
