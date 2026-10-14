import Foundation

/// The basal the pump delivered, read from its `BasalDelivery` (279) records.
///
/// The pump delivers basal in 5-minute cycles: at each it writes a BasalDelivery record and delivers
/// 300 s at that record's `commandedRate`. A change of rate (a temp's start or end, a profile
/// segment, Control-IQ) takes effect at the next BasalDelivery record. A late BasalDelivery record,
/// a missing one, or a resume that writes none leaves time in which nothing was delivered, and no
/// chunk covers it.
///
/// Pure: built from one pass's records, with every date on the phone's clock.
struct PumpBasalTimeline: Equatable {
    static let cycle: TimeInterval = 300
    /// `commandedRate` when the pump has none.
    static let notAvailable = 0xFFFF
    /// A temp change or bolus this soon after a BasalDelivery record can cut its cycle short.
    static let shortCycleWindow: TimeInterval = 20
    /// `DailyBasal` counts a cycle about 10 s after its BasalDelivery record.
    static let dailyBasalSettle: TimeInterval = 60
    static let dailyBasalStretch: TimeInterval = .hours(1)
    /// Units.
    static let dailyBasalTolerance = 0.01
    /// Either side of a temp's programmed end, a BasalDelivery record may or may not still run it.
    static let tempEndTolerance: TimeInterval = 60

    enum Kind: Equatable {
        case algorithm
        case temp
        case profile
        case suspended
    }

    struct Chunk: Equatable {
        /// Of the chunk's BasalDelivery record.
        let sequenceNum: UInt32
        let start: Date
        let end: Date
        /// Milliunits per hour.
        let commandedRate: Int
        /// The pump's profile rate in force, milliunits per hour.
        let profileBasalRate: Int
        let kind: Kind
        /// The temp in force, for a temp chunk or a temp under Control-IQ.
        let tempRateId: Int?
        let endsAtSuspend: Bool
        /// It, and the chunks either side, passed the cross-check, and no failing `DailyBasal`
        /// stretch holds it.
        var isTrusted: Bool

        var unitsPerHour: Double { Double(commandedRate) / 1000 }
        var units: Double { unitsPerHour * end.timeIntervalSince(start) / .hours(1) }
    }

    /// A BasalDelivery record whose chunk is not closed yet.
    struct OpenChunk: Equatable {
        let sequenceNum: UInt32
        let start: Date
    }

    /// Closed chunks, ascending.
    private(set) var chunks: [Chunk] = []
    private(set) var openChunks: [OpenChunk] = []
    /// Why a chunk is untrusted, for the log.
    private(set) var problems: [String] = []

    /// - Parameters:
    ///   - logs: The records one pass read, any types, in any order.
    ///   - date: A record's date on the phone's clock (`HistoryRecordDates.phoneDate(of:)`).
    ///   - gaps: Sequence ranges missing from the store inside `logs`' span.
    ///   - readThrough: How far, on the phone's clock, the log is known to be read to its end: the
    ///     start of a tick that read through the pump's last record. Nil if it did not.
    init(logs: [HistoryLog], date: (HistoryLog) -> Date, gaps: [ClosedRange<UInt32>], readThrough: Date?) {
        let sorted = logs.sorted { $0.sequenceNum < $1.sequenceNum }
        guard let last = sorted.last else { return }
        let records = sorted.map { Record(log: $0, date: date($0)) }

        func hasGap(after lower: UInt32, through upper: UInt32) -> Bool {
            gaps.contains { $0.upperBound > lower && $0.lowerBound <= upper }
        }

        var replay = Replay()
        var deliveries: [(index: Int, record: Record, delivery: BasalDeliveryHistoryLog, passes: Bool, tempRateId: Int?)] = []
        for (index, record) in records.enumerated() {
            if let delivery = record.log as? BasalDeliveryHistoryLog {
                let sameSecond = records[(index + 1)...].prefix { $0.log.pumpTimeSec == record.log.pumpTimeSec }
                let (passes, problem) = replay.check(delivery, at: record.date, sameSecond: sameSecond.map(\.log))
                if let problem {
                    problems.append("BasalDelivery #\(delivery.sequenceNum) at \(record.date): \(problem)")
                }
                deliveries.append((index, record, delivery, passes, replay.tempInForce(at: record.date, includingEnding: true)?.log.tempRateId))
            }
            replay.apply(record)
        }

        var untrusted = Set<UInt32>()
        for (position, delivery) in deliveries.enumerated() where !delivery.passes {
            untrusted.insert(delivery.delivery.sequenceNum)
            for neighbour in [position - 1, position + 1] where deliveries.indices.contains(neighbour) {
                let other = deliveries[neighbour].delivery.sequenceNum
                if !hasGap(after: min(other, delivery.delivery.sequenceNum), through: max(other, delivery.delivery.sequenceNum)) {
                    untrusted.insert(other)
                }
            }
        }
        let stretches = Self.dailyBasalStretches(records, hasGap: hasGap)
        for stretch in stretches where !stretch.passes {
            problems.append(stretch.description)
            for delivery in deliveries where stretch.holds(delivery.delivery.sequenceNum) {
                untrusted.insert(delivery.delivery.sequenceNum)
            }
        }

        for delivery in deliveries {
            let log = delivery.delivery
            guard log.commandedRate != Self.notAvailable, let kind = Self.kind(of: log) else { continue }
            let start = delivery.record.date
            var end = start.addingTimeInterval(Self.cycle)
            var endsAtSuspend = false
            var isClosed = false
            var previous = log.sequenceNum
            // Closed once a record at or past its end has been read with nothing missing before it.
            for record in records[(delivery.index + 1)...] {
                guard !hasGap(after: previous, through: record.log.sequenceNum) else { break }
                previous = record.log.sequenceNum
                if record.log is BasalDeliveryHistoryLog || record.log is PumpingSuspendedHistoryLog, record.date < end {
                    end = max(start, record.date)
                    endsAtSuspend = record.log is PumpingSuspendedHistoryLog
                    isClosed = true
                    break
                }
                if record.date >= end {
                    isClosed = true
                    break
                }
            }
            if !isClosed {
                guard previous == last.sequenceNum, let readThrough, readThrough >= end else {
                    openChunks.append(OpenChunk(sequenceNum: log.sequenceNum, start: start))
                    continue
                }
            }
            chunks.append(Chunk(
                sequenceNum: log.sequenceNum,
                start: start,
                end: end,
                commandedRate: log.commandedRate,
                profileBasalRate: log.profileBasalRate,
                kind: kind,
                tempRateId: kind == .temp || log.commandedRateSourceEnum == .tempRateAndAlgorithm ? delivery.tempRateId : nil,
                endsAtSuspend: endsAtSuspend,
                isTrusted: !untrusted.contains(log.sequenceNum)
            ))
        }
    }

    private static func kind(of log: BasalDeliveryHistoryLog) -> Kind? {
        switch log.commandedRateSourceEnum {
        case .algorithm, .tempRateAndAlgorithm: .algorithm
        case .tempRate: .temp
        case .profile: .profile
        case .suspended: .suspended
        case nil: nil
        }
    }

    private struct Record {
        let log: HistoryLog
        let date: Date
    }

    // MARK: - Cross-check

    /// What the pump's other records say it was doing, replayed in sequence order.
    private struct Replay {
        var isSuspended: Bool?
        var temp: (log: TempRateActivatedHistoryLog, start: Date)?
        var pcm: Int?

        mutating func apply(_ record: Record) {
            switch record.log {
            case let activated as TempRateActivatedHistoryLog:
                temp = (activated, record.date)
            case let completed as TempRateCompletedHistoryLog where temp?.log.tempRateId == completed.tempRateId:
                temp = nil
            case is PumpingSuspendedHistoryLog:
                isSuspended = true
            case is PumpingResumedHistoryLog:
                isSuspended = false
            case let change as ControlIQPcmChangeHistoryLog:
                pcm = change.currentPcm
            default:
                break
            }
        }

        /// An alarm suspend can leave a temp in force with no `TempRateCompleted`; it runs again after the resume.
        func tempInForce(at date: Date, includingEnding: Bool = false) -> (log: TempRateActivatedHistoryLog, start: Date)? {
            guard let temp else { return nil }
            let end = temp.start.addingTimeInterval(TimeInterval(temp.log.durationMilliseconds) / 1000)
            let slack = includingEnding ? PumpBasalTimeline.tempEndTolerance : -PumpBasalTimeline.tempEndTolerance
            return date < end.addingTimeInterval(slack) ? temp : nil
        }

        /// Source 3 or 4 passes unless the PCM in force is open loop or none. Anything else must be
        /// what the replay expects, at the BasalDelivery record's own `profileBasalRate`, before or
        /// after the records sharing its second.
        func check(_ delivery: BasalDeliveryHistoryLog, at date: Date, sameSecond: [HistoryLog]) -> (passes: Bool, problem: String?) {
            if delivery.commandedRate == PumpBasalTimeline.notAvailable {
                return (true, nil)
            }
            switch delivery.commandedRateSourceEnum {
            case .algorithm, .tempRateAndAlgorithm:
                if let pcm, pcm == ControlIQPcmChangeHistoryLog.PCM.noControl.rawValue || pcm == ControlIQPcmChangeHistoryLog.PCM.openLoop.rawValue {
                    return (false, "Control-IQ source \(delivery.commandedRateSource) under PCM \(pcm)")
                }
                return (true, nil)
            case nil:
                return (false, "unknown source \(delivery.commandedRateSource)")
            default:
                break
            }

            var after = self
            for log in sameSecond {
                after.apply(Record(log: log, date: date))
            }
            let expected = expectations(at: date, profileRate: delivery.profileBasalRate)
                + after.expectations(at: date, profileRate: delivery.profileBasalRate)
            let matches = expected.contains { source, rate in
                source == delivery.commandedRateSource && abs(rate - delivery.commandedRate) <= 1
            }
            guard !matches else { return (true, nil) }
            let described = expected.map { "(\($0.source), \($0.rate))" }.joined(separator: " or ")
            return (false, "source \(delivery.commandedRateSource) at \(delivery.commandedRate) mU/h; expected \(described)")
        }

        private func expectations(at date: Date, profileRate: Int) -> [(source: Int, rate: Int)] {
            if isSuspended == true {
                return [(0, 0)]
            }
            var expected: [(source: Int, rate: Int)] = []
            if let temp = tempInForce(at: date, includingEnding: true) {
                expected.append((2, Int((Double(temp.log.percent) / 100 * Double(profileRate)).rounded())))
            }
            if tempInForce(at: date) == nil {
                expected.append((1, profileRate))
            }
            return expected
        }
    }

    // MARK: - DailyBasal check

    private struct Stretch {
        let from: DailyBasalHistoryLog
        let to: DailyBasalHistoryLog
        let fromDate: Date
        let toDate: Date
        let deliveredUnits: Double
        let countedUnits: Double
        let passes: Bool

        func holds(_ sequenceNum: UInt32) -> Bool {
            from.sequenceNum < sequenceNum && sequenceNum < to.sequenceNum
        }

        var description: String {
            "DailyBasal #\(from.sequenceNum)-#\(to.sequenceNum) (\(fromDate)-\(toDate)) grew \(deliveredUnits) U; its BasalDelivery records say \(countedUnits) U"
        }
    }

    /// Stretches of at least an hour within one pump day, between `DailyBasal` records each written
    /// long enough after its latest BasalDelivery record to include it. Each BasalDelivery record
    /// between counts its full cycle, even one a suspend cut short. A shortfall is allowed only
    /// where a temp change or bolus started right after a BasalDelivery record.
    private static func dailyBasalStretches(_ records: [Record], hasGap: (UInt32, UInt32) -> Bool) -> [Stretch] {
        var anchors: [(log: DailyBasalHistoryLog, date: Date)] = []
        var latestDelivery: Date?
        for record in records {
            if record.log is BasalDeliveryHistoryLog {
                latestDelivery = record.date
            } else if let daily = record.log as? DailyBasalHistoryLog, let latestDelivery,
                      record.date.timeIntervalSince(latestDelivery) >= dailyBasalSettle
            {
                anchors.append((daily, record.date))
            }
        }

        var stretches: [Stretch] = []
        var from = anchors.first
        for anchor in anchors.dropFirst() {
            guard let start = from else { break }
            guard start.log.pumpTimeSec / 86400 == anchor.log.pumpTimeSec / 86400,
                  !hasGap(start.log.sequenceNum, anchor.log.sequenceNum)
            else {
                from = anchor
                continue
            }
            guard anchor.date.timeIntervalSince(start.date) >= dailyBasalStretch else { continue }

            let inside = records.filter { start.log.sequenceNum < $0.log.sequenceNum && $0.log.sequenceNum < anchor.log.sequenceNum }
            let deliveries = inside.compactMap { record in
                (record.log as? BasalDeliveryHistoryLog).map { (record.date, $0) }
            }
            func cycleUnits(_ delivery: BasalDeliveryHistoryLog) -> Double {
                delivery.commandedRate == notAvailable ? 0 : Double(delivery.commandedRate) / 1000 * cycle / .hours(1)
            }
            let counted = deliveries.reduce(0) { $0 + cycleUnits($1.1) }
            let interruptions = inside.filter {
                $0.log is TempRateActivatedHistoryLog || $0.log is TempRateCompletedHistoryLog || $0.log is BolusActivatedHistoryLog
            }
            let shortable = deliveries.filter { date, _ in
                interruptions.contains { $0.date >= date && $0.date.timeIntervalSince(date) <= shortCycleWindow }
            }.reduce(0) { $0 + cycleUnits($1.1) }
            let delivered = Double(anchor.log.dailyTotalBasal) - Double(start.log.dailyTotalBasal)
            let shortfall = counted - delivered
            let passes = abs(shortfall) <= dailyBasalTolerance || (shortfall > 0 && shortfall <= shortable + dailyBasalTolerance)
            stretches.append(Stretch(
                from: start.log,
                to: anchor.log,
                fromDate: start.date,
                toDate: anchor.date,
                deliveredUnits: delivered,
                countedUnits: counted,
                passes: passes
            ))
            from = anchor
        }
        return stretches
    }
}
