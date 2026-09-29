@testable import TandemKit
import XCTest

/// Covers the qualifying-event callbacks: which status fetches an event batch triggers, and that
/// the batch is deduplicated before anything reaches the wire. The fetches are derived from the
/// PumpX2-aligned suggested handlers, restricted to the requests this driver actually consumes.
@available(macOS 13.0, iOS 14.0, *) final class QualifyingEventHandlingTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!

    /// The context `makeManager`'s pump reports, for the fetch-table tests that bypass the manager.
    private let legacyContext = QualifyingEventContext(apiVersion: KnownApiVersion.apiV2_1.value)

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
    }

    override func tearDown() {
        bluetooth = nil
        super.tearDown()
    }

    private func makeManager(historyBackfill: Bool) -> TandemPumpManager {
        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState.apiVersion = KnownApiVersion.apiV2_1.value
        state.pumpState.pumpSerial = 123_456
        state.featureFlags[.historyBackfill] = historyBackfill
        return TandemPumpManager(state: state, bluetooth: bluetooth)
    }

    /// Runs the handler and returns the request types that reached the wire, in order.
    @discardableResult
    private func handle(_ events: Set<QualifyingEvent>, historyBackfill: Bool = false) -> [String] {
        let manager = makeManager(historyBackfill: historyBackfill)
        let acknowledged = expectation(description: "qualifying events acknowledged")
        manager.handleQualifyingEvents(events: events) { acknowledged.fulfill() }
        wait(for: [acknowledged], timeout: 1)
        return bluetooth.sentMessages.map { String(describing: type(of: $0)) }
    }

    // MARK: - Event to fetch mapping

    func testEventsWithoutAFetchAreAcknowledgedWithoutConnecting() {
        let sent = handle([.iobChange, .heartbeat, .snoozeStatus, .pumpReset])

        XCTAssertEqual(sent, [])
        XCTAssertEqual(bluetooth.ensureConnectedCount, 0)
    }

    func testBolusChangeFetchesBolusStatus() {
        XCTAssertEqual(handle([.bolusChange]), ["CurrentBolusStatusRequest"])
    }

    /// A bolus changing on the pump is exactly when a bolus delivered from the pump's own UI is
    /// written to history, and the pump is already awake. Reading history now puts it in the
    /// store within seconds instead of leaving it out of IOB until the next sync.
    func testBolusChangeAlsoReadsHistory() {
        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState.apiVersion = KnownApiVersion.apiV2_1.value
        state.pumpState.pumpSerial = 123_456
        state.featureFlags[.historyBackfill] = true
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth)
        bluetooth.stub(HistoryLogStatusRequest.self, with: HistoryLogStatusResponse(
            numEntries: 10,
            firstSequenceNum: 1,
            lastSequenceNum: 10
        ))
        bluetooth.stub(HistoryLogRequest.self, with: HistoryLogResponse(status: 0, streamId: 7))

        let acknowledged = expectation(description: "qualifying events acknowledged")
        manager.handleQualifyingEvents(events: [.bolusChange]) { acknowledged.fulfill() }
        wait(for: [acknowledged], timeout: 1)

        // The backfill runs on its own queue, so it lands after the acknowledgement.
        let read = expectation(description: "history status read")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { read.fulfill() }
        wait(for: [read], timeout: 5)

        XCTAssertFalse(
            bluetooth.sent(HistoryLogStatusRequest.self).isEmpty,
            "A bolus change should kick a history read, not wait for the next sync"
        )
    }

    func testBolusChangeDoesNotReadHistoryWhileTheBackfillFlagIsOff() {
        XCTAssertEqual(handle([.bolusChange], historyBackfill: false), ["CurrentBolusStatusRequest"])
    }

    func testBasalChangeFetchesBasalStatus() {
        XCTAssertEqual(handle([.basalChange]), ["CurrentBasalStatusRequest"])
    }

    /// PumpX2 answers an extended-bolus change with the extended-bolus and last-bolus status,
    /// neither of which the driver consumes standalone — the last-bolus read only happens inside
    /// the bolus fetch, keyed to a specific bolus id. So nothing is fetched until extended
    /// boluses are modelled.
    func testExtendedBolusChangeFetchesNothingYet() {
        XCTAssertEqual(handle([.extendedBolusChange]), [])
    }

    func testBatteryFetchesBatteryStatus() {
        XCTAssertEqual(handle([.battery]), ["CurrentBatteryV1Request"])
    }

    func testRemainingInsulinFetchesReservoirStatus() {
        XCTAssertEqual(handle([.remainingInsulin]), ["InsulinStatusRequest"])
    }

    func testTimeChangeFetchesTimeSinceReset() {
        XCTAssertEqual(handle([.timeChange]), ["TimeSinceResetRequest"])
    }

    func testControlIQInfoFetchesControlIQStatus() {
        XCTAssertEqual(handle([.controlIQInfo]), ["ControlIQInfoV1Request"])
    }

    func testHomeScreenChangeFetchesBasalAndControlIQStatus() {
        XCTAssertEqual(Set(handle([.homeScreenChange])), [
            "CurrentBasalStatusRequest",
            "ControlIQInfoV1Request"
        ])
    }

    /// Suspend and resume refresh the basal status alongside the reservoir. PumpX2 only asks for
    /// insulin status here, but the basal read is what emits the suspend/resume dose to LoopKit,
    /// and the pump does not always pair these events with a basalChange.
    func testSuspendAndResumeFetchReservoirAndBasalStatus() {
        for event in [QualifyingEvent.pumpSuspend, .pumpResume] {
            bluetooth = StubPumpBluetooth()
            XCTAssertEqual(Set(handle([event])), [
                "InsulinStatusRequest",
                "CurrentBasalStatusRequest"
            ], "\(event)")
        }
    }

    func testGlobalPumpSettingsFetchesLimitsAndSettings() {
        // The limits fetch abandons the sequence if the first read goes unanswered, so the basal
        // limit has to be stubbed for the bolus limit request to follow it.
        bluetooth.stub(
            BasalLimitSettingsRequest.self,
            with: BasalLimitSettingsResponse(basalLimit: 3000, basalLimitDefault: 3000)
        )

        XCTAssertEqual(Set(handle([.globalPumpSettings])), [
            "BasalLimitSettingsRequest",
            "GlobalMaxBolusSettingsRequest",
            "PumpGlobalsRequest"
        ])
    }

    /// Every notification category is served by the one bundle reload.
    func testNotificationEventsFetchTheNotificationBundle() {
        for event in [QualifyingEvent.alert, .alarm, .reminder, .malfunction, .cgmAlert] {
            bluetooth = StubPumpBluetooth()
            XCTAssertTrue(handle([event]).contains("AlertStatusRequest"), "\(event)")
        }
    }

    // MARK: - Deduplication

    /// Regression guard: co-firing notification events used to be handled one at a time, so a
    /// batch reloaded the whole bundle once per event.
    func testCoFiringNotificationEventsReloadTheBundleOnce() {
        let sent = handle([.alert, .alarm, .reminder, .cgmAlert])

        XCTAssertEqual(sent.filter { $0 == "AlertStatusRequest" }.count, 1, "got \(sent)")
        XCTAssertEqual(sent.filter { $0 == "AlarmStatusRequest" }.count, 1, "got \(sent)")
    }

    func testOverlappingEventsFetchBasalStatusOnce() {
        let sent = handle([.homeScreenChange, .basalChange])

        XCTAssertEqual(sent.filter { $0 == "CurrentBasalStatusRequest" }.count, 1, "got \(sent)")
    }

    /// A batch mixing handled and unhandled events still runs the handled ones.
    func testUnhandledEventsDoNotSuppressTheRest() {
        let sent = handle([.iobChange, .battery, .bg])

        XCTAssertEqual(sent, ["CurrentBatteryV1Request"])
    }

    // MARK: - Fetch table

    func testFetchesForBatchAreDeduplicatedAndOrdered() {
        let fetches = QualifyingEventFetch.fetches(
            for: [.alert, .alarm, .battery, .basalChange],
            context: legacyContext
        )

        XCTAssertEqual(fetches, [.notifications, .basalStatus, .batteryStatus])
    }

    func testFetchesForBatchIsEmptyWhenNoEventIsActionable() {
        XCTAssertEqual(
            QualifyingEventFetch.fetches(for: [.iobChange, .bg, .cgmChange], context: legacyContext),
            []
        )
    }

    /// The alarm bundle still reloads on a pump too old for the AAM-bits request, because the
    /// alarm status request that survives the API filter maps to the same fetch.
    func testNotificationFetchSurvivesApiVersionFiltering() {
        XCTAssertEqual(
            QualifyingEventFetch.fetches(for: [.alarm], context: legacyContext),
            [.notifications]
        )
        XCTAssertEqual(
            QualifyingEventFetch.fetches(
                for: [.alarm],
                context: QualifyingEventContext(apiVersion: KnownApiVersion.mobiApiV3_5.value)
            ),
            [.notifications]
        )
    }

    /// The battery fetch has to be selected off either battery request version.
    func testBatteryFetchIsSelectedForBothRequestVersions() {
        XCTAssertEqual(
            QualifyingEventFetch.fetches(for: [.battery], context: legacyContext),
            [.batteryStatus]
        )
        XCTAssertEqual(
            QualifyingEventFetch.fetches(
                for: [.battery],
                context: QualifyingEventContext(apiVersion: KnownApiVersion.apiV3_4.value)
            ),
            [.batteryStatus]
        )
    }

    /// A failure to connect must still acknowledge the event, or the pump keeps re-sending it.
    func testEventsAreAcknowledgedWhenTheConnectionFails() {
        bluetooth.connectError = PumpCommError.pumpNotConnected

        let sent = handle([.battery])

        XCTAssertEqual(sent, [])
        XCTAssertEqual(bluetooth.ensureConnectedCount, 1)
    }
}
