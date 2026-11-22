import Foundation

struct PumpClockReading: Equatable {
    /// The pump's wall clock in seconds since 2008-01-01, as it stamps records: it has no zone, so the phone's never moves it.
    let pumpTimeSec: UInt32
    let phoneDate: Date

    /// Two reads of a clock that was not set between them differ by the phone time between them.
    static let agreementTolerance: TimeInterval = 10

    func agrees(with later: PumpClockReading) -> Bool {
        let pumpElapsed = TimeInterval(Int(later.pumpTimeSec) - Int(pumpTimeSec))
        return abs(pumpElapsed - later.phoneDate.timeIntervalSince(phoneDate)) <= Self.agreementTolerance
    }

    /// This reading as the pump's clock would give it at `date`, had it run on untouched.
    func carried(to date: Date) -> PumpClockReading {
        let pumpTimeSec = Int((Double(self.pumpTimeSec) + date.timeIntervalSince(phoneDate)).rounded())
        return PumpClockReading(pumpTimeSec: UInt32(clamping: pumpTimeSec), phoneDate: date)
    }
}

/// A reading of the pump's clock beside its newest history record: every record through `sequenceNum`
/// was written by `phoneDate`, and every later one after it.
public struct PumpClockAnchor: Equatable {
    public let sequenceNum: UInt32
    /// Seconds since 2008-01-01 on the pump's wall clock, as records are stamped.
    public let pumpTimeSec: UInt32
    public let phoneDate: Date

    public init(sequenceNum: UInt32, pumpTimeSec: UInt32, phoneDate: Date) {
        self.sequenceNum = sequenceNum
        self.pumpTimeSec = pumpTimeSec
        self.phoneDate = phoneDate
    }

    /// Seconds the pump's clock gained on the phone's from `earlier` to here, beyond the `recordedDeltaSec`
    /// its own clock-change records between the two account for.
    func unexplainedStep(since earlier: PumpClockAnchor, recordedDeltaSec: Int = 0) -> TimeInterval {
        TimeInterval(Int(pumpTimeSec) - Int(earlier.pumpTimeSec) - recordedDeltaSec) - phoneDate.timeIntervalSince(earlier.phoneDate)
    }

    func agrees(with later: PumpClockAnchor) -> Bool {
        abs(later.unexplainedStep(since: self)) <= TandemPumpManagerState.pumpClockStepThreshold
    }
}

/// The anchors a manager keeps for one pump, oldest first. Of a run of anchors on one untouched clock only
/// the first and last stay, so the two either side of any clock change are always the nearest taken.
public struct PumpClockAnchors: Equatable {
    /// As far back as a history record may still be reported.
    public static let retention: TimeInterval = BolusReportLedger.reportingHorizon
    static let limit = 64

    public private(set) var pumpSerial: UInt32?
    public private(set) var anchors: [PumpClockAnchor]

    public init(pumpSerial: UInt32? = nil, anchors: [PumpClockAnchor] = []) {
        self.pumpSerial = pumpSerial
        self.anchors = anchors
    }

    public func anchors(pumpSerial: UInt32?) -> [PumpClockAnchor] {
        pumpSerial != nil && pumpSerial == self.pumpSerial ? anchors : []
    }

    public mutating func record(_ anchor: PumpClockAnchor, pumpSerial: UInt32) {
        // Another pump, an erased log whose numbering restarted, or the phone's own clock set back.
        let restarts = anchors.last.map { anchor.sequenceNum < $0.sequenceNum || anchor.phoneDate < $0.phoneDate } ?? false
        if self.pumpSerial != pumpSerial || restarts {
            anchors = []
        }
        self.pumpSerial = pumpSerial

        if anchors.count >= 2 {
            let first = anchors[anchors.count - 2]
            let middle = anchors[anchors.count - 1]
            if first.agrees(with: middle), middle.agrees(with: anchor), first.agrees(with: anchor) {
                anchors.removeLast()
            }
        }
        anchors.append(anchor)
        anchors.removeAll { anchor.phoneDate.timeIntervalSince($0.phoneDate) > Self.retention }
        if anchors.count > Self.limit {
            anchors.removeFirst(anchors.count - Self.limit)
        }
    }
}

extension PumpClockAnchors: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        let anchors = (rawValue["anchors"] as? [[String: Any]] ?? []).compactMap { raw -> PumpClockAnchor? in
            guard let sequenceNum = raw["sequenceNum"] as? UInt32,
                  let pumpTimeSec = raw["pumpTimeSec"] as? UInt32,
                  let phoneDate = raw["phoneDate"] as? TimeInterval
            else {
                return nil
            }
            return PumpClockAnchor(sequenceNum: sequenceNum, pumpTimeSec: pumpTimeSec, phoneDate: Date(timeIntervalSinceReferenceDate: phoneDate))
        }
        self.init(pumpSerial: rawValue["pumpSerial"] as? UInt32, anchors: anchors)
    }

    public var rawValue: RawValue {
        var raw: RawValue = [
            "anchors": anchors.map { anchor -> [String: Any] in
                [
                    "sequenceNum": anchor.sequenceNum,
                    "pumpTimeSec": anchor.pumpTimeSec,
                    "phoneDate": anchor.phoneDate.timeIntervalSinceReferenceDate
                ]
            }
        ]
        raw["pumpSerial"] = pumpSerial
        return raw
    }
}
