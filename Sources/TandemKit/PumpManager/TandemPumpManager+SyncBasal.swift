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
        guard !scheduleItems.isEmpty else {
            logger.error("Basal schedule is empty")
            completion(.failure(PumpManagerError.configuration(nil)))
            return
        }

        guard scheduleItems.count <= maximumBasalScheduleEntryCount else {
            logger.error(
                "Basal schedule has \(scheduleItems.count) entries; the pump holds at most \(self.maximumBasalScheduleEntryCount)"
            )
            completion(.failure(BasalScheduleSyncError.tooManyEntries(
                count: scheduleItems.count,
                maximum: maximumBasalScheduleEntryCount
            )))
            return
        }

        let sortedItems = scheduleItems.sorted { $0.startTime < $1.startTime }

        guard Int((sortedItems[0].startTime / 60).rounded()) == 0 else {
            logger.error("Basal schedule starts at \(sortedItems[0].startTime)s, not midnight")
            completion(.failure(BasalScheduleSyncError.firstEntryNotAtMidnight))
            return
        }

        bluetooth.ensureConnected { error in
            if let error {
                self.logger.error("Failed to connect for syncBasal: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard var idpManager = self.loadIDPProfiles() else {
                self.logger.error("Invalid IDPManager state in syncBasalRateSchedule")
                completion(.failure(PumpCommError.requestConstructionFailed(
                    reason: "Invalid IDPManager state in syncBasalRateSchedule"
                )))
                return
            }

            if idpManager.getProfiles().isEmpty == true {
                self.logger.info("No profiles in IDPManager, creating initial profile for Trio")
                // TODO(jwoglom): read correct profile defaults
                let message = idpManager.createNewProfileMessage(
                    profileName: "TandemKitProfile",
                    defaultCarbRatio: 10,
                    defaultBasalRateUnits: scheduleItems.first?.value ?? 0,
                    defaultTargetBG: 110,
                    defaultISF: 40,
                    defaultInsulinDurationMinutes: 240,
                    profileCarbEntryEnabled: false
                )

                guard let newlyCreatedProfile = self.bluetooth.write(message) else {
                    self.logger.error("No active profile found and got unexpected response creating initial profile")
                    completion(.failure(PumpCommError.requestConstructionFailed(
                        reason: "No active profile found and got unexpected response creating initial profile"
                    )))
                    return
                }

                guard newlyCreatedProfile.isStatusOK else {
                    self.logger.error("No active profile found and got unexpected response creating initial profile")
                    completion(.failure(PumpCommError.requestConstructionFailed(
                        reason: "No active profile found and got unexpected response creating initial profile"
                    )))
                    return
                }

                self.logger
                    .info("Created initial IDP profile with ID \(String(describing: newlyCreatedProfile.newIdpId))")

                guard let reloaded = self.loadIDPProfiles() else {
                    self.logger.error("Invalid IDPManager state after creating initial profile")
                    completion(.failure(PumpCommError.requestConstructionFailed(
                        reason: "Invalid IDPManager state after creating initial profile"
                    )))
                    return
                }
                idpManager = reloaded
            }

            // Step 2: Get the active profile
            guard let activeProfile = idpManager.getActiveProfile() else {
                self.logger.error("No active profile found")
                completion(.failure(PumpCommError.requestConstructionFailed(reason: "No active profile found")))
                return
            }

            // Step 3: Get current segments to preserve non-basal fields
            let currentSegments = activeProfile.getSegments()

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
                    completion(.failure(PumpCommError.requestConstructionFailed(
                        reason: "Could not order basal segment writes without a start time collision"
                    )))
                    return
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
                    let firstSegment = currentSegments.first!
                    requests.append(activeProfile.createSegmentMessage(
                        profileStartTime: write.startTime,
                        profileBasalRate: write.basalRate,
                        profileCarbRatio: firstSegment.profileCarbRatio,
                        profileTargetBG: Int(firstSegment.profileTargetBG),
                        profileISF: firstSegment.profileISF
                    ))
                    occupiedStartTimes[nextCreatedSegmentKey] = write.startTime
                    nextCreatedSegmentKey -= 1
                }
            }

            // Step 6: Send all modification requests
            for request in requests {
                guard let response = self.bluetooth.write(request) else {
                    self.logger.error("No response to SetIDPSegment for segment \(request.segmentIndex)")
                    completion(.failure(PumpCommError.requestConstructionFailed(reason: "Pump rejected SetIDPSegment")))
                    return
                }

                guard response.status == 0 else {
                    self.logger
                        .error(
                            "Pump rejected SetIDPSegment, status: \(response.status), operation: \(String(describing: request.operation)), segment: \(request.segmentIndex), startTime: \(request.profileStartTime)"
                        )
                    completion(.failure(PumpCommError.errorResponse(
                        context: String(
                            localized: "Error syncing basal rates: Pump rejected SetIDPSegment",
                            comment: "Message when pump rejects SetIDPSegment"
                        ),
                        request: request,
                        response: response
                    )))
                    return
                }
            }

            if let error = self.verifyProfileMatches(items: sortedItems) {
                completion(.failure(error))
                return
            }

            let schedule = BasalRateSchedule(dailyItems: sortedItems, timeZone: TimeZone.current) ?? self.state.basalRateSchedule
            let previousRate = self.getScheduledBasalRate(at: self.now.addingTimeInterval(self.state.pumpClockOffset))

            self.state.basalRateSchedule = schedule
            self.state.hasSyncedBasalRateSchedule = true
            self.state.settings.maxBasalScheduleEntry = sortedItems.map(\.value).max()
            self.notifyDelegateStateUpdated()

            self.restartBasalDoseAfterScheduleChange(previousRate: previousRate)

            completion(.success(
                BasalRateSchedule(dailyItems: sortedItems, timeZone: TimeZone.current) ?? self.state
                    .basalRateSchedule
            ))
        }
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
        let newRate = getScheduledBasalRate(at: now.addingTimeInterval(state.pumpClockOffset))
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
            guard let stop = bluetooth.write(StopTempRateRequest()), stop.isStatusOK else {
                logger.error("Could not stop the temp basal after a basal schedule change; it is running rescaled")
                return
            }
            logger.info("Stopped the temp basal after a basal schedule change")
        default:
            break
        }

        // Even with no temp to stop: `basalDose` is what the Profile Basal row shows.
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
    func adoptMatchingPumpProfile() {
        let items = state.basalRateSchedule.items.sorted { $0.startTime < $1.startTime }
        guard !state.hasSyncedBasalRateSchedule, items.contains(where: { $0.value > 0 }) else {
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
            return
        }

        logger.info("Pump's basal profile matches the app's schedule; treating it as synced")
        state.hasSyncedBasalRateSchedule = true
    }
}
