import Foundation
import LoopKit

class TandemDoseProgressReporter: DoseProgressReporter {
    var progress: DoseProgress {
        DoseProgress(deliveredUnits: deliveredUnits, percentComplete: deliveredUnits / total)
    }

    private var observers = WeakSet<DoseProgressObserver>()

    // larger total deliveries are faster -- a 10.05u bolus is almost twice as fast as a 9.95u one
    public static let BOLUS_SPEED_UNDER_10U = BolusEndDate.bolusSpeedUnder10U
    public static let BOLUS_SPEED_OVER_10U = BolusEndDate.bolusSpeedOver10U

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
    /// - Parameters:
    ///   - actualDeliveredUnits: The pump-reported delivered volume. When nil,
    ///     falls back to the programmed total (assumes full delivery).
    ///   - pumpTimestamp: The pump's timestamp on the `LastBolusStatus` record for this bolus,
    ///     when one was read.
    ///   - deliveryStartDate: When the pump said delivery began, when that was seen.
    ///   - detectedAt: When the driver noticed the bolus had finished. A parameter so the
    ///     resolved window can be tested.
    func getPumpEvent(
        actualDeliveredUnits: Double? = nil,
        pumpTimestamp: Date? = nil,
        deliveryStartDate: Date? = nil,
        detectedAt: Date = .now
    ) -> NewPumpEvent {
        let delivered = actualDeliveredUnits ?? total
        // The pump's window, not ours: neither end of it is the moment we noticed (#339).
        let endDate = BolusEndDate.resolve(
            startDate: dose.startDate,
            deliveryStartDate: deliveryStartDate,
            deliveredUnits: delivered,
            pumpTimestamp: pumpTimestamp,
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
            units: delivered,
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
