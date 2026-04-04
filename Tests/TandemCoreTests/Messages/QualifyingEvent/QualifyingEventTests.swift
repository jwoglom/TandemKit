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

    func testGroupSuggestedHandlersAlarmIncludesAamRequests() async {
        let messages = await MainActor.run { QualifyingEvent.groupSuggestedHandlers([.alarm]) }

        XCTAssertEqual(
            messageClasses(messages),
            messageClasses([AlarmStatusRequest.self, HighestAamRequest.self, ActiveAamBitsRequest.self])
        )

        XCTAssertTrue(messages.contains(where: { message in
            guard let aamRequest = message as? ActiveAamBitsRequest else {
                return false
            }
            return aamRequest.cargo == Data([2])
        }))
    }

    func testGroupSuggestedHandlersGlobalPumpSettingsUsesCurrentStatusRequests() async {
        let messages = await MainActor.run { QualifyingEvent.groupSuggestedHandlers([.globalPumpSettings]) }

        XCTAssertEqual(
            messageClasses(messages),
            messageClasses([
                GlobalMaxBolusSettingsRequest.self,
                BasalLimitSettingsRequest.self,
                LocalizationRequest.self,
                PumpGlobalsRequest.self,
                PumpSettingsRequest.self
            ])
        )
    }

    func testGroupSuggestedHandlersPumpingStatusUsesLoadStatus() async {
        let messages = await MainActor.run { QualifyingEvent.groupSuggestedHandlers([.pumpingStatus]) }
        XCTAssertEqual(messageClasses(messages), messageClasses([LoadStatusRequest.self]))
    }

    private func messageClasses(_ messages: [Message]) -> Set<ObjectIdentifier> {
        Set(messages.map { ObjectIdentifier(type(of: $0)) })
    }

    private func messageClasses(_ messageTypes: [Message.Type]) -> Set<ObjectIdentifier> {
        Set(messageTypes.map(ObjectIdentifier.init))
    }
}
