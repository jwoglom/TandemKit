import XCTest
@testable import TandemSimulator
import TandemCore
import TandemBLE

/// Integration tests for basic simulator messaging
class BasicMessagingTests: XCTestCase {
    var config: SimulatorConfig!
    var simulator: SimulatedPump!
    var transport: MockTransport!

    override func setUp() async throws {
        // Create configuration for mock transport with bypass authentication
        config = SimulatorConfig()
        config.useMockTransport = true
        config.authenticationMode = .bypass // Skip authentication for basic tests

        // Optional: customize initial state
        config.cgmEnabled = true
        config.currentGlucose = 120
        config.reservoirLevel = 250.0
        config.batteryPercent = 85

        // Create simulator
        simulator = SimulatedPump(config: config)

        // Start simulator
        try await simulator.start()

        // Get reference to mock transport
        guard let mockTransport = simulator.getMockTransport() else {
            XCTFail("Failed to get mock transport")
            throw TestError.transportNotAvailable
        }
        transport = mockTransport
    }

    override func tearDown() async throws {
        if simulator != nil {
            try await simulator.stop()
        }
    }

    /// Test that simulator can start and stop
    func testSimulatorStartStop() async throws {
        // Verify pump state is accessible
        let pumpState = simulator.getPumpState()
        XCTAssertNotNil(pumpState)

        // Verify initial config values
        XCTAssertEqual(pumpState.reservoirLevel, 250.0, accuracy: 0.1)
        XCTAssertEqual(pumpState.batteryPercent, 85)
    }

    /// Test basic TimeSinceResetRequest/Response flow
    func testTimeSinceResetRequest() async throws {
        // Build request
        let request = PacketTestUtils.buildTimeSinceResetRequest(txId: 1)

        // Inject into transport
        transport.injectPacket(request, on: .CURRENT_STATUS_CHARACTERISTICS)

        // Wait for response
        let response = try await waitForResponse(
            on: .CURRENT_STATUS_CHARACTERISTICS,
            timeout: 2.0
        )

        // Parse response
        let parsed = try PacketTestUtils.parseResponsePacket(response)

        // Verify opCode and txId
        XCTAssertEqual(parsed.txId, 1, "Transaction ID should match request")

        // Verify it's a TimeSinceResetResponse (opCode 1)
        let expectedOpCode: UInt8 = 1
        XCTAssertEqual(parsed.opCode, expectedOpCode, "Should be TimeSinceResetResponse")

        // Verify cargo contains time since reset (4 bytes)
        XCTAssertEqual(parsed.cargo.count, 4, "TimeSinceResetResponse should have 4-byte cargo")

        // Create message and verify it's valid
        let message = TimeSinceResetResponse(cargo: parsed.cargo)
        XCTAssertGreaterThanOrEqual(message.pumpTimeSinceReset, 0, "Time since reset should be non-negative")
    }

    /// Test HomeScreenMirrorRequest/Response flow
    func testHomeScreenMirrorRequest() async throws {
        // Build request
        let request = PacketTestUtils.buildHomeScreenMirrorRequest(txId: 2)

        // Inject into transport
        transport.injectPacket(request, on: .CURRENT_STATUS_CHARACTERISTICS)

        // Wait for response
        let response = try await waitForResponse(
            on: .CURRENT_STATUS_CHARACTERISTICS,
            timeout: 2.0
        )

        // Parse response
        let parsed = try PacketTestUtils.parseResponsePacket(response)

        // Verify opCode and txId
        XCTAssertEqual(parsed.txId, 2, "Transaction ID should match request")

        // Verify it's a HomeScreenMirrorResponse (opCode 56)
        let expectedOpCode: UInt8 = 56
        XCTAssertEqual(parsed.opCode, expectedOpCode, "Should be HomeScreenMirrorResponse")

        // Create message and verify some fields
        let message = HomeScreenMirrorResponse(cargo: parsed.cargo)

        // Verify battery matches config
        XCTAssertEqual(message.batteryPercent, 85, "Battery should match config")

        // Verify CGM is enabled
        XCTAssertTrue(message.cgmStatusIconId > 0, "CGM should be enabled")
    }

    /// Test that multiple requests can be handled in sequence
    func testMultipleSequentialRequests() async throws {
        // Send first request
        let request1 = PacketTestUtils.buildTimeSinceResetRequest(txId: 1)
        transport.injectPacket(request1, on: .CURRENT_STATUS_CHARACTERISTICS)
        let response1 = try await waitForResponse(on: .CURRENT_STATUS_CHARACTERISTICS, timeout: 2.0)
        let parsed1 = try PacketTestUtils.parseResponsePacket(response1)
        XCTAssertEqual(parsed1.txId, 1)

        // Send second request
        let request2 = PacketTestUtils.buildHomeScreenMirrorRequest(txId: 2)
        transport.injectPacket(request2, on: .CURRENT_STATUS_CHARACTERISTICS)
        let response2 = try await waitForResponse(on: .CURRENT_STATUS_CHARACTERISTICS, timeout: 2.0)
        let parsed2 = try PacketTestUtils.parseResponsePacket(response2)
        XCTAssertEqual(parsed2.txId, 2)

        // Send third request
        let request3 = PacketTestUtils.buildTimeSinceResetRequest(txId: 3)
        transport.injectPacket(request3, on: .CURRENT_STATUS_CHARACTERISTICS)
        let response3 = try await waitForResponse(on: .CURRENT_STATUS_CHARACTERISTICS, timeout: 2.0)
        let parsed3 = try PacketTestUtils.parseResponsePacket(response3)
        XCTAssertEqual(parsed3.txId, 3)
    }

    /// Test that pump state can be modified and reflected in responses
    func testStateModificationReflectedInResponses() async throws {
        // Get initial state
        let request1 = PacketTestUtils.buildHomeScreenMirrorRequest(txId: 1)
        transport.injectPacket(request1, on: .CURRENT_STATUS_CHARACTERISTICS)
        let response1 = try await waitForResponse(on: .CURRENT_STATUS_CHARACTERISTICS, timeout: 2.0)
        let parsed1 = try PacketTestUtils.parseResponsePacket(response1)
        let message1 = HomeScreenMirrorResponse(cargo: parsed1.cargo)
        let initialBattery = message1.batteryPercent

        // Modify pump state
        let pumpState = simulator.getPumpState()
        pumpState.batteryPercent = 50

        // Get new state
        let request2 = PacketTestUtils.buildHomeScreenMirrorRequest(txId: 2)
        transport.injectPacket(request2, on: .CURRENT_STATUS_CHARACTERISTICS)
        let response2 = try await waitForResponse(on: .CURRENT_STATUS_CHARACTERISTICS, timeout: 2.0)
        let parsed2 = try PacketTestUtils.parseResponsePacket(response2)
        let message2 = HomeScreenMirrorResponse(cargo: parsed2.cargo)

        // Verify battery changed
        XCTAssertEqual(initialBattery, 85, "Initial battery should be 85")
        XCTAssertEqual(message2.batteryPercent, 50, "Battery should be updated to 50")
    }

    /// Test that requests on wrong characteristic are handled appropriately
    func testRequestOnWrongCharacteristic() async throws {
        // Try to send a status request on the control characteristic
        // This should either fail gracefully or be ignored

        let request = PacketTestUtils.buildTimeSinceResetRequest(txId: 1)

        // Inject on wrong characteristic
        transport.injectPacket(request, on: .CONTROL_CHARACTERISTICS)

        // Try to wait for response - should timeout or get no response
        let response = await transport.readResponse(from: .CONTROL_CHARACTERISTICS, timeout: 1.0)

        // We expect either no response or an error response
        // The exact behavior depends on implementation
        if let responseData = response {
            // If we got a response, parse it
            let parsed = try PacketTestUtils.parseResponsePacket(responseData)
            // It should either be an error or the message should have an error status
            print("Received response on wrong characteristic: opCode=\(parsed.opCode), txId=\(parsed.txId)")
        } else {
            // No response is also acceptable
            print("No response received on wrong characteristic (expected)")
        }
    }

    // MARK: - Helper Methods

    /// Wait for a response on a characteristic with timeout
    private func waitForResponse(
        on characteristic: CharacteristicUUID,
        timeout: TimeInterval
    ) async throws -> Data {
        guard let response = await transport.readResponse(
            from: characteristic,
            timeout: timeout
        ) else {
            throw TestError.responseTimeout
        }
        return response
    }
}

// MARK: - Test Errors

enum TestError: Error, LocalizedError {
    case transportNotAvailable
    case responseTimeout

    var errorDescription: String? {
        switch self {
        case .transportNotAvailable:
            return "Mock transport not available"
        case .responseTimeout:
            return "Timed out waiting for response"
        }
    }
}
