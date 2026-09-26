import Foundation

/// Layout mirrors `CgmAlertClearedDexHistoryLog` (370) and Tandem's cloud-export schema; no
/// FreeStyle Libre 2 record has been captured to confirm it.
public class CgmAlertClearedFsl2HistoryLog: HistoryLog {
    public static let typeId = 461

    public let alertId: Int

    /// Tandem's export schema maps 0 to Invalid and 2 to CGM_TYPE_LIBRE2 for this opcode.
    public let sensorType: Int

    public var alert: CGMAlertStatusResponse.CGMAlert? {
        CGMAlertStatusResponse.CGMAlert(rawValue: alertId)
    }

    public var sensorTypeEnum: CGMStatusV2Response.CGMSensorType {
        CGMStatusV2Response.CGMSensorType(rawValue: sensorType) ?? .unknown
    }

    public required init(cargo: Data) {
        let raw = HistoryLog.fillCargo(cargo)
        alertId = Int(raw[10])
        sensorType = Int(raw[11])
        super.init(cargo: raw)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, alertId: Int, sensorType: Int) {
        let payload = CgmAlertClearedFsl2HistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, alertId: alertId, sensorType: sensorType)
        self.alertId = alertId
        self.sensorType = sensorType
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, alertId: Int, sensorType: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(alertId & 0xFF)]),
                Data([UInt8(sensorType & 0xFF)])
            )
        )
    }

    public var description: String {
        "CgmAlertClearedFsl2HistoryLog(cargo=\(cargo.hexadecimalString), alertId=\(alertId), alert=\(String(describing: alert)), sensorType=\(sensorType))"
    }
}
