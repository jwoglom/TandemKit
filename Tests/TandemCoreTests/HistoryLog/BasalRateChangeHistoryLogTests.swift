@testable import TandemKit
import XCTest

/// Ported from pumpX2's `BasalRateChangeHistoryLogTest`.
///
/// The Java test builds `expected` via the short constructor (pumpTimeSec/sequenceNum default to
/// 0) and compares with `testSingleIgnoringBaseFields`, which clears the parsed record's base
/// fields before comparing. The Swift `HistoryLogMessageTester` has no equivalent helper, so this
/// adapts by constructing `expected` with the pump time / sequence number actually encoded in the
/// fixture (decoded independently from the raw bytes) and asserting full equality via `testSingle`
/// instead — an equivalent assertion.
final class BasalRateChangeHistoryLogTests: XCTestCase {
    func testBasalRateChangeHistoryLog_Default() {
        let expected = BasalRateChangeHistoryLog(
            pumpTimeSec: 445993934,
            sequenceNum: 181703,
            commandBasalRate: 0.436,
            baseBasalRate: 0.8,
            maxBasalRate: 5.0,
            insulinDeliveryProfile: 0,
            changeTypeId: 1
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "0300ce53951ac7c50200643bdf3ecdcc4c3f0000a04000000100",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testBasalRateChangeHistoryLog_PumpSuspended() {
        let expected = BasalRateChangeHistoryLog(
            pumpTimeSec: 446031151,
            sequenceNum: 182635,
            commandBasalRate: 0.0,
            baseBasalRate: 1.25,
            maxBasalRate: 5.0,
            insulinDeliveryProfile: 0,
            changeTypeId: 16
        )

        let parsed = HistoryLogMessageTester.testSingle(
            "03002fe5951a6bc90200000000000000a03f0000a04000001000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
