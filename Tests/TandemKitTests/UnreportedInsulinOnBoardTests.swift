@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class UnreportedInsulinOnBoardTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!

    private var now: Date { clock.now }

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock()
    }

    override func tearDown() {
        bluetooth = nil
        clock = nil
        super.tearDown()
    }

    private func makeManager(controlIQEnabled: Bool?, reportedBoluses: [Double] = []) -> TandemPumpManager {
        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState.apiVersion = KnownApiVersion.mobiApiV3_5.value
        state.controlIQEnabled = controlIQEnabled
        state.pumpInsulinDuration = PumpInsulinDuration(.hours(5))
        state.bolusReportLedger = BolusReportLedger(trackingSince: now.addingTimeInterval(-.hours(12)))
        for (index, units) in reportedBoluses.enumerated() {
            state.bolusReportLedger.record(entry(bolusId: index + 1, hoursAgo: 1, units: units))
        }
        return TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
    }

    private func entry(bolusId: Int, hoursAgo: Double, units: Double?) -> BolusReportLedger.Entry {
        BolusReportLedger.Entry(
            bolusId: bolusId,
            pumpSerial: 123_456,
            origin: .commanded,
            raw: Data("bolus \(bolusId)".utf8),
            eventDate: now.addingTimeInterval(-hoursAgo * 3600),
            automatic: false,
            isFinalized: true,
            units: units
        )
    }

    private func stubInsulinOnBoard(milliunits: UInt32, type: ControlIQIOBResponse.IOBType) {
        bluetooth.stub(ControlIQIOBRequest.self, with: ControlIQIOBResponse(
            mudaliarIOB: type == .MUDALIAR ? milliunits : 0,
            timeRemainingSeconds: 14400,
            mudaliarTotalIOB: milliunits,
            swan6hrIOB: type == .SWAN_6HR ? milliunits : 0,
            iobType: type.rawValue
        ))
    }

    // MARK: - Reading the pump's IOB

    func testInsulinOnBoardIsNotReadBeforeThePumpAnswersAControlIQRead() {
        let manager = makeManager(controlIQEnabled: nil)

        XCTAssertNil(manager.fetchInsulinOnBoard())

        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
        XCTAssertNil(manager.state.latestInsulinOnBoard)
    }

    func testInsulinOnBoardIsStoredInUnitsAsThePumpDisplaysIt() {
        let manager = makeManager(controlIQEnabled: true)
        stubInsulinOnBoard(milliunits: 1234, type: .SWAN_6HR)

        manager.fetchInsulinOnBoard()

        XCTAssertEqual(manager.state.latestInsulinOnBoard ?? 0, 1.234, accuracy: 0.0001)
    }

    func testIobChangeReadsInsulinOnBoardWithControlIQOff() {
        let manager = makeManager(controlIQEnabled: false)
        stubInsulinOnBoard(milliunits: 500, type: .MUDALIAR)

        let acknowledged = expectation(description: "qualifying events acknowledged")
        manager.handleQualifyingEvents(events: [.iobChange]) { acknowledged.fulfill() }
        wait(for: [acknowledged], timeout: 1)

        XCTAssertEqual(bluetooth.sent(ControlIQIOBRequest.self).count, 1)
        XCTAssertEqual(manager.state.latestInsulinOnBoard ?? 0, 0.5, accuracy: 0.0001)
    }

    func testSyncReadsInsulinOnBoard() {
        let manager = makeManager(controlIQEnabled: false)
        manager.state.lastSettingsCheckedAt = now
        stubInsulinOnBoard(milliunits: 500, type: .MUDALIAR)

        let synced = expectation(description: "syncPumpData")
        manager.syncPumpData { _ in synced.fulfill() }
        wait(for: [synced], timeout: 5)

        XCTAssertEqual(bluetooth.sent(ControlIQIOBRequest.self).count, 1)
    }

    // MARK: - Against the boluses reported

    func testBolusInsulinBeyondTheReportedBolusesIsFlaggedOnceItPersists() {
        let manager = makeManager(controlIQEnabled: false, reportedBoluses: [1.0])
        stubInsulinOnBoard(milliunits: 3000, type: .MUDALIAR)

        XCTAssertEqual(manager.fetchInsulinOnBoard(), .silent)
        clock.advance(by: UnreportedInsulinOnBoardMonitor.persistence)
        guard case let .unreported(units)? = manager.fetchInsulinOnBoard() else {
            return XCTFail("expected the unreported insulin to be flagged")
        }
        XCTAssertEqual(units, 2.0, accuracy: 0.0001)
    }

    func testBolusInsulinWithinTheReportedBolusesIsNotFlagged() {
        let manager = makeManager(controlIQEnabled: false, reportedBoluses: [1.0, 2.0])
        stubInsulinOnBoard(milliunits: 2500, type: .MUDALIAR)

        manager.fetchInsulinOnBoard()
        clock.advance(by: UnreportedInsulinOnBoardMonitor.persistence)

        XCTAssertEqual(manager.fetchInsulinOnBoard(), .silent)
    }

    func testControlIQInsulinOnBoardIsNotHeldAgainstTheReportedBoluses() {
        let manager = makeManager(controlIQEnabled: true, reportedBoluses: [1.0])
        stubInsulinOnBoard(milliunits: 3000, type: .SWAN_6HR)

        manager.fetchInsulinOnBoard()
        clock.advance(by: UnreportedInsulinOnBoardMonitor.persistence)

        XCTAssertNil(manager.fetchInsulinOnBoard())
        XCTAssertEqual(manager.state.latestInsulinOnBoard ?? 0, 3.0, accuracy: 0.0001)
    }

    func testBolusesOlderThanTheInsulinDurationDoNotCount() {
        let manager = makeManager(controlIQEnabled: false)
        manager.state.bolusReportLedger.record(entry(bolusId: 1, hoursAgo: 6, units: 5))
        manager.state.bolusReportLedger.record(entry(bolusId: 2, hoursAgo: 1, units: 1))
        stubInsulinOnBoard(milliunits: 3000, type: .MUDALIAR)

        manager.fetchInsulinOnBoard()
        clock.advance(by: UnreportedInsulinOnBoardMonitor.persistence)

        XCTAssertEqual(manager.fetchInsulinOnBoard(), .unreported(units: 2))
    }

    func testWithoutAKnownInsulinDurationNothingIsCompared() {
        let manager = makeManager(controlIQEnabled: false)
        manager.state.pumpInsulinDuration = nil
        stubInsulinOnBoard(milliunits: 3000, type: .MUDALIAR)

        XCTAssertNil(manager.fetchInsulinOnBoard())
        XCTAssertEqual(manager.state.latestInsulinOnBoard ?? 0, 3.0, accuracy: 0.0001)
    }

    func testBolusesBeforeTheLedgerStartedLeaveNothingToHoldTheReadingAgainst() {
        let manager = makeManager(controlIQEnabled: false)
        manager.state.bolusReportLedger = BolusReportLedger(trackingSince: now.addingTimeInterval(-.hours(1)))
        stubInsulinOnBoard(milliunits: 3000, type: .MUDALIAR)

        XCTAssertNil(manager.fetchInsulinOnBoard())
    }

    // MARK: - Insulin duration

    private func stubActiveProfile(idpId: Int, insulinDurationMinutes: Int) {
        bluetooth.stub(ProfileStatusRequest.self, with: ProfileStatusResponse(
            numberOfProfiles: 2,
            idpSlot0Id: idpId,
            idpSlot1Id: idpId + 1,
            idpSlot2Id: 0,
            idpSlot3Id: 0,
            idpSlot4Id: 0,
            idpSlot5Id: 0,
            activeSegmentIndex: 0
        ))
        bluetooth.stub(IDPSettingsRequest.self) { request in
            IDPSettingsResponse(
                idpId: (request as? IDPSettingsRequest)?.idpId ?? 0,
                name: "Profile",
                numberOfProfileSegments: 1,
                insulinDuration: insulinDurationMinutes,
                maxBolus: 10000,
                carbEntry: true
            )
        }
    }

    func testInsulinDurationIsReadFromTheActiveProfile() {
        let manager = makeManager(controlIQEnabled: false)
        manager.state.pumpInsulinDuration = nil
        stubActiveProfile(idpId: 3, insulinDurationMinutes: 270)

        manager.fetchInsulinDuration()

        XCTAssertEqual(bluetooth.sent(IDPSettingsRequest.self).map(\.idpId), [3])
        XCTAssertEqual(manager.state.pumpInsulinDuration, PumpInsulinDuration(.minutes(270)))
    }

    func testSyncReadsAnUnknownInsulinDuration() {
        let manager = makeManager(controlIQEnabled: false)
        manager.state.pumpInsulinDuration = nil
        manager.state.lastSettingsCheckedAt = now
        stubActiveProfile(idpId: 1, insulinDurationMinutes: 300)

        let synced = expectation(description: "syncPumpData")
        manager.syncPumpData { _ in synced.fulfill() }
        wait(for: [synced], timeout: 5)

        XCTAssertEqual(manager.state.pumpInsulinDuration?.current, .hours(5))
    }

    func testProfileChangeReadsTheInsulinDurationBeforeTheIOB() {
        XCTAssertEqual(
            QualifyingEventFetch.fetches(
                for: [.profileChange, .iobChange],
                context: QualifyingEventContext(controlIQSupported: true)
            ),
            [.basalStatus, .insulinDuration, .insulinOnBoard]
        )
    }

    func testAShorterDurationKeepsTheLongerWindowUntilItHasPassed() {
        var duration = PumpInsulinDuration(.hours(8))

        duration.update(to: .hours(4), at: now)

        XCTAssertEqual(duration.window(at: now.addingTimeInterval(.hours(7))), .hours(8))
        XCTAssertEqual(duration.window(at: now.addingTimeInterval(.hours(8))), .hours(4))
    }

    func testRereadingTheSameDurationDoesNotExtendTheLongerWindow() {
        var duration = PumpInsulinDuration(.hours(8))
        duration.update(to: .hours(4), at: now)

        duration.update(to: .hours(4), at: now.addingTimeInterval(.hours(6)))
        duration.update(to: .hours(3), at: now.addingTimeInterval(.hours(7)))

        XCTAssertEqual(duration.window(at: now.addingTimeInterval(.hours(7.5))), .hours(8))
        XCTAssertEqual(duration.window(at: now.addingTimeInterval(.hours(8))), .hours(3))
    }

    func testALongerDurationAppliesAtOnce() {
        var duration = PumpInsulinDuration(.hours(8))
        duration.update(to: .hours(4), at: now)

        duration.update(to: .hours(9), at: now.addingTimeInterval(.hours(1)))

        XCTAssertEqual(duration, PumpInsulinDuration(.hours(9)))
    }

    func testInsulinDurationSurvivesARawRoundTrip() {
        var duration = PumpInsulinDuration(.hours(8))
        duration.update(to: .hours(4), at: now)

        XCTAssertEqual(PumpInsulinDuration(rawValue: duration.rawValue), duration)
    }

    // MARK: - Monitor

    func testExcessThatClearsBeforeItPersistsIsNeverFlagged() {
        var monitor = UnreportedInsulinOnBoardMonitor()

        XCTAssertEqual(monitor.observe(bolusOnBoard: 3, reported: 1, at: now), .silent)
        XCTAssertEqual(monitor.observe(bolusOnBoard: 1, reported: 1, at: now.addingTimeInterval(.minutes(10))), .silent)
        XCTAssertEqual(monitor.observe(bolusOnBoard: 3, reported: 1, at: now.addingTimeInterval(.minutes(20))), .silent)
        XCTAssertEqual(
            monitor.observe(bolusOnBoard: 3, reported: 1, at: now.addingTimeInterval(.minutes(40))),
            .silent,
            "the excess restarted at 20 minutes"
        )
    }

    func testFlaggedExcessIsReportedOnceAndThenResolved() {
        var monitor = UnreportedInsulinOnBoardMonitor()
        let later = now.addingTimeInterval(UnreportedInsulinOnBoardMonitor.persistence)

        _ = monitor.observe(bolusOnBoard: 3, reported: 1, at: now)
        XCTAssertEqual(monitor.observe(bolusOnBoard: 3, reported: 1, at: later), .unreported(units: 2))
        XCTAssertEqual(monitor.observe(bolusOnBoard: 3, reported: 1, at: later.addingTimeInterval(300)), .silent)
        XCTAssertEqual(monitor.flagged, 2)
        XCTAssertEqual(monitor.observe(bolusOnBoard: 1, reported: 1, at: later.addingTimeInterval(600)), .resolved)
        XCTAssertNil(monitor.flagged)
        XCTAssertEqual(monitor.observe(bolusOnBoard: 1, reported: 1, at: later.addingTimeInterval(900)), .silent)
    }

    func testExcessWithinRoundingIsNotAnExcess() {
        var monitor = UnreportedInsulinOnBoardMonitor()

        _ = monitor.observe(bolusOnBoard: 1.04, reported: 1, at: now)

        let later = now.addingTimeInterval(UnreportedInsulinOnBoardMonitor.persistence)
        XCTAssertEqual(monitor.observe(bolusOnBoard: 1.04, reported: 1, at: later), .silent)
    }

    // MARK: - Ledger

    func testReportedUnitsSumTheBolusesInTheWindow() {
        var ledger = BolusReportLedger(trackingSince: now.addingTimeInterval(-.hours(12)))
        ledger.record(entry(bolusId: 1, hoursAgo: 10, units: 4))
        ledger.record(entry(bolusId: 2, hoursAgo: 2, units: 1.5))
        ledger.record(entry(bolusId: 3, hoursAgo: 1, units: 0.25))

        XCTAssertEqual(ledger.reportedUnits(since: now.addingTimeInterval(-.hours(8))) ?? 0, 1.75, accuracy: 0.0001)
    }

    func testReportedUnitsAreUnknownBeforeTheLedgerStarted() {
        let ledger = BolusReportLedger(trackingSince: now.addingTimeInterval(-.hours(2)))

        XCTAssertNil(ledger.reportedUnits(since: now.addingTimeInterval(-.hours(8))))
    }

    func testReportedUnitsAreUnknownWhileAnEntryHasNoAmount() {
        var ledger = BolusReportLedger(trackingSince: now.addingTimeInterval(-.hours(12)))
        ledger.record(entry(bolusId: 1, hoursAgo: 2, units: nil))

        XCTAssertNil(ledger.reportedUnits(since: now.addingTimeInterval(-.hours(8))))
    }

    func testFinalizingAnEntryCountsWhatWasDelivered() {
        var ledger = BolusReportLedger(trackingSince: now.addingTimeInterval(-.hours(12)))
        var programmed = entry(bolusId: 1, hoursAgo: 1, units: 2)
        programmed.isFinalized = false
        ledger.record(programmed)

        ledger.markFinalized(raw: programmed.raw, units: 0.8)

        XCTAssertEqual(ledger.reportedUnits(since: now.addingTimeInterval(-.hours(8))) ?? 0, 0.8, accuracy: 0.0001)
    }

    func testEntryAmountSurvivesARawRoundTrip() {
        let original = entry(bolusId: 1, hoursAgo: 1, units: 1.25)

        XCTAssertEqual(BolusReportLedger.Entry(rawValue: original.rawValue), original)
    }
}
