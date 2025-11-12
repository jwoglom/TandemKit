# TandemSimulator

A simulated Tandem insulin pump for integration testing and development without physical hardware.

## Overview

TandemSimulator provides a software implementation of a Tandem insulin pump that can be used for:
- **Integration Testing**: Test TandemKit library functionality without a real pump
- **Development**: Build and test applications using TandemKit without pump access
- **CI/CD**: Automated testing in continuous integration environments
- **Learning**: Understand the Tandem pump communication protocol

### Key Features

- ✅ **Mock Transport Layer**: In-memory packet transport for testing (no BLE required)
- ✅ **Multi-packet Assembly**: Handles fragmented messages correctly
- ✅ **CRC Validation**: Validates CRC16 checksums on incoming packets
- ✅ **HMAC Signing**: Supports HMAC-SHA1 signing for authenticated messages
- ✅ **Message Router**: OpCode-based routing to appropriate handlers
- ✅ **Configurable State**: Customize pump model, serial number, insulin levels, etc.
- ✅ **Status Message Handlers**: Responds to common status requests
- ✅ **JPAKE Authentication**: Full server-side JPAKE protocol implementation
- ✅ **Legacy Authentication**: 16-character pairing code support
- ✅ **BLE Peripheral Mode**: Act as a real BLE peripheral device
- ✅ **Integration Tests**: Comprehensive test suite for message handling

## Architecture

```
TandemSimulator
├── Core/
│   ├── SimulatedPump        # Main coordinator
│   ├── PumpState            # Simulated pump state
│   ├── SimulatorConfig      # Configuration
│   └── Protocols            # Core abstractions
├── Transport/
│   ├── MockTransport        # In-memory transport
│   ├── PacketAssembler      # Multi-packet assembly
│   └── PacketBuilder        # Response packetization
├── Messaging/
│   ├── MessageRouter        # OpCode-based routing
│   └── Handlers/
│       ├── StatusHandlers   # Status message handlers
│       └── ...
└── Authentication/
    └── SimulatorAuthProvider # JPAKE/legacy auth
```

## Usage

### Command Line

#### Start in Test Mode (Mock Transport)

```bash
# Build the simulator
swift build --product tandem-simulator

# Run in test mode (no BLE)
.build/debug/tandem-simulator test --pairing-code 123456
```

#### Configuration Options

```bash
# Start with specific pairing code
tandem-simulator test --pairing-code 123456

# Start with custom serial number
tandem-simulator start --serial SIM99999 --mock-transport

# Start in BLE peripheral mode (not yet implemented)
tandem-simulator start --pairing-code 123456
```

### Programmatic Usage

```swift
import TandemSimulator

// Create configuration
var config = SimulatorConfig()
config.useMockTransport = true
config.pairingCode = "123456"
config.serialNumber = "TEST1234"
config.reservoirLevel = 200.0
config.batteryPercent = 75

// Create and start simulator
let simulator = SimulatedPump(config: config)
try await simulator.start()

// Simulator is now running and processing messages
// Use with TandemCLI or TandemKit for testing

// Stop when done
try await simulator.stop()
```

### Integration Testing

```swift
import XCTest
@testable import TandemSimulator

class MyTests: XCTestCase {
    func testWithSimulator() async throws {
        // Create simulator
        var config = SimulatorConfig()
        config.useMockTransport = true
        let simulator = SimulatedPump(config: config)

        try await simulator.start()

        // Test your TandemKit integration
        // ...

        try await simulator.stop()
    }
}
```

## Configuration

The `SimulatorConfig` struct allows customization of the simulated pump:

### Device Identity

- `pumpModel`: Pump model (.tslimX2 or .mobi)
- `serialNumber`: Serial number (default: "SIM12345")
- `firmwareVersion`: Firmware version string (default: "7.7.0")

### Pairing & Authentication

- `pairingCode`: Pre-set pairing code (6-digit or 16-character)
- `authenticationMode`: Authentication mode
  - `.jpake` - 6-digit pairing code with full JPAKE protocol
  - `.legacy` - 16-character pairing code with HMAC-SHA1 challenge
  - `.bypass` - Skip authentication for testing (auto-authenticated)

### Initial State

- `reservoirLevel`: Insulin units (default: 250.0)
- `batteryPercent`: Battery % 0-100 (default: 85)
- `currentBasalRate`: Basal rate U/hr (default: 1.0)
- `cgmEnabled`: Enable CGM simulation (default: true)
- `currentGlucose`: Initial glucose mg/dL (default: 120)

### Transport & Behavior

- `useMockTransport`: Use in-memory transport vs BLE (default: false)
- `simulateRealisticDelays`: Add response delays (default: true)
- `responseDelayMs`: Delay in milliseconds (default: 50)

## Implemented Message Handlers

The simulator currently handles these message types:

### Status Messages (CURRENT_STATUS_CHARACTERISTICS)

- ✅ `HomeScreenMirrorRequest` → `HomeScreenMirrorResponse`
- ✅ `CurrentBasalStatusRequest` → `CurrentBasalStatusResponse`
- ✅ `CurrentBolusStatusRequest` → `CurrentBolusStatusResponse`
- ✅ `TimeSinceResetRequest` → `TimeSinceResetResponse`
- ✅ `CGMStatusRequest` → `CGMStatusResponse`
- ✅ `InsulinStatusRequest` → `InsulinStatusResponse`
- ✅ `ReminderStatusRequest` → `ReminderStatusResponse`
- ✅ `BasalIQStatusRequest` → `BasalIQStatusResponse`
- ✅ `ControlIQStatusRequest` → `ControlIQStatusResponse`
- ✅ `IDPSegmentRequest` → `IDPSegmentResponse`

### Authentication Messages (AUTHORIZATION_CHARACTERISTICS)

#### JPAKE Protocol (6-digit pairing code)
- ✅ `Jpake1aRequest` → `Jpake1aResponse` (Round 1 part A)
- ✅ `Jpake1bRequest` → `Jpake1bResponse` (Round 1 part B)
- ✅ `Jpake2Request` → `Jpake2Response` (Round 2)
- ✅ `Jpake3SessionKeyRequest` → `Jpake3SessionKeyResponse` (Session key derivation)
- ✅ `Jpake4KeyConfirmationRequest` → `Jpake4KeyConfirmationResponse` (Key confirmation)

#### Legacy Protocol (16-character pairing code)
- ✅ `CentralChallengeRequest` → `CentralChallengeResponse` (Challenge with HMAC key)
- ✅ `PumpChallengeRequest` → `PumpChallengeResponse` (HMAC-SHA1 validation)

#### Final Authentication Step
- ✅ `ChallengeRequest` → `ChallengeResponse` (Server nonce and time)

## Authentication Implementation

The simulator provides **full server-side authentication** for all Tandem pump protocols:

### JPAKE (Password Authenticated Key Exchange by Juggling)

Implements the complete EC-JPAKE protocol using elliptic curve cryptography:

- **Round 1** (Jpake1a/1b): Exchange of ephemeral public keys with zero-knowledge proofs
- **Round 2** (Jpake2): Combined key generation and verification
- **Round 3** (Jpake3): Shared secret derivation via HKDF
- **Round 4** (Jpake4): HMAC-SHA256 key confirmation

**Implementation**: `JpakeServerHandler` class in `SimulatorAuthProvider.swift`
- Uses SwiftECC library for elliptic curve operations
- Supports NIST P-256 curve
- Generates cryptographically secure random challenges
- Derives 20-byte shared secret for message signing

### Legacy Authentication (16-character pairing code)

Implements challenge-response authentication with HMAC-SHA1:

1. **Central Challenge**: Client sends 8-byte random challenge
2. **Pump Response**: Server responds with HMAC key and challenge hash
3. **Pump Challenge**: Client proves knowledge of pairing code via HMAC-SHA1
4. **Validation**: Server validates HMAC and marks session as authenticated

**Implementation**: `handleCentralChallenge()` and `handlePumpChallenge()` in `SimulatorAuthProvider.swift`

### Bypass Mode

For testing and development, bypass mode:
- Automatically marks session as authenticated on startup
- Uses fixed derived secret: `Data(repeating: 0x42, count: 20)`
- Skips all cryptographic operations
- Ideal for integration tests and rapid development

## Current Limitations

### Not Yet Implemented

1. **Complete Message Handlers**: Many message types return minimal responses
   - Most handlers exist but return basic cargo data
   - Some advanced fields not yet populated
   - Requires deeper understanding of message cargo formats

2. **History Log Streaming**: Not implemented
   - Need to generate realistic history entries
   - Support multi-packet streaming responses
   - Handle log pagination and filtering

3. **Qualifying Events**: Async notifications not implemented
   - No periodic events sent
   - No event-based notifications (e.g., alerts, alarms)
   - Need background event generation

4. **Control Messages**: Bolus, basal, settings changes partially implemented
   - Some control messages update state, others are stubs
   - Need to implement full validation logic
   - State changes should be persistent

5. **Advanced Error Handling**: Limited error responses
   - Basic error logging in place
   - Full error response construction needs completion
   - Need comprehensive validation of message parameters

### Known Issues

- Some message response cargo fields contain placeholder data
- Control messages don't always trigger appropriate state changes
- Limited validation of message parameters
- Error responses are logged but not always sent to client

## Development Roadmap

### Phase 1: MVP ✅ COMPLETE

- [x] Project structure
- [x] Mock transport
- [x] Packet assembly/building
- [x] Message router
- [x] Basic status handlers
- [x] Configuration system
- [x] Complete JPAKE authentication
- [x] Legacy pump challenge authentication
- [x] BLE peripheral transport
- [x] Integration tests

### Phase 2: Full Simulator (In Progress)

- [x] Core status message handlers (10+ messages)
- [ ] Complete all status message handlers (remaining edge cases)
- [ ] Implement control message handlers (bolus, basal, etc.)
- [ ] History log generation and streaming
- [ ] Qualifying event notifications
- [ ] State persistence
- [ ] Command-line interface improvements

### Phase 3: Advanced Features

- [ ] Scenario library (pre-defined states)
- [ ] Scripted behaviors (time-based events)
- [ ] Multiple pump simulation
- [ ] Fuzzing and error injection
- [ ] Performance optimization

## Testing with TandemCLI

You can test the simulator with TandemCLI:

```bash
# Terminal 1: Start simulator in test mode (mock transport)
.build/debug/tandem-simulator test --pairing-code 123456

# Terminal 2: Start simulator as BLE peripheral (requires real BLE)
.build/debug/tandem-simulator start --pairing-code 123456

# Using bypass authentication for development
.build/debug/tandem-simulator test --bypass-auth

# Test with integration tests
swift test --filter TandemSimulatorTests
```

### Authentication Modes

The simulator supports three authentication modes:

1. **JPAKE** (6-digit code): Full zero-knowledge proof protocol
   ```bash
   tandem-simulator test --pairing-code 123456
   ```

2. **Legacy** (16-character code): HMAC-SHA1 challenge-response
   ```bash
   tandem-simulator test --pairing-code "abcd-efgh-ijkl-mnop"
   ```

3. **Bypass** (testing): Auto-authenticated, no pairing required
   ```bash
   tandem-simulator test --bypass-auth
   ```

## Contributing

To add new message handlers:

1. Create handler class implementing `MessageHandler` protocol
2. Implement `handleRequest()` to generate appropriate response
3. Register handler in `MessageRouter.registerHandlers()`
4. Access pump state via `PumpStateProvider`
5. Add tests

Example:

```swift
class MyNewHandler: MessageHandler {
    var messageType: Message.Type { MyNewRequest.self }

    func handleRequest(
        _ request: Message,
        state: PumpStateProvider,
        context: HandlerContext
    ) throws -> Message {
        // Build response cargo
        var cargo = Data()
        // ... populate cargo ...

        return MyNewResponse(cargo: cargo)
    }
}
```

## License

Same as TandemKit parent project.

## See Also

- [TandemKit](../../) - Main library for Tandem pump communication
- [TandemCLI](../TandemCLI/) - Command-line client for pump interaction
- [Architecture Analysis](../../ARCHITECTURE_ANALYSIS.md) - Detailed protocol documentation
- [Simulator Implementation Guide](../../SIMULATOR_IMPLEMENTATION_GUIDE.md) - Implementation reference
