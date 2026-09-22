import Foundation
import HealthKit
import LoopKit

public extension TandemPumpManager {
    /// Writes the settings the host app handed over in `PumpManagerSetupSettings` onto the pump.
    ///
    /// Loop and Trio only call `syncBasalRateSchedule` / `syncDeliveryLimits` from their therapy
    /// settings editors. During onboarding LoopKit's editors save locally instead
    /// (`SavingMechanism.synchronous` in `.acceptanceFlow` mode), and the app hands the schedule
    /// and limits to the driver as setup settings, so writing them to the device is the driver's
    /// job -- the same way OmnipodKit programs the initial basal schedule during pod setup.
    ///
    /// Until this ran, a freshly paired pump kept whatever profile it already had while the driver
    /// reported the app-side schedule to the host. A Tandem temp basal is a percent of the pump's
    /// *profile* rate, so a pump sitting at 0 U/hr delivered nothing at any percent.
    /// https://github.com/jwoglom/TandemKit/issues/206
    ///
    /// Reports the first error and keeps going: the three writes are independent, and pairing
    /// itself has already succeeded by the time this runs.
    func applyOnboardingSettings(completion: @escaping (Error?) -> Void) {
        logger.info("Applying onboarding settings to pump")

        // Limits first, so the schedule is written against the limits the user configured rather
        // than whatever ceiling the pump was already holding.
        syncOnboardingDeliveryLimits { limitsError in
            self.syncOnboardingBasalSchedule { basalError in
                self.writePumpTime { timeError in
                    if let timeError {
                        self.logger.error("Onboarding pump time sync failed: \(timeError.localizedDescription)")
                    }

                    completion(limitsError ?? basalError ?? timeError)
                }
            }
        }
    }
}

private extension TandemPumpManager {
    func syncOnboardingBasalSchedule(completion: @escaping (Error?) -> Void) {
        // A state built without a schedule falls back to a single 0 U/hr entry, and oref will not
        // run an all-zero schedule anyway, so one that reaches here is a placeholder rather than
        // the user's. Writing it would set the pump profile to the very 0 U/hr this exists to
        // prevent, so leave the pump's own profile alone and report that nothing was applied.
        guard state.basalRateSchedule.items.contains(where: { $0.value > 0 }) else {
            logger.error("No basal schedule from setup; not writing a zero profile to the pump")
            completion(PumpManagerError.configuration(nil))
            return
        }

        syncBasalRateSchedule(items: state.basalRateSchedule.items) { result in
            switch result {
            case .success:
                completion(nil)
            case let .failure(error):
                self.logger.error("Onboarding basal schedule sync failed: \(error.localizedDescription)")
                completion(error)
            }
        }
    }

    func syncOnboardingDeliveryLimits(completion: @escaping (Error?) -> Void) {
        let unitsPerHour = HKUnit.internationalUnit().unitDivided(by: .hour())
        let maxBasalRate = state.settings.maxTempBasalRate
        let maxBolus = state.settings.maxBolus

        guard maxBasalRate != nil || maxBolus != nil else {
            logger.info("No delivery limits from setup; leaving the pump's own limits in place")
            completion(nil)
            return
        }

        let limits = DeliveryLimits(
            maximumBasalRate: maxBasalRate.map { HKQuantity(unit: unitsPerHour, doubleValue: $0) },
            maximumBolus: maxBolus.map { HKQuantity(unit: .internationalUnit(), doubleValue: $0) }
        )

        syncDeliveryLimits(limits: limits) { result in
            switch result {
            case .success:
                completion(nil)
            case let .failure(error):
                self.logger.error("Onboarding delivery limit sync failed: \(error.localizedDescription)")
                completion(error)
            }
        }
    }
}
