import Foundation
import HealthKit
import LoopKit

public extension TandemPumpManager {
    /// Writes the settings the host handed over in `PumpManagerSetupSettings` onto the pump.
    ///
    /// Loop and Trio call `syncBasalRateSchedule` / `syncDeliveryLimits` only from their therapy
    /// settings editors; during onboarding those editors save locally and the app passes the values
    /// to the driver instead, so writing them to the device is the driver's job.
    /// https://github.com/jwoglom/TandemKit/issues/206
    ///
    /// Reports the first error and keeps going: the writes are independent, and pairing has already
    /// succeeded by the time this runs.
    func applyOnboardingSettings(completion: @escaping (Error?) -> Void) {
        logger.info("Applying onboarding settings to pump")

        // Limits first, so the schedule is written against the limits the user configured rather
        // than whatever ceiling the pump was already holding.
        syncOnboardingDeliveryLimits { limitsError in
            self.syncOnboardingBasalSchedule { basalError in
                self.writePumpTime { completion(limitsError ?? basalError ?? $0) }
            }
        }
    }
}

private extension TandemPumpManager {
    func syncOnboardingBasalSchedule(completion: @escaping (Error?) -> Void) {
        // A state built without a host schedule falls back to a single 0 U/hr entry, and writing
        // that would cause the very 0 U/hr profile this exists to prevent.
        guard state.basalRateSchedule.items.contains(where: { $0.value > 0 }) else {
            logger.error("No basal schedule from setup; not writing a zero profile to the pump")
            completion(PumpManagerError.configuration(nil))
            return
        }

        syncBasalRateSchedule(items: state.basalRateSchedule.items) { completion($0.failure) }
    }

    func syncOnboardingDeliveryLimits(completion: @escaping (Error?) -> Void) {
        let maxBasalRate = state.settings.maxTempBasalRate
        let maxBolus = state.settings.maxBolus

        guard maxBasalRate != nil || maxBolus != nil else {
            logger.info("No delivery limits from setup; leaving the pump's own limits in place")
            completion(nil)
            return
        }

        let unitsPerHour = HKUnit.internationalUnit().unitDivided(by: .hour())
        let limits = DeliveryLimits(
            maximumBasalRate: maxBasalRate.map { HKQuantity(unit: unitsPerHour, doubleValue: $0) },
            maximumBolus: maxBolus.map { HKQuantity(unit: .internationalUnit(), doubleValue: $0) }
        )

        syncDeliveryLimits(limits: limits) { completion($0.failure) }
    }
}

private extension Result {
    var failure: Failure? {
        guard case let .failure(error) = self else { return nil }
        return error
    }
}
