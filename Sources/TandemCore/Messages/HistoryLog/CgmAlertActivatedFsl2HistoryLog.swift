import Foundation

/// Layout mirrors `CgmAlertActivatedDexHistoryLog` (369) and Tandem's cloud-export schema; no
/// FreeStyle Libre 2 record has been captured to confirm it.
public class CgmAlertActivatedFsl2HistoryLog: HistoryLog {
    public static let typeId = 460

    public let alertId: Int

    /// Tandem's export schema maps 0 to Invalid and 2 to CGM_TYPE_LIBRE2 for this opcode.
    public let sensorType: Int

    public let faultLocatorData: UInt32

    public let param1: UInt32

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
        let payload = CgmAlertActivatedFsl2HistoryLog.buildCargo(
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

    public var description: String {
        "CgmAlertActivatedFsl2HistoryLog(cargo=\(cargo.hexadecimalString), alertId=\(alertId), alert=\(String(describing: alert)), sensorType=\(sensorType), faultLocatorData=\(faultLocatorData), param1=\(param1), param2=\(param2))"
    }
}
