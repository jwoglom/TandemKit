import LoopKit
@testable import TandemKit
import XCTest

/// Basal markers, suspends and resumes are keyed on their type and date, and both hosts keep one
/// row per key: of two in one key, the second is lost (#352).
@available(macOS 13.0, iOS 14.0, *) final class DeliveryChangeEventIdentityTests: XCTestCase {
    private static let referenceDay = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 700_000_000))
    private static let tempDuration: TimeInterval = .minutes(30)

    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private var delegateQueue: DispatchQueue!
    /// What the stub pump runs; nil for its profile. It never ends a temp on its own.
    private var runningPercent: Int?
    private var isSuspended = false

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(at(.hours(10)))
        var state = TandemPumpManagerState(basalRateSchedule: BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!)
        state.hasSyncedBasalRateSchedule = true
        state.insulinType = .novolog
        manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        delegate.journalClock = clock
        delegateQueue = DispatchQueue(label: "delivery-change-identity-test")
        manager.pumpManagerDelegate = delegate
        manager.delegateQueue = delegateQueue
        delegateQueue.sync {}

        bluetooth.stub(CurrentBasalStatusRequest.self) { [unowned self] _ in
            if self.isSuspended {
                return CurrentBasalStatusResponse(profileBasalRate: 1000, currentBasalRate: 0, basalModifiedBitmask: 0x01)
            }
            return CurrentBasalStatusResponse(
                profileBasalRate: 1000,
                currentBasalRate: UInt32(10 * (self.runningPercent ?? 100)),
                basalModifiedBitmask: self.runningPercent == nil ? 0 : 0x02
            )
        }
        bluetooth.stub(SetTempRateRequest.self) { [unowned self] request in
            self.runningPercent = (request as? SetTempRateRequest)?.percent
            return SetTempRateResponse(status: 0, tempRateId: 8)
        }
        bluetooth.stub(StopTempRateRequest.self) { [unowned self] _ in
            self.runningPercent = nil
            return StopTempRateResponse(status: 0, tempRateId: 8)
        }
        bluetooth.stub(TempRateRequest.self) { [unowned self] _ in
            TempRateResponse(active: self.runningPercent != nil, percentage: self.runningPercent ?? 0, startTimeRaw: 0, duration: 0)
        }
        bluetooth.stub(SuspendPumpingRequest.self) { [unowned self] _ in
            self.runningPercent = nil
            self.isSuspended = true
            return SuspendPumpingResponse(status: 0)
        }
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        delegateQueue = nil
        clock = nil
        bluetooth = nil
        super.tearDown()
    }

    private func at(_ time: TimeInterval) -> Date {
        Self.referenceDay.addingTimeInterval(time)
    }

    private var tempBasalEnd: Date {
        at(.hours(10)).addingTimeInterval(Self.tempDuration)
    }

    private func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval = DeliveryChangeEventIdentityTests.tempDuration) {
        let done = expectation(description: "temp basal completion")
        var error: PumpManagerError?
        manager.enactTempBasal(unitsPerHour: unitsPerHour, for: duration) {
            error = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertNil(error)
    }

    private func suspend() {
        let done = expectation(description: "suspend completion")
        var error: Error?
        manager.suspendDelivery {
            error = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertNil(error)
    }

    private var batches: [MockPumpManagerDelegate.PumpEventBatch] {
        delegateQueue.sync {}
        return delegate.pumpEventBatches
    }

    /// The events of the one batch sent since `count` batches.
    private func batch(after count: Int, file: StaticString = #filePath, line: UInt = #line) -> [NewPumpEvent] {
        let sent = batches.dropFirst(count)
        XCTAssertEqual(sent.count, 1, "one batch", file: file, line: line)
        return sent.first?.events ?? []
    }

    private func assertOneRawPerEvent(_ events: [NewPumpEvent], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(events.map(\.raw)).count, events.count, "\(events.map { String(decoding: $0.raw, as: UTF8.self) })", file: file, line: line)
    }

    private static func marker(at date: Date) -> NewPumpEvent {
        NewPumpEvent.basal(dose: DoseEntry(type: .basal, startDate: date, endDate: date, value: 1, unit: .unitsPerHour, insulinType: .novolog), date: date)
    }

    private static func suspend(at date: Date) -> NewPumpEvent {
        NewPumpEvent.suspend(dose: DoseEntry(suspendDate: date), date: date)
    }

    private static func resume(at date: Date) -> NewPumpEvent {
        NewPumpEvent.resume(dose: DoseEntry(resumeDate: date, insulinType: .novolog), date: date)
    }

    // MARK: - The raw

    func testTheRawIsTheTypeAndTheDateToTheMillisecond() {
        let date = Date(timeIntervalSince1970: 1_700_000_000.25)

        XCTAssertEqual(String(decoding: Self.marker(at: date).raw, as: UTF8.self), "basal 2023-11-14T22:13:20.250Z")
        XCTAssertEqual(String(decoding: Self.suspend(at: date).raw, as: UTF8.self), "suspend 2023-11-14T22:13:20.250Z")
        XCTAssertEqual(String(decoding: Self.resume(at: date).raw, as: UTF8.self), "resume 2023-11-14T22:13:20.250Z")
    }

    func testTwoChangesOfOneTypeInOneSecondHaveTheirOwnRaws() {
        let first = at(.hours(10))
        let second = first.addingTimeInterval(0.5)

        for event in [Self.marker(at:), Self.suspend(at:), Self.resume(at:)] {
            XCTAssertNotEqual(event(first).raw, event(second).raw)
            XCTAssertEqual(event(first).raw, event(first).raw)
        }
    }

    // MARK: - The marker after a temp basal that ran out

    func testANeutralTempInTheSecondATempBasalRanOutReportsOneMarker() {
        enactTempBasal(unitsPerHour: 2)
        clock.set(tempBasalEnd.addingTimeInterval(0.5))
        let before = batches.count

        enactTempBasal(unitsPerHour: 1)

        let events = batch(after: before)
        XCTAssertEqual(events.map(\.dose?.type), [.tempBasal, .basal])
        XCTAssertEqual(events.first?.dose?.endDate, tempBasalEnd)
        XCTAssertEqual(events.last?.date, clock.now)
        assertOneRawPerEvent(events)
    }

    func testANeutralTempASecondAfterATempBasalRanOutAlsoReportsTheMarkerAtItsEnd() {
        enactTempBasal(unitsPerHour: 2)
        clock.set(tempBasalEnd.addingTimeInterval(1))
        let before = batches.count

        enactTempBasal(unitsPerHour: 1)

        let events = batch(after: before)
        XCTAssertEqual(events.map(\.dose?.type), [.tempBasal, .basal, .basal])
        XCTAssertEqual(events.dropFirst().map(\.date), [tempBasalEnd, clock.now])
        assertOneRawPerEvent(events)
    }

    func testASuspendInTheSecondATempBasalRanOutReportsNoMarker() {
        enactTempBasal(unitsPerHour: 2)
        clock.set(tempBasalEnd.addingTimeInterval(0.5))
        let before = batches.count

        suspend()

        let events = batch(after: before)
        XCTAssertEqual(events.map(\.dose?.type), [.tempBasal, .suspend])
        XCTAssertEqual(events.first?.dose?.endDate, tempBasalEnd)
    }

    func testATempBasalSetInTheSecondTheLastOneRanOutReportsNoMarker() {
        enactTempBasal(unitsPerHour: 2)
        clock.set(tempBasalEnd.addingTimeInterval(0.5))
        let before = batches.count

        enactTempBasal(unitsPerHour: 1.5)

        let events = batch(after: before)
        XCTAssertEqual(events.map(\.dose?.type), [.tempBasal, .tempBasal])
        XCTAssertEqual(events.map(\.dose?.isMutable), [false, true])
        XCTAssertEqual(events.first?.dose?.endDate, tempBasalEnd)
        XCTAssertEqual(events.last?.date, clock.now)
    }

    // MARK: - Across batches

    func testBothHostsKeepTwoMarkersReportedInOneSecond() {
        enactTempBasal(unitsPerHour: 1)
        clock.advance(by: 0.2)
        enactTempBasal(unitsPerHour: 2)
        clock.advance(by: 0.3)

        enactTempBasal(unitsPerHour: 0, for: 0)

        let markers = batches.flatMap(\.events).filter { $0.dose?.type == .basal }
        XCTAssertEqual(markers.map(\.date), [at(.hours(10)), at(.hours(10) + 0.5)])
        assertOneRawPerEvent(markers)
        let loop = LoopDoseStoreOracle()
        let trio = TrioDoseStoreOracle()
        delegate.feed(loop)
        delegate.feed(trio)
        XCTAssertEqual(loop.pumpEvents.filter { $0.dose?.type == .basal }.map(\.date), [at(.hours(10)), at(.hours(10) + 0.5)])
        XCTAssertEqual(trio.scheduledBasals.map(\.timestamp), [at(.hours(10)), at(.hours(10) + 0.5)])
        XCTAssertEqual(trio.skipped.map(\.reason), [])
    }
}
