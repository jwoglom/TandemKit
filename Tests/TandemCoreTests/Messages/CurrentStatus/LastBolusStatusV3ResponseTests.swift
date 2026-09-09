@testable import TandemKit
import XCTest

/// No Mobi hardware capture exists for this message, so these tests build the cargo from the
/// documented layout and assert the round trip plus the `LastBolusStatusAbstractResponse` view
/// the bolus finalization path reads.
final class LastBolusStatusV3ResponseTests: XCTestCase {
    private func response(
        lastBolusTypeBitmask: Int,
        standardBolusId: Int = 100,
        standardDelivered: UInt32 = 2500,
        standardEndReasonId: Int = LastBolusStatusAbstractResponseBolusStatus.complete.rawValue,
        extendedBolusId: Int = 101,
        extendedDelivered: UInt32 = 1500,
        extendedEndReasonId: Int = LastBolusStatusAbstractResponseBolusStatus.complete.rawValue,
        extendedBolusDuration: UInt32 = 1800
    ) -> LastBolusStatusV3Response {
        LastBolusStatusV3Response(
            lastBolusTypeBitmask: lastBolusTypeBitmask,
            standardBolusStatusId: 0,
            standardBolusId: standardBolusId,
            standardBolusTimestamp: 500_000_000,
            standardBolusDeliveredVolume: standardDelivered,
            standardBolusEndReasonId: standardEndReasonId,
            standardBolusSourceId: 0,
            standardBolusTypeBitmask: 1,
            standardBolusRequestedVolume: 3000,
            standardBolusSecondsSincePumpReset: 12345,
            extendedBolusStatusId: 0,
            extendedBolusId: extendedBolusId,
            extendedBolusTimestamp: 500_000_100,
            extendedBolusDeliveredVolume: extendedDelivered,
            extendedBolusEndReasonId: extendedEndReasonId,
            extendedBolusSourceId: 0,
            extendedBolusTypeBitmask: 2,
            extendedBolusRequestedVolume: 2000,
            extendedBolusSecondsSincePumpReset: 12445,
            extendedBolusDuration: extendedBolusDuration
        )
    }

    func testCargoRoundTrip() {
        let built = response(lastBolusTypeBitmask: 0x03)
        XCTAssertEqual(53, built.cargo.count)
        XCTAssertEqual(53, LastBolusStatusV3Response.props.size)

        let parsed = LastBolusStatusV3Response(cargo: built.cargo)
        XCTAssertEqual(built.cargo, parsed.cargo)
        XCTAssertEqual(0x03, parsed.lastBolusTypeBitmask)
        XCTAssertEqual(100, parsed.standardBolusId)
        XCTAssertEqual(2500, parsed.standardBolusDeliveredVolume)
        XCTAssertEqual(3000, parsed.standardBolusRequestedVolume)
        XCTAssertEqual(12345, parsed.standardBolusSecondsSincePumpReset)
        XCTAssertEqual(101, parsed.extendedBolusId)
        XCTAssertEqual(1500, parsed.extendedBolusDeliveredVolume)
        XCTAssertEqual(2000, parsed.extendedBolusRequestedVolume)
        XCTAssertEqual(12445, parsed.extendedBolusSecondsSincePumpReset)
        XCTAssertEqual(1800, parsed.extendedBolusDuration)
    }

    func testSectionsFollowPresenceBitmask() {
        let both = response(lastBolusTypeBitmask: 0x03)
        XCTAssertEqual(2, both.sections.count)
        XCTAssertEqual(false, both.sections.first?.isExtended)
        XCTAssertEqual(true, both.sections.last?.isExtended)
        XCTAssertEqual(0, both.standardSection?.duration)
        XCTAssertEqual(1800, both.extendedSection?.duration)

        let standardOnly = response(lastBolusTypeBitmask: 0x01)
        XCTAssertNotNil(standardOnly.standardSection)
        XCTAssertNil(standardOnly.extendedSection)
        XCTAssertEqual(100, standardOnly.primarySection?.bolusId)

        let extendedOnly = response(lastBolusTypeBitmask: 0x02)
        XCTAssertNil(extendedOnly.standardSection)
        XCTAssertNotNil(extendedOnly.extendedSection)
        XCTAssertEqual(101, extendedOnly.primarySection?.bolusId)

        let neither = response(lastBolusTypeBitmask: 0x00)
        XCTAssertTrue(neither.sections.isEmpty)
        XCTAssertNil(neither.primarySection)
    }

    /// The abstract view reads the standard record when one is present, so the finalization path
    /// sees the immediate portion of a bolus that has both.
    func testAbstractResponseReadsPrimarySection() {
        let both: LastBolusStatusAbstractResponse = response(lastBolusTypeBitmask: 0x03)
        XCTAssertEqual(0, both.status)
        XCTAssertTrue(both.isStatusOK)
        XCTAssertEqual(100, both.bolusId)
        XCTAssertEqual(2500, both.deliveredVolume)
        XCTAssertEqual(500_000_000, both.timestamp)
        XCTAssertEqual(.complete, both.bolusStatus)
        XCTAssertEqual(1, both.bolusTypeBitmask)
        XCTAssertEqual(1800, both.extendedBolusDuration)

        // Extended-only falls back to the extended record rather than reporting a stale
        // standard one the pump did not flag as present.
        let extendedOnly: LastBolusStatusAbstractResponse = response(
            lastBolusTypeBitmask: 0x02,
            extendedEndReasonId: LastBolusStatusAbstractResponseBolusStatus.stopped.rawValue
        )
        XCTAssertEqual(101, extendedOnly.bolusId)
        XCTAssertEqual(1500, extendedOnly.deliveredVolume)
        XCTAssertEqual(500_000_100, extendedOnly.timestamp)
        XCTAssertEqual(.stopped, extendedOnly.bolusStatus)
        XCTAssertEqual(2, extendedOnly.bolusTypeBitmask)

        let neither: LastBolusStatusAbstractResponse = response(lastBolusTypeBitmask: 0x00)
        XCTAssertEqual(0, neither.deliveredVolume)
    }

    func testDeliveredVolumeForBolusIdSumsMatchingSections() {
        // Both portions of one bolus id: the total is what was delivered.
        let shared = response(lastBolusTypeBitmask: 0x03, standardBolusId: 42, extendedBolusId: 42)
        XCTAssertEqual(4000, shared.deliveredVolume(forBolusId: 42))

        // Distinct ids: only the matching record contributes.
        let distinct = response(lastBolusTypeBitmask: 0x03)
        XCTAssertEqual(2500, distinct.deliveredVolume(forBolusId: 100))
        XCTAssertEqual(1500, distinct.deliveredVolume(forBolusId: 101))

        // A record the pump did not flag as present is never read.
        let standardOnly = response(lastBolusTypeBitmask: 0x01)
        XCTAssertNil(standardOnly.deliveredVolume(forBolusId: 101))

        XCTAssertNil(distinct.deliveredVolume(forBolusId: 7))
    }
}
