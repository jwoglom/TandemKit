//
//  AlertActivatedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry indicating an alert was activated.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/AlertActivatedHistoryLog.java
//
import Foundation

public class AlertActivatedHistoryLog: HistoryLog {
    public static let typeId = 4

    public let alertId: UInt32

    public required init(cargo: Data) {
        alertId = Bytes.readUint32(cargo, 10)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, alertId: UInt32) {
        let payload = AlertActivatedHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, alertId: alertId)
        self.alertId = alertId
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, alertId: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(alertId)
            )
        )
    }

    public var alertResponseType: AlertStatusResponse.AlertResponseType? {
        AlertStatusResponse.AlertResponseType(rawValue: Int(alertId))
    }
}
