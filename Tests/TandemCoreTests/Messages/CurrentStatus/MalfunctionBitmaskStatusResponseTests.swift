@testable import TandemKit
import XCTest

final class MalfunctionBitmaskStatusResponseTests: XCTestCase {
    func testMalfunctionBitmaskStatusResponse_zeroBitmaskFixture() {
        let expected = MalfunctionBitmaskStatusResponse(bitmask: 0)

        let parsed = MalfunctionBitmaskStatusResponse(cargo: Data(hexadecimalString: "0000000000000000")!)

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.bitmask)
        XCTAssertTrue(parsed.malfunctions.isEmpty)
        XCTAssertEqual(0, parsed.notificationCount)
    }

    func testBitmaskDecodesBitPositions() {
        let bitmask: UInt64 = (1 << 0) | (1 << 13) | (1 << 25)
        let response = MalfunctionBitmaskStatusResponse(bitmask: bitmask)

        XCTAssertEqual(bitmask, response.bitmask)
        XCTAssertTrue(response.hasMalfunctionBit(0))
        XCTAssertTrue(response.hasMalfunctionBit(13))
        XCTAssertTrue(response.hasMalfunctionBit(25))
        XCTAssertEqual([.software, .periphPower, .pushoffStall], response.malfunctions)
        XCTAssertEqual(3, response.notificationCount)
        XCTAssertEqual([0, 13, 25], response.notificationIds)
    }

    func testParsedCargoMatchesConstructedResponse() {
        let expected = MalfunctionBitmaskStatusResponse(bitmask: (1 << 0) | (1 << 13) | (1 << 25))
        let parsed = MalfunctionBitmaskStatusResponse(cargo: expected.cargo)

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(expected.malfunctions, parsed.malfunctions)
    }

    func testEveryMalfunctionTypeRoundTripsThroughItsOwnBit() {
        for type in MalfunctionBitmaskStatusResponse.MalfunctionType.allCases {
            let response = MalfunctionBitmaskStatusResponse(bitmask: 1 << UInt64(type.rawValue))
            XCTAssertEqual([type], response.malfunctions, "\(type)")
        }
    }
}
