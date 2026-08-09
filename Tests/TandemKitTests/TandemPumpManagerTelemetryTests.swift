import LoopKit
@testable import TandemKit
import XCTest

/// Covers the per-sync status fetches. The battery and Control-IQ reads are API-version dependent,
/// so the request the driver picks has to follow the version the pump reported during pairing —
/// asking a v2.1 pump for a v2 battery response gets no answer at all.
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerTelemetryTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
    }

    override func tearDown() {
        bluetooth = nil
        super.tearDown()
    }

    private func makeManager(apiVersion: KnownApiVersion?) -> TandemPumpManager {
        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState.apiVersion = apiVersion?.value
        return TandemPumpManager(state: state, bluetooth: bluetooth)
    }

    // MARK: - Battery

    func testBatteryTelemetryUsesV1RequestOnLegacyApi() {
        let manager = makeManager(apiVersion: .apiV2_1)
        bluetooth.stub(
            CurrentBatteryV1Request.self,
            with: CurrentBatteryV1Response(currentBatteryAbc: 20, currentBatteryIbc: 80)
        )

        manager.fetchBatteryStatus()

        XCTAssertTrue(bluetooth.didSend(CurrentBatteryV1Request.self))
        XCTAssertFalse(bluetooth.didSend(CurrentBatteryV2Request.self))
        XCTAssertEqual(manager.status.pumpBatteryChargeRemaining ?? 0, 0.8, accuracy: 0.001)
    }

    func testBatteryTelemetryUsesV2RequestWhenApiSupportsIt() {
        let manager = makeManager(apiVersion: .apiV3_4)
        bluetooth.stub(CurrentBatteryV2Request.self, with: CurrentBatteryV2Response(
            currentBatteryAbc: 10,
            currentBatteryIbc: 60,
            chargingStatus: 0,
            unknown1: 0,
            unknown2: 0,
            unknown3: 0,
            unknown4: 0
        ))

        manager.fetchBatteryStatus()

        XCTAssertTrue(bluetooth.didSend(CurrentBatteryV2Request.self))
        XCTAssertFalse(bluetooth.didSend(CurrentBatteryV1Request.self))
        XCTAssertEqual(manager.status.pumpBatteryChargeRemaining ?? 0, 0.6, accuracy: 0.001)
    }

    /// An unknown API version has to fall back to the request every firmware answers.
    func testBatteryTelemetryFallsBackToV1WhenApiVersionUnknown() {
        let manager = makeManager(apiVersion: nil)
        bluetooth.stub(
            CurrentBatteryV1Request.self,
            with: CurrentBatteryV1Response(currentBatteryAbc: 5, currentBatteryIbc: 45)
        )

        manager.fetchBatteryStatus()

        XCTAssertTrue(bluetooth.didSend(CurrentBatteryV1Request.self))
        XCTAssertEqual(manager.status.pumpBatteryChargeRemaining ?? 0, 0.45, accuracy: 0.001)
    }

    /// A failed read must leave the last known charge alone rather than reporting a bogus level.
    func testBatteryTelemetryErrorLeavesChargeUnchanged() {
        let manager = makeManager(apiVersion: .apiV3_4)
        bluetooth.stub(CurrentBatteryV2Request.self) { _ in nil }

        manager.fetchBatteryStatus()

        XCTAssertTrue(bluetooth.didSend(CurrentBatteryV2Request.self))
        XCTAssertNil(manager.status.pumpBatteryChargeRemaining)
    }

    // MARK: - Reservoir

    func testReservoirTelemetryUpdatesStateAndNotifiesDelegate() {
        let manager = makeManager(apiVersion: .apiV3_4)
        let delegate = MockPumpManagerDelegate()
        manager.delegateQueue = DispatchQueue(label: "reservoir-telemetry-test")
        manager.pumpManagerDelegate = delegate

        let readReservoir = expectation(description: "delegate received reservoir value")
        delegate.didReadReservoirExpectation = readReservoir

        bluetooth.stub(InsulinStatusRequest.self, with: InsulinStatusResponse(
            currentInsulinAmount: 150,
            isEstimate: 0,
            insulinLowAmount: 0
        ))

        manager.fetchReservoirStatus()

        wait(for: [readReservoir], timeout: 2.0)

        XCTAssertEqual(manager.reservoirLevel?.unitVolume, 150)
        XCTAssertEqual(delegate.reservoirReadings.last?.units, 150)
        XCTAssertNotNil(manager.state.lastReconciliation)
    }

    func testReservoirTelemetryErrorLeavesLastReadingUnchanged() {
        let manager = makeManager(apiVersion: .apiV3_4)
        bluetooth.stub(InsulinStatusRequest.self) { _ in nil }

        manager.fetchReservoirStatus()

        XCTAssertNil(manager.reservoirLevel)
    }

    // MARK: - Delivery limits read back from the pump

    func testDeliveryLimitsAreReadIntoState() {
        let manager = makeManager(apiVersion: .apiV3_4)
        bluetooth.stub(BasalLimitSettingsRequest.self, with: BasalLimitSettingsResponse(
            basalLimit: 4200,
            basalLimitDefault: 3000
        ))
        bluetooth.stub(GlobalMaxBolusSettingsRequest.self, with: GlobalMaxBolusSettingsResponse(
            maxBolus: 9500,
            maxBolusDefault: 10000
        ))

        manager.fetchDeliveryLimits()

        XCTAssertEqual(manager.state.maxBasalLimitMilliunits, 4200)
        XCTAssertEqual(manager.state.maxBasalLimitDefaultMilliunits, 3000)
        XCTAssertEqual(manager.state.maxBolusLimitMilliunits, 9500)
        XCTAssertEqual(manager.state.maxBolusLimitDefaultMilliunits, 10000)
    }
}
