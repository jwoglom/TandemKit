import Foundation
import LoopKit

class TandemDoseProgressReporter: DoseProgressReporter {
    var progress: DoseProgress {
        DoseProgress(deliveredUnits: deliveredUnits, percentComplete: deliveredUnits / total)
    }

    private var observers = WeakSet<DoseProgressObserver>()

    // larger total deliveries are faster -- a 10.05u bolus is almost twice as fast as a 9.95u one
    public static let BOLUS_SPEED_UNDER_10U = 1 / 28.745858684009523
    public static let BOLUS_SPEED_OVER_10U = 1 / 11.200233479381131

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

    /// Creates a finalized pump event for this bolus.
    /// - Parameter actualDeliveredUnits: The pump-reported delivered volume. When nil,
    ///   falls back to the programmed total (assumes full delivery).
    func getPumpEvent(actualDeliveredUnits: Double? = nil) -> NewPumpEvent {
        let delivered = actualDeliveredUnits ?? total
        return NewPumpEvent.bolus(
            dose: DoseEntry.bolus(
                units: total,
                deliveredUnits: delivered,
                duration: 0, // Ignored if endDate is available
                activationType: activationType,
                insulinType: dose.insulinType,
                startDate: dose.startDate,
                endDate: Date.now
            ),
            // Use the programmed total (not `delivered`) for the pump-event raw, so the derived
            // syncIdentifier is STABLE across the optimistic → finalized (→ history-reconciled) emits
            // for the same bolus. deliveredUnits carries the actual amount (that's what drives IOB);
            // keeping it out of the identity prevents a partial/cancelled bolus from being counted
            // twice (optimistic under one id, finalized under another).
            units: total,
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
            bolusStatedOn = Date.now
            return
        }

        let runningFor = TimeInterval(seconds: Date.now.timeIntervalSince1970 - bolusStatedOn.timeIntervalSince1970)

        let unitsDeliveredPerSec = if total < 10 {
            TandemDoseProgressReporter.BOLUS_SPEED_UNDER_10U
        } else {
            TandemDoseProgressReporter.BOLUS_SPEED_OVER_10U
        }

        deliveredUnits = pumpManager.roundToSupportedBolusVolume(units: min(runningFor * unitsDeliveredPerSec, total))

        DispatchQueue.main.async {
            for observer in self.observers {
                observer.doseProgressReporterDidUpdate(self)
            }
        }
    }
}
