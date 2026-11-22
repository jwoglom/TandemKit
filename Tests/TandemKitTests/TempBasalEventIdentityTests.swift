import LoopKit
@testable import TandemKit
import XCTest

/// A temp basal keeps one `raw` from its first report to its last, however it ends (#344).
@available(macOS 13.0, iOS 14.0, *) final class TempBasalEventIdentityTests: XCTestCase {
    private static let pumpSerial: UInt32 = 123_456
    private static let referenceDay = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 700_000_000))
    private let serial = HistoryLogSyncIdentifier.PumpSerial(TempBasalEventIdentityTests.pumpSerial)!

    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    /// What the stub pump runs; nil for its profile.
    private var runningPercent: Int?
    private var nextTempRateId = 41

    override func setUp() {
        super.setUp()
        bluetooth = StubPumpBluetooth()
        clock = ManualClock(at(.hours(10)))
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        clock = nil
        bluetooth = nil
        super.tearDown()
    }

    private func at(_ time: TimeInterval) -> Date {
        Self.referenceDay.addingTimeInterval(time)
    }

    /// 1 U/hr until 14:00 and 2 U/hr after, on the host and the pump alike.
    private func startManager(pumpSerial: UInt32? = TempBasalEventIdentityTests.pumpSerial) {
        let schedule = BasalRateSchedule(dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: 1.0),
            RepeatingScheduleValue(startTime: .hours(14), value: 2.0)
        ])!
        var state = TandemPumpManagerState(basalRateSchedule: schedule)
        state.hasSyncedBasalRateSchedule = true
        state.insulinType = .novolog
        state.pumpState.pumpSerial = pumpSerial
        manager = TandemPumpManager(state: state, bluetooth: bluetooth, clock: clock)
        delegate = MockPumpManagerDelegate()
        manager.pumpManagerDelegate = delegate
        manager.waitForDelegateCalls()

        bluetooth.stub(CurrentBasalStatusRequest.self) { [unowned self] _ in
            let profile = UInt32((self.manager.getScheduledBasalRate() * 1000).rounded())
            return CurrentBasalStatusResponse(
                profileBasalRate: profile,
                currentBasalRate: profile * UInt32(self.runningPercent ?? 100) / 100,
                basalModifiedBitmask: self.runningPercent == nil ? 0 : 0x02
            )
        }
        bluetooth.stub(SetTempRateRequest.self) { [unowned self] request in
            self.runningPercent = (request as? SetTempRateRequest)?.percent
            defer { self.nextTempRateId += 1 }
            return SetTempRateResponse(status: 0, tempRateId: self.nextTempRateId)
        }
        bluetooth.stub(StopTempRateRequest.self) { [unowned self] _ in
            self.runningPercent = nil
            return StopTempRateResponse(status: 0, tempRateId: self.nextTempRateId - 1)
        }
        bluetooth.stub(TempRateRequest.self) { [unowned self] _ in
            TempRateResponse(active: self.runningPercent != nil, percentage: self.runningPercent ?? 0, startTimeRaw: 0, duration: 0)
        }
    }

    private func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval = .minutes(30), decisionId: UUID? = nil) -> PumpManagerError? {
        let done = expectation(description: "temp basal completion")
        var error: PumpManagerError?
        manager.enactTempBasal(decisionId: decisionId, unitsPerHour: unitsPerHour, for: duration) {
            error = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return error
    }

    private func cancelTempBasal() {
        XCTAssertNil(enactTempBasal(unitsPerHour: 0, for: 0))
    }

    private var tempBasalEvents: [NewPumpEvent] {
        manager.waitForDelegateCalls()
        return delegate.pumpEventBatches.flatMap(\.events).filter { $0.dose?.type == .tempBasal }
    }

    private func tempRate(_ tempRateId: Int) -> Data {
        HistoryLogSyncIdentifier.tempRate(pumpSerial: serial, tempRateId: tempRateId)
    }

    func testATempBasalCancelledEarlyIsFinalizedUnderThePumpsTempRateId() {
        startManager()
        XCTAssertNil(enactTempBasal(unitsPerHour: 1.5))
        clock.advance(by: .minutes(7))

        cancelTempBasal()

        let events = tempBasalEvents
        XCTAssertEqual(events.map(\.dose?.isMutable), [true, false])
        XCTAssertEqual(events.last?.dose?.endDate, at(.hours(10) + .minutes(7)))
        XCTAssertEqual(events.map(\.raw), [tempRate(41), tempRate(41)])
    }

    func testATempBasalReplacedEarlyKeepsItsRawAndTheReplacementHasItsOwn() {
        startManager()
        XCTAssertNil(enactTempBasal(unitsPerHour: 1.5))
        clock.advance(by: .minutes(7))

        XCTAssertNil(enactTempBasal(unitsPerHour: 1.2))

        let events = tempBasalEvents
        XCTAssertEqual(events.map(\.dose?.isMutable), [true, false, true])
        XCTAssertEqual(events.map(\.raw), [tempRate(41), tempRate(41), tempRate(42)])
    }

    func testATempBasalAndItsReplacementEachCarryTheirOwnDecision() {
        startManager()
        let first = UUID()
        let second = UUID()
        XCTAssertNil(enactTempBasal(unitsPerHour: 1.5, decisionId: first))
        clock.advance(by: .minutes(7))

        XCTAssertNil(enactTempBasal(unitsPerHour: 1.2, decisionId: second))

        XCTAssertEqual(tempBasalEvents.map(\.dose?.decisionId), [first, first, second])
    }

    func testEveryPartOfATempBasalCutAtASegmentChangeCarriesItsDecision() {
        clock.set(at(.hours(14) - .minutes(20)))
        startManager()
        let decisionId = UUID()
        XCTAssertNil(enactTempBasal(unitsPerHour: 1.5, decisionId: decisionId))
        clock.set(at(.hours(14) + .minutes(3)))
        manager.fetchBasalStatus()
        clock.set(at(.hours(14) + .minutes(6)))

        cancelTempBasal()

        XCTAssertEqual(tempBasalEvents.count, 4)
        XCTAssertEqual(Set(tempBasalEvents.map(\.dose?.decisionId)), [decisionId])
    }

    func testWithoutTheSerialATempBasalIsKeyedOnWhatWasProgrammedAndKeepsThatKey() {
        startManager(pumpSerial: nil)
        XCTAssertNil(enactTempBasal(unitsPerHour: 1.5))
        clock.advance(by: .minutes(7))

        cancelTempBasal()

        let programmed = Data("tempBasal 0.75 \(ISO8601DateFormatter().string(from: at(.hours(10))))".utf8)
        XCTAssertEqual(tempBasalEvents.map(\.raw), [programmed, programmed])
    }

    func testATempRateIdNotPastTheLastOneMintedIsNotUsedAgain() throws {
        startManager()
        XCTAssertNil(enactTempBasal(unitsPerHour: 1.5))
        clock.advance(by: .minutes(7))
        // The pump's counter restarted.
        nextTempRateId = 3

        XCTAssertNil(enactTempBasal(unitsPerHour: 1.2))
        clock.advance(by: .minutes(7))
        cancelTempBasal()

        let replacement = tempBasalEvents.suffix(2).map(\.raw)
        XCTAssertNil(HistoryLogSyncIdentifier.decode(try XCTUnwrap(replacement.first)))
        XCTAssertEqual(replacement.first, replacement.last)
        XCTAssertEqual(manager.state.lastTempRateEventRaw, tempRate(41))
    }

    func testATempBasalCutAtASegmentChangeKeepsItsRawAndTheRestIsItsFirstPart() {
        clock.set(at(.hours(14) - .minutes(20)))
        startManager()
        XCTAssertNil(enactTempBasal(unitsPerHour: 1.5))
        clock.set(at(.hours(14) + .minutes(3)))
        manager.fetchBasalStatus()
        clock.set(at(.hours(14) + .minutes(6)))

        cancelTempBasal()

        let events = tempBasalEvents
        XCTAssertEqual(events.map(\.dose?.startDate), [at(.hours(14) - .minutes(20)), at(.hours(14) - .minutes(20)), at(.hours(14)), at(.hours(14))])
        XCTAssertEqual(events.map(\.dose?.isMutable), [true, false, true, false])
        XCTAssertEqual(events.prefix(2).map(\.raw), [tempRate(41), tempRate(41)])
        let firstPart = HistoryLogSyncIdentifier.tempRatePart(pumpSerial: serial, tempRateId: 41, part: 1)
        XCTAssertEqual(events.suffix(2).map(\.raw), [firstPart, firstPart])
    }

    func testATempBasalSavedWithoutAnEventRawFinishesUnderTheKeyItRanUnder() {
        let start = at(.hours(10))
        let dose = UnfinalizedDose(tempRate: 1.5, duration: .minutes(30), automatic: true, insulinType: .novolog, startDate: start)

        let finished = NewPumpEvent.tempBasal(dose: dose.toDoseEntry(isMutable: false, endDate: start.addingTimeInterval(.minutes(7))), of: dose)

        XCTAssertEqual(finished.raw, Data("tempBasal 0.75 \(ISO8601DateFormatter().string(from: start))".utf8))
    }
}
