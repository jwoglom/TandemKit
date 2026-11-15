import Foundation

struct IntegrationWaitTimeout: Error, CustomStringConvertible {
    let what: String
    let timeout: TimeInterval

    var description: String { "timed out after \(timeout)s waiting for \(what)" }
}

struct IntegrationWaitBroken: Error, CustomStringConvertible {
    let what: String
    let duration: TimeInterval

    var description: String { "\(what) stopped holding within \(duration)s" }
}

/// Polling waits for the integration tests. Pumps the current run loop while waiting, because
/// parts of the driver (HistoryLogFetcher) complete on the main queue and a blocked main thread
/// would deadlock them.
enum IntegrationWait {
    static let pollInterval: TimeInterval = 0.05

    static func until(
        _ what: String,
        timeout: TimeInterval,
        _ condition: () throws -> Bool
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while try !condition() {
            guard Date() < deadline else {
                throw IntegrationWaitTimeout(what: what, timeout: timeout)
            }
            pump()
        }
    }

    static func value<T>(
        _ what: String,
        timeout: TimeInterval,
        _ read: () throws -> T?
    ) throws -> T {
        var found: T?
        try until(what, timeout: timeout) {
            found = try read()
            return found != nil
        }
        return found!
    }

    /// Throws if `condition` stops holding within `duration`, checked every `interval`.
    static func holds(
        _ what: String,
        for duration: TimeInterval,
        every interval: TimeInterval = 0.5,
        _ condition: () throws -> Bool
    ) throws {
        let deadline = Date().addingTimeInterval(duration)
        while true {
            guard try condition() else {
                throw IntegrationWaitBroken(what: what, duration: duration)
            }
            guard Date() < deadline else {
                return
            }
            let next = min(Date().addingTimeInterval(interval), deadline)
            while Date() < next {
                pump()
            }
        }
    }

    static func pump() {
        if Thread.isMainThread {
            RunLoop.main.run(until: Date().addingTimeInterval(pollInterval))
        } else {
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }

    /// A step of a polling closure that costs more than a poll, such as a sync of the driver, runs at
    /// most once per `interval` while the wait keeps polling at `pollInterval`.
    final class Throttle {
        private let interval: TimeInterval
        private var lastRun: Date?

        init(interval: TimeInterval) {
            self.interval = interval
        }

        func run(_ body: () throws -> Void) rethrows {
            if let lastRun, Date() < lastRun.addingTimeInterval(interval) {
                return
            }
            lastRun = Date()
            try body()
        }
    }
}

/// A completion result written from another queue and read by a polling wait.
final class ResultBox<T> {
    private let lock = NSLock()
    private var stored: T?
    private var _isSet = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isSet
    }

    var value: T? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ value: T) {
        lock.lock()
        stored = value
        _isSet = true
        lock.unlock()
    }

    /// Blocks (pumping the run loop) until `set` has been called.
    func wait(_ what: String, timeout: TimeInterval) throws -> T {
        try IntegrationWait.until(what, timeout: timeout) { isSet }
        return value!
    }
}
