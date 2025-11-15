//
//  CarbEnteredHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry for carbs entered by the user.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/CarbEnteredHistoryLog.java
//
import Foundation

public class CarbEnteredHistoryLog: HistoryLog {
    public static let typeId = 48

    public let carbs: Float

    public required init(cargo: Data) {
        carbs = Bytes.readFloat(cargo, 10)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, carbs: Float) {
        let payload = CarbEnteredHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, carbs: carbs)
        self.carbs = carbs
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, carbs: Float) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toFloat(carbs)
            )
        )
    }
}
