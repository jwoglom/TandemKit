import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemKitReconciliationViewModelTests: XCTestCase {
    private typealias ViewModel = TandemKitReconciliationViewModel
    private static let pumpSerial: UInt32 = 654_321

    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var clock: ManualClock!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(PumpBasalHistory.date(7200))
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.featureFlags[.basalHistoryReporting] = false
        state.pumpState.pumpSerial = Self.pumpSerial
        state.bolusReportLedger = BolusReportLedger(trackingSince: .distantPast)
        state.reportedBasal = ReportedBasalLedger(trackingSince: .distantPast)
        state.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
        state.insulinType = .novolog
        state.hasSyncedBasalRateSchedule = true
        manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        manager.clock = clock
        delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.waitForDelegateCalls()
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        bluetooth = nil
        super.tearDown()
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
        manager.waitForDelegateCalls()
    }

    private func controlIQHour() -> PumpBasalHistory {
        var log = PumpBasalHistory()
        log.pcm(0, .closedLoop)
        for cycle in 0 ..< 12 {
            log.delivery(10 + cycle * 300, source: 3, rate: cycle.isMultiple(of: 2) ? 1000 : 2200)
        }
        return log
    }

    func testBeforeAnyPassTheScreenShowsStatusAndNoDiscrepancies() {
        let viewModel = ViewModel(pumpManager: manager)

        XCTAssertEqual(viewModel.status.map(\.id), ["reconciled", "history", "pass", "clock", "profile", "flags"])
        XCTAssertEqual(viewModel.status[0].value, "Never")
        XCTAssertTrue(viewModel.status[0].isWarning)
        XCTAssertEqual(viewModel.status[2].value, "None yet")
        XCTAssertEqual(viewModel.status[4].value, "Matches the app's schedule")
        XCTAssertEqual(viewModel.status[5].value, "Backfill on, boluses on, basal off")
        XCTAssertTrue(viewModel.discrepancies.isEmpty)
        XCTAssertTrue(viewModel.passes.isEmpty)
        XCTAssertTrue(viewModel.differences.isEmpty)
    }

    func testDifferencesLeftByReportingOffAreOneDiscrepancyAndARowEach() throws {
        pass(controlIQHour())
        let viewModel = ViewModel(pumpManager: manager)

        XCTAssertEqual(viewModel.discrepancies.map(\.id), ["differences-reportingOff"])
        XCTAssertEqual(viewModel.discrepancies[0].title, "Basal cycles differ, not corrected")
        XCTAssertEqual(viewModel.discrepancies[0].value, "6")
        XCTAssertTrue(viewModel.discrepancies[0].isWarning)
        XCTAssertTrue(try XCTUnwrap(viewModel.discrepancies[0].detail).contains("-0.600 U"))

        XCTAssertEqual(viewModel.differences.count, 6)
        XCTAssertEqual(Set(viewModel.differences.map(\.value)), ["Reporting off"])
        XCTAssertTrue(viewModel.differences.allSatisfy(\.isWarning))
        XCTAssertTrue(try XCTUnwrap(viewModel.differences[0].detail).hasPrefix("Pump: Control-IQ at 2.20 U/hr. App: 1.00 U/hr from its schedule"))

        XCTAssertEqual(viewModel.passes.count, 1)
        XCTAssertEqual(viewModel.passes[0].detail, "Records 1001–1013. Cycles: 6 matched, 6 differ, 0 corrected.")
        XCTAssertEqual(viewModel.status.last?.id, "residual")
    }

    func testCorrectedDifferencesAreNoDiscrepancy() {
        manager.state.featureFlags[.basalHistoryReporting] = true
        pass(controlIQHour())
        let viewModel = ViewModel(pumpManager: manager)

        XCTAssertTrue(viewModel.discrepancies.isEmpty)
        XCTAssertEqual(Set(viewModel.differences.map(\.value)), ["Corrected"])
        XCTAssertFalse(viewModel.differences.contains(where: \.isWarning))
    }

    func testThePendingDeliveryChangeAndUnreportedBolusAreDiscrepancies() {
        manager.state.deliveryTransitions.pending = DeliveryTransitionLedger.PendingTransition(
            prior: UnfinalizedDose(basalRate: 1.0, insulinType: .novolog, startDate: clock.now.addingTimeInterval(-600)),
            observed: .suspend,
            detectedAt: clock.now,
            lastConfirmed: clock.now.addingTimeInterval(-300)
        )
        manager.state.bolusReportLedger.noteUnreported(BolusReportLedger.UnreportedBolus(
            bolusId: 42,
            pumpSerial: Self.pumpSerial,
            startDate: clock.now.addingTimeInterval(-120),
            holdsBoundaryAt: clock.now.addingTimeInterval(-120)
        ))
        let viewModel = ViewModel(pumpManager: manager)

        XCTAssertEqual(viewModel.discrepancies.map(\.id), ["pending", "unreported-42"])
        XCTAssertEqual(viewModel.discrepancies[0].title, "Delivery change awaiting pump history")
        XCTAssertTrue(viewModel.discrepancies[0].detail?.hasPrefix("The pump reports a suspend where the scheduled basal was reported") == true)
        XCTAssertEqual(viewModel.discrepancies[1].title, "Pump bolus #42 not yet reported")
    }

    func testASkippedPassIsAWarningRowAndTheClockRowFollowsTheOffset() {
        manager.historyTickFailed(startedAt: clock.now)
        manager.state.currentPumpTime = clock.now.addingTimeInterval(400)
        manager.state.lastPumpTimeCheckDate = clock.now
        manager.state.pumpTimeCheckUTCOffset = TimeZone.current.secondsFromGMT()
        let viewModel = ViewModel(pumpManager: manager)

        XCTAssertEqual(viewModel.passes.first?.detail, "Skipped: Pump history could not be read")
        XCTAssertTrue(viewModel.passes.first?.isWarning == true)
        XCTAssertEqual(viewModel.status[3].value, "6 min 40 s ahead, skewed")
        XCTAssertTrue(viewModel.status[3].isWarning)
    }

    func testTheScreenRefreshesWhenTheStatusChanges() {
        let viewModel = ViewModel(pumpManager: manager)
        XCTAssertTrue(viewModel.passes.isEmpty)

        pass(controlIQHour())
        manager.notifyDelegateStateUpdated()
        let deadline = Date().addingTimeInterval(1)
        while viewModel.passes.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }

        XCTAssertEqual(viewModel.passes.count, 1)
    }

    func testWithoutAPumpManagerTheScreenIsEmpty() {
        let viewModel = ViewModel(pumpManager: nil)

        XCTAssertTrue(viewModel.status.isEmpty)
        XCTAssertTrue(viewModel.discrepancies.isEmpty)
    }
}
