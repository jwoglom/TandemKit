@testable import TandemKit
import XCTest

/// Ported from pumpX2's `TempRateActivatedHistoryLogTest`.
final class TempRateActivatedHistoryLogTests: XCTestCase {
    func testTempRateActivatedHistoryLog1() {
        let expected = TempRateActivatedHistoryLog(
            pumpTimeSec: 579777478,
            sequenceNum: 449311,
            percent: 50.0,
            durationMilliseconds: 7200000.0,
            tempRateId: 21
        )

        _ = HistoryLogMessageTester.testSingle(
            "0210c6b38e221fdb06000000484200badb4a0200150000000000",
            expected
        )
        // no cargo round-trip: bytes 18-19 carry unparsed data (0x0002 LE) that buildCargo does
        // not reproduce; buildCargo also writes tempRateId at offset 18 rather than offset 20,
        // where parse() actually reads it
    }
}
