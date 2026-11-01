#if TANDEMKIT_VIRTUAL_PUMP
import Foundation
import LoopKit
@testable import TandemKit
import XCTest

final class VirtualPumpControlTests: XCTestCase {
    private var bluetooth: StubPumpBluetooth!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!
    private var server: VirtualPumpControl.Server!
    private var client: VirtualPumpControl.Client!

    override func setUpWithError() throws {
        try super.setUpWithError()
        bluetooth = StubPumpBluetooth()
        manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
        delegate = MockPumpManagerDelegate()
        delegateQueue = DispatchQueue(label: "virtual-pump-control-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
        let manager = manager
        server = try VirtualPumpControl.Server { manager }
        client = try VirtualPumpControl.Client(port: server.port)
    }

    override func tearDown() {
        client.close()
        server.stop()
        client = nil
        server = nil
        manager = nil
        delegate = nil
        delegateQueue = nil
        bluetooth = nil
        super.tearDown()
    }

    func testStatusReportsAnUnpairedManagerWithItsDelegate() throws {
        let status = try client.send(.init(command: .status)).status

        XCTAssertEqual(status, VirtualPumpControl.Status(onboarded: false, connected: false, delegateAttached: true))
    }

    func testABatchSentToTheDelegateReadsBackWithItsCompletion() throws {
        manager.reportReconciliationBoundary()
        delegateQueue.sync {}

        let batches = try XCTUnwrap(client.send(.init(command: .pumpEventBatches)).batches)

        XCTAssertEqual(batches.count, delegate.pumpEventBatches.count)
        let batch = try XCTUnwrap(batches.last)
        XCTAssertTrue(batch.completed)
        XCTAssertNil(batch.delegateError)
        XCTAssertEqual(batch.pumpEvents, delegate.pumpEventBatches.last?.events)
        XCTAssertEqual(batch.replacePendingEvents, delegate.pumpEventBatches.last?.replacePendingEvents)
    }

    func testBatchesAfterAnIndexLeaveOutTheEarlierOnes() throws {
        manager.reportReconciliationBoundary()
        manager.reportReconciliationBoundary()
        delegateQueue.sync {}
        let all = try XCTUnwrap(client.send(.init(command: .pumpEventBatches)).batches)

        let later = try XCTUnwrap(client.send(.init(command: .pumpEventBatches, after: all.first?.index)).batches)

        XCTAssertEqual(later.map(\.index), Array(all.map(\.index).dropFirst()))
    }

    func testARefusedCommandThrowsItsReason() {
        XCTAssertThrowsError(try client.send(.init(command: .bolus))) { error in
            XCTAssertEqual(String(describing: error), "bolus needs units")
        }
    }

    func testCommandsMissingTheirArgumentsAreRefused() {
        XCTAssertThrowsError(try client.send(.init(command: .tempBasal, unitsPerHour: 1))) { error in
            XCTAssertEqual(String(describing: error), "tempBasal needs unitsPerHour and duration")
        }
        XCTAssertThrowsError(try client.send(.init(command: .syncBasalSchedule))) { error in
            XCTAssertEqual(String(describing: error), "syncBasalSchedule needs basalSchedule")
        }
    }

    func testATempBasalReachesTheDriverWhichRefusesADurationThePumpDoesNot() {
        XCTAssertThrowsError(try client.send(.init(command: .tempBasal, unitsPerHour: 1, duration: .minutes(5)))) { error in
            XCTAssertTrue(String(describing: error).contains("unsupportedTempBasalDuration(minutes: 5)"), "\(error)")
        }
    }

    func testAScheduleReachesTheDriverWhichRefusesOneNotStartingAtMidnight() {
        let schedule = [RepeatingScheduleValue(startTime: .hours(1), value: 0.85)]

        XCTAssertThrowsError(try client.send(.init(command: .syncBasalSchedule, basalSchedule: schedule))) { error in
            XCTAssertTrue(String(describing: error).contains("firstEntryNotAtMidnight"), "\(error)")
        }
    }

    func testSyncPumpTimeSetsThePumpsClockAsTheSettingsScreenDoes() throws {
        bluetooth.stub(ChangeTimeDateRequest.self, with: ChangeTimeDateResponse(status: 0))

        _ = try client.send(.init(command: .syncPumpTime))

        XCTAssertEqual(bluetooth.sent(ChangeTimeDateRequest.self).count, 1)
    }

    func testSyncPumpTimeAnswersWithThePumpsRefusal() {
        bluetooth.stub(ChangeTimeDateRequest.self, with: ChangeTimeDateResponse(status: 1))

        XCTAssertThrowsError(try client.send(.init(command: .syncPumpTime)))
    }

    func testAFeatureFlagIsSetAsTheFlagsScreenSetsIt() throws {
        XCTAssertTrue(manager.state.featureFlags[.historyDoseReporting])

        try client.send(.init(command: .setFeatureFlag, featureFlag: "historyDoseReporting", enabled: false))

        XCTAssertFalse(manager.state.featureFlags[.historyDoseReporting])
        XCTAssertThrowsError(try client.send(.init(command: .setFeatureFlag, featureFlag: "noSuchFlag", enabled: true))) { error in
            XCTAssertEqual(String(describing: error), "no feature flag noSuchFlag")
        }
    }

    func testCartridgeTubingAndSiteChangesReadBackAsTheMarkersTheDelegateReceived() throws {
        try client.send(.init(command: .recordCartridgeChange))
        try client.send(.init(command: .recordTubingFill))
        try client.send(.init(command: .recordSiteChange, units: 0.3))
        delegateQueue.sync {}

        let events = try XCTUnwrap(client.send(.init(command: .pumpEventBatches)).batches).flatMap(\.pumpEvents)

        XCTAssertEqual(events, delegate.pumpEventBatches.flatMap(\.events))
        XCTAssertEqual(events.map(\.type), [.rewind, .prime, .prime, .replaceComponent(componentType: .infusionSet)])
        XCTAssertEqual(manager.state.lastCannulaFillAmount, 0.3)
    }

    func testACancelWithNoBolusRunningAnswersWithTheDriversRefusal() {
        XCTAssertThrowsError(try client.send(.init(command: .cancelBolus))) { error in
            XCTAssertTrue(String(describing: error).contains("noActiveBolus"), "\(error)")
        }
    }

    func testARequestSurvivesTheWireUnchanged() throws {
        let request = VirtualPumpControl.Request(
            id: 7,
            command: .syncBasalSchedule,
            unitsPerHour: 1.5,
            duration: .minutes(30),
            basalSchedule: [RepeatingScheduleValue(startTime: 0, value: 1.0), RepeatingScheduleValue(startTime: .hours(6), value: 0.75)]
        )

        let decoded = try JSONDecoder().decode(VirtualPumpControl.Request.self, from: JSONEncoder().encode(request))

        XCTAssertEqual(decoded, request)
    }

    func testEventsSurviveTheWireUnchanged() throws {
        let start = Date(timeIntervalSinceReferenceDate: 781_234_567.125)
        let events = [
            NewPumpEvent(
                date: start,
                dose: DoseEntry(
                    type: .bolus,
                    startDate: start,
                    endDate: start.addingTimeInterval(40),
                    value: 1.25,
                    unit: .units,
                    deliveredUnits: 1.2,
                    automatic: false
                ),
                raw: Data([0x01, 0x02, 0xFE]),
                title: "Bolus"
            ),
            NewPumpEvent(
                date: start.addingTimeInterval(300),
                dose: DoseEntry(
                    type: .tempBasal,
                    startDate: start.addingTimeInterval(300),
                    endDate: start.addingTimeInterval(2100),
                    value: 0.45,
                    unit: .unitsPerHour,
                    automatic: true,
                    isMutable: true
                ),
                raw: Data([0x0A]),
                title: "Temp Basal"
            ),
            NewPumpEvent(date: start.addingTimeInterval(600), dose: DoseEntry(suspendDate: start.addingTimeInterval(600)), raw: Data([0x0B]), title: "Suspend"),
            NewPumpEvent(date: start.addingTimeInterval(900), dose: DoseEntry(resumeDate: start.addingTimeInterval(900), wasProgrammedByPumpUI: true), raw: Data([0x0C]), title: "Resume"),
            NewPumpEvent(date: start.addingTimeInterval(960), dose: nil, raw: Data([0x0D]), title: "Cartridge Change", type: .rewind),
            NewPumpEvent(date: start.addingTimeInterval(990), dose: nil, raw: Data([0x0E]), title: "Site Change", type: .replaceComponent(componentType: .infusionSet)),
            NewPumpEvent(date: start.addingTimeInterval(1020), dose: nil, raw: Data([0x0F]), title: "Occlusion", type: .alarm, alarmType: .occlusion),
        ]
        let batch = VirtualPumpControl.Batch(
            index: 3,
            hostNow: start.addingTimeInterval(901),
            lastReconciliation: start.addingTimeInterval(899),
            replacePendingEvents: true,
            events: events.map(VirtualPumpControl.Event.init),
            completed: true,
            delegateError: nil
        )

        let decoded = try JSONDecoder().decode(VirtualPumpControl.Batch.self, from: JSONEncoder().encode(batch))

        XCTAssertEqual(decoded, batch)
        XCTAssertEqual(decoded.pumpEvents, events)
    }
}
#endif
