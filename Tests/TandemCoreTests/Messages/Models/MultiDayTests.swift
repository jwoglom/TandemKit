@testable import TandemKit
import XCTest

final class MultiDayTests: XCTestCase {
    func testFromBitmask() {
        XCTAssertEqual(MultiDay.fromBitmask(127), Set(MultiDay.allCases))
        XCTAssertEqual(MultiDay.fromBitmask(31), [.monday, .tuesday, .wednesday, .thursday, .friday])
        XCTAssertEqual(MultiDay.fromBitmask(96), [.saturday, .sunday])
        XCTAssertEqual(MultiDay.fromBitmask(97), [.monday, .saturday, .sunday])
        XCTAssertEqual(MultiDay.fromBitmask(2), [.tuesday])
        XCTAssertTrue(MultiDay.fromBitmask(0).isEmpty)
    }

    func testAllDays() {
        XCTAssertEqual(MultiDay.allDays, Set(MultiDay.allCases))
    }

    func testToBitmask() {
        XCTAssertEqual(MultiDay.toBitmask([.saturday, .sunday]), 96)
        XCTAssertEqual(MultiDay.toBitmask(MultiDay.allCases), 127)
        XCTAssertEqual(MultiDay.toBitmask([.monday, .monday]), 1)
        for bitmask in 0 ..< 128 {
            XCTAssertEqual(MultiDay.toBitmask(Array(MultiDay.fromBitmask(bitmask))), bitmask)
        }
    }
}
