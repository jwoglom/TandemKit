import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class TempBasalOriginTests: XCTestCase {
    private static let pumpSerial: UInt32 = 246_802
    private static let referenceDay = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 700_000_000))
    private let serial = HistoryLogSyncIdentifier.PumpSerial(TempBasalOriginTests.pumpSerial)!

    private var bluetooth: StubPumpBluetooth!
    private var clock: ManualClock!
    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    /// What the stub pump runs; nil for its profile.
    private var runningPercent: Int?
    private var nextTempRateId = 41
    /// Status codes for the next `SetTempRate`s, in order; 0 once they run out.
    private var setTempRateStatuses: [Int] = []

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
    private func startManager() {
        let schedule = BasalRateSchedule(dailyItems: [
            RepeatingScheduleValue(startTime: 0, value: 1.0),
            RepeatingScheduleValue(startTime: .hours(14), value: 2.0)
        ])!
        var state = TandemPumpManagerState(basalRateSchedule: schedule)
        state.hasSyncedBasalRateSchedule = true
        state.insulinType = .novolog
        state.pumpState.pumpSerial = Self.pumpSerial
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
            let status = self.setTempRateStatuses.isEmpty ? 0 : self.setTempRateStatuses.removeFirst()
            guard status == 0 else { return SetTempRateResponse(status: status, tempRateId: 0) }
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

    private func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval = .minutes(30)) -> PumpManagerError? {
        let done = expectation(description: "temp basal completion")
        var error: PumpManagerError?
        manager.enactTempBasal(decisionId: nil, unitsPerHour: unitsPerHour, for: duration) {
            error = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return error
    }

    private func temp(automatic: Bool, setByHost: Bool) -> UnfinalizedDose {
        UnfinalizedDose(
            tempRate: 1.5,
            duration: .minutes(30),
            automatic: automatic,
            setByHost: setByHost,
            insulinType: .novolog,
            startDate: at(.hours(10)),
            tempRateId: 41,
            tempPercent: 150,
            eventRaw: HistoryLogSyncIdentifier.tempRate(pumpSerial: serial, tempRateId: 41)
        )
    }

    // MARK: - The held temp

    func testATempTheHostSetIsHeldAsTheHostsAndReportedAutomatic() {
        startManager()

        XCTAssertNil(enactTempBasal(unitsPerHour: 1.5))

        XCTAssertTrue(manager.state.basalDose.setByHost)
        XCTAssertTrue(manager.state.basalDose.automatic)
        manager.waitForDelegateCalls()
        let reported = delegate.pumpEventBatches.flatMap(\.events).compactMap(\.dose).filter { $0.type == .tempBasal }
        XCTAssertEqual(reported.map(\.automatic), [true])
    }

    func testThePartAfterASegmentChangeIsStillTheHosts() {
        clock.set(at(.hours(14) - .minutes(20)))
        startManager()
        XCTAssertNil(enactTempBasal(unitsPerHour: 1.5))
        clock.set(at(.hours(14) + .minutes(3)))

        manager.fetchBasalStatus()

        XCTAssertEqual(manager.state.basalDose.startDate, at(.hours(14)))
        XCTAssertTrue(manager.state.basalDose.setByHost)
        XCTAssertTrue(manager.state.basalDose.automatic)
    }

    func testATempRestoredAfterARefusedReplacementKeepsItsOrigin() {
        startManager()
        // Not the host's: a refused replacement must not hand it to the host.
        let held = temp(automatic: false, setByHost: false)
        manager.state.basalDose = held
        runningPercent = 150
        clock.advance(by: .minutes(5))
        // The replacement is refused, the restore is not.
        setTempRateStatuses = [1, 0]

        XCTAssertNotNil(enactTempBasal(unitsPerHour: 1.2))

        XCTAssertEqual(manager.state.basalDose.tempPercent, 150)
        XCTAssertFalse(manager.state.basalDose.setByHost)
        XCTAssertFalse(manager.state.basalDose.automatic)
    }

    // MARK: - Re-statements

    func testEveryPartOfATempKeepsItsFlagsAndIdentity() {
        let source = temp(automatic: false, setByHost: true)
        let raw = Data([1, 2, 3])

        let part = source.tempBasalPart(rate: 3.0, from: at(.hours(10) + .minutes(10)), until: at(.hours(10) + .minutes(30)), eventRaw: raw)

        XCTAssertEqual(part.type, .tempBasal)
        XCTAssertEqual(part.value, 3.0)
        XCTAssertEqual(part.startDate, at(.hours(10) + .minutes(10)))
        XCTAssertEqual(part.estimatedEndDate, at(.hours(10) + .minutes(30)))
        XCTAssertEqual(part.eventRaw, raw)
        XCTAssertFalse(part.automatic)
        XCTAssertTrue(part.setByHost)
        XCTAssertEqual(part.tempRateId, 41)
        XCTAssertEqual(part.tempPercent, 150)
        XCTAssertEqual(part.insulinType, .novolog)
    }

    func testTheHostsTempSurvivesARelaunch() throws {
        let saved = temp(automatic: true, setByHost: true)

        let restored = try XCTUnwrap(UnfinalizedDose(rawValue: saved.rawValue))

        XCTAssertEqual(restored, saved)
        XCTAssertTrue(restored.setByHost)
    }

    func testATempSavedBeforeTheFlagExistedIsNotTakenForTheHosts() throws {
        var raw = temp(automatic: true, setByHost: true).rawValue
        raw["setByHost"] = nil

        let restored = try XCTUnwrap(UnfinalizedDose(rawValue: raw))

        XCTAssertFalse(restored.setByHost)
        XCTAssertTrue(restored.automatic)
    }

    // MARK: - Temps set from settings

    func testATempSetFromSettingsIsKnownByItsIdOnThisPumpOnly() {
        startManager()

        manager.rememberManualTempRate(tempRateId: 42)

        XCTAssertTrue(manager.isManualTempRate(42))
        XCTAssertFalse(manager.isManualTempRate(43))
        manager.state.pumpState.pumpSerial = Self.pumpSerial + 1
        XCTAssertFalse(manager.isManualTempRate(42), "another pump's temp with the same id")
    }

    func testATempSetFromSettingsIsForgottenOnceNoReportCanReachIt() {
        startManager()
        manager.rememberManualTempRate(tempRateId: 42)

        clock.advance(by: TandemPumpManager.manualTempRateMemory)
        XCTAssertFalse(manager.isManualTempRate(42))

        manager.rememberManualTempRate(tempRateId: 43)
        XCTAssertEqual(manager.state.manualTempRates.keys.map { HistoryLogSyncIdentifier.decode($0)?.identifier }, [43])
    }

    func testTempsSetFromSettingsSurviveARelaunch() throws {
        startManager()
        manager.rememberManualTempRate(tempRateId: 42)

        let restored = try XCTUnwrap(TandemPumpManagerState(rawValue: manager.state.rawValue))

        XCTAssertEqual(restored.manualTempRates, manager.state.manualTempRates)
        XCTAssertEqual(restored.manualTempRates.count, 1)
    }

    func testWithoutTheSerialNothingIsRemembered() {
        startManager()
        manager.state.pumpState.pumpSerial = nil

        manager.rememberManualTempRate(tempRateId: 42)

        XCTAssertTrue(manager.state.manualTempRates.isEmpty)
    }
}
