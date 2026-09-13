import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Records the `PumpManagerDelegate` traffic the driver produces so tests can assert on what Loop
/// would have been told. Every callback is recorded under `lock`, because the driver fires them
/// from its own queues.
final class MockPumpManagerDelegate: PumpManagerDelegate {
    struct StatusUpdate {
        let newStatus: PumpManagerStatus
        let oldStatus: PumpManagerStatus
    }

    struct ReservoirReading {
        let units: Double
        let date: Date
    }

    /// One `hasNewPumpEvents` call, recorded whole: the boundary and the replace flag matter as
    /// much as the events.
    struct PumpEventBatch {
        let events: [NewPumpEvent]
        let lastReconciliation: Date?
        let replacePendingEvents: Bool
    }

    private let lock = NSLock()

    private var _statusUpdates: [StatusUpdate] = []
    private var _pumpEvents: [NewPumpEvent] = []
    private var _pumpEventBatches: [PumpEventBatch] = []
    private var _reservoirReadings: [ReservoirReading] = []
    private var _errors: [PumpManagerError] = []
    private var _didUpdateStateCount = 0
    private var _issuedAlerts: [Alert] = []

    private func synchronized<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var statusUpdates: [StatusUpdate] { synchronized { _statusUpdates } }
    var pumpEvents: [NewPumpEvent] { synchronized { _pumpEvents } }
    var pumpEventBatches: [PumpEventBatch] { synchronized { _pumpEventBatches } }
    var reservoirReadings: [ReservoirReading] { synchronized { _reservoirReadings } }
    var errors: [PumpManagerError] { synchronized { _errors } }
    var didUpdateStateCount: Int { synchronized { _didUpdateStateCount } }
    var issuedAlerts: [Alert] { synchronized { _issuedAlerts } }

    /// Fulfilled on every `pumpManagerDidUpdateState`, when set.
    var didUpdateStateExpectation: XCTestExpectation?
    /// Fulfilled on every `hasNewPumpEvents`, when set.
    var didReceivePumpEventsExpectation: XCTestExpectation?
    /// Fulfilled on every `didReadReservoirValue`, when set.
    var didReadReservoirExpectation: XCTestExpectation?

    var detectedSystemTimeOffset: TimeInterval = 0
    var automaticDosingEnabled: Bool = false

    /// Returned from `startDateToFilterNewPumpEvents(for:)`. Settable so a test can model a host
    /// app whose boundary marches forward as events are reported — Trio returns
    /// `lastEventDate - 15min`, which lands within minutes of now once this driver has reported
    /// anything.
    private var _startDateToFilterNewPumpEvents: Date = .distantPast
    var startDateToFilterNewPumpEvents: Date {
        get { synchronized { _startDateToFilterNewPumpEvents } }
        set { synchronized { _startDateToFilterNewPumpEvents = newValue } }
    }

    // MARK: - DeviceManagerDelegate

    func deviceManager(
        _: DeviceManager,
        logEventForDeviceIdentifier _: String?,
        type _: DeviceLogEntryType,
        message _: String,
        completion: ((Error?) -> Void)?
    ) {
        completion?(nil)
    }

    // MARK: - AlertIssuer

    func issueAlert(_ alert: Alert) {
        synchronized { _issuedAlerts.append(alert) }
    }

    func retractAlert(identifier _: Alert.Identifier) {}

    // MARK: - PersistedAlertStore

    func doesIssuedAlertExist(identifier _: Alert.Identifier, completion: @escaping (Swift.Result<Bool, Error>) -> Void) {
        completion(.success(false))
    }

    func lookupAllUnretracted(
        managerIdentifier _: String,
        completion: @escaping (Swift.Result<[PersistedAlert], Error>) -> Void
    ) {
        completion(.success([]))
    }

    func lookupAllUnacknowledgedUnretracted(
        managerIdentifier _: String,
        completion: @escaping (Swift.Result<[PersistedAlert], Error>) -> Void
    ) {
        completion(.success([]))
    }

    func recordRetractedAlert(_: Alert, at _: Date) {}

    // MARK: - PumpManagerStatusObserver

    func pumpManager(_: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        synchronized { _statusUpdates.append(StatusUpdate(newStatus: status, oldStatus: oldStatus)) }
    }

    // MARK: - PumpManagerDelegate

    func pumpManagerBLEHeartbeatDidFire(_: PumpManager) {}

    func pumpManagerMustProvideBLEHeartbeat(_: PumpManager) -> Bool { false }

    func pumpManagerWillDeactivate(_: PumpManager) {}

    func pumpManagerPumpWasReplaced(_: PumpManager) {}

    func pumpManager(_: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents _: Bool) {}

    func pumpManager(_: PumpManager, didError error: PumpManagerError) {
        synchronized { _errors.append(error) }
    }

    func pumpManager(
        _: PumpManager,
        hasNewPumpEvents events: [NewPumpEvent],
        lastReconciliation: Date?,
        replacePendingEvents: Bool,
        completion: @escaping (Error?) -> Void
    ) {
        synchronized {
            _pumpEvents += events
            _pumpEventBatches.append(PumpEventBatch(
                events: events,
                lastReconciliation: lastReconciliation,
                replacePendingEvents: replacePendingEvents
            ))
        }
        didReceivePumpEventsExpectation?.fulfill()
        completion(nil)
    }

    func pumpManager(
        _: PumpManager,
        didReadReservoirValue units: Double,
        at date: Date,
        completion: @escaping (Swift.Result<
            (newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool),
            Error
        >) -> Void
    ) {
        synchronized { _reservoirReadings.append(ReservoirReading(units: units, date: date)) }
        didReadReservoirExpectation?.fulfill()
        completion(.success((SimpleReservoirValue(startDate: date, unitVolume: units), nil, true)))
    }

    func pumpManager(_: PumpManager, didAdjustPumpClockBy _: TimeInterval) {}

    func pumpManagerDidUpdateState(_: PumpManager) {
        synchronized { _didUpdateStateCount += 1 }
        didUpdateStateExpectation?.fulfill()
    }

    func pumpManager(
        _: PumpManager,
        didRequestBasalRateScheduleChange _: BasalRateSchedule,
        completion: @escaping (Error?) -> Void
    ) {
        completion(nil)
    }

    func startDateToFilterNewPumpEvents(for _: PumpManager) -> Date {
        startDateToFilterNewPumpEvents
    }
}
