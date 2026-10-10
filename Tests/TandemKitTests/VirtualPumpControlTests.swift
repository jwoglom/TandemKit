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
