@testable import TandemCore
import XCTest

final class HistoryLogCalibrationTests: XCTestCase {
    /// Arbitrary base instant; the synthetic map places seq 1000 here, +10s per sequence step.
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func date(forSeq seq: UInt32) -> Date {
        base.addingTimeInterval(Double(Int(seq) - 1000) * 10)
    }

    private func makeCalibration() -> HistoryLogCalibration {
        var calibration = HistoryLogCalibration()
        for seq in stride(from: UInt32(1000), through: UInt32(2000), by: 100) {
            calibration.insert(sequenceNum: seq, date: date(forSeq: seq))
        }
        return calibration
    }

    func testEmptyCalibrationReturnsNil() {
        let calibration = HistoryLogCalibration()
        XCTAssertNil(calibration.estimatedDate(forSequenceNum: 100))
        XCTAssertNil(calibration.estimatedSequenceNum(forDate: base))
        XCTAssertFalse(calibration.isUsable)
    }

    func testExactGuidepostRoundTrip() {
        let calibration = makeCalibration()
        XCTAssertEqual(
            calibration.estimatedDate(forSequenceNum: 1500)?.timeIntervalSince1970,
            date(forSeq: 1500).timeIntervalSince1970
        )
        XCTAssertEqual(calibration.estimatedSequenceNum(forDate: date(forSeq: 1500)), 1500)
    }

    func testInterpolationBetweenGuideposts() {
        let calibration = makeCalibration()
        let midDate = date(forSeq: 1550)
        XCTAssertEqual(calibration.estimatedSequenceNum(forDate: midDate), 1550)
        XCTAssertEqual(
            calibration.estimatedDate(forSequenceNum: 1550)?.timeIntervalSince1970 ?? 0,
            midDate.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    func testExtrapolationBeyondNewestIsClamped() {
        let calibration = makeCalibration()
        let beyond = date(forSeq: 2500)
        XCTAssertEqual(calibration.estimatedSequenceNum(forDate: beyond), 2500)
        XCTAssertEqual(calibration.estimatedSequenceNum(forDate: beyond, upperBound: 2100), 2100)
    }

    func testExtrapolationBeforeOldestIsClamped() {
        let calibration = makeCalibration()
        let before = date(forSeq: 500)
        XCTAssertEqual(calibration.estimatedSequenceNum(forDate: before), 500)
        XCTAssertEqual(calibration.estimatedSequenceNum(forDate: before, lowerBound: 800), 800)
    }

    func testSequenceBoundsBracketDate() {
        let calibration = makeCalibration()
        let bounds = calibration.sequenceBounds(forDate: date(forSeq: 1550))
        XCTAssertEqual(bounds?.lower, 1500)
        XCTAssertEqual(bounds?.upper, 1600)
        XCTAssertNil(calibration.sequenceBounds(forDate: date(forSeq: 2500)))
    }

    func testBinarySearchFirstAtOrAfter() {
        let target = date(forSeq: 1734)
        let result = HistoryLogCalibration.binarySearchBoundary(
            .firstAtOrAfter, target: target, lowerBound: 1, upperBound: 100_000,
            probe: { self.date(forSeq: $0) }
        )
        XCTAssertEqual(result, 1734)
    }

    func testBinarySearchLastAtOrBefore() {
        // 3 seconds past seq 1734's timestamp still resolves to 1734 (before 1735).
        let target = date(forSeq: 1734).addingTimeInterval(3)
        let result = HistoryLogCalibration.binarySearchBoundary(
            .lastAtOrBefore, target: target, lowerBound: 1, upperBound: 100_000,
            probe: { self.date(forSeq: $0) }
        )
        XCTAssertEqual(result, 1734)
    }

    func testBinarySearchRespectsMaxProbes() {
        var probeCount = 0
        _ = HistoryLogCalibration.binarySearchBoundary(
            .firstAtOrAfter, target: date(forSeq: 1734), lowerBound: 1, upperBound: 100_000,
            maxProbes: 5, probe: { probeCount += 1; return self.date(forSeq: $0) }
        )
        XCTAssertLessThanOrEqual(probeCount, 5)
    }

    func testBinarySearchNilProbeStopsEarly() {
        // A probe that always fails should not spin and should return a bound within range.
        let result = HistoryLogCalibration.binarySearchBoundary(
            .firstAtOrAfter, target: base, lowerBound: 10, upperBound: 20,
            probe: { _ in nil }
        )
        XCTAssertGreaterThanOrEqual(result, 10)
        XCTAssertLessThanOrEqual(result, 20)
    }

    func testSinglePointDegenerate() {
        var calibration = HistoryLogCalibration()
        calibration.insert(sequenceNum: 42, date: base)
        XCTAssertEqual(calibration.estimatedSequenceNum(forDate: date(forSeq: 2500)), 42)
        XCTAssertEqual(calibration.estimatedDate(forSequenceNum: 999)?.timeIntervalSince1970, base.timeIntervalSince1970)
        XCTAssertFalse(calibration.isUsable)
    }

    func testDedupSortsAndKeepsLastWrite() {
        var calibration = HistoryLogCalibration()
        calibration.insert(sequenceNum: 5, date: base)
        calibration.insert(sequenceNum: 5, date: base.addingTimeInterval(999))
        calibration.insert(sequenceNum: 1, date: base)
        XCTAssertEqual(calibration.count, 2)
        XCTAssertEqual(calibration.points.first?.sequenceNum, 1)
        XCTAssertEqual(calibration.points.last?.date.timeIntervalSince1970, base.timeIntervalSince1970 + 999)
    }
}
