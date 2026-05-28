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

        logger.debug("TimeSinceReset updated: \(timeSinceReset)")

        state.pumpState.timeSinceReset = timeSinceReset
        state.currentPumpTime = currentPumpTime
        state.lastPumpTimeCheckDate = checkedAt
        needsSessionInitialization.value = false

        notifyDelegateStateUpdated()
    }

    func fetchControlIQStatus() {
        let (request, expecting) = ControlIQInfoRequestBuilder.create(apiVersion: state.pumpState.apiVersion)
        guard let response = bluetooth.write(message: request, expecting: expecting) as? ControlIQInfoAbstractResponse else {
            logger.error("Failed to fetch ControlIQ info: \(type(of: request))")
            return
        }

        logger.debug(
            " ControlIQ updated: enabled=\(response.getClosedLoopEnabled()), mode=\(response.getCurrentUserModeTypeId())"
        )

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

        state.controlIQWeight = response.getWeight()
        state.controlIQTotalDailyInsulin = response.getTotalDailyInsulin()
        state.lastControlIQUpdate = Date.now

        notifyDelegateStateUpdated()
    }

    func fetchHomeScreenStatus() {
        guard let response = bluetooth.write(
            message: HomeScreenMirrorRequest(),
            expecting: HomeScreenMirrorResponse.self
        ) as? HomeScreenMirrorResponse else {
            logger.error("Failed to fetch homeScreen Status: \(type(of: HomeScreenMirrorRequest.self))")
            return
        }
    }

    func fetchBolusStatus() {
        guard let response = bluetooth.write(
            message: CurrentBolusStatusRequest(),
            expecting: CurrentBolusStatusResponse.self
        ) as? CurrentBolusStatusResponse else {
            logger.error("Failed to fetch bolus status: \(type(of: CurrentBolusStatusRequest.self))")
            return
        }

        logger.debug(
            "Bolus updated - status: \(String(describing: response.status)) id: \(response.bolusId)"
        )

        // Normal CurrentBolusStatus fetch
//        if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil {
//            return
//        }
//
//        guard let progressReport = bolusProgressReport else {
//            return
//        }
//
//        if response.status == .delivering {
        ////            if state.bolusState == .initiating, let activeBolus = activeBolus.value {
        ////                state.bolusState = .inProgress(activeBolus.dose.toDoseEntry())
        ////                notifyDelegateStateUpdated()
        ////            }
//
//            progressReport.notify()
//            return
//        }
//
//        if response.bolusId == 0, progressReport.bolusStatedOn != nil {
//            // Bolus is finished
//            telemetryScheduler.cancelAll()
//
//            // Query the pump for actual delivered volume rather than assuming full delivery
//            var actualDelivered: Double?
        ////            if let bolusId = activeBolus.value?.id, let transport = transportLock.value {
        ////                actualDelivered = queryLastBolusDeliveredVolume(transport: transport, bolusId: bolusId)
        ////            }
//
//            var events = getActivePumpEvents()
//            events.append(progressReport.getPumpEvent(actualDeliveredUnits: actualDelivered))
//
//            bolusProgressReport = nil
        ////            activeBolus.value = nil
//
//            state.lastReconciliation = Date.now
//            notifyDelegateStateUpdated()
//            emitPumpEvents(events)
//        }
    }

    func fetchNotificationCount() {
        let bundle = NotificationBundle()
        for (request, expecting) in NotificationBundle.allRequests() {
            guard let response = bluetooth.write(message: request, expecting: expecting) else {
                logger.error("Failed to fetch notification status of \(type(of: request))")
                continue
            }

            bundle.add(response)
        }

        state.notificationCount = bundle.getNotificationCount()
        state.lastNotificationUpdate = Date.now
        notifyDelegateStateUpdated()
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

    func fetchReservoirStatus() {
        guard let response = bluetooth.write(
            message: InsulinStatusRequest(),
            expecting: InsulinStatusResponse.self
        ) as? InsulinStatusResponse else {
            logger.error("Failed to fetch reservoir status: \(type(of: InsulinStatusRequest.self))")
            return
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
    }

    func fetchBatteryStatus() {
        let (request, expecting) = CurrentBatteryRequestBuilder.create(apiVersion: state.pumpState.apiVersion)
        guard let response = bluetooth.write(message: request, expecting: expecting) as? CurrentBatteryAbstractResponse else {
            logger.error("Failed to fetch Battery status: \(type(of: request))")
            return
        }

        let percent = Double(response.batteryPercent) / 100.0
        let timestamp = Date.now

        logger.debug("Battery updated: \(percent * 100)% remaining")

        state.lastBatteryReading = TandemPumpManagerState.BatteryReading(date: timestamp, chargeRemaining: percent)
        notifyDelegateStateUpdated()
    }

    func handleHomeScreenMirrorResponse(_ response: HomeScreenMirrorResponse, source _: ResponseSource) {
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
    func queryLastBolusDeliveredVolume(bolusId _: Int) -> Double? {
        do {
//            if PumpStateSupplier.pumpApiVersion.greaterThan(KnownApiVersion.apiV2_1.value) {
//                let response: LastBolusStatusV2Response = try pumpComm.sendMessage(
//                    transport: transport,
//                    message: LastBolusStatusV2Request(),
//                    expecting: LastBolusStatusV2Response.self
//                )
//                guard response.bolusId == bolusId else {
//                    logger
//                        .warning("[bolus] LastBolusStatusV2 bolusId \(response.bolusId) != expected \(bolusId)")
//                    return nil
//                }
//                let units = roundToSupportedBolusVolume(units: Double(response.deliveredVolume) / 1000.0)
//                logger
//                    .info("[bolus] Pump reported delivered volume: \(units)U (raw: \(response.deliveredVolume))")
//                return units == 0 ? nil : units
//            } else {
//                let response: LastBolusStatusResponse = try pumpComm.sendMessage(
//                    transport: transport,
//                    message: LastBolusStatusRequest(),
//                    expecting: LastBolusStatusResponse.self
//                )
//                guard response.bolusId == bolusId else {
//                    logger.warning("[bolus] LastBolusStatus bolusId \(response.bolusId) != expected \(bolusId)")
//                    return nil
//                }
//                let units = roundToSupportedBolusVolume(units: Double(response.deliveredVolume) / 1000.0)
//                logger.info("[bolus] Pump reported delivered volume: \(units)U (raw: \(response.deliveredVolume))")
//                return units == 0 ? nil : units
//            }
            return nil
        } catch {
            logger.error("[bolus] Failed to query last bolus status: \(error)")
            return nil
        }
    }
}
