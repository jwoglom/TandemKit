import Dispatch
import Foundation

// History fetch configuration matching ControlX2
private let TandemHistoryChunkSize: Int = 32
private let TandemHistoryChunkTimeout: TimeInterval = 2.5
private let TandemHistoryPollInterval: TimeInterval = 0.25

/// Errors that can occur during a history fetch session.
enum HistoryFetchError: Error, Equatable {
    case invalidRange(start: UInt32, firstAvailable: UInt32, lastAvailable: UInt32)
    case responseStatus(Int)
    case streamTimeout(expected: Int, received: Int)
    /// No (or non-decodable) response from the pump for a request. Transient; retryable.
    case noResponse

    var isRetryable: Bool {
        switch self {
        case .streamTimeout, .noResponse:
            return true
        default:
            return false
        }
    }
}

/// Orchestrates a single history fetch request/response sequence.
///
/// The session sends a status request to determine the available sequence range,
/// issues a history request for the desired slice, and collects matching
/// `HistoryLogStreamResponse` notifications until the expected number of entries
/// arrive or a timeout occurs.
final class HistoryFetchSession {
    private let sender: HistoryMessageSender
    private let startSequence: UInt32?
    private let maxEntries: Int
    /// Optional lower bound: stop the backward walk once we've fetched an entry older than this
    /// date (≈ insulin duration via `startDateToFilterNewPumpEvents`). `maxEntries` is the backstop.
    private let stopBeforeDate: Date?
    /// Optional upper bound: begin the backward walk at this sequence instead of the pump's newest
    /// (`lastSequenceNum`). Lets a caller fetch an *older* contiguous slice one chunk at a time —
    /// used by the cooperative deep fetch to step backward while yielding the command queue.
    private let endSequence: UInt32?
    private let chunkSize = TandemHistoryChunkSize
    private let chunkTimeout = TandemHistoryChunkTimeout
    private let log = TandemLogger(category: "HistoryFetchSession")
    private var activeCollector: ChunkedStreamCollector?

    init(
        sender: HistoryMessageSender,
        startSequence: UInt32?,
        maxEntries: Int,
        stopBeforeDate: Date? = nil,
        endSequence: UInt32? = nil
    ) {
        self.sender = sender
        self.startSequence = startSequence
        self.maxEntries = maxEntries
        self.stopBeforeDate = stopBeforeDate
        self.endSequence = endSequence
    }

    /// Route incoming stream responses to the active collector.
    /// Called from TandemPumpManager when HistoryLogStreamResponse is received.
    func handleStreamResponse(_ response: HistoryLogStreamResponse) {
        activeCollector?.handleStreamResponse(response)
    }

    /// Execute the fetch flow with retry handling for transient failures.
    /// - Parameters:
    ///   - retries: The number of retry attempts to perform after the initial try.
    ///   - retryDelay: Delay between retry attempts.
    func fetchWithRetry(retries: Int = 2, retryDelay: TimeInterval = 1) throws -> [HistoryLog] {
        var remainingRetries = retries
        var lastError: Error?

        while remainingRetries >= 0 {
            do {
                return try fetch()
            } catch let error as HistoryFetchError {
                lastError = error
                guard remainingRetries > 0, error.isRetryable else { throw error }
            } catch {
                lastError = error
                guard remainingRetries > 0 else { throw error }
            }

            remainingRetries -= 1

            if retryDelay > 0 {
                Thread.sleep(forTimeInterval: retryDelay)
            }
        }

        throw lastError ?? HistoryFetchError.streamTimeout(expected: 0, received: 0)
    }

    /// Execute the fetch flow with chunked backward iteration and return sorted history logs.
    func fetch() throws -> [HistoryLog] {
        guard let status = sender.sendMessage(
            HistoryLogStatusRequest(),
            expecting: HistoryLogStatusResponse.self
        ) as? HistoryLogStatusResponse else {
            throw HistoryFetchError.noResponse
        }

        let start = resolvedStartSequence(from: status)
        guard let start else {
            return []
        }

        // Begin the backward walk at the requested upper bound (clamped to what the pump has), so a
        // caller can fetch an older slice; defaults to the pump's newest sequence.
        let effectiveEnd = min(endSequence ?? status.lastSequenceNum, status.lastSequenceNum)
        guard effectiveEnd >= start else {
            return []
        }

        let availableCount = Int(effectiveEnd &- start + 1)
        let totalToFetch = max(0, min(maxEntries, availableCount))

        if totalToFetch == 0 {
            return []
        }

        var allLogs: [HistoryLog] = []
        activeCollector = ChunkedStreamCollector()

        // Iterate backwards from END to START (like ControlX2 lines 64-96)
        var currentEnd = effectiveEnd

        while currentEnd >= start, allLogs.count < totalToFetch {
            let remainingCount = totalToFetch - allLogs.count
            let chunkCount = min(chunkSize, remainingCount, Int(currentEnd - start + 1))
            let chunkStart = currentEnd - UInt32(chunkCount - 1)

            log.debug("Fetching chunk [\(chunkStart), \(currentEnd)] count=\(chunkCount)")

            do {
                guard let collector = activeCollector else {
                    throw HistoryFetchError.streamTimeout(expected: chunkCount, received: 0)
                }

                let result = try fetchChunk(
                    startSequence: currentEnd, // Request from END
                    count: chunkCount,
                    collector: collector
                )

                switch result {
                case let .complete(logs):
                    allLogs.append(contentsOf: logs)
                    log.debug("Chunk [\(chunkStart), \(currentEnd)] complete: \(logs.count) logs")
                case let .partial(logs, received, expected):
                    allLogs.append(contentsOf: logs)
                    log.warning("Chunk [\(chunkStart), \(currentEnd)] partial: \(received)/\(expected) logs")
                case let .timeout(logs, received, expected):
                    allLogs.append(contentsOf: logs)
                    log.warning("Chunk [\(chunkStart), \(currentEnd)] timeout: \(received)/\(expected) logs")
                }
            } catch {
                // Log error but continue to next chunk for resilience (like ControlX2 line 90-91)
                log.error("Chunk [\(chunkStart), \(currentEnd)] failed: \(error)")
            }

            // Date-bound stop: once the oldest fetched entry is older than the requested bound
            // (≈ insulin duration), we have everything that matters for IOB — stop walking back.
            if let stopBeforeDate,
               let oldest = allLogs.map(\.pumpTimeSec).min(),
               Dates.fromJan12008EpochSecondsToDate(TimeInterval(oldest)) < stopBeforeDate
            {
                log.debug("Reached date bound \(stopBeforeDate); stopping backward fetch at seq \(chunkStart)")
                break
            }

            currentEnd = chunkStart - 1
        }

        activeCollector = nil
        return allLogs.sorted { $0.sequenceNum < $1.sequenceNum }
    }

    /// Fetch a single chunk of history logs.
    private func fetchChunk(
        startSequence: UInt32,
        count: Int,
        collector: ChunkedStreamCollector
    ) throws -> ChunkResult {
        guard let response = sender.sendMessage(
            HistoryLogRequest(startLog: startSequence, numberOfLogs: count),
            expecting: HistoryLogResponse.self
        ) as? HistoryLogResponse else {
            throw HistoryFetchError.noResponse
        }

        guard response.status == 0 else {
            throw HistoryFetchError.responseStatus(response.status)
        }

        collector.startCollecting(streamId: response.streamId, expectedCount: count)
        return try collector.pollForCompletion(timeout: chunkTimeout, pollInterval: TandemHistoryPollInterval)
    }

    private func resolvedStartSequence(from status: HistoryLogStatusResponse) -> UInt32? {
        let first = status.firstSequenceNum
        let last = status.lastSequenceNum

        if status.numEntries == 0 {
            return nil
        }

        if let requestedStart = startSequence {
            if requestedStart > last {
                return nil
            }

            if requestedStart < first {
                return first
            }

            return requestedStart
        }

        return first
    }
}
