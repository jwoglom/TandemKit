@testable import TandemCore
@testable import TandemKit
import XCTest

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
                message is CurrentBasalStatusRequest
            {
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
        XCTAssertEqual(
            telemetryCountAfterDisconnect,
            telemetryCountAfterConnect,
            "Telemetry should pause once transport is cleared"
        )
    }
}

@available(macOS 13.0, iOS 14.0, *) final class MockPumpManagerDelegate: PumpManagerDelegate {
    struct StatusUpdate {
        let newStatus: PumpManagerStatus
        let oldStatus: PumpManagerStatus
    }

    private(set) var statusUpdates: [StatusUpdate] = []
    private(set) var recordedErrors: [PumpManagerError] = []
    private(set) var didUpdateStateCallCount: Int = 0
    var didUpdateStateExpectation: XCTestExpectation?

    var detectedSystemTimeOffset: TimeInterval = 0
    var automaticDosingEnabled: Bool = false

    func deviceManager(
        _: DeviceManager,
        logEventForDeviceIdentifier _: String?,
        type _: DeviceLogEntryType,
        message _: String,
        completion: ((Error?) -> Void)?
    ) {
        completion?(nil)
    }

    func pumpManager(
        _: PumpManager,
        didUpdate status: PumpManagerStatus,
        oldStatus: PumpManagerStatus
    ) {
        statusUpdates.append(StatusUpdate(newStatus: status, oldStatus: oldStatus))
    }

    func pumpManagerBLEHeartbeatDidFire(_: PumpManager) {}

    func pumpManagerMustProvideBLEHeartbeat(_: PumpManager) -> Bool { false }

    func pumpManagerWillDeactivate(_: PumpManager) {}

    func pumpManagerPumpWasReplaced(_: PumpManager) {}

    func pumpManager(
        _: PumpManager,
        didUpdatePumpRecordsBasalProfileStartEvents _: Bool
    ) {}

    func pumpManager(
        _: PumpManager,
        didError error: PumpManagerError
    ) {
        recordedErrors.append(error)
    }

    func pumpManager(
        _: PumpManager,
        hasNewPumpEvents _: [NewPumpEvent],
        lastReconciliation _: Date?,
        replacePendingEvents _: Bool,
        completion: @escaping (Error?) -> Void
    ) {
        completion(nil)
    }

    func pumpManager(
        _: PumpManager,
        didReadReservoirValue units: Double,
        at date: Date,
        completion: @escaping (Result<
            (newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool),
            Error
        >) -> Void
    ) {
        completion(.success((SimpleReservoirValue(startDate: date, unitVolume: units), nil, true)))
    }

    func pumpManager(
        _: PumpManager,
        didAdjustPumpClockBy _: TimeInterval
    ) {}

    func pumpManagerDidUpdateState(_: PumpManager) {
        didUpdateStateCallCount += 1
        didUpdateStateExpectation?.fulfill()
        didUpdateStateExpectation = nil
    }

    func pumpManager(
        _: PumpManager,
        didRequestBasalRateScheduleChange _: BasalRateSchedule,
        completion: @escaping (Error?) -> Void
    ) {
        completion(nil)
    }

    func pumpManagerRecommendsLoop(_: PumpManager) {}

    func startDateToFilterNewPumpEvents(for _: PumpManager) -> Date {
        Date.distantPast
    }
}
