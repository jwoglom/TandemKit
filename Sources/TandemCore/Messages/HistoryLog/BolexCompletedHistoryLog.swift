//
//  BolexCompletedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry when a portion of an extended bolus completes.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/BolexCompletedHistoryLog.java
//
import Foundation

public class BolexCompletedHistoryLog: HistoryLog {
    public static let typeId = 21

    public let completionStatus: Int
    public let bolusId: Int
    public let iob: Float
    public let insulinDelivered: Float
    public let insulinRequested: Float

    public required init(cargo: Data) {
        self.completionStatus = Bytes.readShort(cargo, 10)
        self.bolusId = Bytes.readShort(cargo, 12)
        self.iob = Bytes.readFloat(cargo, 14)
        self.insulinDelivered = Bytes.readFloat(cargo, 18)
        self.insulinRequested = Bytes.readFloat(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, completionStatus: Int, bolusId: Int, iob: Float, insulinDelivered: Float, insulinRequested: Float) {
        let payload = BolexCompletedHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, completionStatus: completionStatus, bolusId: bolusId, iob: iob, insulinDelivered: insulinDelivered, insulinRequested: insulinRequested)
        self.completionStatus = completionStatus
        self.bolusId = bolusId
        self.iob = iob
        self.insulinDelivered = insulinDelivered
        self.insulinRequested = insulinRequested
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, completionStatus: Int, bolusId: Int, iob: Float, insulinDelivered: Float, insulinRequested: Float) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(completionStatus),
                Bytes.firstTwoBytesLittleEndian(bolusId),
                Bytes.toFloat(iob),
                Bytes.toFloat(insulinDelivered),
                Bytes.toFloat(insulinRequested)
            )
        )
    }
}

