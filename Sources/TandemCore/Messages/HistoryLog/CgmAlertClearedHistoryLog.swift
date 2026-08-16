import Foundation

public class CgmAlertClearedHistoryLog: HistoryLog {
    public static let typeId = 172

    public let alertId: UInt32

    public var alert: CGMAlertStatusResponse.CGMAlert? {
        CGMAlertStatusResponse.CGMAlert(rawValue: Int(alertId))
    }

    public required init(cargo: Data) {
        alertId = Bytes.readUint32(cargo, 10)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, alertId: UInt32) {
        let payload = CgmAlertClearedHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, alertId: alertId)
        self.alertId = alertId
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, alertId: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(alertId)
            )
        )
    }
}
