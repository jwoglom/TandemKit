import Foundation
import LoopAlgorithm
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
                    self.disableOnboardingQuickBolus()
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

    /// Under Control-IQ the pump refuses the host's automatic doses, and its basal reaches the host
    /// only with History Basal Reporting, so setup turns it off whatever the feature flags say.
    /// False when the pump does not answer: the first sync reads it again, but turns nothing off.
    func controlIQNeedsTurningOffForSetup(completion: @escaping (Bool) -> Void) {
        bluetooth.ensureConnected { error in
            if let error {
                self.logger.warning("Control-IQ not checked during setup: \(error.localizedDescription)")
                completion(false)
                return
            }
            guard let response = self.fetchControlIQStatus() else {
                self.logger.warning("Control-IQ not checked during setup: no response")
                completion(false)
                return
            }
            completion(response.getClosedLoopEnabled())
        }
    }

    /// Not `configureControlIQMode`, whose sync would read the pump's basal profile before
    /// `applyOnboardingSettings` writes the host's, and queue a profile update over it.
    func turnOffControlIQForSetup(completion: @escaping (Error?) -> Void) {
        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Control-IQ not turned off during setup: \(error.localizedDescription)")
                completion(error)
                return
            }

            // Turning Control-IQ off carries weight and TDI but does not depend on them.
            let request = ChangeControlIQSettingsRequest(
                enabled: false,
                weightLbs: self.state.controlIQWeightLbs ?? 0,
                totalDailyInsulinUnits: self.state.controlIQTotalDailyInsulin ?? 0
            )
            let response = self.bluetooth.write(request)
            if response?.isStatusOK != true {
                let failure = response.map { ControlIQConfigurationError.pumpRejected(status: $0.status) }
                    ?? .noResponse
                // An answer lost after the pump turned it off, or a refusal from a pump already off,
                // leaves nothing to retry. Not `fetchControlIQStatus`, which would start a hand-back.
                let readBack = self.bluetooth.write(
                    ControlIQInfoRequestBuilder.create(apiVersion: self.state.pumpState.apiVersion)
                ) as? ControlIQInfoAbstractResponse
                guard readBack?.getClosedLoopEnabled() == false else {
                    self.logger.error("Control-IQ not turned off during setup: \(failure)")
                    completion(failure)
                    return
                }
                self.logger.warning("Control-IQ turn-off during setup got \(failure), but the pump reads Control-IQ off")
            }

            self.logger.info("Turned Control-IQ off during setup")
            // No hand-back (`controlIQEndedAt`): the host has not dosed with this pump yet, so its
            // first syncs need not wait for Control-IQ's history.
            self.state.useControlIQ = false
            self.state.controlIQEnabled = false
            self.notifyDelegateStateUpdated()
            completion(nil)
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

        let limits = DeliveryLimits(
            maximumBasalRate: maxBasalRate.map { LoopQuantity(unit: .internationalUnitsPerHour, doubleValue: $0) },
            maximumBolus: maxBolus.map { LoopQuantity(unit: .internationalUnit, doubleValue: $0) }
        )

        syncDeliveryLimits(limits: limits) { completion($0.failure) }
    }

    func writeOnboardingSounds(completion: @escaping () -> Void) {
        guard state.pumpSoundsAwaitingWrite else {
            completion()
            return
        }
        guard let request = state.pumpSoundsRequest else {
            state.pumpSoundsAwaitingWrite = false
            completion()
            return
        }

        bluetooth.ensureConnected { error in
            // Written or not, the next pump-globals read should show what the pump holds.
            defer {
                self.state.pumpSoundsAwaitingWrite = false
                completion()
            }

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
        }
    }

    /// Otherwise the button stays live until the first sync, and a bolus from it reaches the host
    /// only from history.
    func disableOnboardingQuickBolus() {
        guard !state.featureFlags.quickBolusButtonSupport else { return }

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.warning("Quick bolus button not checked during setup: \(error.localizedDescription)")
                return
            }
            guard self.fetchGlobalPumpSettings() != nil else {
                self.logger.warning("Quick bolus button not checked during setup: no pump globals")
                return
            }
            self.enforceQuickBolusDisabled()
        }
    }
}

private extension TandemPumpManagerState {
    /// A nil sound is left as the pump has it.
    var pumpSoundsRequest: SetPumpSoundsRequest? {
        var changed: [PumpSoundChangeBitmask] = []
        if quickBolusAnnun != nil { changed.append(.quickBolusAnnun) }
        if generalAnnun != nil { changed.append(.generalAnnun) }
        if reminderAnnun != nil { changed.append(.reminderAnnun) }
        if alertAnnun != nil { changed.append(.alertAnnun) }
        if alarmAnnun != nil { changed.append(.alarmAnnun) }

        guard !changed.isEmpty else {
            return nil
        }

        // The pump applies only the fields whose bit is set; the zeros stand in for the rest.
        return SetPumpSoundsRequest(
            quickBolusAnnunRaw: quickBolusAnnun?.rawValue ?? 0,
            generalAnnunRaw: generalAnnun?.rawValue ?? 0,
            reminderAnnunRaw: reminderAnnun?.rawValue ?? 0,
            alertAnnunRaw: alertAnnun?.rawValue ?? 0,
            alarmAnnunRaw: alarmAnnun?.rawValue ?? 0,
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
