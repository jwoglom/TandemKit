import Foundation

/// The source of "now" for every time-dependent decision in the driver.
///
/// Dose dates, the state-sync throttle, the bolus finalization window and the grace periods around
/// them are all wall-clock arithmetic, which makes them untestable without either real waits or a
/// seam. This is the seam: it is passed explicitly (`TandemPumpManager.clock`), never read from a
/// global, so two managers in one process can run on different clocks.
public protocol TandemClock: AnyObject {
    var now: Date { get }
}

public final class SystemClock: TandemClock {
    public init() {}

    public var now: Date { Date() }
}

#if DEBUG
/// A clock that only moves when a test moves it.
///
/// Thread-safe: the manager reads it from the command queue, the delegate queue and the BLE
/// notification path.
public final class ManualClock: TandemClock {
    private let lock = NSLock()
    private var current: Date

    public init(_ start: Date = Date(timeIntervalSinceReferenceDate: 700_000_000)) {
        current = start
    }

    public var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func set(_ date: Date) {
        lock.lock()
        defer { lock.unlock() }
        current = date
    }

    public func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current.addTimeInterval(interval)
    }
}
#endif
