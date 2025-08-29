//
//  PumpingResumedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry indicating pumping was resumed.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/PumpingResumedHistoryLog.java
//
import Foundation

public class PumpingResumedHistoryLog: HistoryLog {
    public static let typeId = 12

    public let insulinAmount: Int

    public required init(cargo: Data) {
        self.insulinAmount = Bytes.readShort(cargo, 14)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, insulinAmount: Int) {
        let payload = PumpingResumedHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, insulinAmount: insulinAmount)
        self.insulinAmount = insulinAmount
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, insulinAmount: Int) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data(repeating: 0, count: 4),
                Bytes.firstTwoBytesLittleEndian(insulinAmount)
            )
        )
    }
}

