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
    public let completionStatusRaw: UInt32
    /// The position (counts) at which tubing fill completed.
    public let position: UInt32

    public required init(cargo: Data) {
        primeSize = Bytes.readFloat(cargo, 10)
        completionStatusRaw = Bytes.readUint32(cargo, 14)
        position = Bytes.readUint32(cargo, 18)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, primeSize: Float, completionStatus: UInt32, position: UInt32) {
        let payload = TubingFilledHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, primeSize: primeSize, completionStatus: completionStatus, position: position)
        self.primeSize = primeSize
        self.completionStatusRaw = completionStatus
        self.position = position
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, primeSize: Float, completionStatus: UInt32, position: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toFloat(primeSize),
                Bytes.toUint32(completionStatus),
                Bytes.toUint32(position)
            )
        )
    }

    public enum CompletionStatus: Int {
        case userAborted = 0
        case terminatedByAlarm = 1
        case terminatedByMalfunction = 2
        case completed = 3
    }

    public var completionStatus: CompletionStatus? {
        CompletionStatus(rawValue: Int(completionStatusRaw))
    }

    override public var description: String {
        "TubingFilledHistoryLog(cargo=\(cargo.hexadecimalString), primeSize=\(primeSize), completionStatusRaw=\(completionStatusRaw), position=\(position))"
    }
}
