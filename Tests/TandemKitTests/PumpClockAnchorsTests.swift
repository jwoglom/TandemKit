@testable import TandemKit
import XCTest

final class PumpClockAnchorsTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let serial: UInt32 = 1_234_567

    private func anchor(_ sequenceNum: UInt32, minute: Int, pumpAhead: Int = 0) -> PumpClockAnchor {
        PumpClockAnchor(
            sequenceNum: sequenceNum,
            pumpTimeSec: UInt32(600_000_000 + minute * 60 + pumpAhead),
            phoneDate: t0.addingTimeInterval(TimeInterval(minute * 60))
        )
    }

    func testOfARunOnOneUntouchedClockOnlyTheFirstAndLastAnchorsStay() {
        var anchors = PumpClockAnchors()
        for minute in stride(from: 0, through: 60, by: 5) {
            anchors.record(anchor(UInt32(100 + minute), minute: minute), pumpSerial: serial)
        }

        XCTAssertEqual(anchors.anchors, [anchor(100, minute: 0), anchor(160, minute: 60)])
    }

    func testTheAnchorsEitherSideOfAClockChangeBothStay() {
        var anchors = PumpClockAnchors()
        for minute in [0, 5, 10] {
            anchors.record(anchor(UInt32(100 + minute), minute: minute), pumpSerial: serial)
        }
        for minute in [15, 20, 25] {
            anchors.record(anchor(UInt32(100 + minute), minute: minute, pumpAhead: 3600), pumpSerial: serial)
        }

        XCTAssertEqual(anchors.anchors, [
            anchor(100, minute: 0),
            anchor(110, minute: 10),
            anchor(115, minute: 15, pumpAhead: 3600),
            anchor(125, minute: 25, pumpAhead: 3600)
        ])
    }

    func testAClockThatCreepsPastTheToleranceInSmallStepsKeepsAnAnchorWhereItDoes() {
        var anchors = PumpClockAnchors()
        for step in 0 ... 4 {
            anchors.record(anchor(UInt32(100 + step), minute: step * 5, pumpAhead: step * 25), pumpSerial: serial)
        }

        XCTAssertEqual(anchors.anchors.map(\.sequenceNum), [100, 102, 104])
    }

    func testAnchorsOlderThanTheReportingHorizonAreDropped() {
        var anchors = PumpClockAnchors()
        anchors.record(anchor(100, minute: 0), pumpSerial: serial)
        anchors.record(anchor(200, minute: 10, pumpAhead: 3600), pumpSerial: serial)
        anchors.record(anchor(900, minute: 24 * 60 + 5, pumpAhead: 3600), pumpSerial: serial)

        XCTAssertEqual(anchors.anchors.map(\.sequenceNum), [200, 900])
    }

    func testAnotherPumpOrARestartedLogStartsTheAnchorsOver() {
        var anchors = PumpClockAnchors()
        anchors.record(anchor(100, minute: 0), pumpSerial: serial)
        anchors.record(anchor(200, minute: 10, pumpAhead: 3600), pumpSerial: serial)

        var replaced = anchors
        replaced.record(anchor(40, minute: 20), pumpSerial: serial + 1)
        XCTAssertEqual(replaced.anchors.map(\.sequenceNum), [40])
        XCTAssertTrue(replaced.anchors(pumpSerial: serial).isEmpty)

        var erased = anchors
        erased.record(anchor(3, minute: 20, pumpAhead: 3600), pumpSerial: serial)
        XCTAssertEqual(erased.anchors.map(\.sequenceNum), [3])
    }

    func testAnchorsSurviveARawValueRoundTrip() throws {
        var anchors = PumpClockAnchors()
        anchors.record(anchor(100, minute: 0), pumpSerial: serial)
        anchors.record(anchor(200, minute: 10, pumpAhead: 3600), pumpSerial: serial)

        XCTAssertEqual(try XCTUnwrap(PumpClockAnchors(rawValue: anchors.rawValue)), anchors)
    }

    func testTwoReadsOfAnUntouchedClockAgreeAndOnesEitherSideOfAChangeDoNot() {
        let before = PumpClockReading(pumpTimeSec: 600_000_000, phoneDate: t0)

        XCTAssertTrue(before.agrees(with: PumpClockReading(pumpTimeSec: 600_000_042, phoneDate: t0.addingTimeInterval(40))))
        XCTAssertFalse(before.agrees(with: PumpClockReading(pumpTimeSec: 600_000_000, phoneDate: t0.addingTimeInterval(40))))
        XCTAssertFalse(before.agrees(with: PumpClockReading(pumpTimeSec: 600_003_640, phoneDate: t0.addingTimeInterval(40))))
        XCTAssertEqual(before.carried(to: t0.addingTimeInterval(12)), PumpClockReading(pumpTimeSec: 600_000_012, phoneDate: t0.addingTimeInterval(12)))
    }
}
