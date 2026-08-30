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
///     producer legitimately completed with empty `Data`. Callers that must tell
///     a cancel from a timeout use `waitForOutcome(timeout:)`,
///   - cancellable: `cancel()` unblocks the waiter with no payload so in-flight
///     commands can be torn down on disconnect / Bluetooth loss.
final class TandemDispatchGroup {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var entered = false
    private var completed = false
    private var cancelled = false
    private var data: Data?

    func enter() {
        lock.lock()
        defer { lock.unlock() }
        entered = true
        completed = false
        cancelled = false
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
        // cancel() is the only caller that passes no payload, so a nil payload
        // here is exactly a cancellation.
        cancelled = payload == nil
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

    /// Why a bounded wait ended. `wait(timeout:)` collapses `.cancelled` and
    /// `.timedOut` into nil, which is all most call sites need; the ones that
    /// report the failure to a human should distinguish them.
    enum WaitOutcome: Equatable {
        /// The producer completed, with whatever payload it supplied.
        case completed(Data)
        /// `cancel()` was called: the BLE link (or Bluetooth itself) went away,
        /// so the callback that would have completed this wait never can.
        case cancelled
        /// The deadline passed with no completion and no cancellation.
        case timedOut
    }

    @discardableResult func wait(timeout: DispatchTime) -> Data? {
        switch waitForOutcome(timeout: timeout) {
        case let .completed(payload):
            return payload
        case .cancelled, .timedOut:
            return nil
        }
    }

    func waitForOutcome(timeout: DispatchTime) -> WaitOutcome {
        let result = semaphore.wait(timeout: timeout)
        lock.lock()
        defer { lock.unlock() }
        if result == .timedOut {
            // Mark completed so a late leave()/cancel() on this (now discarded)
            // instance becomes a no-op and never strands a stale signal.
            completed = true
            data = nil
            cancelled = false
            return .timedOut
        }
        if cancelled {
            return .cancelled
        }
        // A signalled, non-cancelled completion always carries a payload; the
        // nil-coalesce is only here so this cannot trap on an unreachable path.
        return .completed(data ?? Data())
    }
}
