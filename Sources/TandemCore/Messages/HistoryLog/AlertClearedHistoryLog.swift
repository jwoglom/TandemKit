import Foundation

/// History log entry for clearing an alert.
public class AlertClearedHistoryLog: HistoryLog {
    public static let typeId = 26

    public let alertId: UInt32
    public let faultLocatorData: UInt32

    public required init(cargo: Data) {
        alertId = Bytes.readUint32(cargo, 10)
        faultLocatorData = Bytes.readUint32(cargo, 14)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, alertId: UInt32, faultLocatorData: UInt32) {
        let payload = AlertClearedHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            alertId: alertId,
            faultLocatorData: faultLocatorData
        )
        self.alertId = alertId
        self.faultLocatorData = faultLocatorData
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        alertId: UInt32,
        faultLocatorData: UInt32
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(alertId),
                Bytes.toUint32(faultLocatorData)
            )
        )
    }
}

public extension AlertClearedHistoryLog {
    var description: String {
        "AlertClearedHistoryLog(cargo=\(cargo.hexadecimalString), alertId=\(alertId), faultLocatorData=\(faultLocatorData))"
    }
}
