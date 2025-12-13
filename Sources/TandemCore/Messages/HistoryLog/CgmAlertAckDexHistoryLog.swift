import Foundation

/// History log entry for Dexcom CGM alert acknowledgements.
public class CgmAlertAckDexHistoryLog: HistoryLog {
    public static let typeId = 371

    public let alertId: UInt32
    public let alert: CGMAlertStatusResponse.CGMAlert?

    public required init(cargo: Data) {
        alertId = Bytes.readUint32(cargo, 10)
        alert = CGMAlertStatusResponse.CGMAlert(rawValue: Int(alertId))
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, alertId: UInt32) {
        let payload = CgmAlertAckDexHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, alertId: alertId)
        self.alertId = alertId
        alert = CGMAlertStatusResponse.CGMAlert(rawValue: Int(alertId))
        super.init(cargo: payload)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, alert: CGMAlertStatusResponse.CGMAlert) {
        self.init(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, alertId: UInt32(alert.rawValue))
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, alertId: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), UInt8((typeId >> 8) & 0xFF)]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(alertId)
            )
        )
    }
}

public extension CgmAlertAckDexHistoryLog {
    var description: String {
        "CgmAlertAckDexHistoryLog(cargo=\(cargo.hexadecimalString), alertId=\(alertId), alert=\(String(describing: alert)))"
    }
}
