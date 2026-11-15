import LoopKit
@testable import TandemKit
import XCTest

/// The fill wizards report a `.prime`, and a new manager's first pump, or one with another serial,
/// a `.replaceComponent(.pump)` (#349). None carries a dose or purges pending ones.
@available(macOS 13.0, iOS 14.0, *) final class PrimeAndPumpReplacementEventTests: XCTestCase {
    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let firstSerial: UInt32 = 1_111_111
    private static let secondSerial: UInt32 = 2_222_222

    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(Self.t0)
        delegateQueue = DispatchQueue(label: "prime-and-pump-replacement-test")
        manager = makeManager(state: TandemPumpManagerState(rawValue: [:]))
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        bluetooth = nil
        delegateQueue = nil
        clock = nil
        super.tearDown()
    }

    private func makeManager(state: TandemPumpManagerState) -> TandemPumpManager {
        let manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}
        return manager
    }

    private func reported(_ body: () -> Void) -> [MockPumpManagerDelegate.PumpEventBatch] {
        delegateQueue.sync {}
        let before = delegate.pumpEventBatches.count
        body()
        delegateQueue.sync {}
        return Array(delegate.pumpEventBatches.dropFirst(before))
    }

    private func sync() {
        let synced = expectation(description: "syncPumpData")
        manager.syncPumpData { _ in synced.fulfill() }
        wait(for: [synced], timeout: 5)
    }

    private func stubPump(serial: UInt32) {
        bluetooth.stub(ApiVersionRequest.self, with: ApiVersionResponse(majorVersion: 3, minorVersion: 5))
        bluetooth.stub(PumpVersionBRequest.self, with: PumpVersionBResponse(
            softwareName: "t:slim X2",
            configurationBitsA: 0,
            configurationBitsB: 0,
            serialNumber: serial,
            modelNumber: 1000,
            pumpRevision: "A",
            pcbPartNumberA: 0,
            pcbSerialNumberA: 0,
            pcbRevisionNumberA: "A"
        ))
    }

    // MARK: - Prime

    func testACannulaFillReportsItsPrimeAlongsideTheSiteChange() throws {
        let batches = reported { manager.recordSiteChange(primeAmount: 0.3) }

        let batch = try XCTUnwrap(batches.first)
        XCTAssertEqual(batches.count, 1)
        XCTAssertFalse(batch.replacePendingEvents)
        XCTAssertEqual(batch.events.map(\.type), [.prime, .replaceComponent(componentType: .infusionSet)])
        XCTAssertEqual(batch.events.map(\.date), [Self.t0, Self.t0])
        XCTAssertEqual(batch.events.first?.title, "Cannula Fill 0.3 U")
        XCTAssertTrue(batch.events.allSatisfy { $0.dose == nil })
    }

    func testASiteChangeWithNoFillAmountReportsNoPrime() {
        let events = reported { manager.recordSiteChange() }.flatMap(\.events)

        XCTAssertEqual(events.map(\.type), [.replaceComponent(componentType: .infusionSet)])
    }

    func testATubingFillReportsAPrime() throws {
        clock.advance(by: .minutes(3))

        let batches = reported { manager.recordTubingFill() }

        let prime = try XCTUnwrap(batches.first?.events.first)
        XCTAssertEqual(batches.flatMap(\.events).count, 1)
        XCTAssertEqual(batches.first?.replacePendingEvents, false)
        XCTAssertEqual(prime.type, .prime)
        XCTAssertNil(prime.dose)
        XCTAssertEqual(prime.date, Self.t0.addingTimeInterval(.minutes(3)))
    }

    func testTwoPrimesAreTwoEvents() {
        let first = reported { manager.recordTubingFill() }.flatMap(\.events)
        clock.advance(by: .minutes(2))
        let second = reported { manager.recordSiteChange(primeAmount: 0.5) }.flatMap(\.events)

        XCTAssertNotEqual(first.first?.raw, second.first?.raw)
    }

    // MARK: - Pump replacement

    func testTheFirstPumpANewManagerReadsIsReportedAddedButNotReplaced() throws {
        stubPump(serial: Self.firstSerial)

        let batches = reported { manager.fetchPumpInformation() }

        let event = try XCTUnwrap(batches.first?.events.first)
        XCTAssertEqual(batches.flatMap(\.events).count, 1)
        XCTAssertEqual(batches.first?.replacePendingEvents, false)
        XCTAssertEqual(event.type, .replaceComponent(componentType: .pump))
        XCTAssertEqual(event.title, "Pump Added")
        XCTAssertNil(event.dose)
        XCTAssertEqual(event.date, Self.t0)
        XCTAssertEqual(delegate.pumpWasReplacedCount, 0)
        XCTAssertEqual(manager.state.lastPumpSerial, Self.firstSerial)
    }

    func testAManagerThatHasReadItsPumpBeforeReportsNothingOnItsNextRead() {
        var state = TandemPumpManagerState(rawValue: [:])
        state.lastPumpSerial = Self.firstSerial
        manager = makeManager(state: state)
        stubPump(serial: Self.firstSerial)

        XCTAssertEqual(reported { manager.fetchPumpInformation() }.flatMap(\.events), [])
    }

    func testTheSamePumpReadAgainIsNotAReplacement() {
        stubPump(serial: Self.firstSerial)
        manager.fetchPumpInformation()

        XCTAssertEqual(reported { manager.fetchPumpInformation() }.flatMap(\.events), [])
    }

    func testAPumpWithAnotherSerialPairedAfterTheSavedPairingWasDeletedIsAReplacement() throws {
        stubPump(serial: Self.firstSerial)
        manager.fetchPumpInformation()
        manager.deleteSavedPumpState()
        XCTAssertNil(manager.state.pumpState.pumpSerial)
        clock.advance(by: .minutes(10))
        stubPump(serial: Self.secondSerial)

        let batches = reported { manager.fetchPumpInformation() }

        let event = try XCTUnwrap(batches.first?.events.first)
        XCTAssertEqual(batches.flatMap(\.events).count, 1)
        XCTAssertEqual(batches.first?.replacePendingEvents, false)
        XCTAssertEqual(event.type, .replaceComponent(componentType: .pump))
        XCTAssertEqual(event.title, "Pump Replaced")
        XCTAssertNil(event.dose)
        XCTAssertEqual(event.date, Self.t0.addingTimeInterval(.minutes(10)))
        XCTAssertEqual(delegate.pumpWasReplacedCount, 1)
        XCTAssertEqual(manager.state.lastPumpSerial, Self.secondSerial)
        XCTAssertEqual(manager.state.pumpState.pumpSerial, Self.secondSerial)
        XCTAssertEqual(reported { manager.fetchPumpInformation() }.flatMap(\.events), [], "reported once")
    }

    func testTheSyncAfterThePairingWasDeletedReadsTheNextPumpsSerial() throws {
        stubPump(serial: Self.firstSerial)
        sync()
        sync()
        XCTAssertEqual(bluetooth.sent(PumpVersionBRequest.self).count, 1, "the pump's identity is read with the daily settings")
        manager.deleteSavedPumpState()
        stubPump(serial: Self.secondSerial)

        let events = reported { sync() }.flatMap(\.events)

        XCTAssertEqual(manager.state.pumpState.pumpSerial, Self.secondSerial)
        XCTAssertEqual(events.filter { $0.type == .replaceComponent(componentType: .pump) }.count, 1, "\(events)")
    }

    func testStateSavedBeforeTheLastSerialWasKeptTakesItFromThePumpState() {
        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState.pumpSerial = Self.firstSerial
        var raw = state.rawValue
        raw["lastPumpSerial"] = nil

        XCTAssertEqual(TandemPumpManagerState(rawValue: raw).lastPumpSerial, Self.firstSerial)
    }

    func testAnUpgradedDriverReadingAnotherPumpReportsAReplacement() {
        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState.pumpSerial = Self.firstSerial
        var raw = state.rawValue
        raw["lastPumpSerial"] = nil
        manager = makeManager(state: TandemPumpManagerState(rawValue: raw))
        stubPump(serial: Self.secondSerial)

        let events = reported { manager.fetchPumpInformation() }.flatMap(\.events)

        XCTAssertEqual(events.map(\.type), [.replaceComponent(componentType: .pump)])
    }
}
