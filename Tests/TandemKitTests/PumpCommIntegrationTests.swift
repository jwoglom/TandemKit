//
//  PumpCommIntegrationTests.swift
//  TandemKit
//
//  Integration tests for pump communication covering control commands,
//  status queries, and response handling with various error scenarios.
//

import XCTest
@testable import TandemKit
@testable import TandemCore
@testable import TandemBLE
import Foundation

/// Integration tests for PumpComm message handling
///
/// These tests verify end-to-end message sending and response parsing
/// using a mock transport that simulates various pump behaviors.
final class PumpCommIntegrationTests: XCTestCase {

    // MARK: - Enhanced Mock Transport

    /// Enhanced mock transport that simulates pump responses for control and status messages
    class EnhancedMockPumpTransport: PumpMessageTransport {
        var sentMessages: [Message] = []
        var responseQueue: [Message] = []
        var shouldFail: Bool = false
        var failureError: PumpCommError = .noResponse
        var responseDelay: TimeInterval = 0

        // Track message-specific behaviors
        var suspendShouldSucceed: Bool = true
        var resumeShouldSucceed: Bool = true
        var tempBasalShouldSucceed: Bool = true
        var bolusShouldSucceed: Bool = true

        // Mock pump state
        var isSuspended: Bool = false
        var currentTempRateId: Int = 0
        var currentBasalRate: UInt32 = 1000 // 1.0 U/hr in pump units
        var batteryPercent: Int = 75
        var reservoirUnits: UInt32 = 150000 // 150 U in pump units

        func reset() {
            sentMessages.removeAll()
            responseQueue.removeAll()
            shouldFail = false
            failureError = .noResponse
            responseDelay = 0
            isSuspended = false
            currentTempRateId = 0
            suspendShouldSucceed = true
            resumeShouldSucceed = true
            tempBasalShouldSucceed = true
            bolusShouldSucceed = true
        }

        func sendMessage(_ message: Message) throws -> Message {
            sentMessages.append(message)

            if shouldFail {
                throw failureError
            }

            if responseDelay > 0 {
                Thread.sleep(forTimeInterval: responseDelay)
            }

            // Return appropriate responses based on message type

            // Control messages
            if let _ = message as? SuspendPumpingRequest {
                let status = suspendShouldSucceed ? 0 : 1
                if suspendShouldSucceed {
                    isSuspended = true
                }
                return SuspendPumpingResponse(status: status)
            }

            if let _ = message as? ResumePumpingRequest {
                let status = resumeShouldSucceed ? 0 : 1
                if resumeShouldSucceed {
                    isSuspended = false
                }
                return ResumePumpingResponse(status: status)
            }

            if let _ = message as? SetTempRateRequest {
                let status = tempBasalShouldSucceed ? 0 : 1
                if tempBasalShouldSucceed {
                    currentTempRateId += 1
                }
                return SetTempRateResponse(status: status, tempRateId: currentTempRateId)
            }

            if let _ = message as? StopTempRateRequest {
                return StopTempRateResponse(status: 0, tempRateId: currentTempRateId)
            }

            if let request = message as? InitiateBolusRequest {
                let status = bolusShouldSucceed ? 0 : 1
                let statusTypeId = bolusShouldSucceed ? 0 : 2 // 0=success, 2=revokedPriority
                return InitiateBolusResponse(
                    status: status,
                    bolusId: request.bolusID,
                    statusTypeId: statusTypeId
                )
            }

            // Status queries
            if let _ = message as? CurrentBasalStatusRequest {
                return CurrentBasalStatusResponse(
                    profileBasalRate: currentBasalRate,
                    currentBasalRate: currentBasalRate,
                    basalModifiedBitmask: 0
                )
            }

            if let _ = message as? CurrentBatteryV1Request {
                return CurrentBatteryV1Response(
                    currentBatteryAbc: batteryPercent,
                    currentBatteryIbc: batteryPercent
                )
            }

            if let _ = message as? CurrentBatteryV2Request {
                return CurrentBatteryV2Response(
                    currentBatteryAbc: batteryPercent,
                    currentBatteryIbc: batteryPercent,
                    chargingStatus: 0,
                    unknown1: 0,
                    unknown2: 0,
                    unknown3: 0,
                    unknown4: 0
                )
            }

            if let _ = message as? InsulinStatusRequest {
                return InsulinStatusResponse(
                    currentInsulinAmount: Int(reservoirUnits),
                    isEstimate: 0,
                    insulinLowAmount: 10
                )
            }

            if let _ = message as? ApiVersionRequest {
                return ApiVersionResponse(cargo: Data([0x03, 0x05, 0x00, 0x00]))
            }

            throw PumpCommError.other
        }
    }

    // MARK: - Helper Methods

    func createPumpComm() -> PumpComm {
        var pumpState = PumpState()
        // Pre-populate with pairing artifacts so we're "authenticated"
        pumpState.derivedSecret = Data(repeating: 0xAA, count: 32)
        pumpState.serverNonce = Data(repeating: 0xBB, count: 8)
        return PumpComm(pumpState: pumpState)
    }

    // MARK: - PumpComm.sendMessage() Tests

    func testSendMessageSuccessfulResponse() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()

        let request = CurrentBasalStatusRequest()
        let response = try pumpComm.sendMessage(transport: transport, message: request)

        XCTAssertTrue(response is CurrentBasalStatusResponse)
        XCTAssertEqual(transport.sentMessages.count, 1)
        XCTAssertTrue(transport.sentMessages[0] is CurrentBasalStatusRequest)
    }

    func testSendMessageWithExpectedType() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()

        let request = CurrentBasalStatusRequest()
        let response = try pumpComm.sendMessage(
            transport: transport,
            message: request,
            expecting: CurrentBasalStatusResponse.self
        )

        XCTAssertEqual(response.profileBasalRate, 1000)
        XCTAssertEqual(response.currentBasalRate, 1000)
    }

    func testSendMessageWithWrongExpectedType() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()

        let request = CurrentBasalStatusRequest()

        XCTAssertThrowsError(
            try pumpComm.sendMessage(
                transport: transport,
                message: request,
                expecting: CurrentBatteryV1Response.self // Wrong type!
            )
        ) { error in
            XCTAssertTrue(error is PumpCommError)
            if case .errorResponse = error as? PumpCommError {
                // Expected
            } else {
                XCTFail("Expected errorResponse error")
            }
        }
    }

    func testSendMessageTransportFailure() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()
        transport.shouldFail = true
        transport.failureError = .noResponse

        let request = CurrentBasalStatusRequest()

        XCTAssertThrowsError(
            try pumpComm.sendMessage(transport: transport, message: request)
        ) { error in
            guard let pumpError = error as? PumpCommError else {
                XCTFail("Expected PumpCommError")
                return
            }
            switch pumpError {
            case .noResponse:
                break // Expected
            default:
                XCTFail("Expected noResponse error, got \(pumpError)")
            }
        }
    }

    func testSendMessagePumpNotConnectedError() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()
        transport.shouldFail = true
        transport.failureError = .pumpNotConnected

        let request = CurrentBasalStatusRequest()

        XCTAssertThrowsError(
            try pumpComm.sendMessage(transport: transport, message: request)
        ) { error in
            guard let pumpError = error as? PumpCommError else {
                XCTFail("Expected PumpCommError")
                return
            }
            switch pumpError {
            case .pumpNotConnected:
                break // Expected
            default:
                XCTFail("Expected pumpNotConnected error, got \(pumpError)")
            }
        }
    }

    // MARK: - Suspend/Resume Pump Tests

    func testSuspendPumpingSuccess() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()

        let request = SuspendPumpingRequest()
        let response = try pumpComm.sendMessage(
            transport: transport,
            message: request,
            expecting: SuspendPumpingResponse.self
        )

        XCTAssertEqual(response.status, 0, "Status should indicate success")
        XCTAssertTrue(transport.isSuspended, "Mock pump should be in suspended state")
        XCTAssertEqual(transport.sentMessages.count, 1)
        XCTAssertTrue(transport.sentMessages[0] is SuspendPumpingRequest)
    }

    func testSuspendPumpingFailure() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()
        transport.suspendShouldSucceed = false

        let request = SuspendPumpingRequest()
        let response = try pumpComm.sendMessage(
            transport: transport,
            message: request,
            expecting: SuspendPumpingResponse.self
        )

        XCTAssertNotEqual(response.status, 0, "Status should indicate failure")
        XCTAssertFalse(transport.isSuspended, "Mock pump should not be suspended")
    }

    func testResumePumpingSuccess() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()
        transport.isSuspended = true // Start in suspended state

        let request = ResumePumpingRequest()
        let response = try pumpComm.sendMessage(
            transport: transport,
            message: request,
            expecting: ResumePumpingResponse.self
        )

        XCTAssertEqual(response.status, 0, "Status should indicate success")
        XCTAssertFalse(transport.isSuspended, "Mock pump should no longer be suspended")
    }

    func testResumePumpingFailure() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()
        transport.resumeShouldSucceed = false
        transport.isSuspended = true

        let request = ResumePumpingRequest()
        let response = try pumpComm.sendMessage(
            transport: transport,
            message: request,
            expecting: ResumePumpingResponse.self
        )

        XCTAssertNotEqual(response.status, 0, "Status should indicate failure")
        XCTAssertTrue(transport.isSuspended, "Mock pump should still be suspended")
    }

    func testSuspendResumeSequence() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()

        // Initially not suspended
        XCTAssertFalse(transport.isSuspended)

        // Suspend
        let suspendResponse = try pumpComm.sendMessage(
            transport: transport,
            message: SuspendPumpingRequest(),
            expecting: SuspendPumpingResponse.self
        )
        XCTAssertEqual(suspendResponse.status, 0)
        XCTAssertTrue(transport.isSuspended)

        // Resume
        let resumeResponse = try pumpComm.sendMessage(
            transport: transport,
            message: ResumePumpingRequest(),
            expecting: ResumePumpingResponse.self
        )
        XCTAssertEqual(resumeResponse.status, 0)
        XCTAssertFalse(transport.isSuspended)

        XCTAssertEqual(transport.sentMessages.count, 2)
    }

    // MARK: - Temp Basal Control Tests

    func testSetTempRateSuccess() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()

        // Set temp rate to 120% for 30 minutes
        let request = SetTempRateRequest(minutes: 30, percent: 120)
        let response = try pumpComm.sendMessage(
            transport: transport,
            message: request,
            expecting: SetTempRateResponse.self
        )

        XCTAssertEqual(response.status, 0, "Status should indicate success")
        XCTAssertEqual(response.tempRateId, 1, "Should return a temp rate ID")
        XCTAssertEqual(request.minutes, 30)
        XCTAssertEqual(request.percent, 120)
    }

    func testSetTempRateFailure() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()
        transport.tempBasalShouldSucceed = false

        let request = SetTempRateRequest(minutes: 60, percent: 50)
        let response = try pumpComm.sendMessage(
            transport: transport,
            message: request,
            expecting: SetTempRateResponse.self
        )

        XCTAssertNotEqual(response.status, 0, "Status should indicate failure")
    }

    func testStopTempRateSuccess() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()

        // First set a temp rate
        _ = try pumpComm.sendMessage(
            transport: transport,
            message: SetTempRateRequest(minutes: 30, percent: 150),
            expecting: SetTempRateResponse.self
        )

        // Then stop it
        let stopRequest = StopTempRateRequest()
        let stopResponse = try pumpComm.sendMessage(
            transport: transport,
            message: stopRequest,
            expecting: StopTempRateResponse.self
        )

        XCTAssertEqual(stopResponse.status, 0, "Status should indicate success")
    }

    func testMultipleTempRatesGetUniqueIds() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()

        // Set first temp rate
        let response1 = try pumpComm.sendMessage(
            transport: transport,
            message: SetTempRateRequest(minutes: 30, percent: 120),
            expecting: SetTempRateResponse.self
        )
        XCTAssertEqual(response1.tempRateId, 1)

        // Set second temp rate
        let response2 = try pumpComm.sendMessage(
            transport: transport,
            message: SetTempRateRequest(minutes: 60, percent: 80),
            expecting: SetTempRateResponse.self
        )
        XCTAssertEqual(response2.tempRateId, 2)

        // IDs should be unique
        XCTAssertNotEqual(response1.tempRateId, response2.tempRateId)
    }

    // MARK: - Status Query Tests

    func testQueryBasalStatus() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()
        transport.currentBasalRate = 1250 // 1.25 U/hr

        let request = CurrentBasalStatusRequest()
        let response = try pumpComm.sendMessage(
            transport: transport,
            message: request,
            expecting: CurrentBasalStatusResponse.self
        )

        XCTAssertEqual(response.currentBasalRate, 1250)
        XCTAssertEqual(response.profileBasalRate, 1250)
        XCTAssertEqual(response.basalModifiedBitmask, 0)
    }

    func testQueryBatteryV1() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()
        transport.batteryPercent = 42

        let request = CurrentBatteryV1Request()
        let response = try pumpComm.sendMessage(
            transport: transport,
            message: request,
            expecting: CurrentBatteryV1Response.self
        )

        XCTAssertEqual(response.getBatteryPercent(), 42)
    }

    func testQueryBatteryV2() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()
        transport.batteryPercent = 88

        let request = CurrentBatteryV2Request()
        let response = try pumpComm.sendMessage(
            transport: transport,
            message: request,
            expecting: CurrentBatteryV2Response.self
        )

        XCTAssertEqual(response.getBatteryPercent(), 88)
    }

    func testQueryInsulinStatus() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()
        transport.reservoirUnits = 125000 // 125 U

        let request = InsulinStatusRequest()
        let response = try pumpComm.sendMessage(
            transport: transport,
            message: request,
            expecting: InsulinStatusResponse.self
        )

        XCTAssertEqual(response.currentInsulinAmount, 125000)
    }

    func testStatusQueryPollingCycle() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()

        // Simulate a typical polling cycle that Loop would perform

        // 1. Check basal status
        let basalResponse = try pumpComm.sendMessage(
            transport: transport,
            message: CurrentBasalStatusRequest(),
            expecting: CurrentBasalStatusResponse.self
        )
        XCTAssertEqual(basalResponse.currentBasalRate, 1000)

        // 2. Check battery
        let batteryResponse = try pumpComm.sendMessage(
            transport: transport,
            message: CurrentBatteryV2Request(),
            expecting: CurrentBatteryV2Response.self
        )
        XCTAssertEqual(batteryResponse.getBatteryPercent(), 75)

        // 3. Check reservoir
        let insulinResponse = try pumpComm.sendMessage(
            transport: transport,
            message: InsulinStatusRequest(),
            expecting: InsulinStatusResponse.self
        )
        XCTAssertEqual(insulinResponse.currentInsulinAmount, 150000)

        // 4. Check API version
        let apiResponse = try pumpComm.sendMessage(
            transport: transport,
            message: ApiVersionRequest(),
            expecting: ApiVersionResponse.self
        )
        XCTAssertNotNil(apiResponse)

        // Verify all queries were sent
        XCTAssertEqual(transport.sentMessages.count, 4)
        XCTAssertTrue(transport.sentMessages[0] is CurrentBasalStatusRequest)
        XCTAssertTrue(transport.sentMessages[1] is CurrentBatteryV2Request)
        XCTAssertTrue(transport.sentMessages[2] is InsulinStatusRequest)
        XCTAssertTrue(transport.sentMessages[3] is ApiVersionRequest)
    }

    // MARK: - Bolus Tests

    func testInitiateBolusSuccess() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()

        // Request 5.0 U bolus
        let request = InitiateBolusRequest(
            totalVolume: 5000,
            bolusID: 123,
            bolusTypeBitmask: 1, // Standard bolus
            foodVolume: 3000,
            correctionVolume: 2000,
            bolusCarbs: 50,
            bolusBG: 150,
            bolusIOB: 0
        )

        let response = try pumpComm.sendMessage(
            transport: transport,
            message: request,
            expecting: InitiateBolusResponse.self
        )

        XCTAssertEqual(response.status, 0, "Bolus should succeed")
        XCTAssertEqual(response.bolusId, 123, "Should echo back bolus ID")
        XCTAssertEqual(response.statusTypeId, 0, "Status type should be success")
        XCTAssertTrue(response.wasBolusInitiated, "Bolus should be initiated")
    }

    func testInitiateBolusFailure() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()
        transport.bolusShouldSucceed = false

        let request = InitiateBolusRequest(
            totalVolume: 5000,
            bolusID: 456,
            bolusTypeBitmask: 1,
            foodVolume: 5000,
            correctionVolume: 0,
            bolusCarbs: 50,
            bolusBG: 150,
            bolusIOB: 1500
        )

        let response = try pumpComm.sendMessage(
            transport: transport,
            message: request,
            expecting: InitiateBolusResponse.self
        )

        XCTAssertNotEqual(response.status, 0, "Bolus should fail")
        XCTAssertEqual(response.statusTypeId, 2, "Status type should be revokedPriority")
        XCTAssertFalse(response.wasBolusInitiated, "Bolus should not be initiated")
    }

    func testBolusRequestProperties() throws {
        let request = InitiateBolusRequest(
            totalVolume: 10000, // 10.0 U
            bolusID: 789,
            bolusTypeBitmask: 3, // Food + correction
            foodVolume: 6000,
            correctionVolume: 4000,
            bolusCarbs: 75,
            bolusBG: 180,
            bolusIOB: 2000
        )

        XCTAssertEqual(request.totalVolume, 10000)
        XCTAssertEqual(request.bolusID, 789)
        XCTAssertEqual(request.foodVolume, 6000)
        XCTAssertEqual(request.correctionVolume, 4000)
        XCTAssertEqual(request.bolusCarbs, 75)
        XCTAssertEqual(request.bolusBG, 180)
        XCTAssertEqual(request.bolusIOB, 2000)
    }

    // MARK: - Error Recovery Tests

    func testRetryAfterFailure() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()

        // First request fails
        transport.shouldFail = true
        transport.failureError = .noResponse

        XCTAssertThrowsError(
            try pumpComm.sendMessage(transport: transport, message: CurrentBasalStatusRequest())
        )

        // Retry should work after recovery
        transport.shouldFail = false
        let response = try pumpComm.sendMessage(
            transport: transport,
            message: CurrentBasalStatusRequest(),
            expecting: CurrentBasalStatusResponse.self
        )

        XCTAssertNotNil(response)
        XCTAssertEqual(transport.sentMessages.count, 2, "Should have attempted twice")
    }

    func testMultipleErrorTypes() throws {
        let pumpComm = createPumpComm()
        let transport = EnhancedMockPumpTransport()

        // Test different error types
        let errorTypes: [PumpCommError] = [
            .pumpNotConnected,
            .noResponse,
            .missingAuthenticationKey,
            .other
        ]

        for errorType in errorTypes {
            transport.reset()
            transport.shouldFail = true
            transport.failureError = errorType

            XCTAssertThrowsError(
                try pumpComm.sendMessage(transport: transport, message: CurrentBasalStatusRequest())
            ) { error in
                XCTAssertTrue(error is PumpCommError, "Expected PumpCommError for \(errorType)")
            }
        }
    }

    // MARK: - Authentication State Tests

    func testIsDevicePaired() throws {
        let pumpState = PumpState()
        let pumpComm = PumpComm(pumpState: pumpState)

        // Initially not paired
        XCTAssertFalse(pumpComm.isDevicePaired)

        // After pairing artifacts are set
        var pairedPumpState = PumpState()
        pairedPumpState.derivedSecret = Data(repeating: 0xAA, count: 32)
        pairedPumpState.serverNonce = Data(repeating: 0xBB, count: 8)

        let pumpCommPaired = PumpComm(pumpState: pairedPumpState)
        XCTAssertTrue(pumpCommPaired.isDevicePaired)
        XCTAssertTrue(pumpCommPaired.isAuthenticated)
    }
}
