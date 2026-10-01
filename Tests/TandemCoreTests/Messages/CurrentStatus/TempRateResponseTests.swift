@testable import TandemKit
import XCTest

final class TempRateResponseTests: XCTestCase {
    func testTempRateResponseNotActive() {
        let expected = TempRateResponse(active: false, percentage: 0, startTimeRaw: 0, duration: 0)

        let parsed: TempRateResponse = MessageTester.test(
            "00032b030a0000000000000000000039c6",
            3,
            1,
            .CURRENT_STATUS_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertFalse(parsed.active)
        XCTAssertEqual(0, parsed.percentage)
        XCTAssertEqual(0, parsed.startTimeRaw)
        XCTAssertEqual(0, parsed.duration)
    }

    func testTempRateResponse_values() {
        var r = TempRateResponse(cargo: javaBytes([1, -6, -38, 0, -13, 31, -124, 3, 0, 0]))
        XCTAssertTrue(r.active)
        XCTAssertEqual(900, r.duration)
        XCTAssertEqual(536_019_162, r.startTimeRaw)
        XCTAssertEqual(250, r.percentage)

        r = TempRateResponse(cargo: javaBytes([1, -11, -99, 5, -13, 31, -124, 3, 0, 0]))
        XCTAssertTrue(r.active)
        XCTAssertEqual(900, r.duration)
        XCTAssertEqual(536_020_381, r.startTimeRaw)
        XCTAssertEqual(245, r.percentage)

        r = TempRateResponse(cargo: javaBytes([1, -56, 57, 5, -13, 31, 8, 7, 0, 0]))
        XCTAssertTrue(r.active)
        XCTAssertEqual(1800, r.duration)
        XCTAssertEqual(536_020_281, r.startTimeRaw)
        XCTAssertEqual(200, r.percentage)
    }

    private func javaBytes(_ bytes: [Int8]) -> Data {
        Data(bytes.map { UInt8(bitPattern: $0) })
    }
}
