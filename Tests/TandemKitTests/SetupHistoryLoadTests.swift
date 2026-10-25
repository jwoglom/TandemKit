import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class SetupHistoryLoadTests: XCTestCase {
    private static let pumpSerial: UInt32 = 123_456
    private let serial = HistoryLogSyncIdentifier.PumpSerial(SetupHistoryLoadTests.pumpSerial)!

    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    private lazy var nowPumpTimeSec = UInt32(Dates.fromInstantToJan12008EpochSeconds(Date()))

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.featureFlags[.historyDoseReporting] = true
        state.pumpState.pumpSerial = Self.pumpSerial
        // A manager set up just now, before a host has adopted it.
        manager = TandemPumpManager(state: state, bluetooth: bluetooth)
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        delegateQueue = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func pumpBolus(bolusId: Int, units: Float, firstSequenceNum: UInt32, secondsAgo: UInt32) -> [HistoryLog] {
        let activated = nowPumpTimeSec - secondsAgo
        return [
            BolusActivatedHistoryLog(
                pumpTimeSec: activated,
                sequenceNum: firstSequenceNum,
                bolusId: bolusId,
                selectedIob: 0,
                iob: 0,
                bolusSize: units
            ),
            BolusDeliveryHistoryLog(
                pumpTimeSec: activated,
                sequenceNum: firstSequenceNum + 1,
                bolusID: bolusId,
                bolusDeliveryStatus: 1,
                bolusTypeBitmask: 1,
                bolusSource: BolusDeliveryHistoryLog.BolusSource.quickBolus.rawValue,
                remoteId: 0,
                requestedNow: Int(units * 1000),
                requestedLater: 0,
                correction: 0,
                extendedDurationRequested: 0,
                deliveredTotal: 0
            ),
            BolusCompletedHistoryLog(
                pumpTimeSec: activated + 60,
                sequenceNum: firstSequenceNum + 2,
                completionStatusId: 3,
                bolusId: bolusId,
                iob: units,
                insulinDelivered: units,
                insulinRequested: units
            )
        ]
    }

    private func stubPump(serving logs: [HistoryLog]) {
        let bySequence = Dictionary(uniqueKeysWithValues: logs.map { ($0.sequenceNum, $0) })
        let sequences = logs.map(\.sequenceNum)
        bluetooth.stub(HistoryLogStatusRequest.self, with: HistoryLogStatusResponse(
            numEntries: UInt32(logs.count),
            firstSequenceNum: sequences.min()!,
            lastSequenceNum: sequences.max()!
        ))
        bluetooth.stub(HistoryLogRequest.self, with: HistoryLogResponse(status: 0, streamId: 7))
        bluetooth.onWrite = { [weak self] message in
            guard let self, let request = message as? HistoryLogRequest else { return }
            let top = request.startLog
            let bottom = top >= UInt32(max(request.numberOfLogs, 1)) ? top - UInt32(max(request.numberOfLogs, 1)) + 1 : 0
            let streamed = stride(from: top, through: bottom, by: -1).compactMap { bySequence[$0] }
            guard !streamed.isEmpty else { return }
            self.manager.historyLogStream.send(HistoryLogStreamResponse(
                numberOfHistoryLogs: streamed.count,
                streamId: 7,
                historyLogStreamBytes: streamed.map(\.cargo)
            ))
        }
    }

    /// As the setup's sync does, before the user chooses.
    private func runTick() {
        let ticked = expectation(description: "backfill tick completes")
        manager.historyBackfillCoordinator.runTick { _ in ticked.fulfill() }
        wait(for: [ticked], timeout: 90.0)
    }

    @discardableResult
    private func load(progress: ((Double) -> Void)? = nil) -> Error? {
        var result: Error?
        let loaded = expectation(description: "history load completes")
        manager.loadHistoryForSetup(progress: { progress?($0) }) { error in
            result = error
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 90.0)
        return result
    }

    private func adoptByHost() {
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "setup-history-load-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
        delegateQueue.sync {}
    }

    private var reportedBoluses: [NewPumpEvent] {
        delegate.pumpEventBatches.flatMap(\.events).filter { $0.dose?.type == .bolus }
    }

    // MARK: - Tests

    func testWithoutTheLoadABolusFromBeforeSetupIsNotReported() {
        stubPump(serving: pumpBolus(bolusId: 70, units: 3.6, firstSequenceNum: 1, secondsAgo: 3 * 3600))

        runTick()
        adoptByHost()

        XCTAssertTrue(reportedBoluses.isEmpty)
    }

    func testTheLoadReportsABolusFromBeforeSetupToTheHostThatAdoptsTheManager() throws {
        stubPump(serving: pumpBolus(bolusId: 70, units: 3.6, firstSequenceNum: 1, secondsAgo: 3 * 3600))
        runTick()

        XCTAssertNil(load())
        adoptByHost()

        let event = try XCTUnwrap(reportedBoluses.first)
        XCTAssertEqual(reportedBoluses.count, 1)
        XCTAssertEqual(event.raw, HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 70))
        XCTAssertEqual(event.dose?.deliveredUnits ?? 0, 3.6, accuracy: 0.001)
        XCTAssertEqual(event.dose?.isMutable, false)
    }

    func testTheLoadReportsNothingOlderThanItsWindow() {
        stubPump(serving: pumpBolus(bolusId: 71, units: 2.0, firstSequenceNum: 1, secondsAgo: 6 * 3600 + 900)
            + pumpBolus(bolusId: 72, units: 1.0, firstSequenceNum: 4, secondsAgo: 5 * 3600))

        XCTAssertNil(load())
        adoptByHost()

        XCTAssertEqual(reportedBoluses.map(\.raw), [HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 72)])
    }

    func testTheLoadEndsWithItsProgressFull() {
        stubPump(serving: pumpBolus(bolusId: 73, units: 1.0, firstSequenceNum: 1, secondsAgo: 3600))
        var values: [Double] = []
        let lock = NSLock()

        XCTAssertNil(load { value in
            lock.lock()
            values.append(value)
            lock.unlock()
        })

        lock.lock()
        defer { lock.unlock() }
        XCTAssertEqual(values.last, 1)
        XCTAssertTrue(values.allSatisfy { (0 ... 1).contains($0) })
    }

    func testAnEmptyLogIsLoadedAtOnce() {
        bluetooth.stub(HistoryLogStatusRequest.self, with: HistoryLogStatusResponse(numEntries: 0, firstSequenceNum: 0, lastSequenceNum: 0))

        XCTAssertNil(load())
    }

    func testTheLoadFailsWhenThePumpsHistoryCannotBeRead() {
        XCTAssertEqual(load() as? SetupHistoryLoadError, .historyUnreadable)
    }

    func testTheLoadIsOfferedOnlyWithHistoryDoseReporting() {
        XCTAssertTrue(manager.canLoadHistoryForSetup)

        manager.state.featureFlags[.historyDoseReporting] = false

        XCTAssertFalse(manager.canLoadHistoryForSetup)
    }

    func testLoadingHistoryReportsBolusesFromTheLoadOn() {
        let since = Date().addingTimeInterval(-TandemPumpManager.setupHistoryLoadWindow)
        var ledger = BolusReportLedger(trackingSince: Date())

        ledger.reportHistory(since: since)
        ledger.reportHistory(since: Date())

        XCTAssertEqual(ledger.trackingSince, since)
    }
}
