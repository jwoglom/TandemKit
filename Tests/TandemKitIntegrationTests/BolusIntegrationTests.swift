import LoopKit
@testable import TandemKit
import XCTest

final class BolusIntegrationTests: FaketandemIntegrationTestCase {
    private static let units = 1.0

    /// The emulator's default is 0.05 U/s (a 20 s bolus); this keeps the test short while the
    /// driver still sees the bolus in progress.
    private static let deliveryRate = 0.25

    private func enactBolus(_ driver: FaketandemHarness.Driver) throws -> PumpManagerError? {
        let box = ResultBox<PumpManagerError?>()
        driver.manager.enactBolus(units: Self.units, activationType: .manualNoRecommendation) { box.set($0) }
        return try box.wait("enactBolus completion", timeout: 60)
    }

    func testEnactBolusRunsEndToEndAndIsFinalizedFromThePumpsRecord() throws {
        let clock = ManualClock(Date())
        let driver = makeDriver(clock: clock)
        try harness.pair(driver)
        _ = try harness.sync(driver)
        try harness.client.setState(["bolus_rate_units_per_second": Self.deliveryRate])
        let logStart = try harness.client.snapshot().requestLog.lastSeq
        let eventsBefore = driver.bolusEvents.count

        let error = try enactBolus(driver)

        XCTAssertNil(error, "enactBolus failed: \(String(describing: error))")
        let bolusId = try XCTUnwrap(driver.manager.state.bolusDose?.bolusId)
        switch driver.manager.state.bolusState {
        // The activation's qualifying event can poll CurrentBolusStatus before this line runs.
        case .initiating, .inProgress: break
        default: return XCTFail("bolus state after enact: \(driver.manager.state.bolusState)")
        }

        let started = try XCTUnwrap(Array(driver.bolusEvents.dropFirst(eventsBefore)).first, "the enact must be reported")
        XCTAssertEqual(started.type, .bolus)
        XCTAssertEqual(started.dose?.programmedUnits, Self.units)
        XCTAssertEqual(started.dose?.isMutable, true, "a running bolus is reported mutable")
        XCTAssertEqual(started.dose?.manuallyEntered, false)
        XCTAssertNotNil(started.dose?.syncIdentifier)
        XCTAssertTrue(
            String(decoding: started.raw, as: UTF8.self).hasPrefix("bolus \(Self.units) "),
            "raw must be keyed on the programmed amount: \(String(decoding: started.raw, as: UTF8.self))"
        )

        let control = try harness.requestsSeen(since: logStart).filter { $0.characteristic == "Control" }
        XCTAssertEqual(
            control.prefix(2).map(\.opcode),
            [Int(BolusPermissionRequest.props.opCode), Int(InitiateBolusRequest.props.opCode)],
            "BolusPermission then InitiateBolus: \(control)"
        )

        let emulatorBolus = try harness.client.snapshot().bolus
        XCTAssertEqual(emulatorBolus.bolusId, bolusId)
        XCTAssertEqual(emulatorBolus.unitsTotal, Self.units)
        XCTAssertEqual(emulatorBolus.sourceId, 8, "an app-commanded bolus is BLUETOOTH_REMOTE_BOLUS")

        // Real time: the pump delivers, then records the finished bolus.
        let lastBolus = try IntegrationWait.value("emulator to finish the bolus", timeout: 30) {
            let snapshot = try harness.client.snapshot()
            return snapshot.lastBolus?.bolusId == bolusId ? snapshot.lastBolus : nil
        }
        XCTAssertEqual(lastBolus.deliveredUnits, Self.units)
        XCTAssertEqual(lastBolus.requestedUnits, Self.units)
        XCTAssertEqual(lastBolus.endReasonId, 3, "completed, not stopped")

        // Driver time: past the estimated end and the reconcile grace, so the next sync polls the
        // bolus instead of deferring to a delivery it believes is still running.
        clock.advance(by: driver.manager.estimatedDuration(toBolus: Self.units) + .minutes(2))
        _ = try harness.sync(driver)

        let finalized = try IntegrationWait.value("finalized bolus event", timeout: 30) {
            driver.bolusEvents.dropFirst(eventsBefore).first { $0.dose?.isMutable == false }
        }
        XCTAssertEqual(finalized.dose?.programmedUnits, Self.units)
        XCTAssertEqual(finalized.dose?.deliveredUnits, Self.units, "delivered volume comes from LastBolusStatus")
        XCTAssertEqual(finalized.raw, started.raw, "every report of one bolus must share a raw")
        XCTAssertEqual(finalized.dose?.syncIdentifier, started.dose?.syncIdentifier)
        XCTAssertNil(driver.manager.state.bolusDose)
        guard case .noBolus = driver.manager.state.bolusState else {
            return XCTFail("bolus state after finalization: \(driver.manager.state.bolusState)")
        }

        let messages = try harness.requestsSeen(since: logStart).map(\.message)
        XCTAssertTrue(
            messages.contains { $0.hasPrefix("LastBolusStatus") },
            "finalization must read the pump's last-bolus record; pump saw \(messages)"
        )
    }
}
