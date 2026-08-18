import Foundation

/// Serializes whole history reads across every `HistoryLogFetcher` sharing one pump.
///
/// Each fetcher tracks its own chunk completion against the pump's single history log stream, so
/// two fetches running at once would each count the other's entries as its own and neither could
/// tell when its chunk had actually arrived. The per-instance `fetchActive` flag can't see that:
/// the log viewer and the background backfill hold different fetchers. This gate is held for the
/// duration of a fetch or a probe, and a reader that can't take it steps aside rather than
/// corrupting both reads.
final class HistoryFetchGate {
    private let lock = NSLock()
    private var held = false

    var isBusy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return held
    }

    /// Take the gate, or report that someone else holds it.
    func tryAcquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !held else {
            return false
        }
        held = true
        return true
    }

    func release() {
        lock.lock()
        held = false
        lock.unlock()
    }
}
