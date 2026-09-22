import LoopKit

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

        let sortedItems = scheduleItems.sorted { $0.startTime < $1.startTime }

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
                    segment.profileStartTime = write.startTime
                    segment.profileBasalRate = write.basalRate
                    requests.append(activeProfile.modifySegmentMessage(segment: segment))
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

            self.state.basalRateSchedule = schedule
            self.state.settings.maxBasalScheduleEntry = sortedItems.map(\.value).max()
            self.notifyDelegateStateUpdated()

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
    /// nil when the pump stopped answering: `IDPManager.nextMessages()` reissues the same batch
    /// until its response arrives, so a dropped one has to end the walk rather than spin.
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

    /// A status-0 `SetIDPSegmentResponse` says the pump accepted a write, not that the profile now
    /// holds it, and every temp basal percent is scaled off that profile.
    ///
    /// `pendingSegmentWrites` is the comparison: it returns the writes still needed to make the
    /// pump match, so an empty result against a freshly read profile means the writes landed.
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

}
