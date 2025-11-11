import XCTest
@testable import TandemSimulator
import TandemCore

/// Integration tests for TimeSinceReset message
class TimeSinceResetTests: XCTestCase {
    var config: SimulatorConfig!
    var simulator: SimulatedPump!
    var transport: MockTransport!

    override func setUp() async throws {
        // Create configuration with bypass auth
        config = SimulatorConfig()
        config.useMockTransport = true
        config.authenticationMode = .bypass // Skip JPAKE for testing

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

    /// Test basic TimeSinceResetRequest -> TimeSinceResetResponse flow
    func testTimeSinceResetRequest() async throws {
        // Build request packet
        let requestPacket = PacketTestUtils.buildTimeSinceResetRequest(txId: 1)

        // Inject packet into simulator (simulate client sending to pump)
        transport.injectPacket(requestPacket, on: .CURRENT_STATUS_CHARACTERISTICS)

        // Wait for response (with timeout)
        let responsePacket = try await waitForResponse(
            on: .CURRENT_STATUS_CHARACTERISTICS,
            timeout: 2.0
        )

        // Parse response
        let parsed = try PacketTestUtils.parseResponsePacket(responsePacket)

        // Verify response opCode
        guard let requestMetadata = MessageRegistry.metadata(forName: "TimeSinceResetRequest"),
              let responseMetadata = MessageRegistry.metadata(forName: "TimeSinceResetResponse") else {
            XCTFail("Message metadata not found")
            return
        }

        XCTAssertEqual(parsed.txId, 1, "Response txId should match request")
        XCTAssertEqual(parsed.opCode, responseMetadata.opCode, "Response opCode should be TimeSinceResetResponse")

        // Verify cargo contains 4 bytes (UInt32 time since reset)
        XCTAssertEqual(parsed.cargo.count, 4, "TimeSinceResetResponse cargo should be 4 bytes")

        // Parse the time value
        let timeSinceReset = parsed.cargo.withUnsafeBytes { bytes in
            bytes.load(as: UInt32.self)
        }

        // Verify time is reasonable (should be very small since we just started)
        XCTAssertLessThan(timeSinceReset, 10, "Time since reset should be less than 10 seconds")

        print("✅ TimeSinceReset test passed: \(timeSinceReset) seconds")
    }

    /// Test multiple requests with different txIds
    func testMultipleTimeSinceResetRequests() async throws {
        for txId in UInt8(1)...UInt8(5) {
            // Build and send request
            let requestPacket = PacketTestUtils.buildTimeSinceResetRequest(txId: txId)
            transport.injectPacket(requestPacket, on: .CURRENT_STATUS_CHARACTERISTICS)

            // Wait for response
            let responsePacket = try await waitForResponse(
                on: .CURRENT_STATUS_CHARACTERISTICS,
                timeout: 2.0
            )

            // Parse and verify txId matches
            let parsed = try PacketTestUtils.parseResponsePacket(responsePacket)
            XCTAssertEqual(parsed.txId, txId, "Response txId should match request txId \(txId)")
        }

        print("✅ Multiple TimeSinceReset requests test passed")
    }

    /// Test that time increases between requests
    func testTimeSinceResetIncreases() async throws {
        // First request
        let request1 = PacketTestUtils.buildTimeSinceResetRequest(txId: 1)
        transport.injectPacket(request1, on: .CURRENT_STATUS_CHARACTERISTICS)
        let response1 = try await waitForResponse(on: .CURRENT_STATUS_CHARACTERISTICS, timeout: 2.0)
        let parsed1 = try PacketTestUtils.parseResponsePacket(response1)
        let time1 = parsed1.cargo.withUnsafeBytes { $0.load(as: UInt32.self) }

        // Wait a bit
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Second request
        let request2 = PacketTestUtils.buildTimeSinceResetRequest(txId: 2)
        transport.injectPacket(request2, on: .CURRENT_STATUS_CHARACTERISTICS)
        let response2 = try await waitForResponse(on: .CURRENT_STATUS_CHARACTERISTICS, timeout: 2.0)
        let parsed2 = try PacketTestUtils.parseResponsePacket(response2)
        let time2 = parsed2.cargo.withUnsafeBytes { $0.load(as: UInt32.self) }

        // Verify time increased
        XCTAssertGreaterThan(time2, time1, "Time since reset should increase")
        XCTAssertGreaterThanOrEqual(time2 - time1, 1, "Time should increase by at least 1 second")

        print("✅ TimeSinceReset increases test passed: \(time1) -> \(time2) seconds")
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
