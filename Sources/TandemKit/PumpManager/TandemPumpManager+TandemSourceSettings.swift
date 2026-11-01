import Foundation

/// Relays the pump's settings to Tandem Source, as the Mobi app does, so a clinic's settings and
/// profile reports show what the pump holds.
extension TandemPumpManager {
    /// The app reads settings on every connect; at about twenty reads plus one per profile segment,
    /// the driver reads them this often instead, and at once after it writes the basal profile.
    static let tandemSourceSettingsReadInterval: TimeInterval = .hours(6)

    /// Queues the read as its own job, so a sync hands the host its result without waiting on it.
    func refreshTandemSourceSettingsIfDue(force: Bool = false) {
        guard state.tandemSourceUploadEnabled, tandemSource.isAuthenticated else { return }

        let now = now
        tandemSourceSettingsLock.lock()
        if !force, let last = lastTandemSourceSettingsReadAt, now.timeIntervalSince(last) < Self.tandemSourceSettingsReadInterval {
            tandemSourceSettingsLock.unlock()
            return
        }
        lastTandemSourceSettingsReadAt = now
        tandemSourceSettingsLock.unlock()

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.warning("Couldn't connect to read settings for Tandem Source: \(error.localizedDescription)")
                return
            }
            guard let reads = self.readTandemSourceSettings() else {
                self.logger.warning("The pump didn't answer every settings read; Tandem Source settings not uploaded")
                return
            }
            self.uploadTandemSourceSettingsIfChanged(TandemSourceSettings(reads))
        }
    }

    func uploadTandemSourceSettingsIfChanged(_ settings: TandemSourceSettings) {
        let json: Data
        do {
            json = try settings.encoded()
        } catch {
            logger.error("Couldn't encode settings for Tandem Source: \(error)")
            return
        }
        let hash = SHA256.hash(json).hexadecimalString
        guard hash != state.lastTandemSourceSettingsHash else {
            logger.debug("Pump settings unchanged since the last Tandem Source upload")
            return
        }
        guard let inputs = tandemSourceInputs() else { return }

        tandemSource.triggerSettings(json, inputs: inputs) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(assignmentId):
                self.logger.info("Tandem Source: uploaded pump settings (\(settings.profiles.numberOfProfiles) profiles)")
                self.state.lastTandemSourceSettingsHash = hash
                self.state.lastTandemSourceSettingsUpload = self.now
                if self.state.tandemSourceDeviceAssignmentId != assignmentId {
                    self.state.tandemSourceDeviceAssignmentId = assignmentId
                }
            case let .failure(error):
                self.logger.error("Tandem Source settings upload failed: \(error)")
                self.state.lastTandemSourceError = String(describing: error)
            }
            self.notifyDelegateStateUpdated()
        }
    }

    /// Must run inside an `ensureConnected` job. Nil when a read the upload needs went unanswered.
    func readTandemSourceSettings() -> TandemSourceSettingsReads? {
        if let features = bluetooth.write(PumpFeaturesV2Request(supportedFeature: .mainFeatures)),
           features.supportedFeatureIndex == .mainFeatures
        {
            state.pumpMainFeaturesBitmask = features.pumpFeaturesBitmask
        }

        guard let globals = bluetooth.write(PumpGlobalsRequest()),
              let reminders = bluetooth.write(RemindersRequest()),
              let pumpSettings = bluetooth.write(PumpSettingsRequest()),
              let glucoseAlerts = bluetooth.write(CGMGlucoseAlertSettingsRequest()),
              let rateAlerts = bluetooth.write(CGMRateAlertSettingsRequest()),
              let outOfRangeAlert = bluetooth.write(CGMOORAlertSettingsRequest()),
              let cgmHardware = bluetooth.write(CGMHardwareInfoRequest()),
              let idp = loadIDPProfiles(),
              let profileStatus = idp.profileStatus
        else {
            return nil
        }

        return TandemSourceSettingsReads(
            globals: globals,
            reminders: reminders,
            pumpSettings: pumpSettings,
            glucoseAlerts: glucoseAlerts,
            rateAlerts: rateAlerts,
            outOfRangeAlert: outOfRangeAlert,
            cgmHardware: cgmHardware,
            profileStatus: profileStatus,
            profiles: idp.getProfiles().map { ($0.settings, $0.getSegments()) },
            basalLimit: bluetooth.write(BasalLimitSettingsRequest()),
            globalMaxBolus: bluetooth.write(GlobalMaxBolusSettingsRequest()),
            controlIQ: bluetooth.write(ControlIQInfoV2Request()),
            sleepSchedule: bluetooth.write(ControlIQSleepScheduleRequest()),
            localization: bluetooth.write(LocalizationRequest())
        )
    }
}
