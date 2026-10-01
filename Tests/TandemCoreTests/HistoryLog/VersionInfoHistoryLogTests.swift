@testable import TandemKit
import XCTest

/// Byte layout per the Tandem Source event schema for LID_VERSION_INFO:
/// version u32 @0, configABits u32 @4, configBBits u32 @8, armCrc u16 @12.
final class VersionInfoHistoryLogTests: XCTestCase {
    func testVersionInfoHistoryLogLayout() {
        let expected = VersionInfoHistoryLog(pumpTimeSec: 566_516_808, sequenceNum: 506_706, version: 905_914, configABits: 0x5B, configBBits: 1, armCrc: 0x100A)
        let rawHex = "bf00485cc42152bb0700bad20d005b000000010000000a100000"
        XCTAssertEqual(rawHex, expected.cargo.hexadecimalString)
        let parsed = HistoryLogMessageTester.testSingle(rawHex, expected)
        XCTAssertEqual(905_914, parsed.version)
        XCTAssertEqual(0x5B, parsed.configABits)
        XCTAssertEqual(1, parsed.configBBits)
        XCTAssertEqual(0x100A, parsed.armCrc)
    }
}
