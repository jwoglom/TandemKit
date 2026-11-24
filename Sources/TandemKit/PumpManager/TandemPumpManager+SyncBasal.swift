import LoopKit

public enum BasalScheduleSyncError: Error, Equatable {
    /// Refused before any write: the pump keeps a segment per entry, and a write sequence stopped
    /// at the pump's limit would leave it holding part of the new schedule (#443).
    case tooManyEntries(count: Int, maximum: Int)
    /// Refused before any write: segment 0, which the pump keeps at midnight, takes the first entry.
    case firstEntryNotAtMidnight
}

extension BasalScheduleSyncError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .tooManyEntries(count, maximum):
            return String(
                format: String(
                    localized: "This basal schedule has %1$@ rates, but the pump can hold at most %2$@.",
                    comment: "Error when a basal schedule has more entries than the pump's profile can hold"
                ),
                String(count),
                String(maximum)
            )
        case .firstEntryNotAtMidnight:
            return String(
                localized: "This basal schedule does not start at midnight, but the pump's first basal rate always does.",
                comment: "Error when a basal schedule's first entry is not at midnight"
            )
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case let .tooManyEntries(_, maximum):
            return String(
                format: String(
                    localized: "Edit your basal schedule down to %@ rates or fewer, then save it again.",
                    comment: "Recovery suggestion when a basal schedule has too many entries for the pump"
                ),
                String(maximum)
            )
        case .firstEntryNotAtMidnight:
            return String(
                localized: "Edit your basal schedule so its first rate starts at midnight, then save it again.",
                comment: "Recovery suggestion when a basal schedule's first entry is not at midnight"
            )
        }
    }
}

public extension TandemPumpManager {
    func syncBasalRateSchedule(
        items scheduleItems: [RepeatingScheduleValue<Double>],
        completion: @escaping (_ result: Result<BasalRateSchedule, Error>) -> Void
    ) {
        let completion = watchdogged(timeoutResult: .failure(PumpCommError.pumpNotConnected), completion)
        logger.info("Sync basal schedule...")
        if let error = basalScheduleSyncError(scheduleItems) {
            completion(.failure(error))
            return
        }

        let sortedItems = scheduleItems.sorted { $0.startTime < $1.startTime }

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for syncBasal: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            let result = self.writeBasalRateSchedule(sortedItems)
            if case .success = result {
                self.markBasalProfileValidated()
            }
            completion(result)
        }
    }
}

extension TandemPumpManager {
    /// Refusals that need no pump: each would fail partway through the writes.
    func basalScheduleSyncError(_ scheduleItems: [RepeatingScheduleValue<Double>]) -> Error? {
        guard !scheduleItems.isEmpty else {
            logger.error("Basal schedule is empty")
            return PumpManagerError.configuration(nil)
        }

        guard scheduleItems.count <= maximumBasalScheduleEntryCount else {
            logger.error(
                "Basal schedule has \(scheduleItems.count) entries; the pump holds at most \(self.maximumBasalScheduleEntryCount)"
            )
            return BasalScheduleSyncError.tooManyEntries(count: scheduleItems.count, maximum: maximumBasalScheduleEntryCount)
        }

        let first = scheduleItems.map(\.startTime).min()!
        guard Int((first / 60).rounded()) == 0 else {
            logger.error("Basal schedule starts at \(first)s, not midnight")
            return BasalScheduleSyncError.firstEntryNotAtMidnight
        }

        return nil
    }

    /// Writes `sortedItems` over the pump's active profile and reads it back. Must run inside an
    /// `ensureConnected` job.
    func writeBasalRateSchedule(
        _ sortedItems: [RepeatingScheduleValue<Double>]
    ) -> Result<BasalRateSchedule, Error> {
        do {
            guard var idpManager = self.loadIDPProfiles() else {
                self.logger.error("Invalid IDPManager state in syncBasalRateSchedule")
                throw PumpCommError.requestConstructionFailed(reason: "Invalid IDPManager state in syncBasalRateSchedule")
            }

            if idpManager.getProfiles().isEmpty == true {
                self.logger.info("No profiles in IDPManager, creating initial profile for Trio")
                // The host gives a pump manager no carb ratio, sensitivity or target, so these bias the
                // pump's own bolus calculator and Control-IQ's corrections toward less insulin.
                let message = idpManager.createNewProfileMessage(
                    profileName: "TandemKitProfile",
                    defaultCarbRatio: 30000, // 30 g/U, in the pump's milligrams per unit
                    defaultBasalRateUnits: sortedItems.first?.value ?? 0,
                    defaultTargetBG: 140, // mg/dL
                    defaultISF: 100, // mg/dL per unit
                    defaultInsulinDurationMinutes: 300, // the 5 hours Control-IQ requires
                    profileCarbEntryEnabled: false
                )

                guard let newlyCreatedProfile = self.bluetooth.write(message) else {
                    self.logger.error("No active profile found and got unexpected response creating initial profile")
                    throw PumpCommError.requestConstructionFailed(
                        reason: "No active profile found and got unexpected response creating initial profile"
                    )
                }

                guard newlyCreatedProfile.isStatusOK else {
                    self.logger.error("No active profile found and got unexpected response creating initial profile")
                    throw PumpCommError.requestConstructionFailed(
                        reason: "No active profile found and got unexpected response creating initial profile"
                    )
                }

                self.logger
                    .info("Created initial IDP profile with ID \(String(describing: newlyCreatedProfile.newIdpId))")

                guard let reloaded = self.loadIDPProfiles() else {
                    self.logger.error("Invalid IDPManager state after creating initial profile")
                    throw PumpCommError.requestConstructionFailed(
                        reason: "Invalid IDPManager state after creating initial profile"
                    )
                }
                idpManager = reloaded
            }

            // Step 2: Get the active profile
            guard let activeProfile = idpManager.getActiveProfile() else {
                self.logger.error("No active profile found")
                throw PumpCommError.requestConstructionFailed(reason: "No active profile found")
            }

            // Step 3: Get current segments to preserve non-basal fields
            let currentSegments = activeProfile.getSegments()
            // Before the writes below, which modify these segments in place.
            let previousRate = self.profileRateInForce(currentSegments)

            // Step 4: Delete surplus segments, highest index first so the remaining indices hold.
            var requests: [SetIDPSegmentRequest] = []
            if sortedItems.count < currentSegments.count {
                for index in stride(from: currentSegments.count - 1, through: sortedItems.count, by: -1)
                    where index > 0 // segment 0 cannot be deleted
                {
                    requests.append(activeProfile.deleteSegmentMessage(segment: currentSegments[index]))
                }
            }

            let retainedSegments = Array(currentSegments.prefix(min(sortedItems.count, currentSegments.count)))

            // Step 5: Order the writes so no two segments ever share a start time. The pump
            // rejects such a write with status 1, so applying the schedule in index order fails
            // whenever a segment moves onto a start time the next segment still occupies.
            var pendingWrites = Self.pendingSegmentWrites(
                items: sortedItems,
                retainedSegments: retainedSegments
            )

            // Start time held by each segment, keyed by segment index. Segments created during
            // this sync take a synthetic negative key.
            var occupiedStartTimes: [Int: Int] = [:]
            for segment in retainedSegments {
                occupiedStartTimes[segment.segmentIndex] = segment.profileStartTime
            }
            var nextCreatedSegmentKey = -1

            while !pendingWrites.isEmpty {
                let applicable = pendingWrites.firstIndex { write in
                    !occupiedStartTimes.contains { segmentIndex, startTime in
                        startTime == write.startTime && segmentIndex != write.segment?.segmentIndex
                    }
                }

                guard let applicable else {
                    // Both start time sequences ascend, so a cycle of mutual blocks cannot form.
                    // Bail out rather than spin if the pump ever returns unordered segments.
                    self.logger.error("Could not order basal segment writes without a start time collision")
                    throw PumpCommError.requestConstructionFailed(
                        reason: "Could not order basal segment writes without a start time collision"
                    )
                }

                let write = pendingWrites.remove(at: applicable)

                if let segment = write.segment {
                    var changedFields: Set<IDPSegmentResponse.IDPSegmentStatus> = []
                    if segment.profileStartTime != write.startTime {
                        changedFields.insert(.START_TIME)
                    }
                    if segment.profileBasalRate != write.basalRate {
                        changedFields.insert(.BASAL_RATE)
                    }
                    segment.profileStartTime = write.startTime
                    segment.profileBasalRate = write.basalRate
                    requests.append(activeProfile.modifySegmentMessage(segment: segment, changedFields: changedFields))
                    occupiedStartTimes[segment.segmentIndex] = write.startTime
                } else {
                    requests.append(activeProfile.createSegmentMessage(
                        profileStartTime: write.startTime,
                        profileBasalRate: write.basalRate,
                        copyingSettingsOf: currentSegments.first!
                    ))
                    occupiedStartTimes[nextCreatedSegmentKey] = write.startTime
                    nextCreatedSegmentKey -= 1
                }
            }

            // Step 6: Send all modification requests
            for request in requests {
                guard let response = self.bluetooth.write(request) else {
                    self.logger.error("No response to SetIDPSegment for segment \(request.segmentIndex)")
                    throw PumpCommError.requestConstructionFailed(reason: "Pump rejected SetIDPSegment")
                }

                guard response.status == 0 else {
                    self.logger
                        .error(
                            "Pump rejected SetIDPSegment, status: \(response.status), operation: \(String(describing: request.operation)), segment: \(request.segmentIndex), startTime: \(request.profileStartTime)"
                        )
                    throw PumpCommError.errorResponse(
                        context: String(
                            localized: "Error syncing basal rates: Pump rejected SetIDPSegment",
                            comment: "Message when pump rejects SetIDPSegment"
                        ),
                        request: request,
                        response: response
                    )
                }
            }

            if let error = self.verifyProfileMatches(items: sortedItems) {
                throw error
            }

            let schedule = BasalRateSchedule(dailyItems: sortedItems, timeZone: self.state.scheduleTimeZone) ?? self.state.basalRateSchedule

            self.state.basalRateSchedule = schedule
            self.state.hasSyncedBasalRateSchedule = true
            self.state.settings.maxBasalScheduleEntry = sortedItems.map(\.value).max()
            self.notifyDelegateStateUpdated()

            self.restartBasalDoseAfterScheduleChange(previousRate: previousRate)

            return .success(schedule)
        } catch {
            return .failure(error)
        }
    }

    /// The pump's rate in force before a write. Its own profile, not the schedule: an update writes
    /// the schedule the driver already holds over a profile that differs from it.
    func profileRateInForce(_ segments: [IDPSegmentResponse]) -> Double {
        let minuteOfDay = Int(pumpBasalSchedule.secondsSinceMidnight(at: now) / 60)
        let sorted = segments.sorted { $0.profileStartTime < $1.profileStartTime }
        guard let segment = sorted.last(where: { $0.profileStartTime <= minuteOfDay }) ?? sorted.first else {
            return pumpScheduledBasalRate(at: now)
        }
        return Double(segment.profileBasalRate) / 1000
    }

    /// A pending segment write. `segment` is nil when the write is a create rather than a modify.
    internal struct PendingSegmentWrite {
        let startTime: Int
        let basalRate: Int
        let segment: IDPSegmentResponse?
    }

    /// Pairs each schedule item with the segment at the same position, dropping ones that match.
    internal static func pendingSegmentWrites(
        items: [RepeatingScheduleValue<Double>],
        retainedSegments: [IDPSegmentResponse]
    ) -> [PendingSegmentWrite] {
        items.enumerated().compactMap { index, scheduleItem in
            let startMinutes = Int((scheduleItem.startTime / 60.0).rounded())
            let basalMilliunits = Int((scheduleItem.value * 1000.0).rounded())

            guard index < retainedSegments.count else {
                return PendingSegmentWrite(startTime: startMinutes, basalRate: basalMilliunits, segment: nil)
            }

            let segment = retainedSegments[index]
            guard segment.profileStartTime != startMinutes || segment.profileBasalRate != basalMilliunits else {
                return nil
            }
            return PendingSegmentWrite(startTime: startMinutes, basalRate: basalMilliunits, segment: segment)
        }
    }
}

extension TandemPumpManager {
    /// A temp basal is a percent of the profile rate, so a profile change rescales it (on hardware
    /// a 184% temp fell from 1.38 to 0.92 U/hr). Stopped, as OmnipodKit cancels delivery first.
    func restartBasalDoseAfterScheduleChange(previousRate: Double) {
        let newRate = pumpScheduledBasalRate(at: now)
        guard !state.useControlIQ, Int((newRate * 1000).rounded()) != Int((previousRate * 1000).rounded()) else {
            return
        }

        // Read the pump rather than `state.basalDose`: after re-pairing the driver can miss a temp
        // basal the previous manager set.
        guard let status = bluetooth.write(CurrentBasalStatusRequest()) else {
            logger.error("No basal status after a basal schedule change; recorded dose left as it was")
            return
        }

        switch status.basalType {
        case .suspend:
            return
        case .tempBasal:
            // 0% of either profile: stopping it would resume insulin the loop is withholding.
            if status.currentBasalRate == 0, status.profileBasalRate > 0 {
                return
            }
            guard let stop = bluetooth.write(StopTempRateRequest()), stop.isStatusOK else {
                logger.error("Could not stop the temp basal after a basal schedule change; it is running rescaled")
                return
            }
            logger.info("Stopped the temp basal after a basal schedule change")
        default:
            break
        }

        // Even with no temp to stop: `basalDose` is what the Profile Basal row shows. Not `status`'s
        // rate: whether it reads the segment just written is unknown, and the write was read back.
        startScheduledBasalDose()
    }

    /// Returns nil on a missing response. `IDPManager.nextMessages()` keeps returning the same
    /// requests until they are answered, so carrying on after a dropped response loops forever.
    func loadIDPProfiles() -> IDPManager? {
        let idpManager = IDPManager()

        while !idpManager.isComplete {
            let messages = idpManager.nextMessages()
            guard !messages.isEmpty else {
                return nil
            }

            for request in messages {
                guard let response = self.bluetooth.write(request) else {
                    return nil
                }
                idpManager.processMessage(response)
            }
        }

        return idpManager
    }

    /// A successful `SetIDPSegmentResponse` isn't taken as proof the profile changed, so this
    /// reads it back. `pendingSegmentWrites` lists the writes still needed; none means a match.
    func verifyProfileMatches(items: [RepeatingScheduleValue<Double>]) -> Error? {
        guard let profile = loadIDPProfiles()?.getActiveProfile() else {
            logger.error("Could not read the basal profile back to verify it")
            return PumpCommError.requestConstructionFailed(
                reason: "Could not read the basal profile back to verify it"
            )
        }

        let segments = profile.getSegments()
        guard segments.count == items.count,
              Self.pendingSegmentWrites(items: items, retainedSegments: segments).isEmpty
        else {
            logger.error(
                "Basal profile does not match after sync: \(PumpCommError.basalProfileDifference(pump: segments, app: items))"
            )
            return PumpCommError.basalProfileSyncMismatch(pump: segments, app: items)
        }

        return nil
    }

    /// State saved before `hasSyncedBasalRateSchedule` existed reads false on a pump that was looping,
    /// and hosts sync only on a save. A profile already matching is what a successful sync leaves.
    /// Not after a failed update: a matching profile does not explain a rate that still differs.
    func adoptMatchingPumpProfile() {
        let items = state.basalRateSchedule.items.sorted { $0.startTime < $1.startTime }
        guard !state.hasSyncedBasalRateSchedule,
              !state.basalProfileUpdateFailed,
              items.contains(where: { $0.value > 0 })
        else {
            return
        }

        guard let segments = loadIDPProfiles()?.getActiveProfile()?.getSegments() else {
            logger.error("Could not read the basal profile to check it against the app's schedule")
            return
        }

        guard segments.count == items.count,
              Self.pendingSegmentWrites(items: items, retainedSegments: segments).isEmpty
        else {
            logger.warning(
                "Basal schedule not yet synced, and the pump's profile differs: \(PumpCommError.basalProfileDifference(pump: segments, app: items))"
            )
            noteBasalProfileMismatch()
            return
        }

        logger.info("Pump's basal profile matches the app's schedule; treating it as synced")
        state.hasSyncedBasalRateSchedule = true
        markBasalProfileValidated()
    }

    static let basalProfileUpdateRetryInterval: TimeInterval = .minutes(1)

    /// Writes the app's schedule over the pump's profile. The update ends once the profile reads
    /// back matching and the pump's rate in force agrees with it: a profile that matches while the
    /// rate still differs would otherwise end and restart the update at every reading.
    func updatePumpBasalProfile() {
        basalProfileUpdateLock.lock()
        let tooSoon = lastBasalProfileUpdateAttempt.map { now.timeIntervalSince($0) < Self.basalProfileUpdateRetryInterval } ?? false
        guard !basalProfileUpdateInFlight, !tooSoon else {
            basalProfileUpdateLock.unlock()
            return
        }
        basalProfileUpdateInFlight = true
        lastBasalProfileUpdateAttempt = now
        basalProfileUpdateLock.unlock()

        bluetooth.ensureConnected { error in
            defer { self.finishBasalProfileUpdate() }

            if let error {
                self.logger.error("Failed to connect to update the pump's basal profile: \(error.localizedDescription)")
                return
            }

            // Read here, not when queued: a host sync queued ahead of this job may change it.
            let items = self.state.basalRateSchedule.items.sorted { $0.startTime < $1.startTime }

            // With no schedule from the host, writing it would set the pump to deliver no basal insulin.
            guard items.contains(where: { $0.value > 0 }) else {
                self.logger.error("No basal schedule from the app; not writing it to the pump")
                return
            }

            guard self.basalScheduleSyncError(items) == nil else {
                return
            }

            if case let .failure(error) = self.writeBasalRateSchedule(items) {
                self.logger.error("Could not update the pump's basal profile: \(String(describing: error))")
                return
            }

            guard let status = self.bluetooth.write(CurrentBasalStatusRequest()) else {
                self.logger.error("No basal status after updating the pump's basal profile; checking again at the next reading")
                return
            }

            if let mismatch = self.deliveredBasalRateMismatch(status) {
                self.logger.error(
                    "The pump's basal profile matches the schedule, but it runs \(mismatch.pump) U/hr where the schedule says \(mismatch.expected) U/hr"
                )
                // The write set the flag; a failed update keeps temp basals refused.
                if self.state.basalProfileUpdateFailed {
                    self.state.hasSyncedBasalRateSchedule = false
                    self.notifyDelegateStateUpdated()
                }
                return
            }

            self.logger.info("Updated the pump's basal profile to match the schedule")
            self.markBasalProfileValidated()
        }
    }

    private func finishBasalProfileUpdate() {
        basalProfileUpdateLock.lock()
        basalProfileUpdateInFlight = false
        basalProfileUpdateLock.unlock()
    }

    func markBasalProfileValidated() {
        guard state.basalProfileUpdateStatus != .none else {
            return
        }
        state.basalRateMismatchDetectedAt = nil
        state.basalProfileUpdateFailed = false
        notifyDelegateStateUpdated()
    }
}
