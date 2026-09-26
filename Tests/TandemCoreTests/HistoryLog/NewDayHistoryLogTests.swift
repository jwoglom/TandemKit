@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `NewDayHistoryLogTest`.
final class NewDayHistoryLogTests: XCTestCase {
    func testNewDayHistoryLog1() {
        let expected = NewDayHistoryLog(
            // pumpTimeSec, sequenceNum, commandedBasalRate, featuresBitmask, featureBitmaskIndex
            pumpTimeSec: 580_521_600, sequenceNum: 480_602, commandedBasalRate: 3.4590001, featuresBitmask: 1_986_368_786, featureBitmaskIndex: 93
        ).withHeaderHighNibble(1)

        let parsedRes: NewDayHistoryLog = HistoryLogMessageTester.testSingle(
            "5a10800e9a225a55070042605d40129565765d00000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(
            parsedRes.primaryFeatures,
            [.DEXCOM_G6_SUPPORTED, .CONTROL_IQ_SUPPORTED, .WOMBAT_SUPPORTED, .BASAL_LIMIT_SUPPORTED,
             .AUTO_POP_SUPPORTED, .BLE_PUMP_CONTROL_SUPPORTED, .PUMP_SETTINGS_IN_IDP_GUI_SUPPORTED]
        )
        XCTAssertEqual(
            parsedRes.supportedFeatureIndices,
            [.mainFeatures, .controlFeatures, .controlIqFeatures, .dexcomFeatures, .secondaryFeatures]
        )
    }

    func testNewDayHistoryLog2() {
        let expected = NewDayHistoryLog(
            // pumpTimeSec, sequenceNum, commandedBasalRate, featuresBitmask, featureBitmaskIndex
            pumpTimeSec: 580_694_400, sequenceNum: 487_757, commandedBasalRate: 0.0, featuresBitmask: 1_986_368_786, featureBitmaskIndex: 93
        ).withHeaderHighNibble(1)

        let parsedRes: NewDayHistoryLog = HistoryLogMessageTester.testSingle(
            "5a1080b19c224d71070000000000129565765d00000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
    }

    // Maintainer's t:slim X2 (2024, API 3.4).
    func testNewDayHistoryLogX2SupportedFeatureIndices() {
        let expected = NewDayHistoryLog(
            pumpTimeSec: 534_384_000, sequenceNum: 1_060_003, commandedBasalRate: 0.8, featuresBitmask: 1_982_127_514, featureBitmaskIndex: 125
        )

        let parsedRes: NewDayHistoryLog = HistoryLogMessageTester.testSingle(
            "5a00800dda1fa32c1000cdcc4c3f9add24767d00000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(
            parsedRes.primaryFeatures,
            [.DEXCOM_G6_SUPPORTED, .CONTROL_IQ_SUPPORTED, .BASAL_LIMIT_SUPPORTED, .AUTO_POP_SUPPORTED,
             .BLE_PUMP_CONTROL_SUPPORTED, .PUMP_SETTINGS_IN_IDP_GUI_SUPPORTED]
        )
        XCTAssertEqual(
            parsedRes.supportedFeatureIndices,
            [.mainFeatures, .controlFeatures, .controlIqFeatures, .dexcomFeatures, .abbottFeatures, .secondaryFeatures]
        )
    }

    // Maintainer's t:slim X2 (2022, API 2.5), which does not support the Control-IQ index (3).
    func testNewDayHistoryLogOlderX2FirmwareIndices() {
        let expected = NewDayHistoryLog(
            pumpTimeSec: 461_462_400, sequenceNum: 23508, commandedBasalRate: 0.0, featuresBitmask: 1_982_127_514, featureBitmaskIndex: 21
        )

        let parsedRes: NewDayHistoryLog = HistoryLogMessageTester.testSingle(
            "5a00805b811bd45b0000000000009add24761500000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsedRes.cargo)
        XCTAssertEqual(parsedRes.supportedFeatureIndices, [.mainFeatures, .controlFeatures, .dexcomFeatures])
    }
}
