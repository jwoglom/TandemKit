//
//  BolusCompletedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry when a bolus completes.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/BolusCompletedHistoryLog.java
//
import Foundation

public class BolusCompletedHistoryLog: HistoryLog {
    public static let typeId = 20

    public let completionStatusId: Int
    public let bolusId: Int
    public let iob: Float
    public let insulinDelivered: Float
    public let insulinRequested: Float

    public required init(cargo: Data) {
        completionStatusId = Bytes.readShort(cargo, 10)
        bolusId = Bytes.readShort(cargo, 12)
        iob = Bytes.readFloat(cargo, 14)
        insulinDelivered = Bytes.readFloat(cargo, 18)
        insulinRequested = Bytes.readFloat(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        completionStatusId: Int,
        bolusId: Int,
        iob: Float,
        insulinDelivered: Float,
        insulinRequested: Float
    ) {
        let payload = BolusCompletedHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            completionStatusId: completionStatusId,
            bolusId: bolusId,
            iob: iob,
            insulinDelivered: insulinDelivered,
            insulinRequested: insulinRequested
        )
        self.completionStatusId = completionStatusId
        self.bolusId = bolusId
        self.iob = iob
        self.insulinDelivered = insulinDelivered
        self.insulinRequested = insulinRequested
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        completionStatusId: Int,
        bolusId: Int,
        iob: Float,
        insulinDelivered: Float,
        insulinRequested: Float
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(completionStatusId),
                Bytes.firstTwoBytesLittleEndian(bolusId),
                Bytes.toFloat(iob),
                Bytes.toFloat(insulinDelivered),
                Bytes.toFloat(insulinRequested)
            )
        )
    }

    public var completionStatus: LastBolusStatusAbstractResponse.BolusStatus? {
        LastBolusStatusAbstractResponse.BolusStatus(rawValue: completionStatusId)
    }
}
