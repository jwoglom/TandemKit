@testable import TandemKit
import XCTest

/// Covers the delivered-volume read the bolus finalization path depends on, on both the V2
/// response and the Mobi-only V3 response with its two bolus records.
final class LastBolusDeliveredVolumeTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
    }

    override func tearDown() {
        bluetooth = nil
        super.tearDown()
    }

    private func makeManager(apiVersion: KnownApiVersion = .mobiApiV3_5) -> TandemPumpManager {
        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState.apiVersion = apiVersion.value
        state.pumpState.pumpModel = .MOBI
        return TandemPumpManager(state: state, bluetooth: bluetooth)
    }

    private func v3Response(
        lastBolusTypeBitmask: Int,
        standardBolusId: Int,
        standardDelivered: UInt32,
        extendedBolusId: Int,
        extendedDelivered: UInt32,
        standardTimestamp: UInt32 = 500_000_000,
        extendedTimestamp: UInt32 = 500_000_000
    ) -> LastBolusStatusV3Response {
        LastBolusStatusV3Response(
            lastBolusTypeBitmask: lastBolusTypeBitmask,
            standardBolusStatusId: 0,
            standardBolusId: standardBolusId,
            standardBolusTimestamp: standardTimestamp,
            standardBolusDeliveredVolume: standardDelivered,
            standardBolusEndReasonId: LastBolusStatusAbstractResponseBolusStatus.stoppedWireless.rawValue,
            standardBolusSourceId: 0,
            standardBolusTypeBitmask: 1,
            standardBolusRequestedVolume: 5000,
            standardBolusSecondsSincePumpReset: 1000,
            extendedBolusStatusId: 0,
            extendedBolusId: extendedBolusId,
            extendedBolusTimestamp: extendedTimestamp,
            extendedBolusDeliveredVolume: extendedDelivered,
            extendedBolusEndReasonId: LastBolusStatusAbstractResponseBolusStatus.stoppedWireless.rawValue,
            extendedBolusSourceId: 0,
            extendedBolusTypeBitmask: 2,
            extendedBolusRequestedVolume: 3000,
            extendedBolusSecondsSincePumpReset: 1000,
            extendedBolusDuration: 1800
        )
    }

    func testV2ResponseReportsDeliveredVolume() {
        let manager = makeManager(apiVersion: .apiV3_4)
        bluetooth.stub(LastBolusStatusV2Request.self, with: LastBolusStatusV2Response(
            status: 0,
            bolusId: 2004,
            timestamp: 500_000_000,
            deliveredVolume: 2450,
            bolusStatusId: LastBolusStatusAbstractResponseBolusStatus.stoppedWireless.rawValue,
            bolusSourceId: 0,
            bolusTypeBitmask: 1,
            extendedBolusDuration: 0,
            requestedVolume: 5000
        ))

        XCTAssertEqual(2.45, manager.queryLastBolusDeliveredVolume(bolusId: 2004))
        XCTAssertTrue(bluetooth.didSend(LastBolusStatusV2Request.self))
    }

    /// A Mobi is asked with the V3 request, and its reply must finalize at the delivered
    /// amount instead of falling back to the programmed one.
    func testV3ResponseReportsDeliveredVolume() {
        let manager = makeManager()
        bluetooth.stub(LastBolusStatusV3Request.self, with: v3Response(
            lastBolusTypeBitmask: 0x01,
            standardBolusId: 2004,
            standardDelivered: 2450,
            extendedBolusId: 0,
            extendedDelivered: 0
        ))

        XCTAssertEqual(2.45, manager.queryLastBolusDeliveredVolume(bolusId: 2004))
    }

    /// Both portions of one bolus id sum, so an extended bolus is not under-reported.
    func testV3ResponseSumsBothPortionsOfSameBolus() {
        let manager = makeManager()
        bluetooth.stub(LastBolusStatusV3Request.self, with: v3Response(
            lastBolusTypeBitmask: 0x03,
            standardBolusId: 2004,
            standardDelivered: 2000,
            extendedBolusId: 2004,
            extendedDelivered: 1000
        ))

        XCTAssertEqual(3.0, manager.queryLastBolusDeliveredVolume(bolusId: 2004))
    }

    /// An extended-only record for the tracked bolus is read from the extended section, which
    /// the single-record abstract view would have missed if it always read the standard one.
    func testV3ResponseReadsExtendedOnlyRecord() {
        let manager = makeManager()
        bluetooth.stub(LastBolusStatusV3Request.self, with: v3Response(
            lastBolusTypeBitmask: 0x02,
            standardBolusId: 0,
            standardDelivered: 0,
            extendedBolusId: 2004,
            extendedDelivered: 1250
        ))

        XCTAssertEqual(1.25, manager.queryLastBolusDeliveredVolume(bolusId: 2004))
    }

    /// A response about a different bolus is rejected rather than attributed to this one.
    func testV3ResponseForOtherBolusIsRejected() {
        let manager = makeManager()
        bluetooth.stub(LastBolusStatusV3Request.self, with: v3Response(
            lastBolusTypeBitmask: 0x03,
            standardBolusId: 2001,
            standardDelivered: 2000,
            extendedBolusId: 2002,
            extendedDelivered: 1000
        ))

        XCTAssertNil(manager.queryLastBolusDeliveredVolume(bolusId: 2004))
    }

    // MARK: - Pump timestamp

    /// The timestamp dates the end of the bolus (#339), so a bolus present in both records ends
    /// when its *last* portion did, not when its first one did.
    func testV3ReportsTheLatestTimestampAcrossBothRecordsOfOneBolus() throws {
        let manager = makeManager()
        bluetooth.stub(LastBolusStatusV3Request.self, with: v3Response(
            lastBolusTypeBitmask: 0x03,
            standardBolusId: 2004,
            standardDelivered: 2000,
            extendedBolusId: 2004,
            extendedDelivered: 1000,
            standardTimestamp: 500_000_000,
            extendedTimestamp: 500_001_800
        ))

        let report = try XCTUnwrap(manager.queryLastBolusReport(bolusId: 2004))

        XCTAssertEqual(report.pumpTimestamp, Dates.fromJan12008EpochSecondsToDate(500_001_800))
    }

    /// An extended-only bolus is dated from the extended record, which the single-record
    /// abstract view reads only because no standard record is present.
    func testV3ReportsTheExtendedOnlyRecordsTimestamp() throws {
        let manager = makeManager()
        bluetooth.stub(LastBolusStatusV3Request.self, with: v3Response(
            lastBolusTypeBitmask: 0x02,
            standardBolusId: 0,
            standardDelivered: 0,
            extendedBolusId: 2004,
            extendedDelivered: 1250,
            standardTimestamp: 500_009_999,
            extendedTimestamp: 500_000_500
        ))

        let report = try XCTUnwrap(manager.queryLastBolusReport(bolusId: 2004))

        XCTAssertEqual(report.pumpTimestamp, Dates.fromJan12008EpochSecondsToDate(500_000_500))
    }

    func testV2ReportsItsSingleTimestamp() throws {
        let manager = makeManager(apiVersion: .apiV3_4)
        bluetooth.stub(LastBolusStatusV2Request.self, with: LastBolusStatusV2Response(
            status: 0,
            bolusId: 2004,
            timestamp: 500_000_123,
            deliveredVolume: 2450,
            bolusStatusId: LastBolusStatusAbstractResponseBolusStatus.stoppedWireless.rawValue,
            bolusSourceId: 0,
            bolusTypeBitmask: 1,
            extendedBolusDuration: 0,
            requestedVolume: 5000
        ))

        let report = try XCTUnwrap(manager.queryLastBolusReport(bolusId: 2004))

        XCTAssertEqual(report.pumpTimestamp, Dates.fromJan12008EpochSecondsToDate(500_000_123))
    }

    func testUnansweredRequestReportsNil() {
        let manager = makeManager()
        XCTAssertNil(manager.queryLastBolusDeliveredVolume(bolusId: 2004))
        XCTAssertTrue(bluetooth.didSend(LastBolusStatusV3Request.self))
    }
}
