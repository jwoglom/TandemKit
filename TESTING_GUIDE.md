# TandemSimulator Testing Guide

This guide explains how to test the TandemSimulator and use it for integration testing of TandemKit.

## Quick Start

### Running Tests

```bash
# Run all simulator tests
swift test --filter TandemSimulatorTests

# Run specific test suite
swift test --filter TimeSinceResetTests
swift test --filter HomeScreenMirrorTests

# Run specific test
swift test --filter testTimeSinceResetRequest
```

### Running the Simulator

```bash
# Build the simulator
swift build --product tandem-simulator

# Run in test mode (bypass auth, mock transport)
.build/debug/tandem-simulator test

# Run with specific configuration
.build/debug/tandem-simulator test --serial TEST1234

# Run in start mode with bypass auth for testing
.build/debug/tandem-simulator start --mock-transport --bypass-auth
```

## Testing Architecture

### Bypass Authentication Mode

The simulator supports **bypass authentication** which skips JPAKE/legacy auth and auto-authenticates with a stub derived secret. This enables testing without implementing full cryptographic protocols.

**How it works:**
- `AuthMode.bypass` is set in configuration
- `SimulatorAuthProvider` auto-sets `isAuthenticated = true`
- Uses fixed derived secret: `Data(repeating: 0x42, count: 20)`
- All signed messages use this stub secret for HMAC

**When to use:**
- ✅ Integration testing
- ✅ Unit testing message handlers
- ✅ Development without real pump
- ❌ Testing actual JPAKE protocol

### Mock Transport

The `MockTransport` provides in-memory packet queues that simulate BLE communication without actual Bluetooth.

**Features:**
- Thread-safe packet queues per characteristic
- `injectPacket()` - Simulates client sending to pump
- `readResponse()` - Simulates client reading pump response
- Timeout support for async operations
- No BLE setup required

**Access in tests:**
```swift
let simulator = SimulatedPump(config: config)
try await simulator.start()

// Get mock transport
guard let transport = simulator.getMockTransport() else {
    XCTFail("Failed to get mock transport")
    return
}

// Inject packet
transport.injectPacket(packetData, on: .CURRENT_STATUS_CHARACTERISTICS)

// Read response
let response = await transport.readResponse(
    from: .CURRENT_STATUS_CHARACTERISTICS,
    timeout: 2.0
)
```

## Writing Integration Tests

### Test Structure

```swift
import XCTest
@testable import TandemSimulator
import TandemCore

class MyMessageTests: XCTestCase {
    var config: SimulatorConfig!
    var simulator: SimulatedPump!
    var transport: MockTransport!

    override func setUp() async throws {
        // Configure simulator with bypass auth
        config = SimulatorConfig()
        config.useMockTransport = true
        config.authenticationMode = .bypass

        // Customize initial state as needed
        config.cgmEnabled = true
        config.currentGlucose = 120
        config.reservoirLevel = 250.0

        // Create and start
        simulator = SimulatedPump(config: config)
        try await simulator.start()

        // Get transport
        transport = simulator.getMockTransport()!
    }

    override func tearDown() async throws {
        try await simulator.stop()
    }

    func testMyMessage() async throws {
        // Build request
        let request = PacketTestUtils.buildRequestPacket(
            opCode: myOpCode,
            txId: 1,
            cargo: Data()
        )

        // Inject
        transport.injectPacket(request, on: .CURRENT_STATUS_CHARACTERISTICS)

        // Wait for response
        let response = try await waitForResponse(
            on: .CURRENT_STATUS_CHARACTERISTICS,
            timeout: 2.0
        )

        // Parse and verify
        let parsed = try PacketTestUtils.parseResponsePacket(response)
        XCTAssertEqual(parsed.txId, 1)
        // ... more assertions
    }

    // Helper
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
```

### Packet Building Utilities

`PacketTestUtils` provides helpers for building and parsing packets:

#### Building Requests

```swift
// Simple request (no HMAC)
let packet = PacketTestUtils.buildRequestPacket(
    opCode: 56,  // HomeScreenMirrorRequest
    txId: 1,
    cargo: Data()
)

// Signed request (with HMAC)
let signedPacket = PacketTestUtils.buildSignedRequestPacket(
    opCode: 120,
    txId: 1,
    cargo: myCargoData,
    derivedSecret: derivedSecretData,
    timeSinceReset: 12345
)

// Pre-built helpers
let tsr = PacketTestUtils.buildTimeSinceResetRequest(txId: 1)
let hsm = PacketTestUtils.buildHomeScreenMirrorRequest(txId: 1)
```

#### Parsing Responses

```swift
// Parse single packet
let parsed = try PacketTestUtils.parseResponsePacket(responseData)
print("OpCode: \(parsed.opCode)")
print("TxId: \(parsed.txId)")
print("Cargo: \(parsed.cargo.hexadecimalString)")

// Parse multi-packet response
let parsed = try PacketTestUtils.parseResponsePackets([packet1, packet2, packet3])
```

#### Using Parsed Data

```swift
// Parse response and create Message object
let parsed = try PacketTestUtils.parseResponsePacket(responseData)
let message = HomeScreenMirrorResponse(cargo: parsed.cargo)

// Access message fields
XCTAssertEqual(message.cgmTrendIconId, 3)
XCTAssertTrue(message.cgmDisplayData)
```

### Modifying Pump State

You can modify pump state mid-test to verify response changes:

```swift
// Get pump state
let pumpState = simulator.getPumpState()

// Modify state
pumpState.activeBolusAmount = 5.0
pumpState.activeBolusStartTime = Date()
pumpState.controlIQEnabled = true
pumpState.reservoirLevel = 350.0
pumpState.currentGlucose = 180

// Send request - response will reflect new state
let request = PacketTestUtils.buildHomeScreenMirrorRequest(txId: 2)
transport.injectPacket(request, on: .CURRENT_STATUS_CHARACTERISTICS)
let response = await transport.readResponse(...)

// Verify response reflects modified state
let message = HomeScreenMirrorResponse(cargo: parsed.cargo)
XCTAssertEqual(message.bolusStatusIconId, 1) // Active bolus
```

## Example Tests

### TimeSinceReset Test

```swift
func testTimeSinceResetRequest() async throws {
    // Build request
    let request = PacketTestUtils.buildTimeSinceResetRequest(txId: 1)

    // Inject into simulator
    transport.injectPacket(request, on: .CURRENT_STATUS_CHARACTERISTICS)

    // Wait for response
    let response = try await waitForResponse(
        on: .CURRENT_STATUS_CHARACTERISTICS,
        timeout: 2.0
    )

    // Parse response
    let parsed = try PacketTestUtils.parseResponsePacket(response)
    XCTAssertEqual(parsed.cargo.count, 4) // UInt32

    // Extract time value
    let time = parsed.cargo.withUnsafeBytes { $0.load(as: UInt32.self) }
    XCTAssertLessThan(time, 10) // Should be <10 sec since start
}
```

### HomeScreenMirror Test

```swift
func testHomeScreenMirrorRequest() async throws {
    // Build request
    let request = PacketTestUtils.buildHomeScreenMirrorRequest(txId: 1)
    transport.injectPacket(request, on: .CURRENT_STATUS_CHARACTERISTICS)

    // Get response
    let response = try await waitForResponse(
        on: .CURRENT_STATUS_CHARACTERISTICS,
        timeout: 2.0
    )

    // Parse and verify
    let parsed = try PacketTestUtils.parseResponsePacket(response)
    XCTAssertEqual(parsed.cargo.count, 9) // 9 bytes

    // Create message and check fields
    let message = HomeScreenMirrorResponse(cargo: parsed.cargo)
    XCTAssertTrue(message.cgmDisplayData)
    XCTAssertEqual(message.cgmTrendIconId, 3) // Stable
    XCTAssertEqual(message.basalStatusIconId, 1) // Normal
}
```

### State Modification Test

```swift
func testHomeScreenMirrorWithActiveBolus() async throws {
    // Modify pump state
    let pumpState = simulator.getPumpState()
    pumpState.activeBolusAmount = 5.0
    pumpState.activeBolusStartTime = Date()

    // Send request
    let request = PacketTestUtils.buildHomeScreenMirrorRequest(txId: 2)
    transport.injectPacket(request, on: .CURRENT_STATUS_CHARACTERISTICS)

    // Get and verify response
    let response = try await waitForResponse(...)
    let parsed = try PacketTestUtils.parseResponsePacket(response)
    let message = HomeScreenMirrorResponse(cargo: parsed.cargo)

    // Verify active bolus is indicated
    XCTAssertEqual(message.bolusStatusIconId, 1)
}
```

## Testing Message Handlers

To add a new message handler and test it:

### 1. Create Handler

```swift
class MyNewHandler: MessageHandler {
    var messageType: Message.Type { MyNewRequest.self }

    func handleRequest(
        _ request: Message,
        state: PumpStateProvider,
        context: HandlerContext
    ) throws -> Message {
        // Build response from state
        let response = MyNewResponse(/* ... */)
        return response
    }
}
```

### 2. Register Handler

In `MessageRouter.registerHandlers()`:

```swift
registerHandler(MyNewHandler())
```

### 3. Write Test

```swift
func testMyNewMessage() async throws {
    // Get opCode from registry
    guard let metadata = MessageRegistry.metadata(forName: "MyNewRequest") else {
        XCTFail("Message not found")
        return
    }

    // Build request
    let request = PacketTestUtils.buildRequestPacket(
        opCode: metadata.opCode,
        txId: 1,
        cargo: myRequestCargo
    )

    // Inject and get response
    transport.injectPacket(request, on: .CURRENT_STATUS_CHARACTERISTICS)
    let response = try await waitForResponse(...)

    // Parse and verify
    let parsed = try PacketTestUtils.parseResponsePacket(response)
    let message = MyNewResponse(cargo: parsed.cargo)

    // Verify fields
    XCTAssertEqual(message.someField, expectedValue)
}
```

## Debugging

### Enable Logging

Set log level in tests:

```swift
override func setUp() async throws {
    // Enable debug logging
    SimulatorLogging.setup(level: .debug)

    // Rest of setup...
}
```

### Inspect Packets

```swift
// Print request packet
let request = PacketTestUtils.buildTimeSinceResetRequest(txId: 1)
print("Request: \(request.hexadecimalString)")

// Print response packet
let response = try await waitForResponse(...)
print("Response: \(response.hexadecimalString)")

// Parse and print fields
let parsed = try PacketTestUtils.parseResponsePacket(response)
print("OpCode: \(parsed.opCode)")
print("TxId: \(parsed.txId)")
print("Cargo: \(parsed.cargo.hexadecimalString)")
```

### Check Pump State

```swift
let pumpState = simulator.getPumpState()
print("Reservoir: \(pumpState.reservoirLevel)")
print("Battery: \(pumpState.batteryPercent)%")
print("CGM: \(pumpState.currentGlucose ?? 0) mg/dL")
print("Time since reset: \(pumpState.timeSinceReset) sec")
```

## Current Test Coverage

### Working Message Types

- ✅ **TimeSinceResetRequest** → TimeSinceResetResponse
  - Returns actual time since pump start
  - Increases over time
  - 4-byte UInt32 cargo

- ✅ **HomeScreenMirrorRequest** → HomeScreenMirrorResponse
  - Returns 9-byte status summary
  - CGM trend, bolus, basal, Control-IQ states
  - Reflects current pump state
  - All fields populated from PumpState

### Test Suites

1. **TimeSinceResetTests** (3 tests)
   - Basic request/response
   - Multiple requests with different txIds
   - Verify time increases

2. **HomeScreenMirrorTests** (4 tests)
   - Basic request/response with field validation
   - Active bolus indicator
   - Control-IQ state
   - Full reservoir indicator

## Continuous Integration

### Running in CI

```bash
# Run all tests
swift test

# Run with parallel execution
swift test --parallel

# Generate test report
swift test --enable-code-coverage
```

### Test Requirements

- No actual BLE hardware needed
- No JPAKE crypto implementation needed
- Runs entirely in-memory
- Fast execution (<1 second per test)

## Next Steps

To expand test coverage:

1. **Populate more handlers**: CurrentBasalStatus, CurrentBolusStatus, etc.
2. **Add multi-packet tests**: Test messages that span multiple packets
3. **Test signed messages**: Verify HMAC validation with bypass secret
4. **Test error cases**: Invalid opcodes, malformed packets, timeouts
5. **Performance tests**: Measure throughput, latency
6. **State persistence tests**: Save/load pump state

## Resources

- [TandemSimulator README](Sources/TandemSimulator/README.md) - Usage and configuration
- [Architecture Analysis](ARCHITECTURE_ANALYSIS.md) - Protocol deep-dive
- [Simulator Implementation Guide](SIMULATOR_IMPLEMENTATION_GUIDE.md) - Implementation patterns
- [MVP Summary](SIMULATOR_MVP_SUMMARY.md) - Current status

## Troubleshooting

### Test Times Out

```
guard let response = await transport.readResponse(...) else {
    throw TestError.responseTimeout
}
```

**Causes:**
- Simulator not started
- Wrong characteristic
- Handler not registered
- Message not in MessageRegistry

**Solutions:**
- Verify `try await simulator.start()` was called
- Check characteristic matches request/response
- Add handler to `MessageRouter.registerHandlers()`
- Verify message is in TandemCore registry

### Response OpCode Mismatch

```
XCTAssertEqual(parsed.opCode, expectedOpCode)
// Fails: Expected 57, got 0
```

**Causes:**
- Handler returning wrong message type
- Handler not found for opCode

**Solutions:**
- Check handler returns correct response type
- Verify handler is registered
- Check MessageRegistry has correct mapping

### Cargo Size Mismatch

```
XCTAssertEqual(parsed.cargo.count, 9)
// Fails: Expected 9, got 0
```

**Causes:**
- Handler not populating cargo
- Message using empty Data() constructor

**Solutions:**
- Use message's full constructor with fields
- Populate cargo correctly in handler
- Check message definition in TandemCore

## Example: Complete Test Flow

```swift
class CompleteExampleTests: XCTestCase {
    var simulator: SimulatedPump!
    var transport: MockTransport!

    override func setUp() async throws {
        // 1. Configure
        var config = SimulatorConfig()
        config.useMockTransport = true
        config.authenticationMode = .bypass
        config.cgmEnabled = true
        config.currentGlucose = 120

        // 2. Create and start
        simulator = SimulatedPump(config: config)
        try await simulator.start()
        transport = simulator.getMockTransport()!
    }

    override func tearDown() async throws {
        try await simulator.stop()
    }

    func testComplete() async throws {
        // 3. Build request
        let request = PacketTestUtils.buildHomeScreenMirrorRequest(txId: 1)

        // 4. Inject into simulator
        transport.injectPacket(request, on: .CURRENT_STATUS_CHARACTERISTICS)

        // 5. Wait for response
        guard let responseData = await transport.readResponse(
            from: .CURRENT_STATUS_CHARACTERISTICS,
            timeout: 2.0
        ) else {
            XCTFail("No response received")
            return
        }

        // 6. Parse packet
        let parsed = try PacketTestUtils.parseResponsePacket(responseData)
        XCTAssertEqual(parsed.txId, 1)

        // 7. Create message
        let response = HomeScreenMirrorResponse(cargo: parsed.cargo)

        // 8. Verify fields
        XCTAssertTrue(response.cgmDisplayData)
        XCTAssertEqual(response.cgmTrendIconId, 3)

        // 9. Modify state
        let state = simulator.getPumpState()
        state.activeBolusAmount = 5.0

        // 10. Test again with new state
        let request2 = PacketTestUtils.buildHomeScreenMirrorRequest(txId: 2)
        transport.injectPacket(request2, on: .CURRENT_STATUS_CHARACTERISTICS)
        let response2Data = await transport.readResponse(...)!
        let parsed2 = try PacketTestUtils.parseResponsePacket(response2Data)
        let response2 = HomeScreenMirrorResponse(cargo: parsed2.cargo)

        // 11. Verify state change reflected
        XCTAssertEqual(response2.bolusStatusIconId, 1) // Now has active bolus

        print("✅ Complete test flow passed!")
    }
}
```

This demonstrates the full testing workflow from setup to verification!
