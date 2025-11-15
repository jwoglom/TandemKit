import XCTest
@testable import TandemKit
@testable import TandemCore

@available(macOS 13.0, iOS 14.0, *)
final class TandemPumpManagerTelemetryTests: XCTestCase {
    private enum BatteryType {
        case v1
        case v2
    }

    override func tearDown() {
        super.tearDown()
        PumpStateSupplier.pumpApiVersion = nil
    }

    private func enqueueCommonTelemetryResponses(
        on peripheralManager: MockPeripheralManager,
        batteryType: BatteryType,
        cgmResponse: CurrentEGVGuiDataResponse,
        alertIntMap: UInt64 = 0,
        alarmIntMap: UInt64 = 0
    ) {
        switch batteryType {
        case .v1:
            peripheralManager.enqueueResponse(
                for: CurrentBatteryV1Request.self,
                response: CurrentBatteryV1Response(currentBatteryAbc: 20, currentBatteryIbc: 80)
            )
        case .v2:
            peripheralManager.enqueueResponse(
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
        }

        peripheralManager.enqueueResponse(
            for: InsulinStatusRequest.self,
            response: InsulinStatusResponse(currentInsulinAmount: 120_000, isEstimate: 0, insulinLowAmount: 0)
        )
        peripheralManager.enqueueResponse(
            for: CurrentBasalStatusRequest.self,
            response: CurrentBasalStatusResponse(profileBasalRate: 1_000, currentBasalRate: 1_000, basalModifiedBitmask: 0)
        )
        peripheralManager.enqueueResponse(
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
        peripheralManager.enqueueResponse(
            for: CurrentEGVGuiDataRequest.self,
            response: cgmResponse
        )
        peripheralManager.enqueueResponse(
            for: AlertStatusRequest.self,
            response: AlertStatusResponse(intMap: alertIntMap)
        )
        peripheralManager.enqueueResponse(
            for: AlarmStatusRequest.self,
            response: AlarmStatusResponse(intMap: alarmIntMap)
        )
    }

    func testBatteryTelemetryUsesV1RequestWhenApiIsLegacy() {
        PumpStateSupplier.pumpApiVersion = { KnownApiVersion.apiV2_1.value }

        let mockPeripheralManager = MockPeripheralManager()
        let cgmResponse = CurrentEGVGuiDataResponse(
            bgReadingTimestampSeconds: 0,
            cgmReading: 110,
            egvStatusId: CurrentEGVGuiDataResponse.EGVStatus.VALID.rawValue,
            trendRate: 3
        )
        enqueueCommonTelemetryResponses(on: mockPeripheralManager, batteryType: .v1, cgmResponse: cgmResponse)

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
        let cgmResponse = CurrentEGVGuiDataResponse(
            bgReadingTimestampSeconds: 0,
            cgmReading: 125,
            egvStatusId: CurrentEGVGuiDataResponse.EGVStatus.VALID.rawValue,
            trendRate: 3
        )
        enqueueCommonTelemetryResponses(on: mockPeripheralManager, batteryType: .v2, cgmResponse: cgmResponse)

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
        let cgmResponse = CurrentEGVGuiDataResponse(
            bgReadingTimestampSeconds: 0,
            cgmReading: 118,
            egvStatusId: CurrentEGVGuiDataResponse.EGVStatus.VALID.rawValue,
            trendRate: 3
        )
        enqueueCommonTelemetryResponses(on: mockPeripheralManager, batteryType: .v2, cgmResponse: cgmResponse)

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

    func testCGMTelemetryPopulatesStatusAndRawState() {
        PumpStateSupplier.pumpApiVersion = { KnownApiVersion.apiV3_4.value }

        let mockPeripheralManager = MockPeripheralManager()
        let timestamp: UInt32 = 600
        let cgmResponse = CurrentEGVGuiDataResponse(
            bgReadingTimestampSeconds: timestamp,
            cgmReading: 145,
            egvStatusId: CurrentEGVGuiDataResponse.EGVStatus.VALID.rawValue,
            trendRate: 4
        )
        enqueueCommonTelemetryResponses(on: mockPeripheralManager, batteryType: .v2, cgmResponse: cgmResponse)

        let transport = MockPumpMessageTransport(peripheralManager: mockPeripheralManager)
        let mockPumpComm = MockPumpComm(pumpState: nil)
        let manager = TandemPumpManager(state: TandemPumpManagerState())
        manager.setPumpCommForTesting(mockPumpComm)

        let expectation = expectation(description: "CGM telemetry dispatched")
        mockPumpComm.onSend = { message in
            if message is CurrentEGVGuiDataRequest {
                expectation.fulfill()
            }
        }

        manager.updateTransport(transport)
        wait(for: [expectation], timeout: 1.0)

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        guard let glucoseDisplay = manager.status.glucoseDisplay else {
            return XCTFail("Expected glucose display to be populated")
        }
        XCTAssertEqual(glucoseDisplay.value, 145, accuracy: 0.1)
        XCTAssertTrue(glucoseDisplay.isStateValid)
        XCTAssertNil(manager.status.pumpStatusHighlight)

        let rawState = manager.rawState
        let cgmRaw = rawState["lastCGMReading"] as? [String: Any]
        XCTAssertNotNil(cgmRaw)
        let storedStatus = (cgmRaw?["egvStatusId"] as? Int)
        XCTAssertEqual(storedStatus, CurrentEGVGuiDataResponse.EGVStatus.VALID.rawValue)
    }

    func testAlertTelemetryCreatesWarningHighlight() {
        PumpStateSupplier.pumpApiVersion = { KnownApiVersion.apiV3_4.value }

        let mockPeripheralManager = MockPeripheralManager()
        let cgmResponse = CurrentEGVGuiDataResponse(
            bgReadingTimestampSeconds: 0,
            cgmReading: 130,
            egvStatusId: CurrentEGVGuiDataResponse.EGVStatus.VALID.rawValue,
            trendRate: 3
        )
        let alertBit = UInt64(1) << UInt64(AlertStatusResponse.AlertResponseType.LOW_INSULIN_ALERT.rawValue)
        enqueueCommonTelemetryResponses(
            on: mockPeripheralManager,
            batteryType: .v2,
            cgmResponse: cgmResponse,
            alertIntMap: alertBit
        )

        let transport = MockPumpMessageTransport(peripheralManager: mockPeripheralManager)
        let mockPumpComm = MockPumpComm(pumpState: nil)
        let manager = TandemPumpManager(state: TandemPumpManagerState())
        manager.setPumpCommForTesting(mockPumpComm)

        manager.updateTransport(transport)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        let highlight = manager.status.pumpStatusHighlight
        XCTAssertEqual(highlight?.state, .warning)
        XCTAssertTrue(highlight?.localizedMessage.contains("Pump alert") ?? false)
        XCTAssertTrue(highlight?.localizedMessage.contains("Low Insulin") ?? false)

        let activeAlerts = manager.rawState["activeAlertIDs"] as? [Int]
        XCTAssertEqual(activeAlerts, [AlertStatusResponse.AlertResponseType.LOW_INSULIN_ALERT.rawValue])
    }

    func testAlarmTelemetryCreatesCriticalHighlight() {
        PumpStateSupplier.pumpApiVersion = { KnownApiVersion.apiV3_4.value }

        let mockPeripheralManager = MockPeripheralManager()
        let cgmResponse = CurrentEGVGuiDataResponse(
            bgReadingTimestampSeconds: 0,
            cgmReading: 140,
            egvStatusId: CurrentEGVGuiDataResponse.EGVStatus.VALID.rawValue,
            trendRate: 3
        )
        let alarmBit = UInt64(1) << UInt64(AlarmStatusResponse.AlarmResponseType.OCCLUSION_ALARM.rawValue)
        enqueueCommonTelemetryResponses(
            on: mockPeripheralManager,
            batteryType: .v2,
            cgmResponse: cgmResponse,
            alarmIntMap: alarmBit
        )

        let transport = MockPumpMessageTransport(peripheralManager: mockPeripheralManager)
        let mockPumpComm = MockPumpComm(pumpState: nil)
        let manager = TandemPumpManager(state: TandemPumpManagerState())
        manager.setPumpCommForTesting(mockPumpComm)

        manager.updateTransport(transport)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        let highlight = manager.status.pumpStatusHighlight
        XCTAssertEqual(highlight?.state, .critical)
        XCTAssertTrue(highlight?.localizedMessage.contains("Pump alarm") ?? false)
        XCTAssertTrue(highlight?.localizedMessage.contains("Occlusion") ?? false)

        let activeAlarms = manager.rawState["activeAlarmIDs"] as? [Int]
        XCTAssertEqual(activeAlarms, [AlarmStatusResponse.AlarmResponseType.OCCLUSION_ALARM.rawValue])
    }

    func testLowCGMTelemetryGeneratesHighlightWhenNoAlerts() {
        PumpStateSupplier.pumpApiVersion = { KnownApiVersion.apiV3_4.value }

        let mockPeripheralManager = MockPeripheralManager()
        let cgmResponse = CurrentEGVGuiDataResponse(
            bgReadingTimestampSeconds: 0,
            cgmReading: 55,
            egvStatusId: CurrentEGVGuiDataResponse.EGVStatus.LOW.rawValue,
            trendRate: 0
        )
        enqueueCommonTelemetryResponses(on: mockPeripheralManager, batteryType: .v2, cgmResponse: cgmResponse)

        let transport = MockPumpMessageTransport(peripheralManager: mockPeripheralManager)
        let mockPumpComm = MockPumpComm(pumpState: nil)
        let manager = TandemPumpManager(state: TandemPumpManagerState())
        manager.setPumpCommForTesting(mockPumpComm)

        manager.updateTransport(transport)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        let highlight = manager.status.pumpStatusHighlight
        XCTAssertEqual(highlight?.state, .critical)
        XCTAssertTrue(highlight?.localizedMessage.contains("Glucose low") ?? false)
    }
}
