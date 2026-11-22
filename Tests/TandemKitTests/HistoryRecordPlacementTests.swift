@testable import TandemKit
import XCTest

/// Stamps and anchors share one arbitrary pump clock; the phone's is `phoneZero` plus seconds.
final class HistoryRecordPlacementTests: XCTestCase {
    private let phoneZero = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let pumpZero = 600_000_000
    private let day = 86400

    private func phone(_ seconds: TimeInterval) -> Date {
        phoneZero.addingTimeInterval(seconds)
    }

    /// An anchor at phone second `phoneSeconds`, the pump's clock `ahead` of where it started.
    private func anchor(_ sequenceNum: UInt32, at phoneSeconds: Int, ahead: Int = 0) -> PumpClockAnchor {
        PumpClockAnchor(sequenceNum: sequenceNum, pumpTimeSec: UInt32(pumpZero + phoneSeconds + ahead), phoneDate: phone(TimeInterval(phoneSeconds)))
    }

    /// A record written at phone second `phoneSeconds` by a pump clock `ahead` of where it started.
    private func record(_ sequenceNum: UInt32, at phoneSeconds: Int, ahead: Int = 0) -> HistoryLog {
        BolusActivatedHistoryLog(pumpTimeSec: UInt32(pumpZero + phoneSeconds + ahead), sequenceNum: sequenceNum, bolusId: 1, selectedIob: 0, iob: 0, bolusSize: 1)
    }

    private func dates(_ logs: [HistoryLog], anchors: [PumpClockAnchor], now: TimeInterval) -> HistoryRecordDates {
        HistoryRecordDates(logs, anchors: anchors, now: phone(now)) { $0 }
    }

    func testARecordIsDatedByItsAgeAtTheAnchorAboveItHoweverFarOffThePumpsClockIs() {
        for ahead in [0, 3 * 3600, 2 * day, -2 * day, -6900 * day] {
            let log = record(10, at: 700, ahead: ahead)
            let dates = dates([log], anchors: [anchor(12, at: 1000, ahead: ahead)], now: 1000)

            XCTAssertEqual(dates.placement(pumpTimeSec: log.pumpTimeSec, sequenceNum: 10), .dated(phone(700)), "pump clock \(ahead) s ahead")
        }
    }

    func testARecordStampedAfterTheAnchorAboveItIsHeld() {
        let log = record(10, at: 700, ahead: 2 * 3600)
        let dates = dates([log], anchors: [anchor(12, at: 1000)], now: 1000)

        XCTAssertEqual(dates.placement(pumpTimeSec: log.pumpTimeSec, sequenceNum: 10), .held(notAfter: phone(1000)))
        XCTAssertEqual(dates.phoneDate(of: log), .distantFuture)
        XCTAssertNil(dates.date(of: log))
        XCTAssertTrue(dates.isHeld(log))
        XCTAssertEqual(dates.latestPossibleDate(of: log), phone(1000))
    }

    func testARecordStampedBeforeTheAnchorBelowItOnAnUntouchedClockKeepsItsDate() {
        let log = record(10, at: -900)
        let dates = dates([log], anchors: [anchor(9, at: 0), anchor(12, at: 1000)], now: 1000)

        XCTAssertEqual(dates.placement(pumpTimeSec: log.pumpTimeSec, sequenceNum: 10), .dated(phone(-900)))
    }

    func testARecordIsDatedAcrossAClockChangeThePumpRecordedOnEitherSideOfIt() {
        let hour = 3600
        let before = record(10, at: 300)
        let change = TimeChangedHistoryLog(pumpTimeSec: UInt32(pumpZero + 400 + hour), sequenceNum: 11, timePrior: 1_000_000, timeAfter: 4_600_000, rawRTC: 0)
        let after = record(12, at: 500, ahead: hour)
        let dates = dates([before, change, after], anchors: [anchor(9, at: 0), anchor(13, at: 1000, ahead: hour)], now: 1000)

        XCTAssertEqual(dates.placement(pumpTimeSec: before.pumpTimeSec, sequenceNum: 10), .dated(phone(300)))
        XCTAssertEqual(dates.placement(pumpTimeSec: after.pumpTimeSec, sequenceNum: 12), .dated(phone(500)))
    }

    func testRecordsEitherSideOfAJumpThePumpDidNotRecordAreEachDatedOnTheirOwnClock() {
        let jump = 3000 * day
        let before = record(10, at: 300)
        let after = record(11, at: 900, ahead: jump)
        let dates = dates([before, after], anchors: [anchor(9, at: 0), anchor(12, at: 1020, ahead: jump)], now: 5000)

        XCTAssertEqual(dates.placement(pumpTimeSec: before.pumpTimeSec, sequenceNum: 10), .dated(phone(300)))
        XCTAssertEqual(dates.placement(pumpTimeSec: after.pumpTimeSec, sequenceNum: 11), .dated(phone(900)))
    }

    func testRecordsEitherSideOfAnUnrecordedJumpBackAreEachDatedOnTheirOwnClock() {
        let jump = -6900 * day
        // Stamps run back at the jump, so the bolus types these are would make the first undatable; a
        // pass's other records sit between two anchors the same way.
        let before = BasalDeliveryHistoryLog(pumpTimeSec: UInt32(pumpZero + 300), sequenceNum: 10, commandedRateSource: 1, commandedRate: 800, profileBasalRate: 800, algorithmRate: 0, tempRate: 0)
        let dates = dates([before], anchors: [anchor(9, at: 0), anchor(12, at: 1020, ahead: jump)], now: 5000)

        XCTAssertEqual(dates.placement(pumpTimeSec: before.pumpTimeSec, sequenceNum: 10), .dated(phone(300)))
    }

    func testARecordBothClocksPlaceBetweenTheAnchorsIsHeldWhenTheyDifferByMoreThanMinutes() {
        let hour = 3600
        let log = record(10, at: 2 * hour)
        let dates = dates([log], anchors: [anchor(9, at: 0), anchor(12, at: 3 * hour, ahead: hour)], now: TimeInterval(3 * hour))

        XCTAssertEqual(dates.placement(pumpTimeSec: log.pumpTimeSec, sequenceNum: 10), .held(notAfter: phone(TimeInterval(3 * hour))))
    }

    func testARecordBothClocksPlaceWithinMinutesOfEachOtherTakesTheLaterDate() {
        let log = record(10, at: 1800)
        let dates = dates([log], anchors: [anchor(9, at: 0), anchor(12, at: 3600, ahead: 240)], now: 3600)

        XCTAssertEqual(dates.placement(pumpTimeSec: log.pumpTimeSec, sequenceNum: 10), .dated(phone(1800)))

        let ranAhead = record(10, at: 1800, ahead: 240)
        XCTAssertEqual(dates.placement(pumpTimeSec: ranAhead.pumpTimeSec, sequenceNum: 10), .dated(phone(1800 + 240)))
    }

    func testARecordNeitherClockPlacesBetweenTheAnchorsIsHeld() {
        let log = record(10, at: 300, ahead: 40 * day)
        let dates = dates([log], anchors: [anchor(9, at: 0), anchor(12, at: 1000, ahead: 3000 * day)], now: 1000)

        XCTAssertEqual(dates.placement(pumpTimeSec: log.pumpTimeSec, sequenceNum: 10), .held(notAfter: phone(1000)))
    }

    func testARecordAboveEveryAnchorIsDatedFromTheOneBelowIt() {
        let log = record(10, at: 300, ahead: 2 * day)
        let dates = dates([log], anchors: [anchor(9, at: 0, ahead: 2 * day)], now: 400)

        XCTAssertEqual(dates.placement(pumpTimeSec: log.pumpTimeSec, sequenceNum: 10), .dated(phone(300)))
    }

    func testAnAnchorAtARecordsOwnSequenceNumberIsAboveIt() {
        let log = record(12, at: 700, ahead: 2 * day)
        let dates = dates([log], anchors: [anchor(12, at: 1000, ahead: 2 * day)], now: 1000)

        XCTAssertEqual(dates.placement(pumpTimeSec: log.pumpTimeSec, sequenceNum: 12), .dated(phone(700)))
    }

    func testWithNoAnchorARecordIsDatedByTheOffsetGivenAndHeldIfThatIsAheadOfThePhone() {
        let stamp = UInt32(pumpZero)
        let onPumpClock = Dates.fromJan12008EpochSecondsToDate(TimeInterval(stamp))
        let log = BolusActivatedHistoryLog(pumpTimeSec: stamp, sequenceNum: 10, bolusId: 1, selectedIob: 0, iob: 0, bolusSize: 1)

        let behind = HistoryRecordDates([log], now: onPumpClock.addingTimeInterval(7200)) { $0.addingTimeInterval(3600) }
        XCTAssertEqual(behind.placement(pumpTimeSec: stamp, sequenceNum: 10), .dated(onPumpClock.addingTimeInterval(3600)))

        let ahead = HistoryRecordDates([log], now: onPumpClock.addingTimeInterval(-7200)) { $0 }
        XCTAssertEqual(ahead.placement(pumpTimeSec: stamp, sequenceNum: 10), .held(notAfter: onPumpClock.addingTimeInterval(-7200)))
    }
}
