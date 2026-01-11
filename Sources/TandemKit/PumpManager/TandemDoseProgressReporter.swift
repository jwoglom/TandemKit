import Foundation
import LoopKit

class TandemDoseProgressReporter: DoseProgressReporter {
    var progress: DoseProgress {
        DoseProgress(deliveredUnits: deliveredUnits, percentComplete: deliveredUnits / total)
    }

    private var observers = WeakSet<DoseProgressObserver>()

    private let FAST_INSULIN_SPEED = 0.15
    private let SLOW_INSULIN_SPEED = 0.075
    private let FAST_INSULIN_DELIVERY = TimeInterval(seconds: 10 / 0.15)

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

        // units < 10 -> bolus speed = 0.15 u/s
        // units > 10 -> bolus speed = first 10 units == 0.15 u/s, then == 0.075 u/s
        if runningFor < FAST_INSULIN_DELIVERY {
            deliveredUnits = min(runningFor * FAST_INSULIN_SPEED, total)
        } else {
            deliveredUnits = min(10 + (runningFor - FAST_INSULIN_DELIVERY) * SLOW_INSULIN_SPEED, total)
        }

        DispatchQueue.main.async {
            for observer in self.observers {
                observer.doseProgressReporterDidUpdate(self)
            }
        }
    }
}
