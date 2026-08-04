import Foundation
import LoopKit

extension TandemPumpManager {
    func fetchTimeSinceReset() {
        guard let response = bluetooth.write(
            message: TimeSinceResetRequest(),
            expecting: TimeSinceResetResponse.self
        ) as? TimeSinceResetResponse else {
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
        let (request, expecting) = ControlIQInfoRequestBuilder.create(apiVersion: state.pumpState.apiVersion)
        guard let response = bluetooth.write(message: request, expecting: expecting) as? ControlIQInfoAbstractResponse else {
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

    func fetchPumpInformation() {
        guard let apiResponse = bluetooth.write(
            message: ApiVersionRequest(),
            expecting: ApiVersionResponse.self
        ) as? ApiVersionResponse else {
            logger.error("Failed to fetch apiVersion")
            return
        }

        state.pumpState.apiVersion = apiResponse.getApiVersion()

        guard let pumpVersionResponse = bluetooth.write(
            message: PumpVersionBRequest(),
            expecting: PumpVersionBResponse.self
        ) as? PumpVersionBResponse else {
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

            guard let response = self.bluetooth.write(
                message: CurrentBasalStatusRequest(),
                expecting: CurrentBasalStatusResponse.self
            ) as? CurrentBasalStatusResponse else {
                self.logger.error("Failed to fetch basal Status for suspend: \(type(of: HomeScreenMirrorRequest.self))")
                completion(nil)
                return
            }

            completion(response.basalType == .suspend)
        }
    }

    func fetchBasalStatus() {
        guard let response = bluetooth.write(
            message: CurrentBasalStatusRequest(),
            expecting: CurrentBasalStatusResponse.self
        ) as? CurrentBasalStatusResponse else {
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

        guard let response = bluetooth.write(
            message: CurrentBolusStatusRequest(),
            expecting: CurrentBolusStatusResponse.self
        ) as? CurrentBolusStatusResponse else {
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

            // Query the pump for actual delivered volume rather than assuming full delivery
            var actualDelivered: Double?
            if let bolusId = state.bolusDose?.bolusId {
                actualDelivered = queryLastBolusDeliveredVolume(bolusId: bolusId)
            }

            var events = getActivePumpEvents()
            events.append(progressReport.getPumpEvent(actualDeliveredUnits: actualDelivered))

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
        for request in NotificationBundle.allRequests() {
            guard let expecting = expectedNotificationResponseType(for: request) else {
                logger.error("No response type mapping for \(type(of: request))")
                continue
            }
            guard let response = bluetooth.write(message: request, expecting: expecting) else {
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
    }

    /// Resolves the concrete response type expected on the wire for a notification status request.
    /// Most pairings follow the `Request`/`Response` naming convention resolved by
    /// `MessageRegistry`; `MalfunctionStatusRequest` is the exception, since its response is
    /// `MalfunctionBitmaskStatusResponse`.
    private func expectedNotificationResponseType(for request: Message) -> Message.Type? {
        if request is MalfunctionStatusRequest {
            return MalfunctionBitmaskStatusResponse.self
        }
        return MessageRegistry.responseMetadata(for: request)?.type
    }

    func fetchDeliveryLimits() {
        guard let basalResponse = bluetooth.write(
            message: BasalLimitSettingsRequest(),
            expecting: BasalLimitSettingsResponse.self
        ) as? BasalLimitSettingsResponse else {
            logger.error("Failed to fetch basal limits: \(type(of: BasalLimitSettingsRequest.self))")
            return
        }

        guard let bolusResponse = bluetooth.write(
            message: GlobalMaxBolusSettingsRequest(),
            expecting: GlobalMaxBolusSettingsResponse.self
        ) as? GlobalMaxBolusSettingsResponse else {
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
        guard let response = bluetooth.write(
            message: PumpGlobalsRequest(),
            expecting: PumpGlobalsResponse.self
        ) as? PumpGlobalsResponse else {
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

    /// Reads the cartridge volume, connecting first if needed. Yields nil if the pump didn't answer.
    func fetchInsulinRemaining(completion: @escaping (Double?) -> Void) {
        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for reservoir status: \(error.localizedDescription)")
                completion(nil)
                return
            }

            completion(self.fetchReservoirStatus())
        }
    }

    /// MUST be called on the command queue. Returns the units remaining, or nil on failure.
    @discardableResult
    func fetchReservoirStatus() -> Double? {
        guard let response = bluetooth.write(
            message: InsulinStatusRequest(),
            expecting: InsulinStatusResponse.self
        ) as? InsulinStatusResponse else {
            logger.error("Failed to fetch reservoir status: \(type(of: InsulinStatusRequest.self))")
            return nil
        }

        let timestamp = Date.now
        let units = Double(response.currentInsulinAmount)
        let reservoirValue = SimpleReservoirValue(startDate: timestamp, unitVolume: units)

        logger.debug("Reservoir updated: \(String(format: "%.2f", units)) U remaining")

        state.lastReconciliation = timestamp
        state.lastReservoirReading = reservoirValue
        notifyDelegateStateUpdated()

        pumpDelegate.notify { delegate in
            guard let delegate = delegate else {
                self.logger.warning("No pump delegate, not notifying...")
                return
            }

            delegate.pumpManager(
                self,
                didReadReservoirValue: units,
                at: timestamp,
                completion: { _ in }
            )
        }

        return units
    }

    func fetchBatteryStatus() {
        let (request, expecting) = CurrentBatteryRequestBuilder.create(apiVersion: state.pumpState.apiVersion)
        guard let response = bluetooth.write(message: request, expecting: expecting) as? CurrentBatteryAbstractResponse else {
            logger.error("Failed to fetch Battery status: \(type(of: request))")
            return
        }

        logger.debug("Battery updated: \(response.batteryPercent)% remaining")

        state.lastBatteryReading = TandemPumpManagerState.BatteryReading(
            date: Date.now,
            chargeRemaining: Double(response.batteryPercent) / 100.0
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

    /// Queries the pump for the actual delivered volume of the last bolus.
    /// Used after both cancellation and natural completion to get the real delivered amount.
    /// Returns the delivered volume in units, or nil if the query fails or the bolus ID doesn't match.
    func queryLastBolusDeliveredVolume(bolusId: Int) -> Double? {
        let (request, expecting) = LastBolusRequestBuilder.create(apiVersion: state.pumpState.apiVersion)

        guard let response = bluetooth.write(
            message: request,
            expecting: expecting
        ) as? LastBolusStatusAbstractResponse else {
            logger.error("Failed to get lastBolusStatus: \(type(of: request))")
            return nil
        }

        guard response.bolusId == bolusId else {
            logger.warning("LastBolusStatus bolusId \(response.bolusId) != expected \(bolusId)")
            return nil
        }

        return roundToSupportedBolusVolume(units: Double(response.deliveredVolume) / 1000.0)
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
            guard let response = bluetooth.write(
                message: DismissNotificationRequest(
                    notificationType: .alert,
                    notificationId: UInt32(alert.rawValue)
                ),
                expecting: DismissNotificationResponse.self
            ) as? DismissNotificationResponse else {
                logger.error("Failed to send DismissNotificationRequest")
                return
            }

            if response.status != 0 {
                logger.warning("[auto-ack] Failed to acknowledge \(alert): status=\(response.status)")
            }
        }
    }
}
