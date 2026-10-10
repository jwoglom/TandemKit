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

    /// Enacts a bolus the pump then holds mid-delivery, observes it through
    /// `createBolusProgressReporter(reportingOn: queue)`, and steps the driver's clock until the
    /// estimate reaches the programmed amount.
    private func observeBolusUntilTheEstimateIsComplete(
        _ driver: FaketandemHarness.Driver,
        clock: ManualClock,
        reportingOn queue: DispatchQueue
    ) throws -> (reporter: DoseProgressReporter, recorder: ProgressRecorder) {
        XCTAssertNil(try enactBolus(driver))
        // Held, so progress is read while the pump still delivers however slow the build.
        try harness.client.stallBolus()

        let recorder = ProgressRecorder(reportingQueue: queue)
        let reporter = try XCTUnwrap(driver.manager.createBolusProgressReporter(reportingOn: queue))
        reporter.addObserver(recorder)

        // The estimate counts from the first delivering status; stepping the clock before it is taken
        // would start the count after the step.
        try IntegrationWait.until("the driver to see the bolus delivering", timeout: 30) {
            driver.manager.bolusProgressReport?.bolusStatedOn != nil
        }
        clock.advance(by: driver.manager.estimatedDuration(toBolus: Self.units))
        try IntegrationWait.until("the host to be told the programmed amount went in", timeout: 15) {
            recorder.updates.last?.progress.deliveredUnits == Self.units
        }
        return (reporter, recorder)
    }

    private func finishHeldBolus(_ driver: FaketandemHarness.Driver) throws {
        try harness.client.completeBolus()
        try IntegrationWait.until("the driver to see the bolus finish", timeout: 30) {
            driver.manager.bolusProgressReport == nil
        }
    }

    func testBolusProgressReachesTheHostUntilThePumpFinishesTheBolus() throws {
        let clock = ManualClock(Date())
        let driver = makeDriver(clock: clock)
        try harness.pair(driver)
        _ = try harness.sync(driver)
        let eventsBefore = driver.bolusEvents.count
        let hostQueue = DispatchQueue(label: "bolus-progress-host-queue")

        let (reporter, recorder) = try observeBolusUntilTheEstimateIsComplete(driver, clock: clock, reportingOn: hostQueue)

        XCTAssertTrue(try harness.client.snapshot().bolus.active, "progress was reported while the pump delivered")
        XCTAssertEqual(recorder.updates.last?.progress.percentComplete, 1)
        XCTAssertEqual(reporter.progress.deliveredUnits, Self.units)

        reporter.removeObserver(recorder)
        try finishHeldBolus(driver)
        XCTAssertNil(driver.manager.createBolusProgressReporter(reportingOn: hostQueue), "no reporter once the bolus is over")
        let finalized = try IntegrationWait.value("finalized bolus event", timeout: 30) {
            driver.bolusEvents.dropFirst(eventsBefore).first { $0.dose?.isMutable == false }
        }
        XCTAssertEqual(finalized.dose?.programmedUnits, Self.units)
        XCTAssertEqual(finalized.dose?.deliveredUnits, Self.units)
    }

    func testBolusProgressIsReportedOnTheQueueTheHostPassed() throws {
        let clock = ManualClock(Date())
        let driver = makeDriver(clock: clock)
        try harness.pair(driver)
        _ = try harness.sync(driver)
        let hostQueue = DispatchQueue(label: "bolus-progress-host-queue")

        let (reporter, recorder) = try observeBolusUntilTheEstimateIsComplete(driver, clock: clock, reportingOn: hostQueue)

        XCTAssertTrue(recorder.updates.allSatisfy(\.onReportingQueue), "every progress callback runs on the queue the host passed")

        reporter.removeObserver(recorder)
        try finishHeldBolus(driver)
    }
}

/// Reads progress inside the callback, as Trio's `doseProgressReporterDidUpdate` does.
private final class ProgressRecorder: DoseProgressObserver {
    private let reportingQueueKey = DispatchSpecificKey<Void>()
    private let lock = NSLock()
    private var recorded: [(onReportingQueue: Bool, progress: DoseProgress)] = []

    init(reportingQueue: DispatchQueue) {
        reportingQueue.setSpecific(key: reportingQueueKey, value: ())
    }

    var updates: [(onReportingQueue: Bool, progress: DoseProgress)] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func doseProgressReporterDidUpdate(_ doseProgressReporter: DoseProgressReporter) {
        let update = (onReportingQueue: DispatchQueue.getSpecific(key: reportingQueueKey) != nil, progress: doseProgressReporter.progress)
        lock.lock()
        recorded.append(update)
        lock.unlock()
    }
}
