import XCTest
@testable import TandemKit
@testable import TandemCore
import LoopKit

@available(macOS 13.0, iOS 14.0, *)
final class TandemPumpManagerHistoryTests: XCTestCase {
    private var originalPumpTimeSupplier: (() -> UInt32)? = PumpStateSupplier.pumpTimeSinceReset

    override func tearDown() {
        super.tearDown()
        PumpStateSupplier.pumpTimeSinceReset = originalPumpTimeSupplier
    }

    func testHistoryStreamProducesEventsAndReservoirUpdates() {
        let now = Date()
        let pumpSeconds = UInt32(now.timeIntervalSince1970)
        PumpStateSupplier.pumpTimeSinceReset = { pumpSeconds }

        let schedule = BasalRateSchedule(
            items: [
                RepeatingScheduleValue(startTime: 0, value: 0.8),
                RepeatingScheduleValue(startTime: 12 * 60 * 60, value: 1.0)
            ],
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let reservoirStart = SimpleReservoirValue(startDate: now.addingTimeInterval(-3600), unitVolume: 200.0)
        let state = TandemPumpManagerState(
            pumpState: nil,
            lastReservoirReading: reservoirStart,
            basalRateSchedule: schedule
        )

        let manager = TandemPumpManager(state: state)
        manager.delegateQueue = DispatchQueue(label: "delegate.queue")

        let delegate = MockPumpManagerDelegate()
        delegate.detectedSystemTimeOffset = 0
        let eventsExpectation = expectation(description: "history events delivered")
        delegate.pumpEventsExpectation = eventsExpectation
        let reservoirExpectation = expectation(description: "reservoir updated")
        delegate.reservoirExpectation = reservoirExpectation
        manager.pumpManagerDelegate = delegate

        let basePumpTime = pumpSeconds - 120
        let bolusLog = BolusCompletedHistoryLog(
            pumpTimeSec: basePumpTime,
            sequenceNum: 1,
            completionStatusId: 0,
            bolusId: 15,
            iob: 0,
            insulinDelivered: 1.5,
            insulinRequested: 1.5
        )
        let suspendLog = PumpingSuspendedHistoryLog(
            pumpTimeSec: basePumpTime + 30,
            sequenceNum: 2,
            insulinAmount: 0,
            reasonId: 0
        )
        let resumeLog = PumpingResumedHistoryLog(
            pumpTimeSec: basePumpTime + 90,
            sequenceNum: 3,
            insulinAmount: 0
        )
        let alarmLog = AlarmActivatedHistoryLog(
            pumpTimeSec: basePumpTime + 120,
            sequenceNum: 4,
            alarmId: 7
        )

        let stream = HistoryLogStreamResponse(
            numberOfHistoryLogs: 4,
            streamId: 1,
            historyLogStreamBytes: [bolusLog.cargo, suspendLog.cargo, resumeLog.cargo, alarmLog.cargo]
        )

        let metadata = MessageRegistry.metadata(for: stream)
        let pumpComm = PumpComm(pumpState: nil)
        manager.pumpComm(
            pumpComm,
            didReceive: stream,
            metadata: metadata,
            characteristic: .HISTORY_LOG_CHARACTERISTICS,
            txId: 0x01
        )

        wait(for: [eventsExpectation, reservoirExpectation], timeout: 1.0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(delegate.pumpEvents.count, 1)
        let events = delegate.pumpEvents.first ?? []
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.compactMap { $0.type }, [.bolus, .suspend, .resume, .alarm])

        let updatedReservoir = delegate.reservoirUpdates.last?.newValue
        XCTAssertEqual(updatedReservoir?.unitVolume ?? 0, 198.5, accuracy: 0.01)

        if case .active(let resumeDate)? = manager.status.basalDeliveryState {
            let offset = now.timeIntervalSince1970 - TimeInterval(pumpSeconds)
            let expectedResume = Date(timeIntervalSince1970: offset + TimeInterval(basePumpTime + 120))
            XCTAssertEqual(resumeDate.timeIntervalSince1970, expectedResume.timeIntervalSince1970, accuracy: 1.0)
        } else {
            XCTFail("Expected pump to resume after history processing")
        }

        if let lastSync = manager.lastSync {
            let offset = now.timeIntervalSince1970 - TimeInterval(pumpSeconds)
            let expected = Date(timeIntervalSince1970: offset + TimeInterval(basePumpTime + 120))
            XCTAssertEqual(lastSync.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0)
        } else {
            XCTFail("Expected reconciliation date to be recorded")
        }
    }

    func testDuplicateHistoryStreamDoesNotReissueEvents() {
        let now = Date()
        let pumpSeconds = UInt32(now.timeIntervalSince1970)
        PumpStateSupplier.pumpTimeSinceReset = { pumpSeconds }

        let state = TandemPumpManagerState(pumpState: nil)
        let manager = TandemPumpManager(state: state)
        manager.delegateQueue = DispatchQueue(label: "delegate.queue")

        let delegate = MockPumpManagerDelegate()
        delegate.detectedSystemTimeOffset = 0
        let eventsExpectation = expectation(description: "first history events delivered")
        delegate.pumpEventsExpectation = eventsExpectation
        manager.pumpManagerDelegate = delegate

        let basePumpTime = pumpSeconds - 60
        let bolusLog = BolusCompletedHistoryLog(
            pumpTimeSec: basePumpTime,
            sequenceNum: 10,
            completionStatusId: 0,
            bolusId: 22,
            iob: 0,
            insulinDelivered: 1.0,
            insulinRequested: 1.0
        )
        let stream = HistoryLogStreamResponse(
            numberOfHistoryLogs: 1,
            streamId: 2,
            historyLogStreamBytes: [bolusLog.cargo]
        )

        let metadata = MessageRegistry.metadata(for: stream)
        let pumpComm = PumpComm(pumpState: nil)
        manager.pumpComm(
            pumpComm,
            didReceive: stream,
            metadata: metadata,
            characteristic: .HISTORY_LOG_CHARACTERISTICS,
            txId: 0x02
        )

        wait(for: [eventsExpectation], timeout: 1.0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        let initialEventCount = delegate.pumpEvents.count
        delegate.pumpEventsExpectation = nil

        manager.pumpComm(
            pumpComm,
            didReceive: stream,
            metadata: metadata,
            characteristic: .HISTORY_LOG_CHARACTERISTICS,
            txId: 0x03
        )

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(delegate.pumpEvents.count, initialEventCount)
        let restoredState = XCTAssertNoThrowWithResult(try TandemPumpManagerState(rawValue: manager.rawState))
        XCTAssertEqual(restoredState?.recentHistorySequenceNumbers.count, 1)
    }
}

private func XCTAssertNoThrowWithResult<T>(_ expression: @autoclosure () throws -> T) -> T? {
    do {
        return try expression()
    } catch {
        XCTFail("Unexpected error: \(error)")
        return nil
    }
}
