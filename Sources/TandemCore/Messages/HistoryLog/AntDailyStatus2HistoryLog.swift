import Foundation

/// AIDANET (AIQ) new day record 2: pump control state and sensor type. Tandem name LID_ANT_DAILY_STATUS2.
///
/// Mirrors pumpX2's `AntDailyStatus2HistoryLog`.
public class AntDailyStatus2HistoryLog: HistoryLog {
    public static let typeId = 563

    /// Raw pump control state, see `DailyStatusHistoryLog.PumpControlState`.
    public let pumpControlState: Int
    /// Raw sensor type, see `DailyStatusHistoryLog.SensorType`.
    public let sensorType: Int

    public required init(cargo: Data) {
        pumpControlState = Int(cargo[cargo.startIndex + 10])
        sensorType = Int(cargo[cargo.startIndex + 11])
        super.init(cargo: cargo)
    }

    public convenience init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        self.init(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, pumpControlState: 0, sensorType: 0)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        pumpControlState: Int,
        sensorType: Int
    ) {
        let payload = AntDailyStatus2HistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            pumpControlState: pumpControlState,
            sensorType: sensorType
        )
        self.pumpControlState = pumpControlState
        self.sensorType = sensorType
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, pumpControlState: 0, sensorType: 0)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        pumpControlState: Int,
        sensorType: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(pumpControlState & 0xFF)]),
                Data([UInt8(sensorType & 0xFF)])
            )
        )
    }



    public var description: String {
        "AntDailyStatus2HistoryLog(cargo=\(cargo.hexadecimalString), pumpControlState=\(pumpControlState), sensorType=\(sensorType))"
    }
}
