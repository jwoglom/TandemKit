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
        XCTAssertEqual(
            reportedTransitions.map(\.raw),
            [4, 5].map { HistoryLogSyncIdentifier.logSequence(pumpSerial: serial, sequenceNum: $0) },
            "the identity any pump manager reports these records under"
        )
    }

    func testTheLoadReportsNoSecondSuspendForAPumpSuspendedWhenSetUp() {
        let suspended = nowPumpTimeSec - 20 * 60
        stubPump(serving: pumpBolus(bolusId: 76, units: 1.0, firstSequenceNum: 1, secondsAgo: 3600) + [
            PumpingSuspendedHistoryLog(pumpTimeSec: suspended, sequenceNum: 4, preSuspendState: 106, insulinAmount: 150, reasonId: 0, rpaTimeout: 15),
        ])
        // Setup's sync: its reading of the pump, then its tick.
        manager.observeDeliveryState(.suspend)
        runTick()

        XCTAssertNil(load())
        adoptByHost()

        XCTAssertEqual(reportedTransitions.map(\.dose?.type), [.suspend])
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

    // MARK: - The pump's delivery at setup

    private func readDelivery() -> SetupDeliveryReading {
        var result: SetupDeliveryReading?
        let read = expectation(description: "delivery read")
        manager.readDeliveryForSetup { reading in
            result = reading
            read.fulfill()
        }
        wait(for: [read], timeout: 10)
        return result ?? SetupDeliveryReading()
    }

    private func stubPumpBeforeSetup(pumpClockAhead: TimeInterval, lastBolusSecondsAgo: UInt32?, basal: CurrentBasalStatusResponse) {
        bluetooth.stub(ApiVersionRequest.self, with: ApiVersionResponse(majorVersion: 3, minorVersion: 4))
        bluetooth.stub(PumpVersionBRequest.self, with: PumpVersionBResponse(
            softwareName: "t:slim X2",
            configurationBitsA: 0,
            configurationBitsB: 0,
            serialNumber: 654_321,
            modelNumber: PumpModel.TSLIM_X2.rawValue,
            pumpRevision: "A",
            pcbPartNumberA: 0,
            pcbSerialNumberA: 0,
            pcbRevisionNumberA: "A"
        ))
        bluetooth.stub(TimeSinceResetRequest.self, with: TimeSinceResetResponse(
            currentTime: nowPumpTimeSec + UInt32(pumpClockAhead),
            pumpTimeSinceReset: 1000
        ))
        bluetooth.stub(ControlIQInfoV2Request.self, with: ControlIQInfoV2Response(
            closedLoopEnabled: true,
            weight: 150,
            weightUnit: ControlIQInfoAbstractResponse.WeightUnit.pounds.rawValue,
            totalDailyInsulin: 40,
            currentUserModeType: 0,
            byte6: 0,
            byte7: 0,
            byte8: 0,
            controlStateType: 0,
            exerciseChoice: 0,
            exerciseDuration: 0,
            exerciseTimeRemaining: 0
        ))
        bluetooth.stub(ControlIQIOBRequest.self, with: ControlIQIOBResponse(
            mudaliarIOB: 1200,
            timeRemainingSeconds: 600,
            mudaliarTotalIOB: 1500,
            swan6hrIOB: 2300,
            iobType: 1
        ))
        bluetooth.stub(LastBolusStatusV2Request.self, with: LastBolusStatusV2Response(
            status: 0,
            bolusId: 77,
            timestamp: lastBolusSecondsAgo.map { nowPumpTimeSec + UInt32(pumpClockAhead) - $0 } ?? 0,
            deliveredVolume: 4000,
            bolusStatusId: LastBolusStatusAbstractResponseBolusStatus.complete.rawValue,
            bolusSourceId: 0,
            bolusTypeBitmask: 1,
            extendedBolusDuration: 0,
            requestedVolume: 4000
        ))
        bluetooth.stub(CurrentBasalStatusRequest.self, with: basal)
    }

    func testThePumpIsReadAsItsLastUserLeftItBeforeSetupWritesAnything() throws {
        stubPumpBeforeSetup(
            pumpClockAhead: 120,
            lastBolusSecondsAgo: 80 * 60,
            basal: CurrentBasalStatusResponse(profileBasalRate: 800, currentBasalRate: 1100, basalModifiedBitmask: 0)
        )

        let reading = readDelivery()

        XCTAssertEqual(try XCTUnwrap(reading.insulinOnBoard), 2.3, accuracy: 0.0005, "the IOB the pump shows")
        guard case let .delivered(at) = reading.lastBolus else {
            return XCTFail("last bolus \(reading.lastBolus)")
        }
        XCTAssertEqual(Date().timeIntervalSince(at), 80 * 60, accuracy: 5, "on the phone's clock")
        XCTAssertEqual(try XCTUnwrap(reading.currentBasalRate), 1.1, accuracy: 0.0005)
        XCTAssertFalse(reading.isSuspended)
        XCTAssertEqual(manager.state.pumpState.pumpSerial, 654_321, "the serial the load keys its reports on")
        XCTAssertEqual(
            Set(bluetooth.sentMessages.map { String(describing: type(of: $0)) }),
            [
                "ApiVersionRequest", "PumpVersionBRequest", "TimeSinceResetRequest", "ControlIQInfoV2Request",
                "ControlIQIOBRequest", "LastBolusStatusV2Request", "CurrentBasalStatusRequest"
            ],
            "reads alone"
        )
    }

    func testASuspendedPumpReadsSuspendedWithNoBasalRate() {
        stubPumpBeforeSetup(
            pumpClockAhead: 0,
            lastBolusSecondsAgo: 60,
            basal: CurrentBasalStatusResponse(profileBasalRate: 800, currentBasalRate: 0, basalModifiedBitmask: 0x01)
        )

        let reading = readDelivery()

        XCTAssertTrue(reading.isSuspended)
        XCTAssertNil(reading.currentBasalRate)
    }

    func testAPumpThatNeverBolusedReadsNoLastBolus() {
        stubPumpBeforeSetup(
            pumpClockAhead: 0,
            lastBolusSecondsAgo: nil,
            basal: CurrentBasalStatusResponse(profileBasalRate: 800, currentBasalRate: 800, basalModifiedBitmask: 0)
        )

        XCTAssertEqual(readDelivery().lastBolus, SetupDeliveryReading.LastBolus.none)
    }

    func testAPumpThatDoesNotAnswerReadsNothing() {
        XCTAssertEqual(readDelivery(), SetupDeliveryReading())
    }

    func testTheLoadIsOfferedUnlessTheLastBolusIsOverSixHoursAgo() {
        let hours: (Double) -> SetupDeliveryReading = {
            SetupDeliveryReading(lastBolus: .delivered(at: Date().addingTimeInterval(-$0 * 3600)))
        }

        XCTAssertTrue(manager.offersHistoryLoad(after: hours(5.9)))
        XCTAssertFalse(manager.offersHistoryLoad(after: hours(6.1)))
        XCTAssertFalse(manager.offersHistoryLoad(after: SetupDeliveryReading(lastBolus: .none)))
        XCTAssertTrue(manager.offersHistoryLoad(after: SetupDeliveryReading()), "a last bolus that could not be read")

        manager.state.featureFlags[.historyDoseReporting] = false

        XCTAssertFalse(manager.offersHistoryLoad(after: hours(1)))
    }
}
