@testable import TandemKit
import XCTest

final class CartridgeFilledHistoryLogTests: XCTestCase {
    func testCartridgeFilledHistoryLog() {
        // long insulinDisplay, float insulinActual
        let expected = CartridgeFilledHistoryLog(
            pumpTimeSec: 0,
            sequenceNum: 0,
            insulinDisplay: 180,
            insulinActual: 185.63852
        )

        let parsedRes = HistoryLogMessageTester.testSingleIgnoringBaseFields(
            "2100fb59951a35c60200b400000076a339430000000000000000",
            expected
        )
        MessageTester.assertHexEquals(
            expected.cargo,
            HistoryLogMessageTester.cargoIgnoringBaseFields(parsedRes)
        )
    }
}
