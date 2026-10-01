import Foundation
import HealthKit
import LoopKit

/// No clock or sounds field: neither failed write blocks setup. `showPumpTimeSyncWarning` flags a
/// wrong pump clock afterwards, and sounds are not a safety setting.
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
                self.writeOnboardingSounds {
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

    func writeOnboardingSounds(completion: @escaping () -> Void) {
        guard let request = state.onboardingSounds?.request else {
            completion()
            return
        }

        bluetooth.ensureConnected { error in
            defer { completion() }

            if let error {
                self.logger.warning("Pump sounds not set during setup: \(error.localizedDescription)")
                return
            }

            guard let response = self.bluetooth.write(request) else {
                self.logger.warning("Pump sounds not set during setup: no response")
                return
            }

            guard response.isStatusOK else {
                self.logger.warning("Pump sounds not set during setup: status \(response.status)")
                return
            }

            self.state.onboardingSounds = nil
        }
    }
}

private extension TandemPumpManagerState.PumpSounds {
    var request: SetPumpSoundsRequest? {
        var changed: [PumpSoundChangeBitmask] = []
        if quickBolus != nil { changed.append(.quickBolusAnnun) }
        if general != nil { changed.append(.generalAnnun) }
        if reminder != nil { changed.append(.reminderAnnun) }
        if alert != nil { changed.append(.alertAnnun) }
        if alarm != nil { changed.append(.alarmAnnun) }

        guard !changed.isEmpty else {
            return nil
        }

        // The pump applies only the fields whose bit is set; the zeros stand in for the rest.
        return SetPumpSoundsRequest(
            quickBolusAnnunRaw: quickBolus?.rawValue ?? 0,
            generalAnnunRaw: general?.rawValue ?? 0,
            reminderAnnunRaw: reminder?.rawValue ?? 0,
            alertAnnunRaw: alert?.rawValue ?? 0,
            alarmAnnunRaw: alarm?.rawValue ?? 0,
            cgmAlertAnnunA: 0,
            cgmAlertAnnunB: 0,
            changeBitmaskRaw: PumpSoundChangeBitmask.toBitmask(changed)
        )
    }
}

private extension Result {
    var failure: Failure? {
        guard case let .failure(error) = self else { return nil }
        return error
    }
}
