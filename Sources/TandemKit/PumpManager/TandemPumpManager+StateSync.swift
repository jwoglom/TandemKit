import Foundation
import LoopKit

extension TandemPumpManager {
    func fetchTimeSinceReset() {
        guard let response = bluetooth.write(TimeSinceResetRequest()) else {
            logger.error("Failed to fetch ControlIQ info: \(type(of: TimeSinceResetRequest.self))")
            return
        }

        let timeSinceReset = response.pumpTimeSinceReset
        let currentPumpTime = response.currentTimeDate
        let checkedAt = Date.now

        state.pumpState.timeSinceReset = timeSinceReset
        state.currentPumpTime = currentPumpTime
        state.lastPumpTimeCheckDate = checkedAt

        notifyDelegateStateUpdated()
    }

    func fetchControlIQStatus() {
        let request = ControlIQInfoRequestBuilder.create(apiVersion: state.pumpState.apiVersion)
        guard let response = bluetooth.write(request) as? ControlIQInfoAbstractResponse else {
            logger.error("Failed to fetch ControlIQ info: \(type(of: request))")
            return
        }

        state.controlIQEnabled = response.getClosedLoopEnabled()

        // If the pump reports ControlIQ is enabled (e.g., turned on via pump screen),
        // sync useControlIQ so dosing guards activate and Trio disables closed loop
        if response.getClosedLoopEnabled(), !state.useControlIQ {
            logger.warning("[handleControlIQResponse] Pump has ControlIQ enabled but useControlIQ was false -- syncing")
            state.useControlIQ = true
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
        state.lastControlIQUpdate = Date.now

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
        state.lastCGMStatusUpdate = Date.now

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
                self.logger.error("Failed to fetch basal Status for suspend: \(type(of: HomeScreenMirrorRequest.self))")
                completion(nil)
                return
            }

            completion(response.basalType == .suspend)
        }
    }

    func fetchBasalStatus() {
        guard let response = bluetooth.write(CurrentBasalStatusRequest()) else {
            logger.error("Failed to fetch basal Status: \(type(of: HomeScreenMirrorRequest.self))")
            return
        }

        let activeBasalType = response.basalType
        if activeBasalType != state.basalDose.type {
            if activeBasalType == .basal, state.basalDose.type == .resume {
                // This is also the same
                return
            }

            logger.debug("Updating new basal dose: \(activeBasalType)")
            let now = Date.now
            var events = getActivePumpEvents(endDate: now)

            if activeBasalType == .suspend {
                let dose = UnfinalizedDose(suspendStartTime: now)
                events.append(NewPumpEvent.suspend(
                    dose: dose.toDoseEntry(),
                    date: dose.startDate
                ))

                state.basalDose = dose
                state.lastReconciliation = Date.now

                emitPumpEvents(events)
                notifyDelegateStateUpdated()
                return
            }

            if activeBasalType == .basal {
                if !events.contains(where: { $0.type == .basal }) {
                    let dose = UnfinalizedDose(
                        basalRate: getScheduledBasalRate(),
                        insulinType: state.insulinType,
                        startDate: now
                    )
                    events.append(NewPumpEvent.basal(
                        dose: dose.toDoseEntry(),
                        date: dose.startDate
                    ))

                    state.basalDose = dose
                }

                state.lastReconciliation = Date.now

                emitPumpEvents(events)
                notifyDelegateStateUpdated()
                return
            }
        }
    }

    static let bolusSyncReconcileGrace: TimeInterval = .seconds(30)

    /// Defer to event-driven bolus tracking only while the bolus should still be delivering —
    /// a bolusChange event lost to a disconnect is never replayed, so sync must reconcile if past the grace time.
    func shouldDeferBolusSync(at date: Date = .now) -> Bool {
        guard let bolusDose = state.bolusDose else {
            return false
        }
        return date < bolusDose.estimatedEndDate.addingTimeInterval(Self.bolusSyncReconcileGrace)
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

        // Normal CurrentBolusStatus fetch
        if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil {
            if state.bolusState != .noBolus || state.bolusDose != nil {
                state.bolusDose = nil
                state.bolusState = .noBolus
                notifyDelegateStateUpdated()
            }
            return
        }

        guard let progressReport = bolusProgressReport else {
            return
        }

        if response.status == .delivering {
            if let dose = state.bolusDose {
                // The pump's own start of delivery, which runs ~15s behind when we programmed the
                // bolus, is what the reported dose starts at (#339).
                dose.recordDeliveryStart(response.timestampDate)

                // Recalculate endDate of the bolus
                dose.estimatedEndDate = Date.now.addingTimeInterval(estimatedDuration(toBolus: dose.value))

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

        if response.bolusId == 0 {
            // Bolus is finished
            telemetryScheduler.cancelAll()

            // Query the pump for actual delivered volume rather than assuming full delivery,
            // and for its own timestamp rather than dating the bolus at this detection (#339).
            var lastBolus: LastBolusReport?
            if let bolusId = state.bolusDose?.bolusId {
                lastBolus = queryLastBolusReport(bolusId: bolusId)
            }

            var events = getActivePumpEvents()
            events.append(progressReport.getPumpEvent(
                actualDeliveredUnits: lastBolus?.deliveredUnits,
                pumpTimestamp: lastBolus?.pumpTimestamp,
                deliveryStartDate: state.bolusDose?.deliveryStartDate
            ))

            bolusProgressReport = nil
            state.bolusDose = nil
            state.bolusState = .noBolus
            state.lastReconciliation = Date.now
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
        state.lastNotificationUpdate = Date.now
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

    func fetchGlobalPumpSettings() {
        guard let response = bluetooth.write(PumpGlobalsRequest()) else {
            logger.error("Failed to fetch global pump settings: \(type(of: PumpGlobalsRequest.self))")
            return
        }

        state.quickBolusAnnun = response.quickBolusAnnouncement
        state.reminderAnnun = response.reminderAnnouncement
        state.alarmAnnun = response.alarmAnnouncement
        state.alertAnnun = response.alertAnnouncement
        state.generalAnnun = response.generalAnnouncement
        state.quickBolusEnabled = response.isQuickBolusEnabled()
        state.quickBolusEntryType = response.quickBolusEntryType
        state.quickBolusIncrementUnits = response.quickBolusIncrementUnits
        state.quickBolusIncrementCarbs = response.quickBolusIncrementCarbs
        state.quickBolusStatus = response.quickBolusStatus
        notifyDelegateStateUpdated()
    }

    /// Turns the pump's quick bolus button off when `quickBolusButtonSupport` is off and the pump
    /// reports it enabled. Reads `state.quickBolusEnabled`, so it needs a `fetchGlobalPumpSettings`
    /// earlier in the same sync.
    func enforceQuickBolusDisabled() {
        guard !state.featureFlags.quickBolusButtonSupport, state.quickBolusEnabled == true else {
            return
        }

        logger.warning("Quick bolus button is enabled on the pump; disabling it")

        guard let response = bluetooth.write(SetQuickBolusSettingsRequest(enabled: false, mode: .units, increment: .disabled)) else {
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

        let timestamp = Date.now
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
            date: Date.now,
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
            let now = Date.now
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

    /// How long the pump is given to report the delivered volume of a cancelled bolus before the
    /// driver settles for its own estimate. Several sync cycles: the read normally succeeds on the
    /// first retry, and every cycle the dose stays mutable is a cycle the host counts the full
    /// programmed amount.
    static let cancelledBolusFinalizationWindow: TimeInterval = .minutes(15)

    /// Retries the delivered-volume read for a bolus that was cancelled while the pump was
    /// unreachable, and finalizes the dose once it answers.
    ///
    /// `cancelBolus` leaves the dose mutable rather than finalizing it at a guessed 0 U (#328).
    /// This is what eventually closes it out: the pump's own number when it arrives, and after
    /// `cancelledBolusFinalizationWindow` the progress reporter's estimate from the moment of the
    /// cancel — never a value the driver knows to be a placeholder.
    func finalizePendingCancelledBolus(now: Date = .now) {
        guard let pending = state.pendingCancelledBolus, let bolusId = pending.bolusId else {
            return
        }

        // Not while another bolus is being tracked: `LastBolusStatus` reports whatever the pump
        // stored last, and reading it mid-bolus risks matching a later bolus that happens to carry
        // the same id. The window below still closes the dose out.
        let lastBolus = state.bolusDose == nil ? queryLastBolusReport(bolusId: bolusId) : nil
        if let lastBolus {
            pending.deliveredUnits = lastBolus.deliveredUnits
        } else if now.timeIntervalSince(pending.estimatedEndDate) < Self.cancelledBolusFinalizationWindow {
            logger.warning("Pump still has no delivered volume for cancelled bolus \(bolusId); leaving it mutable")
            return
        } else {
            // Out of retries. `deliveredUnits` still holds the estimate recorded at the cancel,
            // which is what the dose is finalized with.
            logger.error(
                "Giving up on the pump's delivered volume for cancelled bolus \(bolusId); finalizing with the estimate \(pending.deliveredUnits)U"
            )
        }

        let finalizedDose = pending.toDoseEntry(endDate: BolusEndDate.resolve(
            startDate: pending.startDate,
            deliveryStartDate: pending.deliveryStartDate,
            deliveredUnits: pending.deliveredUnits,
            pumpTimestamp: lastBolus?.pumpTimestamp,
            detectedAt: now
        ))

        state.pendingCancelledBolus = nil

        var events = getActivePumpEvents()
        events.append(NewPumpEvent.bolus(
            dose: finalizedDose,
            units: finalizedDose.deliveredUnits ?? 0,
            date: pending.startDate
        ))

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
