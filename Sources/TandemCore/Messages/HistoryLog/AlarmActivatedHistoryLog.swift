//
//  AlarmActivatedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry indicating an alarm was activated.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/AlarmActivatedHistoryLog.java
//
import Foundation

public class AlarmActivatedHistoryLog: HistoryLog {
    public static let typeId = 5

    public let alarmId: UInt32
    public let faultLocatorData: UInt32
    public let param1: UInt32
    public let param2: Float

    public required init(cargo: Data) {
        alarmId = Bytes.readUint32(cargo, 10)
        faultLocatorData = Bytes.readUint32(cargo, 14)
        param1 = Bytes.readUint32(cargo, 18)
        param2 = Bytes.readFloat(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        alarmId: UInt32,
        faultLocatorData: UInt32 = 0,
        param1: UInt32 = 0,
        param2: Float = 0
    ) {
        let payload = AlarmActivatedHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            alarmId: alarmId,
            faultLocatorData: faultLocatorData,
            param1: param1,
            param2: param2
        )
        self.alarmId = alarmId
        self.faultLocatorData = faultLocatorData
        self.param1 = param1
        self.param2 = param2
        super.init(cargo: payload)
    }

    public convenience init(alarmId: UInt32, faultLocatorData: UInt32, param1: UInt32, param2: Float) {
        self.init(pumpTimeSec: 0, sequenceNum: 0, alarmId: alarmId, faultLocatorData: faultLocatorData, param1: param1, param2: param2)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        alarmId: UInt32,
        faultLocatorData: UInt32 = 0,
        param1: UInt32 = 0,
        param2: Float = 0
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(alarmId),
                Bytes.toUint32(faultLocatorData),
                Bytes.toUint32(param1),
                Bytes.toFloat(param2)
            )
        )
    }

    public var alarmResponseType: AlarmStatusResponse.AlarmResponseType? {
        AlarmStatusResponse.AlarmResponseType(rawValue: Int(alarmId))
    }

    public var description: String {
        "AlarmActivatedHistoryLog(cargo=\(cargo.hexadecimalString), alarmResponseType=\(String(describing: alarmResponseType)), alarmId=\(alarmId), faultLocatorData=\(faultLocatorData), param1=\(param1), param2=\(param2))"
    }
}
