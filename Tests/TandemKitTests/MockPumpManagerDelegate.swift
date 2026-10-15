import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Records the `PumpManagerDelegate` traffic the driver produces so tests can assert on what Loop
/// would have been told. Every callback is recorded under `lock`, because the driver fires them
/// from its own queues.
///
/// Two views of the same traffic: the per-kind arrays (`pumpEvents`, `statusUpdates`, ...) the unit
/// tests read, and `journal`, an ordered record of every call with its position, wall time and the
/// injected clock's time, which the conformance tests replay into a `DoseOracle` with `feed(_:)`.
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

    /// One delegate call in the order it arrived.
    struct JournalEntry {
        enum Kind {
            case pumpEvents(PumpEventBatch)
            case statusUpdate(StatusUpdate)
            case didError(PumpManagerError)
            case willDeactivate
            case pumpWasReplaced
            case issueAlert(Alert)
            case retractAlert(Alert.Identifier)
            case didAdjustPumpClock(by: TimeInterval)
            case reservoirReading(ReservoirReading)
            case didUpdateState
            case didUpdatePumpRecordsBasalProfileStartEvents(Bool)
            case didRequestBasalRateScheduleChange(BasalRateSchedule)
            case bleHeartbeatDidFire
        }

        /// 0-based position in the journal.
        let index: Int
        /// `Date()` when the call was recorded.
        let wallTime: Date
        /// `journalClock.now` when the call was recorded, if a clock was injected. This is the
        /// driver's idea of "now" — the instant its doses are dated against.
        let clockTime: Date?
        let kind: Kind

        /// The time a host would have read as "now": the injected clock's, else the wall clock's.
        var hostNow: Date { clockTime ?? wallTime }

        var pumpEventBatch: PumpEventBatch? {
            if case let .pumpEvents(batch) = kind { return batch }
            return nil
        }
    }

    private let lock = NSLock()

    private var _statusUpdates: [StatusUpdate] = []
    private var _pumpEvents: [NewPumpEvent] = []
    private var _pumpEventBatches: [PumpEventBatch] = []
    private var _reservoirReadings: [ReservoirReading] = []
    private var _errors: [PumpManagerError] = []
    private var _didUpdateStateCount = 0
    private var _issuedAlerts: [Alert] = []
    private var _retractedAlerts: [Alert.Identifier] = []
    private var _willDeactivateCount = 0
    private var _pumpWasReplacedCount = 0
    private var _clockAdjustments: [TimeInterval] = []
    private var _journal: [JournalEntry] = []

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
    var retractedAlerts: [Alert.Identifier] { synchronized { _retractedAlerts } }
    var willDeactivateCount: Int { synchronized { _willDeactivateCount } }
    var pumpWasReplacedCount: Int { synchronized { _pumpWasReplacedCount } }
    var clockAdjustments: [TimeInterval] { synchronized { _clockAdjustments } }
    var journal: [JournalEntry] { synchronized { _journal } }

    /// When set, every journal entry also carries this clock's `now`. Give it the driver's clock.
    var journalClock: TandemClock? {
        get { synchronized { _journalClock } }
        set { synchronized { _journalClock = newValue } }
    }

    private var _journalClock: TandemClock?

    /// Fulfilled on every `pumpManagerDidUpdateState`, when set.
    var didUpdateStateExpectation: XCTestExpectation?
    /// Fulfilled on every `hasNewPumpEvents`, when set.
    var didReceivePumpEventsExpectation: XCTestExpectation?

    /// When set, `hasNewPumpEvents` keeps its completion for `finishHeldPumpEventBatch()`, as a host
    /// still storing the batch does.
    var holdsPumpEventCompletions: Bool {
        get { synchronized { _holdsPumpEventCompletions } }
        set { synchronized { _holdsPumpEventCompletions = newValue } }
    }

    var heldPumpEventCompletionCount: Int { synchronized { _heldPumpEventCompletions.count } }

    func finishHeldPumpEventBatch() {
        let completion = synchronized { _heldPumpEventCompletions.removeFirst() }
        completion(nil)
    }

    private var _holdsPumpEventCompletions = false
    private var _heldPumpEventCompletions: [(Error?) -> Void] = []
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

    // MARK: - Delegate queue

    private static let delegateQueueKey = DispatchSpecificKey<ObjectIdentifier>()

    /// Loop's delegate methods `dispatchPrecondition` onto its `delegateQueue`, and crashed when a
    /// backfill tick called `startDateToFilterNewPumpEvents` from the command queue.
    private func expectDelegateQueue(of manager: DeviceManager, _ method: String = #function) {
        guard let queue = (manager as? PumpManager)?.delegateQueue else { return }
        let id = ObjectIdentifier(queue)
        queue.setSpecific(key: Self.delegateQueueKey, value: id)
        guard DispatchQueue.getSpecific(key: Self.delegateQueueKey) != id else { return }
        XCTFail("\(method) was called off the pump manager's delegateQueue")
    }

    // MARK: - Journal

    /// Must be called with `lock` held.
    private func record(_ kind: JournalEntry.Kind) {
        _journal.append(JournalEntry(
            index: _journal.count,
            wallTime: Date(),
            clockTime: _journalClock?.now,
            kind: kind
        ))
    }

    /// Journal entries that are `hasNewPumpEvents` calls, in order.
    var pumpEventJournal: [JournalEntry] {
        journal.filter { $0.pumpEventBatch != nil }
    }

    /// Readings that arrived newer than the boundary the host then held. Loop's `DoseStore` counts
    /// whole-unit reservoir drops in place of pump events past its boundary while it holds one.
    var reservoirReadingsAheadOfTheBoundary: [ReservoirReading] {
        var boundary: Date?
        var ahead: [ReservoirReading] = []
        for entry in journal {
            switch entry.kind {
            case let .pumpEvents(batch):
                boundary = batch.lastReconciliation
            case let .reservoirReading(reading) where reading.date > boundary ?? .distantPast:
                ahead.append(reading)
            default:
                break
            }
        }
        return ahead
    }

    /// Replays every `hasNewPumpEvents` batch recorded so far into each oracle, in order, dating each
    /// with the driver clock's time at the call (or the wall time without a clock). Returns the
    /// number of batches fed. Pass `after` to continue from a previous feed's last journal index.
    @discardableResult
    func feed(_ oracles: DoseOracle..., after lastIndex: Int? = nil) -> Int {
        // One read of the journal, so a batch the driver sends meanwhile reaches every oracle or none.
        var fed = 0
        for entry in journal where entry.index > (lastIndex ?? -1) {
            guard let batch = entry.pumpEventBatch else { continue }
            for oracle in oracles {
                oracle.addPumpEvents(
                    batch.events,
                    lastReconciliation: batch.lastReconciliation,
                    replacePendingEvents: batch.replacePendingEvents,
                    now: entry.hostNow
                )
            }
            fed += 1
        }
        return fed
    }

    // MARK: - DeviceManagerDelegate

    func deviceManager(
        _ manager: DeviceManager,
        logEventForDeviceIdentifier _: String?,
        type _: DeviceLogEntryType,
        message _: String,
        completion: ((Error?) -> Void)?
    ) {
        expectDelegateQueue(of: manager)
        completion?(nil)
    }

    // MARK: - AlertIssuer

    func issueAlert(_ alert: Alert) {
        synchronized {
            _issuedAlerts.append(alert)
            record(.issueAlert(alert))
        }
    }

    func retractAlert(identifier: Alert.Identifier) {
        synchronized {
            _retractedAlerts.append(identifier)
            record(.retractAlert(identifier))
        }
    }

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

    func pumpManager(_ manager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        expectDelegateQueue(of: manager)
        synchronized {
            let update = StatusUpdate(newStatus: status, oldStatus: oldStatus)
            _statusUpdates.append(update)
            record(.statusUpdate(update))
        }
    }

    // MARK: - PumpManagerDelegate

    func pumpManagerBLEHeartbeatDidFire(_ manager: PumpManager) {
        expectDelegateQueue(of: manager)
        synchronized { record(.bleHeartbeatDidFire) }
    }

    func pumpManagerMustProvideBLEHeartbeat(_ manager: PumpManager) -> Bool {
        expectDelegateQueue(of: manager)
        return false
    }

    func pumpManagerWillDeactivate(_ manager: PumpManager) {
        expectDelegateQueue(of: manager)
        synchronized {
            _willDeactivateCount += 1
            record(.willDeactivate)
        }
    }

    func pumpManagerPumpWasReplaced(_ manager: PumpManager) {
        expectDelegateQueue(of: manager)
        synchronized {
            _pumpWasReplacedCount += 1
            record(.pumpWasReplaced)
        }
    }

    func pumpManager(_ manager: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents value: Bool) {
        expectDelegateQueue(of: manager)
        synchronized { record(.didUpdatePumpRecordsBasalProfileStartEvents(value)) }
    }

    func pumpManager(_ manager: PumpManager, didError error: PumpManagerError) {
        expectDelegateQueue(of: manager)
        synchronized {
            _errors.append(error)
            record(.didError(error))
        }
    }

    func pumpManager(
        _ manager: PumpManager,
        hasNewPumpEvents events: [NewPumpEvent],
        lastReconciliation: Date?,
        replacePendingEvents: Bool,
        completion: @escaping (Error?) -> Void
    ) {
        expectDelegateQueue(of: manager)
        synchronized {
            let batch = PumpEventBatch(
                events: events,
                lastReconciliation: lastReconciliation,
                replacePendingEvents: replacePendingEvents
            )
            _pumpEvents += events
            _pumpEventBatches.append(batch)
            record(.pumpEvents(batch))
        }
        didReceivePumpEventsExpectation?.fulfill()
        let holds = synchronized { () -> Bool in
            if _holdsPumpEventCompletions {
                _heldPumpEventCompletions.append(completion)
            }
            return _holdsPumpEventCompletions
        }
        if !holds {
            completion(nil)
        }
    }

    func pumpManager(
        _ manager: PumpManager,
        didReadReservoirValue units: Double,
        at date: Date,
        completion: @escaping (Swift.Result<
            (newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool),
            Error
        >) -> Void
    ) {
        expectDelegateQueue(of: manager)
        synchronized {
            let reading = ReservoirReading(units: units, date: date)
            _reservoirReadings.append(reading)
            record(.reservoirReading(reading))
        }
        didReadReservoirExpectation?.fulfill()
        completion(.success((SimpleReservoirValue(startDate: date, unitVolume: units), nil, true)))
    }

    func pumpManager(_ manager: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {
        expectDelegateQueue(of: manager)
        synchronized {
            _clockAdjustments.append(adjustment)
            record(.didAdjustPumpClock(by: adjustment))
        }
    }

    func pumpManagerDidUpdateState(_ manager: PumpManager) {
        expectDelegateQueue(of: manager)
        synchronized {
            _didUpdateStateCount += 1
            record(.didUpdateState)
        }
        didUpdateStateExpectation?.fulfill()
    }

    func pumpManager(
        _ manager: PumpManager,
        didRequestBasalRateScheduleChange schedule: BasalRateSchedule,
        completion: @escaping (Error?) -> Void
    ) {
        expectDelegateQueue(of: manager)
        synchronized { record(.didRequestBasalRateScheduleChange(schedule)) }
        completion(nil)
    }

    func startDateToFilterNewPumpEvents(for manager: PumpManager) -> Date {
        expectDelegateQueue(of: manager)
        return startDateToFilterNewPumpEvents
    }
}
