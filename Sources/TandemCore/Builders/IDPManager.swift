import Foundation

/// IDPManager provides an abstraction for managing insulin delivery profiles (IDPs).
///
/// This manager handles:
/// - Fetching all profiles and their segments from the pump
/// - Creating, modifying, and deleting profile segments
/// - Creating and deleting entire profiles
/// - Setting the active profile
///
/// Based on pumpX2's IDPManager.java implementation.
///
/// ## Usage
/// 1. Create an IDPManager instance
/// 2. Call `nextMessages()` to get the next batch of requests to send
/// 3. Send those requests to the pump via `PumpComm.sendMessage`
/// 4. Pass each response to `processMessage()`
/// 5. Repeat steps 2-4 until `isComplete()` returns true
/// 6. Access profiles via `getProfiles()` or `getActiveProfile()`
/// 7. Generate mutation requests via profile methods like `modifySegmentMessage()`, `createSegmentMessage()`, etc.
public class IDPManager {
    // MARK: - Profile

    /// Represents a complete insulin delivery profile with all segments.
    public class Profile {
        private var idpSettingsResponse: IDPSettingsResponse
        fileprivate var segments: [IDPSegmentResponse] = []
        private let isActive: Bool

        public init(idpSettingsResponse: IDPSettingsResponse, isActive: Bool) {
            self.idpSettingsResponse = idpSettingsResponse
            self.isActive = isActive
        }

        /// Whether all segments have been loaded for this profile.
        public var isComplete: Bool {
            segments.count == idpSettingsResponse.numberOfProfileSegments
        }

        public var settings: IDPSettingsResponse {
            idpSettingsResponse
        }

        public var idpId: Int {
            idpSettingsResponse.idpId
        }

        /// Returns all segments. Only valid after `isComplete` is true.
        public func getSegments() -> [IDPSegmentResponse] {
            precondition(isComplete, "Profile is not complete - cannot get segments")
            return segments
        }

        public var isActiveProfile: Bool {
            isActive
        }

        // MARK: - Profile Mutation Messages

        /// Generate a request to delete this profile.
        public func deleteProfileMessage() -> DeleteIDPRequest {
            DeleteIDPRequest(idpId: idpId)
        }

        /// Generate a request to duplicate this profile with a new name.
        public func duplicateProfileMessage(newProfileName: String) -> CreateIDPRequest {
            CreateIDPRequest(profileName: newProfileName, sourceIdpId: idpId)
        }

        /// Generate a request to make this profile the active one.
        public func setActiveProfileMessage() -> SetActiveIDPRequest {
            SetActiveIDPRequest(idpId: idpId)
        }

        // MARK: - Segment Mutation Messages

        /// Generate a request to delete a segment from this profile.
        ///
        /// - Note: Segment index 0 cannot be deleted.
        /// - Parameter segment: The segment to delete
        /// - Returns: Request to send to the pump
        public func deleteSegmentMessage(segment: IDPSegmentResponse) -> SetIDPSegmentRequest {
            precondition(segment.idpId == idpId, "Segment does not belong to this profile")
            precondition(segment.segmentIndex != 0, "Cannot delete segment 0")

            // Per pumpX2: use all 5 flags even when deleting
            let statusMask = IDPSegmentResponse.IDPSegmentStatus.allFieldsMask()

            return SetIDPSegmentRequest(
                idpId: idpId,
                unknownId: 0,
                segmentIndex: segment.segmentIndex,
                operation: .deleteSegmentId,
                profileStartTime: segment.profileStartTime,
                profileBasalRate: segment.profileBasalRate,
                profileCarbRatio: segment.profileCarbRatio,
                profileTargetBG: segment.profileTargetBG,
                profileISF: segment.profileISF,
                idpStatusId: statusMask
            )
        }

        /// Generate a request to modify an existing segment.
        ///
        /// - Parameter segment: The segment with updated values
        /// - Returns: Request to send to the pump
        public func modifySegmentMessage(segment: IDPSegmentResponse) -> SetIDPSegmentRequest {
            precondition(segment.idpId == idpId, "Segment does not belong to this profile")

            // Per pumpX2 IDPManager.modifySegmentMessage: must include all 5 fields
            let statusMask = IDPSegmentResponse.IDPSegmentStatus.allFieldsMask()

            return SetIDPSegmentRequest(
                idpId: idpId,
                unknownId: 0,
                segmentIndex: segment.segmentIndex,
                operation: .modifySegmentId,
                profileStartTime: segment.profileStartTime,
                profileBasalRate: segment.profileBasalRate,
                profileCarbRatio: segment.profileCarbRatio,
                profileTargetBG: segment.profileTargetBG,
                profileISF: segment.profileISF,
                idpStatusId: statusMask
            )
        }

        /// Generate a request to create a new segment in this profile.
        ///
        /// - Parameters:
        ///   - profileStartTime: Start time in minutes from midnight (e.g., 480 for 8:00 AM)
        ///   - profileBasalRate: Basal rate in milliunits (e.g., 800 for 0.8 U/hr)
        ///   - profileCarbRatio: Carb ratio as UInt32 (e.g., 10000 for 1:10)
        ///   - profileTargetBG: Target BG in mg/dL
        ///   - profileISF: Insulin sensitivity factor (e.g., 50 for 1:50)
        /// - Returns: Request to send to the pump
        public func createSegmentMessage(
            profileStartTime: Int,
            profileBasalRate: Int,
            profileCarbRatio: UInt32,
            profileTargetBG: Int,
            profileISF: Int
        ) -> SetIDPSegmentRequest {
            // Per pumpX2 IDPManager.createSegmentMessage: must include all 5 fields
            let statusMask = IDPSegmentResponse.IDPSegmentStatus.allFieldsMask()

            return SetIDPSegmentRequest(
                idpId: idpId,
                unknownId: 0,
                segmentIndex: 0, // Segment index is ignored for create operations
                operation: .createSegment,
                profileStartTime: profileStartTime,
                profileBasalRate: profileBasalRate,
                profileCarbRatio: profileCarbRatio,
                profileTargetBG: profileTargetBG,
                profileISF: profileISF,
                idpStatusId: statusMask
            )
        }

        /// Convenience method to create a segment with floating-point basal rate.
        public func createSegmentMessage(
            profileStartTimeMinutes: Int,
            profileBasalRateUnits: Double,
            profileCarbRatio: UInt32,
            profileTargetBG: Int,
            profileISF: Int
        ) -> SetIDPSegmentRequest {
            let basalMilliunits = Int((profileBasalRateUnits * 1000.0).rounded())
            return createSegmentMessage(
                profileStartTime: profileStartTimeMinutes,
                profileBasalRate: basalMilliunits,
                profileCarbRatio: profileCarbRatio,
                profileTargetBG: profileTargetBG,
                profileISF: profileISF
            )
        }

        // MARK: - Internal

        fileprivate func processMessage(_ message: Message) {
            if let segmentResponse = message as? IDPSegmentResponse {
                precondition(segmentResponse.idpId == idpId, "Segment does not belong to this profile")

                // Remove any existing segment with this index and add the new one
                segments.removeAll { $0.segmentIndex == segmentResponse.segmentIndex }
                segments.append(segmentResponse)
                segments.sort { $0.segmentIndex < $1.segmentIndex }
            } else if let settingsResponse = message as? IDPSettingsResponse {
                precondition(settingsResponse.idpId == idpId, "Settings do not belong to this profile")
                idpSettingsResponse = settingsResponse
            }
        }
    }

    // MARK: - IDPManager

    private var profiles: [Profile] = []
    private var profileStatusResponse: ProfileStatusResponse?

    public init() {}

    public init(profileStatusResponse: ProfileStatusResponse) {
        self.profileStatusResponse = profileStatusResponse
    }

    /// Returns the next batch of messages to send to the pump.
    ///
    /// Send each message via `PumpComm.sendMessage`, then pass the responses to `processMessage()`.
    /// Continue calling this until it returns an empty array and `isComplete()` is true.
    public func nextMessages() -> [Message] {
        var messages: [Message] = []

        // Step 1: Get profile status if we don't have it
        guard let profileStatus = profileStatusResponse else {
            messages.append(ProfileStatusRequest())
            return messages
        }

        // Step 2: For each profile slot, fetch settings and segments
        for idpSlotId in profileStatus.idpSlotIds {
            if let profile = profiles.first(where: { $0.idpId == idpSlotId }) {
                // We have this profile - check if it's complete
                if !profile.isComplete {
                    let segmentCount = profile.settings.numberOfProfileSegments
                    for i in 0 ..< segmentCount {
                        let hasSegment = profile.segments.contains { $0.segmentIndex == i }
                        if !hasSegment {
                            messages.append(IDPSegmentRequest(idpId: idpSlotId, segmentIndex: i))
                        }
                    }
                }
            } else {
                // We don't have this profile yet - fetch its settings
                messages.append(IDPSettingsRequest(idpId: idpSlotId))
            }
        }

        return messages
    }

    /// Process a response message from the pump.
    ///
    /// Call this for each response received after sending messages from `nextMessages()`.
    @discardableResult public func processMessage(_ message: Message) -> IDPManager {
        if let profileStatus = message as? ProfileStatusResponse {
            profileStatusResponse = profileStatus
            // Remove profiles that no longer exist
            profiles.removeAll { profile in
                !profileStatus.idpSlotIds.contains(profile.idpId)
            }
        } else if let settings = message as? IDPSettingsResponse {
            let idpId = settings.idpId
            if let existingProfile = profiles.first(where: { $0.idpId == idpId }) {
                existingProfile.processMessage(message)
            } else {
                guard let profileStatus = profileStatusResponse else {
                    fatalError("Received IDPSettingsResponse before ProfileStatusResponse")
                }
                let activeSlot = profileStatus.activeIdpSlotId
                let isActive = (idpId == activeSlot)
                let newProfile = Profile(idpSettingsResponse: settings, isActive: isActive)
                profiles.append(newProfile)

                // Sort profiles by their slot order
                profiles.sort { a, b in
                    guard let aIndex = profileStatus.idpSlotIds.firstIndex(of: a.idpId),
                          let bIndex = profileStatus.idpSlotIds.firstIndex(of: b.idpId)
                    else {
                        return false
                    }
                    return aIndex < bIndex
                }
            }
        } else if let segment = message as? IDPSegmentResponse {
            let idpId = segment.idpId
            if let profile = profiles.first(where: { $0.idpId == idpId }) {
                profile.processMessage(message)
            }
        }

        return self
    }

    /// Whether the specified message is an IDP-related response.
    public static func isIDPManagerResponse(_ message: Message) -> Bool {
        message is ProfileStatusResponse || message is IDPSettingsResponse || message is IDPSegmentResponse
    }

    /// Whether all profiles and segments have been loaded.
    public var isComplete: Bool {
        guard let profileStatus = profileStatusResponse else {
            return false
        }

        return profiles.count == profileStatus.numberOfProfiles &&
            profiles.allSatisfy(\.isComplete)
    }

    /// Returns all loaded profiles. Only valid after `isComplete` is true.
    public func getProfiles() -> [Profile] {
        precondition(isComplete, "IDPManager is not complete - cannot get profiles")
        return profiles
    }

    /// Returns the active profile. Only valid after `isComplete` is true.
    public func getActiveProfile() -> Profile? {
        precondition(isComplete, "IDPManager is not complete - cannot get active profile")
        guard let profileStatus = profileStatusResponse else {
            return nil
        }

        let activeIdpId = profileStatus.activeIdpSlotId
        return profiles.first { $0.idpId == activeIdpId }
    }

    /// Returns a profile by its IDP ID.
    public func getProfile(withIdpId idpId: Int) -> Profile? {
        profiles.first { $0.idpId == idpId }
    }

    /// Clear all cached profile data.
    public func clear() {
        profiles.removeAll()
        profileStatusResponse = nil
    }

    // MARK: - Profile Creation

    /// Generate a request to create a brand new profile.
    ///
    /// - Parameters:
    ///   - profileName: Name for the new profile (max 16 chars)
    ///   - defaultCarbRatio: Carb ratio for first segment (e.g., 10000 for 1:10)
    ///   - defaultBasalRateMilliunits: Basal rate in milliunits (e.g., 1000 for 1.0 U/hr)
    ///   - defaultTargetBG: Target BG in mg/dL
    ///   - defaultISF: Insulin sensitivity factor (e.g., 50 for 1:50)
    ///   - defaultInsulinDuration: Insulin duration in minutes (e.g., 180 for 3 hours)
    ///   - profileCarbEntryEnabled: Whether carb entry is enabled
    /// - Returns: Request to send to the pump
    public func createNewProfileMessage(
        profileName: String,
        defaultCarbRatio: Int,
        defaultBasalRateMilliunits: Int,
        defaultTargetBG: Int,
        defaultISF: Int,
        defaultInsulinDuration: Int,
        profileCarbEntryEnabled: Bool
    ) -> CreateIDPRequest {
        CreateIDPRequest(
            profileName: profileName,
            firstSegmentProfileCarbRatio: defaultCarbRatio,
            firstSegmentProfileBasalRate: defaultBasalRateMilliunits,
            firstSegmentProfileTargetBG: defaultTargetBG,
            firstSegmentProfileISF: defaultISF,
            profileInsulinDuration: defaultInsulinDuration,
            profileCarbEntry: profileCarbEntryEnabled ? 1 : 0
        )
    }

    /// Convenience method with floating-point basal rate.
    public func createNewProfileMessage(
        profileName: String,
        defaultCarbRatio: Int,
        defaultBasalRateUnits: Double,
        defaultTargetBG: Int,
        defaultISF: Int,
        defaultInsulinDurationMinutes: Int,
        profileCarbEntryEnabled: Bool
    ) -> CreateIDPRequest {
        let basalMilliunits = Int((defaultBasalRateUnits * 1000.0).rounded())
        return createNewProfileMessage(
            profileName: profileName,
            defaultCarbRatio: defaultCarbRatio,
            defaultBasalRateMilliunits: basalMilliunits,
            defaultTargetBG: defaultTargetBG,
            defaultISF: defaultISF,
            defaultInsulinDuration: defaultInsulinDurationMinutes,
            profileCarbEntryEnabled: profileCarbEntryEnabled
        )
    }
}

// MARK: - IDPSegmentStatus Extension

public extension IDPSegmentResponse.IDPSegmentStatus {
    /// Returns a bitmask with all 5 status flags set (value: 31).
    ///
    /// Per pumpX2 IDPManager: all segment operations (create, modify, delete)
    /// must include all 5 fields even if some values are 0.
    static func allFieldsMask() -> Int {
        let all: Set<IDPSegmentResponse.IDPSegmentStatus> = [
            .BASAL_RATE,
            .CARB_RATIO,
            .TARGET_BG,
            .CORRECTION_FACTOR,
            .START_TIME
        ]
        return all.reduce(0) { $0 | $1.rawValue }
    }
}
