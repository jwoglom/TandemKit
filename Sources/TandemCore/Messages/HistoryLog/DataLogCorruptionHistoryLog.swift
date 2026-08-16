//
//  DataLogCorruptionHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//  Migrated from PumpX2's DataLogCorruptionHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/DataLogCorruptionHistoryLog.java
//
import Foundation

/// History log entry indicating data log corruption.
public class DataLogCorruptionHistoryLog: HistoryLog {
    public static let typeId = 60

    public let block: UInt32
    public let reason: Int

    public required init(cargo: Data) {
        block = Bytes.readUint32(cargo, 10)
        reason = Int(cargo[cargo.startIndex + 17])
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, block: UInt32, reason: Int) {
        let payload = DataLogCorruptionHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            block: block,
            reason: reason
        )
        self.block = block
        self.reason = reason
        super.init(cargo: payload)
    }

    public convenience init(block: UInt32, reason: Int) {
        self.init(pumpTimeSec: 0, sequenceNum: 0, block: block, reason: reason)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, block: UInt32, reason: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(block),
                Data([0, 0, 0]),
                Data([UInt8(reason & 0xFF)])
            )
        )
    }

    public var description: String {
        "DataLogCorruptionHistoryLog(cargo=\(cargo.hexadecimalString), block=\(block), reason=\(reason))"
    }
}
