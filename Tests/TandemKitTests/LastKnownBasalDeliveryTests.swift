import Foundation
import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class LastKnownBasalDeliveryTests: XCTestCase {
    private static let day = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 700_000_000))
    private static let lastContact = day.addingTimeInterval(.hours(11) + .minutes(30))
    private static let locale = Locale(identifier: "en_US")

    private var manager: TandemPumpManager!

    override func setUp() {
        super.setUp()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth())
        manager.state.basalRateSchedule = BasalRateSchedule(dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: 0.8),
            RepeatingScheduleValue(startTime: .hours(12), value: 1.2)
        ])!
        manager.state.hasSyncedBasalRateSchedule = true
        manager.state.lastReconciliation = Self.lastContact
        manager.state.basalDose = UnfinalizedDose(basalRate: 0.8, insulinType: .novolog, startDate: Self.day)
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    private func runTempBasal(_ rate: Double, endingAt end: Date) {
        let start = Self.lastContact.addingTimeInterval(-.minutes(10))
        manager.state.basalDose = UnfinalizedDose(
            tempRate: rate,
            duration: end.timeIntervalSince(start),
            automatic: true,
            insulinType: .novolog,
            startDate: start
        )
    }

    private func describe(_ delivery: LastKnownBasalDelivery?, at now: Date) throws -> String {
        try XCTUnwrap(delivery).localizedDescription(appName: "Trio", now: now, locale: Self.locale)
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Self.locale
        formatter.timeZone = .current
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - What the pump was doing

    func testAPumpThatHasNeverSyncedHasNothingToReport() {
        manager.state.lastReconciliation = nil

        XCTAssertNil(manager.lastKnownBasalDelivery)
    }

    func testWithNoTempBasalTheProfileRateIsTheOneInForceAtTheLastContact() {
        manager.state.basalDose = UnfinalizedDose(basalRate: 1.2, insulinType: .novolog, startDate: Self.day.addingTimeInterval(-.hours(1)))

        XCTAssertEqual(
            manager.lastKnownBasalDelivery,
            LastKnownBasalDelivery(lastContact: Self.lastContact, delivery: .profile(unitsPerHour: 0.8))
        )
    }

    func testARunningTempBasalReturnsToTheProfileRateInForceAtItsEnd() {
        let end = Self.day.addingTimeInterval(.hours(12) + .minutes(15))
        runTempBasal(0.4, endingAt: end)

        XCTAssertEqual(
            manager.lastKnownBasalDelivery,
            LastKnownBasalDelivery(
                lastContact: Self.lastContact,
                delivery: .tempBasal(unitsPerHour: 0.4, endDate: end, profileUnitsPerHourAfter: 1.2)
            )
        )
    }

    func testATempBasalThatEndedBeforeTheLastContactIsNotDescribedAsRunning() {
        runTempBasal(0.4, endingAt: Self.lastContact)

        XCTAssertEqual(manager.lastKnownBasalDelivery?.delivery, .profile(unitsPerHour: 0.8))
    }

    /// An hour ahead, so the pump's clock has passed noon when the phone's reads 11:45.
    func testOnASkewedPumpClockTheTempEndsIntoThePumpsOwnProfileSegment() {
        manager.state.lastPumpTimeCheckDate = Self.lastContact
        manager.state.currentPumpTime = Self.lastContact.addingTimeInterval(.hours(1))
        manager.state.pumpTimeCheckUTCOffset = TimeZone.current.secondsFromGMT()
        let end = Self.day.addingTimeInterval(.hours(11) + .minutes(45))
        runTempBasal(0.4, endingAt: end)

        XCTAssertEqual(
            manager.lastKnownBasalDelivery?.delivery,
            .tempBasal(unitsPerHour: 0.4, endDate: end, profileUnitsPerHourAfter: 1.2)
        )
    }

    func testASuspendedPumpIsReportedAsSuspended() {
        manager.state.basalDose = UnfinalizedDose(suspendStartTime: Self.lastContact.addingTimeInterval(-.minutes(20)))

        XCTAssertEqual(manager.lastKnownBasalDelivery?.delivery, .suspended)
    }

    func testUnderControlIQThePumpsAlgorithmIsReportedInPlaceOfARate() {
        manager.state.useControlIQ = true
        runTempBasal(0.4, endingAt: Self.lastContact.addingTimeInterval(.minutes(20)))

        XCTAssertEqual(manager.lastKnownBasalDelivery?.delivery, .controlIQ)
    }

    func testASuspendUnderControlIQIsReportedAsSuspended() {
        manager.state.useControlIQ = true
        manager.state.basalDose = UnfinalizedDose(suspendStartTime: Self.lastContact)

        XCTAssertEqual(manager.lastKnownBasalDelivery?.delivery, .suspended)
    }

    /// Until the first schedule sync the pump's profile may not be the app's (#443).
    func testAProfileNeverSyncedFromTheScheduleGivesNoRatesButStillASuspend() {
        manager.state.hasSyncedBasalRateSchedule = false

        XCTAssertNil(manager.lastKnownBasalDelivery)

        manager.state.basalDose = UnfinalizedDose(suspendStartTime: Self.lastContact)

        XCTAssertEqual(manager.lastKnownBasalDelivery?.delivery, .suspended)
    }

    func testAnUntrustedPumpClockGivesNoRates() {
        manager.state.lastPumpTimeCheckDate = Self.lastContact
        manager.state.currentPumpTime = Self.lastContact.addingTimeInterval(.days(3))

        XCTAssertNil(manager.lastKnownBasalDelivery)
    }

    func testAPumpProfileThatDiffersFromTheScheduleGivesNoRates() {
        manager.state.basalRateMismatchDetectedAt = Self.lastContact

        XCTAssertNil(manager.lastKnownBasalDelivery)

        manager.state.basalRateMismatchDetectedAt = nil
        manager.state.basalProfileUpdateFailed = true

        XCTAssertNil(manager.lastKnownBasalDelivery)
    }

    func testAnAllZeroScheduleGivesNoRates() {
        manager.state.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0)])!

        XCTAssertNil(manager.lastKnownBasalDelivery)
    }

    /// History alone gives the replacing temp's duration, so there is no end time to quote.
    func testATempThePumpRunsInPlaceOfTheHeldOneGivesNothing() {
        let held = UnfinalizedDose(
            tempRate: 0.4,
            duration: .minutes(30),
            automatic: true,
            insulinType: .novolog,
            startDate: Self.lastContact.addingTimeInterval(-.minutes(10))
        )
        manager.state.basalDose = held
        manager.state.deliveryTransitions.pending = DeliveryTransitionLedger.PendingTransition(
            prior: held,
            observed: .tempBasal,
            detectedAt: Self.lastContact,
            lastConfirmed: Self.lastContact.addingTimeInterval(-.minutes(5)),
            replacement: .init(start: Self.lastContact.addingTimeInterval(-.minutes(3)), percent: 150, rate: 1.2)
        )

        XCTAssertNil(manager.lastKnownBasalDelivery)
    }

    // MARK: - How it reads

    func testARunningTempBasalSaysWhenThePumpReturnsToItsProfile() throws {
        let end = Self.day.addingTimeInterval(.hours(12) + .minutes(15))
        runTempBasal(0.4, endingAt: end)

        XCTAssertEqual(
            try describe(manager.lastKnownBasalDelivery, at: Self.lastContact.addingTimeInterval(.minutes(5))),
            "Trio last connected to your pump 5 minutes ago. At that time, the pump was delivering basal at a temp rate of 0.40 U/hr, and will return to the profile basal rate of 1.20 U/hr at \(time(end)) if not reconnected."
        )
    }

    func testATempBasalPastItsEndIsExpectedToHaveReturnedToTheProfile() throws {
        let end = Self.day.addingTimeInterval(.hours(12) + .minutes(15))
        runTempBasal(0.4, endingAt: end)

        XCTAssertEqual(
            try describe(manager.lastKnownBasalDelivery, at: end),
            "Trio last connected to your pump 45 minutes ago. At that time, the pump was delivering basal at 0.40 U/hr with a planned end time of \(time(end)). We expect the pump to have returned to its profile basal rate of 1.20 U/hr and it will continue as programmed until reconnected."
        )
    }

    func testNoTempBasalSaysThePumpContinuesAsProgrammed() throws {
        XCTAssertEqual(
            try describe(manager.lastKnownBasalDelivery, at: Self.lastContact.addingTimeInterval(.minutes(1))),
            "Trio last connected to your pump 1 minute ago. At that time, the pump was delivering basal at the profile basal rate of 0.80 U/hr and will continue to deliver basal as programmed until reconnected."
        )
    }

    func testASuspendedPumpSaysTheAppCannotTellWhetherItResumed() throws {
        manager.state.basalDose = UnfinalizedDose(suspendStartTime: Self.lastContact)

        XCTAssertEqual(
            try describe(manager.lastKnownBasalDelivery, at: Self.lastContact.addingTimeInterval(.minutes(16))),
            "Trio last connected to your pump 16 minutes ago. At that time, insulin delivery was suspended. Trio cannot tell whether it has been resumed since."
        )
    }

    func testControlIQSaysThePumpsAlgorithmKeepsRunning() throws {
        manager.state.useControlIQ = true

        XCTAssertEqual(
            try describe(manager.lastKnownBasalDelivery, at: Self.lastContact.addingTimeInterval(.minutes(20))),
            "Trio last connected to your pump 20 minutes ago. At that time, the pump's Control-IQ algorithm was adjusting basal delivery, and it keeps running on the pump whether or not Trio is connected."
        )
    }

    func testAnEndMoreThanHalfADayAwayCarriesItsDate() throws {
        let end = Self.lastContact.addingTimeInterval(.hours(20))
        runTempBasal(0.4, endingAt: end)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Self.locale
        dateFormatter.timeZone = .current
        dateFormatter.dateStyle = .medium

        let text = try describe(manager.lastKnownBasalDelivery, at: Self.lastContact)

        XCTAssertTrue(text.contains(dateFormatter.string(from: end)), text)
        XCTAssertTrue(text.contains(time(end)), text)
    }

    func testTheTimeSinceTheLastContactReadsInTheLargestUnitsThatFit() {
        let cases: [(TimeInterval, String)] = [
            (-30, "less than a minute ago"),
            (59, "less than a minute ago"),
            (.minutes(1), "1 minute ago"),
            (.minutes(59), "59 minutes ago"),
            (.minutes(60), "1 hour ago"),
            (.minutes(65), "1 hour 5 minutes ago"),
            (.hours(2), "2 hours ago"),
            (.hours(25), "1 day 1 hour ago"),
            (.hours(48), "2 days ago")
        ]
        for (interval, expected) in cases {
            XCTAssertEqual(LastKnownBasalDelivery.elapsedDescription(interval), expected, "for \(interval) s")
        }
    }
}
