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

    // MARK: - Suggested handlers

    private func requestTypeNames(_ messages: [Message]) -> Set<String> {
        Set(messages.map { String(describing: type(of: $0)) })
    }

    /// An alarm asks for the alarm bitmask plus the highest active alarm and the AAM bits that
    /// corroborate it, matching PumpX2.
    func testSuggestedHandlersForAlarmIncludeAamRequests() {
        let messages = QualifyingEvent.groupSuggestedHandlers([.alarm])

        XCTAssertEqual(requestTypeNames(messages), [
            "AlarmStatusRequest",
            "HighestAamRequest",
            "ActiveAamBitsRequest"
        ])

        let aamRequests = messages.compactMap { $0 as? ActiveAamBitsRequest }
        XCTAssertEqual(aamRequests.map(\.cargo), [Data([2])])
    }

    /// The malfunction variant asks about AAM type 4 rather than 2.
    func testSuggestedHandlersForMalfunctionUseMalfunctionAamType() {
        let messages = QualifyingEvent.groupSuggestedHandlers([.malfunction])

        XCTAssertEqual(requestTypeNames(messages), [
            "MalfunctionStatusRequest",
            "HighestAamRequest",
            "ActiveAamBitsRequest"
        ])

        let aamRequests = messages.compactMap { $0 as? ActiveAamBitsRequest }
        XCTAssertEqual(aamRequests.map(\.cargo), [Data([4])])
    }

    func testSuggestedHandlersForGlobalPumpSettings() {
        let messages = QualifyingEvent.groupSuggestedHandlers([.globalPumpSettings])

        XCTAssertEqual(requestTypeNames(messages), [
            "GlobalMaxBolusSettingsRequest",
            "BasalLimitSettingsRequest",
            "LocalizationRequest",
            "PumpGlobalsRequest",
            "PumpSettingsRequest"
        ])
    }

    func testSuggestedHandlersForPumpingStatusUseLoadStatus() {
        let messages = QualifyingEvent.groupSuggestedHandlers([.pumpingStatus])

        XCTAssertEqual(requestTypeNames(messages), ["LoadStatusRequest"])
    }

    /// Events with no follow-up in the Tandem app ask for nothing at all.
    func testSuggestedHandlersAreEmptyForEventsWithoutFollowUp() {
        for event in [QualifyingEvent.pumpCommunicationsSuspended, .snoozeStatus, .pumpReset, .heartbeat] {
            XCTAssertTrue(
                event.suggestedHandlers().isEmpty,
                "\(event) should have no suggested handlers"
            )
        }
    }

    /// Requests newer than the pump's firmware are dropped: ActiveAamBits needs Mobi v3.5, and
    /// BolusPermissionChangeReason is API_FUTURE, so neither survives a v2.1 pump.
    func testGroupSuggestedHandlersExcludesRequestsNewerThanTheApiVersion() {
        let messages = QualifyingEvent.groupSuggestedHandlers(
            [.alarm, .bolusPermissionRevoked],
            context: QualifyingEventContext(
                apiVersion: KnownApiVersion.apiV2_1.value,
                inProgressBolusId: 42
            )
        )

        XCTAssertEqual(requestTypeNames(messages), ["AlarmStatusRequest", "HighestAamRequest"])
    }

    func testGroupSuggestedHandlersIncludesMobiRequestsOnMobiApi() {
        let messages = QualifyingEvent.groupSuggestedHandlers(
            [.alarm],
            context: QualifyingEventContext(apiVersion: KnownApiVersion.mobiApiV3_5.value)
        )

        XCTAssertEqual(requestTypeNames(messages), [
            "AlarmStatusRequest",
            "HighestAamRequest",
            "ActiveAamBitsRequest"
        ])
    }

    /// Overlapping events must not send the same request twice — homeScreenChange and
    /// basalChange both want the current basal status and the home screen mirror.
    func testGroupSuggestedHandlersDeduplicatesSharedRequests() {
        let messages = QualifyingEvent.groupSuggestedHandlers([.homeScreenChange, .basalChange])
        let names = messages.map { String(describing: type(of: $0)) }

        XCTAssertEqual(names.count, Set(names).count, "expected no duplicate requests, got \(names)")
        XCTAssertEqual(Set(names), [
            "CurrentBasalStatusRequest",
            "CurrentEGVGuiDataRequest",
            "HomeScreenMirrorRequest",
            "ControlIQInfoV1Request",
            "NonControlIQIOBRequest",
            "TempRateRequest"
        ])
    }

    /// The two AAM requests differ only in cargo, so deduplication has to keep both.
    func testGroupSuggestedHandlersKeepsRequestsThatDifferOnlyByCargo() {
        let messages = QualifyingEvent.groupSuggestedHandlers([.alarm, .malfunction])
        let aamCargo = messages.compactMap { $0 as? ActiveAamBitsRequest }.map(\.cargo)

        XCTAssertEqual(Set(aamCargo), [Data([2]), Data([4])])
        XCTAssertEqual(messages.compactMap { $0 as? HighestAamRequest }.count, 1)
    }

    /// The IOB opcode depends on whether the pump runs Control-IQ.
    func testSuggestedHandlersSelectIOBRequestByControlIQSupport() {
        XCTAssertEqual(
            requestTypeNames(QualifyingEvent.iobChange.suggestedHandlers()),
            ["NonControlIQIOBRequest"]
        )
        XCTAssertEqual(
            requestTypeNames(QualifyingEvent.iobChange.suggestedHandlers(
                context: QualifyingEventContext(controlIQSupported: true)
            )),
            ["ControlIQIOBRequest"]
        )
    }

    /// The version-dependent requests follow the pump's API version, the same way the driver's
    /// own status fetches do.
    func testSuggestedHandlersSelectVersionedRequestsByApiVersion() {
        let legacy = QualifyingEventContext(apiVersion: KnownApiVersion.apiV2_1.value)
        let modern = QualifyingEventContext(apiVersion: KnownApiVersion.apiV3_4.value)

        XCTAssertEqual(
            requestTypeNames(QualifyingEvent.battery.suggestedHandlers(context: legacy)),
            ["CurrentBatteryV1Request"]
        )
        XCTAssertEqual(
            requestTypeNames(QualifyingEvent.battery.suggestedHandlers(context: modern)),
            ["CurrentBatteryV2Request"]
        )

        XCTAssertTrue(
            requestTypeNames(QualifyingEvent.bolusChange.suggestedHandlers(context: legacy))
                .contains("LastBolusStatusRequest")
        )
        XCTAssertTrue(
            requestTypeNames(QualifyingEvent.bolusChange.suggestedHandlers(context: modern))
                .contains("LastBolusStatusV2Request")
        )
    }

    /// Without a known bolus id there is nothing to ask about, so the event drops out entirely.
    func testBolusPermissionRevokedNeedsAnInProgressBolusId() {
        XCTAssertTrue(QualifyingEvent.bolusPermissionRevoked.suggestedHandlers().isEmpty)

        let messages = QualifyingEvent.bolusPermissionRevoked.suggestedHandlers(
            context: QualifyingEventContext(inProgressBolusId: 7)
        )
        XCTAssertEqual(messages.compactMap { $0 as? BolusPermissionChangeReasonRequest }.map(\.bolusId), [7])
    }
}
