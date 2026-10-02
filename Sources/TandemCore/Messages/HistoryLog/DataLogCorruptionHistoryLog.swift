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
        reason = Int(cargo[cargo.startIndex + 14])
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
                Data([UInt8(reason & 0xFF)]),
                Data([0, 0, 0])
            )
        )
    }

    public enum Reason: Int {
        case INVALID_HEADER_ID = 0
        case BAD_INTEGRITY = 1
        case INVALID_BLOCK = 2
        case SPARE_DEACTIVATION_FAILED = 3
        case INVALID_SEQUENCE_NUMBER = 4
        case PATTERN_MISMATCH = 5
        case BAD_FIRST_BLOCK = 6
        case DISCOVERY_BAD_SEQUENCE_NUMBER_INCREMENT = 7
    }

    public var reasonEnum: Reason? {
        Reason(rawValue: reason)
    }

    public var description: String {
        "DataLogCorruptionHistoryLog(cargo=\(cargo.hexadecimalString), block=\(block), reason=\(reason))"
    }
}
