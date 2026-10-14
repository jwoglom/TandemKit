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
        isCommandedBolus: @escaping (Int) -> Bool = { _ in false },
        hostDate: @escaping (Date) -> Date = { $0 }
    ) -> [NewPumpEvent] {
        HistoryToDoseMapper().mapToEvents(
            logs,
            dates: HistoryRecordDates(logs, hostDate: hostDate),
            pumpSerial: serial,
            insulinType: insulinType,
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
        XCTAssertEqual(event.date, pumpDate(1000), "Dated at activation, not completion")
        XCTAssertEqual(dose.programmedUnits, 2.5)
        XCTAssertEqual(dose.deliveredUnits, 2.5)
        XCTAssertFalse(dose.isMutable)
        XCTAssertEqual(dose.syncIdentifier, event.raw.hexadecimalString)
        // isCommandedBolus returned false, so this is a pump-UI (quick / Control-IQ) bolus.
        XCTAssertTrue(dose.wasProgrammedByPumpUI)
        XCTAssertEqual(dose.automatic, false, "Trio reads a nil automatic as an SMB")
    }

    func testControlIQBolusIsAutomatic() throws {
        let events = map([
            BolusActivatedHistoryLog(pumpTimeSec: 1000, sequenceNum: 1, bolusId: 7, selectedIob: 0, iob: 0, bolusSize: 0.4),
            BolusDeliveryHistoryLog(
                pumpTimeSec: 1000,
                sequenceNum: 2,
                bolusID: 7,
                bolusDeliveryStatus: 1,
                bolusTypeBitmask: 8,
                bolusSource: BolusDeliveryHistoryLog.BolusSource.controlIQAutoBolus.rawValue,
                remoteId: 0,
                requestedNow: 400,
                requestedLater: 0,
                correction: 400,
                extendedDurationRequested: 0,
                deliveredTotal: 0
            )
        ])

        XCTAssertEqual(try XCTUnwrap(events.first?.dose).automatic, true)
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

    func testBasalSuspendResumeAndAlarmRecordsAreNotMapped() {
        let events = map([
            TempRateActivatedHistoryLog(pumpTimeSec: 1000, sequenceNum: 10, percent: 150, durationMilliseconds: 1_800_000, tempRateId: 4),
            TempRateCompletedHistoryLog(pumpTimeSec: 1600, sequenceNum: 11, tempRateId: 4, timeLeft: 1_200_000),
            BasalRateChangeHistoryLog(
                pumpTimeSec: 1700,
                sequenceNum: 12,
                commandBasalRate: 1,
                baseBasalRate: 1,
                maxBasalRate: 3,
                insulinDeliveryProfile: 1,
                changeTypeId: 1
            ),
            PumpingSuspendedHistoryLog(pumpTimeSec: 1800, sequenceNum: 13, preSuspendState: 0, insulinAmount: 0, reasonId: 0, rpaTimeout: 0),
            PumpingResumedHistoryLog(pumpTimeSec: 1900, sequenceNum: 14, preResumeState: 0, insulinAmount: 0),
            AlarmActivatedHistoryLog(pumpTimeSec: 2000, sequenceNum: 15, alarmId: 2)
        ])

        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Extended boluses (#424)

    private func bolexActivation(bolusId: Int, units: Float, at pumpTimeSec: UInt32, sequenceNum: UInt32) -> BolexActivatedHistoryLog {
        BolexActivatedHistoryLog(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, bolusId: bolusId, iob: 0, bolexSize: units)
    }

    private func bolexCompletion(
        bolusId: Int,
        delivered: Float,
        requested: Float,
        stoppedEarly: Bool = false,
        at pumpTimeSec: UInt32,
        sequenceNum: UInt32
    ) -> BolexCompletedHistoryLog {
        BolexCompletedHistoryLog(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            completionStatus: stoppedEarly ? 0 : 3,
            bolusId: bolusId,
            iob: delivered,
            insulinDelivered: delivered,
            insulinRequested: requested
        )
    }

    private func bolusDelivery(bolusId: Int, extendedMinutes: Int, at pumpTimeSec: UInt32, sequenceNum: UInt32) -> BolusDeliveryHistoryLog {
        BolusDeliveryHistoryLog(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            bolusID: bolusId,
            bolusDeliveryStatus: 1,
            bolusTypeBitmask: 3,
            bolusSource: BolusDeliveryHistoryLog.BolusSource.gui.rawValue,
            remoteId: bolusId & 0xFF,
            requestedNow: 1000,
            requestedLater: 2000,
            correction: 0,
            extendedDurationRequested: extendedMinutes,
            deliveredTotal: 0
        )
    }

    func testAnExtendedBolusWithAnUpFrontPartIsTwoDoses() throws {
        let events = map([
            bolusDelivery(bolusId: 12, extendedMinutes: 120, at: 1000, sequenceNum: 1),
            BolusActivatedHistoryLog(pumpTimeSec: 1000, sequenceNum: 2, bolusId: 12, selectedIob: 0, iob: 0, bolusSize: 1.0),
            BolusCompletedHistoryLog(
                pumpTimeSec: 1040,
                sequenceNum: 3,
                completionStatusId: 3,
                bolusId: 12,
                iob: 1,
                insulinDelivered: 1,
                insulinRequested: 1
            ),
            bolexActivation(bolusId: 12, units: 2.0, at: 1041, sequenceNum: 4),
            bolexCompletion(bolusId: 12, delivered: 2.0, requested: 2.0, at: 1041 + 7200, sequenceNum: 5)
        ])

        XCTAssertEqual(events.map(\.raw), [
            HistoryLogSyncIdentifier.bolus(pumpSerial: serial, bolusId: 12),
            HistoryLogSyncIdentifier.extendedBolus(pumpSerial: serial, bolusId: 12)
        ])
        XCTAssertEqual(events[0].dose?.deliveredUnits, 1.0, "BolusCompleted counts the up-front part alone")

        let extended = try XCTUnwrap(events[1].dose)
        XCTAssertEqual(events[1].type, .bolus)
        XCTAssertEqual(events[1].date, pumpDate(1041))
        XCTAssertEqual(extended.type, .bolus)
        XCTAssertEqual(extended.startDate, pumpDate(1041))
        XCTAssertEqual(extended.endDate, pumpDate(1041 + 7200))
        XCTAssertEqual(extended.programmedUnits, 2.0)
        XCTAssertEqual(extended.deliveredUnits, 2.0)
        XCTAssertFalse(extended.isMutable)
        XCTAssertEqual(extended.syncIdentifier, events[1].raw.hexadecimalString)
        XCTAssertTrue(extended.wasProgrammedByPumpUI)
        XCTAssertEqual(extended.automatic, false)
    }

    func testAFullyExtendedBolusIsOneExtendedDose() throws {
        let events = map([
            bolexActivation(bolusId: 13, units: 2.0, at: 1000, sequenceNum: 1),
            bolexCompletion(bolusId: 13, delivered: 2.0, requested: 2.0, at: 1000 + 1800, sequenceNum: 2)
        ])

        XCTAssertEqual(events.map(\.raw), [HistoryLogSyncIdentifier.extendedBolus(pumpSerial: serial, bolusId: 13)])
        let dose = try XCTUnwrap(events.first?.dose)
        XCTAssertEqual(dose.startDate, pumpDate(1000))
        XCTAssertEqual(dose.endDate, pumpDate(1000 + 1800))
        XCTAssertEqual(dose.deliveredUnits, 2.0)
        XCTAssertFalse(dose.isMutable)
    }

    func testAnExtendedPartStoppedEarlyEndsAtItsCompletionWithWhatItDelivered() throws {
        let events = map([
            bolusDelivery(bolusId: 14, extendedMinutes: 120, at: 1000, sequenceNum: 1),
            bolexActivation(bolusId: 14, units: 2.0, at: 1000, sequenceNum: 2),
            bolexCompletion(bolusId: 14, delivered: 0.75, requested: 2.0, stoppedEarly: true, at: 1000 + 2700, sequenceNum: 3)
        ])

        let dose = try XCTUnwrap(events.first?.dose)
        XCTAssertEqual(dose.endDate, pumpDate(1000 + 2700), "at the stop, not the programmed end")
        XCTAssertEqual(dose.programmedUnits, 2.0)
        XCTAssertEqual(dose.deliveredUnits, 0.75)
        XCTAssertFalse(dose.isMutable)
    }

    func testAnExtendedPartInFlightIsMutableOverItsProgrammedDuration() throws {
        let events = map([
            bolusDelivery(bolusId: 15, extendedMinutes: 90, at: 1000, sequenceNum: 1),
            bolexActivation(bolusId: 15, units: 3.0, at: 1001, sequenceNum: 2)
        ])

        XCTAssertEqual(events.map(\.raw), [HistoryLogSyncIdentifier.extendedBolus(pumpSerial: serial, bolusId: 15)])
        let dose = try XCTUnwrap(events.first?.dose)
        XCTAssertTrue(dose.isMutable)
        XCTAssertEqual(dose.startDate, pumpDate(1001))
        XCTAssertEqual(dose.endDate, pumpDate(1001 + 90 * 60))
        XCTAssertEqual(dose.programmedUnits, 3.0)
        XCTAssertNil(dose.deliveredUnits)
    }

    private func extendedRequest(bolusId: Int, standardPercent: Int, minutes: Int, at pumpTimeSec: UInt32, sequenceNum: UInt32) -> BolusRequestedMsg2HistoryLog {
        BolusRequestedMsg2HistoryLog(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            bolusId: bolusId,
            options: BolusRequestedMsg2HistoryLog.BolusOption.extended.rawValue,
            standardPercent: standardPercent,
            duration: minutes,
            spare1: 0,
            isf: 0,
            targetBG: 0,
            userOverride: false,
            declinedCorrection: false,
            selectedIOB: 0,
            spare2: 0
        )
    }

    func testAnExtendedPartInFlightTakesItsDurationFromTheRequestWithoutBolusDeliveryRecords() throws {
        let events = map([
            extendedRequest(bolusId: 20, standardPercent: 50, minutes: 60, at: 1000, sequenceNum: 1),
            BolusActivatedHistoryLog(pumpTimeSec: 1015, sequenceNum: 2, bolusId: 20, selectedIob: 0, iob: 0, bolusSize: 0.75),
            BolusCompletedHistoryLog(
                pumpTimeSec: 1055,
                sequenceNum: 3,
                completionStatusId: 3,
                bolusId: 20,
                iob: 0.75,
                insulinDelivered: 0.75,
                insulinRequested: 0.75
            ),
            bolexActivation(bolusId: 20, units: 0.75, at: 1055, sequenceNum: 4)
        ])

        let extended = try XCTUnwrap(events.first { $0.raw == HistoryLogSyncIdentifier.extendedBolus(pumpSerial: serial, bolusId: 20) }?.dose)
        XCTAssertTrue(extended.isMutable)
        XCTAssertEqual(extended.endDate, pumpDate(1055 + 60 * 60))
    }

    func testBolusDeliveryRecordsWinOverTheRequestForTheDuration() throws {
        let events = map([
            extendedRequest(bolusId: 21, standardPercent: 0, minutes: 45, at: 1000, sequenceNum: 1),
            bolusDelivery(bolusId: 21, extendedMinutes: 30, at: 1015, sequenceNum: 2),
            bolexActivation(bolusId: 21, units: 2.0, at: 1015, sequenceNum: 3)
        ])

        XCTAssertEqual(try XCTUnwrap(events.first?.dose).endDate, pumpDate(1015 + 30 * 60))
    }

    func testAnExtendedPartInFlightWithoutItsDurationCountsAtItsStart() throws {
        let events = map([bolexActivation(bolusId: 16, units: 3.0, at: 1000, sequenceNum: 1)])

        let dose = try XCTUnwrap(events.first?.dose)
        XCTAssertTrue(dose.isMutable)
        XCTAssertEqual(dose.endDate, dose.startDate)
    }

    func testABolexCompletionWithoutItsActivationIsNotMapped() {
        let events = map([bolexCompletion(bolusId: 17, delivered: 2.0, requested: 2.0, at: 5000, sequenceNum: 9)])

        XCTAssertTrue(events.isEmpty, "\(events)")
    }

    func testAnExtendedPartStartingInItsUpFrontPartsSecondStartsASecondLater() throws {
        let events = map([
            BolusActivatedHistoryLog(pumpTimeSec: 1000, sequenceNum: 1, bolusId: 18, selectedIob: 0, iob: 0, bolusSize: 0.05),
            BolusCompletedHistoryLog(
                pumpTimeSec: 1000,
                sequenceNum: 2,
                completionStatusId: 3,
                bolusId: 18,
                iob: 0.05,
                insulinDelivered: 0.05,
                insulinRequested: 0.05
            ),
            bolexActivation(bolusId: 18, units: 1.0, at: 1000, sequenceNum: 3),
            bolexCompletion(bolusId: 18, delivered: 1.0, requested: 1.0, at: 1600, sequenceNum: 4)
        ])

        XCTAssertEqual(events.map(\.date), [pumpDate(1000), pumpDate(1001)])
        XCTAssertEqual(events.last?.dose?.startDate, pumpDate(1001))
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

    func testDatesAreOnThePhonesClock() throws {
        let events = map(
            [
                BolusActivatedHistoryLog(pumpTimeSec: 1000, sequenceNum: 1, bolusId: 3, selectedIob: 0, iob: 0, bolusSize: 1.0),
                BolusCompletedHistoryLog(
                    pumpTimeSec: 1300,
                    sequenceNum: 2,
                    completionStatusId: 0,
                    bolusId: 3,
                    iob: 1,
                    insulinDelivered: 1,
                    insulinRequested: 1
                ),
                TimeChangedHistoryLog(pumpTimeSec: 5000, sequenceNum: 3, timePrior: 0, timeAfter: 3_600_000, rawRTC: 0)
            ],
            hostDate: { $0.addingTimeInterval(-.hours(3)) }
        )

        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.date, pumpDate(1000 + 3600 - 3 * 3600))
        XCTAssertEqual(event.dose?.endDate, pumpDate(1300 + 3600 - 3 * 3600))
    }

    func testEventsAreSortedAscendingByDate() {
        // Feed the window out of order, with the in-flight bolus (appended after the main loop)
        // dated earliest, to pin the final sort.
        let events = map([
            BolusCompletedHistoryLog(
                pumpTimeSec: 9000,
                sequenceNum: 40,
                completionStatusId: 0,
                bolusId: 8,
                iob: 1,
                insulinDelivered: 1,
                insulinRequested: 1
            ),
            BolusActivatedHistoryLog(pumpTimeSec: 1000, sequenceNum: 1, bolusId: 6, selectedIob: 0, iob: 0, bolusSize: 1.0),
            BolusCompletedHistoryLog(
                pumpTimeSec: 5000,
                sequenceNum: 20,
                completionStatusId: 0,
                bolusId: 7,
                iob: 1,
                insulinDelivered: 1,
                insulinRequested: 1
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
