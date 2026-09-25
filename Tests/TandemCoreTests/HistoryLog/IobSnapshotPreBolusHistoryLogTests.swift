@testable import TandemKit
import XCTest

final class IobSnapshotPreBolusHistoryLogTests: XCTestCase {
    func testMobiMudaliarDisplayed() {
        let expected = IobSnapshotPreBolusHistoryLog(
            pumpTimeSec: 589529231,
            sequenceNum: 640844,
            bolusId: 2904,
            unknownU8At12: 1,
            selectedIob: 0,
            mudaliarIob: Float(bitPattern: 0x3f3fe725),
            swan6hrIob: Float(bitPattern: 0x3f206f16),
            unknownFloatAt22: Float(bitPattern: 0x3ec8f713)
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle("ce108f8023234cc70900580b010025e73f3f166f203f13f7c83e", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.bolusId, 2904)
        XCTAssertEqual(parsed.selectedIobType, .mudaliarIOB)
        XCTAssertEqual(parsed.mudaliarIob.bitPattern, 0x3f3fe725)
        XCTAssertEqual(parsed.swan6hrIob.bitPattern, 0x3f206f16)
        XCTAssertEqual(parsed.unknownFloatAt22.bitPattern, 0x3ec8f713)
    }

    // A ControlIQIOBResponse 16 s later read mudaliarIOB 2500 / swan6hrIOB 2462; BolusActivated carries the Swan value.
    func testX2SwanDisplayed() {
        let expected = IobSnapshotPreBolusHistoryLog(
            pumpTimeSec: 503759752,
            sequenceNum: 2108107,
            bolusId: 10673,
            unknownU8At12: 3,
            selectedIob: 1,
            mudaliarIob: Float(bitPattern: 0x40200001),
            swan6hrIob: Float(bitPattern: 0x401d9425),
            unknownFloatAt22: Float(bitPattern: 0x401c2104)
        )

        let parsed = HistoryLogMessageTester.testSingle("ce0088c3061ecb2a2000b12903010100204025941d4004211c40", expected)
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(parsed.selectedIobType, .swanIOBMeal)

        let activated = HistoryLogParser.parse(Data(hexadecimalString: "370098c3061ed82a2000b129010025941d40cdcc4c3d00000000")!) as? BolusActivatedHistoryLog
        XCTAssertEqual(activated?.iob.bitPattern, parsed.swan6hrIob.bitPattern)
    }
}
