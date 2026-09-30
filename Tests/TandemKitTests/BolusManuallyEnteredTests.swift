import LoopKit
@testable import TandemKit
import XCTest

/// LoopKit's `manuallyEntered` marks insulin the pump did not deliver, and Trio stores it as
/// `isExternal`; every bolus TandemKit reports went through the pump (#337).
@available(macOS 13.0, iOS 14.0, *) final class BolusManuallyEnteredTests: XCTestCase {
    private static let activationTypes: [BolusActivationType] = [
        .automatic,
        .manualNoRecommendation,
        .manualRecommendationAccepted,
        .manualRecommendationChanged,
        .none
    ]

    private static let startDate = Date(timeIntervalSinceReferenceDate: 700_000_000)

    func testMutableBolusIsNeverManuallyEntered() {
        for activationType in Self.activationTypes {
            let dose = DoseEntry.bolus(
                units: 2,
                deliveredUnits: 0,
                duration: .minutes(1),
                activationType: activationType,
                insulinType: .novolog,
                startDate: Self.startDate,
                now: Self.startDate
            )

            XCTAssertTrue(dose.isMutable)
            XCTAssertFalse(dose.manuallyEntered, "\(activationType)")
            XCTAssertEqual(dose.automatic, activationType.isAutomatic, "\(activationType)")
        }
    }

    func testFinalizedBolusIsNeverManuallyEntered() {
        for activationType in Self.activationTypes {
            let dose = DoseEntry.bolus(
                units: 2,
                deliveredUnits: 2,
                duration: 0,
                activationType: activationType,
                insulinType: .novolog,
                startDate: Self.startDate,
                endDate: Self.startDate.addingTimeInterval(.minutes(1))
            )

            XCTAssertFalse(dose.isMutable)
            XCTAssertFalse(dose.manuallyEntered, "\(activationType)")
            XCTAssertEqual(dose.automatic, activationType.isAutomatic, "\(activationType)")
        }
    }

    func testCompletedBolusReportMatchesTheInProgressOneForEveryActivationType() throws {
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth())

        for activationType in Self.activationTypes {
            let inProgress = UnfinalizedDose(
                units: 2,
                duration: .minutes(1),
                activationType: activationType,
                insulinType: .novolog,
                bolusId: 1,
                now: Self.startDate
            ).toDoseEntry(isMutable: true)
            let reporter = TandemDoseProgressReporter(pumpManager: manager, dose: inProgress, activationType: activationType)

            let finalized = try XCTUnwrap(reporter.getPumpEvent(actualDeliveredUnits: 2).dose)

            XCTAssertFalse(finalized.isMutable)
            XCTAssertFalse(finalized.manuallyEntered, "\(activationType)")
            XCTAssertEqual(finalized.manuallyEntered, inProgress.manuallyEntered, "\(activationType)")
            XCTAssertEqual(finalized.automatic, inProgress.automatic, "\(activationType)")
        }
    }
}
