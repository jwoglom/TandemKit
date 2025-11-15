//
//  TubingFilledHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//  Migrated from PumpX2's TubingFilledHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/TubingFilledHistoryLog.java
//
import Foundation

/// History log entry indicating the pump's tubing was filled.
public class TubingFilledHistoryLog: HistoryLog {
    public static let typeId = 63

    public let primeSize: Float

    public required init(cargo: Data) {
        primeSize = Bytes.readFloat(cargo, 10)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, primeSize: Float) {
        let payload = TubingFilledHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, primeSize: primeSize)
        self.primeSize = primeSize
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, primeSize: Float) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toFloat(primeSize)
            )
        )
    }
}
