import Dispatch
import Foundation
import TandemCore

/// Errors that can occur during a history fetch session.
enum HistoryFetchError: Error, Equatable {
    case invalidRange(start: UInt32, firstAvailable: UInt32, lastAvailable: UInt32)
    case responseStatus(Int)
    case streamTimeout(expected: Int, received: Int)
}

/// Orchestrates a single history fetch request/response sequence.
///
/// The session sends a status request to determine the available sequence range,
/// issues a history request for the desired slice, and collects matching
/// `HistoryLogStreamResponse` notifications until the expected number of entries
/// arrive or a timeout occurs.
final class HistoryFetchSession {
    private let transport: PumpMessageTransport
    private let pumpComm: PumpComm
    private let startSequence: UInt32?
    private let maxEntries: Int
    private let streamTimeout: TimeInterval

    private let queue = DispatchQueue(label: "com.loopkit.TandemKit.HistoryFetchSession")

    private var activeStreamId: Int?
    private var expectedCount: Int?
    private var collected: [HistoryLog] = []
    private var finished = false
    private var semaphore: DispatchSemaphore?

    init(
        transport: PumpMessageTransport,
        pumpComm: PumpComm,
        startSequence: UInt32?,
        maxEntries: Int = 100,
        streamTimeout: TimeInterval = 10
    ) {
        self.transport = transport
        self.pumpComm = pumpComm
        self.startSequence = startSequence
        self.maxEntries = maxEntries
        self.streamTimeout = streamTimeout
    }

    /// Collect a streamed response emitted by the pump.
    func handleStreamResponse(_ response: HistoryLogStreamResponse) {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.finished,
                  let expected = self.expectedCount,
                  let streamId = self.activeStreamId,
                  streamId == response.streamId else {
                return
            }

            self.collected.append(contentsOf: response.historyLogs)

            if self.collected.count >= expected {
                self.finished = true
                self.semaphore?.signal()
            }
        }
    }

    /// Execute the fetch flow and return sorted history logs.
    func fetch() throws -> [HistoryLog] {
        let status: HistoryLogStatusResponse = try pumpComm.sendMessage(
            transport: transport,
            message: HistoryLogStatusRequest(),
            expecting: HistoryLogStatusResponse.self
        )

        let start = resolvedStartSequence(from: status)
        guard let start else {
            return []
        }

        let availableCount = Int(status.lastSequenceNum &- start + 1)
        let requestCount = max(0, min(maxEntries, availableCount))

        let response: HistoryLogResponse = try pumpComm.sendMessage(
            transport: transport,
            message: HistoryLogRequest(startLog: start, numberOfLogs: requestCount),
            expecting: HistoryLogResponse.self
        )

        guard response.status == 0 else {
            throw HistoryFetchError.responseStatus(response.status)
        }

        return try awaitStreamedLogs(streamId: response.streamId, expected: requestCount)
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

    private func awaitStreamedLogs(streamId: Int, expected: Int) throws -> [HistoryLog] {
        if expected == 0 {
            return []
        }

        let semaphore = DispatchSemaphore(value: 0)

        queue.sync {
            activeStreamId = streamId
            expectedCount = expected
            collected = []
            finished = false
            self.semaphore = semaphore
        }

        let waitResult = semaphore.wait(timeout: .now() + streamTimeout)

        let results = queue.sync { () -> [HistoryLog] in
            finished = true
            semaphore.signal()
            return collected.sorted { $0.sequenceNum < $1.sequenceNum }
        }

        guard waitResult == .success else {
            throw HistoryFetchError.streamTimeout(expected: expected, received: results.count)
        }

        return results
    }
}
