import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class SetupHistoryLoadTests: XCTestCase {
    private static let pumpSerial: UInt32 = 123_456
    private let serial = HistoryLogSyncIdentifier.PumpSerial(SetupHistoryLoadTests.pumpSerial)!

    private var bluetooth: StubPumpBluetooth!
    private var archive: ReportedHistoryArchive!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    private lazy var nowPumpTimeSec = UInt32(Dates.fromInstantToJan12008EpochSeconds(Date()))

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        archive = ReportedHistoryArchive(defaults: nil)
        // A manager set up just now, before a host has adopted it.
        manager = TandemPumpManager(state: Self.state(), bluetooth: bluetooth, reportedHistoryArchive: archive)
    }

    override func tearDown() {
        manager = nil
        archive = nil
        delegate = nil
        delegateQueue = nil
        bluetooth = nil
        super.tearDown()
    }

    private static func state(pumpSerial: UInt32 = pumpSerial) -> TandemPumpManagerState {
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.historyBackfill] = true
        state.featureFlags[.historyDoseReporting] = true
        state.pumpState.pumpSerial = pumpSerial
        return state
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

    private func pumpSuspension(firstSequenceNum: UInt32, secondsAgo: UInt32, minutes: UInt32) -> [HistoryLog] {
        let suspended = nowPumpTimeSec - secondsAgo
        return [
            PumpingSuspendedHistoryLog(
                pumpTimeSec: suspended,
                sequenceNum: firstSequenceNum,
                preSuspendState: 106,
                insulinAmount: 150,
                reasonId: 0,
                rpaTimeout: 15
            ),
            PumpingResumedHistoryLog(
                pumpTimeSec: suspended + minutes * 60,
                sequenceNum: firstSequenceNum + 1,
                preResumeState: 100,
                insulinAmount: 150
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

    private var reportedTransitions: [NewPumpEvent] {
        delegate.pumpEventBatches.flatMap(\.events).filter { $0.dose?.type == .suspend || $0.dose?.type == .resume }
    }

    /// A manager for the pump, in this app, that told the host what `told` records and was then deleted.
    private func deleteEarlierManager(pumpSerial: UInt32 = pumpSerial, told: (inout TandemPumpManagerState) -> Void) {
        var state = Self.state(pumpSerial: pumpSerial)
        told(&state)
        let earlier = TandemPumpManager(state: state, bluetooth: StubPumpBluetooth(), reportedHistoryArchive: archive)
        let deleted = expectation(description: "earlier manager deleted")
        earlier.prepareForDeactivation { _ in deleted.fulfill() }
        wait(for: [deleted], timeout: 10.0)
    }

    private func appBolus(_ bolusId: Int, pumpSerial: UInt32 = pumpSerial, isFinalized: Bool = true) -> BolusReportLedger.Entry {
        BolusReportLedger.Entry(
            bolusId: bolusId,
            pumpSerial: pumpSerial,
            origin: .commanded,
            raw: Data("app bolus \(bolusId)".utf8),
            eventDate: Date().addingTimeInterval(-3 * 3600),
            automatic: false,
            isFinalized: isFinalized,
            units: 3.6
        )
    }

    private func transition(_ kind: DeliveryTransitionLedger.Kind, secondsAgo: TimeInterval, sequenceNum: UInt32?, isReported: Bool = true) -> DeliveryTransitionLedger.Entry {
        let date = Date().addingTimeInterval(-secondsAgo)
        return DeliveryTransitionLedger.Entry(kind: kind, date: date, earliest: date, latest: date, sequenceNum: sequenceNum, isReported: isReported)
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

    func testWithoutTheLoadASuspendFromBeforeSetupIsNotReported() {
        stubPump(serving: pumpSuspension(firstSequenceNum: 1, secondsAgo: 2 * 3600, minutes: 15))

        runTick()
        adoptByHost()

        XCTAssertTrue(reportedTransitions.isEmpty)
    }

    func testTheLoadReportsASuspendAndResumeFromBeforeSetupAtThePumpsTimes() throws {
        stubPump(serving: pumpBolus(bolusId: 74, units: 1.0, firstSequenceNum: 1, secondsAgo: 3 * 3600)
            + pumpSuspension(firstSequenceNum: 4, secondsAgo: 2 * 3600, minutes: 15))
        runTick()

        XCTAssertNil(load())
        adoptByHost()

        XCTAssertEqual(reportedTransitions.map(\.dose?.type), [.suspend, .resume])
        let suspended = Date().addingTimeInterval(-2 * 3600)
        XCTAssertEqual(try XCTUnwrap(reportedTransitions.first).date.timeIntervalSince(suspended), 0, accuracy: 5)
        XCTAssertEqual(try XCTUnwrap(reportedTransitions.last).date.timeIntervalSince(suspended), 15 * 60, accuracy: 5)
    }

    func testTheLoadReportsNoSuspendOlderThanItsWindow() {
        stubPump(serving: pumpSuspension(firstSequenceNum: 1, secondsAgo: 6 * 3600 + 900, minutes: 10)
            + pumpBolus(bolusId: 75, units: 1.0, firstSequenceNum: 3, secondsAgo: 3600))

        XCTAssertNil(load())
        adoptByHost()

        XCTAssertTrue(reportedTransitions.isEmpty)
    }

    func testTheTransitionLedgerTakesRecordsFromTheLoadOnBeforeTheOnesItTracks() {
        var ledger = DeliveryTransitionLedger()
        ledger.track(pumpSerial: Self.pumpSerial, after: 50)
        let since = Date().addingTimeInterval(-3600)

        ledger.reportHistory(since: since)
        ledger.reportHistory(since: Date())

        XCTAssertEqual(ledger.historySince, since)
        XCTAssertTrue(ledger.isTracked(sequenceNum: 40, date: since.addingTimeInterval(60)))
        XCTAssertFalse(ledger.isTracked(sequenceNum: 40, date: since.addingTimeInterval(-60)))
        XCTAssertTrue(ledger.isTracked(sequenceNum: 51, date: since.addingTimeInterval(-60)))
        XCTAssertEqual(DeliveryTransitionLedger(rawValue: ledger.rawValue), ledger)
    }

    func testAnotherPumpEndsTheTransitionLedgersLoadedHistory() {
        var ledger = DeliveryTransitionLedger()
        ledger.track(pumpSerial: Self.pumpSerial, after: 50)
        ledger.reportHistory(since: Date().addingTimeInterval(-3600))

        ledger.track(pumpSerial: Self.pumpSerial + 1, after: 10)

        XCTAssertNil(ledger.historySince)
    }

    func testTheLoadReportsNoBolusAManagerDeletedFromThisAppReported() {
        deleteEarlierManager { $0.bolusReportLedger.record(self.appBolus(70)) }
        stubPump(serving: pumpBolus(bolusId: 70, units: 3.6, firstSequenceNum: 1, secondsAgo: 3 * 3600)
            + pumpBolus(bolusId: 71, units: 1.0, firstSequenceNum: 4, secondsAgo: 2 * 3600))
        runTick()

        XCTAssertNil(load())
        adoptByHost()

        XCTAssertEqual(reportedBoluses.map(\.raw), [HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 71)])
    }

    func testTheLoadReportsNoSuspendOrResumeAManagerDeletedFromThisAppReported() {
        deleteEarlierManager { state in
            state.deliveryTransitions.track(pumpSerial: Self.pumpSerial, after: 3)
            state.deliveryTransitions.record(self.transition(.suspend, secondsAgo: 2 * 3600, sequenceNum: 4))
            state.deliveryTransitions.record(self.transition(.resume, secondsAgo: 2 * 3600 - 15 * 60, sequenceNum: 5))
        }
        stubPump(serving: pumpBolus(bolusId: 74, units: 1.0, firstSequenceNum: 1, secondsAgo: 3 * 3600)
            + pumpSuspension(firstSequenceNum: 4, secondsAgo: 2 * 3600, minutes: 15))
        runTick()

        XCTAssertNil(load())
        adoptByHost()

        XCTAssertTrue(reportedTransitions.isEmpty)
    }

    func testTheLoadReportsABolusAManagerDeletedFromThisAppReportedForAnotherPump() {
        deleteEarlierManager(pumpSerial: Self.pumpSerial + 1) { $0.bolusReportLedger.record(self.appBolus(70, pumpSerial: Self.pumpSerial + 1)) }
        stubPump(serving: pumpBolus(bolusId: 70, units: 3.6, firstSequenceNum: 1, secondsAgo: 3 * 3600))
        runTick()

        XCTAssertNil(load())
        adoptByHost()

        XCTAssertEqual(reportedBoluses.map(\.raw), [HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 70)])
    }

    func testDeletingThePumpArchivesOnlyWhatTheHostKeeps() throws {
        let finishedTemp = ReportedBasalLedger.Row(kind: .tempBasal, raw: Data("finished".utf8), date: Date().addingTimeInterval(-3600), end: Date().addingTimeInterval(-1800), rate: 0, isMutable: false)
        let runningTemp = ReportedBasalLedger.Row(kind: .tempBasal, raw: Data("running".utf8), date: Date().addingTimeInterval(-600), end: Date().addingTimeInterval(1200), rate: 2, isMutable: true)
        deleteEarlierManager { state in
            state.bolusReportLedger.record(self.appBolus(70))
            state.bolusReportLedger.record(self.appBolus(71, isFinalized: false))
            state.reportedBasal = ReportedBasalLedger(trackingSince: .distantPast, rows: [finishedTemp, runningTemp])
            state.deliveryTransitions.track(pumpSerial: Self.pumpSerial, after: 3)
            state.deliveryTransitions.record(self.transition(.suspend, secondsAgo: 3600, sequenceNum: 4))
            state.deliveryTransitions.record(self.transition(.resume, secondsAgo: 3599.5, sequenceNum: 5, isReported: false))
        }

        let reported = try XCTUnwrap(archive.reported(pumpSerial: Self.pumpSerial, now: Date()))

        XCTAssertEqual(reported.boluses.map(\.bolusId), [70])
        XCTAssertEqual(reported.basalRows, [finishedTemp])
        XCTAssertEqual(reported.transitions.map(\.sequenceNum), [4])
    }

    func testDeletingThePumpAgainKeepsWhatAnEarlierManagerArchived() throws {
        deleteEarlierManager { $0.bolusReportLedger.record(self.appBolus(70)) }
        deleteEarlierManager { $0.bolusReportLedger.record(self.appBolus(72)) }

        let reported = try XCTUnwrap(archive.reported(pumpSerial: Self.pumpSerial, now: Date()))

        XCTAssertEqual(Set(reported.boluses.map(\.bolusId)), [70, 72])
    }

    func testAnArchiveOlderThanItsRetentionIsNotTaken() {
        deleteEarlierManager { $0.bolusReportLedger.record(self.appBolus(70)) }

        XCTAssertNil(archive.reported(pumpSerial: Self.pumpSerial, now: Date().addingTimeInterval(ReportedHistoryArchive.retention + 60)))
    }

    #if !os(Linux)
    func testTheArchiveIsKeptInTheHostAppsDefaults() throws {
        let suite = "SetupHistoryLoadTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let reported = ReportedHistoryArchive.Reported(savedAt: Date(), boluses: [appBolus(70)])

        ReportedHistoryArchive(defaults: defaults).save(reported, pumpSerial: Self.pumpSerial)

        let read = ReportedHistoryArchive(defaults: UserDefaults(suiteName: suite)).reported(pumpSerial: Self.pumpSerial, now: Date())
        XCTAssertEqual(read?.boluses, reported.boluses)
    }
    #endif

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
