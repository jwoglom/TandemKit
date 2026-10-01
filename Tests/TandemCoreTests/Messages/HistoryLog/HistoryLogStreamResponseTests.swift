@testable import TandemKit
import XCTest

final class HistoryLogStreamResponseTests: XCTestCase {
    func testHistoryLogStreamResponseId90() {
        let expected = HistoryLogStreamResponse(
            numberOfHistoryLogs: 1,
            streamId: 4,
            historyLogStreamBytes: [javaBytes([90, 0, -128, 13, -108, 26, 0, 0, 0, 0, 0, 0, 0, 0, -102, -35, 32, 2, 0, 0, 0, 0, 0, 0, 0, 0])]
        )

        let parsed: HistoryLogStreamResponse = MessageTester.test(
            "000081001c01045a00800d941a00000000000000009add200200000000000000004834",
            0,
            2,
            .HISTORY_LOG_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.numberOfHistoryLogs)
        XCTAssertEqual(4, parsed.streamId)
        XCTAssertEqual(expected.historyLogStreamBytes, parsed.historyLogStreamBytes)
        XCTAssertEqual(90, Bytes.readShort(parsed.cargo, 2))
        XCTAssertEqual(90, parsed.historyLogStreamBytes.first.map { Bytes.readShort($0, 0) })
    }

    func testHistoryLogStreamResponseId23() {
        let expected = HistoryLogStreamResponse(
            numberOfHistoryLogs: 1,
            streamId: 10,
            historyLogStreamBytes: [javaBytes([23, 0, 43, -55, -77, 26, 53, 11, 0, 0, 100, 0, 0, 0, 100, 0, 0, 0, 1, 0, 0, 0, -11, 118, 92, 0])]
        )

        let parsed: HistoryLogStreamResponse = MessageTester.test(
            "000081001c010a17002bc9b31a350b0000640000006400000001000000f5765c003b5c",
            0,
            2,
            .HISTORY_LOG_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.numberOfHistoryLogs)
        XCTAssertEqual(10, parsed.streamId)
        XCTAssertEqual(expected.historyLogStreamBytes, parsed.historyLogStreamBytes)
        XCTAssertEqual(23, Bytes.readShort(parsed.cargo, 2))
        XCTAssertEqual(23, parsed.historyLogStreamBytes.first.map { Bytes.readShort($0, 0) })
    }

    func testHistoryLogStreamResponseId17() {
        let expected = HistoryLogStreamResponse(
            numberOfHistoryLogs: 1,
            streamId: 11,
            historyLogStreamBytes: [javaBytes([17, 0, 84, -55, -77, 26, 54, 11, 0, 0, 3, 24, 93, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])]
        )

        let parsed: HistoryLogStreamResponse = MessageTester.test(
            "000081001c010b110054c9b31a360b000003185d000100000000000000000000006e81",
            0,
            2,
            .HISTORY_LOG_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.numberOfHistoryLogs)
        XCTAssertEqual(11, parsed.streamId)
        XCTAssertEqual(expected.historyLogStreamBytes, parsed.historyLogStreamBytes)
        XCTAssertEqual(17, Bytes.readShort(parsed.cargo, 2))
        XCTAssertEqual(17, parsed.historyLogStreamBytes.first.map { Bytes.readShort($0, 0) })
    }

    func testHistoryLogStreamResponseId17_2() {
        let expected = HistoryLogStreamResponse(
            numberOfHistoryLogs: 1,
            streamId: 12,
            historyLogStreamBytes: [javaBytes([17, 0, 85, -55, -77, 26, 55, 11, 0, 0, -61, 24, 93, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])]
        )

        let parsed: HistoryLogStreamResponse = MessageTester.test(
            "000081001c010c110055c9b31a370b0000c3185d00000000000000000000000000c06e",
            0,
            2,
            .HISTORY_LOG_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.numberOfHistoryLogs)
        XCTAssertEqual(12, parsed.streamId)
        XCTAssertEqual(expected.historyLogStreamBytes, parsed.historyLogStreamBytes)
        XCTAssertEqual(17, Bytes.readShort(parsed.cargo, 2))
        XCTAssertEqual(17, parsed.historyLogStreamBytes.first.map { Bytes.readShort($0, 0) })
    }

    func testHistoryLogStreamResponseId22() {
        let expected = HistoryLogStreamResponse(
            numberOfHistoryLogs: 1,
            streamId: 13,
            historyLogStreamBytes: [javaBytes([22, 0, 86, -55, -77, 26, 56, 11, 0, 0, 100, 0, 0, 0, 100, 0, 0, 0, 1, 0, 0, 0, -17, 29, 93, 0])]
        )

        let parsed: HistoryLogStreamResponse = MessageTester.test(
            "000081001c010d160056c9b31a380b0000640000006400000001000000ef1d5d00a77d",
            0,
            2,
            .HISTORY_LOG_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.numberOfHistoryLogs)
        XCTAssertEqual(13, parsed.streamId)
        XCTAssertEqual(expected.historyLogStreamBytes, parsed.historyLogStreamBytes)
        XCTAssertEqual(22, Bytes.readShort(parsed.cargo, 2))
        XCTAssertEqual(22, parsed.historyLogStreamBytes.first.map { Bytes.readShort($0, 0) })
    }

    func testHistoryLogStreamResponseId10() {
        let expected = HistoryLogStreamResponse(
            numberOfHistoryLogs: 1,
            streamId: 14,
            historyLogStreamBytes: [javaBytes([10, 0, 87, -55, -77, 26, 57, 11, 0, 0, 1, 3, 0, 0, -33, 30, 93, 0, 1, 32, 93, 0, 52, 33, 93, 0])]
        )

        let parsed: HistoryLogStreamResponse = MessageTester.test(
            "000081001c010e0a0057c9b31a390b000001030000df1e5d0001205d0034215d000c57",
            0,
            2,
            .HISTORY_LOG_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.numberOfHistoryLogs)
        XCTAssertEqual(14, parsed.streamId)
        XCTAssertEqual(expected.historyLogStreamBytes, parsed.historyLogStreamBytes)
        XCTAssertEqual(10, Bytes.readShort(parsed.cargo, 2))
        XCTAssertEqual(10, parsed.historyLogStreamBytes.first.map { Bytes.readShort($0, 0) })
    }

    func testHistoryLogStreamResponseId81() {
        let expected = HistoryLogStreamResponse(
            numberOfHistoryLogs: 1,
            streamId: 15,
            historyLogStreamBytes: [javaBytes([81, 0, 95, -55, -77, 26, 58, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 100, 112, 16])]
        )

        let parsed: HistoryLogStreamResponse = MessageTester.test(
            "000081001c010f51005fc9b31a3a0b00000000000000000000000000000164701091ea",
            0,
            2,
            .HISTORY_LOG_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.numberOfHistoryLogs)
        XCTAssertEqual(15, parsed.streamId)
        XCTAssertEqual(expected.historyLogStreamBytes, parsed.historyLogStreamBytes)
        XCTAssertEqual(81, Bytes.readShort(parsed.cargo, 2))
        XCTAssertEqual(81, parsed.historyLogStreamBytes.first.map { Bytes.readShort($0, 0) })
    }

    func testHistoryLogStreamResponse_MultiStream_1() {
        let expected = HistoryLogStreamResponse(
            numberOfHistoryLogs: 3,
            streamId: 8,
            historyLogStreamBytes: [
                Data(hexadecimalString: "07013352331b6e0f000013010000000000000000000000000000")!,
                Data(hexadecimalString: "db002751331b6d0f000000000000000000000000000006000000")!,
                Data(hexadecimalString: "ed002651331b6c0f000000000000000000000000000000000000")!
            ]
        )

        let parsed: HistoryLogStreamResponse = MessageTester.test(
            "0000810050030807013352331b6e0f000013010000000000000000000000000000db002751331b6d0f000000000000000000000000000006000000ed002651331b6c0f000000000000000000000000000000000000c651",
            0,
            5,
            .HISTORY_LOG_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(3, parsed.numberOfHistoryLogs)
        XCTAssertEqual(8, parsed.streamId)
        XCTAssertEqual(expected.historyLogStreamBytes, parsed.historyLogStreamBytes)
    }

    func testHistoryLogStreamResponse_MultiStream_2() {
        let expected = HistoryLogStreamResponse(
            numberOfHistoryLogs: 3,
            streamId: 8,
            historyLogStreamBytes: [
                Data(hexadecimalString: "17012651331b6b0f00000000000000002003ffffffff00000000")!,
                Data(hexadecimalString: "db00fb4f331b6a0f000000000000000000000000000006000000")!,
                Data(hexadecimalString: "1701fa4f331b690f00000000000000002003ffffffff00000000")!
            ]
        )

        let parsed: HistoryLogStreamResponse = MessageTester.test(
            "0000810050030817012651331b6b0f00000000000000002003ffffffff00000000db00fb4f331b6a0f0000000000000000000000000000060000001701fa4f331b690f00000000000000002003ffffffff00000000cfc8",
            0,
            5,
            .HISTORY_LOG_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(3, parsed.numberOfHistoryLogs)
        XCTAssertEqual(8, parsed.streamId)
        XCTAssertEqual(expected.historyLogStreamBytes, parsed.historyLogStreamBytes)
    }

    func testHistoryLogStreamResponse_MultiStream_3() {
        let expected = HistoryLogStreamResponse(
            numberOfHistoryLogs: 3,
            streamId: 8,
            historyLogStreamBytes: [
                Data(hexadecimalString: "db00cf4e331b680f000000000000000000000000000006000000")!,
                Data(hexadecimalString: "1701ce4e331b670f00000000000000002003ffffffff00000000")!,
                Data(hexadecimalString: "08011a4e331b660f0000100100000d0408000000000000000000")!
            ]
        )

        let parsed: HistoryLogStreamResponse = MessageTester.test(
            "00008100500308db00cf4e331b680f0000000000000000000000000000060000001701ce4e331b670f00000000000000002003ffffffff0000000008011a4e331b660f0000100100000d04080000000000000000000614",
            0,
            5,
            .HISTORY_LOG_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(3, parsed.numberOfHistoryLogs)
        XCTAssertEqual(8, parsed.streamId)
        XCTAssertEqual(expected.historyLogStreamBytes, parsed.historyLogStreamBytes)
    }

    func testHistoryLogStreamResponse_MultiStream_4() {
        let expected = HistoryLogStreamResponse(
            numberOfHistoryLogs: 1,
            streamId: 8,
            historyLogStreamBytes: [Data(hexadecimalString: "0801ca4d331b650f0000100100000d0408000000000000000000")!]
        )

        let parsed: HistoryLogStreamResponse = MessageTester.test(
            "000081001c01080801ca4d331b650f0000100100000d0408000000000000000000b442",
            0,
            2,
            .HISTORY_LOG_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(1, parsed.numberOfHistoryLogs)
        XCTAssertEqual(8, parsed.streamId)
        XCTAssertEqual(expected.historyLogStreamBytes, parsed.historyLogStreamBytes)
    }

    func testHistoryLogStreamResponse_MultiStream_5() {
        let expected = HistoryLogStreamResponse(
            numberOfHistoryLogs: 3,
            streamId: 40,
            historyLogStreamBytes: [
                javaBytes([-37, 16, -98, -51, 39, 32, 73, -98, 1, 0, 2, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0]),
                javaBytes([44, 17, -98, -51, 39, 32, 72, -98, 1, 0, -123, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
                javaBytes([34, 17, -98, -51, 39, 32, 71, -98, 1, 0, -39, 19, 40, 32, -124, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
            ]
        )

        let parsed: HistoryLogStreamResponse = MessageTester.test(
            "00008100500328db109ecd2720499e0100020000000200000000000000050000002c119ecd2720489e01008500000000000000000000000000000022119ecd2720479e0100d9132820840000000000000000000000676e",
            0,
            5,
            .HISTORY_LOG_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(3, parsed.numberOfHistoryLogs)
        XCTAssertEqual(40, parsed.streamId)
        XCTAssertEqual(expected.historyLogStreamBytes, parsed.historyLogStreamBytes)
    }

    private func javaBytes(_ bytes: [Int8]) -> Data {
        Data(bytes.map { UInt8(bitPattern: $0) })
    }
}
