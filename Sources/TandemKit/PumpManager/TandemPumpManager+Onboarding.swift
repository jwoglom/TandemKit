import Foundation
import HealthKit
import LoopKit

/// No clock field: a failed time write doesn't block setup, and `showPumpTimeSyncWarning` flags
/// a wrong pump clock afterwards.
public struct OnboardingSettingsFailure: Error {
    public let basalSchedule: Error?
    public let deliveryLimits: Error?
}

public extension TandemPumpManager {
    /// Loop and Trio only call `syncBasalRateSchedule` and `syncDeliveryLimits` from their settings
    /// screens, not during pump setup, so without this the pump keeps whatever it had. Issue #206.
    func applyOnboardingSettings(completion: @escaping (OnboardingSettingsFailure?) -> Void) {
        logger.info("Applying onboarding settings to pump")

        // Limits first: if the pump's current max basal is below a scheduled rate, it may refuse
        // that segment.
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
        // With no schedule from the host, `TandemUICoordinator` falls back to one 0 U/hr entry.
        // Writing that would set the pump to deliver no basal insulin.
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
