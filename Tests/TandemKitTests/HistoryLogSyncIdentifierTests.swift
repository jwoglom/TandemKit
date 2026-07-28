@testable import TandemKit
import XCTest

final class HistoryLogSyncIdentifierTests: XCTestCase {
    /// Golden values. The host app persists these bytes as a dose's syncIdentifier, so a change here
    /// is a data-migration event, not a test to update: re-reporting the same delivery under a new
    /// identity double-counts insulin. See `HistoryLogSyncIdentifier`.
    func testWireFormatIsFrozen() {
        XCTAssertEqual(
            HistoryLogSyncIdentifier.bolus(pumpSerial: 12345, bolusId: 42).hexadecimalString,
            "0101393000002a000000"
        )
        XCTAssertEqual(
            HistoryLogSyncIdentifier.tempRate(pumpSerial: 12345, tempRateId: 42).hexadecimalString,
            "0102393000002a000000"
        )
        XCTAssertEqual(
            HistoryLogSyncIdentifier.logSequence(pumpSerial: 12345, sequenceNum: 42).hexadecimalString,
            "0103393000002a000000"
        )
    }

    func testIdentifiersAreTenBytes() {
        XCTAssertEqual(HistoryLogSyncIdentifier.bolus(pumpSerial: 1, bolusId: 1).count, 10)
    }

    /// The point of the scheme: an optimistic report and its history confirmation carry the same id,
    /// so the host app finalizes in place instead of recording a second dose.
    func testSameBolusIdFromDifferentPhasesMatches() {
        let atCommandTime = HistoryLogSyncIdentifier.bolus(pumpSerial: 777, bolusId: 9)
        let fromHistory = HistoryLogSyncIdentifier.bolus(pumpSerial: 777, bolusId: 9)

        XCTAssertEqual(atCommandTime, fromHistory)
    }

    func testSchemesDoNotCollide() {
        let identifiers = Set([
            HistoryLogSyncIdentifier.bolus(pumpSerial: 1, bolusId: 5),
            HistoryLogSyncIdentifier.tempRate(pumpSerial: 1, tempRateId: 5),
            HistoryLogSyncIdentifier.logSequence(pumpSerial: 1, sequenceNum: 5)
        ])

        XCTAssertEqual(identifiers.count, 3)
    }

    /// bolusIds and tempRateIds are small pump counters that repeat across pumps.
    func testPumpSerialSeparatesIdentifiers() {
        XCTAssertNotEqual(
            HistoryLogSyncIdentifier.bolus(pumpSerial: 1, bolusId: 5),
            HistoryLogSyncIdentifier.bolus(pumpSerial: 2, bolusId: 5)
        )
    }

    func testDecodeRoundTrip() throws {
        let decoded = try XCTUnwrap(
            HistoryLogSyncIdentifier.decode(
                HistoryLogSyncIdentifier.tempRate(pumpSerial: 4_294_967_295, tempRateId: 65535)
            )
        )

        XCTAssertEqual(decoded.scheme, .tempRate)
        XCTAssertEqual(decoded.pumpSerial, 4_294_967_295)
        XCTAssertEqual(decoded.identifier, 65535)
    }

    func testDecodeRejectsForeignData() {
        XCTAssertNil(HistoryLogSyncIdentifier.decode(Data()))
        XCTAssertNil(HistoryLogSyncIdentifier.decode(Data(count: 10)))
        XCTAssertNil(HistoryLogSyncIdentifier.decode(Data([2, 1, 0, 0, 0, 0, 0, 0, 0, 0])))
        XCTAssertNil(HistoryLogSyncIdentifier.decode(Data([1, 9, 0, 0, 0, 0, 0, 0, 0, 0])))
    }

    func testNegativeIdsClampRatherThanTrap() {
        XCTAssertEqual(
            HistoryLogSyncIdentifier.decode(HistoryLogSyncIdentifier.bolus(pumpSerial: 1, bolusId: -1))?.identifier,
            0
        )
    }

    func testStoredLogExposesItsSequenceIdentity() {
        let log = StoredHistoryLog(
            pumpSerial: 12345,
            sequenceNum: 42,
            typeId: 3,
            pumpTimeSec: 1000,
            cargo: Data(count: HistoryLog.length)
        )

        XCTAssertEqual(
            log.logSequenceSyncIdentifier,
            HistoryLogSyncIdentifier.logSequence(pumpSerial: 12345, sequenceNum: 42)
        )
    }
}
