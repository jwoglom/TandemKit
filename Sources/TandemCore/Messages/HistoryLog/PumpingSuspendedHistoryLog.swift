//
//  PumpingSuspendedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry indicating pumping was suspended.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/PumpingSuspendedHistoryLog.java
//
import Foundation

public class PumpingSuspendedHistoryLog: HistoryLog {
    public static let typeId = 11

    public let insulinAmount: Int
    public let reasonId: Int

    public required init(cargo: Data) {
        insulinAmount = Bytes.readShort(cargo, 14)
        reasonId = Int(cargo[16])
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, insulinAmount: Int, reasonId: Int) {
        let payload = PumpingSuspendedHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            insulinAmount: insulinAmount,
            reasonId: reasonId
        )
        self.insulinAmount = insulinAmount
        self.reasonId = reasonId
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, insulinAmount: Int, reasonId: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data(repeating: 0, count: 4),
                Bytes.firstTwoBytesLittleEndian(insulinAmount),
                Data([UInt8(reasonId)])
            )
        )
    }

    public enum SuspendReason: Int {
        case userAborted = 0
        case alarm = 1
        case malfunction = 2
        case autoSuspendPredictiveLowGlucose = 6
    }

    public var reason: SuspendReason? {
        SuspendReason(rawValue: reasonId)
    }
}
