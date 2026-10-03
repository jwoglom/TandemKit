@testable import TandemKit
import XCTest

final class LastBolusStatusV3ResponseTests: XCTestCase {
    /// Captured from a Mobi: a completed 0.4 U standard bolus, no extended portion. The last two
    /// bytes are the packet CRC, which the recorded cargo carried past the 53-byte message.
    private static let mobiStandardBolusCapture =
        "0104070c0000393827239001000003080990010000bbb106000000000000000000000000000000000000000000ffffffff000000002c61"

    private var mobiStandardBolus: LastBolusStatusV3Response {
        let cargo = Data(hexadecimalString: Self.mobiStandardBolusCapture)!
        return LastBolusStatusV3Response(cargo: Data(cargo.prefix(Int(LastBolusStatusV3Response.props.size))))
    }

    func testStandardSectionBolusTypesUseHistoryLogMapping() throws {
        let section = try XCTUnwrap(mobiStandardBolus.standardSection)

        XCTAssertEqual([.now, .correction], section.bolusTypes)
    }

    func testMobiStandardBolusCapture() {
        let parsed = mobiStandardBolus

        XCTAssertEqual(1, parsed.lastBolusTypeBitmask)
        XCTAssertTrue(parsed.isStandardBolusPresent)
        XCTAssertFalse(parsed.isExtendedBolusPresent)

        XCTAssertEqual(4, parsed.standardBolusStatusId)
        XCTAssertEqual(3079, parsed.standardBolusId)
        XCTAssertEqual(589_772_857, parsed.standardBolusTimestamp)
        XCTAssertEqual(400, parsed.standardBolusDeliveredVolume)
        XCTAssertEqual(3, parsed.standardBolusEndReasonId)
        XCTAssertEqual(8, parsed.standardBolusSourceId)
        XCTAssertEqual(9, parsed.standardBolusTypeBitmask)
        XCTAssertEqual(400, parsed.standardBolusRequestedVolume)
        XCTAssertEqual(438_715, parsed.standardBolusSecondsSincePumpReset)

        XCTAssertEqual(0, parsed.extendedBolusStatusId)
        XCTAssertEqual(0, parsed.extendedBolusId)
        XCTAssertEqual(0, parsed.extendedBolusTimestamp)
        XCTAssertEqual(0, parsed.extendedBolusDeliveredVolume)
        XCTAssertEqual(0, parsed.extendedBolusEndReasonId)
        XCTAssertEqual(0, parsed.extendedBolusSourceId)
        XCTAssertEqual(0, parsed.extendedBolusTypeBitmask)
        XCTAssertEqual(0, parsed.extendedBolusRequestedVolume)
        XCTAssertEqual(4_294_967_295, parsed.extendedBolusSecondsSincePumpReset)
        XCTAssertEqual(0, parsed.extendedBolusDuration)
    }

    /// Re-serializing the captured fields reproduces the captured bytes.
    func testMobiStandardBolusCaptureRoundTrip() {
        let parsed = mobiStandardBolus
        let rebuilt = LastBolusStatusV3Response(
            lastBolusTypeBitmask: parsed.lastBolusTypeBitmask,
            standardBolusStatusId: parsed.standardBolusStatusId,
            standardBolusId: parsed.standardBolusId,
            standardUnknown: parsed.standardUnknown,
            standardBolusTimestamp: parsed.standardBolusTimestamp,
            standardBolusDeliveredVolume: parsed.standardBolusDeliveredVolume,
            standardBolusEndReasonId: parsed.standardBolusEndReasonId,
            standardBolusSourceId: parsed.standardBolusSourceId,
            standardBolusTypeBitmask: parsed.standardBolusTypeBitmask,
            standardBolusRequestedVolume: parsed.standardBolusRequestedVolume,
            standardBolusSecondsSincePumpReset: parsed.standardBolusSecondsSincePumpReset,
            extendedBolusStatusId: parsed.extendedBolusStatusId,
            extendedBolusId: parsed.extendedBolusId,
            extendedUnknown: parsed.extendedUnknown,
            extendedBolusTimestamp: parsed.extendedBolusTimestamp,
            extendedBolusDeliveredVolume: parsed.extendedBolusDeliveredVolume,
            extendedBolusEndReasonId: parsed.extendedBolusEndReasonId,
            extendedBolusSourceId: parsed.extendedBolusSourceId,
            extendedBolusTypeBitmask: parsed.extendedBolusTypeBitmask,
            extendedBolusRequestedVolume: parsed.extendedBolusRequestedVolume,
            extendedBolusSecondsSincePumpReset: parsed.extendedBolusSecondsSincePumpReset,
            extendedBolusDuration: parsed.extendedBolusDuration
        )

        XCTAssertEqual(53, rebuilt.cargo.count)
        MessageTester.assertHexEquals(parsed.cargo, rebuilt.cargo)
    }

    /// The abstract view the bolus finalization path reads, on the captured bolus.
    func testMobiStandardBolusCaptureAbstractResponse() {
        let response: LastBolusStatusAbstractResponse = mobiStandardBolus

        XCTAssertEqual(4, response.status)
        XCTAssertEqual(3079, response.bolusId)
        XCTAssertEqual(400, response.deliveredVolume)
        XCTAssertEqual(589_772_857, response.timestamp)
        XCTAssertEqual(.complete, response.bolusStatus)
        XCTAssertEqual(9, response.bolusTypeBitmask)
        XCTAssertEqual(0, response.extendedBolusDuration)

        XCTAssertEqual(400, mobiStandardBolus.deliveredVolume(forBolusId: 3079))
        XCTAssertNil(mobiStandardBolus.deliveredVolume(forBolusId: 3080))
    }

    // MARK: - Extended-bolus cases, which the capture above does not cover

    private func response(
        lastBolusTypeBitmask: Int,
        standardBolusId: Int = 100,
        standardDelivered: UInt32 = 2500,
        extendedBolusId: Int = 101,
        extendedDelivered: UInt32 = 1500,
        extendedEndReasonId: Int = LastBolusStatusAbstractResponseBolusStatus.complete.rawValue
    ) -> LastBolusStatusV3Response {
        LastBolusStatusV3Response(
            lastBolusTypeBitmask: lastBolusTypeBitmask,
            standardBolusStatusId: 0,
            standardBolusId: standardBolusId,
            standardBolusTimestamp: 589_772_857,
            standardBolusDeliveredVolume: standardDelivered,
            standardBolusEndReasonId: LastBolusStatusAbstractResponseBolusStatus.complete.rawValue,
            standardBolusSourceId: 8,
            standardBolusTypeBitmask: 1,
            standardBolusRequestedVolume: 3000,
            standardBolusSecondsSincePumpReset: 438_715,
            extendedBolusStatusId: 0,
            extendedBolusId: extendedBolusId,
            extendedBolusTimestamp: 589_772_957,
            extendedBolusDeliveredVolume: extendedDelivered,
            extendedBolusEndReasonId: extendedEndReasonId,
            extendedBolusSourceId: 8,
            extendedBolusTypeBitmask: 2,
            extendedBolusRequestedVolume: 2000,
            extendedBolusSecondsSincePumpReset: 438_815,
            extendedBolusDuration: 1800
        )
    }

    func testSectionsFollowPresenceBitmask() {
        let both = response(lastBolusTypeBitmask: 0x03)
        XCTAssertEqual(2, both.sections.count)
        XCTAssertEqual(false, both.sections.first?.isExtended)
        XCTAssertEqual(true, both.sections.last?.isExtended)
        XCTAssertEqual(0, both.standardSection?.duration)
        XCTAssertEqual(1800, both.extendedSection?.duration)

        let extendedOnly = response(lastBolusTypeBitmask: 0x02)
        XCTAssertNil(extendedOnly.standardSection)
        XCTAssertNotNil(extendedOnly.extendedSection)
        XCTAssertEqual(101, extendedOnly.primarySection?.bolusId)

        let neither = response(lastBolusTypeBitmask: 0x00)
        XCTAssertTrue(neither.sections.isEmpty)
        XCTAssertNil(neither.primarySection)
    }

    /// The abstract view reads the standard record when one is present, and falls back to the
    /// extended record rather than reporting a stale one the pump did not flag as present.
    func testAbstractResponseReadsPrimarySection() {
        let both: LastBolusStatusAbstractResponse = response(lastBolusTypeBitmask: 0x03)
        XCTAssertEqual(100, both.bolusId)
        XCTAssertEqual(2500, both.deliveredVolume)
        XCTAssertEqual(589_772_857, both.timestamp)
        XCTAssertEqual(1, both.bolusTypeBitmask)
        XCTAssertEqual(1800, both.extendedBolusDuration)

        let extendedOnly: LastBolusStatusAbstractResponse = response(
            lastBolusTypeBitmask: 0x02,
            extendedEndReasonId: LastBolusStatusAbstractResponseBolusStatus.stopped.rawValue
        )
        XCTAssertEqual(101, extendedOnly.bolusId)
        XCTAssertEqual(1500, extendedOnly.deliveredVolume)
        XCTAssertEqual(589_772_957, extendedOnly.timestamp)
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
        XCTAssertNil(distinct.deliveredVolume(forBolusId: 7))

        // A record the pump did not flag as present is never read.
        XCTAssertNil(response(lastBolusTypeBitmask: 0x01).deliveredVolume(forBolusId: 101))
    }
}
