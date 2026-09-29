import Foundation
import LoopKit

class TandemDoseProgressReporter: DoseProgressReporter {
    var progress: DoseProgress {
        DoseProgress(deliveredUnits: deliveredUnits, percentComplete: deliveredUnits / total)
    }

    private var observers = WeakSet<DoseProgressObserver>()

    private let pumpManager: TandemPumpManager
    private let dose: DoseEntry
    private let activationType: BolusActivationType
    private let total: Double
    public private(set) var bolusStatedOn: Date?
    private var deliveredUnits: Double = 0

    public init(pumpManager: TandemPumpManager, dose: DoseEntry, activationType: BolusActivationType) {
        self.pumpManager = pumpManager
        self.dose = dose
        self.activationType = activationType
        total = dose.programmedUnits
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
                startDate: deliveryStartDate ?? dose.startDate,
                endDate: endDate
            ),
            // The event date stays the moment the bolus was programmed even when the dose starts
            // later: hosts key pump events on it, and moving it would report a second bolus.
            date: dose.startDate
        )
    }

    public func addObserver(_ observer: DoseProgressObserver) {
        observers.insert(observer)
    }

    public func removeObserver(_ observer: DoseProgressObserver) {
        observers.remove(observer)
    }

    public func isUnfinalized() -> Bool {
        deliveredUnits < total
    }

    public func notify() {
        guard let bolusStatedOn else {
            // First time pump switched to delivering state
            // Just record the timestamp for now
            bolusStatedOn = pumpManager.now
            return
        }

        let runningFor = TimeInterval(seconds: pumpManager.now.timeIntervalSince1970 - bolusStatedOn.timeIntervalSince1970)

        let unitsDeliveredPerSec = if total < 10 {
            TandemPumpCapabilities.bolusSpeedUnder10U
        } else {
            TandemPumpCapabilities.bolusSpeedOver10U
        }

        // Nearest milliunit, not the 0.05 U command grid: this estimate can end up as a dose's
        // delivered amount, and flooring it understates IOB.
        deliveredUnits = HistoryToDoseMapper.roundToReportingResolution(min(runningFor * unitsDeliveredPerSec, total))

        DispatchQueue.main.async {
            for observer in self.observers {
                observer.doseProgressReporterDidUpdate(self)
            }
        }
    }
}
