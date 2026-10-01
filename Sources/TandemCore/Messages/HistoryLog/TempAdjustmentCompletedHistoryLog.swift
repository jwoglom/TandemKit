import Foundation

/// Temporary adjustment (temp basal rate or temp control rate) completed. Tandem name LID_TEMP_ADJUSTMENT_COMPLETED.
///
/// Mirrors pumpX2's `TempAdjustmentCompletedHistoryLog`.
public class TempAdjustmentCompletedHistoryLog: HistoryLog {
    public static let typeId = 564

    /// Raw stop reason, see `StopReason`.
    public let stopReason: Int
    /// The temp rate ID.
    public let tempRateId: Int
    /// Time left, in milliseconds.
    public let timeLeft: UInt32

    public required init(cargo: Data) {
        stopReason = Bytes.readShort(cargo, 10)
        tempRateId = Bytes.readShort(cargo, 12)
        timeLeft = Bytes.readUint32(cargo, 14)
        super.init(cargo: cargo)
    }

    public convenience init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        self.init(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, stopReason: 0, tempRateId: 0, timeLeft: 0)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        stopReason: Int,
        tempRateId: Int,
        timeLeft: UInt32
    ) {
        let payload = TempAdjustmentCompletedHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            stopReason: stopReason,
            tempRateId: tempRateId,
            timeLeft: timeLeft
        )
        self.stopReason = stopReason
        self.tempRateId = tempRateId
        self.timeLeft = timeLeft
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, stopReason: 0, tempRateId: 0, timeLeft: 0)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        stopReason: Int,
        tempRateId: Int,
        timeLeft: UInt32
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(stopReason),
                Bytes.firstTwoBytesLittleEndian(tempRateId),
                Bytes.toUint32(timeLeft)
            )
        )
    }

    public enum StopReason: Int {
        case USER_ABORTED = 0
        case TERMINATED_BY_ALARM = 1
        case COMPLETED = 3
        case USER_ABORTED_BLE = 8
        case TERMINATED_BY_PUMP_CONTROL_MODE_CHANGE = 10
        case TERMINATED_BY_CLOSED_LOOP_PREFERRED_CHANGE = 11

        public static func fromId(_ id: Int) -> StopReason? {
            StopReason(rawValue: id)
        }
    }

    public var stopReasonEnum: StopReason? {
        StopReason.fromId(stopReason)
    }

    public var description: String {
        "TempAdjustmentCompletedHistoryLog(cargo=\(cargo.hexadecimalString), stopReason=\(stopReason), tempRateId=\(tempRateId), timeLeft=\(timeLeft))"
    }
}
