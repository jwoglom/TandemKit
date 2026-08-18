import Combine
import Foundation
@testable import TandemKit
import XCTest

/// Drives `HistoryLogFetcher` end to end against a stub pump.
///
/// The pump does not reply to a `HistoryLogRequest` with the entries; it acknowledges the request
/// and then streams the logs back as unsolicited notifications on a separate characteristic. The
/// stub reproduces that split — the ack comes from the write, the entries are published onto
/// `historyLogStream` — so the fetcher's chunk-completion and gap-healing logic is exercised for
/// real.
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerHistoryIntegrationTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var fetcher: HistoryLogFetcher!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        fetcher = HistoryLogFetcher(pumpManager: manager)
    }

    override func tearDown() {
        fetcher?.cancel()
        fetcher = nil
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// A recent pump-clock base for generated entries. Timestamps must be inside the retention
    /// window, or the manager's store would prune them as they arrive.
    private lazy var basePumpTimeSec = UInt32(Dates.fromInstantToJan12008EpochSeconds(Date()))

    private func log(sequenceNum: UInt32) -> BolusActivatedHistoryLog {
        BolusActivatedHistoryLog(
            pumpTimeSec: basePumpTimeSec + sequenceNum,
            sequenceNum: sequenceNum,
            bolusId: Int(sequenceNum),
            selectedIob: 0,
            iob: 0,
            bolusSize: 1.0
        )
    }

    private func stubStatus(first: UInt32, last: UInt32) {
        bluetooth.stub(HistoryLogStatusRequest.self, with: HistoryLogStatusResponse(
            numEntries: last - first + 1,
            firstSequenceNum: first,
            lastSequenceNum: last
        ))
    }

    /// Acknowledges every `HistoryLogRequest` and streams back the entries it asked for, minus
    /// anything in `withholding` (used to force the gap-healing pass).
    private func stubHistoryStream(
        withholding: Set<UInt32> = [],
        streamEachChunkTwice: Bool = false,
        streamId: Int = 7
    ) {
        bluetooth.stub(HistoryLogRequest.self, with: HistoryLogResponse(status: 0, streamId: streamId))

        bluetooth.onWrite = { [weak self] message in
            guard let self, let request = message as? HistoryLogRequest else { return }

            // The pump streams backward from startLog, so build the requested window the same way.
            let top = Int(request.startLog)
            let bottom = max(0, top - max(request.numberOfLogs, 1) + 1)

            let logs = stride(from: top, through: bottom, by: -1)
                .map { UInt32($0) }
                .filter { !withholding.contains($0) }
                .map { self.log(sequenceNum: $0) }

            guard !logs.isEmpty else { return }

            let response = HistoryLogStreamResponse(
                numberOfHistoryLogs: logs.count,
                streamId: streamId,
                historyLogStreamBytes: logs.map(\.cargo)
            )
            self.manager.historyLogStream.send(response)
            if streamEachChunkTwice {
                self.manager.historyLogStream.send(response)
            }
        }
    }

    private func runFetch(numberOfLogs: Int, endingAt: UInt32? = nil) -> Result<HistoryLogFetcher.Progress, HistoryLogFetcher.FetchError> {
        var result: Result<HistoryLogFetcher.Progress, HistoryLogFetcher.FetchError>!
        let expectation = expectation(description: "history fetch completes")
        fetcher.start(numberOfLogs: numberOfLogs, endingAtSequenceNum: endingAt) {
            result = $0
            expectation.fulfill()
        }
        // The fetcher waits out a fixed post-request delay before polling for chunk completion, and
        // a chunk that never completes burns its full timeout before the gap-healing pass. Both are
        // wall-clock waits inside HistoryLogFetcher, so allow well beyond the happy path.
        wait(for: [expectation], timeout: 60.0)
        return result
    }

    // MARK: - Status

    func testFetchStatusReadsPumpRange() {
        stubStatus(first: 5, last: 12)

        var status: HistoryLogStatusResponse?
        let expectation = expectation(description: "status")
        fetcher.fetchStatus { status = $0; expectation.fulfill() }
        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(status?.firstSequenceNum, 5)
        XCTAssertEqual(status?.lastSequenceNum, 12)
    }

    func testFetchStatusReportsNilWhenDisconnected() {
        stubStatus(first: 5, last: 12)
        bluetooth.connectError = PumpCommError.pumpNotConnected

        var status: HistoryLogStatusResponse? = HistoryLogStatusResponse(
            numEntries: 0,
            firstSequenceNum: 0,
            lastSequenceNum: 0
        )
        let expectation = expectation(description: "status")
        fetcher.fetchStatus { status = $0; expectation.fulfill() }
        wait(for: [expectation], timeout: 5.0)

        XCTAssertNil(status)
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }

    // MARK: - Fetching

    func testFetchCollectsStreamedLogs() {
        stubStatus(first: 1, last: 5)
        stubHistoryStream()

        var received: [UInt32] = []
        fetcher.onLog = { received.append($0.sequenceNum) }

        let result = runFetch(numberOfLogs: 5)

        guard case let .success(progress) = result else {
            return XCTFail("Expected success, got \(String(describing: result))")
        }
        XCTAssertEqual(progress.expectedCount, 5)
        XCTAssertEqual(progress.fetchedCount, 5)
        XCTAssertEqual(received.sorted(), [1, 2, 3, 4, 5])
    }

    /// The window is clamped into the pump's `[first, last]` range, so asking for more entries than
    /// the pump holds must not walk below its first sequence number.
    func testFetchClampsWindowToPumpRange() {
        stubStatus(first: 10, last: 12)
        stubHistoryStream()

        let result = runFetch(numberOfLogs: 100)

        guard case let .success(progress) = result else {
            return XCTFail("Expected success, got \(String(describing: result))")
        }
        XCTAssertEqual(progress.expectedCount, 3)
        XCTAssertEqual(progress.fetchedCount, 3)

        let requests = bluetooth.sent(HistoryLogRequest.self)
        XCTAssertFalse(requests.isEmpty)
        XCTAssertTrue(requests.allSatisfy { $0.startLog <= 12 })
    }

    func testFetchEndingAtSequenceWalksBackwardFromThere() {
        stubStatus(first: 1, last: 20)
        stubHistoryStream()

        var received: [UInt32] = []
        fetcher.onLog = { received.append($0.sequenceNum) }

        let result = runFetch(numberOfLogs: 3, endingAt: 10)

        guard case let .success(progress) = result else {
            return XCTFail("Expected success, got \(String(describing: result))")
        }
        XCTAssertEqual(progress.expectedCount, 3)
        XCTAssertEqual(received.sorted(), [8, 9, 10])
    }

    /// A log that arrives twice — the pump re-streams entries whenever a chunk is re-requested —
    /// must reach the caller only once, or Loop would double-count the dose.
    func testDuplicateStreamEntriesAreReportedOnce() {
        stubStatus(first: 1, last: 3)
        stubHistoryStream(streamEachChunkTwice: true)

        var received: [UInt32] = []
        fetcher.onLog = { received.append($0.sequenceNum) }

        let result = runFetch(numberOfLogs: 3)

        guard case let .success(progress) = result else {
            return XCTFail("Expected success, got \(String(describing: result))")
        }
        XCTAssertEqual(received.sorted(), [1, 2, 3])
        XCTAssertEqual(progress.fetchedCount, 3)
    }

    /// Entries streamed once the fetch has finished belong to no window and must not be reported.
    func testStreamEntriesAfterFetchAreIgnored() {
        stubStatus(first: 1, last: 3)
        stubHistoryStream()

        var received: [UInt32] = []
        fetcher.onLog = { received.append($0.sequenceNum) }

        _ = runFetch(numberOfLogs: 3)
        let countAfterFetch = received.count

        manager.historyLogStream.send(HistoryLogStreamResponse(
            numberOfHistoryLogs: 1,
            streamId: 7,
            historyLogStreamBytes: [log(sequenceNum: 99).cargo]
        ))

        XCTAssertEqual(received.count, countAfterFetch)
    }

    /// Entries that never stream back trigger a second, gap-healing pass over the missing range.
    func testMissingEntriesAreReRequested() {
        stubStatus(first: 1, last: 4)
        stubHistoryStream(withholding: [3])

        let result = runFetch(numberOfLogs: 4)

        guard case let .success(progress) = result else {
            return XCTFail("Expected success, got \(String(describing: result))")
        }
        XCTAssertEqual(progress.expectedCount, 4)
        XCTAssertEqual(progress.fetchedCount, 3, "The withheld entry should still be missing")
        XCTAssertGreaterThan(
            bluetooth.sent(HistoryLogRequest.self).count,
            1,
            "The missing range should be re-requested"
        )
    }

    func testFetchFailsWhenStatusIsUnavailable() {
        bluetooth.stub(HistoryLogStatusRequest.self) { _ in nil }

        let result = runFetch(numberOfLogs: 3)

        guard case .failure(.noStatusResponse) = result else {
            return XCTFail("Expected noStatusResponse, got \(String(describing: result))")
        }
    }

    // MARK: - Probing a single entry

    func testProbeLogReturnsRequestedEntry() {
        stubHistoryStream()

        let probed = fetcher.probeLog(sequenceNum: 42, timeout: 5.0)

        XCTAssertEqual(probed?.sequenceNum, 42)
        XCTAssertEqual(bluetooth.sent(HistoryLogRequest.self).first?.startLog, 42)
    }

    func testProbeLogReturnsNilWhenEntryNeverStreams() {
        bluetooth.stub(HistoryLogRequest.self, with: HistoryLogResponse(status: 0, streamId: 7))

        XCTAssertNil(fetcher.probeLog(sequenceNum: 42, timeout: 0.5))
    }

    // MARK: - Session store

    private static let pumpSerial: UInt32 = 123_456

    private func setPumpSerial() {
        manager.state.pumpState.pumpSerial = Self.pumpSerial
    }

    func testStreamedLogsArePersistedToSessionStore() throws {
        setPumpSerial()
        stubStatus(first: 1, last: 5)
        stubHistoryStream()

        _ = runFetch(numberOfLogs: 5)

        XCTAssertEqual(try manager.historyLogStore.count(pumpSerial: Self.pumpSerial), 5)
        XCTAssertEqual(try manager.historyLogStore.newest(pumpSerial: Self.pumpSerial)?.sequenceNum, 5)
        XCTAssertEqual(try manager.historyLogStore.oldest(pumpSerial: Self.pumpSerial)?.sequenceNum, 1)
    }

    /// Until a PumpVersionResponse has populated the serial, entries cannot be keyed and must not
    /// be stored — an entry filed under a placeholder serial would never be found again.
    func testLogsAreNotStoredBeforeSerialIsKnown() throws {
        stubStatus(first: 1, last: 3)
        stubHistoryStream()

        _ = runFetch(numberOfLogs: 3)

        XCTAssertEqual(try manager.historyLogStore.count(pumpSerial: 0), 0)
        XCTAssertEqual(try manager.historyLogStore.count(pumpSerial: Self.pumpSerial), 0)
    }

    func testRepeatFetchIsServedFromStoreWithoutChunkRequests() {
        setPumpSerial()
        stubStatus(first: 1, last: 5)
        stubHistoryStream()

        _ = runFetch(numberOfLogs: 5)
        let requestsAfterFirst = bluetooth.sent(HistoryLogRequest.self).count
        XCTAssertGreaterThan(requestsAfterFirst, 0)

        var received: [UInt32] = []
        fetcher.onLog = { received.append($0.sequenceNum) }
        let result = runFetch(numberOfLogs: 5)

        guard case let .success(progress) = result else {
            return XCTFail("Expected success, got \(String(describing: result))")
        }
        XCTAssertEqual(progress.fetchedCount, 5)
        XCTAssertEqual(received.sorted(), [1, 2, 3, 4, 5], "Stored entries must reach onLog like streamed ones")
        XCTAssertEqual(
            bluetooth.sent(HistoryLogRequest.self).count,
            requestsAfterFirst,
            "A window fully covered by the store must not request chunks from the pump"
        )
    }

    func testFetchRequestsOnlyRangesMissingFromStore() throws {
        setPumpSerial()
        stubStatus(first: 1, last: 5)
        stubHistoryStream()

        // Pre-store the middle of the window, as an earlier fetch would have.
        try manager.historyLogStore.insert([2, 3, 4].map { log(sequenceNum: $0) }, pumpSerial: Self.pumpSerial)

        var received: [UInt32] = []
        fetcher.onLog = { received.append($0.sequenceNum) }
        let result = runFetch(numberOfLogs: 5)

        guard case let .success(progress) = result else {
            return XCTFail("Expected success, got \(String(describing: result))")
        }
        XCTAssertEqual(progress.fetchedCount, 5)
        XCTAssertEqual(received.sorted(), [1, 2, 3, 4, 5])

        // Only the store's gaps are requested, newest range first.
        let requests = bluetooth.sent(HistoryLogRequest.self)
        XCTAssertEqual(requests.map(\.startLog), [5, 1])
        XCTAssertTrue(requests.allSatisfy { $0.numberOfLogs == 1 })
    }

    func testRetentionPruneRunsAtMostOncePerInterval() throws {
        setPumpSerial()
        let now = Date()

        // The first insert primes the prune clock (nothing is expired yet).
        manager.storeHistoryLogs([log(sequenceNum: 1)], now: now)
        XCTAssertEqual(try manager.historyLogStore.count(pumpSerial: Self.pumpSerial), 1)

        // An entry far past retention survives when it arrives inside the prune interval...
        let expired = BolusActivatedHistoryLog(
            pumpTimeSec: 1000, // 2008, far outside the 90-day retention window
            sequenceNum: 2,
            bolusId: 2,
            selectedIob: 0,
            iob: 0,
            bolusSize: 1.0
        )
        manager.storeHistoryLogs([expired], now: now.addingTimeInterval(60))
        XCTAssertEqual(try manager.historyLogStore.count(pumpSerial: Self.pumpSerial), 2)

        // ...and is pruned by the first insert after the interval elapses.
        manager.storeHistoryLogs(
            [log(sequenceNum: 3)],
            now: now.addingTimeInterval(TandemPumpManager.historyLogPruneInterval + 1)
        )
        XCTAssertEqual(
            try manager.historyLogStore.sequenceNumbers(pumpSerial: Self.pumpSerial, in: 1 ... 3),
            [1, 3]
        )
    }
}
