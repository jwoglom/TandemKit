@testable import TandemKit
import XCTest

final class UsbConnectedHistoryLogTests: XCTestCase {
    func testUsbConnectedHistoryLog1() {
        // float negotiatedCurrentmA
        let expected = UsbConnectedHistoryLog(
            pumpTimeSec: 0,
            sequenceNum: 0,
            negotiatedCurrentmA: 100.0
        )

        let parsedRes = HistoryLogMessageTester.testSingleIgnoringBaseFields(
            "240045e5951a71c902000000c842000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(
            expected.cargo,
            HistoryLogMessageTester.cargoIgnoringBaseFields(parsedRes)
        )
    }
}
