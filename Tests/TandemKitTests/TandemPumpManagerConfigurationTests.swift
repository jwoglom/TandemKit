import HealthKit
import LoopKit
@testable import TandemKit
import XCTest

/// Covers the two settings the host app pushes down to the pump: the basal rate schedule (via IDP
/// profile segments) and the delivery limits. Both walk a multi-step request sequence, so the
/// assertions are on the exact messages the driver produced.
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerConfigurationTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!

    private let idpId = 10
    private let profileIndex = 0

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
    }

    override func tearDown() {
        manager = nil
        bluetooth = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Stubs the IDP discovery walk: one profile in slot 0 with `segments` already on the pump.
    private func stubActiveProfile(segments: [IDPSegmentResponse]) {
        bluetooth.stub(ProfileStatusRequest.self, with: ProfileStatusResponse(
            numberOfProfiles: 1,
            idpSlot0Id: idpId,
            idpSlot1Id: 0,
            idpSlot2Id: 0,
            idpSlot3Id: 0,
            idpSlot4Id: 0,
            idpSlot5Id: 0,
            activeSegmentIndex: 0
        ))

        bluetooth.stub(IDPSettingsRequest.self, with: IDPSettingsResponse(
            idpId: idpId,
            name: "Test",
            numberOfProfileSegments: segments.count,
            insulinDuration: 180,
            maxBolus: 0,
            carbEntry: true
        ))

        bluetooth.stub(IDPSegmentRequest.self) { request in
            guard let request = request as? IDPSegmentRequest else { return nil }
            return segments.first { $0.segmentIndex == request.segmentIndex }
        }

        bluetooth.stub(SetIDPSegmentRequest.self, with: SetIDPSegmentResponse(status: 0, unknown: 0))
    }

    private func segment(
        index: Int,
        startTime: Int,
        basalMilliunits: Int
    ) -> IDPSegmentResponse {
        IDPSegmentResponse(
            idpId: idpId,
            segmentIndex: index,
            profileStartTime: startTime,
            profileBasalRate: basalMilliunits,
            profileCarbRatio: 10000,
            profileTargetBG: 110,
            profileISF: 50,
            idpStatusId: 31
        )
    }

    private func syncBasal(_ items: [RepeatingScheduleValue<Double>]) -> Result<BasalRateSchedule, Error> {
        var result: Result<BasalRateSchedule, Error>!
        let expectation = expectation(description: "syncBasalRateSchedule")
        manager.syncBasalRateSchedule(items: items) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        return result
    }

    // MARK: - Basal schedule

    func testSyncBasalRateScheduleOnlyModifiesChangedSegments() throws {
        // Pump already has 00:00 -> 0.8 U/hr and 01:00 -> 1.2 U/hr; only the second one changes.
        stubActiveProfile(segments: [
            segment(index: 0, startTime: 0, basalMilliunits: 800),
            segment(index: 1, startTime: 60, basalMilliunits: 1200)
        ])

        let result = syncBasal([
            RepeatingScheduleValue(startTime: 0, value: 0.8),
            RepeatingScheduleValue(startTime: 3600, value: 1.5)
        ])

        guard case .success = result else {
            return XCTFail("Expected success, got \(result)")
        }

        let writes = bluetooth.sent(SetIDPSegmentRequest.self)
        XCTAssertEqual(writes.count, 1, "Only the changed segment should be written")
        XCTAssertEqual(writes.first?.segmentIndex, 1)
        XCTAssertEqual(writes.first?.profileBasalRate, 1500)
        XCTAssertEqual(writes.first?.profileStartTime, 60)
    }

    func testSyncBasalRateScheduleCreatesSegmentsForNewEntries() throws {
        // Pump has one segment; the new schedule has three, so two must be created.
        stubActiveProfile(segments: [segment(index: 0, startTime: 0, basalMilliunits: 800)])

        let result = syncBasal([
            RepeatingScheduleValue(startTime: 0, value: 0.8),
            RepeatingScheduleValue(startTime: 3600, value: 1.0),
            RepeatingScheduleValue(startTime: 7200, value: 1.2)
        ])

        guard case .success = result else {
            return XCTFail("Expected success, got \(result)")
        }

        let writes = bluetooth.sent(SetIDPSegmentRequest.self)
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes.map(\.profileStartTime), [60, 120])
        XCTAssertEqual(writes.map(\.profileBasalRate), [1000, 1200])
    }

    func testSyncBasalRateScheduleStoresScheduleAndMaxEntry() throws {
        stubActiveProfile(segments: [segment(index: 0, startTime: 0, basalMilliunits: 800)])

        let items = [
            RepeatingScheduleValue(startTime: 0, value: 0.8),
            RepeatingScheduleValue(startTime: 3600, value: 1.4)
        ]
        _ = syncBasal(items)

        XCTAssertEqual(manager.state.basalRateSchedule.items.map(\.value), [0.8, 1.4])
        XCTAssertEqual(manager.state.settings.maxBasalScheduleEntry, 1.4)
    }

    func testSyncBasalRateScheduleRejectsEmptySchedule() {
        let result = syncBasal([])

        guard case .failure = result else {
            return XCTFail("Expected an empty schedule to be rejected")
        }
        XCTAssertTrue(bluetooth.sentMessages.isEmpty, "Nothing should be sent for an empty schedule")
    }

    /// A rejected segment write has to fail the whole sync — silently reporting success would leave
    /// the host app believing a basal schedule is in effect that the pump never accepted.
    func testSyncBasalRateScheduleFailsWhenPumpRejectsSegment() {
        stubActiveProfile(segments: [
            segment(index: 0, startTime: 0, basalMilliunits: 800),
            segment(index: 1, startTime: 60, basalMilliunits: 1200)
        ])
        bluetooth.stub(SetIDPSegmentRequest.self, with: SetIDPSegmentResponse(status: 3, unknown: 0))

        let result = syncBasal([
            RepeatingScheduleValue(startTime: 0, value: 0.8),
            RepeatingScheduleValue(startTime: 3600, value: 1.5)
        ])

        guard case .failure = result else {
            return XCTFail("Expected a rejected segment write to fail the sync")
        }
    }

    func testSyncBasalRateScheduleFailsWhenNotConnected() {
        bluetooth.connectError = PumpCommError.pumpNotConnected

        let result = syncBasal([RepeatingScheduleValue(startTime: 0, value: 0.8)])

        guard case .failure = result else {
            return XCTFail("Expected a connect failure to fail the sync")
        }
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }

    // MARK: - Delivery limits

    private func syncLimits(_ limits: DeliveryLimits) -> Result<DeliveryLimits, Error> {
        var result: Result<DeliveryLimits, Error>!
        let expectation = expectation(description: "syncDeliveryLimits")
        manager.syncDeliveryLimits(limits: limits) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        return result
    }

    func testSyncDeliveryLimitsPushesLimitsToPumpAndStoresThem() throws {
        bluetooth.stub(SetMaxBasalLimitRequest.self, with: SetMaxBasalLimitResponse(status: 0))
        bluetooth.stub(SetMaxBolusLimitRequest.self, with: SetMaxBolusLimitResponse(status: 0))

        let limits = DeliveryLimits(
            maximumBasalRate: HKQuantity(
                unit: HKUnit.internationalUnit().unitDivided(by: .hour()),
                doubleValue: 4.2
            ),
            maximumBolus: HKQuantity(unit: .internationalUnit(), doubleValue: 9.5)
        )

        let result = syncLimits(limits)

        guard case .success = result else {
            return XCTFail("Expected success, got \(result)")
        }

        XCTAssertEqual(bluetooth.sent(SetMaxBasalLimitRequest.self).count, 1)
        XCTAssertEqual(bluetooth.sent(SetMaxBolusLimitRequest.self).count, 1)
        XCTAssertEqual(manager.state.settings.maxTempBasalRate, 4.2)
        XCTAssertEqual(manager.state.settings.maxBolus, 9.5)
    }

    /// The stored maxBolus is what `enactBolus` validates against, so a pump rejection must not
    /// leave the driver believing a limit it never accepted is in force.
    func testSyncDeliveryLimitsFailsWhenPumpRejectsBolusLimit() {
        bluetooth.stub(SetMaxBasalLimitRequest.self, with: SetMaxBasalLimitResponse(status: 0))
        bluetooth.stub(SetMaxBolusLimitRequest.self, with: SetMaxBolusLimitResponse(status: 1))

        let limits = DeliveryLimits(
            maximumBasalRate: HKQuantity(
                unit: HKUnit.internationalUnit().unitDivided(by: .hour()),
                doubleValue: 4.2
            ),
            maximumBolus: HKQuantity(unit: .internationalUnit(), doubleValue: 9.5)
        )

        let result = syncLimits(limits)

        guard case .failure = result else {
            return XCTFail("Expected a rejected limit write to fail the sync")
        }
        XCTAssertNil(manager.state.settings.maxBolus)
    }
}
