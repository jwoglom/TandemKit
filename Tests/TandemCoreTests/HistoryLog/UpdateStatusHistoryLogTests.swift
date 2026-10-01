@testable import TandemKit
import XCTest

/// Byte layout per the Tandem Source event schema for LID_UPDATE_STATUS:
/// swUpdateStatus u16 @0, metadataAndVersionStatus u16 @2, fullDlAndCrcStatus u16 @4,
/// fileDlAndSideloadStatus u16 @6, externalFlashStatus u16 @8, updateSuccessful u8 @10, swPartNum u32 @12.
final class UpdateStatusHistoryLogTests: XCTestCase {
    func testUpdateStatusHistoryLogLayout() {
        let expected = UpdateStatusHistoryLog(
            pumpTimeSec: 566_516_808,
            sequenceNum: 506_706,
            swUpdateStatus: 0x0101,
            metadataAndVersionStatus: 0x0202,
            fullDlAndCrcStatus: 0x0303,
            fileDlAndSideloadStatus: 0x0404,
            externalFlashStatus: 0x0505,
            updateSuccessful: 1,
            swPartNum: 1_009_000
        )
        let rawHex = "cb00485cc42152bb070001010202030304040505010068650f00"
        XCTAssertEqual(rawHex, expected.cargo.hexadecimalString)
        let parsed = HistoryLogMessageTester.testSingle(rawHex, expected)
        XCTAssertEqual(0x0101, parsed.swUpdateStatus)
        XCTAssertEqual(0x0202, parsed.metadataAndVersionStatus)
        XCTAssertEqual(0x0303, parsed.fullDlAndCrcStatus)
        XCTAssertEqual(0x0404, parsed.fileDlAndSideloadStatus)
        XCTAssertEqual(0x0505, parsed.externalFlashStatus)
        XCTAssertEqual(.successful, parsed.updateSuccessfulEnum)
        XCTAssertEqual(1_009_000, parsed.swPartNum)
    }
}
