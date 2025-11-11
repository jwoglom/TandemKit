# Building a TandemKit Pump Simulator - Quick Start Guide

## Overview

A pump simulator needs to:
1. Accept BLE connections
2. Handle message requests
3. Implement JPAKE authentication
4. Sign responses with HMAC-SHA1
5. Manage pump state
6. Generate appropriate responses

## Quick Implementation Checklist

### 1. Mock Transport Layer

```swift
public class MockPumpTransport: PumpMessageTransport {
    private var pumpState = PumpState()
    private var messageHandlers: [String: (Message) -> Message] = [:]
    
    public func sendMessage(_ message: Message) throws -> Message {
        let messageType = String(describing: type(of: message))
        
        // Route to appropriate handler
        if let handler = messageHandlers[messageType] {
            return handler(message)
        }
        
        // Try generic routing
        return try routeMessage(message)
    }
    
    private func routeMessage(_ message: Message) throws -> Message {
        // Look up in MessageRegistry
        if let responseMeta = MessageRegistry.responseMetadata(for: message) {
            // Generate appropriate response
            return generateResponse(for: message, expectedType: responseMeta.type)
        }
        throw PumpCommError.other
    }
}
```

### 2. Implement JPAKE Server Side

The pump must respond to JPAKE messages. You have two options:

**Option A: Simple Pre-shared Secret**
```swift
func handleJpake3Request(_ request: Jpake3SessionKeyRequest) -> Jpake3SessionKeyResponse {
    // In a real implementation, complete JPAKE
    // For testing, use a pre-shared secret
    let derivedSecret = Data(count: 16)  // Your shared secret
    let serverNonce = generateNonce()
    
    return Jpake3SessionKeyResponse(
        appInstanceId: request.appInstanceId,
        deviceKeyNonce: serverNonce
    )
}
```

**Option B: Full JPAKE (Complex)**
- Implement EcJpake on server side
- Mirror the client's JpakeAuthBuilder
- Generate server messages for each client message

### 3. Message Handlers

```swift
class MessageHandlers {
    var pumpState: PumpSimulatorState
    var authKey: Data?
    
    func handle(_ message: Message) -> Message {
        switch message {
        case let m as PumpVersionRequest:
            return handlePumpVersion(m)
        case let m as InitiateBolusRequest:
            return handleInitiateBolus(m)
        case let m as CurrentBatteryV1Request:
            return handleBattery(m)
        default:
            return UnknownResponse()
        }
    }
    
    private func handlePumpVersion(_ request: PumpVersionRequest) -> PumpVersionResponse {
        return PumpVersionResponse(
            armSwVer: 0x02020000,
            mspSwVer: 0x01000000,
            configABits: 0,
            configBBits: 0,
            serialNum: 12345,
            partNum: 1,
            pumpRev: "2.0",
            pcbaSN: 1,
            pcbaRev: "A",
            modelNum: 1
        )
    }
    
    private func handleInitiateBolus(_ request: InitiateBolusRequest) -> InitiateBolusResponse {
        if let authKey = authKey {
            // Verify HMAC if message was signed
            // Update pump state
            pumpState.bolusActive = true
            pumpState.bolusAmount = request.amount
        }
        return InitiateBolusResponse(success: true)
    }
    
    private func handleBattery(_ request: CurrentBatteryV1Request) -> CurrentBatteryV1Response {
        return CurrentBatteryV1Response(
            batteryPercent: pumpState.batteryPercent,
            batteryVoltage: 350  // millivolts
        )
    }
}
```

### 4. Packet Assembly and CRC/HMAC

```swift
class ResponseBuilder {
    func buildResponse(_ message: Message, txId: UInt8) throws -> Data {
        // Get message properties
        let props = type(of: message).props
        
        // Build packet
        var packet = Data()
        packet.append(props.opCode)
        packet.append(txId)
        packet.append(UInt8(message.cargo.count))
        packet.append(message.cargo)
        
        // If signed, add HMAC
        if props.signed, let authKey = authKey {
            let hmac = HmacSha1(data: packet, key: authKey)
            packet.append(hmac)
        }
        
        // Add CRC16
        let crc = CalculateCRC16(packet)
        packet.append(crc)
        
        return packet
    }
    
    private var authKey: Data? {
        // Return authentication key after pairing
    }
}
```

### 5. Pump State Simulator

```swift
class PumpSimulatorState {
    // Connection state
    var isConnected: Bool = false
    var isAuthenticated: Bool = false
    
    // Pump state
    var batteryPercent: Int = 95
    var bolusActive: Bool = false
    var bolusAmount: Double = 0.0
    var bolusDelivered: Double = 0.0
    var basalRate: Double = 0.5
    var isSuspended: Bool = false
    var currentMode: PumpMode = .normal
    
    // Timing
    var timeSinceReset: UInt32 = 0
    var lastMessageTime: Date = Date()
    
    // Authentication
    var derivedSecret: Data?
    var serverNonce: Data?
    
    // Message tracking
    var lastTxId: UInt8 = 0
    
    enum PumpMode {
        case normal
        case tempBasal
        case suspended
        case alerting
    }
}
```

### 6. Simulate Multi-Packet Messages

```swift
// For messages requiring multiple packets
// the simulator needs to:

1. Check message size
2. If > max chunk size (18 or 40 bytes):
   - Split into multiple packets
   - Set "packets remaining" counter in first bytes
3. Each packet includes:
   - [packetsRemaining] [txId] [cargo_chunk] [crc16]

// Example: A 100-byte response in 18-byte chunks:
let response = buildResponse()  // 100 bytes
let chunks = response.chunked(into: 18)  // ~6 packets

var packets: [Data] = []
for (index, chunk) in chunks.enumerated() {
    var packet = Data()
    packet.append(UInt8(chunks.count - index - 1))  // packets remaining
    packet.append(txId)
    packet.append(contentsOf: chunk)
    
    // Add CRC for this packet
    let crc = CalculateCRC16(packet)
    packet.append(crc)
    
    packets.append(packet)
}
```

### 7. Async Notification Simulation

```swift
// Pump can send unsolicited notifications (e.g., alarm, bolus complete)

class NotificationSimulator {
    func generateAlarmNotification() -> Message {
        // Create an unsolicited alarm message
        return AlertStatusResponse(...)
    }
    
    func simulateBoluCompletion(after delay: TimeInterval) {
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            // Send CurrentBolusStatus with bolusDelivered updated
            let notification = CurrentBolusStatusResponse(...)
            self?.notificationHandler?(notification)
        }
    }
}
```

### 8. Integration with TandemKit

```swift
// Using the simulator with real TandemKit code:

let mockTransport = MockPumpTransport()
let pumpComm = PumpComm(pumpState: PumpState())

// Test pairing
do {
    try pumpComm.pair(transport: mockTransport, pairingCode: "123456")
    print("Pairing successful")
} catch {
    print("Pairing failed: \(error)")
}

// Test message sending
do {
    let request = PumpVersionRequest()
    let response = try pumpComm.sendMessage(transport: mockTransport, message: request)
    if let versionResponse = response as? PumpVersionResponse {
        print("Pump version: \(versionResponse.armSwVer)")
    }
} catch {
    print("Message failed: \(error)")
}
```

## Testing Checklist

- [ ] Simulator accepts connections
- [ ] JPAKE pairing works (generates correct nonces/secrets)
- [ ] CRC16 validation passes
- [ ] HMAC-SHA1 signing/validation works
- [ ] Multi-packet messages reassemble correctly
- [ ] All major message types respond appropriately
- [ ] Pump state updates correctly (bolus, temp rate, etc.)
- [ ] Async notifications work
- [ ] Error cases handled (invalid pairing code, timeout, etc.)

## Key Files to Reference

1. **Message Examples**: `/Sources/TandemCore/Messages/CurrentStatus/`
2. **Packetization**: `/Sources/TandemBLE/Bluetooth/Packetize.swift`
3. **CRC**: `/Sources/TandemBLE/Bluetooth/CRC16.swift`
4. **HMAC**: `/Sources/TandemCore/Common/HmacSha1.swift`
5. **JPAKE**: `/Sources/TandemCore/Builders/JpakeAuthBuilder.swift`
6. **Message Registry**: `/Sources/TandemCore/Messages/MessageRegistry.swift`

## Message Routing Strategy

```swift
// In your simulator, implement message routing like:

func handleRequest(_ request: Message, txId: UInt8) -> Message {
    let opCode = type(of: request).props.opCode
    let characteristic = type(of: request).props.characteristic
    
    // Find expected response type from registry
    guard let responseMeta = MessageRegistry.responseMetadata(for: request) else {
        throw PumpCommError.other
    }
    
    // Route based on message type
    switch request {
    case is PumpVersionRequest:
        return PumpVersionResponse(...)
    case is InitiateBolusRequest:
        return InitiateBolusResponse(...)
    // ... more cases
    default:
        // Generic handler for unknown types
        return responseMeta.type.init(cargo: Data())
    }
}
```

## Performance Considerations

1. **Packet Assembly**: Queue received packets until complete message
2. **HMAC Computation**: Only verify for signed messages
3. **State Consistency**: Ensure pump state matches responses
4. **Timing**: Add realistic delays for long operations (bolus delivery, etc.)
5. **Concurrency**: Handle multiple simultaneous requests safely

## Debugging Tips

1. **Log All Messages**: Use PumpLogger to trace message flow
2. **Validate Packets**: Print hex dumps of packets
3. **Verify CRC/HMAC**: Check calculations match expected values
4. **Trace State**: Log pump state changes
5. **Compare with Real**: If possible, compare against actual pump responses

## Common Pitfalls

1. **Byte Order**: Integers use little-endian
2. **HMAC Key Derivation**: Must use HKDF with correct nonce
3. **CRC16**: Uses specific lookup table (see CRC16.swift)
4. **Packet Chunking**: Different sizes for data (18) vs control (40)
5. **TxId Management**: Must increment for each message
6. **Signed Messages**: Add HMAC before CRC
7. **Multi-Packet**: "Packets remaining" counts down, not up

