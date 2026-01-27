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

    private let dose: DoseEntry
    private let activationType: BolusActivationType
    private let total: Double
    public private(set) var bolusStatedOn: Date?
    private var deliveredUnits: Double = 0

    public init(dose: DoseEntry, activationType: BolusActivationType) {
        self.dose = dose
        self.activationType = activationType
        total = dose.programmedUnits
    }

    func getPumpEvent() -> NewPumpEvent {
        NewPumpEvent.bolus(
            dose: DoseEntry.bolus(
                units: total,
                deliveredUnits: total,
                duration: 0, // Ignored if endDate is available
                activationType: activationType,
                insulinType: dose.insulinType,
                startDate: dose.startDate,
                endDate: Date.now
            ),
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

        deliveredUnits = runningFor * unitsDeliveredPerSec

        DispatchQueue.main.async {
            for observer in self.observers {
                observer.doseProgressReporterDidUpdate(self)
            }
        }
    }
}
