@testable import TandemKit
import XCTest

/// With `quickBolusButtonSupport` off — the default — every sync has to confirm the pump's quick
/// bolus button is disabled and turn it off if the pump says otherwise, so a button pressed on the
/// pump cannot deliver insulin the app knows nothing about.
@available(macOS 13.0, iOS 14.0, *) final class QuickBolusEnforcementTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
    }

    override func tearDown() {
        bluetooth = nil
        super.tearDown()
    }

    private func makeManager(quickBolusButtonSupport: Bool = false) -> TandemPumpManager {
        var state = TandemPumpManagerState(rawValue: [:])
        state.featureFlags[.quickBolusButtonSupport] = quickBolusButtonSupport
        return TandemPumpManager(state: state, bluetooth: bluetooth)
    }

    private func makeGlobals(quickBolusEnabled: Bool) -> PumpGlobalsResponse {
        PumpGlobalsResponse(
            quickBolusEnabledRaw: quickBolusEnabled ? 1 : 0,
            quickBolusIncrementUnits: 500,
            quickBolusIncrementCarbs: 2000,
            quickBolusEntryType: 0,
            quickBolusStatus: 0,
            buttonAnnun: 0,
            quickBolusAnnun: 0,
            generalAnnun: 0,
            reminderAnnun: 0,
            alertAnnun: 0,
            alarmAnnun: 0,
            fillTubingAnnun: 0
        )
    }

    private func sync(_ manager: TandemPumpManager) {
        let synced = expectation(description: "syncPumpData")
        manager.syncPumpData { _ in synced.fulfill() }
        wait(for: [synced], timeout: 5)
    }

    func testQuickBolusButtonSupportIsOffByDefault() {
        XCTAssertFalse(TandemFeatureFlags.default.quickBolusButtonSupport)
        XCTAssertFalse(TandemPumpManagerState(rawValue: [:]).featureFlags.quickBolusButtonSupport)
    }

    func testSyncDisablesTheQuickBolusButtonWhenTheFlagIsOff() throws {
        let manager = makeManager()
        bluetooth.stub(PumpGlobalsRequest.self, with: makeGlobals(quickBolusEnabled: true))
        bluetooth.stub(SetQuickBolusSettingsRequest.self, with: SetQuickBolusSettingsResponse(status: 0))

        sync(manager)

        let request = try XCTUnwrap(bluetooth.sent(SetQuickBolusSettingsRequest.self).first)
        XCTAssertFalse(request.enabled)
        XCTAssertFalse(try XCTUnwrap(manager.state.quickBolusEnabled))
    }

    func testSyncLeavesTheQuickBolusButtonAloneWhenTheFlagIsOn() {
        let manager = makeManager(quickBolusButtonSupport: true)
        bluetooth.stub(PumpGlobalsRequest.self, with: makeGlobals(quickBolusEnabled: true))

        sync(manager)

        XCTAssertFalse(bluetooth.didSend(SetQuickBolusSettingsRequest.self))
        XCTAssertEqual(manager.state.quickBolusEnabled, true)
    }

    func testSyncSendsNothingWhenTheQuickBolusButtonIsAlreadyOff() {
        let manager = makeManager()
        bluetooth.stub(PumpGlobalsRequest.self, with: makeGlobals(quickBolusEnabled: false))

        sync(manager)

        XCTAssertFalse(bluetooth.didSend(SetQuickBolusSettingsRequest.self))
    }

    /// The globals are otherwise only re-read once a day, which would leave a button enabled on the
    /// pump unnoticed until the next daily settings check.
    func testGlobalsAreReReadOnEverySyncWhileTheFlagIsOff() {
        let manager = makeManager()
        manager.state.lastSettingsCheckedAt = Date.now
        bluetooth.stub(PumpGlobalsRequest.self, with: makeGlobals(quickBolusEnabled: true))
        bluetooth.stub(SetQuickBolusSettingsRequest.self, with: SetQuickBolusSettingsResponse(status: 0))

        sync(manager)

        XCTAssertEqual(bluetooth.sent(PumpGlobalsRequest.self).count, 1)
        XCTAssertTrue(bluetooth.didSend(SetQuickBolusSettingsRequest.self))
    }

    func testGlobalsAreNotReReadEverySyncWhileTheFlagIsOn() {
        let manager = makeManager(quickBolusButtonSupport: true)
        manager.state.lastSettingsCheckedAt = Date.now
        bluetooth.stub(PumpGlobalsRequest.self, with: makeGlobals(quickBolusEnabled: true))

        sync(manager)

        XCTAssertTrue(bluetooth.sent(PumpGlobalsRequest.self).isEmpty)
    }

    func testStateKeepsReportingEnabledWhenThePumpRejectsTheDisable() {
        let manager = makeManager()
        bluetooth.stub(PumpGlobalsRequest.self, with: makeGlobals(quickBolusEnabled: true))
        bluetooth.stub(SetQuickBolusSettingsRequest.self, with: SetQuickBolusSettingsResponse(status: 1))

        sync(manager)

        XCTAssertTrue(bluetooth.didSend(SetQuickBolusSettingsRequest.self))
        XCTAssertEqual(manager.state.quickBolusEnabled, true)
    }
}
