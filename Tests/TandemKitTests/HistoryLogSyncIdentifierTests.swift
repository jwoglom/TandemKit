@testable import TandemKit
import XCTest

final class HistoryLogSyncIdentifierTests: XCTestCase {
    private func serial(
        _ value: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> HistoryLogSyncIdentifier.PumpSerial {
        try XCTUnwrap(HistoryLogSyncIdentifier.PumpSerial(value), file: file, line: line)
    }

    /// Golden values. The host app persists these bytes as a dose's syncIdentifier, so a change here
    /// is a data-migration event, not a test to update: re-reporting the same delivery under a new
    /// identity double-counts insulin. See `HistoryLogSyncIdentifier`.
    func testWireFormatIsFrozen() throws {
        let pumpSerial = try serial(12345)

        XCTAssertEqual(
            HistoryLogSyncIdentifier.bolus(pumpSerial: pumpSerial, bolusId: 42).hexadecimalString,
            "0101393000002a000000"
        )
        XCTAssertEqual(
            HistoryLogSyncIdentifier.tempRate(pumpSerial: pumpSerial, tempRateId: 42).hexadecimalString,
            "0102393000002a000000"
        )
        XCTAssertEqual(
            HistoryLogSyncIdentifier.logSequence(pumpSerial: pumpSerial, sequenceNum: 42).hexadecimalString,
            "0103393000002a000000"
        )
        XCTAssertEqual(
            HistoryLogSyncIdentifier.tempRatePart(pumpSerial: pumpSerial, tempRateId: 42, part: 1).hexadecimalString,
            "0105393000002a000100"
        )
    }

    func testThePartsOfATempRateCountOnFromItsIdentity() throws {
        let pumpSerial = try serial(12345)
        let temp = HistoryLogSyncIdentifier.tempRate(pumpSerial: pumpSerial, tempRateId: 42)

        let first = try XCTUnwrap(HistoryLogSyncIdentifier.nextTempRatePart(after: temp))

        XCTAssertEqual(first, HistoryLogSyncIdentifier.tempRatePart(pumpSerial: pumpSerial, tempRateId: 42, part: 1))
        XCTAssertEqual(
            HistoryLogSyncIdentifier.nextTempRatePart(after: first),
            HistoryLogSyncIdentifier.tempRatePart(pumpSerial: pumpSerial, tempRateId: 42, part: 2)
        )
        XCTAssertNil(HistoryLogSyncIdentifier.nextTempRatePart(after: HistoryLogSyncIdentifier.bolus(pumpSerial: pumpSerial, bolusId: 42)))
        XCTAssertNil(HistoryLogSyncIdentifier.nextTempRatePart(after: Data("tempBasal 0.75 2026-01-01T00:00:00Z".utf8)))
    }

    func testIdentifiersAreTenBytes() throws {
        XCTAssertEqual(HistoryLogSyncIdentifier.bolus(pumpSerial: try serial(1), bolusId: 1).count, 10)
    }

    /// The point of the scheme: an optimistic report and its history confirmation carry the same id,
    /// so the host app finalizes in place instead of recording a second dose.
    func testSameBolusIdFromDifferentPhasesMatches() throws {
        let atCommandTime = HistoryLogSyncIdentifier.bolus(pumpSerial: try serial(777), bolusId: 9)
        let fromHistory = HistoryLogSyncIdentifier.bolus(pumpSerial: try serial(777), bolusId: 9)

        XCTAssertEqual(atCommandTime, fromHistory)
    }

    func testSchemesDoNotCollide() throws {
        let pumpSerial = try serial(1)
        let identifiers = Set([
            HistoryLogSyncIdentifier.bolus(pumpSerial: pumpSerial, bolusId: 5),
            HistoryLogSyncIdentifier.tempRate(pumpSerial: pumpSerial, tempRateId: 5),
            HistoryLogSyncIdentifier.logSequence(pumpSerial: pumpSerial, sequenceNum: 5),
            HistoryLogSyncIdentifier.tempRatePart(pumpSerial: pumpSerial, tempRateId: 5, part: 0)
        ])

        XCTAssertEqual(identifiers.count, 4)
    }

    /// bolusIds and tempRateIds are small pump counters that repeat across pumps.
    func testPumpSerialSeparatesIdentifiers() throws {
        XCTAssertNotEqual(
            HistoryLogSyncIdentifier.bolus(pumpSerial: try serial(1), bolusId: 5),
            HistoryLogSyncIdentifier.bolus(pumpSerial: try serial(2), bolusId: 5)
        )
    }

    /// An unknown serial has to stop the identifier from being built at all. A placeholder would let
    /// one pump's doses be re-minted under its real serial later — counted twice — and would let two
    /// pumps' bolusId counters collide with each other.
    func testUnknownPumpSerialCannotBeUsed() {
        XCTAssertNil(HistoryLogSyncIdentifier.PumpSerial(nil))
    }

    /// Zero is what `?? 0` produces, and what an unparsed PumpVersionResponse reads back.
    func testZeroPumpSerialIsRejected() {
        XCTAssertNil(HistoryLogSyncIdentifier.PumpSerial(0))
    }

    func testDecodeRoundTrip() throws {
        let decoded = try XCTUnwrap(
            HistoryLogSyncIdentifier.decode(
                HistoryLogSyncIdentifier.tempRate(pumpSerial: try serial(4_294_967_295), tempRateId: 65535)
            )
        )

        XCTAssertEqual(decoded.scheme, .tempRate)
        XCTAssertEqual(decoded.pumpSerial.rawValue, 4_294_967_295)
        XCTAssertEqual(decoded.identifier, 65535)
    }

    func testDecodeRejectsForeignData() {
        XCTAssertNil(HistoryLogSyncIdentifier.decode(Data()))
        XCTAssertNil(HistoryLogSyncIdentifier.decode(Data(count: 10)))
        XCTAssertNil(HistoryLogSyncIdentifier.decode(Data([2, 1, 0, 0, 0, 0, 0, 0, 0, 0])))
        XCTAssertNil(HistoryLogSyncIdentifier.decode(Data([1, 9, 0, 0, 0, 0, 0, 0, 0, 0])))
    }

    /// Well-formed apart from the serial, so it is not something this type ever minted.
    func testDecodeRejectsZeroSerial() {
        XCTAssertNil(HistoryLogSyncIdentifier.decode(Data([1, 1, 0, 0, 0, 0, 42, 0, 0, 0])))
    }

    func testNegativeIdsClampRatherThanTrap() throws {
        XCTAssertEqual(
            HistoryLogSyncIdentifier.decode(
                HistoryLogSyncIdentifier.bolus(pumpSerial: try serial(1), bolusId: -1)
            )?.identifier,
            0
        )
    }

    func testStoredLogExposesItsSequenceIdentity() throws {
        let log = StoredHistoryLog(
            pumpSerial: 12345,
            sequenceNum: 42,
            typeId: 3,
            pumpTimeSec: 1000,
            cargo: Data(count: HistoryLog.length)
        )

        XCTAssertEqual(
            log.logSequenceSyncIdentifier,
            HistoryLogSyncIdentifier.logSequence(pumpSerial: try serial(12345), sequenceNum: 42)
        )
    }

    /// A stored entry can carry the zero placeholder, so the identity has to be unavailable rather
    /// than minted under a serial no pump reports.
    func testStoredLogWithUnknownSerialHasNoSequenceIdentity() {
        let log = StoredHistoryLog(
            pumpSerial: 0,
            sequenceNum: 42,
            typeId: 3,
            pumpTimeSec: 1000,
            cargo: Data(count: HistoryLog.length)
        )

        XCTAssertNil(log.logSequenceSyncIdentifier)
    }
}
