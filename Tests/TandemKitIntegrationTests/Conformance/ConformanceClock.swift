import Foundation
@testable import TandemKit
import XCTest

/// The driver's `ManualClock` and the emulator's manual clock (`/api/clock`), moved together.
///
/// Delivery arithmetic on the pump (bolus progress, temp-rate expiry, basal drain) runs on the
/// pump's clock; the driver's windows (bolus estimated end, sync throttles, dose dates) run on its
/// `TandemClock`. Keeping the two in lock-step is what makes a dose's start or end second exact
/// instead of "within a tolerance", and lets a 30 minute temp basal expire in one call.
///
/// `pumpOffsetSeconds` skews every timestamp the pump puts on the wire (README "Clock") without
/// moving delivery. Its default is not zero: a Tandem pump keeps its clock in **local time**, and
/// TandemKit decodes every pump-epoch timestamp on that assumption
/// (`Dates.fromJan12008ToUnixEpochSeconds` subtracts `TimeZone.current.secondsFromGMT()`), while
/// faketandem stamps pump-epoch seconds from UTC. Left at zero, every wire timestamp the driver
/// reads lands `secondsFromGMT` away from the pump's own record (four hours in EDT) — the same
/// mismatch behind the timezone-dependent HistoryLog unit tests. `localTimeOffset` reproduces the
/// real pump's convention; add a genuine skew on top of it for the clock-skew scenarios (plan D5).
final class ConformanceClock {
    /// The wire-time offset that makes the emulator report local time the way a real pump does.
    static func localTimeOffset(at instant: Date = Date()) -> Double {
        Double(TimeZone.current.secondsFromGMT(for: instant))
    }

    let driver: ManualClock
    let client: FaketandemClient
    private(set) var pumpOffsetSeconds: Double = 0
    private(set) var frozen = true

    init(driver: ManualClock, client: FaketandemClient) {
        self.driver = driver
        self.client = client
    }

    /// The instant both clocks read (the driver's; `pumpNow()` reads the emulator's back).
    var now: Date { driver.now }

    /// Puts the emulator in manual mode, frozen at `at`, and sets the driver to the same instant.
    /// `skewSeconds` is added to the local-time offset: 0 is a pump whose clock is right.
    @discardableResult
    func start(at instant: Date = Date(), frozen: Bool = true, skewSeconds: Double = 0) throws -> Date {
        // Whole seconds: the pump keeps time in seconds since its epoch, so a fractional instant
        // would make every "same second" comparison flaky.
        let aligned = Date(timeIntervalSinceReferenceDate: instant.timeIntervalSinceReferenceDate.rounded(.down))
        pumpOffsetSeconds = Self.localTimeOffset(at: aligned) + skewSeconds
        self.frozen = frozen
        try client.setClock(mode: "manual", now: aligned, frozen: frozen, pumpOffsetSeconds: pumpOffsetSeconds)
        driver.set(aligned)
        return aligned
    }

    /// Steps both clocks by `seconds`. The emulator's step runs its simulator, split into `ticks`
    /// so anything that has to happen part-way (a bolus finishing before a temp rate expires)
    /// happens in order; the driver's clock jumps once, which is all a driver can observe anyway.
    @discardableResult
    func advanceBoth(seconds: TimeInterval, ticks: Int = 1) throws -> Date {
        precondition(seconds >= 0, "clocks only move forward")
        let clock = try client.advanceClock(seconds: seconds, ticks: max(1, ticks))
        driver.advance(by: seconds)
        try assertAligned(clock)
        return driver.now
    }

    /// Stops the emulator's clock where it is (it stands still until the next `advanceBoth`).
    func freeze() throws {
        frozen = true
        try client.setClock(mode: "manual", frozen: true, pumpOffsetSeconds: pumpOffsetSeconds)
    }

    /// Lets the emulator's clock run at wall-clock speed from where it stands. The driver's clock
    /// does not follow; use this only around waits that genuinely need real time to pass on the
    /// pump, and `freeze()` again before asserting on times.
    func unfreeze() throws {
        frozen = false
        try client.setClock(mode: "manual", frozen: false, pumpOffsetSeconds: pumpOffsetSeconds)
    }

    /// Moves the driver's clock up to the emulator's, after an unfrozen stretch.
    func resyncDriverToPump() throws {
        let clock = try client.clock()
        if clock.now > driver.now {
            driver.set(clock.now)
        }
    }

    /// Changes the pump's clock skew (on top of the local-time convention) without moving either clock.
    func setSkew(seconds: Double) throws {
        pumpOffsetSeconds = Self.localTimeOffset(at: driver.now) + seconds
        try client.setClock(mode: "manual", frozen: frozen, pumpOffsetSeconds: pumpOffsetSeconds)
    }

    func pumpNow() throws -> Date {
        try client.clock().pumpNow
    }

    /// The emulator's clock reading, which should match the driver's to the second while frozen.
    private func assertAligned(_ clock: FaketandemClock, file: StaticString = #filePath, line: UInt = #line) throws {
        guard frozen else { return }
        let drift = clock.now.timeIntervalSince(driver.now)
        XCTAssertEqual(drift, 0, accuracy: 1, "driver and pump clocks drifted apart by \(drift)s", file: file, line: line)
    }
}
