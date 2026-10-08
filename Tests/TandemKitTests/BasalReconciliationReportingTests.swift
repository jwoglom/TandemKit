import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class BasalReconciliationReportingTests: XCTestCase {
    private static let pumpSerial: UInt32 = 654_321
    private let serial = HistoryLogSyncIdentifier.PumpSerial(BasalReconciliationReportingTests.pumpSerial)!

    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!
    private var clock: ManualClock!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(PumpBasalHistory.date(7200))
        manager = makeManager(state: Self.state())
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        delegateQueue = nil
        bluetooth = nil
        super.tearDown()
    }

    private static func state() -> TandemPumpManagerState {
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.pumpState.pumpSerial = pumpSerial
        state.bolusReportLedger = BolusReportLedger(trackingSince: .distantPast)
        state.reportedBasal = ReportedBasalLedger(trackingSince: .distantPast)
        state.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
        state.insulinType = .novolog
        return state
    }

    private func makeManager(state: TandemPumpManagerState) -> TandemPumpManager {
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        manager.clock = clock
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "basal-reconciliation-reporting-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
        return manager
    }

    private func pass(_ log: PumpBasalHistory) {
        manager.storeHistoryLogs(log.logs, now: clock.now)
        let sequences = log.logs.map(\.sequenceNum)
        let range = sequences.min()! ... sequences.max()!
        manager.reportHistoryDoses(
            after: HistoryBackfillCoordinator.TickOutcome(
                bookkeeping: HistoryBackfillState(pumpSerial: Self.pumpSerial, watermark: range.upperBound),
                rangesRead: [range],
                sessionCovered: range,
                isDeepBackfillComplete: true,
                emitFloor: .distantPast,
                startedAt: clock.now,
                pumpSequenceRange: range
            ),
            now: clock.now
        )
        delegateQueue.sync {}
    }

    private func controlIQHour() -> PumpBasalHistory {
        var log = PumpBasalHistory()
        log.pcm(0, .closedLoop)
        for cycle in 0 ..< 12 {
            log.delivery(10 + cycle * 300, source: 3, rate: cycle.isMultiple(of: 2) ? 1000 : 2200)
        }
        return log
    }

    func testDifferencesAreLoggedOnceAndNothingIsReported() {
        let log = controlIQHour()

        pass(log)
        XCTAssertEqual(manager.loggedBasalDifferences.count, 6)
        pass(log)

        XCTAssertEqual(manager.loggedBasalDifferences.count, 6)
        XCTAssertTrue(delegate.pumpEventBatches.flatMap(\.events).isEmpty)
    }

    func testNothingIsComparedWithoutTheBackfill() {
        manager.state.featureFlags[.historyBackfill] = false

        pass(controlIQHour())

        XCTAssertTrue(manager.loggedBasalDifferences.isEmpty)
    }
}
