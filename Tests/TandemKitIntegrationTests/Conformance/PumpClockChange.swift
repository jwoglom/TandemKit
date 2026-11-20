import Foundation

/// A change to the pump's clock in the middle of its history, as a scenario stages it on faketandem,
/// with the phone's zone either side of it. Fixed-offset zones, as in conformance group G.
struct PumpClockChange {
    enum Kind {
        /// Set on the pump's screen, by this many seconds: the pump writes `TimeChanged`/`DateChange`.
        case setOnThePump(TimeInterval)
        /// The pump resets and its clock restarts this many days after 2008-01-01, with an `ArmInit`
        /// record and no `TimeChanged` or `DateChange`.
        case reset(toDay: Int)
        /// The clock moves to this many days after 2008-01-01 with no record at all.
        case jump(toDay: Int)
    }

    let zoneBefore: String
    let zoneAfter: String
    let kind: Kind

    static let dstForward = PumpClockChange(zoneBefore: "Etc/GMT+5", zoneAfter: "Etc/GMT+4", kind: .setOnThePump(.hours(1)))
    static let dstBack = PumpClockChange(zoneBefore: "Etc/GMT+4", zoneAfter: "Etc/GMT+5", kind: .setOnThePump(-.hours(1)))
    static let threeHoursEast = PumpClockChange(zoneBefore: "Etc/GMT+7", zoneAfter: "Etc/GMT+4", kind: .setOnThePump(.hours(3)))
    static let threeHoursWest = PumpClockChange(zoneBefore: "Etc/GMT+4", zoneAfter: "Etc/GMT+7", kind: .setOnThePump(-.hours(3)))
    static let twelveHoursEast = PumpClockChange(zoneBefore: "Etc/GMT+5", zoneAfter: "Etc/GMT-7", kind: .setOnThePump(.hours(12)))
    static let twelveHoursWest = PumpClockChange(zoneBefore: "Etc/GMT-7", zoneAfter: "Etc/GMT+5", kind: .setOnThePump(-.hours(12)))
    static let seventyThreeHoursAhead = PumpClockChange(zoneBefore: "Etc/GMT+4", zoneAfter: "Etc/GMT+4", kind: .setOnThePump(.hours(73)))
    static let seventyThreeHoursBehind = PumpClockChange(zoneBefore: "Etc/GMT+4", zoneAfter: "Etc/GMT+4", kind: .setOnThePump(-.hours(73)))
    static let resetTo2008 = PumpClockChange(zoneBefore: "Etc/GMT+4", zoneAfter: "Etc/GMT+4", kind: .reset(toDay: 0))
    static let resetTo2020 = PumpClockChange(zoneBefore: "Etc/GMT+4", zoneAfter: "Etc/GMT+4", kind: .reset(toDay: 4383))
    static let jumpTo2035 = PumpClockChange(zoneBefore: "Etc/GMT+4", zoneAfter: "Etc/GMT+4", kind: .jump(toDay: 9862))

    func apply(on client: FaketandemClient, clock: ConformanceClock, phone: PhoneTimeZone) throws {
        if zoneAfter != zoneBefore {
            phone.set(zoneAfter)
        }
        switch kind {
        case let .setOnThePump(delta):
            try client.setPumpTimeOnThePump(deltaSeconds: delta)
        case let .reset(day):
            try clock.setSkew(seconds: Self.skew(toWireSeconds: day * 86400 + 180, at: clock.now))
            try client.setState(["time_since_reset": 0])
            try client.appendHistory(records: ["NewDay", "ArmInit", "VersionInfo"].map { ["type": $0, "seconds_ago": 0, "data": [String: Any]()] })
        case let .jump(day):
            try clock.setSkew(seconds: Self.skew(toWireSeconds: day * 86400 + 180, at: clock.now))
        }
    }

    /// The skew that puts the pump's wire clock at `wireSeconds` past its 2008 epoch, in the phone's zone.
    private static func skew(toWireSeconds wireSeconds: Int, at now: Date) -> Double {
        let wireZero = FaketandemClock.tandemEpochUnix - Double(TimeZone.current.secondsFromGMT(for: now))
        return wireZero + Double(wireSeconds) - now.timeIntervalSince1970
    }
}
