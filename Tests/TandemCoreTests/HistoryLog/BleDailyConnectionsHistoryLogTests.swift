@testable import TandemKit
import XCTest

final class BleDailyConnectionsHistoryLogTests: XCTestCase {
    func testBleDailyConnectionsNoUnauthenticatedConnections() {
        // Maintainer's Tandem Mobi (7.9.0.2).
        let expected = BleDailyConnectionsHistoryLog(
            pumpTimeSec: 590716558,
            sequenceNum: 703738,
            connectedPercent: 100,
            unknown11: 6,
            connections: 32,
            unauthenticatedConnections: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "da118e9e3523fabc0a0064062000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(100, parsed.connectedPercent)
        XCTAssertEqual(32, parsed.connections)
        XCTAssertEqual(0, parsed.unauthenticatedConnections)
        XCTAssertEqual(32, parsed.authenticatedConnections)
        XCTAssertEqual(Data(count: 10), parsed.unknownTail)
    }

    func testBleDailyConnectionsMostConnections() {
        // Maintainer's Tandem Mobi (7.9.0.2).
        let expected = BleDailyConnectionsHistoryLog(
            pumpTimeSec: 590543757,
            sequenceNum: 693854,
            connectedPercent: 99,
            unknown11: 6,
            connections: 66,
            unauthenticatedConnections: 3
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "da118dfb32235e960a0063064200030000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(99, parsed.connectedPercent)
        XCTAssertEqual(66, parsed.connections)
        XCTAssertEqual(3, parsed.unauthenticatedConnections)
        XCTAssertEqual(63, parsed.authenticatedConnections)
    }

    func testBleDailyConnectionsLongOutage() {
        // Maintainer's Tandem Mobi (7.9.0.2).
        let expected = BleDailyConnectionsHistoryLog(
            pumpTimeSec: 590802958,
            sequenceNum: 708039,
            connectedPercent: 97,
            unknown11: 6,
            connections: 35,
            unauthenticatedConnections: 5
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "da110ef03623c7cd0a0061062300050000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(97, parsed.connectedPercent)
        XCTAssertEqual(35, parsed.connections)
        XCTAssertEqual(5, parsed.unauthenticatedConnections)
        XCTAssertEqual(30, parsed.authenticatedConnections)
    }

    func testBleDailyConnectionsSingleConnectionAllDay() {
        // Maintainer's Tandem Mobi (7.9.0.1).
        let expected = BleDailyConnectionsHistoryLog(
            pumpTimeSec: 585137729,
            sequenceNum: 629401,
            connectedPercent: 100,
            unknown11: 6,
            connections: 0,
            unauthenticatedConnections: 0
        ).withHeaderHighNibble(1)

        let parsed = HistoryLogMessageTester.testSingle(
            "da11417ee022999a090064060000000000000000000000000000",
            expected
        )
        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(100, parsed.connectedPercent)
        XCTAssertEqual(0, parsed.connections)
        XCTAssertEqual(0, parsed.unauthenticatedConnections)
    }
}
