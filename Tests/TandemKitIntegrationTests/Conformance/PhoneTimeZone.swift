import Foundation

/// The phone's time zone, which the driver reads as `TimeZone.current` (`Dates`, the schedule, the
/// status). Set through `TZ`, since `NSTimeZone.default` does not reach `TimeZone.current` on Linux.
final class PhoneTimeZone {
    private let original: String?

    init() {
        original = ProcessInfo.processInfo.environment["TZ"]
    }

    /// The phone moves to `identifier`: what a trip or a DST transition does to a phone's clock.
    func set(_ identifier: String) {
        setenv("TZ", identifier, 1)
        NSTimeZone.resetSystemTimeZone()
        precondition(TimeZone.current.identifier == identifier, "TimeZone.current is \(TimeZone.current.identifier), not \(identifier)")
    }

    func restore() {
        if let original {
            setenv("TZ", original, 1)
        } else {
            unsetenv("TZ")
        }
        NSTimeZone.resetSystemTimeZone()
    }
}
