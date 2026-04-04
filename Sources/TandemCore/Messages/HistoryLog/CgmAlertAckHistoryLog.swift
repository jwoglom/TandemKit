import Foundation

public class CgmAlertAckHistoryLog: HistoryLog {
    public static let typeId = 173

    public let alertId: UInt32

    public required init(cargo: Data) {
        alertId = Bytes.readUint32(cargo, 10)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, alertId: UInt32) {
        let payload = CgmAlertAckHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, alertId: alertId)
        self.alertId = alertId
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, alertId: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(alertId)
            )
        )
    }

    public var description: String {
        "CgmAlertAckHistoryLog(cargo=\(cargo.hexadecimalString), alertId=\(alertId))"
    }
}
