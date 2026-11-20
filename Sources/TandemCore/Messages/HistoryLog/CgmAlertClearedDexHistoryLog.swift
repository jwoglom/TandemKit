import Foundation

public class CgmAlertClearedDexHistoryLog: HistoryLog {
    public static let typeId = 370

    public let alertId: Int

    /// CGMSensorType ordinal; Tandem's export schema lists 0 Invalid, 1 Dexcom G6, 3 Dexcom G7.
    /// Every captured record has 3, all from Dexcom G7 sessions.
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
        let payload = CgmAlertClearedDexHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, alertId: alertId, sensorType: sensorType)
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

    override public var description: String {
        "CgmAlertClearedDexHistoryLog(cargo=\(cargo.hexadecimalString), alertId=\(alertId), alert=\(String(describing: alert)), sensorType=\(sensorType))"
    }
}
