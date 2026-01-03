@testable import TandemKit
import LoopKit
import XCTest

final class HistoryReconcilerTests: XCTestCase {
    func testMatchesPendingBolusByTimeAndUnits() {
        let reconciler = HistoryReconciler()
        let now = Date()

        let pendingDose = DoseEntry(
            type: .bolus,
            startDate: now,
            value: 1.25,
            unit: .units,
            deliveredUnits: 1.2
        )
        let pending = PendingDose(
            syncIdentifier: "pending-bolus",
            dose: pendingDose,
            requestedAt: now
        )

        let eventDose = DoseEntry(
            type: .bolus,
            startDate: now.addingTimeInterval(60),
            value: 1.25,
            unit: .units,
            deliveredUnits: 1.19
        )
        let event = NewPumpEvent(
            date: eventDose.endDate,
            dose: eventDose,
            raw: Data([0x01]),
            title: "Bolus",
            type: .bolus
        )

        let result = reconciler.reconcile(pendingDoses: [pending], historyEvents: [event], now: now)

        XCTAssertEqual(result.reconciledEvents.count, 1)
        let reconciledDose = try XCTUnwrap(result.reconciledEvents.first?.dose)
        XCTAssertEqual(reconciledDose.syncIdentifier, "pending-bolus")
        XCTAssertTrue(result.stillPending.isEmpty)
        XCTAssertTrue(result.uncertainPending.isEmpty)
    }

    func testLeavesUnmatchedPending() {
        let reconciler = HistoryReconciler()
        let now = Date()

        let pendingDose = DoseEntry(
            type: .tempBasal,
            startDate: now,
            value: 2.0,
            unit: .unitsPerHour
        )
        let pending = PendingDose(
            syncIdentifier: "pending-temp",
            dose: pendingDose,
            requestedAt: now
        )

        let result = reconciler.reconcile(pendingDoses: [pending], historyEvents: [], now: now)

        XCTAssertEqual(result.stillPending.count, 1)
        XCTAssertTrue(result.uncertainPending.isEmpty)
    }

    func testMarksOldPendingAsUncertain() {
        let reconciler = HistoryReconciler()
        let now = Date()
        let oldDate = now.addingTimeInterval(-30 * 60 * 60)

        let pendingDose = DoseEntry(
            type: .suspend,
            startDate: oldDate,
            value: 0,
            unit: .units
        )
        let pending = PendingDose(
            syncIdentifier: "stale",
            dose: pendingDose,
            requestedAt: oldDate
        )

        let result = reconciler.reconcile(pendingDoses: [pending], historyEvents: [], now: now)

        XCTAssertEqual(result.uncertainPending.count, 1)
        XCTAssertEqual(result.uncertainPending.first?.syncIdentifier, "stale")
    }
}
