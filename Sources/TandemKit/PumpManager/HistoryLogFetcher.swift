import Combine
import Foundation

/// Fetches a window of history logs ending at the pump's newest entry, mirroring ControlX2's
/// HistoryLogFetcher: the range is walked backward in chunks of 32, each HistoryLogRequest is
/// issued with the chunk's highest sequence number (the pump streams entries backward from
/// `startLog`), and a chunk is considered done once every sequence number in it has arrived or
/// a timeout elapses. Entries are deduplicated by sequence number, and after the initial walk a
/// single gap-healing pass re-requests any ranges that never arrived.
public final class HistoryLogFetcher {
    public struct Progress {
        public let fetchedCount: Int
        public let expectedCount: Int
        public let earliestFetched: Date?
        public let latestFetched: Date?
    }

    public enum FetchError: LocalizedError {
        case noStatusResponse
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .noStatusResponse:
                return "Unable to read the history log status from the pump"
            case .cancelled:
                return "History log fetch was cancelled"
            }
        }
    }

    private static let chunkSize: Int64 = 32
    private static let requestDelay: TimeInterval = 1.0
    private static let pollInterval: TimeInterval = 0.5
    private static let chunkTimeout: TimeInterval = 4.0
    private static let sendTimeout: DispatchTimeInterval = .seconds(45)

    private let pumpManager: TandemPumpManager
    private let logger = TandemLogger(category: "HistoryLogFetcher")
    private let queue = DispatchQueue(label: "com.jwoglom.TandemKit.historyLogFetcher")

    // Guards everything below; written from both the fetch queue and the BLE notification path.
    private let lock = NSLock()
    private var receivedSeqNums = Set<UInt32>()
    private var windowStart: Int64 = 0
    private var windowEnd: Int64 = -1
    private var earliestPumpTimeSec: UInt32?
    private var latestPumpTimeSec: UInt32?
    private var fetchActive = false
    private var cancelled = false

    private var streamSubscription: AnyCancellable?

    /// Called on the main queue for each history log not seen before in this fetch.
    public var onLog: ((HistoryLog) -> Void)?
    /// Called on the main queue for every HistoryLogStreamResponse received (including ones
    /// that only contain already-seen entries), for capture-style exporting.
    public var onStreamMessage: ((Date, HistoryLogStreamResponse) -> Void)?
    /// Called on the main queue whenever the fetched count advances.
    public var onProgress: ((Progress) -> Void)?

    public init(pumpManager: TandemPumpManager) {
        self.pumpManager = pumpManager
    }

    deinit {
        streamSubscription?.cancel()
    }

    /// Reads the pump's history log status (entry count and first/last sequence numbers).
    public func fetchStatus(completion: @escaping (HistoryLogStatusResponse?) -> Void) {
        pumpManager.bluetooth.ensureConnected { error in
            guard error == nil else {
                completion(nil)
                return
            }
            let response = self.pumpManager.bluetooth.write(
                message: HistoryLogStatusRequest(),
                expecting: HistoryLogStatusResponse.self
            ) as? HistoryLogStatusResponse
            completion(response)
        }
    }

    /// Reads exactly one history log by sequence number and returns it, without feeding the
    /// per-log/progress callbacks or the export capture — used to sample "guidepost" entries and
    /// to binary-search date boundaries. Blocks (bounded) on the calling thread, so must be run
    /// off the main queue. Returns nil if the entry did not stream back in time.
    ///
    /// Must not be called while a full `start(...)` fetch is in progress: the shared history-log
    /// stream would otherwise be consumed by both paths at once. The guard below enforces this.
    public func probeLog(sequenceNum: UInt32, timeout: TimeInterval = 6.0) -> HistoryLog? {
        lock.lock()
        let busy = fetchActive
        lock.unlock()
        if busy {
            logger.warning("Ignoring probeLog(\(sequenceNum)): fetch in progress")
            return nil
        }

        let captureLock = NSLock()
        var captured: HistoryLog?
        let streamSemaphore = DispatchSemaphore(value: 0)

        // Subscribe before sending so a fast stream response can't be missed.
        let subscription = pumpManager.historyLogStream.sink { response in
            for log in response.historyLogs where log.sequenceNum == sequenceNum {
                captureLock.lock()
                let firstHit = captured == nil
                if firstHit { captured = log }
                captureLock.unlock()
                if firstHit { streamSemaphore.signal() }
            }
        }
        defer { subscription.cancel() }

        let sendSemaphore = DispatchSemaphore(value: 0)
        pumpManager.bluetooth.ensureConnected { error in
            defer { sendSemaphore.signal() }
            guard error == nil else { return }
            _ = self.pumpManager.bluetooth.write(
                message: HistoryLogRequest(startLog: sequenceNum, numberOfLogs: 1),
                expecting: HistoryLogResponse.self
            )
        }

        // Wait for connect + request acknowledgement, then for the streamed entry itself. The
        // stream can arrive before the ack returns; the pre-installed subscription captures it
        // either way, so the second wait returns immediately in that case.
        _ = sendSemaphore.wait(timeout: .now() + Self.sendTimeout)
        _ = streamSemaphore.wait(timeout: .now() + timeout)

        captureLock.lock()
        defer { captureLock.unlock() }
        return captured
    }

    /// Fetches `numberOfLogs` entries ending at `endingAtSequenceNum` (inclusive), walking
    /// backward from there. When `endingAtSequenceNum` is nil the window ends at the pump's newest
    /// entry, matching the original "most recent N logs" behavior. The end is clamped into the
    /// pump's `[first, last]` range. Progress and per-log callbacks fire while the fetch runs;
    /// `completion` fires exactly once on the main queue.
    public func start(
        numberOfLogs: Int,
        endingAtSequenceNum: UInt32? = nil,
        completion: @escaping (Result<Progress, FetchError>) -> Void
    ) {
        lock.lock()
        if fetchActive {
            lock.unlock()
            logger.warning("Ignoring start(): fetch already in progress")
            return
        }
        fetchActive = true
        cancelled = false
        receivedSeqNums = []
        earliestPumpTimeSec = nil
        latestPumpTimeSec = nil
        windowStart = 0
        windowEnd = -1
        lock.unlock()

        streamSubscription = pumpManager.historyLogStream
            .sink { [weak self] response in
                self?.handleStreamResponse(response)
            }

        queue.async {
            let result = self.runFetch(numberOfLogs: numberOfLogs, endingAtSequenceNum: endingAtSequenceNum)

            self.lock.lock()
            self.fetchActive = false
            self.lock.unlock()
            self.streamSubscription?.cancel()
            self.streamSubscription = nil

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    private func runFetch(numberOfLogs: Int, endingAtSequenceNum: UInt32?) -> Result<Progress, FetchError> {
        guard let status = sendSync(
            HistoryLogStatusRequest(),
            expecting: HistoryLogStatusResponse.self
        ) as? HistoryLogStatusResponse else {
            logger.error("Failed to fetch history log status")
            return .failure(.noStatusResponse)
        }

        let first = Int64(status.firstSequenceNum)
        let last = Int64(status.lastSequenceNum)
        let requestedEnd = endingAtSequenceNum.map { Int64($0) } ?? last
        let end = min(max(requestedEnd, first), last)
        let start = min(max(first, end - Int64(numberOfLogs) + 1), end)

        lock.lock()
        windowStart = start
        windowEnd = end
        lock.unlock()

        logger.info("Fetching history logs \(start)-\(end) (pump has \(first)-\(last))")
        walkRange(startId: start, endId: end)

        // Gap-healing pass: re-request whatever never arrived, newest range first, like
        // ControlX2 does on its next status cycle.
        let missing = missingRanges(startId: start, endId: end)
        if !missing.isEmpty, !isCancelled {
            logger.info("Retrying \(missing.count) missing history log range(s)")
            for range in missing.reversed() {
                walkRange(startId: range.lowerBound, endId: range.upperBound)
            }
        }

        if isCancelled {
            return .failure(.cancelled)
        }
        return .success(currentProgress())
    }

    /// Walks [startId, endId] backward in chunks, requesting each chunk's top sequence number.
    private func walkRange(startId: Int64, endId: Int64) {
        var i = endId
        while i >= startId, !isCancelled {
            let count = Int(min(Self.chunkSize, i - startId + 1))
            let chunkStart = i - Int64(count) + 1

            if sendSync(
                HistoryLogRequest(startLog: UInt32(i), numberOfLogs: count),
                expecting: HistoryLogResponse.self
            ) == nil {
                logger.warning("No HistoryLogResponse for chunk \(chunkStart)-\(i)")
            }

            // Same cadence as ControlX2: initial delay, then poll until the chunk has fully
            // streamed in or the per-chunk timeout expires (stragglers are healed later).
            sleepUnlessCancelled(Self.requestDelay)
            var waited: TimeInterval = 0
            while !isCancelled, waited < Self.chunkTimeout {
                if receivedCount(from: chunkStart, to: i) >= count {
                    break
                }
                sleepUnlessCancelled(Self.pollInterval)
                waited += Self.pollInterval
            }

            i = chunkStart - 1
        }
    }

    private func handleStreamResponse(_ response: HistoryLogStreamResponse) {
        let receivedAt = Date()

        lock.lock()
        guard fetchActive else {
            lock.unlock()
            return
        }
        var newLogs: [HistoryLog] = []
        for log in response.historyLogs where !receivedSeqNums.contains(log.sequenceNum) {
            receivedSeqNums.insert(log.sequenceNum)
            newLogs.append(log)
            if earliestPumpTimeSec.map({ log.pumpTimeSec < $0 }) ?? true {
                earliestPumpTimeSec = log.pumpTimeSec
            }
            if latestPumpTimeSec.map({ log.pumpTimeSec > $0 }) ?? true {
                latestPumpTimeSec = log.pumpTimeSec
            }
        }
        let progress = progressLocked()
        lock.unlock()

        DispatchQueue.main.async {
            self.onStreamMessage?(receivedAt, response)
            for log in newLogs {
                self.onLog?(log)
            }
            if !newLogs.isEmpty {
                self.onProgress?(progress)
            }
        }
    }

    private func currentProgress() -> Progress {
        lock.lock()
        defer { lock.unlock() }
        return progressLocked()
    }

    private func progressLocked() -> Progress {
        let expected = windowEnd >= windowStart ? Int(windowEnd - windowStart + 1) : 0
        let fetched = receivedSeqNums.filter { Int64($0) >= windowStart && Int64($0) <= windowEnd }.count
        return Progress(
            fetchedCount: fetched,
            expectedCount: expected,
            earliestFetched: earliestPumpTimeSec.map { Dates.fromJan12008EpochSecondsToDate(TimeInterval($0)) },
            latestFetched: latestPumpTimeSec.map { Dates.fromJan12008EpochSecondsToDate(TimeInterval($0)) }
        )
    }

    private func receivedCount(from start: Int64, to end: Int64) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return receivedSeqNums.filter { Int64($0) >= start && Int64($0) <= end }.count
    }

    /// Contiguous sub-ranges of [startId, endId] with no received entries, ascending.
    private func missingRanges(startId: Int64, endId: Int64) -> [ClosedRange<Int64>] {
        lock.lock()
        let received = receivedSeqNums
        lock.unlock()

        var ranges: [ClosedRange<Int64>] = []
        var gapStart: Int64?
        for seq in startId ... endId {
            if received.contains(UInt32(seq)) {
                if let start = gapStart {
                    ranges.append(start ... (seq - 1))
                    gapStart = nil
                }
            } else if gapStart == nil {
                gapStart = seq
            }
        }
        if let start = gapStart {
            ranges.append(start ... endId)
        }
        return ranges
    }

    private func sendSync(_ message: Message, expecting: Message.Type) -> Message? {
        let semaphore = DispatchSemaphore(value: 0)
        var response: Message?
        pumpManager.bluetooth.ensureConnected { error in
            defer { semaphore.signal() }
            guard error == nil else {
                return
            }
            response = self.pumpManager.bluetooth.write(message: message, expecting: expecting)
        }
        _ = semaphore.wait(timeout: .now() + Self.sendTimeout)
        return response
    }

    private func sleepUnlessCancelled(_ interval: TimeInterval) {
        guard !isCancelled else { return }
        Thread.sleep(forTimeInterval: interval)
    }
}
