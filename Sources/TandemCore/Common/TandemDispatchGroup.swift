import Foundation

/// Single-shot wait/signal primitive used to block a command thread until a
/// matching BLE callback arrives (or a timeout / teardown occurs).
///
/// A fresh instance is allocated for every read/write/notify operation; it is
/// entered exactly once and then awaited exactly once. The implementation is:
///   - idempotent on completion: duplicate or late `leave(_:)`/`cancel()` calls
///     after the waiter has already been released are no-ops (the original
///     count-based guard had a data race and could mismatch group enter/leave),
///   - able to distinguish a real completion from a timeout: `wait(timeout:)`
///     returns `nil` only when it timed out or was cancelled, never when the
///     producer legitimately completed with empty `Data`,
///   - cancellable: `cancel()` unblocks the waiter with no payload so in-flight
///     commands can be torn down on disconnect / Bluetooth loss.
final class TandemDispatchGroup {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var entered = false
    private var completed = false
    private var data: Data?

    func enter() {
        lock.lock()
        defer { lock.unlock() }
        entered = true
        completed = false
        data = nil
    }

    /// Completes the wait with the given payload. Safe to call multiple times;
    /// only the first completion after an `enter()` releases the waiter.
    func leave(_ data: Data) {
        complete(with: data)
    }

    /// Cancels an outstanding wait, releasing the waiter with no payload.
    /// Used to tear down in-flight commands on disconnect / Bluetooth loss so
    /// the blocked command thread returns promptly and releases its locks.
    func cancel() {
        complete(with: nil)
    }

    private func complete(with payload: Data?) {
        lock.lock()
        guard entered, !completed else {
            lock.unlock()
            return
        }
        completed = true
        data = payload
        lock.unlock()
        semaphore.signal()
    }

    @discardableResult func wait() -> Data? {
        semaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    @discardableResult func wait(timeout: DispatchTime) -> Data? {
        let result = semaphore.wait(timeout: timeout)
        lock.lock()
        defer { lock.unlock() }
        if result == .timedOut {
            // Mark completed so a late leave()/cancel() on this (now discarded)
            // instance becomes a no-op and never strands a stale signal.
            completed = true
            data = nil
            return nil
        }
        return data
    }
}
