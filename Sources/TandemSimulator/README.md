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
- ⏳ **JPAKE Authentication**: Server-side JPAKE protocol (stub implementation)
- ⏳ **BLE Peripheral Mode**: Act as a real BLE peripheral (planned)

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

### Pairing

- `pairingCode`: Pre-set pairing code (6-digit or 16-character)
- `authenticationMode`: .jpake or .legacy

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

- ⏳ `Jpake1Request` → `Jpake1Response` (stub)
- ⏳ `Jpake2Request` → `Jpake2Response` (stub)
- ⏳ `Jpake3Request` → `Jpake3Response` (stub)
- ⏳ `Jpake4Request` → `Jpake4Response` (stub)
- ⏳ `ChallengeRequest` → `ChallengeResponse` (stub)
- ⏳ `PumpChallengeRequest` → `PumpChallengeResponse` (not implemented)

## Current Limitations

### Not Yet Implemented

1. **JPAKE Server Protocol**: Authentication handlers are stubs
   - Full JPAKE cryptographic operations needed
   - Shared secret derivation required
   - Zero-knowledge proof generation/verification

2. **Legacy Pump Challenge**: 16-character code authentication not implemented

3. **BLE Peripheral Mode**: CoreBluetooth peripheral implementation pending
   - Can only use mock transport currently
   - Need to advertise as Tandem pump
   - Handle BLE service/characteristic setup

4. **Complete Message Handlers**: Many message types return empty responses
   - Handlers exist but don't populate cargo data
   - Need to implement proper field mapping
   - Requires understanding of message cargo formats

5. **History Log Streaming**: Not implemented
   - Need to generate history entries
   - Support multi-packet streaming responses

6. **Qualifying Events**: Async notifications not implemented
   - No periodic events sent
   - No event-based notifications

7. **Control Messages**: Bolus, basal, settings changes not implemented

### Known Issues

- Message response cargo is mostly empty (returns valid structure but no data)
- No actual state changes from control messages
- No validation of message parameters
- No error responses for invalid requests

## Development Roadmap

### Phase 1: MVP (Current)

- [x] Project structure
- [x] Mock transport
- [x] Packet assembly/building
- [x] Message router
- [x] Basic status handlers (stubs)
- [x] Configuration system
- [ ] Complete JPAKE authentication
- [ ] Integration tests

### Phase 2: Full Simulator

- [ ] Complete all status message handlers
- [ ] Implement control message handlers
- [ ] BLE peripheral transport
- [ ] History log generation
- [ ] Qualifying event notifications
- [ ] State persistence

### Phase 3: Advanced Features

- [ ] Scenario library (pre-defined states)
- [ ] Scripted behaviors (time-based events)
- [ ] Multiple pump simulation
- [ ] Fuzzing and error injection
- [ ] Performance optimization

## Testing with TandemCLI

Once JPAKE authentication is fully implemented, you can test the simulator with TandemCLI:

```bash
# Terminal 1: Start simulator
.build/debug/tandem-simulator test --pairing-code 123456

# Terminal 2: Use TandemCLI (mock mode)
# Note: This requires TandemCLI to support connecting to mock transport
.build/debug/tandemkit-cli pair 123456
.build/debug/tandemkit-cli send TimeSinceResetRequest
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
