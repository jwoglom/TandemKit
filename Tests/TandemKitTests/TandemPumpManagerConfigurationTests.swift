import XCTest
@testable import TandemKit
@testable import TandemCore
import LoopKit

final class TandemPumpManagerConfigurationTests: XCTestCase {
    private func makeManager(pumpState: PumpState) -> TandemPumpManager {
        let state = TandemPumpManagerState(pumpState: pumpState)
        return TandemPumpManager(state: state)
    }

    func testSyncBasalRateScheduleSendsSegmentUpdates() throws {
        let pumpState = PumpState(address: 0x01020304)
        let manager = makeManager(pumpState: pumpState)
        let peripheral = MockPeripheralManager()
        let transport = MockPumpMessageTransport(peripheralManager: peripheral)
        let mockComm = MockPumpComm(pumpState: pumpState)
        manager.setPumpCommForTesting(mockComm)

        PumpStateSupplier.pumpApiVersion = { KnownApiVersion.apiV3_4.value }
        defer { PumpStateSupplier.pumpApiVersion = nil }

        peripheral.enqueueResponse(
            for: CurrentBatteryV2Request.self,
            response: CurrentBatteryV2Response(
                currentBatteryAbc: 80,
                currentBatteryIbc: 80,
                chargingStatus: 0,
                unknown1: 0,
                unknown2: 0,
                unknown3: 0,
                unknown4: 0
            )
        )
        peripheral.enqueueResponse(
            for: InsulinStatusRequest.self,
            response: InsulinStatusResponse(currentInsulinAmount: 150_000, isEstimate: 0, insulinLowAmount: 0)
        )
        peripheral.enqueueResponse(
            for: CurrentBasalStatusRequest.self,
            response: CurrentBasalStatusResponse(profileBasalRate: 900, currentBasalRate: 900, basalModifiedBitmask: 0)
        )
        peripheral.enqueueResponse(
            for: CurrentBolusStatusRequest.self,
            response: CurrentBolusStatusResponse(
                statusId: 0,
                bolusId: 0,
                timestamp: 0,
                requestedVolume: 0,
                bolusSourceId: 0,
                bolusTypeBitmask: 0
            )
        )
        peripheral.enqueueResponse(
            for: HistoryLogStatusRequest.self,
            response: HistoryLogStatusResponse(numEntries: 0, firstSequenceNum: 0, lastSequenceNum: 0)
        )

        manager.updateTransport(transport)

        let items = [
            RepeatingScheduleValue(startTime: 0, value: 0.8),
            RepeatingScheduleValue(startTime: 3_600, value: 1.2)
        ]

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

        waitForExpectations(timeout: 1)

        let unwrappedResult = try XCTUnwrap(result)
        let schedule = try XCTUnwrap(try? unwrappedResult.get())
        XCTAssertEqual(schedule.items, items.sorted { $0.startTime < $1.startTime })
        XCTAssertEqual(schedule.timeZone, manager.status.timeZone)

        XCTAssertEqual(peripheral.sentMessages.count, items.count)
        let firstRequest = try XCTUnwrap(peripheral.sentMessages.first?.message as? SetIDPSegmentRequest)
        XCTAssertEqual(firstRequest.segmentIndex, 0)
        XCTAssertEqual(firstRequest.profileStartTime, Int((items[0].startTime / 60.0).rounded()))
        XCTAssertEqual(firstRequest.profileBasalRate, Int((items[0].value * 1000.0).rounded()))
        let expectedMask = IDPSegmentResponse.IDPSegmentStatus.fromBitmask(firstRequest.idpStatusId)
        XCTAssertTrue(expectedMask.contains(.BASAL_RATE))
        XCTAssertTrue(expectedMask.contains(.START_TIME))

        let restoredState = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.rawState))
        XCTAssertEqual(restoredState.basalRateSchedule?.items, items.sorted { $0.startTime < $1.startTime })
        XCTAssertEqual(restoredState.settings.maxBasalScheduleEntry, items.map { $0.value }.max())
    }

    func testSyncDeliveryLimitsUpdatesSettings() throws {
        let pumpState = PumpState(address: 0x0A0B0C0D)
        let manager = makeManager(pumpState: pumpState)
        let peripheral = MockPeripheralManager()
        let transport = MockPumpMessageTransport(peripheralManager: peripheral)
        let mockComm = MockPumpComm(pumpState: pumpState)
        manager.setPumpCommForTesting(mockComm)

        PumpStateSupplier.pumpApiVersion = { KnownApiVersion.apiV3_4.value }
        defer { PumpStateSupplier.pumpApiVersion = nil }

        peripheral.enqueueResponse(
            for: CurrentBatteryV2Request.self,
            response: CurrentBatteryV2Response(
                currentBatteryAbc: 90,
                currentBatteryIbc: 90,
                chargingStatus: 0,
                unknown1: 0,
                unknown2: 0,
                unknown3: 0,
                unknown4: 0
            )
        )
        peripheral.enqueueResponse(
            for: InsulinStatusRequest.self,
            response: InsulinStatusResponse(currentInsulinAmount: 140_000, isEstimate: 0, insulinLowAmount: 0)
        )
        peripheral.enqueueResponse(
            for: CurrentBasalStatusRequest.self,
            response: CurrentBasalStatusResponse(profileBasalRate: 800, currentBasalRate: 800, basalModifiedBitmask: 0)
        )
        peripheral.enqueueResponse(
            for: CurrentBolusStatusRequest.self,
            response: CurrentBolusStatusResponse(
                statusId: 0,
                bolusId: 0,
                timestamp: 0,
                requestedVolume: 0,
                bolusSourceId: 0,
                bolusTypeBitmask: 0
            )
        )
        peripheral.enqueueResponse(
            for: HistoryLogStatusRequest.self,
            response: HistoryLogStatusResponse(numEntries: 0, firstSequenceNum: 0, lastSequenceNum: 0)
        )

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
        let basalRequest = try XCTUnwrap(peripheral.sentMessages.first { $0.message is SetMaxBasalLimitRequest }?.message as? SetMaxBasalLimitRequest)
        XCTAssertEqual(basalRequest.maxHourlyBasalMilliunits, Int((limits.maximumBasalRatePerHour! * 1000.0).rounded()))

        let bolusRequest = try XCTUnwrap(peripheral.sentMessages.first { $0.message is SetMaxBolusLimitRequest }?.message as? SetMaxBolusLimitRequest)
        XCTAssertEqual(bolusRequest.maxBolusMilliunits, Int((limits.maximumBolus! * 1000.0).rounded()))

        let restoredState = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.rawState))
        XCTAssertEqual(restoredState.settings.maxTempBasalRate, limits.maximumBasalRatePerHour)
        XCTAssertEqual(restoredState.settings.maxBolus, limits.maximumBolus)
    }
}
