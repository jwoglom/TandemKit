import Foundation
@testable import TandemCore
@testable import TandemKit
import XCTest

final class HistoryFetchSessionTests: XCTestCase {
    func testFetchCollectsStreamedLogs() throws {
        let peripheral = MockPeripheralManager()
        let transport = MockPumpMessageTransport(peripheralManager: peripheral)
        let pumpComm = MockPumpComm(pumpState: nil)
        let status = HistoryLogStatusResponse(numEntries: 3, firstSequenceNum: 10, lastSequenceNum: 12)
        peripheral.enqueueResponse(for: HistoryLogStatusRequest.self, response: status)
        peripheral.enqueueResponse(for: HistoryLogRequest.self, response: HistoryLogResponse(status: 0, streamId: 7))

        let session = HistoryFetchSession(transport: transport, pumpComm: pumpComm, startSequence: nil, maxEntries: 3, streamTimeout: 2)

        let logA = BolusActivatedHistoryLog(pumpTimeSec: 100, sequenceNum: 10, bolusId: 1, iob: 0.5, bolusSize: 1.0)
        let logB = BolusActivatedHistoryLog(pumpTimeSec: 110, sequenceNum: 11, bolusId: 2, iob: 0.5, bolusSize: 1.0)
        let logC = BolusActivatedHistoryLog(pumpTimeSec: 120, sequenceNum: 12, bolusId: 3, iob: 0.5, bolusSize: 1.0)
        let response1 = HistoryLogStreamResponse(numberOfHistoryLogs: 2, streamId: 7, historyLogStreamBytes: [logB.cargo, logA.cargo])
        let response2 = HistoryLogStreamResponse(numberOfHistoryLogs: 1, streamId: 7, historyLogStreamBytes: [logC.cargo])

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            session.handleStreamResponse(response1)
            session.handleStreamResponse(response2)
        }

        let logs = try session.fetch()

        XCTAssertEqual(logs.map(\.sequenceNum), [10, 11, 12])
    }

    func testStreamTimeoutForMismatchedStreamId() throws {
        let peripheral = MockPeripheralManager()
        let transport = MockPumpMessageTransport(peripheralManager: peripheral)
        let pumpComm = MockPumpComm(pumpState: nil)
        let status = HistoryLogStatusResponse(numEntries: 1, firstSequenceNum: 5, lastSequenceNum: 5)
        peripheral.enqueueResponse(for: HistoryLogStatusRequest.self, response: status)
        peripheral.enqueueResponse(for: HistoryLogRequest.self, response: HistoryLogResponse(status: 0, streamId: 2))

        let session = HistoryFetchSession(transport: transport, pumpComm: pumpComm, startSequence: nil, maxEntries: 1, streamTimeout: 0.1)

        let log = BolusActivatedHistoryLog(pumpTimeSec: 90, sequenceNum: 5, bolusId: 9, iob: 0, bolusSize: 0.5)
        let wrongStream = HistoryLogStreamResponse(numberOfHistoryLogs: 1, streamId: 3, historyLogStreamBytes: [log.cargo])

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
            session.handleStreamResponse(wrongStream)
        }

        XCTAssertThrowsError(try session.fetch()) { error in
            XCTAssertEqual(error as? HistoryFetchError, .streamTimeout(expected: 1, received: 0))
        }
    }

    func testReturnsEmptyWhenStartBeyondLast() throws {
        let peripheral = MockPeripheralManager()
        let transport = MockPumpMessageTransport(peripheralManager: peripheral)
        let pumpComm = MockPumpComm(pumpState: nil)
        let status = HistoryLogStatusResponse(numEntries: 2, firstSequenceNum: 1, lastSequenceNum: 2)
        peripheral.enqueueResponse(for: HistoryLogStatusRequest.self, response: status)

        let session = HistoryFetchSession(transport: transport, pumpComm: pumpComm, startSequence: 5, maxEntries: 2, streamTimeout: 0.1)

        let logs = try session.fetch()

        XCTAssertTrue(logs.isEmpty)
        XCTAssertEqual(peripheral.sentMessages.map { type(of: $0) }, [HistoryLogStatusRequest.self])
    }
}
