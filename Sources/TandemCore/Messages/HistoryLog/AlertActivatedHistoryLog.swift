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
    public let faultLocatorData: UInt32
    public let param1: UInt32
    public let param2: Float

    public required init(cargo: Data) {
        alertId = Bytes.readUint32(cargo, 10)
        faultLocatorData = Bytes.readUint32(cargo, 14)
        param1 = Bytes.readUint32(cargo, 18)
        param2 = Bytes.readFloat(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        alertId: UInt32,
        faultLocatorData: UInt32 = 0,
        param1: UInt32 = 0,
        param2: Float = 0
    ) {
        let payload = AlertActivatedHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            alertId: alertId,
            faultLocatorData: faultLocatorData,
            param1: param1,
            param2: param2
        )
        self.alertId = alertId
        self.faultLocatorData = faultLocatorData
        self.param1 = param1
        self.param2 = param2
        super.init(cargo: payload)
    }

    public convenience init(alertId: UInt32, faultLocatorData: UInt32, param1: UInt32, param2: Float) {
        self.init(pumpTimeSec: 0, sequenceNum: 0, alertId: alertId, faultLocatorData: faultLocatorData, param1: param1, param2: param2)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        alertId: UInt32,
        faultLocatorData: UInt32 = 0,
        param1: UInt32 = 0,
        param2: Float = 0
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(alertId),
                Bytes.toUint32(faultLocatorData),
                Bytes.toUint32(param1),
                Bytes.toFloat(param2)
            )
        )
    }

    public var alertResponseType: AlertStatusResponse.AlertResponseType? {
        AlertStatusResponse.AlertResponseType(rawValue: Int(alertId))
    }

    public var description: String {
        "AlertActivatedHistoryLog(cargo=\(cargo.hexadecimalString), alertResponseType=\(String(describing: alertResponseType)), alertId=\(alertId), faultLocatorData=\(faultLocatorData), param1=\(param1), param2=\(param2))"
    }
}
