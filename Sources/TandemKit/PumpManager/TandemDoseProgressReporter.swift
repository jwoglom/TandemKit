import Foundation
import LoopKit

class TandemDoseProgressReporter: DoseProgressReporter {
    var progress: DoseProgress {
        let deliveredUnits = locked { _deliveredUnits }
        return DoseProgress(deliveredUnits: deliveredUnits, percentComplete: deliveredUnits / total)
    }

    private let observers = WeakSynchronizedSet<DoseProgressObserver>()

    private let pumpManager: TandemPumpManager
    private let dose: DoseEntry
    private let activationType: BolusActivationType
    private let eventRaw: Data?
    private let total: Double

    // notify() runs on the command and telemetry queues while hosts read progress on their own.
    private let lock = NSLock()
    private var _bolusStatedOn: Date?
    private var _deliveredUnits: Double = 0

    var bolusStatedOn: Date? { locked { _bolusStatedOn } }

    var programmedUnits: Double { total }

    public init(pumpManager: TandemPumpManager, dose: DoseEntry, activationType: BolusActivationType, eventRaw: Data? = nil) {
        self.pumpManager = pumpManager
        self.dose = dose
        self.activationType = activationType
        self.eventRaw = eventRaw
        total = dose.programmedUnits
    }

    /// This reporter, calling back the observers added through it on `queue`.
    func reporting(on queue: DispatchQueue) -> DoseProgressReporter {
        QueueBoundDoseProgressReporter(reporter: self, queue: queue)
    }

    func getPumpEvent(
        actualDeliveredUnits delivered: Double,
        pumpTimestamp: Date? = nil,
        deliveryStartDate: Date? = nil,
        detectedAt: Date? = nil
    ) -> NewPumpEvent {
        let detectedAt = detectedAt ?? pumpManager.now
        // The pump's window, not ours: neither end of it is the moment we noticed (#339).
        let endDate = BolusEndDate.resolve(
            startDate: dose.startDate,
            deliveryStartDate: deliveryStartDate,
            deliveredUnits: delivered,
            pumpTimestamp: pumpTimestamp.map(pumpManager.hostDate(forPumpDate:)),
            detectedAt: detectedAt
        )
        return NewPumpEvent.bolus(
            dose: DoseEntry.bolus(
                units: total,
                deliveredUnits: delivered,
                duration: 0, // Ignored if endDate is available
                activationType: activationType,
                insulinType: dose.insulinType,
                decisionId: dose.decisionId,
                startDate: deliveryStartDate ?? dose.startDate,
                endDate: endDate
            ),
            // The event date stays the moment the bolus was programmed even when the dose starts
            // later: hosts key pump events on it, and moving it would report a second bolus.
            date: dose.startDate,
            eventRaw: eventRaw
        )
    }

    public func addObserver(_ observer: DoseProgressObserver) {
        addObserver(observer, queue: .main)
    }

    func addObserver(_ observer: DoseProgressObserver, queue: DispatchQueue) {
        observers.insert(observer, queue: queue)
    }

    public func removeObserver(_ observer: DoseProgressObserver) {
        observers.removeElement(observer)
    }

    public func isUnfinalized() -> Bool {
        locked { _deliveredUnits } < total
    }

    public func notify() {
        let now = pumpManager.now
        let unitsDeliveredPerSec = if total < 10 {
            TandemPumpCapabilities.bolusSpeedUnder10U
        } else {
            TandemPumpCapabilities.bolusSpeedOver10U
        }

        let measured: Bool = locked {
            guard let bolusStatedOn = _bolusStatedOn else {
                // The first delivering status only starts the clock.
                _bolusStatedOn = now
                return false
            }

            let runningFor = TimeInterval(seconds: now.timeIntervalSince1970 - bolusStatedOn.timeIntervalSince1970)

            // Nearest milliunit, not the 0.05 U command grid: this estimate can end up as a dose's
            // delivered amount, and flooring it understates IOB.
            _deliveredUnits = TandemPumpCapabilities.roundToReportingResolution(min(runningFor * unitsDeliveredPerSec, total))
            return true
        }

        guard measured else {
            return
        }

        observers.forEach { observer in
            observer.doseProgressReporterDidUpdate(self)
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// LoopKit's contract: a host's observers are called on the queue it passed `createBolusProgressReporter(reportingOn:)`.
private final class QueueBoundDoseProgressReporter: DoseProgressReporter {
    private let reporter: TandemDoseProgressReporter
    private let queue: DispatchQueue

    init(reporter: TandemDoseProgressReporter, queue: DispatchQueue) {
        self.reporter = reporter
        self.queue = queue
    }

    var progress: DoseProgress { reporter.progress }

    func addObserver(_ observer: DoseProgressObserver) {
        reporter.addObserver(observer, queue: queue)
    }

    func removeObserver(_ observer: DoseProgressObserver) {
        reporter.removeObserver(observer)
    }
}
