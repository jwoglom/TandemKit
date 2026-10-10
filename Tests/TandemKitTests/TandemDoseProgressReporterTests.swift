import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TandemDoseProgressReporterTests: XCTestCase {
    private var clock: ManualClock!
    private var manager: TandemPumpManager!

    override func setUp() {
        super.setUp()
        clock = ManualClock()
        manager = TandemPumpManager(
            state: TandemPumpManagerState(rawValue: [:]),
            bluetooth: StubPumpBluetooth(),
            clock: clock
        )
    }

    override func tearDown() {
        manager = nil
        clock = nil
        super.tearDown()
    }

    private static func makeReporter(for manager: TandemPumpManager, now: Date) -> TandemDoseProgressReporter {
        TandemDoseProgressReporter(
            pumpManager: manager,
            dose: DoseEntry.bolus(
                units: 3,
                deliveredUnits: 0,
                duration: .minutes(3),
                activationType: .manualNoRecommendation,
                insulinType: .novolog,
                startDate: now,
                now: now
            ),
            activationType: .manualNoRecommendation
        )
    }

    func testObserversAreCalledOnTheQueueTheHostAskedToBeReportedOn() throws {
        manager.bolusProgressReport = Self.makeReporter(for: manager, now: clock.now)
        let hostQueue = DispatchQueue(label: "dose-progress-host-queue")
        let hostQueueKey = DispatchSpecificKey<Void>()
        hostQueue.setSpecific(key: hostQueueKey, value: ())
        let reported = expectation(description: "progress reported")
        var calledOnHostQueue: Bool?
        let observer = ProgressObserver { _ in
            calledOnHostQueue = DispatchQueue.getSpecific(key: hostQueueKey) != nil
            reported.fulfill()
        }

        let reporter = try XCTUnwrap(manager.createBolusProgressReporter(reportingOn: hostQueue))
        reporter.addObserver(observer)
        manager.bolusProgressReport?.notify()
        clock.advance(by: 30)
        manager.bolusProgressReport?.notify()

        wait(for: [reported], timeout: 5)
        XCTAssertEqual(hostQueue.sync { calledOnHostQueue }, true)
        XCTAssertEqual(
            reporter.progress.deliveredUnits,
            TandemPumpCapabilities.roundToReportingResolution(30 * TandemPumpCapabilities.bolusSpeedUnder10U),
            accuracy: 1e-9
        )
    }

    func testConcurrentNotifiesAndObserverChangesLeaveTheEstimateIntact() {
        let reporter = Self.makeReporter(for: manager, now: clock.now)
        let observers = (0 ..< 8).map { _ in ProgressObserver { _ in } }
        let hostQueue = DispatchQueue(label: "dose-progress-concurrency-host-queue")
        reporter.notify()
        clock.advance(by: 30)

        DispatchQueue.concurrentPerform(iterations: 20000) { index in
            let observer = observers[index % observers.count]
            switch index % 3 {
            case 0:
                reporter.notify()
            case 1:
                reporter.addObserver(observer, queue: hostQueue)
            default:
                reporter.removeObserver(observer)
                _ = reporter.progress
            }
        }
        hostQueue.sync {}

        XCTAssertEqual(
            reporter.progress.deliveredUnits,
            TandemPumpCapabilities.roundToReportingResolution(30 * TandemPumpCapabilities.bolusSpeedUnder10U),
            accuracy: 1e-9
        )
    }

    func testConcurrentReporterSwapsDoNotOverReleaseTheReporter() {
        let manager = manager!
        let now = clock.now

        DispatchQueue.concurrentPerform(iterations: 20000) { index in
            if index.isMultiple(of: 2) {
                manager.bolusProgressReport = Self.makeReporter(for: manager, now: now)
            } else {
                _ = manager.createBolusProgressReporter(reportingOn: .main)?.progress
            }
        }

        XCTAssertNotNil(manager.bolusProgressReport)
    }
}

private final class ProgressObserver: DoseProgressObserver {
    private let onUpdate: (DoseProgressReporter) -> Void

    init(onUpdate: @escaping (DoseProgressReporter) -> Void) {
        self.onUpdate = onUpdate
    }

    func doseProgressReporterDidUpdate(_ doseProgressReporter: DoseProgressReporter) {
        onUpdate(doseProgressReporter)
    }
}
