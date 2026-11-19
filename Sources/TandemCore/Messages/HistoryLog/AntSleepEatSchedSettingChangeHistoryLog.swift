import Foundation

/// AIDANET (AIQ) sleep/eat schedule setting change. Tandem name LID_ANT_SLEEP_EAT_SCHED_SETTING_CHANGE.
///
/// Mirrors pumpX2's `AntSleepEatSchedSettingChangeHistoryLog`.
public class AntSleepEatSchedSettingChangeHistoryLog: HistoryLog {
    public static let typeId = 566

    /// Start of schedule segment 0, in minutes past midnight.
    public let sleepEatSegmentStartTime0: Int
    /// Start of schedule segment 1, in minutes past midnight.
    public let sleepEatSegmentStartTime1: Int
    /// Start of schedule segment 2, in minutes past midnight.
    public let sleepEatSegmentStartTime2: Int
    /// Start of schedule segment 3, in minutes past midnight.
    public let sleepEatSegmentStartTime3: Int
    /// Raw type of schedule segment 0, see `AntDailyStatus1HistoryLog.SleepEatSegmentType`.
    public let sleepEatSegmentType0: Int
    /// Raw type of schedule segment 1, see `AntDailyStatus1HistoryLog.SleepEatSegmentType`.
    public let sleepEatSegmentType1: Int
    /// Raw type of schedule segment 2, see `AntDailyStatus1HistoryLog.SleepEatSegmentType`.
    public let sleepEatSegmentType2: Int
    /// Raw type of schedule segment 3, see `AntDailyStatus1HistoryLog.SleepEatSegmentType`.
    public let sleepEatSegmentType3: Int

    public required init(cargo: Data) {
        sleepEatSegmentStartTime0 = Bytes.readShort(cargo, 10)
        sleepEatSegmentStartTime1 = Bytes.readShort(cargo, 12)
        sleepEatSegmentStartTime2 = Bytes.readShort(cargo, 14)
        sleepEatSegmentStartTime3 = Bytes.readShort(cargo, 16)
        sleepEatSegmentType0 = Int(cargo[cargo.startIndex + 18])
        sleepEatSegmentType1 = Int(cargo[cargo.startIndex + 19])
        sleepEatSegmentType2 = Int(cargo[cargo.startIndex + 20])
        sleepEatSegmentType3 = Int(cargo[cargo.startIndex + 21])
        super.init(cargo: cargo)
    }

    public convenience init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        self.init(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, sleepEatSegmentStartTime0: 0, sleepEatSegmentStartTime1: 0, sleepEatSegmentStartTime2: 0, sleepEatSegmentStartTime3: 0, sleepEatSegmentType0: 0, sleepEatSegmentType1: 0, sleepEatSegmentType2: 0, sleepEatSegmentType3: 0)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        sleepEatSegmentStartTime0: Int,
        sleepEatSegmentStartTime1: Int,
        sleepEatSegmentStartTime2: Int,
        sleepEatSegmentStartTime3: Int,
        sleepEatSegmentType0: Int,
        sleepEatSegmentType1: Int,
        sleepEatSegmentType2: Int,
        sleepEatSegmentType3: Int
    ) {
        let payload = AntSleepEatSchedSettingChangeHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            sleepEatSegmentStartTime0: sleepEatSegmentStartTime0,
            sleepEatSegmentStartTime1: sleepEatSegmentStartTime1,
            sleepEatSegmentStartTime2: sleepEatSegmentStartTime2,
            sleepEatSegmentStartTime3: sleepEatSegmentStartTime3,
            sleepEatSegmentType0: sleepEatSegmentType0,
            sleepEatSegmentType1: sleepEatSegmentType1,
            sleepEatSegmentType2: sleepEatSegmentType2,
            sleepEatSegmentType3: sleepEatSegmentType3
        )
        self.sleepEatSegmentStartTime0 = sleepEatSegmentStartTime0
        self.sleepEatSegmentStartTime1 = sleepEatSegmentStartTime1
        self.sleepEatSegmentStartTime2 = sleepEatSegmentStartTime2
        self.sleepEatSegmentStartTime3 = sleepEatSegmentStartTime3
        self.sleepEatSegmentType0 = sleepEatSegmentType0
        self.sleepEatSegmentType1 = sleepEatSegmentType1
        self.sleepEatSegmentType2 = sleepEatSegmentType2
        self.sleepEatSegmentType3 = sleepEatSegmentType3
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, sleepEatSegmentStartTime0: 0, sleepEatSegmentStartTime1: 0, sleepEatSegmentStartTime2: 0, sleepEatSegmentStartTime3: 0, sleepEatSegmentType0: 0, sleepEatSegmentType1: 0, sleepEatSegmentType2: 0, sleepEatSegmentType3: 0)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        sleepEatSegmentStartTime0: Int,
        sleepEatSegmentStartTime1: Int,
        sleepEatSegmentStartTime2: Int,
        sleepEatSegmentStartTime3: Int,
        sleepEatSegmentType0: Int,
        sleepEatSegmentType1: Int,
        sleepEatSegmentType2: Int,
        sleepEatSegmentType3: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(sleepEatSegmentStartTime0),
                Bytes.firstTwoBytesLittleEndian(sleepEatSegmentStartTime1),
                Bytes.firstTwoBytesLittleEndian(sleepEatSegmentStartTime2),
                Bytes.firstTwoBytesLittleEndian(sleepEatSegmentStartTime3),
                Data([UInt8(sleepEatSegmentType0 & 0xFF)]),
                Data([UInt8(sleepEatSegmentType1 & 0xFF)]),
                Data([UInt8(sleepEatSegmentType2 & 0xFF)]),
                Data([UInt8(sleepEatSegmentType3 & 0xFF)])
            )
        )
    }



    override public var description: String {
        "AntSleepEatSchedSettingChangeHistoryLog(cargo=\(cargo.hexadecimalString), sleepEatSegmentStartTime0=\(sleepEatSegmentStartTime0), sleepEatSegmentStartTime1=\(sleepEatSegmentStartTime1), sleepEatSegmentStartTime2=\(sleepEatSegmentStartTime2), sleepEatSegmentStartTime3=\(sleepEatSegmentStartTime3), sleepEatSegmentType0=\(sleepEatSegmentType0), sleepEatSegmentType1=\(sleepEatSegmentType1), sleepEatSegmentType2=\(sleepEatSegmentType2), sleepEatSegmentType3=\(sleepEatSegmentType3))"
    }
}
