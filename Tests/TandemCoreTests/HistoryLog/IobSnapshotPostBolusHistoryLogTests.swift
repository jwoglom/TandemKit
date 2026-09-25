@testable import TandemKit
import XCTest

final class IobSnapshotPostBolusHistoryLogTests: XCTestCase {
    func testMobiMudaliarDisplayed() {
        let expected = IobSnapshotPostBolusHistoryLog(
            pumpTimeSec: 589529251,
            sequenceNum: 640860,
            bolusId: 2904,
            unknownU8At12: 1,
            selectedIob: 0,
            mudaliarIob: Float(bitPattern: 0x3f731a58),
            swan6hrIob: Float(bitPattern: 0x3f53a249),
            unknownFloatAt22: Float(bitPattern: 0x3f17aebd)
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("cf10a38023235cc70900580b0100581a733f49a2533fbdae173f", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)

        let completed = HistoryLogParser.parse(Data(hexadecimalString: "1410a38023235dc709000300580b581a733fcdcc4c3ecdcc4c3e")!) as? BolusCompletedHistoryLog
        XCTAssertEqual(completed?.iob.bitPattern, parsed.mudaliarIob.bitPattern)
    }

    func testX2SwanDisplayed() {
        let expected = IobSnapshotPostBolusHistoryLog(
            pumpTimeSec: 503759781,
            sequenceNum: 2108126,
            bolusId: 10673,
            unknownU8At12: 3,
            selectedIob: 1,
            mudaliarIob: Float(bitPattern: 0x40233334),
            swan6hrIob: Float(bitPattern: 0x4020c758),
            unknownFloatAt22: Float(bitPattern: 0x401f5437)
        )

        let parsed = HistoryLogMessageTester.testSingle("cf00a5c3061ede2a2000b12903013433234058c7204037541f40", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)

        let completed = HistoryLogParser.parse(Data(hexadecimalString: "1400a5c3061edf2a20000300b12958c72040cdcc4c3dcdcc4c3d")!) as? BolusCompletedHistoryLog
        XCTAssertEqual(completed?.iob.bitPattern, parsed.swan6hrIob.bitPattern)
    }
}
