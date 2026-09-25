@testable import TandemKit
import XCTest

final class CartridgeFillResponseHistoryLogTests: XCTestCase {
    private func check(_ hex: String, pumpTimeSec: UInt32, sequenceNum: UInt32, responseOpCode: Int, status: Int) {
        let expected = CartridgeFillResponseHistoryLog(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            responseOpCode: responseOpCode,
            status: status
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(hex, expected)
        XCTAssertEqual(pumpTimeSec, parsed.pumpTimeSec)
        XCTAssertEqual(sequenceNum, parsed.sequenceNum)
        XCTAssertEqual(responseOpCode, parsed.responseOpCode)
        XCTAssertEqual(status, parsed.status)
        XCTAssertEqual(0, parsed.unknown11)
        XCTAssertEqual(Data(count: 13), parsed.unknownTail)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testExitChangeCartridgeModeResponse() {
        check("6711e267312376830a0093000000000000000000000000000000", pumpTimeSec: 590440418, sequenceNum: 689014, responseOpCode: 147, status: 0)
    }

    func testEnterFillTubingModeResponse() {
        check("6711e66731237b830a0095000000000000000000000000000000", pumpTimeSec: 590440422, sequenceNum: 689019, responseOpCode: 149, status: 0)
    }

    func testFillCannulaResponse() {
        check("671154683123b4830a0099000000000000000000000000000000", pumpTimeSec: 590440532, sequenceNum: 689076, responseOpCode: 153, status: 0)
    }

    func testExitChangeCartridgeModeResponseFailed() {
        check("6711f325f0201c62090093000100000000000000000000000000", pumpTimeSec: 552609267, sequenceNum: 614940, responseOpCode: 147, status: 1)
    }

    func testUnknownBytesRoundTrip() {
        var tail = Data(count: 13)
        tail[0] = 0x12
        tail[12] = 0x34
        let built = CartridgeFillResponseHistoryLog(
            pumpTimeSec: 1,
            sequenceNum: 2,
            responseOpCode: 145,
            unknown11: 7,
            status: 0,
            unknownTail: tail
        )
        let parsed = CartridgeFillResponseHistoryLog(cargo: built.cargo)
        XCTAssertEqual(145, parsed.responseOpCode)
        XCTAssertEqual(7, parsed.unknown11)
        XCTAssertEqual(0, parsed.status)
        XCTAssertEqual(tail, parsed.unknownTail)
        MessageTester.assertHexEquals(built.cargo, parsed.cargo)
    }
}
