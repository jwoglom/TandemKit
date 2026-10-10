import Foundation
import LoopKit

extension TandemPumpManager {
    func fetchTimeSinceReset() {
        guard let response = bluetooth.write(TimeSinceResetRequest()) else {
            logger.error("Failed to fetch time since reset")
            return
        }

        let timeSinceReset = response.pumpTimeSinceReset
        let currentPumpTime = response.currentTimeDate
        let checkedAt = now

        state.pumpState.timeSinceReset = timeSinceReset
        state.currentPumpTime = currentPumpTime
        state.lastPumpTimeCheckDate = checkedAt
        state.pumpTimeCheckUTCOffset = TimeZone.current.secondsFromGMT()

        notifyDelegateStateUpdated()
        reconcilePumpClockSkewAlert()
    }

    func fetchControlIQStatus() {
        let request = ControlIQInfoRequestBuilder.create(apiVersion: state.pumpState.apiVersion)
        guard let response = bluetooth.write(request) as? ControlIQInfoAbstractResponse else {
            logger.error("Failed to fetch ControlIQ info: \(type(of: request))")
            return
        }

        let closedLoopEnabled = response.getClosedLoopEnabled()
        state.controlIQEnabled = closedLoopEnabled

        // The dosing guards follow useControlIQ, so it mirrors the pump's state whenever that
        // differs from what's expected: a stale true refused every temp basal
        // (jwoglom/tandemkit-stress#4).
        if closedLoopEnabled != state.useControlIQ {
            logger.warning("Pump reports Control-IQ \(closedLoopEnabled ? "on" : "off") but useControlIQ was \(state.useControlIQ); syncing")
            if !closedLoopEnabled {
                state.controlIQEndedAt = now
            }
            state.useControlIQ = closedLoopEnabled
        }

        if let userMode = response.currentUserModeType {
            state.controlIQUserMode = TandemPumpManagerState.ControlIQUserMode.fromUserModeType(userMode)
        } else {
            state.controlIQUserMode = nil
        }

        // A pump on which Control-IQ has never been configured reports zeroes here. Those are not
        // values that can be sent back to it -- it rejects a ChangeControlIQSettingsRequest built
        // from them -- so they are stored as "unset" rather than as a weight of nothing.
        let reportedWeight = response.getWeight()
        state.controlIQWeightUnit = response.weightUnit
        state.controlIQWeightLbs = reportedWeight == 0
            ? nil
            : ControlIQSettingsLimits.pounds(from: reportedWeight, unit: response.weightUnit)

        let reportedTotalDailyInsulin = response.getTotalDailyInsulin()
        state.controlIQTotalDailyInsulin = reportedTotalDailyInsulin == 0 ? nil : reportedTotalDailyInsulin
        state.lastControlIQUpdate = now

        notifyDelegateStateUpdated()
    }

    /// Reads the pump's CGM sensor session status into `state.cgmSessionState`.
    ///
    /// The settings screen warns that Control-IQ is running open-loop when no CGM is connected, so
    /// the session state has to be refreshed on every sync — the user can pair or stop a sensor on
    /// the pump itself, and Control-IQ may have been enabled long before the app was launched.
    /// A failed read leaves the previous value in place rather than clearing it, so a dropped
    /// message never reads as "sensor disconnected".
    func fetchCGMSessionStatus() {
        // The request is Mobi-only; sending it to a pump that cannot answer would just burn a
        // round-trip timeout on every sync.
        guard supports(CGMStatusV2Request.self) else {
            return
        }

        guard let response = bluetooth.write(CGMStatusV2Request()) else {
            logger.error("Failed to fetch CGM status")
            return
        }

        updateCGMSessionState(from: response)
    }

    /// Stores the session state from a CGM status response, whatever triggered the read.
    func updateCGMSessionState(from response: CGMStatusV2Response) {
        state.cgmSessionState = response.sessionState
        state.lastCGMStatusUpdate = now

        notifyDelegateStateUpdated()
    }

    func fetchPumpInformation() {
        guard let apiResponse = bluetooth.write(ApiVersionRequest()) else {
            logger.error("Failed to fetch apiVersion")
            return
        }

        state.pumpState.apiVersion = apiResponse.getApiVersion()

        guard let pumpVersionResponse = bluetooth.write(PumpVersionBRequest()) else {
            logger.error("Failed to fetch PumpVersionB")
            return
        }

        state.pumpState.pumpSerial = pumpVersionResponse.serialNumber
        state.pumpState.modelNumber = pumpVersionResponse.modelNumber
        state.pumpState.softwareName = pumpVersionResponse.softwareName
        state.pumpState.controlBitsA = pumpVersionResponse.configurationBitsA
        state.pumpState.controlBitsB = pumpVersionResponse.configurationBitsB
        state.pumpState.pcbSerialNumber = pumpVersionResponse.pcbSerialNumberA
        state.pumpState.pumpModel = PumpModel(rawValue: pumpVersionResponse.modelNumber)

//        BleSoftwareInfoRequest
        // PumpVersionBRequest
        // ApiVersionRequest
    }

    func fetchSuspendStatus(completion: @escaping (Bool?) -> Void) {
        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for suspend status: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let response = self.bluetooth.write(CurrentBasalStatusRequest()) else {
                self.logger.error("Failed to fetch suspend status: \(String(describing: CurrentBasalStatusRequest.self))")
                completion(nil)
                return
            }

            // The wizards resume after this; a stop it found must reach the host first (#348).
            let isSuspended = response.basalType == .suspend
            guard self.observeDeliveryState(response.basalType) else {
                completion(isSuspended)
                return
            }
            self.afterHistoryIsReported { completion(isSuspended) }
            self.historyBackfillCoordinator.runTick()
        }
    }

    func fetchBasalStatus() {
        guard let response = bluetooth.write(CurrentBasalStatusRequest()) else {
            logger.error("Failed to fetch basal status: \(String(describing: CurrentBasalStatusRequest.self))")
            return
        }

        verifyDeliveredBasalRate(response)

        observeReplacedTempBasal(response)
        observeDeliveryState(response.basalType)

        if response.basalType == .tempBasal {
            reportTempBasalSegmentChanges()
            stopTempBasalOnFailedProfileUpdate()
        }

        maintainPumpClockSkewCompensation(response)
    }

    /// A temp is a percent of the pump's profile, so on one that differs from the schedule it runs
    /// other than what the host was told. A zero temp is 0% of any profile and keeps running.
    func stopTempBasalOnFailedProfileUpdate() {
        guard state.basalProfileUpdateFailed, state.basalDose.type == .tempBasal, state.basalDose.value > 0 else {
            return
        }
        guard let stop = bluetooth.write(StopTempRateRequest()), stop.isStatusOK else {
            logger.error("Could not stop the temp basal running on a basal profile that differs from the schedule")
            return
        }
        logger.warning("Stopped the temp basal: the pump's basal rate does not match the schedule")
        startScheduledBasalDose()
    }

    static let bolusSyncReconcileGrace: TimeInterval = .seconds(30)

    /// Defer to event-driven bolus tracking only while the bolus should still be delivering —
    /// a bolusChange event lost to a disconnect is never replayed, so sync must reconcile if past the grace time.
    func shouldDeferBolusSync(at date: Date? = nil) -> Bool {
        let date = date ?? now
        guard let bolusDose = state.bolusDose else {
            return false
        }
        return date < bolusDose.estimatedEndDate.addingTimeInterval(Self.bolusSyncReconcileGrace)
    }

    /// History reports a bolus the app did not start only once it completes.
    private func noteUntrackedBolus(_ response: CurrentBolusStatusResponse) {
        guard response.status == .delivering || response.status == .requesting,
              response.bolusId != state.bolusDose?.bolusId,
              let serial = historyLogStoreSerial?.rawValue,
              state.bolusReportLedger.entry(bolusId: response.bolusId, pumpSerial: serial) == nil
        else {
            return
        }
        let source = response.bolusSource.map { "\($0)" } ?? "source \(response.bolusSourceId)"
        guard state.featureFlags.historyDoseReporting else {
            logger.warning("Pump is delivering bolus \(response.bolusId) (\(source)), which the app did not start; with History Dose Reporting off it is never reported")
            return
        }

        let startDate = response.timestamp == 0 ? now : min(hostDate(forPumpDate: response.timestampDate), now)
        let floor = HistoryBackfillPlanner.emitFloor(
            bookkeeping: state.historyBackfill,
            trackingSince: state.bolusReportLedger.trackingSince,
            now: now
        )
        guard startDate >= floor else { return }
        let holdsBoundaryAt = max(startDate, state.lastReconciliation ?? startDate)
        if state.bolusReportLedger.boundaryHold(pumpSerial: serial) == nil {
            logger.info("Pump is delivering bolus \(response.bolusId) (\(source)), which the app did not start; holding lastReconciliation at \(holdsBoundaryAt) until history reports it")
        }
        state.bolusReportLedger.noteUnreported(BolusReportLedger.UnreportedBolus(
            bolusId: response.bolusId,
            pumpSerial: serial,
            startDate: startDate,
            holdsBoundaryAt: holdsBoundaryAt
        ))
        notifyDelegateStateUpdated()
    }

    struct UntrackedBolusProgress {
        let bolusId: Int
        let dose: DoseEntry
        let reporter: TandemDoseProgressReporter
    }

    /// Hosts show a bolus, and the button that stops it, only while `bolusState` says it runs and
    /// they can get a progress reporter for it. The dose itself still reaches them only from history.
    private func showUntrackedBolus(_ response: CurrentBolusStatusResponse) -> Bool {
        guard response.status == .delivering || response.status == .requesting, response.requestedVolume > 0 else {
            endUntrackedBolus()
            return false
        }

        if untrackedBolusProgress?.bolusId != response.bolusId {
            let startDate = response.timestamp == 0 ? now : min(hostDate(forPumpDate: response.timestampDate), now)
            let units = Double(response.requestedVolume) / 1000
            let automatic = response.bolusSource == .controlIQAutoBolus
            let dose = DoseEntry(
                type: .bolus,
                startDate: startDate,
                endDate: startDate.addingTimeInterval(estimatedDuration(toBolus: units)),
                value: units,
                unit: .units,
                description: "Bolus #\(response.bolusId)",
                syncIdentifier: historyLogStoreSerial.map { HistoryLogSyncIdentifier.bolus(pumpSerial: $0, bolusId: response.bolusId).hexadecimalString },
                insulinType: state.insulinType,
                automatic: automatic,
                isMutable: true,
                wasProgrammedByPumpUI: response.bolusSource != .bluetoothRemoteBolus
            )
            untrackedBolusProgress = UntrackedBolusProgress(
                bolusId: response.bolusId,
                dose: dose,
                reporter: TandemDoseProgressReporter(
                    pumpManager: self,
                    dose: dose,
                    activationType: automatic ? .automatic : .manualNoRecommendation,
                    deliveryStartedAt: response.status == .delivering ? startDate : nil
                )
            )
            logger.info("Showing bolus \(response.bolusId), which the app did not start, as in progress")
        }
        guard let progress = untrackedBolusProgress else { return true }

        let bolusState: PumpManagerStatus.BolusState = response.status == .delivering ? .inProgress(progress.dose) : .initiating
        if state.bolusState != bolusState {
            state.bolusState = bolusState
            notifyDelegateStateUpdated()
        }
        if response.status == .delivering {
            progress.reporter.notify()
            telemetryScheduler.schedule(kind: .bolus, interval: .seconds(1), leeway: .milliseconds(100)) { [weak self] in
                self?.untrackedBolusProgress?.reporter.notify()
            }
        }
        return true
    }

    func endUntrackedBolus() {
        guard untrackedBolusProgress != nil else { return }
        untrackedBolusProgress = nil
        telemetryScheduler.cancelAll()
        state.bolusState = .noBolus
        notifyDelegateStateUpdated()
    }

    func fetchBolusStatus(fromSync: Bool) {
        if fromSync, shouldDeferBolusSync() {
            logger.warning("Skip bolus sync during bolus...")
            return
        }

        if fromSync, let bolusDose = state.bolusDose {
            logger.warning("Bolus \(bolusDose.bolusId ?? -1) past estimated end; reconciling stale bolus state")
        }

        guard let response = bluetooth.write(CurrentBolusStatusRequest()) else {
            logger.error("Failed to fetch bolus status: \(type(of: CurrentBolusStatusRequest.self))")
            return
        }

        noteUntrackedBolus(response)
        if state.bolusDose == nil, bolusProgressReport == nil, showUntrackedBolus(response) {
            return
        }

        // The pump runs one bolus at a time: another id delivering means ours finished out of contact.
        let trackedBolusId = state.bolusDose?.bolusId
        let deliveringAnother = response.status == .delivering && trackedBolusId != nil && response.bolusId != trackedBolusId
        if deliveringAnother {
            logger.warning("Pump is delivering bolus \(response.bolusId), not \(trackedBolusId ?? -1); finishing ours")
        }

        if response.status == .alreadyDeliveredOrInvalid || deliveringAnother, bolusProgressReport == nil {
            guard let dose = state.bolusDose, let bolusId = dose.bolusId else {
                if state.bolusState != .noBolus {
                    state.bolusState = .noBolus
                    notifyDelegateStateUpdated()
                }
                return
            }

            var events = getActivePumpEvents()
            if let lastBolus = queryLastBolusReport(bolusId: bolusId) {
                dose.deliveredUnits = lastBolus.deliveredUnits
                events.append(NewPumpEvent.bolus(
                    dose: dose.toDoseEntry(
                        endDate: BolusEndDate.resolve(
                            startDate: dose.startDate,
                            deliveryStartDate: dose.deliveryStartDate,
                            deliveredUnits: dose.deliveredUnits,
                            pumpTimestamp: hostDate(forPumpDate: lastBolus.pumpTimestamp),
                            detectedAt: now
                        ),
                        now: now
                    ),
                    date: dose.startDate
                ))
            } else {
                holdForFinalization(dose, fallbackUnits: dose.value)
                events.append(NewPumpEvent.bolus(
                    dose: dose.toDoseEntry(isMutable: true),
                    date: dose.startDate
                ))
            }

            state.bolusDose = nil
            state.bolusState = .noBolus
            state.lastReconciliation = now
            notifyDelegateStateUpdated()
            emitPumpEvents(events)
            return
        }

        if bolusProgressReport == nil, let dose = state.bolusDose {
            bolusProgressReport = TandemDoseProgressReporter(
                pumpManager: self,
                dose: dose.toDoseEntry(isMutable: true),
                activationType: dose.automatic ? .automatic : .manualNoRecommendation
            )
        }

        guard let progressReport = bolusProgressReport else {
            return
        }

        if response.status == .delivering, !deliveringAnother {
            if let dose = state.bolusDose {
                // The pump's own start of delivery, which runs ~15s behind when we programmed the
                // bolus, is what the reported dose starts at (#339).
                dose.recordDeliveryStart(hostDate(forPumpDate: response.timestampDate), now: now)

                // Recalculate endDate of the bolus
                dose.estimatedEndDate = now.addingTimeInterval(estimatedDuration(toBolus: dose.value))

                state.bolusDose = dose
                state.bolusState = .inProgress(dose.toDoseEntry(isMutable: true))
                notifyDelegateStateUpdated()
            }

            progressReport.notify()

            telemetryScheduler.cancelAll()
            telemetryScheduler.schedule(kind: .bolus, interval: .seconds(1), leeway: .milliseconds(100)) {
                self.bolusProgressReport?.notify()
            }
            return
        }

        if response.bolusId == 0 || deliveringAnother {
            telemetryScheduler.cancelAll()

            // The pump's own timestamp dates the end of delivery, not this detection (#339).
            var lastBolus: LastBolusReport?
            if let bolusId = state.bolusDose?.bolusId {
                lastBolus = queryLastBolusReport(bolusId: bolusId)
            }

            var events = getActivePumpEvents()
            if let lastBolus {
                events.append(progressReport.getPumpEvent(
                    actualDeliveredUnits: lastBolus.deliveredUnits,
                    pumpTimestamp: lastBolus.pumpTimestamp,
                    deliveryStartDate: state.bolusDose?.deliveryStartDate
                ))
            } else if let dose = state.bolusDose {
                // Held, not finalized at the programmed total: the pump may yet say it stopped early,
                // and a finalized dose is never revised (#328).
                logger.error("No delivered volume for finished bolus \(dose.bolusId ?? -1); keeping it mutable")
                holdForFinalization(dose, fallbackUnits: dose.value)
                events.append(NewPumpEvent.bolus(
                    dose: dose.toDoseEntry(isMutable: true),
                    date: dose.startDate
                ))
            } else {
                // Not the sampled estimate, which is 0 U until a second delivering status (#448).
                events.append(progressReport.getPumpEvent(actualDeliveredUnits: progressReport.programmedUnits))
            }

            bolusProgressReport = nil
            state.bolusDose = nil
            state.bolusState = .noBolus
            state.lastReconciliation = now
            notifyDelegateStateUpdated()

            emitPumpEvents(events)
        }
    }

    /// Re-reads only the pump's notification surfaces (alerts, alarms, CGM alerts, malfunctions)
    /// and reports whether the pump could be reached.
    ///
    /// This is the cheap counterpart to `syncPumpData` for screens that only care about what the
    /// pump is currently asking the user to acknowledge. It matters most during a tubing fill: the
    /// pump can stop mid-fill and wait for confirmation before it delivers more, and the screen has
    /// no way to know that until the notification state is read again (#248). Pulling reservoir,
    /// battery, bolus and basal along with it would make that read far too expensive to repeat as
    /// often as the fill screen needs to.
    func refreshNotifications(completion: @escaping (Bool) -> Void) {
        let completion = watchdogged(timeoutResult: false, completion)
        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for notification refresh: \(error.localizedDescription)")
                completion(false)
                return
            }

            self.fetchNotifications()
            completion(true)
        }
    }

    func fetchNotifications() {
        notificationBundle = NotificationBundle()
        for request in NotificationBundle.allRequests(apiVersion: state.pumpState.apiVersion) {
            guard let response = bluetooth.write(request) else {
                logger.error("Failed to fetch notification status of \(type(of: request))")
                continue
            }

            guard NotificationBundle.isNotificationResponse(response) else {
                continue
            }

            if let response = response as? AlertStatusResponse {
                autoAcknowledgeBasalAlertsIfNeeded(alertResponse: response)
            }

            notificationBundle.add(response)
        }

        state.notificationCount = notificationBundle.getNotificationCount()
        state.lastNotificationUpdate = now
        notifyDelegateStateUpdated()

        reconcileLoopKitAlerts()
    }

    func fetchDeliveryLimits() {
        guard let basalResponse = bluetooth.write(BasalLimitSettingsRequest()) else {
            logger.error("Failed to fetch basal limits: \(type(of: BasalLimitSettingsRequest.self))")
            return
        }

        guard let bolusResponse = bluetooth.write(GlobalMaxBolusSettingsRequest()) else {
            logger.error("Failed to fetch bolus limits: \(type(of: GlobalMaxBolusSettingsRequest.self))")
            return
        }

        state.maxBasalLimitMilliunits = Int(basalResponse.basalLimit)
        state.maxBasalLimitDefaultMilliunits = Int(basalResponse.basalLimitDefault)
        state.maxBolusLimitMilliunits = bolusResponse.maxBolus
        state.maxBolusLimitDefaultMilliunits = bolusResponse.maxBolusDefault
        notifyDelegateStateUpdated()
    }

    @discardableResult func fetchGlobalPumpSettings() -> PumpGlobalsResponse? {
        guard let response = bluetooth.write(PumpGlobalsRequest()) else {
            logger.error("Failed to fetch global pump settings: \(type(of: PumpGlobalsRequest.self))")
            return nil
        }

        if !state.pumpSoundsAwaitingWrite {
            state.quickBolusAnnun = response.quickBolusAnnouncement
            state.reminderAnnun = response.reminderAnnouncement
            state.alarmAnnun = response.alarmAnnouncement
            state.alertAnnun = response.alertAnnouncement
            state.generalAnnun = response.generalAnnouncement
        }
        state.quickBolusEnabled = response.isQuickBolusEnabled()
        state.quickBolusEntryType = response.quickBolusEntryType
        state.quickBolusIncrementUnits = response.quickBolusIncrementUnits
        state.quickBolusIncrementCarbs = response.quickBolusIncrementCarbs
        state.quickBolusStatus = response.quickBolusStatus
        notifyDelegateStateUpdated()
        return response
    }

    /// Turns the pump's quick bolus button off when `quickBolusButtonSupport` is off and the pump
    /// reports it enabled. Reads `state.quickBolusEnabled`, so it needs a `fetchGlobalPumpSettings`
    /// earlier in the same sync.
    func enforceQuickBolusDisabled() {
        guard !state.featureFlags.quickBolusButtonSupport, state.quickBolusEnabled == true else {
            return
        }

        logger.warning("Quick bolus button is enabled on the pump; disabling it")

        let request = SetQuickBolusSettingsRequest(
            enabled: false,
            mode: state.quickBolusEntryType.flatMap(QuickBolusMode.init(rawValue:)) ?? .units,
            incrementUnits: state.quickBolusIncrementUnits ?? 500,
            incrementCarbs: state.quickBolusIncrementCarbs ?? 2000,
            changedFields: .enabled
        )
        guard let response = bluetooth.write(request) else {
            logger.error("Failed to disable quick bolus button: no response")
            return
        }

        guard response.isStatusOK else {
            logger.error("Failed to disable quick bolus button: status \(response.status)")
            return
        }

        state.quickBolusEnabled = false
        logger.info("Disabled the quick bolus button on the pump")
        notifyDelegateStateUpdated()
    }

    /// Runs its own command job, so it is safe to call from anywhere.
    func fetchReservoirStatus(completion: @escaping (Double?) -> Void) {
        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for reservoir status: \(error.localizedDescription)")
                completion(nil)
                return
            }

            completion(self.fetchReservoirStatus())
        }
    }

    /// Returns the units remaining, or nil on failure.
    @discardableResult
    func fetchReservoirStatus() -> Double? {
        guard let response = bluetooth.write(InsulinStatusRequest()) else {
            logger.error("Failed to fetch reservoir status: \(type(of: InsulinStatusRequest.self))")
            return nil
        }

        let timestamp = now
        let units = Double(response.currentInsulinAmount)
        let reservoirValue = SimpleReservoirValue(startDate: timestamp, unitVolume: units)

        logger.debug("Reservoir updated: \(String(format: "%.2f", units)) U remaining")

        state.lastReconciliation = timestamp
        state.lastReservoirReading = reservoirValue
        state.lastReservoirReadingNeedsReport = true
        notifyDelegateStateUpdated()

        reportReservoirReading(reservoirValue)

        // Also runs outside a sync, and a reservoir value newer than the host's event boundary
        // arbitrates back to whole-unit reservoir doses.
        reportReconciliationBoundary()

        return units
    }

    /// `didReadReservoirValue` is the reservoir's only channel to the host and nothing re-derives
    /// it, so a call made with no delegate attached — the pairing sync runs before the host adopts
    /// the manager — would strand the host on a stale value. Hold the reading for the flush below
    /// instead. The pending flag is read and written inside `notify`, serialized on the delegate
    /// queue, so a flush racing a fresh read cannot report twice.
    func reportReservoirReading(_ reading: ReservoirValue) {
        pumpDelegate.notify { delegate in
            guard let delegate = delegate else {
                self.logger.warning("No pump delegate; holding reservoir reading until one attaches")
                return
            }

            self.logger.debug("Reporting \(String(format: "%.2f", reading.unitVolume)) U to the host app")

            delegate.pumpManager(
                self,
                didReadReservoirValue: reading.unitVolume,
                at: reading.startDate,
                completion: { _ in }
            )

            self.state.lastReservoirReadingNeedsReport = false
            self.notifyDelegateStateUpdated()
        }
    }

    /// Sends the last reading if it never reached a delegate. A no-op in the normal case.
    func flushPendingReservoirReading() {
        guard state.lastReservoirReadingNeedsReport, let reading = state.lastReservoirReading else {
            return
        }

        logger.info("Delegate attached; reporting the reservoir reading it missed")
        reportReservoirReading(reading)
    }

    func fetchBatteryStatus() {
        let request = CurrentBatteryRequestBuilder.create(apiVersion: state.pumpState.apiVersion)
        guard let response = bluetooth.write(request) as? CurrentBatteryAbstractResponse else {
            logger.error("Failed to fetch Battery status: \(type(of: request))")
            return
        }

        logger.debug("Battery updated: \(response.batteryPercent)% remaining, charging=\(response.isCharging)")

        state.lastBatteryReading = TandemPumpManagerState.BatteryReading(
            date: now,
            chargeRemaining: Double(response.batteryPercent) / 100.0,
            isCharging: response.isCharging
        )
        notifyDelegateStateUpdated()
    }

    func handleHomeScreenMirrorResponse(_ response: HomeScreenMirrorResponse) {
        guard let basalIcon = response.basalStatusIcon else {
            return
        }

        let basalType = basalIcon.type
        if basalType != state.basalDose.type {
            let now = self.now
            var events = getActivePumpEvents(endDate: now)
            var dose: UnfinalizedDose

            switch basalType {
            case .suspend:
                dose = UnfinalizedDose(suspendStartTime: now)
                events.append(NewPumpEvent.suspend(dose: dose.toDoseEntry(), date: dose.startDate))

            case .basal:
                // Home screen does not emit resume, thus we check if we need to emit resume or basal
                // based on previous state
                if state.basalDose.type == .suspend {
                    dose = UnfinalizedDose(
                        resumeStartTime: now,
                        insulinType: state.insulinType
                    )
                } else {
                    dose = UnfinalizedDose(
                        basalRate: getScheduledBasalRate(),
                        insulinType: state.insulinType,
                        startDate: now
                    )
                }
                events.append(NewPumpEvent.basal(dose: dose.toDoseEntry(), date: dose.startDate))

            default:
                return
            }

            state.basalDose = dose
            notifyDelegateStateUpdated()
            emitPumpEvents(events)
        }
    }

    static let bolusFinalizationWindow: TimeInterval = .minutes(15)

    /// Holds `dose` mutable until the pump or its history says what it delivered (#328), and
    /// records `fallbackUnits` as what it is finalized with if neither ever does (#448).
    func holdForFinalization(_ dose: UnfinalizedDose, fallbackUnits: Double, now: Date? = nil) {
        let now = now ?? self.now
        let previouslyHeld = state.pendingBolusFinalization

        dose.deliveredUnits = fallbackUnits
        // Delivery has stopped; also the start of the retry window.
        dose.estimatedEndDate = now
        // Before the stale one is finalized, so that replacing batch carries this one.
        state.pendingBolusFinalization = dose

        if let stale = previouslyHeld, stale.bolusId != dose.bolusId {
            // Only one is held at a time, so the older settles now rather than staying mutable
            // forever. Not from LastBolusStatus: that describes the newer bolus.
            let record = stale.bolusId.flatMap { historyBolusReport(bolusId: $0, startedAt: stale.startDate) }
            if let record {
                stale.deliveredUnits = record.deliveredUnits
            }
            finalize(stale, pumpTimestamp: record?.pumpTimestamp, now: now)
        }
    }

    /// Closes out a bolus left mutable because its delivered volume was unknown, with the pump's
    /// number from `LastBolusStatus` or its history or, past the window, the fallback recorded
    /// when it was held (#328, #448).
    func finalizePendingBolus(now: Date? = nil) {
        let now = now ?? self.now
        guard let pending = state.pendingBolusFinalization, let bolusId = pending.bolusId else {
            return
        }

        // `LastBolusStatus` reports whatever the pump stored last, which mid-bolus may be a later
        // bolus carrying the same id.
        let lastBolus = state.bolusDose == nil ? queryLastBolusReport(bolusId: bolusId) : nil
        let record = lastBolus ?? historyBolusReport(bolusId: bolusId, startedAt: pending.startDate)
        if let record {
            pending.deliveredUnits = record.deliveredUnits
        } else if now.timeIntervalSince(pending.estimatedEndDate) < Self.bolusFinalizationWindow {
            logger.warning("Pump still has no delivered volume for bolus \(bolusId); leaving it mutable")
            return
        } else {
            logger.error(
                "Giving up on the pump's delivered volume for bolus \(bolusId); finalizing with the fallback \(pending.deliveredUnits)U"
            )
        }

        finalize(pending, pumpTimestamp: record?.pumpTimestamp, now: now)
    }

    /// The pump's `BolusCompleted` record for `bolusId`, if history backfill has already read it
    /// into the session store. Never reads the pump itself, so it honours the backfill flag (#448).
    func historyBolusReport(bolusId: Int, startedAt: Date) -> LastBolusReport? {
        guard let serial = historyLogStoreSerial else {
            return nil
        }

        // An hour's margin for clock skew; bolus ids repeat only over far longer.
        let since = Dates.fromInstantToJan12008EpochSeconds(startedAt.addingTimeInterval(state.pumpClockOffset - .hours(1)))
        let stored: [StoredHistoryLog]
        do {
            stored = try historyLogStore.logs(
                pumpSerial: serial.rawValue,
                ofTypes: [BolusCompletedHistoryLog.typeId],
                sincePumpTimeSec: UInt32(clamping: Int64(max(0, since)))
            )
        } catch {
            logger.error("Failed to read history for bolus \(bolusId): \(error)")
            return nil
        }

        guard let completion = stored.compactMap({ $0.parsed() as? BolusCompletedHistoryLog }).last(where: { $0.bolusId == bolusId })
        else {
            return nil
        }
        logger.info("Delivered volume for bolus \(bolusId) recovered from pump history")
        return LastBolusReport(
            deliveredUnits: HistoryToDoseMapper.roundToReportingResolution(Double(completion.insulinDelivered)),
            // Same pump clock and epoch as `LastBolusStatus`, so `finalize` translates it the same way.
            pumpTimestamp: Dates.fromJan12008EpochSecondsToDate(TimeInterval(completion.pumpTimeSec))
        )
    }

    private func finalize(_ pending: UnfinalizedDose, pumpTimestamp: Date?, now: Date) {
        let finalizedDose = pending.toDoseEntry(
            endDate: BolusEndDate.resolve(
                startDate: pending.startDate,
                deliveryStartDate: pending.deliveryStartDate,
                deliveredUnits: pending.deliveredUnits,
                pumpTimestamp: pumpTimestamp.map(hostDate(forPumpDate:)),
                detectedAt: now
            ),
            now: now
        )

        if state.pendingBolusFinalization === pending {
            state.pendingBolusFinalization = nil
        }

        var events = getActivePumpEvents()
        events.append(NewPumpEvent.bolus(dose: finalizedDose, date: pending.startDate))

        state.lastReconciliation = now
        notifyDelegateStateUpdated()
        emitPumpEvents(events)
    }

    /// What the pump reports about a bolus it has finished with.
    struct LastBolusReport {
        /// Delivered volume in units, at the pump's native milliunit resolution.
        let deliveredUnits: Double
        /// The pump's own timestamp on the record. Used to date the end of delivery instead of
        /// the moment the driver noticed it (see `BolusEndDate`).
        let pumpTimestamp: Date
    }

    /// Queries the pump for what it recorded about the last bolus.
    /// Used after both cancellation and natural completion to get the real delivered amount and
    /// the pump's own timestamp for it. Returns nil if the query fails or the bolus ID doesn't
    /// match.
    func queryLastBolusReport(bolusId: Int) -> LastBolusReport? {
        let request = LastBolusRequestBuilder.create(
            apiVersion: state.pumpState.apiVersion,
            pumpModel: state.pumpState.pumpModel
        )

        guard let response = bluetooth.write(request) as? LastBolusStatusAbstractResponse else {
            logger.error("Failed to get lastBolusStatus: \(type(of: request))")
            return nil
        }

        guard let milliunits = deliveredMilliunits(from: response, bolusId: bolusId) else {
            return nil
        }

        return LastBolusReport(
            // Round to nearest milliunit, matching `HistoryToDoseMapper`. Not
            // `roundToSupportedBolusVolume`: that floors to the 0.05 U command grid, understating
            // a partial delivery by up to an increment — the direction that lets the loop
            // over-deliver.
            deliveredUnits: HistoryToDoseMapper.roundToReportingResolution(Double(milliunits) / 1000.0),
            pumpTimestamp: pumpTimestamp(from: response, bolusId: bolusId)
        )
    }

    /// Convenience for callers that only need the volume.
    func queryLastBolusDeliveredVolume(bolusId: Int) -> Double? {
        queryLastBolusReport(bolusId: bolusId)?.deliveredUnits
    }

    /// The pump's timestamp for `bolusId`. On a V3 response the two records can carry different
    /// timestamps, so the latest of the matching ones is used: delivery is over only once every
    /// portion of the bolus is.
    private func pumpTimestamp(from response: LastBolusStatusAbstractResponse, bolusId: Int) -> Date {
        if let v3 = response as? LastBolusStatusV3Response {
            let matching = v3.sections.filter { $0.bolusId == bolusId }
            if let latest = matching.map(\.timestampDate).max() {
                return latest
            }
        }
        return response.timestampDate
    }

    /// Delivered volume in milliunits that `response` reports for `bolusId`, or nil when it
    /// describes some other bolus.
    private func deliveredMilliunits(from response: LastBolusStatusAbstractResponse, bolusId: Int) -> UInt32? {
        // A V3 response reports the immediate and extended records separately. The driver only
        // ever programs immediate boluses, so our id should only ever appear in the immediate
        // record; summing guards the case where the pump reports both against one id, which no
        // capture covers. Over-reporting delivered insulin is the safer way to be wrong here.
        if let v3 = response as? LastBolusStatusV3Response {
            guard let matched = v3.deliveredVolume(forBolusId: bolusId) else {
                logger.warning("LastBolusStatusV3 has no record for bolusId \(bolusId): \(v3)")
                return nil
            }
            return matched
        }

        guard response.bolusId == bolusId else {
            logger.warning("LastBolusStatus bolusId \(response.bolusId) != expected \(bolusId)")
            return nil
        }
        return response.deliveredVolume
    }

    func autoAcknowledgeBasalAlertsIfNeeded(alertResponse: AlertStatusResponse) {
        guard state.autoAcknowledgeBasalAlerts else {
            return
        }

        let basalAlertsToAck = alertResponse.alerts.intersection(
            AlertStatusResponse.AlertResponseType.basalAlertsToIgnoreWhenLooping
        )

        guard !basalAlertsToAck.isEmpty else {
            return
        }

        logger.info("[auto-ack] Found \(basalAlertsToAck.count) basal alert(s) to acknowledge: \(basalAlertsToAck)")
        for alert in basalAlertsToAck {
            guard let response = bluetooth.write(DismissNotificationRequest(
                    notificationType: .alert,
                    notificationId: UInt32(alert.rawValue)
                )) else {
                logger.error("Failed to send DismissNotificationRequest")
                return
            }

            if response.status != 0 {
                logger.warning("[auto-ack] Failed to acknowledge \(alert): status=\(response.status)")
            }
        }
    }
}

extension TandemPumpManager {
    /// Time for the write started at the first mismatching reading to land, and to be retried, before
    /// a mismatch still read is a failure.
    static let basalProfileUpdateTimeout: TimeInterval = .minutes(5)

    /// Writes the host's schedule over a mismatch rather than leaving the pump's profile: hosts take
    /// the pump to hold what they last saved, as Trio keeps a basal profile only once a sync takes.
    func verifyDeliveredBasalRate(_ response: CurrentBasalStatusResponse) {
        guard let mismatch = deliveredBasalRateMismatch(response) else {
            // One matching segment is not the whole profile; only a read-back ends an update.
            if state.basalProfileUpdateStatus != .none {
                updatePumpBasalProfile()
            }
            return
        }

        logger.error("Pump basal profile is \(mismatch.pump) U/hr where the schedule says \(mismatch.expected) U/hr")
        noteBasalProfileMismatch()
    }

    /// Nil when the rates agree, or when the reading says nothing about the profile.
    func deliveredBasalRateMismatch(_ response: CurrentBasalStatusResponse) -> (pump: Double, expected: Double)? {
        // An all-zero schedule is the placeholder for one the host never gave, not a rate to hold.
        guard state.basalRateSchedule.items.contains(where: { $0.value > 0 }) else {
            return nil
        }

        let pumpRate: Double
        switch response.basalType {
        case .basal where !state.useControlIQ:
            pumpRate = response.currentBasalRate
        case .basal, .tempBasal:
            // `currentBasalRate` is the temp's or Control-IQ's; `profileBasalRate` is the profile's.
            pumpRate = response.profileBasalRate
        default:
            return nil
        }

        // Look the schedule up at the pump's time of day. The offset, not `currentPumpTime`, which
        // is a snapshot from the last clock read.
        let expected = getScheduledBasalRate(at: now.addingTimeInterval(state.pumpClockOffset))

        // Compare whole milliunits, as the pump stores them, so float noise isn't a mismatch.
        guard Int((pumpRate * 1000).rounded()) != Int((expected * 1000).rounded()) else {
            return nil
        }
        return (pumpRate, expected)
    }

    /// From a basal reading or a profile read that differs from the schedule.
    func noteBasalProfileMismatch() {
        guard let detectedAt = state.basalRateMismatchDetectedAt else {
            logger.warning("Updating the pump's basal profile to match the schedule")
            state.basalRateMismatchDetectedAt = now
            notifyDelegateStateUpdated()
            updatePumpBasalProfile()
            return
        }

        // Also once failed: a retry that verified the profile sets the flag again even though the
        // rate in force still differs.
        if now.timeIntervalSince(detectedAt) >= Self.basalProfileUpdateTimeout,
           !state.basalProfileUpdateFailed || state.hasSyncedBasalRateSchedule
        {
            if !state.basalProfileUpdateFailed {
                logger.error("Could not update the pump's basal profile to match the schedule; refusing temp basals")
            }
            state.basalProfileUpdateFailed = true
            state.hasSyncedBasalRateSchedule = false
            notifyDelegateStateUpdated()
        }

        updatePumpBasalProfile()
    }
}

extension TandemPumpManager {
    static let pumpClockSkewAlertIdentifier = "pump-clock-skew"
    static let skewCompensationDuration: TimeInterval = .minutes(30)

    func reconcilePumpClockSkewAlert() {
        let skewed = state.isPumpClockSkewed
        guard skewed != state.pumpClockSkewAlertIssued else { return }

        let minutes = max(1, Int((abs(state.pumpClockOffset) / 60).rounded()))
        let identifier = LoopKit.Alert.Identifier(
            managerIdentifier: TandemPumpManager.managerIdentifier,
            alertIdentifier: Self.pumpClockSkewAlertIdentifier
        )
        pumpDelegate.notify { delegate in
            guard let delegate, skewed != self.state.pumpClockSkewAlertIssued else { return }

            if skewed {
                let content = LoopKit.Alert.Content(
                    title: String(localized: "Pump Time Is Off", comment: "Title of the alert that the pump's clock differs from the phone's"),
                    body: String(
                        format: String(
                            localized: "Your pump's clock is %d minutes different from your phone's, which affects temporary basal rates. Open the pump's settings in the app to sync its time.",
                            comment: "Body of the alert that the pump's clock differs from the phone's (minutes)"
                        ),
                        minutes
                    ),
                    acknowledgeActionButtonLabel: String(localized: "OK", comment: "Acknowledges the pump time alert")
                )
                self.logger.warning("Pump clock is \(minutes) min off the phone's; issuing an alert")
                delegate.issueAlert(LoopKit.Alert(
                    identifier: identifier,
                    foregroundContent: content,
                    backgroundContent: content,
                    trigger: .immediate,
                    interruptionLevel: .timeSensitive
                ))
            } else {
                self.logger.info("Pump clock agrees with the phone's again; retracting the alert")
                delegate.retractAlert(identifier: identifier)
            }
            self.state.pumpClockSkewAlertIssued = skewed
            self.notifyDelegateStateUpdated()
        }
    }

    /// While the pump's clock is skewed its segments sit apart from the host's, and the host counts
    /// its own scheduled rate whenever no temp runs. So wherever it would, the pump runs a temp at
    /// the percent of its own rate that delivers the host's.
    func maintainPumpClockSkewCompensation(_ status: CurrentBasalStatusResponse) {
        if status.basalType != .tempBasal {
            skewCompensationTemp = nil
        }

        let wanted: Int? = {
            guard state.isPumpClockSkewed, !state.useControlIQ, state.hasSyncedBasalRateSchedule,
                  state.basalDose.type == .basal, state.deliveryTransitions.pending == nil,
                  status.basalType != .suspend, status.profileBasalRate > 0,
                  bolusProgressReport?.isUnfinalized() != true
            else {
                return nil
            }
            let percent = tempBasalPercentAndRate(
                requestedRate: getScheduledBasalRate(),
                baseline: status.profileBasalRate
            ).percent
            return percent == 100 ? nil : percent
        }()

        if let running = skewCompensationTemp {
            if running.percent == wanted, running.endsAt.timeIntervalSince(now) > .minutes(10) {
                return
            }
            guard let stop = bluetooth.write(StopTempRateRequest()), stop.isStatusOK else {
                logger.error("Could not stop the pump clock skew temp")
                return
            }
            skewCompensationTemp = nil
        } else if status.basalType == .tempBasal {
            return
        }

        guard let wanted else { return }
        guard let response = bluetooth.write(SetTempRateRequest(minutes: Int(Self.skewCompensationDuration.minutes), percent: wanted)),
              response.isStatusOK
        else {
            logger.error("Could not set the pump clock skew temp at \(wanted)%")
            return
        }
        skewCompensationTemp = (wanted, now.addingTimeInterval(Self.skewCompensationDuration))
        logger.info("Pump clock is skewed; running \(wanted)% of the pump's \(status.profileBasalRate) U/hr to deliver the host's \(self.getScheduledBasalRate()) U/hr")

        if let readback = bluetooth.write(CurrentBasalStatusRequest()),
           !Self.tempBasalReadbackMatches(readback, percent: wanted)
        {
            logger.error("Pump reads back \(readback.currentBasalRate) U/hr for the clock skew temp; stopping it")
            if bluetooth.write(StopTempRateRequest())?.isStatusOK == true {
                skewCompensationTemp = nil
            }
        }
    }
}
