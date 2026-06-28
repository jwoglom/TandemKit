import Dispatch
import Foundation

/// Result of a chunk collection attempt.
internal enum ChunkResult {
    case complete([HistoryLog])
    case partial([HistoryLog], received: Int, expected: Int)
    case timeout([HistoryLog], received: Int, expected: Int)
}

/// Thread-safe collector for history log stream responses with polling-based completion detection.
/// Replaces semaphore-based blocking with polling to enable per-chunk timeouts.
internal final class ChunkedStreamCollector {
    private let queue = DispatchQueue(label: "com.loopkit.TandemKit.ChunkedStreamCollector")
    private var collected: [HistoryLog] = []
    private var expectedCount: Int?
    private var activeStreamId: Int?
    private var finished = false

    /// Prepare to collect responses for a new stream.
    internal func startCollecting(streamId: Int, expectedCount: Int) {
        queue.sync {
            self.activeStreamId = streamId
            self.expectedCount = expectedCount
            self.collected = []
            self.finished = false
        }
    }

    /// Handle an incoming stream response.
    /// Should be called from TandemPumpManager when HistoryLogStreamResponse is received.
    internal func handleStreamResponse(_ response: HistoryLogStreamResponse) {
        queue.sync {
            guard !finished,
                  let expected = expectedCount,
                  let streamId = activeStreamId,
                  streamId == response.streamId
            else {
                return
            }

            collected.append(contentsOf: response.historyLogs)

            if collected.count >= expected {
                finished = true
            }
        }
    }

    /// Poll for completion with timeout.
    /// Port of ControlX2's polling logic (lines 78-93).
    ///
    /// - Parameters:
    ///   - timeout: Maximum time to wait for all logs (default 2.5s)
    ///   - pollInterval: How often to check for completion (default 250ms)
    /// - Returns: ChunkResult indicating complete, partial, or timeout
    internal func pollForCompletion(
        timeout: TimeInterval = 2.5,
        pollInterval: TimeInterval = 0.25
    ) throws -> ChunkResult {
        let startTime = Date()
        var waitTimeMs: TimeInterval = 0

        while true {
            // Check if we've collected all expected logs
            let (isFinished, currentCount, expected) = queue.sync { () -> (Bool, Int, Int?) in
                (finished, collected.count, expectedCount)
            }

            guard let expectedCount = expected else {
                throw HistoryFetchError.streamTimeout(expected: 0, received: 0)
            }

            if isFinished || currentCount >= expectedCount {
                let logs = queue.sync { collected }
                return .complete(logs)
            }

            // Check timeout
            waitTimeMs = Date().timeIntervalSince(startTime)
            if waitTimeMs >= timeout {
                let logs = queue.sync { collected }
                return .timeout(logs, received: currentCount, expected: expectedCount)
            }

            // Sleep for poll interval
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }

    /// Reset collector state (useful for reusing the same instance).
    internal func reset() {
        queue.sync {
            collected = []
            expectedCount = nil
            activeStreamId = nil
            finished = false
        }
    }
}
