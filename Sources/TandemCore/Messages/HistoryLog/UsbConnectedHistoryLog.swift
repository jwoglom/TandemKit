//
//  UsbConnectedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry indicating a USB connection event.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/UsbConnectedHistoryLog.java
//

import Foundation

public class UsbConnectedHistoryLog: HistoryLog {
    public static let typeId = 36

    /// The negotiated current in milliamps.
    public let negotiatedCurrentmA: Float

    public required init(cargo: Data) {
        self.negotiatedCurrentmA = Bytes.readFloat(cargo, 10)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, negotiatedCurrentmA: Float) {
        let payload = UsbConnectedHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, negotiatedCurrentmA: negotiatedCurrentmA)
        self.negotiatedCurrentmA = negotiatedCurrentmA
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, negotiatedCurrentmA: Float) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toFloat(negotiatedCurrentmA)
            )
        )
    }
}

