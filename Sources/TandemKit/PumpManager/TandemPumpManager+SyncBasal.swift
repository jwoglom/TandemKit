import LoopKit

public extension TandemPumpManager {
    func syncBasalRateSchedule(
        items scheduleItems: [RepeatingScheduleValue<Double>],
        completion: @escaping (_ result: Result<BasalRateSchedule, Error>) -> Void
    ) {
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

                for (request, expecting) in messages {
                    let response = self.bluetooth.write(
                        message: request,
                        expecting: expecting
                    )
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

                guard let newlyCreatedProfile = self.bluetooth.write(
                    message: message,
                    expecting: CreateIDPResponse.self
                ) as? CreateIDPResponse else {
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
                    for (request, expecting) in messages {
                        let response = self.bluetooth.write(
                            message: request,
                            expecting: expecting
                        )
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

            // Step 4: Build modify requests for each new basal schedule item
            var modifyRequests: [SetIDPSegmentRequest] = []

            for (index, scheduleItem) in sortedItems.enumerated() {
                let startMinutes = Int((scheduleItem.startTime / 60.0).rounded())
                let basalMilliunits = Int((scheduleItem.value * 1000.0).rounded())

                if index < currentSegments.count {
                    // Check if existing segment needs modification
                    let currentSegment = currentSegments[index]
                    let needsUpdate = currentSegment.profileStartTime != startMinutes ||
                        currentSegment.profileBasalRate != basalMilliunits

                    if needsUpdate {
                        let segment = currentSegment
                        segment.profileStartTime = startMinutes
                        segment.profileBasalRate = basalMilliunits
                        let request = activeProfile.modifySegmentMessage(segment: segment)
                        modifyRequests.append(request)
                    }
                } else {
                    // Create new segment with default values from first segment
                    let firstSegment = currentSegments.first!
                    let request = activeProfile.createSegmentMessage(
                        profileStartTime: startMinutes,
                        profileBasalRate: basalMilliunits,
                        profileCarbRatio: firstSegment.profileCarbRatio,
                        profileTargetBG: Int(firstSegment.profileTargetBG),
                        profileISF: firstSegment.profileISF
                    )
                    modifyRequests.append(request)
                }
            }

            // Step 5: If we have fewer items than current segments, delete extra segments
            if sortedItems.count < currentSegments.count {
                for i in sortedItems.count ..< currentSegments.count {
                    if i > 0 { // Can't delete segment 0
                        let deleteRequest = activeProfile.deleteSegmentMessage(segment: currentSegments[i])
                        
                        // Prepent delete actions
                        modifyRequests.insert(deleteRequest, at: 0)
                    }
                }
            }

            // Step 6: Send all modification requests
            for request in modifyRequests {
                guard let response = self.bluetooth.write(
                    message: request,
                    expecting: SetIDPSegmentResponse.self
                ) as? SetIDPSegmentResponse else {
                    self.logger.error("Pump rejected SetIDPSegment")
                    completion(.failure(PumpCommError.requestConstructionFailed(reason: "Pump rejected SetIDPSegment")))
                    return
                }

                guard response.status == 0 else {
                    self.logger.error("Pump rejected SetIDPSegment, status: \(response.status)")
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
}
