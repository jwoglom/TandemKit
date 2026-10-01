@testable import TandemKit
import XCTest

final class UInt32HexadecimalStringTests: XCTestCase {
    func testZeroIsEightZeroDigits() {
        XCTAssertEqual(UInt32(0).hexadecimalString, "0x00000000")
    }

    func testOneIsPaddedOnTheLeft() {
        XCTAssertEqual(UInt32(1).hexadecimalString, "0x00000001")
    }

    func testAMidValueIsPaddedOnTheLeft() {
        XCTAssertEqual(UInt32(0x0001_E240).hexadecimalString, "0x0001e240")
    }

    func testTheLargestValueFillsAllEightDigits() {
        XCTAssertEqual(UInt32.max.hexadecimalString, "0xffffffff")
    }
}
