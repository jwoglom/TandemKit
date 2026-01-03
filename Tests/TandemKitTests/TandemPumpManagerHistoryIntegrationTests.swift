import Foundation
@testable import TandemCore
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerHistoryIntegrationTests: XCTestCase {
    func testFetchPumpHistoryDeliversEventsAndUpdatesState() {
        var pumpState = PumpState()
        pumpState.derivedSecret = Data(repeating: 0x01, count: 32)
        pumpState.serverNonce = Data(repeating: 0x02, count: 8)

        let manager = TandemPumpManager(state: TandemPumpManagerState(pumpState: pumpState))
        let delegate = CapturingPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = DispatchQueue(label: "com.loopkit.TandemKit.tests.history")

        let peripheral = MockPeripheralManager()
        let transport = MockPumpMessageTransport(peripheralManager: peripheral)
        let mockPumpComm = MockPumpComm(pumpState: pumpState)
        manager.setPumpCommForTesting(mockPumpComm)
        manager.updateTransport(transport)

        let status = HistoryLogStatusResponse(numEntries: 2, firstSequenceNum: 5, lastSequenceNum: 6)
        peripheral.enqueueResponse(for: HistoryLogStatusRequest.self, response: status)
        peripheral.enqueueResponse(for: HistoryLogRequest.self, response: HistoryLogResponse(status: 0, streamId: 9))

        let activation = BolusActivatedHistoryLog(pumpTimeSec: 100, sequenceNum: 5, bolusId: 7, iob: 0, bolusSize: 1.25)
        let completedLog = BolusCompletedHistoryLog(
            pumpTimeSec: 110,
            sequenceNum: 6,
            bolusId: 7,
            requestedVolume: 1.25,
            deliveredVolume: 1.25,
            duration: 600,
            iob: 0
        )

        let delegateExpectation = expectation(description: "delegate received events")
        delegate.onHasNewPumpEvents = { events, lastReconciliation, replacePendingEvents, completion in
            XCTAssertEqual(events.count, 1)
            if case let .bolus(dose: dose, units: units) = events.first {
                XCTAssertEqual(units, completedLog.deliveredVolume, accuracy: 0.01)
                XCTAssertEqual(dose.programmedUnits, completedLog.requestedVolume, accuracy: 0.01)
            } else {
                XCTFail("Expected bolus event")
            }
            XCTAssertNotNil(lastReconciliation)
            XCTAssertTrue(replacePendingEvents)
            delegateExpectation.fulfill()
            completion(nil)
        }

        manager.fetchPumpHistory { error in
            XCTAssertNil(error)
        }

        let stream = HistoryLogStreamResponse(
            numberOfHistoryLogs: 2,
            streamId: 9,
            historyLogStreamBytes: [activation.cargo, completedLog.cargo]
        )

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            mockPumpComm.delegate?.pumpComm(
                mockPumpComm,
                didReceive: stream,
                metadata: nil,
                characteristic: .HISTORY_LOG_CHARACTERISTICS,
                txId: 0
            )
        }

        wait(for: [delegateExpectation], timeout: 1.0)
        XCTAssertEqual(manager.state.lastHistorySequenceNum, 6)
        XCTAssertNotNil(manager.state.lastHistoryReconciliation)
    }

    func testFetchPumpHistoryUsesLastSequenceForStart() {
        var pumpState = PumpState()
        pumpState.derivedSecret = Data(repeating: 0x01, count: 32)
        pumpState.serverNonce = Data(repeating: 0x02, count: 8)

        var managerState = TandemPumpManagerState(pumpState: pumpState)
        managerState.lastHistorySequenceNum = 12

        let manager = TandemPumpManager(state: managerState)
        let delegate = CapturingPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = DispatchQueue(label: "com.loopkit.TandemKit.tests.history.sequence")

        let peripheral = MockPeripheralManager()
        let transport = MockPumpMessageTransport(peripheralManager: peripheral)
        let mockPumpComm = MockPumpComm(pumpState: pumpState)
        manager.setPumpCommForTesting(mockPumpComm)
        manager.updateTransport(transport)

        let status = HistoryLogStatusResponse(numEntries: 4, firstSequenceNum: 10, lastSequenceNum: 14)
        peripheral.enqueueResponse(for: HistoryLogStatusRequest.self, response: status)
        peripheral.enqueueResponse(for: HistoryLogRequest.self, response: HistoryLogResponse(status: 0, streamId: 3))

        let tempActivation = TempRateActivatedHistoryLog(
            pumpTimeSec: 200,
            sequenceNum: 13,
            tempRateId: 5,
            percent: 150,
            duration: 30,
            iob: 0,
            basalRate: 900,
            basalRate2: 900
        )
        let tempCompletion = TempRateCompletedHistoryLog(
            pumpTimeSec: 230,
            sequenceNum: 14,
            tempRateId: 5,
            iob: 0,
            basalRate: 900,
            basalRate2: 900
        )

        let delegateExpectation = expectation(description: "delegate received temp basal events")
        delegate.onHasNewPumpEvents = { events, _, _, completion in
            XCTAssertEqual(events.count, 1)
            delegateExpectation.fulfill()
            completion(nil)
        }

        manager.fetchPumpHistory { error in
            XCTAssertNil(error)
        }

        let stream = HistoryLogStreamResponse(
            numberOfHistoryLogs: 2,
            streamId: 3,
            historyLogStreamBytes: [tempActivation.cargo, tempCompletion.cargo]
        )

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            mockPumpComm.delegate?.pumpComm(
                mockPumpComm,
                didReceive: stream,
                metadata: nil,
                characteristic: .HISTORY_LOG_CHARACTERISTICS,
                txId: 0
            )
        }

        wait(for: [delegateExpectation], timeout: 1.0)

        let requests = peripheral.sentMessages.compactMap { $0 as? HistoryLogRequest }
        XCTAssertEqual(requests.first?.startLog, 13)
    }

    func testScheduledHistoryFetchTriggersAfterTransportComesOnline() {
        var pumpState = PumpState()
        pumpState.derivedSecret = Data(repeating: 0x01, count: 32)
        pumpState.serverNonce = Data(repeating: 0x02, count: 8)

        let manager = TandemPumpManager(state: TandemPumpManagerState(pumpState: pumpState))
        manager.setHistoryTelemetryIntervalForTesting(0.05)
        let delegate = CapturingPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = DispatchQueue(label: "com.loopkit.TandemKit.tests.history.telemetry")

        let peripheral = MockPeripheralManager()
        let transport = MockPumpMessageTransport(peripheralManager: peripheral)
        let mockPumpComm = MockPumpComm(pumpState: pumpState)
        manager.setPumpCommForTesting(mockPumpComm)

        let status = HistoryLogStatusResponse(numEntries: 1, firstSequenceNum: 1, lastSequenceNum: 1)
        peripheral.enqueueResponse(for: HistoryLogStatusRequest.self, response: status)
        peripheral.enqueueResponse(for: HistoryLogRequest.self, response: HistoryLogResponse(status: 0, streamId: 2))

        let activation = BolusActivatedHistoryLog(pumpTimeSec: 50, sequenceNum: 1, bolusId: 3, iob: 0, bolusSize: 0.5)
        let completedLog = BolusCompletedHistoryLog(
            pumpTimeSec: 60,
            sequenceNum: 1,
            bolusId: 3,
            requestedVolume: 0.5,
            deliveredVolume: 0.5,
            duration: 120,
            iob: 0
        )

        let delegateExpectation = expectation(description: "delegate received scheduled history events")
        delegate.onHasNewPumpEvents = { events, _, _, eventsCompletion in
            XCTAssertEqual(events.count, 1)
            if case let .bolus(dose: dose, units: units) = events.first {
                XCTAssertEqual(units, completedLog.deliveredVolume, accuracy: 0.01)
                XCTAssertEqual(dose.programmedUnits, completedLog.requestedVolume, accuracy: 0.01)
            } else {
                XCTFail("Expected bolus event from scheduled fetch")
            }
            delegateExpectation.fulfill()
            eventsCompletion(nil)
        }

        manager.updateTransport(transport)

        let stream = HistoryLogStreamResponse(
            numberOfHistoryLogs: 1,
            streamId: 2,
            historyLogStreamBytes: [activation.cargo, completedLog.cargo]
        )

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            mockPumpComm.delegate?.pumpComm(
                mockPumpComm,
                didReceive: stream,
                metadata: nil,
                characteristic: .HISTORY_LOG_CHARACTERISTICS,
                txId: 0
            )
        }

        wait(for: [delegateExpectation], timeout: 1.0)
    }
}

@available(macOS 13.0, iOS 14.0, *) private final class CapturingPumpManagerDelegate: MockPumpManagerDelegate {
    var onHasNewPumpEvents: (([NewPumpEvent], Date?, Bool, (_ completion: (Error?) -> Void) -> Void) -> Void)?

    override func pumpManager(
        _ pumpManager: PumpManager,
        hasNewPumpEvents events: [NewPumpEvent],
        lastReconciliation: Date?,
        replacePendingEvents: Bool,
        completion: @escaping (Error?) -> Void
    ) {
        onHasNewPumpEvents?(events, lastReconciliation, replacePendingEvents, completion)
    }
}
