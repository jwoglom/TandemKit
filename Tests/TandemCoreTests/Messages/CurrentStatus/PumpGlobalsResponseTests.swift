@testable import TandemKit
import XCTest

final class PumpGlobalsResponseTests: XCTestCase {
    func testPumpGlobalsResponse() {
        let expected = PumpGlobalsResponse(
            quickBolusEnabledRaw: 0,
            quickBolusIncrementUnits: 500,
            quickBolusIncrementCarbs: 2000,
            quickBolusEntryType: 0,
            quickBolusStatus: 0,
            buttonAnnun: PumpGlobalsResponse.AnnunciationEnum.vibrate.rawValue,
            quickBolusAnnun: PumpGlobalsResponse.AnnunciationEnum.audioLow.rawValue,
            generalAnnun: PumpGlobalsResponse.AnnunciationEnum.audioLow.rawValue,
            reminderAnnun: PumpGlobalsResponse.AnnunciationEnum.vibrate.rawValue,
            alertAnnun: PumpGlobalsResponse.AnnunciationEnum.vibrate.rawValue,
            alarmAnnun: PumpGlobalsResponse.AnnunciationEnum.audioLow.rawValue,
            fillTubingAnnun: PumpGlobalsResponse.AnnunciationEnum.audioLow.rawValue
        )

        let parsed: PumpGlobalsResponse = MessageTester.test(
            "000357030e00f401d007000003020203030202050f",
            3,
            2,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.quickBolusEnabledRaw)
        XCTAssertFalse(parsed.isQuickBolusEnabled())
        XCTAssertEqual(500, parsed.quickBolusIncrementUnits)
        XCTAssertEqual(2000, parsed.quickBolusIncrementCarbs)
        XCTAssertEqual(0, parsed.quickBolusEntryType)
        XCTAssertEqual(0, parsed.quickBolusStatus)
        XCTAssertEqual(.vibrate, parsed.buttonAnnouncement)
        XCTAssertEqual(.audioLow, parsed.quickBolusAnnouncement)
        XCTAssertEqual(.audioLow, parsed.generalAnnouncement)
        XCTAssertEqual(.vibrate, parsed.reminderAnnouncement)
        XCTAssertEqual(.vibrate, parsed.alertAnnouncement)
        XCTAssertEqual(.audioLow, parsed.alarmAnnouncement)
        XCTAssertEqual(.audioLow, parsed.fillTubingAnnouncement)
    }
}
