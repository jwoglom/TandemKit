@testable import TandemKit
import LoopKit
import TandemCore
import XCTest

final class HistoryToDoseMapperTests: XCTestCase {
    func testPairsBolusActivationAndCompletion() {
        let mapper = HistoryToDoseMapper()
        let reconciler = HistoryTimestampReconciler()
        let timeZone = TimeZone(secondsFromGMT: 0)!

        let activated = BolusActivatedHistoryLog(
            pumpTimeSec: 1_000,
            sequenceNum: 1,
            bolusId: 42,
            iob: 0,
            bolusSize: 1.5
        )
        let completed = BolusCompletedHistoryLog(
            pumpTimeSec: 1_060,
            sequenceNum: 2,
            completionStatusId: 0,
            bolusId: 42,
            iob: 0,
            insulinDelivered: 1.4,
            insulinRequested: 1.5
        )

        let events = mapper.mapToEvents([completed, activated], reconciler: reconciler, insulinType: .rapidActingAnalog, timeZone: timeZone)

        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.type, .bolus)
        XCTAssertEqual(event.dose?.type, .bolus)
        XCTAssertEqual(event.dose?.value, 1.5)
        XCTAssertEqual(event.dose?.deliveredUnits, 1.4)
        XCTAssertEqual(event.dose?.startDate, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(event.dose?.endDate, Date(timeIntervalSince1970: 1_060))
        XCTAssertEqual(event.dose?.insulinType, .rapidActingAnalog)
    }

    func testTempBasalUsesDurationForEndDate() {
        let mapper = HistoryToDoseMapper()
        let reconciler = HistoryTimestampReconciler()
        let timeZone = TimeZone(secondsFromGMT: 0)!

        let activated = TempRateActivatedHistoryLog(
            pumpTimeSec: 10_000,
            sequenceNum: 10,
            percent: 150,
            duration: 30,
            tempRateId: 7
        )
        let completed = TempRateCompletedHistoryLog(
            pumpTimeSec: 11_200,
            sequenceNum: 11,
            tempRateId: 7,
            timeLeft: 0
        )

        let events = mapper.mapToEvents([activated, completed], reconciler: reconciler, insulinType: .unknown, timeZone: timeZone)

        let dose = try XCTUnwrap(events.first?.dose)
        XCTAssertEqual(dose.type, .tempBasal)
        XCTAssertEqual(dose.startDate, Date(timeIntervalSince1970: 10_000))
        XCTAssertEqual(dose.endDate, Date(timeIntervalSince1970: 11_800))
        XCTAssertEqual(dose.value, 1.5)
        XCTAssertEqual(dose.unit, .unitsPerHour)
    }

    func testSuspendResumeMapping() {
        let mapper = HistoryToDoseMapper()
        let reconciler = HistoryTimestampReconciler()
        let timeZone = TimeZone(secondsFromGMT: 0)!

        let suspend = PumpingSuspendedHistoryLog(
            pumpTimeSec: 20_000,
            sequenceNum: 20,
            insulinAmount: 0,
            reasonId: PumpingSuspendedHistoryLog.SuspendReason.autoSuspendPredictiveLowGlucose.rawValue
        )
        let resume = PumpingResumedHistoryLog(
            pumpTimeSec: 20_600,
            sequenceNum: 21,
            insulinAmount: 0
        )

        let events = mapper.mapToEvents([suspend, resume], reconciler: reconciler, insulinType: .ultraRapidActing, timeZone: timeZone)
        XCTAssertEqual(events.map { $0.type }, [.suspend, .resume])

        XCTAssertEqual(events[0].dose?.type, .suspend)
        XCTAssertEqual(events[0].dose?.startDate, Date(timeIntervalSince1970: 20_000))
        XCTAssertEqual(events[1].dose?.type, .resume)
        XCTAssertEqual(events[1].dose?.startDate, Date(timeIntervalSince1970: 20_600))
    }

    func testClockChangeAdjustsSubsequentEvents() {
        let mapper = HistoryToDoseMapper()
        let reconciler = HistoryTimestampReconciler()
        let timeZone = TimeZone(secondsFromGMT: 0)!

        let clockChange = TimeChangedHistoryLog(
            pumpTimeSec: 30,
            sequenceNum: 2,
            timePrior: 30,
            timeAfter: 3_630,
            rawRTC: 0
        )
        let completed = BolusCompletedHistoryLog(
            pumpTimeSec: 3_700,
            sequenceNum: 3,
            completionStatusId: 0,
            bolusId: 1,
            iob: 0,
            insulinDelivered: 1,
            insulinRequested: 1
        )

        let events = mapper.mapToEvents([clockChange, completed], reconciler: reconciler, insulinType: nil, timeZone: timeZone)

        let dose = try XCTUnwrap(events.first?.dose)
        XCTAssertEqual(dose.startDate, Date(timeIntervalSince1970: 3_700 + 3_600))
    }

    func testUnpairedBolusActivationGeneratesMutableEvent() {
        let mapper = HistoryToDoseMapper()
        let reconciler = HistoryTimestampReconciler()
        let timeZone = TimeZone(secondsFromGMT: 0)!

        let activation = BolusActivatedHistoryLog(
            pumpTimeSec: 50,
            sequenceNum: 10,
            bolusId: 12,
            iob: 0,
            bolusSize: 2.5
        )

        let events = mapper.mapToEvents([activation], reconciler: reconciler, insulinType: nil, timeZone: timeZone)

        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].isMutable)
        XCTAssertEqual(events[0].dose?.type, .bolus)
        XCTAssertNil(events[0].dose?.deliveredUnits)
        XCTAssertEqual(events[0].dose?.value, 2.5)
    }

    func testUnpairedTempBasalActivationGeneratesMutableEvent() {
        let mapper = HistoryToDoseMapper()
        let reconciler = HistoryTimestampReconciler()
        let timeZone = TimeZone(secondsFromGMT: 0)!

        let activation = TempRateActivatedHistoryLog(
            pumpTimeSec: 400,
            sequenceNum: 40,
            percent: 200,
            duration: 15,
            tempRateId: 5
        )

        let events = mapper.mapToEvents([activation], reconciler: reconciler, insulinType: nil, timeZone: timeZone)

        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].isMutable)
        XCTAssertEqual(events[0].dose?.type, .tempBasal)
        XCTAssertEqual(events[0].dose?.endDate, Date(timeIntervalSince1970: 400 + (15 * 60)))
    }
}
