import Foundation
import LoopKit

extension TandemPumpManager {
    func fetchTimeSinceReset() {
        do {
//            let response: TimeSinceResetResponse = try pumpComm.sendMessage(
//                transport: transport,
//                message: TimeSinceResetRequest(),
//                expecting: TimeSinceResetResponse.self
//            )
//
//            handleTimeSinceResetResponse(response, source: .telemetry)
        } catch {
            logger.error("TimeSinceReset telemetry request failed: \(error)")
        }
    }

    func fetchControlIQStatus() {
        do {
//            let response: ControlIQInfoV2Response = try pumpComm.sendMessage(
//                transport: transport,
//                message: ControlIQInfoV2Request(),
//                expecting: ControlIQInfoV2Response.self
//            )
//
//            handleControlIQResponse(response, source: .telemetry)
        } catch {
            logger.error("ControlIQ status telemetry request failed: \(error)")
        }
    }

    func fetchHomeScreenStatus() {
        do {
//            let response: HomeScreenMirrorResponse = try pumpComm.sendMessage(
//                transport: transport,
//                message: HomeScreenMirrorRequest(),
//                expecting: HomeScreenMirrorResponse.self
//            )
//
//            handleHomeScreenMirrorResponse(response, source: .telemetry)
        } catch {
            logger.error("HomeScreen telemetry request failed: \(error)")
        }
    }

    func fetchBolusStatus() {
        do {
//            let response: CurrentBolusStatusResponse = try pumpComm.sendMessage(
//                transport: transport,
//                message: CurrentBolusStatusRequest(),
//                expecting: CurrentBolusStatusResponse.self
//            )
//
//            handleBolusResponse(response, source: .telemetry)
        } catch {
            logger.error("Bolus telemetry request failed: \(error)")
        }
    }

    func fetchNotificationCount() {
        do {
//            let bundle = NotificationBundle()
//            for request in NotificationBundle.allRequests() {
//                if let response = try? self.pumpComm.sendMessage(transport: transport, message: request),
//                   NotificationBundle.isNotificationResponse(response)
//                {
//                    bundle.add(response)
//                }
//            }
//
//            updateNotificationBundle(bundle)
        } catch {
            logger.error("fetchNotificationCount failed: \(error)")
        }
    }

    func fetchDeliveryLimits() {
        do {
//            let basalResponse: BasalLimitSettingsResponse = try pumpComm.sendMessage(
//                transport: transport,
//                message: BasalLimitSettingsRequest(),
//                expecting: BasalLimitSettingsResponse.self
//            )
//
//            let bolusResponse: GlobalMaxBolusSettingsResponse = try pumpComm.sendMessage(
//                transport: transport,
//                message: GlobalMaxBolusSettingsRequest(),
//                expecting: GlobalMaxBolusSettingsResponse.self
//            )
//
//            state.maxBasalLimitMilliunits = Int(basalResponse.basalLimit)
//            state.maxBasalLimitDefaultMilliunits = Int(basalResponse.basalLimitDefault)
//            state.maxBolusLimitMilliunits = bolusResponse.maxBolus
//            state.maxBolusLimitDefaultMilliunits = bolusResponse.maxBolusDefault
//            notifyDelegateStateUpdated()
        } catch {
            logger.error("Failed to fetch delivery limits: \(error.localizedDescription)")
        }
    }

    func fetchGlobalPumpSettings() {
        do {
//            let response: PumpGlobalsResponse = try pumpComm.sendMessage(
//                transport: transport,
//                message: PumpGlobalsRequest(),
//                expecting: PumpGlobalsResponse.self
//            )
//
//            handleGlobalPumpSettingsResponse(response, source: .telemetry)
        } catch {
            logger.error("Pump global telemetry request failed: \(error)")
        }
    }

    func fetchReservoirStatus() {
        do {
//            let response = try pumpComm.sendMessage(
//                transport: transport,
//                message: InsulinStatusRequest(),
//                expecting: InsulinStatusResponse.self
//            )
//
//            handleReservoirResponse(response, source: .telemetry)
        } catch {
            logger.error("Reservoir telemetry request failed: \(error)")
        }
    }

    func fetchBatteryStatus() {
        do {
//            let request = CurrentBatteryRequestBuilder.create(apiVersion: PumpStateSupplier.pumpApiVersion)
//            if let v2Request = request as? CurrentBatteryV2Request {
//                let response: CurrentBatteryV2Response = try pumpComm.sendMessage(
//                    transport: transport,
//                    message: v2Request,
//                    expecting: CurrentBatteryV2Response.self
//                )
//
//                handleBatteryResponse(response, source: .telemetry)
//            } else if let v1Request = request as? CurrentBatteryV1Request {
//                let response: CurrentBatteryV1Response = try pumpComm.sendMessage(
//                    transport: transport,
//                    message: v1Request,
//                    expecting: CurrentBatteryV1Response.self
//                )
//
//                handleBatteryResponse(response, source: .telemetry)
//            } else {
//                logger
//                    .error(
//                        "Battery telemetry request builder returned unsupported type: \(String(describing: type(of: request)))"
//                    )
//            }
        } catch {
            logger.error("Battery telemetry request failed: \(error)")
        }
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

    func handleControlIQResponse(_ response: ControlIQInfoV2Response, source: ResponseSource) {
        logger.debug(
            "[\(source.label)] ControlIQ updated: enabled=\(response.closedLoopEnabled), mode=\(response.currentUserModeTypeRaw)"
        )

        state.controlIQEnabled = response.closedLoopEnabled

        // If the pump reports ControlIQ is enabled (e.g., turned on via pump screen),
        // sync useControlIQ so dosing guards activate and Trio disables closed loop
        if response.closedLoopEnabled, !state.useControlIQ {
            logger.warning("[handleControlIQResponse] Pump has ControlIQ enabled but useControlIQ was false -- syncing")
            state.useControlIQ = true
        }

        if let userMode = response.currentUserModeType {
            state.controlIQUserMode = TandemPumpManagerState.ControlIQUserMode.fromUserModeType(userMode)
        } else {
            state.controlIQUserMode = nil
        }

        state.controlIQWeight = response.weight
        state.controlIQTotalDailyInsulin = response.totalDailyInsulin
        state.lastControlIQUpdate = Date.now

        notifyDelegateStateUpdated()
    }

    func handleTimeSinceResetResponse(_ response: TimeSinceResetResponse, source: ResponseSource) {
        let timeSinceReset = response.pumpTimeSinceReset
        let currentPumpTime = response.currentTimeDate
        let checkedAt = Date.now

        logger.debug("[\(source.label)] TimeSinceReset updated: \(timeSinceReset)")

        state.pumpState.timeSinceReset = timeSinceReset
        state.currentPumpTime = currentPumpTime
        state.lastPumpTimeCheckDate = checkedAt
//            pumpComm.syncPumpState(pumpState)
        needsSessionInitialization.value = false

        // Update the PumpStateSupplier with the new value
//            updatePairingArtifacts(with: pumpState)

        notifyDelegateStateUpdated()
    }

    func handleGlobalPumpSettingsResponse(_ response: PumpGlobalsResponse, source: ResponseSource) {
        logger.debug("[\(source.label)] Pump Global updated -> \(response.description)")

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

    func handleBolusResponse(_ response: CurrentBolusStatusResponse, source: ResponseSource) {
        logger.debug(
            "[\(source.label)] Bolus updated - status: \(String(describing: response.status)) id: \(response.bolusId)"
        )

        // Normal CurrentBolusStatus fetch
        if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil {
            return
        }

        guard let progressReport = bolusProgressReport else {
            return
        }

        if response.status == .delivering {
//            if state.bolusState == .initiating, let activeBolus = activeBolus.value {
//                state.bolusState = .inProgress(activeBolus.dose.toDoseEntry())
//                notifyDelegateStateUpdated()
//            }

            progressReport.notify()
            return
        }

        if response.bolusId == 0, progressReport.bolusStatedOn != nil {
            // Bolus is finished
            telemetryScheduler.cancelAll()

            // Query the pump for actual delivered volume rather than assuming full delivery
            var actualDelivered: Double?
//            if let bolusId = activeBolus.value?.id, let transport = transportLock.value {
//                actualDelivered = queryLastBolusDeliveredVolume(transport: transport, bolusId: bolusId)
//            }

            var events = getActivePumpEvents()
            events.append(progressReport.getPumpEvent(actualDeliveredUnits: actualDelivered))

            bolusProgressReport = nil
//            activeBolus.value = nil

            state.lastReconciliation = Date.now
            notifyDelegateStateUpdated()
            emitPumpEvents(events)
        }
    }

    func handleBatteryResponse(_ response: CurrentBatteryAbstractResponse, source: ResponseSource) {
        let percent = Double(response.batteryPercent) / 100.0
        let timestamp = Date.now

        logger.debug("[\(source.label)] Battery updated: \(percent * 100)% remaining")

        state.lastBatteryReading = TandemPumpManagerState.BatteryReading(date: timestamp, chargeRemaining: percent)
        notifyDelegateStateUpdated()
    }

    func handleReservoirResponse(_ response: InsulinStatusResponse, source: ResponseSource) {
        let units = Double(response.currentInsulinAmount)
        logger.debug("[\(source.label)] Reservoir updated: \(String(format: "%.2f", units)) U remaining")

        let timestamp = Date.now
        let reservoirValue = SimpleReservoirValue(startDate: timestamp, unitVolume: units)

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
