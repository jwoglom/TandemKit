import LoopKit
@testable import TandemKit
import XCTest

/// What the history backfill diagnostics screen records and shows: the resolution log and the
/// session monitor the driver feeds, and the report laid out from them.
@available(macOS 13.0, iOS 14.0, *) final class HistoryBackfillDiagnosticsTests: XCTestCase {
    private static let pumpSerial: UInt32 = 123_456
    private static let appBolusId = 5120
    private let serial = HistoryLogSyncIdentifier.PumpSerial(HistoryBackfillDiagnosticsTests.pumpSerial)!

    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        // Recent, so fixtures stay inside the store's retention.
        clock = ManualClock(Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded()))
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.featureFlags[.historyDoseReporting] = true
        state.pumpState.pumpSerial = Self.pumpSerial
        state.bolusReportLedger = BolusReportLedger(trackingSince: .distantPast)
        makeManager(state: state)
    }

    override func tearDown() {
        delegateQueue = nil
        delegate = nil
        manager = nil
        clock = nil
        bluetooth = nil
        super.tearDown()
    }

    private func makeManager(state: TandemPumpManagerState) {
        manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "history-backfill-diagnostics-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
    }

    // MARK: - Fixtures

    private var now: Date { clock.now }

    private func pumpTime(secondsAgo: TimeInterval) -> UInt32 {
        UInt32(Dates.fromInstantToJan12008EpochSeconds(now.addingTimeInterval(-secondsAgo)))
    }

    private func pumpDate(_ log: HistoryLog) -> Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(log.pumpTimeSec))
    }

    private func bolusStart(
        bolusId: Int,
        units: Float,
        firstSequenceNum: UInt32,
        secondsAgo: TimeInterval,
        source: BolusDeliveryHistoryLog.BolusSource = .quickBolus
    ) -> [HistoryLog] {
        let activated = pumpTime(secondsAgo: secondsAgo)
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
                bolusSource: source.rawValue,
                remoteId: 0,
                requestedNow: Int(units * 1000),
                requestedLater: 0,
                correction: 0,
                extendedDurationRequested: 0,
                deliveredTotal: 0
            )
        ]
    }

    private func completion(bolusId: Int, delivered: Float, requested: Float, sequenceNum: UInt32, secondsAgo: TimeInterval) -> HistoryLog {
        BolusCompletedHistoryLog(
            pumpTimeSec: pumpTime(secondsAgo: secondsAgo),
            sequenceNum: sequenceNum,
            completionStatusId: 3,
            bolusId: bolusId,
            iob: delivered,
            insulinDelivered: delivered,
            insulinRequested: requested
        )
    }

    private func report(_ logs: [HistoryLog], floor: Date? = nil) {
        manager.storeHistoryLogs(logs, now: now)
        let sequences = logs.map(\.sequenceNum)
        manager.reportHistoryBoluses(
            in: sequences.min()! ... sequences.max()!,
            pumpSerial: serial,
            floor: floor ?? now.addingTimeInterval(-BolusReportLedger.retention),
            now: now
        )
        delegateQueue.sync {}
    }

    private var resolutions: [BolusResolutionLog.Event] {
        manager.state.bolusResolutionLog.events
    }

    private var lastPass: HistoryBackfillMonitor.ReportingPass? {
        manager.historyBackfillMonitor.snapshot.lastReportingPass
    }

    private func commandedEntry(bolusId: Int, isFinalized: Bool, secondsAgo: TimeInterval = 600) -> BolusReportLedger.Entry {
        BolusReportLedger.Entry(
            bolusId: bolusId,
            pumpSerial: Self.pumpSerial,
            origin: .commanded,
            raw: Data("bolus 1.0 live".utf8),
            eventDate: now.addingTimeInterval(-secondsAgo),
            automatic: false,
            isFinalized: isFinalized
        )
    }

    private func heldDose(bolusId: Int = appBolusId, units: Double = 2.0) -> UnfinalizedDose {
        UnfinalizedDose(
            units: units,
            duration: 60,
            activationType: .manualNoRecommendation,
            insulinType: nil,
            bolusId: bolusId,
            now: now.addingTimeInterval(-300)
        )
    }

    private func storeCompletion(bolusId: Int = appBolusId, delivered: Float, secondsAgo: TimeInterval = 60) {
        manager.storeHistoryLogs(
            [completion(bolusId: bolusId, delivered: delivered, requested: 2.0, sequenceNum: 900, secondsAgo: secondsAgo)],
            now: now
        )
    }

    // MARK: - History dose reporting

    func testAPumpBolusIsRecordedWithWhenItWasFoundAndWhatStartedIt() throws {
        let start = bolusStart(bolusId: 42, units: 2.0, firstSequenceNum: 100, secondsAgo: 300)

        report(start + [completion(bolusId: 42, delivered: 2.0, requested: 2.0, sequenceNum: 102, secondsAgo: 240)])

        let event = try XCTUnwrap(resolutions.first)
        XCTAssertEqual(resolutions.count, 1)
        XCTAssertEqual(event.kind, .pumpBolusFound)
        XCTAssertEqual(event.bolusId, 42)
        XCTAssertEqual(event.date, now)
        XCTAssertEqual(event.doseDate, pumpDate(start[0]))
        XCTAssertEqual(event.programmedUnits, 2.0)
        XCTAssertEqual(event.deliveredUnits, 2.0)
        XCTAssertFalse(event.isMutable)
        XCTAssertEqual(event.bolusSource, BolusDeliveryHistoryLog.BolusSource.quickBolus.rawValue)
        XCTAssertEqual(lastPass?.boluses, 1)
        XCTAssertEqual(lastPass?.reported, 1)
    }

    func testAnInFlightPumpBolusIsRecordedFoundThenFinalized() throws {
        let start = bolusStart(bolusId: 43, units: 0.5, firstSequenceNum: 200, secondsAgo: 60)
        report(start)
        XCTAssertEqual(resolutions.map(\.kind), [.pumpBolusFound])
        XCTAssertEqual(resolutions.first?.isMutable, true)
        XCTAssertNil(resolutions.first?.deliveredUnits)

        clock.advance(by: 30)
        report(start)
        XCTAssertEqual(lastPass?.awaitingCompletion, 1, "#452: reported once, then nothing until it completes")
        XCTAssertEqual(resolutions.count, 1)

        clock.advance(by: 30)
        report(start + [completion(bolusId: 43, delivered: 0.45, requested: 0.5, sequenceNum: 202, secondsAgo: 5)])

        let finalized = try XCTUnwrap(resolutions.last)
        XCTAssertEqual(resolutions.map(\.kind), [.pumpBolusFound, .pumpBolusFinalized])
        XCTAssertEqual(finalized.date, now)
        XCTAssertEqual(finalized.deliveredUnits, 0.45)
        XCTAssertFalse(finalized.isMutable)
    }

    func testAnAppBolusFinalizedFromHistoryIsRecorded() throws {
        let entry = commandedEntry(bolusId: 52, isFinalized: false)
        manager.state.bolusReportLedger.record(entry)
        manager.state.pendingBolusFinalization = heldDose(bolusId: 52, units: 1.0)

        report(bolusStart(bolusId: 52, units: 1.0, firstSequenceNum: 600, secondsAgo: 600, source: .bluetoothRemoteBolus)
            + [completion(bolusId: 52, delivered: 0.65, requested: 1.0, sequenceNum: 602, secondsAgo: 570)])

        let event = try XCTUnwrap(resolutions.first)
        XCTAssertEqual(event.kind, .appBolusFinalizedFromHistory)
        XCTAssertEqual(event.doseDate, entry.eventDate, "Dated as the app first reported it")
        XCTAssertEqual(event.deliveredUnits, 0.65)
        XCTAssertEqual(event.programmedUnits, 1.0)
    }

    func testThePassCountsWhatItLeftAlone() {
        manager.state.bolusReportLedger.record(commandedEntry(bolusId: 50, isFinalized: true))
        manager.state.bolusReportLedger.record(commandedEntry(bolusId: 51, isFinalized: false))
        let live = heldDose(bolusId: 51, units: 1.0)
        manager.state.bolusDose = live
        manager.bolusProgressReport = TandemDoseProgressReporter(
            pumpManager: manager,
            dose: live.toDoseEntry(isMutable: true),
            activationType: .manualNoRecommendation
        )

        report(
            bolusStart(bolusId: 50, units: 1.0, firstSequenceNum: 400, secondsAgo: 900)
                + [completion(bolusId: 50, delivered: 1.0, requested: 1.0, sequenceNum: 402, secondsAgo: 880)]
                + bolusStart(bolusId: 51, units: 1.0, firstSequenceNum: 403, secondsAgo: 600)
                + [completion(bolusId: 51, delivered: 1.0, requested: 1.0, sequenceNum: 405, secondsAgo: 560)]
                + bolusStart(bolusId: 60, units: 1.0, firstSequenceNum: 406, secondsAgo: 3600),
            floor: now.addingTimeInterval(-1800)
        )

        let pass = lastPass
        XCTAssertEqual(pass?.boluses, 3)
        XCTAssertEqual(pass?.alreadyFinalized, 1)
        XCTAssertEqual(pass?.leftToLivePath, 1)
        XCTAssertEqual(pass?.belowFloor, 1)
        XCTAssertEqual(pass?.reported, 0)
        XCTAssertEqual(pass?.result, .completed)
        XCTAssertTrue(resolutions.isEmpty)
    }

    func testAnExtendedBolusIsRecordedOnceHoweverOftenItIsRead() {
        let bolex = BolexActivatedHistoryLog(
            pumpTimeSec: pumpTime(secondsAgo: 120),
            sequenceNum: 700,
            bolusId: 61,
            iob: 0,
            bolexSize: 1.5
        )

        report([bolex])
        report([bolex])

        XCTAssertEqual(resolutions.map(\.kind), [.extendedBolusNotReported])
        XCTAssertEqual(resolutions.first?.programmedUnits, 1.5)
        XCTAssertEqual(manager.state.bolusResolutionLog.count(.extendedBolusNotReported), 1)
        XCTAssertEqual(lastPass?.extendedBoluses, 1)
    }

    func testAPassThatCannotConnectIsRecordedAsDeferred() {
        bluetooth.connectError = PumpCommError.pumpNotConnected

        manager.reportHistoryDoses(
            after: HistoryBackfillCoordinator.TickOutcome(
                bookkeeping: HistoryBackfillState(pumpSerial: Self.pumpSerial, watermark: 10),
                rangesRead: [1 ... 10],
                sessionCovered: 1 ... 10,
                isDeepBackfillComplete: true,
                emitFloor: .distantPast
            ),
            now: now
        )

        guard case .deferred? = lastPass?.result else {
            return XCTFail("Expected a deferred pass, got \(String(describing: lastPass?.result))")
        }
        XCTAssertEqual(lastPass?.covered, 1 ... 10)
    }

    // MARK: - Held boluses

    private func holdAppBolus() {
        manager.holdForFinalization(heldDose(), fallbackUnits: 2.0)
    }

    func testHoldingABolusIsRecordedWithItsFallback() throws {
        holdAppBolus()

        let event = try XCTUnwrap(resolutions.last)
        XCTAssertEqual(event.kind, .bolusHeld)
        XCTAssertEqual(event.bolusId, Self.appBolusId)
        XCTAssertEqual(event.fallbackUnits, 2.0)
        XCTAssertTrue(event.isMutable)
    }

    func testAHeldBolusFinalizedWithItsFallbackIsRecorded() throws {
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        holdAppBolus()

        let afterTheWindow = now.addingTimeInterval(TandemPumpManager.bolusFinalizationWindow + 60)
        manager.finalizePendingBolus(now: afterTheWindow)

        let event = try XCTUnwrap(resolutions.last)
        XCTAssertEqual(event.kind, .heldBolusFinalizedWithFallback)
        XCTAssertEqual(event.date, afterTheWindow)
        XCTAssertEqual(event.deliveredUnits, 2.0)
        XCTAssertEqual(event.fallbackUnits, 2.0)
        XCTAssertEqual(manager.state.bolusResolutionLog.count(.heldBolusFinalizedWithFallback), 1)
    }

    func testAHeldBolusFinalizedFromHistoryRecordsTheFallbackItReplaced() throws {
        bluetooth.stub(LastBolusStatusRequest.self) { _ in nil }
        holdAppBolus()
        storeCompletion(delivered: 1.234)

        manager.finalizePendingBolus()

        let event = try XCTUnwrap(resolutions.last)
        XCTAssertEqual(event.kind, .heldBolusFinalizedFromHistory)
        XCTAssertEqual(event.deliveredUnits, 1.234)
        XCTAssertEqual(event.fallbackUnits, 2.0)
    }

    func testAHeldBolusThePumpConfirmsLaterIsRecorded() throws {
        holdAppBolus()
        bluetooth.stub(LastBolusStatusRequest.self, with: LastBolusStatusResponse(
            status: 0,
            bolusId: Self.appBolusId,
            timestamp: 0,
            deliveredVolume: 1500,
            bolusStatusId: 0,
            bolusSourceId: 0,
            bolusTypeBitmask: 0,
            extendedBolusDuration: 0
        ))

        manager.finalizePendingBolus()

        let event = try XCTUnwrap(resolutions.last)
        XCTAssertEqual(event.kind, .heldBolusConfirmedByPump)
        XCTAssertEqual(event.deliveredUnits, 1.5)
    }

    func testHoldingASecondBolusRecordsTheFirstAsSuperseded() throws {
        holdAppBolus()

        manager.holdForFinalization(heldDose(bolusId: Self.appBolusId + 1, units: 1.0), fallbackUnits: 1.0)

        XCTAssertEqual(resolutions.map(\.kind), [.bolusHeld, .heldBolusFinalizedWithFallback, .bolusHeld])
        let superseded = try XCTUnwrap(resolutions.first { $0.kind == .heldBolusFinalizedWithFallback })
        XCTAssertEqual(superseded.bolusId, Self.appBolusId)
        XCTAssertEqual(superseded.note, "Superseded by bolus \(Self.appBolusId + 1)")
    }

    // MARK: - Backfill ticks

    private func runTick() {
        let ticked = expectation(description: "backfill tick completes")
        manager.historyBackfillCoordinator.runTick(now: now) { _ in ticked.fulfill() }
        wait(for: [ticked], timeout: 90.0)
        delegateQueue.sync {}
    }

    /// Serves `logs` the way the pump does: status from their range, entries streamed back on
    /// `historyLogStream` after the request is acknowledged.
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
            let count = UInt32(max(request.numberOfLogs, 1))
            let bottom = top >= count ? top - count + 1 : 0
            let streamed = stride(from: top, through: bottom, by: -1).compactMap { bySequence[$0] }
            guard !streamed.isEmpty else { return }
            self.manager.historyLogStream.send(HistoryLogStreamResponse(
                numberOfHistoryLogs: streamed.count,
                streamId: 7,
                historyLogStreamBytes: streamed.map(\.cargo)
            ))
        }
    }

    func testATickSkippedByTheFlagIsRecorded() {
        manager.state.featureFlags[.historyBackfill] = false

        runTick()

        let monitor = manager.historyBackfillMonitor.snapshot
        XCTAssertEqual(monitor.recentTicks.first?.skipped, .flagOff)
        XCTAssertEqual(monitor.totals.ticksSkipped[.flagOff], 1)
        XCTAssertNil(monitor.lastCompletedTick)
    }

    func testATickWithoutAPumpSerialIsRecorded() {
        manager.state.pumpState.pumpSerial = nil

        runTick()

        XCTAssertEqual(manager.historyBackfillMonitor.snapshot.recentTicks.first?.skipped, .noPumpSerial)
    }

    func testATickThatStepsAsideForAnotherReaderIsRecorded() {
        XCTAssertTrue(manager.historyFetchGate.tryAcquire())
        defer { manager.historyFetchGate.release() }

        runTick()

        XCTAssertEqual(manager.historyBackfillMonitor.snapshot.recentTicks.first?.skipped, .readerBusy)
    }

    func testATickThePumpGaveNoStatusIsRecorded() {
        bluetooth.stub(HistoryLogStatusRequest.self) { _ in nil }

        runTick()

        let monitor = manager.historyBackfillMonitor.snapshot
        XCTAssertEqual(monitor.recentTicks.first?.skipped, .noStatus)
        XCTAssertNil(monitor.runningTickStartedAt)
    }

    func testACompletedTickRecordsWhatItReadAndTheReportThatFollowed() throws {
        let logs = bolusStart(bolusId: 80, units: 2.0, firstSequenceNum: 1, secondsAgo: 300)
            + [completion(bolusId: 80, delivered: 2.0, requested: 2.0, sequenceNum: 3, secondsAgo: 240)]
        stubPump(serving: logs)

        runTick()

        let monitor = manager.historyBackfillMonitor.snapshot
        let outcome = try XCTUnwrap(monitor.lastCompletedTick?.outcome)
        XCTAssertEqual(outcome.rangesRead, [1 ... 3])
        XCTAssertNil(outcome.watermarkBefore)
        XCTAssertEqual(outcome.bookkeeping.watermark, 3)
        XCTAssertEqual(outcome.pumpStatus?.lastSequenceNum, 3)
        XCTAssertEqual(monitor.lastStatus?.numEntries, 3)
        XCTAssertEqual(monitor.sessionCovered, 1 ... 3)
        XCTAssertEqual(monitor.lastWatermarkAdvance?.to, 3)
        XCTAssertNil(monitor.lastWatermarkAdvance?.from)
        XCTAssertEqual(monitor.totals.ticksCompleted, 1)
        XCTAssertEqual(monitor.totals.entriesRead, 3)
        XCTAssertNil(monitor.runningTickStartedAt)
        XCTAssertEqual(monitor.lastReportingPass?.reported, 1)
        XCTAssertEqual(resolutions.map(\.kind), [.pumpBolusFound])
    }

    // MARK: - Snapshot and report

    private func reportNow() -> HistoryBackfillReport {
        HistoryBackfillReport(manager.historyBackfillSnapshot(), timeZone: TimeZone(identifier: "UTC")!)
    }

    private func row(_ label: String, in section: String, of report: HistoryBackfillReport) -> HistoryBackfillReport.Row? {
        report.sections.first { $0.title == section }?.rows.first { $0.label == label }
    }

    private func finding(containing text: String, in report: HistoryBackfillReport) -> HistoryBackfillReport.Finding? {
        report.findings.first { $0.message.contains(text) }
    }

    private func recordStatus(first: UInt32 = 1, last: UInt32) {
        manager.historyBackfillMonitor.statusRead(HistoryLogStatusReading(
            HistoryLogStatusResponse(numEntries: last - first + 1, firstSequenceNum: first, lastSequenceNum: last),
            readAt: now
        ))
    }

    func testTheWatermarkIsComparedWithThePumpsNewestEntry() throws {
        manager.state.historyBackfill = HistoryBackfillState(pumpSerial: Self.pumpSerial, watermark: 100, firstSeenFloor: now.addingTimeInterval(-.hours(7)))
        manager.storeHistoryLogs(bolusStart(bolusId: 1, units: 1.0, firstSequenceNum: 99, secondsAgo: 30), now: now)
        recordStatus(last: 104)

        let report = reportNow()

        let watermark = try XCTUnwrap(row("Last read (watermark)", in: "Read Position", of: report))
        XCTAssertEqual(watermark.value, "100")
        XCTAssertTrue(watermark.detail?.contains("pump time") == true, "The entry at the watermark is in the store")
        let newest = try XCTUnwrap(row("Pump's newest entry", in: "Read Position", of: report))
        XCTAssertEqual(newest.value, "104")
        XCTAssertTrue(newest.detail?.contains("4 not read yet") == true)
        XCTAssertEqual(row("Read position saved for", in: "Read Position", of: report)?.value, "This pump")
        XCTAssertEqual(finding(containing: "not read yet", in: report)?.tone, .normal)
    }

    func testAWatermarkPastThePumpsNewestEntryIsCritical() {
        manager.state.historyBackfill = HistoryBackfillState(pumpSerial: Self.pumpSerial, watermark: 5000)
        recordStatus(last: 104)

        let report = reportNow()

        XCTAssertEqual(finding(containing: "the pump's log restarted", in: report)?.tone, .critical)
        XCTAssertEqual(row("Pump's newest entry", in: "Read Position", of: report)?.tone, .critical)
    }

    func testFindingsListTheMostSevereFirst() {
        manager.state.featureFlags[.historyDoseReporting] = false
        manager.holdForFinalization(heldDose(), fallbackUnits: 2.0)
        manager.state.historyBackfill = HistoryBackfillState(pumpSerial: Self.pumpSerial, watermark: 5000)
        recordStatus(last: 104)

        let tones = reportNow().findings.map(\.tone)

        XCTAssertEqual(tones.first, .critical)
        XCTAssertEqual(tones, tones.sorted { $0.rank < $1.rank })
        XCTAssertTrue(tones.contains(.warning))
        XCTAssertTrue(tones.contains(.normal))
    }

    func testBookkeepingForAnotherPumpIsFlagged() {
        manager.state.historyBackfill = HistoryBackfillState(pumpSerial: Self.pumpSerial + 1, watermark: 10)

        let report = reportNow()

        XCTAssertEqual(row("Read position saved for", in: "Read Position", of: report)?.value, "Another pump")
        XCTAssertNotNil(finding(containing: "belongs to another pump", in: report))
    }

    func testAHeldBolusIsShownWithItsFallbackAndWindow() throws {
        manager.holdForFinalization(heldDose(), fallbackUnits: 2.0)

        let report = reportNow()

        let held = try XCTUnwrap(row("Held for finalization", in: "Live Doses", of: report))
        XCTAssertEqual(held.value, "#\(Self.appBolusId) · 2.00 U")
        XCTAssertTrue(held.detail?.contains("fallback 2.00 U") == true)
        XCTAssertTrue(held.detail?.contains("window ends") == true)
        XCTAssertEqual(finding(containing: "is held", in: report)?.tone, .warning)
    }

    func testAnUnfinalizedAppBolusNothingTracksIsFlagged() throws {
        manager.state.bolusReportLedger.record(commandedEntry(bolusId: 77, isFinalized: false, secondsAgo: 3600))

        let report = reportNow()

        XCTAssertEqual(finding(containing: "App bolus #77", in: report)?.tone, .warning)
        let ledgerRow = try XCTUnwrap(row("#77 · app", in: "Bolus Report Ledger", of: report))
        XCTAssertEqual(ledgerRow.value, "Unfinalized")
        XCTAssertEqual(ledgerRow.tone, .warning)
    }

    func testAnAppBolusTheLivePathIsDeliveringIsNotFlagged() {
        manager.state.bolusReportLedger.record(commandedEntry(bolusId: 78, isFinalized: false, secondsAgo: 3600))
        manager.state.bolusDose = heldDose(bolusId: 78)

        let report = reportNow()

        XCTAssertNil(finding(containing: "App bolus #78", in: report))
        XCTAssertEqual(row("#78 · app", in: "Bolus Report Ledger", of: report)?.value, "Delivering")
    }

    func testAPumpBolusLongInFlightIsFlagged() {
        manager.state.bolusReportLedger.record(BolusReportLedger.Entry(
            bolusId: 79,
            pumpSerial: Self.pumpSerial,
            origin: .history,
            raw: HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 79),
            eventDate: now.addingTimeInterval(-.minutes(45)),
            automatic: false,
            isFinalized: false
        ))

        let report = reportNow()

        XCTAssertEqual(finding(containing: "#452", in: report)?.tone, .warning)
        XCTAssertEqual(row("#79 · pump", in: "Bolus Report Ledger", of: report)?.value, "In flight")
    }

    func testTheLedgerSaysWhenAPumpBolusWasFoundAndWhatStartedIt() throws {
        report(bolusStart(bolusId: 81, units: 0.3, firstSequenceNum: 10, secondsAgo: 300, source: .controlIQAutoBolus)
            + [completion(bolusId: 81, delivered: 0.3, requested: 0.3, sequenceNum: 12, secondsAgo: 280)])

        let ledgerRow = try XCTUnwrap(row("#81 · pump", in: "Bolus Report Ledger", of: reportNow()))
        XCTAssertEqual(ledgerRow.value, "Finalized")
        XCTAssertTrue(ledgerRow.detail?.contains("found") == true)
        XCTAssertTrue(ledgerRow.detail?.contains("5m later") == true)
        XCTAssertTrue(ledgerRow.detail?.contains("Control-IQ") == true)
    }

    func testOnlyTheLatestFinalizedAppBolusesAreListed() throws {
        let listed = HistoryBackfillReport.listedFinalizedAppBoluses
        for index in 0 ..< listed + 3 {
            manager.state.bolusReportLedger.record(commandedEntry(bolusId: 1000 + index, isFinalized: true, secondsAgo: TimeInterval(3600 - index)))
        }
        manager.state.bolusReportLedger.record(commandedEntry(bolusId: 999, isFinalized: false, secondsAgo: 7200))

        let rows = try XCTUnwrap(reportNow().sections.first { $0.title == "Bolus Report Ledger" }).rows

        XCTAssertEqual(rows.first?.value, String(listed + 4), "The summary still counts every entry")
        XCTAssertEqual(rows.filter { $0.value == "Finalized" }.count, listed)
        XCTAssertNil(rows.first { $0.label == "#1000 · app" }, "The oldest finalized ones are left out")
        XCTAssertNotNil(rows.first { $0.label == "#\(1000 + listed + 2) · app" })
        XCTAssertNotNil(rows.first { $0.label == "#999 · app" }, "An unfinalized one is listed however old")
    }

    func testABluetoothBolusTheAppHasNoRecordOfIsFlagged() {
        report(bolusStart(bolusId: 82, units: 1.0, firstSequenceNum: 20, secondsAgo: 300, source: .bluetoothRemoteBolus)
            + [completion(bolusId: 82, delivered: 1.0, requested: 1.0, sequenceNum: 22, secondsAgo: 250)])

        XCTAssertEqual(finding(containing: "#327", in: reportNow())?.tone, .warning)
    }

    func testFallbackFinalizationsAndExtendedBolusesAreFlagged() {
        manager.state.bolusResolutionLog.record(BolusResolutionLog.Event(date: now, kind: .heldBolusFinalizedWithFallback, bolusId: 1))
        manager.state.bolusResolutionLog.record(BolusResolutionLog.Event(date: now, kind: .extendedBolusNotReported, bolusId: 2))

        let report = reportNow()

        XCTAssertEqual(finding(containing: "#464", in: report)?.tone, .warning)
        XCTAssertEqual(finding(containing: "#424", in: report)?.tone, .warning)
        XCTAssertEqual(row(BolusResolutionLog.Kind.heldBolusFinalizedWithFallback.title, in: "Dose Resolutions", of: report)?.value, "1")
    }

    func testBackfillOffIsFlaggedAndSaysReportingHasNoEffect() {
        manager.state.featureFlags[.historyBackfill] = false

        let report = reportNow()

        XCTAssertEqual(finding(containing: "History Backfill is off", in: report)?.tone, .warning)
        XCTAssertNotNil(finding(containing: "has no effect", in: report))
    }

    func testAReportingFloorSetByTheLedgerIsNamed() {
        manager.state.bolusReportLedger = BolusReportLedger(trackingSince: now.addingTimeInterval(-.hours(2)))

        let report = reportNow()

        XCTAssertNotNil(finding(containing: "when the ledger started tracking", in: report))
        XCTAssertEqual(row("Reporting floor", in: "Floors", of: report)?.detail, "set by when the ledger started tracking")
    }

    private func finishTick(
        covering covered: ClosedRange<UInt32>,
        finishedSecondsAgo: TimeInterval = 0,
        isDeepBackfillComplete: Bool = true,
        rangesFailed: [ClosedRange<UInt32>] = [],
        hitDeepSliceCap: Bool = false
    ) {
        let finishedAt = now.addingTimeInterval(-finishedSecondsAgo)
        manager.historyBackfillMonitor.tickFinished(
            startedAt: finishedAt.addingTimeInterval(-5),
            finishedAt: finishedAt,
            outcome: HistoryBackfillCoordinator.TickOutcome(
                bookkeeping: HistoryBackfillState(pumpSerial: Self.pumpSerial, watermark: covered.upperBound),
                rangesRead: [covered],
                sessionCovered: covered,
                isDeepBackfillComplete: isDeepBackfillComplete,
                emitFloor: .distantPast,
                rangesFailed: rangesFailed,
                hitDeepSliceCap: hitDeepSliceCap
            )
        )
    }

    func testATroubledTickIsFlagged() {
        finishTick(covering: 1 ... 300, isDeepBackfillComplete: false, rangesFailed: [301 ... 310], hitDeepSliceCap: true)

        let report = reportNow()

        XCTAssertEqual(finding(containing: "failed on the last tick: 301–310", in: report)?.tone, .warning)
        XCTAssertEqual(finding(containing: "hit its cap", in: report)?.tone, .warning)
        XCTAssertEqual(finding(containing: "has not yet reached", in: report)?.tone, .normal)
        XCTAssertEqual(row("Walk backward", in: "Session Store", of: report)?.value, "In progress")
    }

    func testGapsInWhatThisSessionReadAreFlagged() {
        manager.storeHistoryLogs(bolusStart(bolusId: 1, units: 1.0, firstSequenceNum: 10, secondsAgo: 60), now: now)
        manager.storeHistoryLogs(bolusStart(bolusId: 2, units: 1.0, firstSequenceNum: 15, secondsAgo: 30), now: now)
        finishTick(covering: 10 ... 16)

        let report = reportNow()

        XCTAssertEqual(finding(containing: "1 gap(s), 3 entries", in: report)?.tone, .warning)
        XCTAssertEqual(row("Gaps", in: "Session Store", of: report)?.detail, "12–14 (3)")
    }

    func testAStaleTickIsFlagged() {
        finishTick(covering: 1 ... 10, finishedSecondsAgo: .minutes(20))

        XCTAssertEqual(finding(containing: "The last completed backfill tick was 20m ago", in: reportNow())?.tone, .warning)
    }

    func testADeferredReportingPassIsFlagged() {
        var pass = HistoryBackfillMonitor.ReportingPass(date: now, covered: 1 ... 10, floor: now)
        pass.result = .deferred("Pump not connected")
        manager.historyBackfillMonitor.reportingPassFinished(pass)

        let report = reportNow()

        XCTAssertEqual(finding(containing: "deferred to the next tick: Pump not connected", in: report)?.tone, .warning)
        XCTAssertEqual(row("Last pass", in: "History Dose Reporting", of: report)?.tone, .warning)
    }

    func testAPumpClockOffFromThePhonesIsNoted() {
        manager.state.lastPumpTimeCheckDate = now
        manager.state.currentPumpTime = now.addingTimeInterval(-.minutes(3))

        let report = reportNow()

        XCTAssertNotNil(finding(containing: "3m behind the phone's", in: report))
        XCTAssertEqual(row("Pump clock offset", in: "Live Doses", of: report)?.value, "-3m")
    }

    func testAMissingSerialAndABusyStreamAreNoted() {
        manager.state.pumpState.pumpSerial = nil
        XCTAssertTrue(manager.historyFetchGate.tryAcquire())
        defer { manager.historyFetchGate.release() }

        let report = reportNow()

        XCTAssertEqual(finding(containing: "pump serial isn't known", in: report)?.tone, .warning)
        XCTAssertNotNil(finding(containing: "holds the pump's history stream", in: report))
    }

    func testTheCopiedReportLeavesOutThePumpSerialAndIdentities() {
        manager.state.historyBackfill = HistoryBackfillState(pumpSerial: Self.pumpSerial, watermark: 100)
        report(bolusStart(bolusId: 83, units: 1.0, firstSequenceNum: 30, secondsAgo: 300)
            + [completion(bolusId: 83, delivered: 1.0, requested: 1.0, sequenceNum: 32, secondsAgo: 250)])
        let identity = HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 83).hexadecimalString

        let text = reportNow().text

        XCTAssertFalse(text.contains(String(Self.pumpSerial)))
        XCTAssertFalse(text.lowercased().contains(identity.lowercased()))
        XCTAssertTrue(text.contains("Read Position"))
        XCTAssertTrue(text.contains("#83 · pump"))
    }

    func testResettingClearsTheResolutionsAndSessionTotals() {
        manager.holdForFinalization(heldDose(), fallbackUnits: 2.0)
        manager.state.featureFlags[.historyBackfill] = false
        runTick()

        clock.advance(by: 60)
        manager.resetHistoryDiagnostics()

        XCTAssertEqual(manager.state.bolusResolutionLog, BolusResolutionLog(countingSince: now))
        XCTAssertEqual(manager.historyBackfillMonitor.snapshot.totals, HistoryBackfillMonitor.Totals())
        XCTAssertNotNil(manager.state.pendingBolusFinalization, "Diagnostics only; the held bolus is untouched")
    }

    // MARK: - Formatting

    func testUnitsKeepTwoDecimalsAndAThirdOnlyWhenThePumpReportedOne() {
        XCTAssertEqual(HistoryBackfillReport.Format.units(2.0), "2.00 U")
        XCTAssertEqual(HistoryBackfillReport.Format.units(0.35), "0.35 U")
        XCTAssertEqual(HistoryBackfillReport.Format.units(0.401), "0.401 U")
    }

    func testDurationsUseTheLargestUnitsThatFit() {
        XCTAssertEqual(HistoryBackfillReport.Format.duration(0.2), "<1s")
        XCTAssertEqual(HistoryBackfillReport.Format.duration(59), "59s")
        XCTAssertEqual(HistoryBackfillReport.Format.duration(61), "1m 1s")
        XCTAssertEqual(HistoryBackfillReport.Format.duration(3600), "1h")
        XCTAssertEqual(HistoryBackfillReport.Format.duration(.hours(25)), "1d 1h")
        XCTAssertEqual(HistoryBackfillReport.Format.signedDuration(-5), "-5s")
    }
}
