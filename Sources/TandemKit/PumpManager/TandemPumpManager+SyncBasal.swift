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

            // Step 1: Fetch current profile data using IDPManager
            let idpManager = IDPManager()

            // Fetch all IDP data until complete
            while !idpManager.isComplete {
                let messages = idpManager.nextMessages()
                if messages.isEmpty, !idpManager.isComplete {
                    self.logger.error("Invalid IDPManager state in syncBasalRateSchedule")
                    completion(.failure(PumpCommError.requestConstructionFailed(
                        reason: "Invalid IDPManager state in syncBasalRateSchedule"
                    )))
                    return
                }

                for request in messages {
                    let response = self.bluetooth.write(request)
                    if let response {
                        idpManager.processMessage(response)
                    }
                }
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

                // Return to step 1: Reset idpManager
                idpManager.clear()

                // Fetch all IDP data until complete
                while !idpManager.isComplete {
                    let messages = idpManager.nextMessages()
                    for request in messages {
                        let response = self.bluetooth.write(request)
                        if let response {
                            idpManager.processMessage(response)
                        }
                    }
                }
            }

            // Step 2: Get the active profile
            guard let activeProfile = idpManager.getActiveProfile() else {
                self.logger.error("No active profile found")
                completion(.failure(PumpCommError.requestConstructionFailed(reason: "No active profile found")))
                return
            }

            // Step 3: Get current segments to preserve non-basal fields
            let currentSegments = activeProfile.getSegments()

            // Step 4: Delete the surplus tail segments first, highest index first so the indices of
            // the segments we are about to modify stay valid.
            var requests: [SetIDPSegmentRequest] = []
            if sortedItems.count < currentSegments.count {
                for index in stride(from: currentSegments.count - 1, through: sortedItems.count, by: -1)
                    where index > 0 // segment 0 cannot be deleted
                {
                    requests.append(activeProfile.deleteSegmentMessage(segment: currentSegments[index]))
                }
            }

            // Segments that survive the deletes, paired positionally with the new schedule items.
            let retainedSegments = Array(currentSegments.prefix(min(sortedItems.count, currentSegments.count)))

            // Step 5: Work out which segments actually change, and order those writes so that the
            // profile never transiently holds two segments with the same start time. The pump
            // rejects such a write with status 1, which is what made a shrinking schedule fail: the
            // segment being moved forward landed on a start time the next segment still occupied.
            var pendingWrites = Self.pendingSegmentWrites(
                items: sortedItems,
                retainedSegments: retainedSegments
            )

            // Start time currently held by each retained segment, keyed by segment index. Segments
            // created during this sync get a synthetic negative key so they occupy their slot too.
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
                    // Unreachable for well-formed schedules: both the current and the target start
                    // times are strictly ascending, so a cycle of mutual blocks cannot form. Bail
                    // out rather than spin if the pump ever hands back something unordered.
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
                    // Create new segment with default values from first segment
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

    /// A basal segment write the pump still needs, paired with the existing segment it modifies.
    ///
    /// `segment` is nil when the new schedule has more entries than the profile has segments, in
    /// which case the write is a create rather than a modify.
    internal struct PendingSegmentWrite {
        let startTime: Int
        let basalRate: Int
        let segment: IDPSegmentResponse?
    }

    /// Pairs each schedule item with the segment at the same position and drops the ones that
    /// already match, so only genuine changes are sent to the pump.
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
