import XCTest
@testable import TandemCore

final class QualifyingEventTests: XCTestCase {
    func testFromBitmaskMultiple() {
        let mask: UInt32 = QualifyingEvent.alert.id | QualifyingEvent.alarm.id | QualifyingEvent.bolusPermissionRevoked.id
        let events = QualifyingEvent.fromBitmask(mask)
        XCTAssertTrue(events.contains(.alert))
        XCTAssertTrue(events.contains(.alarm))
        XCTAssertTrue(events.contains(.bolusPermissionRevoked))
        XCTAssertEqual(events.count, 3)
    }

    @MainActor
    func testSuggestedHandlersAlert() {
        let handlers = QualifyingEvent.alert.suggestedHandlers
        XCTAssertEqual(handlers.count, 1)
        let msg = handlers[0]()
        XCTAssertTrue(msg is AlertStatusRequest)
    }

    @MainActor
    func testGroupSuggestedHandlersDeduplicates() {
        let events: Set<QualifyingEvent> = [.pumpSuspend, .pumpResume]
        let messages = QualifyingEvent.groupSuggestedHandlers(events)
        // InsulinStatusRequest should only appear once
        let opcodes = messages.map { type(of: $0).props.opCode }
        XCTAssertEqual(opcodes.count, Set(opcodes).count)
        XCTAssertTrue(opcodes.contains(InsulinStatusRequest.props.opCode))
    }
}
