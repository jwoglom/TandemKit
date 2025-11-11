import XCTest
@testable import TandemSimulator
import TandemCore

/// Integration tests for HomeScreenMirror message
class HomeScreenMirrorTests: XCTestCase {
    var config: SimulatorConfig!
    var simulator: SimulatedPump!
    var transport: MockTransport!

    override func setUp() async throws {
        // Create configuration with bypass auth
        config = SimulatorConfig()
        config.useMockTransport = true
        config.authenticationMode = .bypass
        config.cgmEnabled = true
        config.currentGlucose = 120
        config.reservoirLevel = 250.0
        config.batteryPercent = 85
        config.controlIQEnabled = false

        // Create and start simulator
        simulator = SimulatedPump(config: config)
        try await simulator.start()

        // Get mock transport reference
        guard let mockTransport = simulator.getMockTransport() else {
            XCTFail("Failed to get mock transport")
            return
        }
        transport = mockTransport
    }

    override func tearDown() async throws {
        if simulator != nil {
            try await simulator.stop()
        }
    }

    /// Test HomeScreenMirrorRequest -> HomeScreenMirrorResponse flow
    func testHomeScreenMirrorRequest() async throws {
        // Build request packet
        let requestPacket = PacketTestUtils.buildHomeScreenMirrorRequest(txId: 1)

        // Inject packet into simulator
        transport.injectPacket(requestPacket, on: .CURRENT_STATUS_CHARACTERISTICS)

        // Wait for response
        let responsePacket = try await waitForResponse(
            on: .CURRENT_STATUS_CHARACTERISTICS,
            timeout: 2.0
        )

        // Parse response
        let parsed = try PacketTestUtils.parseResponsePacket(responsePacket)

        // Verify response opCode
        guard let responseMetadata = MessageRegistry.metadata(forName: "HomeScreenMirrorResponse") else {
            XCTFail("HomeScreenMirrorResponse metadata not found")
            return
        }

        XCTAssertEqual(parsed.txId, 1, "Response txId should match request")
        XCTAssertEqual(parsed.opCode, responseMetadata.opCode, "Response opCode should be HomeScreenMirrorResponse")

        // Verify cargo size (should be 9 bytes per message definition)
        XCTAssertEqual(parsed.cargo.count, 9, "HomeScreenMirrorResponse cargo should be 9 bytes")

        // Parse the response message
        let response = HomeScreenMirrorResponse(cargo: parsed.cargo)

        // Verify CGM data is available (we configured CGM enabled with glucose value)
        XCTAssertTrue(response.cgmDisplayData, "CGM display data should be available")

        // Verify CGM trend (should be stable=3 by default)
        XCTAssertEqual(response.cgmTrendIconId, 3, "CGM trend should be stable (3)")

        // Verify no active bolus
        XCTAssertEqual(response.bolusStatusIconId, 0, "No active bolus")

        // Verify normal basal
        XCTAssertEqual(response.basalStatusIconId, 1, "Normal basal")

        // Verify Control-IQ state (disabled)
        XCTAssertEqual(response.apControlStateIconId, 0, "Control-IQ should be disabled")

        // Verify insulin level (250.0 units, not > 300)
        XCTAssertFalse(response.remainingInsulinPlusIcon, "Reservoir not at max level")

        print("✅ HomeScreenMirror test passed")
        print("   CGM Trend: \(response.cgmTrendIconId)")
        print("   Bolus Status: \(response.bolusStatusIconId)")
        print("   Basal Status: \(response.basalStatusIconId)")
        print("   Control-IQ: \(response.apControlStateIconId)")
        print("   CGM Data: \(response.cgmDisplayData)")
    }

    /// Test with different pump configurations
    func testHomeScreenMirrorWithActiveBolus() async throws {
        // Modify pump state to have active bolus
        let pumpState = simulator.getPumpState()
        pumpState.activeBolusAmount = 5.0
        pumpState.activeBolusStartTime = Date()

        // Send request
        let requestPacket = PacketTestUtils.buildHomeScreenMirrorRequest(txId: 2)
        transport.injectPacket(requestPacket, on: .CURRENT_STATUS_CHARACTERISTICS)

        // Get response
        let responsePacket = try await waitForResponse(
            on: .CURRENT_STATUS_CHARACTERISTICS,
            timeout: 2.0
        )
        let parsed = try PacketTestUtils.parseResponsePacket(responsePacket)
        let response = HomeScreenMirrorResponse(cargo: parsed.cargo)

        // Verify active bolus is indicated
        XCTAssertEqual(response.bolusStatusIconId, 1, "Active bolus should be indicated")

        print("✅ HomeScreenMirror with active bolus test passed")
    }

    /// Test with Control-IQ enabled
    func testHomeScreenMirrorWithControlIQ() async throws {
        // Enable Control-IQ
        let pumpState = simulator.getPumpState()
        pumpState.controlIQEnabled = true

        // Send request
        let requestPacket = PacketTestUtils.buildHomeScreenMirrorRequest(txId: 3)
        transport.injectPacket(requestPacket, on: .CURRENT_STATUS_CHARACTERISTICS)

        // Get response
        let responsePacket = try await waitForResponse(
            on: .CURRENT_STATUS_CHARACTERISTICS,
            timeout: 2.0
        )
        let parsed = try PacketTestUtils.parseResponsePacket(responsePacket)
        let response = HomeScreenMirrorResponse(cargo: parsed.cargo)

        // Verify Control-IQ is indicated
        XCTAssertEqual(response.apControlStateIconId, 1, "Control-IQ should be enabled")

        print("✅ HomeScreenMirror with Control-IQ test passed")
    }

    /// Test with full reservoir
    func testHomeScreenMirrorWithFullReservoir() async throws {
        // Set reservoir to max
        let pumpState = simulator.getPumpState()
        pumpState.reservoirLevel = 350.0

        // Send request
        let requestPacket = PacketTestUtils.buildHomeScreenMirrorRequest(txId: 4)
        transport.injectPacket(requestPacket, on: .CURRENT_STATUS_CHARACTERISTICS)

        // Get response
        let responsePacket = try await waitForResponse(
            on: .CURRENT_STATUS_CHARACTERISTICS,
            timeout: 2.0
        )
        let parsed = try PacketTestUtils.parseResponsePacket(responsePacket)
        let response = HomeScreenMirrorResponse(cargo: parsed.cargo)

        // Verify full reservoir is indicated
        XCTAssertTrue(response.remainingInsulinPlusIcon, "Full reservoir should be indicated")

        print("✅ HomeScreenMirror with full reservoir test passed")
    }

    // MARK: - Helpers

    private func waitForResponse(
        on characteristic: CharacteristicUUID,
        timeout: TimeInterval
    ) async throws -> Data {
        guard let response = await transport.readResponse(from: characteristic, timeout: timeout) else {
            throw TestError.responseTimeout
        }
        return response
    }
}

enum TestError: Error {
    case responseTimeout
}
