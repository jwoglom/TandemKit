import XCTest
@testable import TandemKit
@testable import TandemCore

@available(macOS 13.0, iOS 14.0, *)
final class TandemPumpManagerConnectionTests: XCTestCase {
    private var originalApiVersionSupplier: (() -> Int)? = PumpStateSupplier.pumpApiVersion

    override func tearDown() {
        super.tearDown()
        PumpStateSupplier.pumpApiVersion = originalApiVersionSupplier
    }

    func testConnectAndDisconnectManageTransportTelemetryAndState() {
        PumpStateSupplier.pumpApiVersion = { KnownApiVersion.apiV3_4.value }

        var pumpState = PumpState()
        pumpState.derivedSecret = Data(repeating: 0xAA, count: 32)
        pumpState.serverNonce = Data(repeating: 0xBB, count: 8)

        var managerState = TandemPumpManagerState(pumpState: pumpState)
        managerState.deliveryIsUncertain = false

        let manager = TandemPumpManager(state: managerState)
        let delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate

        let mockPeripheralManager = MockPeripheralManager()
        mockPeripheralManager.enqueueResponse(
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
        mockPeripheralManager.enqueueResponse(
            for: InsulinStatusRequest.self,
            response: InsulinStatusResponse(
                currentInsulinAmount: 150_000,
                isEstimate: 0,
                insulinLowAmount: 0
            )
        )
        mockPeripheralManager.enqueueResponse(
            for: CurrentBasalStatusRequest.self,
            response: CurrentBasalStatusResponse(
                profileBasalRate: 900,
                currentBasalRate: 900,
                basalModifiedBitmask: 0
            )
        )

        let transport = MockPumpMessageTransport(peripheralManager: mockPeripheralManager)
        let mockPumpComm = MockPumpComm(pumpState: pumpState)
        manager.setPumpCommForTesting(mockPumpComm)

        let telemetryExpectation = expectation(description: "Telemetry triggered")
        telemetryExpectation.expectedFulfillmentCount = 3

        mockPumpComm.onSend = { message in
            if message is CurrentBatteryV2Request ||
                message is InsulinStatusRequest ||
                message is CurrentBasalStatusRequest {
                telemetryExpectation.fulfill()
            }
        }

        manager.connect()

        XCTAssertTrue(manager.status.deliveryIsUncertain, "Starting a connection should mark delivery uncertain")

        manager.updateTransport(transport)

        wait(for: [telemetryExpectation], timeout: 1.0)

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertFalse(manager.status.deliveryIsUncertain, "Connected transport should clear uncertainty")
        XCTAssertEqual(delegate.statusUpdates.last?.0.deliveryIsUncertain, false)
        XCTAssertEqual(manager.pumpBatteryChargeRemaining, 0.8, accuracy: 0.01)
        XCTAssertNotNil(manager.reservoirLevel)

        let rawState = manager.rawState
        XCTAssertEqual(rawState["deliveryIsUncertain"] as? Bool, false)
        XCTAssertNotNil(rawState["lastReservoirReading"])

        let telemetryCountAfterConnect = mockPumpComm.calls.count

        manager.disconnect()

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertTrue(manager.status.deliveryIsUncertain, "Disconnecting should mark delivery uncertain")
        XCTAssertEqual(manager.rawState["deliveryIsUncertain"] as? Bool, true)

        let telemetryCountAfterDisconnect = mockPumpComm.calls.count
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(telemetryCountAfterDisconnect, telemetryCountAfterConnect, "Telemetry should pause once transport is cleared")
    }
}

@available(macOS 13.0, iOS 14.0, *)
final class MockPumpManagerDelegate: PumpManagerDelegate {
    struct StatusUpdate {
        let newStatus: PumpManagerStatus
        let oldStatus: PumpManagerStatus
    }

    private(set) var statusUpdates: [StatusUpdate] = []
    private(set) var recordedErrors: [PumpManagerError] = []
    private(set) var didUpdateStateCallCount: Int = 0

    var detectedSystemTimeOffset: TimeInterval = 0
    var automaticDosingEnabled: Bool = false

    func deviceManager(
        _ manager: DeviceManager,
        logEventForDeviceIdentifier deviceIdentifier: String?,
        type: DeviceLogEntryType,
        message: String,
        completion: ((Error?) -> Void)?
    ) {
        completion?(nil)
    }

    func pumpManager(
        _ pumpManager: PumpManager,
        didUpdate status: PumpManagerStatus,
        oldStatus: PumpManagerStatus
    ) {
        statusUpdates.append(StatusUpdate(newStatus: status, oldStatus: oldStatus))
    }

    func pumpManagerBLEHeartbeatDidFire(_ pumpManager: PumpManager) {}

    func pumpManagerMustProvideBLEHeartbeat(_ pumpManager: PumpManager) -> Bool { false }

    func pumpManagerWillDeactivate(_ pumpManager: PumpManager) {}

    func pumpManagerPumpWasReplaced(_ pumpManager: PumpManager) {}

    func pumpManager(
        _ pumpManager: PumpManager,
        didUpdatePumpRecordsBasalProfileStartEvents pumpRecordsBasalProfileStartEvents: Bool
    ) {}

    func pumpManager(
        _ pumpManager: PumpManager,
        didError error: PumpManagerError
    ) {
        recordedErrors.append(error)
    }

    func pumpManager(
        _ pumpManager: PumpManager,
        hasNewPumpEvents events: [NewPumpEvent],
        lastReconciliation: Date?,
        replacePendingEvents: Bool,
        completion: @escaping (Error?) -> Void
    ) {
        completion(nil)
    }

    func pumpManager(
        _ pumpManager: PumpManager,
        didReadReservoirValue units: Double,
        at date: Date,
        completion: @escaping (Result<(newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool), Error>) -> Void
    ) {
        completion(.success((SimpleReservoirValue(startDate: date, unitVolume: units), nil, true)))
    }

    func pumpManager(
        _ pumpManager: PumpManager,
        didAdjustPumpClockBy adjustment: TimeInterval
    ) {}

    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        didUpdateStateCallCount += 1
    }

    func pumpManager(
        _ pumpManager: PumpManager,
        didRequestBasalRateScheduleChange basalRateSchedule: BasalRateSchedule,
        completion: @escaping (Error?) -> Void
    ) {
        completion(nil)
    }

    func pumpManagerRecommendsLoop(_ pumpManager: PumpManager) {}

    func startDateToFilterNewPumpEvents(for manager: PumpManager) -> Date {
        Date.distantPast
    }
}
