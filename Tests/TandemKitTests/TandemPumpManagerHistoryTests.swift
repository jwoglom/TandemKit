import XCTest
@testable import TandemKit
@testable import TandemCore
import LoopKit

@available(macOS 13.0, iOS 14.0, *)
final class TandemPumpManagerHistoryTests: XCTestCase {
    private func enqueueDefaultTelemetryResponses(on peripheral: MockPeripheralManager) {
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
    }

    func testHistorySyncProcessesStreamAndDeliversEvents() throws {
        PumpStateSupplier.pumpApiVersion = { KnownApiVersion.apiV3_4.value }
        defer { PumpStateSupplier.pumpApiVersion = nil }

        let pumpState = PumpState(address: 0x1234ABCD)
        let managerState = TandemPumpManagerState(pumpState: pumpState)
        let manager = TandemPumpManager(state: managerState)
        let delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate

        let peripheral = MockPeripheralManager()
        enqueueDefaultTelemetryResponses(on: peripheral)

        let statusResponse = HistoryLogStatusResponse(numEntries: 3, firstSequenceNum: 100, lastSequenceNum: 102)
        peripheral.enqueueResponse(for: HistoryLogStatusRequest.self, response: statusResponse)

        let historyAck = HistoryLogResponse(status: 0, streamId: 7)
        peripheral.enqueueResponse(for: HistoryLogRequest.self, response: historyAck)

        let transport = MockPumpMessageTransport(peripheralManager: peripheral)
        let mockComm = MockPumpComm(pumpState: pumpState)
        manager.setPumpCommForTesting(mockComm)

        let baseTime: UInt32 = 1_700_000_000
        let bolusLog = BolusDeliveryHistoryLog(
            pumpTimeSec: baseTime,
            sequenceNum: 100,
            bolusID: 501,
            bolusDeliveryStatus: 0,
            bolusTypeBitmask: 1,
            bolusSource: BolusDeliveryHistoryLog.BolusSource.gui.rawValue,
            reserved: 0,
            requestedNow: 500,
            requestedLater: 0,
            correction: 0,
            extendedDurationRequested: 0,
            deliveredTotal: 500
        )
        let suspendLog = PumpingSuspendedHistoryLog(
            pumpTimeSec: baseTime + 60,
            sequenceNum: 101,
            insulinAmount: 0,
            reasonId: PumpingSuspendedHistoryLog.SuspendReason.userAborted.rawValue
        )
        let resumeLog = PumpingResumedHistoryLog(
            pumpTimeSec: baseTime + 120,
            sequenceNum: 102,
            insulinAmount: 0
        )

        let streamResponse = HistoryLogStreamResponse(
            numberOfHistoryLogs: 3,
            streamId: historyAck.streamId,
            historyLogStreamBytes: [bolusLog.cargo, suspendLog.cargo, resumeLog.cargo]
        )

        var historyRequestTriggered = false
        mockComm.onSend = { message in
            if message is HistoryLogRequest, !historyRequestTriggered {
                historyRequestTriggered = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let metadata = MessageRegistry.metadata(for: streamResponse)
                    manager.pumpComm(
                        mockComm,
                        didReceive: streamResponse,
                        metadata: metadata,
                        characteristic: .HISTORY_LOG_CHARACTERISTICS,
                        txId: 0x01
                    )
                }
            }
        }

        let eventsExpectation = expectation(description: "History events delivered")
        delegate.onPumpEvents = { events in
            if events.count == 3 {
                eventsExpectation.fulfill()
            }
        }

        manager.updateTransport(transport)
        wait(for: [eventsExpectation], timeout: 2.0)

        let batches = delegate.pumpEventBatches
        XCTAssertEqual(batches.count, 1)
        let events = try XCTUnwrap(batches.first)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].type, .bolus)
        XCTAssertEqual(events[0].dose?.value, 5.0, accuracy: 0.001)
        XCTAssertEqual(events[1].type, .suspend)
        XCTAssertEqual(events[2].type, .resume)

        let restoredState = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.rawState))
        XCTAssertEqual(restoredState.nextHistorySequence, 103)
        XCTAssertEqual(restoredState.lastReconciliation, events.map { $0.date }.max())
    }

    func testHistorySyncHandlesPaginationAcrossMultipleStreams() throws {
        PumpStateSupplier.pumpApiVersion = { KnownApiVersion.apiV3_4.value }
        defer { PumpStateSupplier.pumpApiVersion = nil }

        let pumpState = PumpState(address: 0x0BADF00D)
        var state = TandemPumpManagerState(pumpState: pumpState)
        state.nextHistorySequence = 80
        let manager = TandemPumpManager(state: state)
        let delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate

        let peripheral = MockPeripheralManager()
        enqueueDefaultTelemetryResponses(on: peripheral)

        let statusResponse = HistoryLogStatusResponse(numEntries: 18, firstSequenceNum: 80, lastSequenceNum: 97)
        peripheral.enqueueResponse(for: HistoryLogStatusRequest.self, response: statusResponse)

        let firstAck = HistoryLogResponse(status: 0, streamId: 9)
        let secondAck = HistoryLogResponse(status: 0, streamId: 10)
        peripheral.enqueueResponse(for: HistoryLogRequest.self, response: firstAck)
        peripheral.enqueueResponse(for: HistoryLogRequest.self, response: secondAck)

        let transport = MockPumpMessageTransport(peripheralManager: peripheral)
        let mockComm = MockPumpComm(pumpState: pumpState)
        manager.setPumpCommForTesting(mockComm)

        let baseTime: UInt32 = 1_700_100_000
        let pageOneLogs: [Data] = (0..<16).map { index in
            let sequence = UInt32(80 + index)
            let log = BolusDeliveryHistoryLog(
                pumpTimeSec: baseTime + UInt32(index * 60),
                sequenceNum: sequence,
                bolusID: Int(sequence),
                bolusDeliveryStatus: 0,
                bolusTypeBitmask: 1,
                bolusSource: BolusDeliveryHistoryLog.BolusSource.gui.rawValue,
                reserved: 0,
                requestedNow: 500,
                requestedLater: 0,
                correction: 0,
                extendedDurationRequested: 0,
                deliveredTotal: 500
            )
            return log.cargo
        }

        let pageTwoLogs: [Data] = (0..<2).map { index in
            let sequence = UInt32(96 + index)
            let log = BolusDeliveryHistoryLog(
                pumpTimeSec: baseTime + UInt32((16 + index) * 60),
                sequenceNum: sequence,
                bolusID: Int(sequence),
                bolusDeliveryStatus: 0,
                bolusTypeBitmask: 1,
                bolusSource: BolusDeliveryHistoryLog.BolusSource.gui.rawValue,
                reserved: 0,
                requestedNow: 500,
                requestedLater: 0,
                correction: 0,
                extendedDurationRequested: 0,
                deliveredTotal: 500
            )
            return log.cargo
        }

        let firstStream = HistoryLogStreamResponse(
            numberOfHistoryLogs: pageOneLogs.count,
            streamId: firstAck.streamId,
            historyLogStreamBytes: pageOneLogs
        )

        let secondStream = HistoryLogStreamResponse(
            numberOfHistoryLogs: pageTwoLogs.count,
            streamId: secondAck.streamId,
            historyLogStreamBytes: pageTwoLogs
        )

        let eventsExpectation = expectation(description: "Paginated events delivered")
        eventsExpectation.expectedFulfillmentCount = 2
        delegate.onPumpEvents = { events in
            if !events.isEmpty {
                eventsExpectation.fulfill()
            }
        }

        var historyRequestCount = 0
        mockComm.onSend = { message in
            guard message is HistoryLogRequest else { return }
            historyRequestCount += 1
            if historyRequestCount == 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let metadata = MessageRegistry.metadata(for: firstStream)
                    manager.pumpComm(
                        mockComm,
                        didReceive: firstStream,
                        metadata: metadata,
                        characteristic: .HISTORY_LOG_CHARACTERISTICS,
                        txId: 0x02
                    )
                }
            } else if historyRequestCount == 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let metadata = MessageRegistry.metadata(for: secondStream)
                    manager.pumpComm(
                        mockComm,
                        didReceive: secondStream,
                        metadata: metadata,
                        characteristic: .HISTORY_LOG_CHARACTERISTICS,
                        txId: 0x03
                    )
                }
            }
        }

        manager.updateTransport(transport)
        wait(for: [eventsExpectation], timeout: 2.0)

        XCTAssertEqual(delegate.pumpEventBatches.count, 2)
        XCTAssertEqual(delegate.pumpEventBatches.flatMap { $0 }.count, 18)

        let restoredState = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.rawState))
        XCTAssertEqual(restoredState.nextHistorySequence, 98)
        XCTAssertEqual(restoredState.lastReconciliation, delegate.pumpEventBatches.flatMap { $0 }.map { $0.date }.max())
    }
}
