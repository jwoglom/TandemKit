//
//  HistoryLogRecord.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Base class for pump history log records.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/HistoryLog.java
//

import Foundation

/// Base class representing a single 26-byte history log entry.
open class HistoryLog {
    public static let length = 26

    public let cargo: Data
    public let typeId: Int
    public let pumpTimeSec: UInt32
    public let sequenceNum: UInt32

    public required init(cargo: Data) {
        let filled = HistoryLog.fillCargo(cargo)
        self.cargo = filled
        self.typeId = Int(Bytes.readShort(filled, 0) & 0x0FFF)
        self.pumpTimeSec = Bytes.readUint32(filled, 2)
        self.sequenceNum = Bytes.readUint32(filled, 6)
    }

    /// Pads or truncates cargo to the standard 26-byte length.
    public static func fillCargo(_ cargo: Data) -> Data {
        if cargo.count == length {
            return cargo
        }
        var ret = Data(count: length)
        ret.replaceSubrange(0..<min(cargo.count, length), with: cargo.prefix(length))
        return ret
    }
}

