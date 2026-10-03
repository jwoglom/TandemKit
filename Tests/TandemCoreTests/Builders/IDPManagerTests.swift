@testable import TandemKit
import XCTest

final class IDPManagerTests: XCTestCase {
    // MARK: - Basic Flow Tests

    func testInitialStateRequestsProfileStatus() {
        let manager = IDPManager()
        let messages = manager.nextMessages()

        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages.first is ProfileStatusRequest)
        XCTAssertFalse(manager.isComplete)
    }

    func testProcessProfileStatusRequestsSettings() {
        let manager = IDPManager()

        // Step 1: Get profile status request
        var messages = manager.nextMessages()
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages.first is ProfileStatusRequest)

        // Step 2: Process profile status response with 2 profiles
        let profileStatus = ProfileStatusResponse(
            numberOfProfiles: 2,
            idpSlot0Id: 10,
            idpSlot1Id: 20,
            idpSlot2Id: 0,
            idpSlot3Id: 0,
            idpSlot4Id: 0,
            idpSlot5Id: 0,
            activeSegmentIndex: 0
        )
        manager.processMessage(profileStatus)

        // Step 3: Should now request settings for both profiles
        messages = manager.nextMessages()
        XCTAssertEqual(messages.count, 2)

        let settingsRequests = messages.compactMap { $0 as? IDPSettingsRequest }
        XCTAssertEqual(settingsRequests.count, 2)
        XCTAssertTrue(settingsRequests.contains { $0.idpId == 10 })
        XCTAssertTrue(settingsRequests.contains { $0.idpId == 20 })
    }

    func testProcessSettingsRequestsSegments() {
        let manager = IDPManager()

        // Setup: Process profile status
        let profileStatus = ProfileStatusResponse(
            numberOfProfiles: 1,
            idpSlot0Id: 10,
            idpSlot1Id: 0,
            idpSlot2Id: 0,
            idpSlot3Id: 0,
            idpSlot4Id: 0,
            idpSlot5Id: 0,
            activeSegmentIndex: 0
        )
        manager.processMessage(profileStatus)
        _ = manager.nextMessages() // IDPSettingsRequest

        // Process settings response with 3 segments
        let settings = IDPSettingsResponse(
            idpId: 10,
            name: "Test",
            numberOfProfileSegments: 3,
            insulinDuration: 180,
            maxBolus: 0,
            carbEntry: true
        )
        manager.processMessage(settings)

        // Should now request all 3 segments
        let messages = manager.nextMessages()
        XCTAssertEqual(messages.count, 3)

        let segmentRequests = messages.compactMap { $0 as? IDPSegmentRequest }
        XCTAssertEqual(segmentRequests.count, 3)
        XCTAssertTrue(segmentRequests.contains { $0.segmentIndex == 0 })
        XCTAssertTrue(segmentRequests.contains { $0.segmentIndex == 1 })
        XCTAssertTrue(segmentRequests.contains { $0.segmentIndex == 2 })
    }

    func testCompleteFlow() throws {
        let manager = IDPManager()

        // Step 1: Profile status
        _ = manager.nextMessages()
        let profileStatus = ProfileStatusResponse(
            numberOfProfiles: 1,
            idpSlot0Id: 10,
            idpSlot1Id: 0,
            idpSlot2Id: 0,
            idpSlot3Id: 0,
            idpSlot4Id: 0,
            idpSlot5Id: 0,
            activeSegmentIndex: 0
        )
        manager.processMessage(profileStatus)

        // Step 2: Settings
        _ = manager.nextMessages()
        let settings = IDPSettingsResponse(
            idpId: 10,
            name: "Test",
            numberOfProfileSegments: 2,
            insulinDuration: 180,
            maxBolus: 0,
            carbEntry: true
        )
        manager.processMessage(settings)

        // Step 3: Segments
        _ = manager.nextMessages()
        let segment0 = IDPSegmentResponse(
            idpId: 10,
            segmentIndex: 0,
            profileStartTime: 0,
            profileBasalRate: 1000,
            profileCarbRatio: 10000,
            profileTargetBG: 110,
            profileISF: 50,
            idpStatusId: 31
        )
        manager.processMessage(segment0)

        let segment1 = IDPSegmentResponse(
            idpId: 10,
            segmentIndex: 1,
            profileStartTime: 480,
            profileBasalRate: 1200,
            profileCarbRatio: 10000,
            profileTargetBG: 110,
            profileISF: 50,
            idpStatusId: 31
        )
        manager.processMessage(segment1)

        // Should be complete now
        XCTAssertTrue(manager.isComplete)
        XCTAssertEqual(manager.nextMessages().count, 0)

        let profiles = manager.getProfiles()
        XCTAssertEqual(profiles.count, 1)

        let profile = try XCTUnwrap(profiles.first)
        XCTAssertEqual(profile.idpId, 10)
        XCTAssertTrue(profile.isComplete)
        XCTAssertTrue(profile.isActiveProfile)

        let segments = profile.getSegments()
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].segmentIndex, 0)
        XCTAssertEqual(segments[1].segmentIndex, 1)
    }

    // MARK: - Modify Segment Tests

    /// The masks a modify can carry, each as Tandem's app sent it in pumpX2's captures
    /// (`SetIDPSegmentRequestTests`).
    func testModifySegmentMessageFlagsOnlyTheChangedFields() throws {
        let combinations: [(Set<IDPSegmentResponse.IDPSegmentStatus>, Int)] = [
            ([.BASAL_RATE], 1),
            ([.START_TIME], 16),
            ([.BASAL_RATE, .START_TIME], 17)
        ]

        for (fields, mask) in combinations {
            let manager = IDPManager()
            setupCompleteManager(manager)
            let profile = try XCTUnwrap(manager.getActiveProfile())
            let segment = try XCTUnwrap(profile.getSegments().last)
            segment.profileStartTime = 600
            segment.profileBasalRate = 1500

            let request = profile.modifySegmentMessage(segment: segment, changedFields: fields)

            XCTAssertEqual(request.idpId, profile.idpId)
            XCTAssertEqual(request.segmentIndex, segment.segmentIndex)
            XCTAssertEqual(request.operation, .modifySegmentId)
            XCTAssertEqual(request.profileStartTime, 600)
            XCTAssertEqual(request.profileBasalRate, 1500)
            XCTAssertEqual(request.idpStatusId, mask, "\(fields)")
        }
    }

    // MARK: - Create Segment Tests

    func testCreateSegmentMessageIncludesAllFields() throws {
        let manager = IDPManager()
        setupCompleteManager(manager)

        let profile = try XCTUnwrap(manager.getActiveProfile())

        let request = profile.createSegmentMessage(
            profileStartTime: 720, // 12:00 PM
            profileBasalRate: 1300,
            profileCarbRatio: 12000,
            profileTargetBG: 120,
            profileISF: 40
        )

        XCTAssertEqual(request.idpId, profile.idpId)
        XCTAssertEqual(request.operation, .createSegment)
        XCTAssertEqual(request.profileStartTime, 720)
        XCTAssertEqual(request.profileBasalRate, 1300)
        XCTAssertEqual(request.profileCarbRatio, 12000)
        XCTAssertEqual(request.profileTargetBG, 120)
        XCTAssertEqual(request.profileISF, 40)
        XCTAssertEqual(request.idpStatusId, 31, "Must include all 5 fields")
    }

    func testCreateSegmentMessageWithFloatingPointBasal() throws {
        let manager = IDPManager()
        setupCompleteManager(manager)

        let profile = try XCTUnwrap(manager.getActiveProfile())

        let request = profile.createSegmentMessage(
            profileStartTimeMinutes: 720,
            profileBasalRateUnits: 1.25,
            profileCarbRatio: 12000,
            profileTargetBG: 120,
            profileISF: 40
        )

        XCTAssertEqual(request.profileBasalRate, 1250) // 1.25 * 1000
    }

    // MARK: - Delete Segment Tests

    func testDeleteSegmentMessageIncludesAllFields() throws {
        let manager = IDPManager()
        setupCompleteManager(manager)

        let profile = try XCTUnwrap(manager.getActiveProfile())
        let segments = profile.getSegments()
        let segment = try XCTUnwrap(segments.last) // Don't try to delete segment 0

        let request = profile.deleteSegmentMessage(segment: segment)

        XCTAssertEqual(request.idpId, profile.idpId)
        XCTAssertEqual(request.segmentIndex, segment.segmentIndex)
        XCTAssertEqual(request.operation, .deleteSegmentId)
        XCTAssertEqual(request.idpStatusId, 31, "Must include all 5 fields")
    }

    // MARK: - Profile Management Tests

    func testDeleteProfileMessage() throws {
        let manager = IDPManager()
        setupCompleteManager(manager)

        let profile = try XCTUnwrap(manager.getActiveProfile())
        let request = profile.deleteProfileMessage()

        XCTAssertEqual(request.idpId, profile.idpId)
    }

    func testDuplicateProfileMessage() throws {
        let manager = IDPManager()
        setupCompleteManager(manager)

        let profile = try XCTUnwrap(manager.getActiveProfile())
        let request = profile.duplicateProfileMessage(newProfileName: "Copy")

        XCTAssertEqual(request.profileName, "Copy")
        XCTAssertEqual(request.sourceIdpId, profile.idpId)
    }

    func testSetActiveProfileMessage() throws {
        let manager = IDPManager()
        setupCompleteManager(manager)

        let profile = try XCTUnwrap(manager.getActiveProfile())
        let request = profile.setActiveProfileMessage()

        XCTAssertEqual(request.idpId, profile.idpId)
    }

    func testCreateNewProfileMessage() {
        let manager = IDPManager()

        let request = manager.createNewProfileMessage(
            profileName: "New Profile",
            defaultCarbRatio: 10000,
            defaultBasalRateMilliunits: 1000,
            defaultTargetBG: 110,
            defaultISF: 50,
            defaultInsulinDuration: 180,
            profileCarbEntryEnabled: true
        )

        XCTAssertEqual(request.profileName, "New Profile")
        XCTAssertEqual(request.firstSegmentProfileCarbRatio, 10000)
        XCTAssertEqual(request.firstSegmentProfileBasalRate, 1000)
        XCTAssertEqual(request.firstSegmentProfileTargetBG, 110)
        XCTAssertEqual(request.firstSegmentProfileISF, 50)
        XCTAssertEqual(request.profileInsulinDuration, 180)
        XCTAssertEqual(request.profileCarbEntry, 1)
        XCTAssertEqual(request.sourceIdpId, -1)
    }

    func testCreateNewProfileMessageWithFloatingPointBasal() {
        let manager = IDPManager()

        let request = manager.createNewProfileMessage(
            profileName: "New Profile",
            defaultCarbRatio: 10000,
            defaultBasalRateUnits: 1.5,
            defaultTargetBG: 110,
            defaultISF: 50,
            defaultInsulinDurationMinutes: 180,
            profileCarbEntryEnabled: false
        )

        XCTAssertEqual(request.firstSegmentProfileBasalRate, 1500) // 1.5 * 1000
        XCTAssertEqual(request.profileCarbEntry, 0)
    }

    // MARK: - Helper Method Tests

    func testAllFieldsMask() {
        let mask = IDPSegmentResponse.IDPSegmentStatus.allFieldsMask()
        XCTAssertEqual(mask, 31)

        let flags = IDPSegmentResponse.IDPSegmentStatus.fromBitmask(mask)
        XCTAssertEqual(flags.count, 5)
        XCTAssertTrue(flags.contains(.BASAL_RATE))
        XCTAssertTrue(flags.contains(.CARB_RATIO))
        XCTAssertTrue(flags.contains(.TARGET_BG))
        XCTAssertTrue(flags.contains(.CORRECTION_FACTOR))
        XCTAssertTrue(flags.contains(.START_TIME))
    }

    func testIsIDPManagerResponse() {
        XCTAssertTrue(IDPManager.isIDPManagerResponse(ProfileStatusResponse(
            numberOfProfiles: 0,
            idpSlot0Id: 0,
            idpSlot1Id: 0,
            idpSlot2Id: 0,
            idpSlot3Id: 0,
            idpSlot4Id: 0,
            idpSlot5Id: 0,
            activeSegmentIndex: 0
        )))

        XCTAssertTrue(IDPManager.isIDPManagerResponse(IDPSettingsResponse(
            idpId: 0,
            name: "",
            numberOfProfileSegments: 0,
            insulinDuration: 0,
            maxBolus: 0,
            carbEntry: false
        )))

        XCTAssertTrue(IDPManager.isIDPManagerResponse(IDPSegmentResponse(
            idpId: 0,
            segmentIndex: 0,
            profileStartTime: 0,
            profileBasalRate: 0,
            profileCarbRatio: 0,
            profileTargetBG: 0,
            profileISF: 0,
            idpStatusId: 0
        )))

        XCTAssertFalse(IDPManager.isIDPManagerResponse(ProfileStatusRequest()))
    }

    // MARK: - Helpers

    private func setupCompleteManager(_ manager: IDPManager) {
        // Profile status
        let profileStatus = ProfileStatusResponse(
            numberOfProfiles: 1,
            idpSlot0Id: 10,
            idpSlot1Id: 0,
            idpSlot2Id: 0,
            idpSlot3Id: 0,
            idpSlot4Id: 0,
            idpSlot5Id: 0,
            activeSegmentIndex: 0
        )
        manager.processMessage(profileStatus)

        // Settings
        let settings = IDPSettingsResponse(
            idpId: 10,
            name: "Test",
            numberOfProfileSegments: 2,
            insulinDuration: 180,
            maxBolus: 0,
            carbEntry: true
        )
        manager.processMessage(settings)

        // Segments
        let segment0 = IDPSegmentResponse(
            idpId: 10,
            segmentIndex: 0,
            profileStartTime: 0,
            profileBasalRate: 1000,
            profileCarbRatio: 10000,
            profileTargetBG: 110,
            profileISF: 50,
            idpStatusId: 31
        )
        manager.processMessage(segment0)

        let segment1 = IDPSegmentResponse(
            idpId: 10,
            segmentIndex: 1,
            profileStartTime: 480,
            profileBasalRate: 1200,
            profileCarbRatio: 10000,
            profileTargetBG: 110,
            profileISF: 50,
            idpStatusId: 31
        )
        manager.processMessage(segment1)
    }
}
