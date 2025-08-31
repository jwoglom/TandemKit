//
//  UsbEnumeratedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry indicating the USB interface was enumerated.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/UsbEnumeratedHistoryLog.java
//

import Foundation

public class UsbEnumeratedHistoryLog: HistoryLog {
    public static let typeId = 67

    /// The negotiated current in milliamps during enumeration.
    public let negotiatedCurrentmA: Int

    public required init(cargo: Data) {
        self.negotiatedCurrentmA = Int(cargo[10])
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, negotiatedCurrentmA: Int) {
        let payload = UsbEnumeratedHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, negotiatedCurrentmA: negotiatedCurrentmA)
        self.negotiatedCurrentmA = negotiatedCurrentmA
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, negotiatedCurrentmA: Int) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(negotiatedCurrentmA & 0xFF)])
            )
        )
    }
}

