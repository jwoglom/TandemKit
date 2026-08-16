import Foundation

public class CgmAlertAckDexHistoryLog: HistoryLog {
    public static let typeId = 371

    public let alertId: Int

    /// The type of glucose sensor which raised the alert. Constant (3) in every captured record;
    /// the meaning of other values is unconfirmed.
    public let sensorType: Int

    /// Identifies what acknowledged the alert (e.g. pump GUI vs. a paired device). Field name is
    /// taken from tconnectsync's cloud-export schema; only value 0 (unacknowledged/default) and 1
    /// are present in the capture used to validate this field.
    public let ackSource: UInt32

    public var alert: CGMAlertStatusResponse.CGMAlert? {
        CGMAlertStatusResponse.CGMAlert(rawValue: alertId)
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
