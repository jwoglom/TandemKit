import Foundation

/// Basal-IQ (predictive low glucose suspend) periodic record. Tandem name LID_PLGS_PERIODIC.
///
/// Mirrors pumpX2's `PlgsPeriodicHistoryLog`.
public class PlgsPeriodicHistoryLog: HistoryLog {
    public static let typeId = 140

    /// Timestamp, in seconds.
    public let timestamp: UInt32
    /// Five minute reading, in mg/dL.
    public let fmr: Int
    /// Predicted glucose value, in mg/dL.
    public let pgv: Int
    /// Raw FMR status, see `FmrStatus`.
    public let fmrStatus: Int
    /// Whether the predicted glucose value is valid.
    public let pgvValid: Bool
    /// Raw rule state bitmask, see `RuleState`.
    public let ruleState: Int
    /// Raw hypo minimizer state, see `HoMinState`.
    public let hoMinState: Int
    /// Raw status bitmask, see `Status`.
    public let status: UInt32

    public required init(cargo: Data) {
        timestamp = Bytes.readUint32(cargo, 10)
        fmr = Bytes.readShort(cargo, 14)
        pgv = Bytes.readShort(cargo, 16)
        fmrStatus = Int(cargo[cargo.startIndex + 18])
        pgvValid = cargo[cargo.startIndex + 19] != 0
        ruleState = Int(cargo[cargo.startIndex + 20])
        hoMinState = Int(cargo[cargo.startIndex + 21])
        status = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public convenience init(pumpTimeSec: UInt32, sequenceNum: UInt32) {
        self.init(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, timestamp: 0, fmr: 0, pgv: 0, fmrStatus: 0, pgvValid: false, ruleState: 0, hoMinState: 0, status: 0)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        timestamp: UInt32,
        fmr: Int,
        pgv: Int,
        fmrStatus: Int,
        pgvValid: Bool,
        ruleState: Int,
        hoMinState: Int,
        status: UInt32
    ) {
        let payload = PlgsPeriodicHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            timestamp: timestamp,
            fmr: fmr,
            pgv: pgv,
            fmrStatus: fmrStatus,
            pgvValid: pgvValid,
            ruleState: ruleState,
            hoMinState: hoMinState,
            status: status
        )
        self.timestamp = timestamp
        self.fmr = fmr
        self.pgv = pgv
        self.fmrStatus = fmrStatus
        self.pgvValid = pgvValid
        self.ruleState = ruleState
        self.hoMinState = hoMinState
        self.status = status
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, timestamp: 0, fmr: 0, pgv: 0, fmrStatus: 0, pgvValid: false, ruleState: 0, hoMinState: 0, status: 0)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        timestamp: UInt32,
        fmr: Int,
        pgv: Int,
        fmrStatus: Int,
        pgvValid: Bool,
        ruleState: Int,
        hoMinState: Int,
        status: UInt32
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(timestamp),
                Bytes.firstTwoBytesLittleEndian(fmr),
                Bytes.firstTwoBytesLittleEndian(pgv),
                Data([UInt8(fmrStatus & 0xFF)]),
                Data([pgvValid ? 1 : 0]),
                Data([UInt8(ruleState & 0xFF)]),
                Data([UInt8(hoMinState & 0xFF)]),
                Bytes.toUint32(status)
            )
        )
    }

    public enum FmrStatus: Int {
        case NO_FMR = 0
        case PERIODIC_GLUCOSE_READING = 1
        case CALIBRATION_RESPONSE_GLUCOSE_READING = 2
        case SENSOR_SESSION_STOPPED = 3
        case SENSOR_SESSION_STARTED = 4
        case CALIBRATION_ENTERED = 5
        case PUMPING_EVENT = 6

        public static func fromId(_ id: Int) -> FmrStatus? {
            FmrStatus(rawValue: id)
        }
    }

    public enum RuleState: Int, CaseIterable {
        case HO_SUSPEND_RULE = 1
        case HO_RECOVERY_RULE = 2
        case HO_UNAVAILABLE_RULE = 4

        public static func fromId(_ mask: Int) -> Set<RuleState> {
            var items = Set<RuleState>()
            for i in RuleState.allCases where (mask & i.rawValue) != 0 {
                items.insert(i)
            }
            return items
        }
    }

    public enum HoMinState: Int {
        case ON_AND_AVAILABLE = 0
        case ON_AND_SUSPENDED = 1
        case OFF = 2
        case ON_AND_NOT_AVAILABLE = 3

        public static func fromId(_ id: Int) -> HoMinState? {
            HoMinState(rawValue: id)
        }
    }

    public enum Status: Int, CaseIterable {
        case SUSPEND_PREDICTED = 1
        case SUSPEND_CURRENT = 2
        case RESUME_EGV_RISE = 16
        case RESUME_NADIR_LOCK = 64
        case UNAVAILABLE_TIME_SMALL = 128
        case UNAVAILABLE_SUSPEND_OVERRIDE = 256
        case UNAVAILABLE_CGM_OFF = 512
        case UNAVAILABLE_HIGH_EGV = 1024
        case UNAVAILABLE_NOT_THERAPY = 2048
        case UNAVAILABLE_BOLUS_ACTIVE = 4096
        case UNAVAILABLE_NO_CURRENT = 8192

        public static func fromId(_ mask: Int) -> Set<Status> {
            var items = Set<Status>()
            for i in Status.allCases where (mask & i.rawValue) != 0 {
                items.insert(i)
            }
            return items
        }
    }

    public var fmrStatusEnum: FmrStatus? {
        FmrStatus.fromId(fmrStatus)
    }

    public var ruleStateSet: Set<RuleState> {
        RuleState.fromId(ruleState)
    }

    public var hoMinStateEnum: HoMinState? {
        HoMinState.fromId(hoMinState)
    }

    public var statusSet: Set<Status> {
        Status.fromId(Int(status))
    }

    override public var description: String {
        "PlgsPeriodicHistoryLog(cargo=\(cargo.hexadecimalString), timestamp=\(timestamp), fmr=\(fmr), pgv=\(pgv), fmrStatus=\(fmrStatus), pgvValid=\(pgvValid), ruleState=\(ruleState), hoMinState=\(hoMinState), status=\(status))"
    }
}
