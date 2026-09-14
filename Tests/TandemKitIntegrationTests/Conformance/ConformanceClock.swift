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
/// The two offsets between the emulator's clock and the wire are kept apart here the way the
/// emulator keeps them apart (README "Clock"):
///
/// - **the pump's zone** is its local-time convention, not a lie. A Tandem pump keeps its clock in
///   local time with no zone attached, and TandemKit decodes every pump-epoch timestamp on that
///   assumption (`Dates.fromJan12008ToUnixEpochSeconds` subtracts `TimeZone.current.secondsFromGMT()`).
///   `start()` therefore puts the emulator in the *test process's own* zone, so the driver decodes
///   back exactly the instant the pump meant. Earlier this was faked with a wire skew equal to
///   `secondsFromGMT`, because the emulator stamped pump-epoch seconds from UTC; it encodes in the
///   pump's zone now, and `pump_timezone` is the honest knob (and the one that reproduces a
///   traveling pump or a DST boundary).
/// - **`pumpOffsetSeconds` is a genuine skew**, a lie the pump tells about the time: it moves every
///   wire timestamp on top of the zone without touching delivery. It is 0 unless a scenario asks
///   for a skewed pump clock (plan D5).
final class ConformanceClock {
    let driver: ManualClock
    let client: FaketandemClient
    /// The pump's clock skew, in seconds. Zero is a pump whose clock is right.
    private(set) var pumpOffsetSeconds: Double = 0
    /// The IANA zone the pump keeps its clock in. The test process's own, so that what the driver
    /// decodes out of a wire timestamp is the instant the pump recorded.
    private(set) var pumpTimezone: String = TimeZone.current.identifier
    private(set) var frozen = true

    init(driver: ManualClock, client: FaketandemClient) {
        self.driver = driver
        self.client = client
    }

    /// The instant both clocks read (the driver's; `pumpNow()` reads the emulator's back).
    var now: Date { driver.now }

    /// Puts the emulator in manual mode, frozen at `at`, in this process's time zone, and sets the
    /// driver to the same instant. `skewSeconds` is the pump's clock skew: 0 is a pump whose clock
    /// is right.
    @discardableResult
    func start(at instant: Date = Date(), frozen: Bool = true, skewSeconds: Double = 0, timezone: String? = nil) throws -> Date {
        // Whole seconds: the pump keeps time in seconds since its epoch, so a fractional instant
        // would make every "same second" comparison flaky.
        let aligned = Date(timeIntervalSinceReferenceDate: instant.timeIntervalSinceReferenceDate.rounded(.down))
        pumpOffsetSeconds = skewSeconds
        pumpTimezone = timezone ?? TimeZone.current.identifier
        self.frozen = frozen
        try client.setClock(
            mode: "manual",
            now: aligned,
            frozen: frozen,
            pumpOffsetSeconds: pumpOffsetSeconds,
            pumpTimezone: pumpTimezone
        )
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
        try client.setClock(mode: "manual", frozen: true, pumpOffsetSeconds: pumpOffsetSeconds, pumpTimezone: pumpTimezone)
    }

    /// Lets the emulator's clock run at wall-clock speed from where it stands. The driver's clock
    /// does not follow; use this only around waits that genuinely need real time to pass on the
    /// pump, and `freeze()` again before asserting on times.
    func unfreeze() throws {
        frozen = false
        try client.setClock(mode: "manual", frozen: false, pumpOffsetSeconds: pumpOffsetSeconds, pumpTimezone: pumpTimezone)
    }

    /// Moves the driver's clock up to the emulator's, after an unfrozen stretch.
    func resyncDriverToPump() throws {
        let clock = try client.clock()
        if clock.now > driver.now {
            driver.set(clock.now)
        }
    }

    /// Changes the pump's clock skew (on top of its zone) without moving either clock.
    func setSkew(seconds: Double) throws {
        pumpOffsetSeconds = seconds
        try client.setClock(mode: "manual", frozen: frozen, pumpOffsetSeconds: pumpOffsetSeconds, pumpTimezone: pumpTimezone)
    }

    /// Moves the pump to another time zone: every wire timestamp moves with it, delivery does not.
    func setTimezone(_ identifier: String) throws {
        pumpTimezone = identifier
        try client.setClock(mode: "manual", frozen: frozen, pumpOffsetSeconds: pumpOffsetSeconds, pumpTimezone: identifier)
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
