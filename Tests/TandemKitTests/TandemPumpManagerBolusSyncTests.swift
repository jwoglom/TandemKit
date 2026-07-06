import LoopKit
@testable import TandemCore
@testable import TandemKit
import XCTest

final class TandemPumpManagerBolusSyncTests: XCTestCase {
    private func makeManager(bolusDose: UnfinalizedDose?) -> TandemPumpManager {
        let state = TandemPumpManagerState(pumpState: nil)
        let manager = TandemPumpManager(state: state)
        manager.state.bolusDose = bolusDose
        return manager
    }

    private func makeBolusDose(estimatedEndDate: Date) -> UnfinalizedDose {
        let dose = UnfinalizedDose(
            units: 0.1,
            duration: .seconds(8),
            activationType: .automatic,
            insulinType: nil,
            bolusId: 2004
        )
        dose.estimatedEndDate = estimatedEndDate
        return dose
    }

    func testSyncNotDeferredWithoutTrackedBolus() {
        let manager = makeManager(bolusDose: nil)
        XCTAssertFalse(manager.shouldDeferBolusSync(at: Date()))
    }

    func testSyncDeferredWhileBolusStillExpectedToRun() {
        let now = Date()
        let manager = makeManager(bolusDose: makeBolusDose(estimatedEndDate: now.addingTimeInterval(10)))
        XCTAssertTrue(manager.shouldDeferBolusSync(at: now))
    }

    func testSyncDeferredWithinGraceAfterEstimatedEnd() {
        let now = Date()
        let manager = makeManager(bolusDose: makeBolusDose(estimatedEndDate: now.addingTimeInterval(-10)))
        XCTAssertTrue(manager.shouldDeferBolusSync(at: now))
    }

    /// Regression: a bolus whose completion event was lost (BLE dropped mid-bolus; the pump
    /// does not replay missed qualifying events) must not defer the sync path forever —
    /// otherwise the stale in-progress state blocks temp basals until the pump is re-paired.
    func testSyncReconcilesAfterGraceExpires() {
        let now = Date()
        let staleEnd = now.addingTimeInterval(-TandemPumpManager.bolusSyncReconcileGrace - 1)
        let manager = makeManager(bolusDose: makeBolusDose(estimatedEndDate: staleEnd))
        XCTAssertFalse(manager.shouldDeferBolusSync(at: now))
    }
}
