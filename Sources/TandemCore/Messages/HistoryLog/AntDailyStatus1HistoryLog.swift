import Foundation

/// AIDANET (AIQ) new day record 1: algorithm settings and the sleep/eat schedule. Tandem name LID_ANT_DAILY_STATUS1.
///
/// Mirrors pumpX2's `AntDailyStatus1HistoryLog`.
public class AntDailyStatus1HistoryLog: HistoryLog {
    public static let typeId = 562

    /// Whether closed loop is preferred.
    public let closedLoopPreferred: Bool
    /// Total daily insulin setting, in units.
    public let totalDailyInsulinUnits: Int
    /// Raw glycemic goal, see `GlycemicGoal`.
    public let glycemicGoal: Int
    /// Raw prior therapy, see `PriorTherapy`.
    public let priorTherapy: Int
    /// Start of schedule segment 0, in minutes past midnight.
    public let sleepEatSegmentStartTime0: Int
    /// Start of schedule segment 1, in minutes past midnight.
    public let sleepEatSegmentStartTime1: Int
    /// Start of schedule segment 2, in minutes past midnight.
    public let sleepEatSegmentStartTime2: Int
    /// Start of schedule segment 3, in minutes past midnight.
    public let sleepEatSegmentStartTime3: Int
    /// Raw type of schedule segment 0, see `SleepEatSegmentType`.
    public let sleepEatSegmentType0: Int
    /// Raw type of schedule segment 1, see `SleepEatSegmentType`.
    public let sleepEatSegmentType1: Int
    /// Raw type of schedule segment 2, see `SleepEatSegmentType`.
    public let sleepEatSegmentType2: Int
    /// Raw type of schedule segment 3, see `SleepEatSegmentType`.
    public let sleepEatSegmentType3: Int

    public required init(cargo: Data) {
        closedLoopPreferred = cargo[cargo.startIndex + 10] != 0
        totalDailyInsulinUnits = Int(cargo[cargo.startIndex + 11])
        glycemicGoal = Int(cargo[cargo.startIndex + 12])
        priorTherapy = Int(cargo[cargo.startIndex + 13])
        sleepEatSegmentStartTime0 = Bytes.readShort(cargo, 14)
        sleepEatSegmentStartTime1 = Bytes.readShort(cargo, 16)
        sleepEatSegmentStartTime2 = Bytes.readShort(cargo, 18)
        sleepEatSegmentStartTime3 = Bytes.readShort(cargo, 20)
        sleepEatSegmentType0 = Int(cargo[cargo.startIndex + 22])
        sleepEatSegmentType1 = Int(cargo[cargo.startIndex + 23])
        sleepEatSegmentType2 = Int(cargo[cargo.startIndex + 24])
        sleepEatSegmentType3 = Int(cargo[cargo.startIndex + 25])
        super.init(cargo: cargo)
    }

    public convenience init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        self.init(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, closedLoopPreferred: false, totalDailyInsulinUnits: 0, glycemicGoal: 0, priorTherapy: 0, sleepEatSegmentStartTime0: 0, sleepEatSegmentStartTime1: 0, sleepEatSegmentStartTime2: 0, sleepEatSegmentStartTime3: 0, sleepEatSegmentType0: 0, sleepEatSegmentType1: 0, sleepEatSegmentType2: 0, sleepEatSegmentType3: 0)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        closedLoopPreferred: Bool,
        totalDailyInsulinUnits: Int,
        glycemicGoal: Int,
        priorTherapy: Int,
        sleepEatSegmentStartTime0: Int,
        sleepEatSegmentStartTime1: Int,
        sleepEatSegmentStartTime2: Int,
        sleepEatSegmentStartTime3: Int,
        sleepEatSegmentType0: Int,
        sleepEatSegmentType1: Int,
        sleepEatSegmentType2: Int,
        sleepEatSegmentType3: Int
    ) {
        let payload = AntDailyStatus1HistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            closedLoopPreferred: closedLoopPreferred,
            totalDailyInsulinUnits: totalDailyInsulinUnits,
            glycemicGoal: glycemicGoal,
            priorTherapy: priorTherapy,
            sleepEatSegmentStartTime0: sleepEatSegmentStartTime0,
            sleepEatSegmentStartTime1: sleepEatSegmentStartTime1,
            sleepEatSegmentStartTime2: sleepEatSegmentStartTime2,
            sleepEatSegmentStartTime3: sleepEatSegmentStartTime3,
            sleepEatSegmentType0: sleepEatSegmentType0,
            sleepEatSegmentType1: sleepEatSegmentType1,
            sleepEatSegmentType2: sleepEatSegmentType2,
            sleepEatSegmentType3: sleepEatSegmentType3
        )
        self.closedLoopPreferred = closedLoopPreferred
        self.totalDailyInsulinUnits = totalDailyInsulinUnits
        self.glycemicGoal = glycemicGoal
        self.priorTherapy = priorTherapy
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
        buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, closedLoopPreferred: false, totalDailyInsulinUnits: 0, glycemicGoal: 0, priorTherapy: 0, sleepEatSegmentStartTime0: 0, sleepEatSegmentStartTime1: 0, sleepEatSegmentStartTime2: 0, sleepEatSegmentStartTime3: 0, sleepEatSegmentType0: 0, sleepEatSegmentType1: 0, sleepEatSegmentType2: 0, sleepEatSegmentType3: 0)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        closedLoopPreferred: Bool,
        totalDailyInsulinUnits: Int,
        glycemicGoal: Int,
        priorTherapy: Int,
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
                Data([closedLoopPreferred ? 1 : 0]),
                Data([UInt8(totalDailyInsulinUnits & 0xFF)]),
                Data([UInt8(glycemicGoal & 0xFF)]),
                Data([UInt8(priorTherapy & 0xFF)]),
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

    public enum GlycemicGoal: Int {
        case RELAXED = 0
        case BALANCED = 1
        case TIGHTEST = 2

        public static func fromId(_ id: Int) -> GlycemicGoal? {
            GlycemicGoal(rawValue: id)
        }
    }

    public enum PriorTherapy: Int {
        case PREVIOUS_PUMPING_EXPERIENCE = 0
        case MULTIPLE_DAILY_INJECTIONS = 1
        case NOT_SET = 2

        public static func fromId(_ id: Int) -> PriorTherapy? {
            PriorTherapy(rawValue: id)
        }
    }

    public enum SleepEatSegmentType: Int {
        case NONE = 0
        case LESS = 1
        case STANDARD = 2
        case MORE = 3
        case MAX = 4
        case SLEEP = 5
        case NOT_DEFINED = 6

        public static func fromId(_ id: Int) -> SleepEatSegmentType? {
            SleepEatSegmentType(rawValue: id)
        }
    }

    public var glycemicGoalEnum: GlycemicGoal? {
        GlycemicGoal.fromId(glycemicGoal)
    }

    public var priorTherapyEnum: PriorTherapy? {
        PriorTherapy.fromId(priorTherapy)
    }

    public var sleepEatSegmentType0Enum: SleepEatSegmentType? {
        SleepEatSegmentType.fromId(sleepEatSegmentType0)
    }

    public var sleepEatSegmentType1Enum: SleepEatSegmentType? {
        SleepEatSegmentType.fromId(sleepEatSegmentType1)
    }

    public var sleepEatSegmentType2Enum: SleepEatSegmentType? {
        SleepEatSegmentType.fromId(sleepEatSegmentType2)
    }

    public var sleepEatSegmentType3Enum: SleepEatSegmentType? {
        SleepEatSegmentType.fromId(sleepEatSegmentType3)
    }

    public var description: String {
        "AntDailyStatus1HistoryLog(cargo=\(cargo.hexadecimalString), closedLoopPreferred=\(closedLoopPreferred), totalDailyInsulinUnits=\(totalDailyInsulinUnits), glycemicGoal=\(glycemicGoal), priorTherapy=\(priorTherapy), sleepEatSegmentStartTime0=\(sleepEatSegmentStartTime0), sleepEatSegmentStartTime1=\(sleepEatSegmentStartTime1), sleepEatSegmentStartTime2=\(sleepEatSegmentStartTime2), sleepEatSegmentStartTime3=\(sleepEatSegmentStartTime3), sleepEatSegmentType0=\(sleepEatSegmentType0), sleepEatSegmentType1=\(sleepEatSegmentType1), sleepEatSegmentType2=\(sleepEatSegmentType2), sleepEatSegmentType3=\(sleepEatSegmentType3))"
    }
}
