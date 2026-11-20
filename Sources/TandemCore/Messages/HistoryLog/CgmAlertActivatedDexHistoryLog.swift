import Foundation

public class CgmAlertActivatedDexHistoryLog: HistoryLog {
    public static let typeId = 369

    public let alertId: Int

    /// CGMSensorType ordinal; Tandem's export schema lists 0 Invalid, 1 Dexcom G6, 3 Dexcom G7.
    /// Every captured record has 3, all from Dexcom G7 sessions.
    public let sensorType: Int

    /// An opaque code identifying the firmware location which raised this alert. Field name and
    /// position are taken from tconnectsync's cloud-export schema; the values are stable per
    /// alertId in the capture used to validate this field, but their internal structure is not
    /// otherwise documented.
    public let faultLocatorData: UInt32

    /// The measured value associated with the alert (e.g. the glucose reading, in mg/dL, that
    /// triggered a threshold alert), as an unsigned 32-bit integer.
    public let param1: UInt32

    /// The threshold or configured setpoint associated with the alert (e.g. 80.0 or 200.0 mg/dL
    /// for low/high glucose alerts).
    public let param2: Float

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
        faultLocatorData = Bytes.readUint32(raw, 14)
        param1 = Bytes.readUint32(raw, 18)
        param2 = Bytes.readFloat(raw, 22)
        super.init(cargo: raw)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        alertId: Int,
        sensorType: Int,
        faultLocatorData: UInt32,
        param1: UInt32,
        param2: Float
    ) {
        let payload = CgmAlertActivatedDexHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            alertId: alertId,
            sensorType: sensorType,
            faultLocatorData: faultLocatorData,
            param1: param1,
            param2: param2
        )
        self.alertId = alertId
        self.sensorType = sensorType
        self.faultLocatorData = faultLocatorData
        self.param1 = param1
        self.param2 = param2
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        alertId: Int,
        sensorType: Int,
        faultLocatorData: UInt32,
        param1: UInt32,
        param2: Float
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(alertId & 0xFF)]),
                Data([UInt8(sensorType & 0xFF)]),
                Bytes.emptyBytes(2),
                Bytes.toUint32(faultLocatorData),
                Bytes.toUint32(param1),
                Bytes.toFloat(param2)
            )
        )
    }

    override public var description: String {
        "CgmAlertActivatedDexHistoryLog(cargo=\(cargo.hexadecimalString), alertId=\(alertId), alert=\(String(describing: alert)), sensorType=\(sensorType), faultLocatorData=\(faultLocatorData), param1=\(param1), param2=\(param2))"
    }
}
