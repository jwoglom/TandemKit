@testable import TandemKit
import XCTest

final class QualifyingEventTests: XCTestCase {
    func testFromBitmaskMultiple() {
        let mask: UInt32 = QualifyingEvent.alert.id | QualifyingEvent.alarm.id | QualifyingEvent.bolusPermissionRevoked.id
        let events = QualifyingEvent.fromBitmask(mask)
        XCTAssertTrue(events.contains(.alert))
        XCTAssertTrue(events.contains(.alarm))
        XCTAssertTrue(events.contains(.bolusPermissionRevoked))
        XCTAssertEqual(events.count, 3)
    }

    func testQualifyingEventMaskIncludesActiveProfileSegmentChange() {
        let events = QualifyingEvent.fromRawBytes(Data(hexadecimalString: "210c5000")!)
        XCTAssertEqual(events, [.homeScreenChange, .alert, .bolusChange, .iobChange, .activeProfileSegmentChange, .controlIQInfo])
    }

    func testQualifyingEventMaskIncludesPumpingStatusBit() {
        let events = QualifyingEvent.fromRawBytes(Data(hexadecimalString: "00000404")!)
        XCTAssertEqual(events, [.remainingInsulin, .pumpingStatus])
    }

    func testQualifyingEventNewBits() {
        XCTAssertEqual(QualifyingEvent.fromRawBytes(Data(hexadecimalString: "00000001")!), [.globalPumpSettings])
        XCTAssertEqual(QualifyingEvent.fromRawBytes(Data(hexadecimalString: "00000002")!), [.snoozeStatus])
        XCTAssertEqual(QualifyingEvent.fromRawBytes(Data(hexadecimalString: "00000004")!), [.pumpingStatus])
        XCTAssertEqual(QualifyingEvent.fromRawBytes(Data(hexadecimalString: "00000008")!), [.pumpReset])
        XCTAssertEqual(QualifyingEvent.fromRawBytes(Data(hexadecimalString: "00000010")!), [.heartbeat])
    }
}
