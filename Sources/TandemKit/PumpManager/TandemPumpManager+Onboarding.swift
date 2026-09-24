import Foundation
import HealthKit
import LoopKit

/// Which setup settings the pump did not take. A failed clock write is not one: the pump time badge
/// and the settings screen already cover it, and it leaves delivery as the app reports it.
public struct OnboardingSettingsFailure: Error {
    public let basalSchedule: Error?
    public let deliveryLimits: Error?
}

public extension TandemPumpManager {
    /// Loop and Trio sync basal rates and limits only from their therapy settings editors, so the
    /// driver has to write the ones handed over in `PumpManagerSetupSettings`. Issue #206.
    func applyOnboardingSettings(completion: @escaping (OnboardingSettingsFailure?) -> Void) {
        logger.info("Applying onboarding settings to pump")

        // Limits first, so the schedule is written against the limits the user configured.
        syncOnboardingDeliveryLimits { limitsError in
            self.syncOnboardingBasalSchedule { basalError in
                self.writePumpTime { timeError in
                    if let timeError {
                        self.logger.warning("Pump clock not set during setup: \(timeError.localizedDescription)")
                    }

                    guard basalError != nil || limitsError != nil else {
                        completion(nil)
                        return
                    }
                    completion(OnboardingSettingsFailure(basalSchedule: basalError, deliveryLimits: limitsError))
                }
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
