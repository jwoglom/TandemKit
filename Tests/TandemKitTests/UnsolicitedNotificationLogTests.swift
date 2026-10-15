import CoreBluetooth
@testable import TandemKit
import XCTest

final class UnsolicitedNotificationLogTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 700_000_000)
    private let currentStatus = CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS

    private func message(_ opCode: UInt8, txId: UInt8) -> AssembledMessage {
        AssembledMessage(opCode: opCode, txId: txId, payloadLength: 0, cargo: Data([0, 0]))
    }

    private func recordTimedOutApiVersion(_ log: inout UnsolicitedNotificationLog, txId: UInt8, at date: Date) {
        log.recordUnanswered(
            request: "ApiVersionRequest",
            txId: txId,
            responseOpCode: ApiVersionResponse.props.opCode,
            characteristic: currentStatus,
            at: date
        )
    }

    func testMessagesWithinTheQuietGapAreOneBurst() {
        var log = UnsolicitedNotificationLog()
        let gap = UnsolicitedNotificationLog.quietGap

        let kinds = [0, 0.5, 1, gap + 1.5, gap + 2].map {
            log.classify(message(ApiVersionResponse.props.opCode, txId: 9), on: currentStatus, at: start.addingTimeInterval($0))
        }

        XCTAssertEqual(kinds, [.startsBurst, .inBurst(2), .inBurst(3), .startsBurst, .inBurst(2)])
    }

    func testTheAnswerToAWriteThatTimedOutIsItsLateAnswer() {
        var log = UnsolicitedNotificationLog()
        recordTimedOutApiVersion(&log, txId: 4, at: start)

        let kind = log.classify(message(ApiVersionResponse.props.opCode, txId: 4), on: currentStatus, at: start.addingTimeInterval(3))

        XCTAssertEqual(kind, .lateAnswer(request: "ApiVersionRequest", secondsAfterGivingUp: 3))
    }

    func testARefusalUnderTheTxIdOfAWriteThatTimedOutIsItsLateAnswer() {
        var log = UnsolicitedNotificationLog()
        log.recordUnanswered(
            request: "InitiateBolusRequest",
            txId: 4,
            responseOpCode: InitiateBolusResponse.props.opCode,
            characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
            at: start
        )

        let kind = log.classify(message(ErrorResponse.props.opCode, txId: 4), on: currentStatus, at: start.addingTimeInterval(1))

        XCTAssertEqual(kind, .lateAnswer(request: "InitiateBolusRequest", secondsAfterGivingUp: 1))
    }

    func testALateAnswerIsMatchedOnce() {
        var log = UnsolicitedNotificationLog()
        recordTimedOutApiVersion(&log, txId: 4, at: start)
        let answer = message(ApiVersionResponse.props.opCode, txId: 4)

        _ = log.classify(answer, on: currentStatus, at: start.addingTimeInterval(1))

        XCTAssertEqual(log.classify(answer, on: currentStatus, at: start.addingTimeInterval(2)), .startsBurst)
    }

    func testAMessageUnderTheSameTxIdButAnotherOpcodeIsNotTheLateAnswer() {
        var log = UnsolicitedNotificationLog()
        recordTimedOutApiVersion(&log, txId: 4, at: start)

        let kind = log.classify(message(CurrentBasalStatusResponse.props.opCode, txId: 4), on: currentStatus, at: start.addingTimeInterval(1))

        XCTAssertEqual(kind, .startsBurst)
    }

    func testAnAnswerPastTheWindowIsNoLongerTakenAsLate() {
        var log = UnsolicitedNotificationLog()
        recordTimedOutApiVersion(&log, txId: 4, at: start)

        let kind = log.classify(
            message(ApiVersionResponse.props.opCode, txId: 4),
            on: currentStatus,
            at: start.addingTimeInterval(UnsolicitedNotificationLog.lateAnswerWindow + 1)
        )

        XCTAssertEqual(kind, .startsBurst)
    }
}
