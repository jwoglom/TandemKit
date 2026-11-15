import LoopKit
@testable import TandemKit
import XCTest

/// The settings screen warns that Control-IQ is running open-loop when no CGM is connected to the
/// pump. That warning is only correct if the driver actually knows the pump's CGM session state, so
/// these tests pin where that state comes from: every sync, not just the moment the user switches
/// the algorithm to Control-IQ from inside the app.
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerCGMStatusTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
    }

    override func tearDown() {
        bluetooth = nil
        super.tearDown()
    }

    private func makeManager(
        apiVersion: KnownApiVersion? = .mobiApiV3_5,
        pumpModel: PumpModel? = .MOBI
    ) -> TandemPumpManager {
        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState.apiVersion = apiVersion?.value
        state.pumpState.pumpModel = pumpModel
        return TandemPumpManager(state: state, bluetooth: bluetooth)
    }

    private func makeResponse(sessionState: CGMStatusV2Response.SessionState) -> CGMStatusV2Response {
        CGMStatusV2Response(
            sessionStateId: sessionState.rawValue,
            lastCalibrationTimestamp: 0,
            sensorStartedTimestamp: 100,
            transmitterBatteryStatusId: CGMStatusV2Response.TransmitterBatteryStatus.unavailable.rawValue,
            sessionDurationSeconds: 3600,
            sessionTimeRemainingSeconds: 3600,
            cgmSensorTypeId: CGMStatusV2Response.CGMSensorType.dexcomG7.rawValue,
            gracePeriod: false
        )
    }

    func testFetchStoresActiveSensorSession() {
        let manager = makeManager()
        bluetooth.stub(CGMStatusV2Request.self, with: makeResponse(sessionState: .active))

        manager.fetchCGMSessionStatus()

        XCTAssertTrue(bluetooth.didSend(CGMStatusV2Request.self))
        XCTAssertEqual(manager.state.cgmSessionState, .active)
        XCTAssertEqual(manager.state.isCGMSensorSessionConfigured, true)
        XCTAssertNotNil(manager.state.lastCGMStatusUpdate)
    }

    /// A sensor that is still warming up will be feeding Control-IQ shortly, so it must not be
    /// reported as a disconnected CGM.
    func testWarmingUpSensorCountsAsConfigured() {
        let manager = makeManager()
        bluetooth.stub(CGMStatusV2Request.self, with: makeResponse(sessionState: .startPending))

        manager.fetchCGMSessionStatus()

        XCTAssertEqual(manager.state.isCGMSensorSessionConfigured, true)
    }

    func testStoppedSessionIsReportedAsNotConfigured() {
        let manager = makeManager()
        bluetooth.stub(CGMStatusV2Request.self, with: makeResponse(sessionState: .stopped))

        manager.fetchCGMSessionStatus()

        XCTAssertEqual(manager.state.isCGMSensorSessionConfigured, false)
    }

    /// A dropped or unanswered read must leave the last known session state alone. Downgrading it
    /// to "no sensor" is what produced the spurious warning this test guards against.
    func testFailedFetchLeavesPreviousSessionStateIntact() {
        let manager = makeManager()
        bluetooth.stub(CGMStatusV2Request.self, with: makeResponse(sessionState: .active))
        manager.fetchCGMSessionStatus()

        bluetooth.stub(CGMStatusV2Request.self) { _ in nil }
        manager.fetchCGMSessionStatus()

        XCTAssertEqual(manager.state.cgmSessionState, .active)
    }

    /// Until the pump has been read, the session state is unknown — which is distinct from knowing
    /// there is no sensor, and must not raise the warning.
    func testSessionStateStartsUnknown() {
        let manager = makeManager()

        XCTAssertNil(manager.state.cgmSessionState)
        XCTAssertNil(manager.state.isCGMSensorSessionConfigured)
    }

    /// `CGMStatusV2Request` is Mobi-only; sending it to a t:slim X2 would just burn a round-trip
    /// timeout on every sync.
    func testSkipsRequestOnNonMobiPump() {
        let manager = makeManager(apiVersion: .apiV2_1, pumpModel: .TSLIM_X2)
        bluetooth.stub(CGMStatusV2Request.self, with: makeResponse(sessionState: .active))

        manager.fetchCGMSessionStatus()

        XCTAssertFalse(bluetooth.didSend(CGMStatusV2Request.self))
        XCTAssertNil(manager.state.cgmSessionState)
    }

    func testSkipsRequestWhenApiVersionPredatesIt() {
        let manager = makeManager(apiVersion: .apiV3_4, pumpModel: .MOBI)
        bluetooth.stub(CGMStatusV2Request.self, with: makeResponse(sessionState: .active))

        manager.fetchCGMSessionStatus()

        XCTAssertFalse(bluetooth.didSend(CGMStatusV2Request.self))
    }

    /// A pump whose model and API version have not been read yet cannot be assumed to answer. The
    /// first sync reads them (`fetchPumpInformation`) before the CGM status, so nothing is lost by
    /// waiting until the pump has identified itself.
    func testSkipsRequestWhenPumpIsNotYetIdentified() {
        let manager = makeManager(apiVersion: nil, pumpModel: nil)
        bluetooth.stub(CGMStatusV2Request.self, with: makeResponse(sessionState: .active))

        manager.fetchCGMSessionStatus()

        XCTAssertFalse(bluetooth.didSend(CGMStatusV2Request.self))
        XCTAssertNil(manager.state.cgmSessionState)
    }

    /// The regression this suite exists for: the CGM session state has to be refreshed by the
    /// ordinary sync, so a pump whose Control-IQ was enabled before the app launched still knows a
    /// sensor is connected.
    func testSyncPumpDataRefreshesCGMSessionState() {
        let manager = makeManager()
        bluetooth.stub(CGMStatusV2Request.self, with: makeResponse(sessionState: .active))

        let synced = expectation(description: "syncPumpData")
        manager.syncPumpData { _ in synced.fulfill() }
        wait(for: [synced], timeout: 5)

        XCTAssertTrue(bluetooth.didSend(CGMStatusV2Request.self))
        XCTAssertEqual(manager.state.cgmSessionState, .active)
    }

    /// The one-shot read used by the CGM settings screen and the Control-IQ switch feeds the same
    /// state, so the settings screen updates from it too.
    func testGetCGMStatusUpdatesState() {
        let manager = makeManager()
        bluetooth.stub(CGMStatusV2Request.self, with: makeResponse(sessionState: .stopped))

        let fetched = expectation(description: "getCGMStatus")
        manager.getCGMStatus { response in
            XCTAssertEqual(response?.sessionState, .stopped)
            fetched.fulfill()
        }
        wait(for: [fetched], timeout: 5)

        XCTAssertEqual(manager.state.cgmSessionState, .stopped)
    }

    private func enableBlocker(
        of manager: TandemPumpManager,
        weightLbs: Int? = 154,
        totalDailyInsulin: Int? = 42
    ) -> ControlIQEnableBlocker? {
        var blocker: ControlIQEnableBlocker?
        let checked = expectation(description: "checkControlIQCanBeEnabled")
        manager.checkControlIQCanBeEnabled(weightLbs: weightLbs, totalDailyInsulin: totalDailyInsulin) {
            blocker = $0
            checked.fulfill()
        }
        wait(for: [checked], timeout: 5)
        return blocker
    }

    func testControlIQCanBeEnabledWithValuesAndASensorSession() {
        let manager = makeManager()
        bluetooth.stub(CGMStatusV2Request.self, with: makeResponse(sessionState: .active))

        XCTAssertNil(enableBlocker(of: manager))
    }

    func testAWarmingUpSensorDoesNotBlockEnablingControlIQ() {
        let manager = makeManager()
        bluetooth.stub(CGMStatusV2Request.self, with: makeResponse(sessionState: .startPending))

        XCTAssertNil(enableBlocker(of: manager))
    }

    func testControlIQCannotBeEnabledWithoutASensorSession() {
        let manager = makeManager()
        bluetooth.stub(CGMStatusV2Request.self, with: makeResponse(sessionState: .stopped))

        XCTAssertEqual(enableBlocker(of: manager), .cgmRequired)
    }

    func testControlIQCannotBeEnabledWhenThePumpDoesNotAnswerTheCGMRead() {
        let manager = makeManager()
        bluetooth.stub(CGMStatusV2Request.self) { _ in nil }

        XCTAssertEqual(enableBlocker(of: manager), .cgmRequired)
    }

    func testControlIQCannotBeEnabledWithoutAWeightOrTotalDailyInsulin() {
        let manager = makeManager()
        bluetooth.stub(CGMStatusV2Request.self, with: makeResponse(sessionState: .active))

        XCTAssertEqual(enableBlocker(of: manager, weightLbs: nil), .valuesRequired)
        XCTAssertEqual(enableBlocker(of: manager, totalDailyInsulin: nil), .valuesRequired)
        XCTAssertFalse(bluetooth.didSend(CGMStatusV2Request.self), "the pump is not read for a switch that cannot be made")
    }

    /// `rawState` is what survives an app restart, so the session state has to round-trip through
    /// it rather than resetting to unknown on every launch.
    func testSessionStateSurvivesRawValueRoundTrip() {
        var state = TandemPumpManagerState(rawValue: [:])
        state.cgmSessionState = .active
        state.lastCGMStatusUpdate = Date(timeIntervalSinceReferenceDate: 1_234_567)

        let restored = TandemPumpManagerState(rawValue: state.rawValue)

        XCTAssertEqual(restored.cgmSessionState, .active)
        XCTAssertEqual(restored.lastCGMStatusUpdate, state.lastCGMStatusUpdate)
    }
}
