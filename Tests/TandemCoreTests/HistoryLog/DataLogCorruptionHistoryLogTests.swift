@testable import TandemKit
import XCTest

/// Byte layout per the Tandem Source event schema for LID_DATA_LOG_CORRUPTION: block u32 @0, reason u8 @4.
final class DataLogCorruptionHistoryLogTests: XCTestCase {
    func testDataLogCorruptionHistoryLogLayout() {
        let expected = DataLogCorruptionHistoryLog(pumpTimeSec: 566_516_808, sequenceNum: 506_706, block: 4660, reason: 4)
        let rawHex = "3c00485cc42152bb070034120000040000000000000000000000"
        XCTAssertEqual(rawHex, expected.cargo.hexadecimalString)
        let parsed = HistoryLogMessageTester.testSingle(rawHex, expected)
        XCTAssertEqual(4660, parsed.block)
        XCTAssertEqual(4, parsed.reason)
    }
}
