import Foundation

public class CgmAlertAckDexHistoryLog: HistoryLog {
    public static let typeId = 371

    public let alertId: Int

    /// CGMSensorType ordinal; Tandem's export schema lists 0 Invalid, 1 Dexcom G6, 3 Dexcom G7.
    /// Every captured record has 3, all from Dexcom G7 sessions.
    public let sensorType: Int

    /// Raw `AckSource`: 0 acknowledged by the user, 1 by software (Tandem's export schema).
    public let ackSource: UInt32

    public var alert: CGMAlertStatusResponse.CGMAlert? {
        CGMAlertStatusResponse.CGMAlert(rawValue: alertId)
    }

    public var sensorTypeEnum: CGMStatusV2Response.CGMSensorType {
        CGMStatusV2Response.CGMSensorType(rawValue: sensorType) ?? .unknown
    }

    public var ackSourceEnum: AckSource? {
        AckSource(rawValue: ackSource)
    }

    public enum AckSource: UInt32 {
        case user = 0
        case software = 1
    }

    public required init(cargo: Data) {
        let raw = HistoryLog.fillCargo(cargo)
        alertId = Int(raw[10])
        sensorType = Int(raw[11])
        ackSource = Bytes.readUint32(raw, 14)
        super.init(cargo: raw)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, alertId: Int, sensorType: Int, ackSource: UInt32) {
        let payload = CgmAlertAckDexHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, alertId: alertId, sensorType: sensorType, ackSource: ackSource)
        self.alertId = alertId
        self.sensorType = sensorType
        self.ackSource = ackSource
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, alertId: Int, sensorType: Int, ackSource: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(alertId & 0xFF)]),
                Data([UInt8(sensorType & 0xFF)]),
                Bytes.emptyBytes(2),
                Bytes.toUint32(ackSource)
            )
        )
    }

    public var description: String {
        "CgmAlertAckDexHistoryLog(cargo=\(cargo.hexadecimalString), alertId=\(alertId), alert=\(String(describing: alert)), sensorType=\(sensorType), ackSource=\(ackSource))"
    }
}
