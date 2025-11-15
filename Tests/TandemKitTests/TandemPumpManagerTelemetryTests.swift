import XCTest
@testable import TandemKit
@testable import TandemCore

@available(macOS 13.0, iOS 14.0, *)
final class TandemPumpManagerTelemetryTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        PumpStateSupplier.pumpApiVersion = nil
    }

    func testBatteryTelemetryUsesV1RequestWhenApiIsLegacy() {
        PumpStateSupplier.pumpApiVersion = { KnownApiVersion.apiV2_1.value }

        let mockPeripheralManager = MockPeripheralManager()
        mockPeripheralManager.enqueueResponse(
            for: CurrentBatteryV1Request.self,
            response: CurrentBatteryV1Response(currentBatteryAbc: 20, currentBatteryIbc: 80)
        )
        mockPeripheralManager.enqueueResponse(
            for: InsulinStatusRequest.self,
            response: InsulinStatusResponse(currentInsulinAmount: 120_000, isEstimate: 0, insulinLowAmount: 0)
        )
        mockPeripheralManager.enqueueResponse(
            for: CurrentBasalStatusRequest.self,
            response: CurrentBasalStatusResponse(profileBasalRate: 1_000, currentBasalRate: 1_000, basalModifiedBitmask: 0)
        )
        mockPeripheralManager.enqueueResponse(
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
        mockPeripheralManager.enqueueResponse(
            for: HistoryLogStatusRequest.self,
            response: HistoryLogStatusResponse(numEntries: 0, firstSequenceNum: 0, lastSequenceNum: 0)
        )

        let transport = MockPumpMessageTransport(peripheralManager: mockPeripheralManager)
        let mockPumpComm = MockPumpComm(pumpState: nil)
        let manager = TandemPumpManager(state: TandemPumpManagerState())
        manager.setPumpCommForTesting(mockPumpComm)

        let expectation = expectation(description: "Battery request dispatched")
        mockPumpComm.onSend = { message in
            if message is CurrentBatteryV1Request {
                expectation.fulfill()
            }
        }

        manager.updateTransport(transport)
        wait(for: [expectation], timeout: 1.0)

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertNotNil(
            mockPumpComm.calls.first(where: { $0.requestType == CurrentBatteryV1Request.self && $0.expectedResponseType == CurrentBatteryV1Response.self }),
            "Expected PumpComm to request CurrentBatteryV1Response for legacy API"
        )
        XCTAssertTrue(
            mockPeripheralManager.sentMessages.contains(where: { $0.message is CurrentBatteryV1Request }),
            "Legacy battery request should be sent via transport"
        )
        XCTAssertTrue(
            mockPeripheralManager.sentMessages.contains(where: { $0.message is CurrentBolusStatusRequest }),
            "Bolus status request should be sent via transport"
        )
        XCTAssertEqual(manager.pumpBatteryChargeRemaining, 0.8, accuracy: 0.01)
    }

    func testBatteryTelemetryUsesV2RequestWhenApiSupportsIt() {
        PumpStateSupplier.pumpApiVersion = { KnownApiVersion.apiV3_4.value }

        let mockPeripheralManager = MockPeripheralManager()
        mockPeripheralManager.enqueueResponse(
            for: CurrentBatteryV2Request.self,
            response: CurrentBatteryV2Response(
                currentBatteryAbc: 10,
                currentBatteryIbc: 60,
                chargingStatus: 0,
                unknown1: 0,
                unknown2: 0,
                unknown3: 0,
                unknown4: 0
            )
        )
        mockPeripheralManager.enqueueResponse(
            for: InsulinStatusRequest.self,
            response: InsulinStatusResponse(currentInsulinAmount: 150_000, isEstimate: 0, insulinLowAmount: 0)
        )
        mockPeripheralManager.enqueueResponse(
            for: CurrentBasalStatusRequest.self,
            response: CurrentBasalStatusResponse(profileBasalRate: 900, currentBasalRate: 900, basalModifiedBitmask: 0)
        )
        mockPeripheralManager.enqueueResponse(
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
        mockPeripheralManager.enqueueResponse(
            for: HistoryLogStatusRequest.self,
            response: HistoryLogStatusResponse(numEntries: 0, firstSequenceNum: 0, lastSequenceNum: 0)
        )

        let transport = MockPumpMessageTransport(peripheralManager: mockPeripheralManager)
        let mockPumpComm = MockPumpComm(pumpState: nil)
        let manager = TandemPumpManager(state: TandemPumpManagerState())
        manager.setPumpCommForTesting(mockPumpComm)

        let expectation = expectation(description: "Battery V2 request dispatched")
        mockPumpComm.onSend = { message in
            if message is CurrentBatteryV2Request {
                expectation.fulfill()
            }
        }

        manager.updateTransport(transport)
        wait(for: [expectation], timeout: 1.0)

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertNotNil(
            mockPumpComm.calls.first(where: { $0.requestType == CurrentBatteryV2Request.self && $0.expectedResponseType == CurrentBatteryV2Response.self }),
            "Expected PumpComm to request CurrentBatteryV2Response for newer API"
        )
        XCTAssertTrue(
            mockPeripheralManager.sentMessages.contains(where: { $0.message is CurrentBatteryV2Request }),
            "Newer API battery request should be sent via transport"
        )
        XCTAssertEqual(manager.pumpBatteryChargeRemaining, 0.6, accuracy: 0.01)
    }

    func testBatteryTelemetryErrorDoesNotUpdateCharge() {
        PumpStateSupplier.pumpApiVersion = { KnownApiVersion.apiV3_4.value }

        let mockPeripheralManager = MockPeripheralManager()
        mockPeripheralManager.enqueueError(for: CurrentBatteryV2Request.self, error: PumpCommError.noResponse)
        mockPeripheralManager.enqueueResponse(
            for: InsulinStatusRequest.self,
            response: InsulinStatusResponse(currentInsulinAmount: 110_000, isEstimate: 0, insulinLowAmount: 0)
        )
        mockPeripheralManager.enqueueResponse(
            for: CurrentBasalStatusRequest.self,
            response: CurrentBasalStatusResponse(profileBasalRate: 1_200, currentBasalRate: 1_200, basalModifiedBitmask: 0)
        )
        mockPeripheralManager.enqueueResponse(
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
        mockPeripheralManager.enqueueResponse(
            for: HistoryLogStatusRequest.self,
            response: HistoryLogStatusResponse(numEntries: 0, firstSequenceNum: 0, lastSequenceNum: 0)
        )

        let transport = MockPumpMessageTransport(peripheralManager: mockPeripheralManager)
        let mockPumpComm = MockPumpComm(pumpState: nil)
        let manager = TandemPumpManager(state: TandemPumpManagerState())
        manager.setPumpCommForTesting(mockPumpComm)

        let expectation = expectation(description: "Battery error dispatched")
        mockPumpComm.onSend = { message in
            if message is CurrentBatteryV2Request {
                expectation.fulfill()
            }
        }

        manager.updateTransport(transport)
        wait(for: [expectation], timeout: 1.0)

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertNil(manager.pumpBatteryChargeRemaining)
        XCTAssertNotNil(
            mockPumpComm.calls.first(where: { $0.requestType == CurrentBatteryV2Request.self })
        )
    }
}
