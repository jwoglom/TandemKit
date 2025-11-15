@testable import TandemCore
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

    func testSuggestedHandlersAlert() async {
        let handlers = await MainActor.run { QualifyingEvent.alert.suggestedHandlers }
        XCTAssertEqual(handlers.count, 1)
        let msg = await MainActor.run { handlers[0]() }
        XCTAssertTrue(msg is AlertStatusRequest)
    }

    func testGroupSuggestedHandlersDeduplicates() async {
        let events: Set<QualifyingEvent> = [.pumpSuspend, .pumpResume]
        let messages = await MainActor.run { QualifyingEvent.groupSuggestedHandlers(events) }
        // InsulinStatusRequest should only appear once
        let opcodes = messages.map { type(of: $0).props.opCode }
        XCTAssertEqual(opcodes.count, Set(opcodes).count)
        XCTAssertTrue(opcodes.contains(InsulinStatusRequest.props.opCode))
    }
}
