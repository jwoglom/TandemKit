import LoopKit
@testable import TandemCore
@testable import TandemKit
import XCTest

final class TandemPumpManagerConfigurationTests: XCTestCase {
    private func makeManager(pumpState: PumpState) -> TandemPumpManager {
        let state = TandemPumpManagerState(pumpState: pumpState)
        return TandemPumpManager(state: state)
    }

    func testSyncBasalRateScheduleSendsSegmentUpdates() throws {
        let pumpState = PumpState(address: 0x0102_0304)
        let manager = makeManager(pumpState: pumpState)
        let peripheral = MockPeripheralManager()
        let transport = MockPumpMessageTransport(peripheralManager: peripheral)
        let mockComm = MockPumpComm(pumpState: pumpState)
        manager.setPumpCommForTesting(mockComm)
        manager.updateTransport(transport)

        let items = [
            RepeatingScheduleValue(startTime: 0, value: 0.8),
            RepeatingScheduleValue(startTime: 3600, value: 1.2)
        ]

        // Step 1: Mock ProfileStatusRequest -> ProfileStatusResponse
        peripheral.enqueueResponse(
            for: ProfileStatusRequest.self,
            response: ProfileStatusResponse(
                numberOfProfiles: 1,
                idpSlot0Id: 10,
                idpSlot1Id: 0,
                idpSlot2Id: 0,
                idpSlot3Id: 0,
                idpSlot4Id: 0,
                idpSlot5Id: 0,
                activeSegmentIndex: 0
            )
        )

        // Step 2: Mock IDPSettingsRequest -> IDPSettingsResponse
        peripheral.enqueueResponse(
            for: IDPSettingsRequest.self,
            response: IDPSettingsResponse(
                idpId: 10,
                profileName: "Test",
                numberOfProfileSegments: 2,
                activeProfile: 1,
                carbEntry: 1,
                totalDailyInsulin: 0,
                profileInsulinDuration: 180
            )
        )

        // Step 3: Mock IDPSegmentRequest -> IDPSegmentResponse for existing segments
        peripheral.enqueueResponse(
            for: IDPSegmentRequest.self,
            response: IDPSegmentResponse(
                idpId: 10,
                segmentIndex: 0,
                profileStartTime: 0,
                profileBasalRate: 1000,
                profileCarbRatio: 10000,
                profileTargetBG: 110,
                profileISF: 50,
                idpStatusId: 31
            )
        )
        peripheral.enqueueResponse(
            for: IDPSegmentRequest.self,
            response: IDPSegmentResponse(
                idpId: 10,
                segmentIndex: 1,
                profileStartTime: 480,
                profileBasalRate: 1200,
                profileCarbRatio: 10000,
                profileTargetBG: 110,
                profileISF: 50,
                idpStatusId: 31
            )
        )

        // Step 4: Mock SetIDPSegmentRequest -> SetIDPSegmentResponse for modifications
        for _ in items {
            peripheral.enqueueResponse(
                for: SetIDPSegmentRequest.self,
                response: SetIDPSegmentResponse(status: 0, unknown: 0)
            )
        }

        let expectation = expectation(description: "basal schedule synced")
        var result: Result<BasalRateSchedule, Error>?

        manager.syncBasalRateSchedule(items: items) { syncResult in
            result = syncResult
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)

        let unwrappedResult = try XCTUnwrap(result)
        let schedule = try XCTUnwrap(try? unwrappedResult.get())
        XCTAssertEqual(schedule.items, items.sorted { $0.startTime < $1.startTime })
        XCTAssertEqual(schedule.timeZone, manager.status.timeZone)

        // Find the SetIDPSegmentRequest messages (should be the last 2)
        let setRequests = peripheral.sentMessages.compactMap { $0.message as? SetIDPSegmentRequest }
        XCTAssertEqual(setRequests.count, items.count)

        let firstRequest = try XCTUnwrap(setRequests.first)
        XCTAssertEqual(firstRequest.segmentIndex, 0)
        XCTAssertEqual(firstRequest.profileStartTime, Int((items[0].startTime / 60.0).rounded()))
        XCTAssertEqual(firstRequest.profileBasalRate, Int((items[0].value * 1000.0).rounded()))
        // Per pumpX2 IDPManager: all 5 flags must be set when modifying segments
        let expectedMask = IDPSegmentResponse.IDPSegmentStatus.fromBitmask(firstRequest.idpStatusId)
        XCTAssertEqual(firstRequest.idpStatusId, 31, "Status mask should be 31 (all 5 fields)")
        XCTAssertTrue(expectedMask.contains(.BASAL_RATE))
        XCTAssertTrue(expectedMask.contains(.CARB_RATIO))
        XCTAssertTrue(expectedMask.contains(.TARGET_BG))
        XCTAssertTrue(expectedMask.contains(.CORRECTION_FACTOR))
        XCTAssertTrue(expectedMask.contains(.START_TIME))

        // Verify other fields from existing segment were preserved
        XCTAssertEqual(firstRequest.profileCarbRatio, 10000)
        XCTAssertEqual(firstRequest.profileTargetBG, 110)
        XCTAssertEqual(firstRequest.profileISF, 50)

        let restoredState = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.rawState))
        XCTAssertEqual(restoredState.basalRateSchedule?.items, items.sorted { $0.startTime < $1.startTime })
        XCTAssertEqual(restoredState.settings.maxBasalScheduleEntry, items.map(\.value).max())
    }

    func testSyncDeliveryLimitsUpdatesSettings() throws {
        let pumpState = PumpState(address: 0x0A0B_0C0D)
        let manager = makeManager(pumpState: pumpState)
        let peripheral = MockPeripheralManager()
        let transport = MockPumpMessageTransport(peripheralManager: peripheral)
        let mockComm = MockPumpComm(pumpState: pumpState)
        manager.setPumpCommForTesting(mockComm)
        manager.updateTransport(transport)

        peripheral.enqueueResponse(
            for: SetMaxBasalLimitRequest.self,
            response: SetMaxBasalLimitResponse(status: 0)
        )
        peripheral.enqueueResponse(
            for: SetMaxBolusLimitRequest.self,
            response: SetMaxBolusLimitResponse(status: 0)
        )

        let limits = DeliveryLimits(maximumBasalRatePerHour: 3.5, maximumBolus: 11.2)

        let expectation = expectation(description: "limits synced")
        var result: Result<DeliveryLimits, Error>?

        manager.syncDeliveryLimits(limits: limits) { syncResult in
            result = syncResult
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)

        let appliedLimits = try XCTUnwrap(result?.get())
        XCTAssertEqual(appliedLimits.maximumBasalRatePerHour, limits.maximumBasalRatePerHour)
        XCTAssertEqual(appliedLimits.maximumBolus, limits.maximumBolus)

        XCTAssertEqual(peripheral.sentMessages.count, 2)
        let basalRequest = try XCTUnwrap(
            peripheral.sentMessages.first { $0.message is SetMaxBasalLimitRequest }?
                .message as? SetMaxBasalLimitRequest
        )
        XCTAssertEqual(basalRequest.maxHourlyBasalMilliunits, Int((limits.maximumBasalRatePerHour! * 1000.0).rounded()))

        let bolusRequest = try XCTUnwrap(
            peripheral.sentMessages.first { $0.message is SetMaxBolusLimitRequest }?
                .message as? SetMaxBolusLimitRequest
        )
        XCTAssertEqual(bolusRequest.maxBolusMilliunits, Int((limits.maximumBolus! * 1000.0).rounded()))

        let restoredState = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.rawState))
        XCTAssertEqual(restoredState.settings.maxTempBasalRate, limits.maximumBasalRatePerHour)
        XCTAssertEqual(restoredState.settings.maxBolus, limits.maximumBolus)
    }
}
