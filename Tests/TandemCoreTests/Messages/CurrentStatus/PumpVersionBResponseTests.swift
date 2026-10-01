@testable import TandemKit
import XCTest

final class PumpVersionBResponseTests: XCTestCase {
    func testPumpVersionBResponse_CapturedMobiPayload() {
        let expected = PumpVersionBResponse(
            softwareName: "Control-IQ+ 7.9.0.2",
            configurationBitsA: 0,
            configurationBitsB: 0,
            serialNumber: 1_485_742,
            modelNumber: 1_004_000,
            pumpRevision: "0",
            pcbPartNumberA: 1_011_004,
            pcbSerialNumberA: 251_300_136,
            pcbRevisionNumberA: "0"
        )

        let parsed: PumpVersionBResponse = MessageTester.test(
            "000685063c436f6e74726f6c2d49512b20372e392e302e32000000000000000000aeab1600e0510f0030000000000000003c6d0f002889fa0e300000000000000013da",
            6,
            4,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual("Control-IQ+ 7.9.0.2", parsed.softwareName)
        XCTAssertEqual(0, parsed.configurationBitsA)
        XCTAssertEqual(0, parsed.configurationBitsB)
        XCTAssertEqual(1_485_742, parsed.serialNumber)
        XCTAssertEqual(1_004_000, parsed.modelNumber)
        XCTAssertEqual("0", parsed.pumpRevision)
        XCTAssertEqual(1_011_004, parsed.pcbPartNumberA)
        XCTAssertEqual(251_300_136, parsed.pcbSerialNumberA)
        XCTAssertEqual("0", parsed.pcbRevisionNumberA)
    }
}
