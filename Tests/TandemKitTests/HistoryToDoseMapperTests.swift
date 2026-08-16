import LoopKit
@testable import TandemKit
import XCTest

final class HistoryToDoseMapperTests: XCTestCase {
    private let serial = HistoryLogSyncIdentifier.PumpSerial(12345)!

    private func pumpDate(_ pumpTimeSec: Int) -> Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(pumpTimeSec))
    }

    private func map(
        _ logs: [HistoryLog],
        insulinType: InsulinType? = nil,
        scheduledBasalRate: @escaping (Date) -> Double = { _ in 1.0 },
        roundBasalRate: @escaping (Double) -> Double = { ($0 * 100).rounded() / 100 },
        isCommandedBolus: @escaping (Int) -> Bool = { _ in false }
    ) -> [NewPumpEvent] {
        HistoryToDoseMapper().mapToEvents(
            logs,
            reconciler: HistoryTimestampReconciler(),
            pumpSerial: serial,
            insulinType: insulinType,
            scheduledBasalRate: scheduledBasalRate,
            roundBasalRate: roundBasalRate,
            isCommandedBolus: isCommandedBolus
        )
    }

    // MARK: - Boluses

    func testMatchedBolusProducesFinalizedDose() throws {
        let events = map([
            BolusActivatedHistoryLog(pumpTimeSec: 1000, sequenceNum: 1, bolusId: 7, selectedIob: 0, iob: 0, bolusSize: 2.5),
            BolusCompletedHistoryLog(
                pumpTimeSec: 1300,
                sequenceNum: 2,
                completionStatusId: 0,
                bolusId: 7,
                iob: 2.5,
                insulinDelivered: 2.5,
                insulinRequested: 2.5
            )
        ])

        XCTAssertEqual(events.count, 1)
        let event = events[0]
        XCTAssertEqual(event.type, .bolus)
        XCTAssertEqual(event.raw, HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 7))

        let dose = try XCTUnwrap(event.dose)
        XCTAssertEqual(dose.type, .bolus)
        XCTAssertEqual(dose.startDate, pumpDate(1000))
        XCTAssertEqual(dose.endDate, pumpDate(1300))
        XCTAssertEqual(event.date, pumpDate(1300))
        XCTAssertEqual(dose.programmedUnits, 2.5)
        XCTAssertEqual(dose.deliveredUnits, 2.5)
        XCTAssertFalse(dose.isMutable)
        XCTAssertEqual(dose.syncIdentifier, event.raw.hexadecimalString)
        // isCommandedBolus returned false, so this is a pump-UI (quick / Control-IQ) bolus.
        XCTAssertTrue(dose.wasProgrammedByPumpUI)
    }

    func testCommandedBolusIsNotMarkedAsPumpUI() throws {
        let events = map(
            [
                BolusCompletedHistoryLog(
                    pumpTimeSec: 1300,
                    sequenceNum: 2,
                    completionStatusId: 0,
                    bolusId: 7,
                    iob: 1,
                    insulinDelivered: 1,
                    insulinRequested: 1
                )
            ],
            isCommandedBolus: { $0 == 7 }
        )

        let dose = try XCTUnwrap(events.first?.dose)
        XCTAssertFalse(dose.wasProgrammedByPumpUI)
    }

    func testBolusUnitsRoundedToReportingResolution() throws {
        // Float(0.9) is 0.89999997615814; reporting must not preserve that noise, nor floor a
        // partial delivery down a whole increment.
        let events = map([
            BolusActivatedHistoryLog(pumpTimeSec: 1000, sequenceNum: 1, bolusId: 3, selectedIob: 0, iob: 0, bolusSize: 0.9),
            BolusCompletedHistoryLog(
                pumpTimeSec: 1100,
                sequenceNum: 2,
                completionStatusId: 0,
                bolusId: 3,
                iob: 0.9,
                insulinDelivered: 0.9,
                insulinRequested: 0.9
            )
        ])

        let dose = try XCTUnwrap(events.first?.dose)
        XCTAssertEqual(dose.programmedUnits, 0.9)
        XCTAssertEqual(dose.deliveredUnits, 0.9)
    }

    func testCancelledBolusKeepsProgrammedAndDeliveredDistinct() throws {
        let events = map([
            BolusActivatedHistoryLog(pumpTimeSec: 1000, sequenceNum: 1, bolusId: 4, selectedIob: 0, iob: 0, bolusSize: 2.5),
            BolusCompletedHistoryLog(
                pumpTimeSec: 1200,
                sequenceNum: 2,
                completionStatusId: 0,
                bolusId: 4,
                iob: 1.041,
                insulinDelivered: 1.041,
                insulinRequested: 2.5
            )
        ])

        let dose = try XCTUnwrap(events.first?.dose)
        XCTAssertEqual(dose.programmedUnits, 2.5)
        XCTAssertEqual(dose.deliveredUnits, 1.041)
    }

    func testActivationWithoutCompletionIsMutable() throws {
        let events = map([
            BolusActivatedHistoryLog(pumpTimeSec: 1000, sequenceNum: 1, bolusId: 9, selectedIob: 0, iob: 0, bolusSize: 3.0)
        ])

        XCTAssertEqual(events.count, 1)
        let event = events[0]
        XCTAssertEqual(event.raw, HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 9))

        let dose = try XCTUnwrap(event.dose)
        XCTAssertTrue(dose.isMutable)
        XCTAssertEqual(dose.startDate, pumpDate(1000))
        XCTAssertEqual(dose.programmedUnits, 3.0)
        XCTAssertNil(dose.deliveredUnits)
        XCTAssertEqual(dose.syncIdentifier, event.raw.hexadecimalString)
    }

    func testCompletionWithoutActivationUsesRequestedUnitsAndCompletionTime() throws {
        let events = map([
            BolusCompletedHistoryLog(
                pumpTimeSec: 1300,
                sequenceNum: 2,
                completionStatusId: 0,
                bolusId: 5,
                iob: 1.2,
                insulinDelivered: 1.2,
                insulinRequested: 1.2
            )
        ])

        let dose = try XCTUnwrap(events.first?.dose)
        XCTAssertEqual(dose.startDate, pumpDate(1300))
        XCTAssertEqual(dose.endDate, pumpDate(1300))
        XCTAssertEqual(dose.programmedUnits, 1.2)
        XCTAssertFalse(dose.isMutable)
    }

    // MARK: - Temp basals

    func testMatchedTempBasalConvertsPercentToAbsoluteRate() throws {
        let events = map(
            [
                TempRateActivatedHistoryLog(
                    pumpTimeSec: 1000,
                    sequenceNum: 1,
                    percent: 150,
                    durationMilliseconds: 1_800_000,
                    tempRateId: 11
                ),
                // Completion stamped a few seconds after the programmed end; delivery cannot
                // outlive the programmed window.
                TempRateCompletedHistoryLog(pumpTimeSec: 2803, sequenceNum: 2, tempRateId: 11, timeLeft: 0)
            ],
            scheduledBasalRate: { _ in 0.8 }
        )

        XCTAssertEqual(events.count, 1)
        let event = events[0]
        XCTAssertEqual(event.type, .tempBasal)
        XCTAssertEqual(event.raw, HistoryLogSyncIdentifier.tempRate(pumpSerial: serial, tempRateId: 11))

        let dose = try XCTUnwrap(event.dose)
        XCTAssertEqual(dose.type, .tempBasal)
        XCTAssertEqual(dose.unit, .unitsPerHour)
        XCTAssertEqual(dose.unitsPerHour, 1.2, accuracy: 1e-9)
        XCTAssertEqual(dose.startDate, pumpDate(1000))
        XCTAssertEqual(dose.endDate, pumpDate(1000 + 1800))
        XCTAssertFalse(dose.isMutable)
        XCTAssertEqual(dose.syncIdentifier, event.raw.hexadecimalString)
    }

    func testEarlyCancelledTempBasalEndsAtCompletion() throws {
        let events = map([
            TempRateActivatedHistoryLog(
                pumpTimeSec: 1000,
                sequenceNum: 1,
                percent: 50,
                durationMilliseconds: 1_800_000,
                tempRateId: 12
            ),
            TempRateCompletedHistoryLog(pumpTimeSec: 1600, sequenceNum: 2, tempRateId: 12, timeLeft: 1200)
        ])

        let dose = try XCTUnwrap(events.first?.dose)
        XCTAssertEqual(dose.endDate, pumpDate(1600))
    }

    func testTempBasalActivationWithoutCompletionIsMutable() throws {
        let events = map([
            TempRateActivatedHistoryLog(
                pumpTimeSec: 1000,
                sequenceNum: 1,
                percent: 200,
                durationMilliseconds: 3_600_000,
                tempRateId: 13
            )
        ])

        let dose = try XCTUnwrap(events.first?.dose)
        XCTAssertTrue(dose.isMutable)
        XCTAssertEqual(dose.endDate, pumpDate(1000 + 3600))
    }

    func testTempBasalCompletionWithoutActivationIsDropped() {
        // The percent, duration and start time all live on the activation record, so a
        // completion alone cannot be mapped.
        let events = map([
            TempRateCompletedHistoryLog(pumpTimeSec: 1600, sequenceNum: 2, tempRateId: 14, timeLeft: 0)
        ])

        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Basal changes, suspend/resume, alarms

    func testBasalRateChangeMapsToBasalEvent() throws {
        let events = map([
            BasalRateChangeHistoryLog(
                pumpTimeSec: 2000,
                sequenceNum: 8,
                commandBasalRate: 1.15,
                baseBasalRate: 1.15,
                maxBasalRate: 3,
                insulinDeliveryProfile: 1,
                changeTypeId: 1
            )
        ])

        XCTAssertEqual(events.count, 1)
        let event = events[0]
        XCTAssertEqual(event.type, .basal)
        XCTAssertEqual(event.raw, HistoryLogSyncIdentifier.logSequence(pumpSerial: serial, sequenceNum: 8))

        let dose = try XCTUnwrap(event.dose)
        XCTAssertEqual(dose.type, .basal)
        XCTAssertEqual(dose.startDate, pumpDate(2000))
        XCTAssertEqual(dose.unitsPerHour, 1.15, accuracy: 1e-6)
        XCTAssertEqual(dose.unit, .unitsPerHour)
    }

    func testSuspendAndResumeMapToLedgerEvents() throws {
        let events = map([
            PumpingSuspendedHistoryLog(pumpTimeSec: 3000, sequenceNum: 20, preSuspendState: 0, insulinAmount: 100, reasonId: 0, rpaTimeout: 0),
            PumpingResumedHistoryLog(pumpTimeSec: 3600, sequenceNum: 21, preResumeState: 0, insulinAmount: 100)
        ])

        XCTAssertEqual(events.count, 2)

        let suspend = events[0]
        XCTAssertEqual(suspend.type, .suspend)
        XCTAssertEqual(suspend.date, pumpDate(3000))
        XCTAssertEqual(suspend.raw, HistoryLogSyncIdentifier.logSequence(pumpSerial: serial, sequenceNum: 20))
        XCTAssertEqual(try XCTUnwrap(suspend.dose).type, .suspend)

        let resume = events[1]
        XCTAssertEqual(resume.type, .resume)
        XCTAssertEqual(resume.date, pumpDate(3600))
        XCTAssertEqual(resume.raw, HistoryLogSyncIdentifier.logSequence(pumpSerial: serial, sequenceNum: 21))
        XCTAssertEqual(try XCTUnwrap(resume.dose).type, .resume)
    }

    func testAlarmAndAlertMapToDoselessAlarmEvents() {
        let events = map([
            AlarmActivatedHistoryLog(pumpTimeSec: 4000, sequenceNum: 30, alarmId: 5),
            AlertActivatedHistoryLog(pumpTimeSec: 4100, sequenceNum: 31, alertId: 2)
        ])

        XCTAssertEqual(events.count, 2)
        for event in events {
            XCTAssertEqual(event.type, .alarm)
            XCTAssertNil(event.dose)
        }
        XCTAssertEqual(events[0].raw, HistoryLogSyncIdentifier.logSequence(pumpSerial: serial, sequenceNum: 30))
        XCTAssertEqual(events[1].raw, HistoryLogSyncIdentifier.logSequence(pumpSerial: serial, sequenceNum: 31))
    }

    // MARK: - Cross-cutting behaviour

    func testClockChangeInWindowAdjustsEarlierRecords() throws {
        // The bolus was written an hour before the user fixed a clock that ran an hour slow;
        // its reported dates must land on the corrected clock.
        let events = map([
            BolusActivatedHistoryLog(pumpTimeSec: 1000, sequenceNum: 1, bolusId: 2, selectedIob: 0, iob: 0, bolusSize: 1.0),
            BolusCompletedHistoryLog(
                pumpTimeSec: 1300,
                sequenceNum: 2,
                completionStatusId: 0,
                bolusId: 2,
                iob: 1,
                insulinDelivered: 1,
                insulinRequested: 1
            ),
            TimeChangedHistoryLog(pumpTimeSec: 5000, sequenceNum: 3, timePrior: 0, timeAfter: 3_600_000, rawRTC: 0)
        ])

        let dose = try XCTUnwrap(events.first?.dose)
        XCTAssertEqual(dose.startDate, pumpDate(1000 + 3600))
        XCTAssertEqual(dose.endDate, pumpDate(1300 + 3600))
    }

    func testEventsAreSortedAscendingByDate() {
        // Feed the window out of order, with the in-flight bolus (appended after the main loop)
        // dated earliest, to pin the final sort.
        let events = map([
            PumpingSuspendedHistoryLog(pumpTimeSec: 9000, sequenceNum: 40, preSuspendState: 0, insulinAmount: 0, reasonId: 0, rpaTimeout: 0),
            BolusActivatedHistoryLog(pumpTimeSec: 1000, sequenceNum: 1, bolusId: 6, selectedIob: 0, iob: 0, bolusSize: 1.0),
            BasalRateChangeHistoryLog(
                pumpTimeSec: 5000,
                sequenceNum: 20,
                commandBasalRate: 1,
                baseBasalRate: 1,
                maxBasalRate: 3,
                insulinDeliveryProfile: 1,
                changeTypeId: 1
            )
        ])

        XCTAssertEqual(events.map(\.date), [pumpDate(1000), pumpDate(5000), pumpDate(9000)])
    }

    func testInsulinTypePropagatesToDoses() throws {
        let events = map(
            [
                BolusCompletedHistoryLog(
                    pumpTimeSec: 1300,
                    sequenceNum: 2,
                    completionStatusId: 0,
                    bolusId: 1,
                    iob: 1,
                    insulinDelivered: 1,
                    insulinRequested: 1
                )
            ],
            insulinType: .novolog
        )

        XCTAssertEqual(try XCTUnwrap(events.first?.dose).insulinType, .novolog)
    }

    func testUnhandledLogTypesAreIgnored() {
        let events = map([
            UnknownHistoryLog(cargo: Data(count: HistoryLog.length)),
            CarbEnteredHistoryLog(cargo: Data(count: HistoryLog.length))
        ])

        XCTAssertTrue(events.isEmpty)
    }
}
