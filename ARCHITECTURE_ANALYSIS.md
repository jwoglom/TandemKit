# TandemKit Architecture - Comprehensive Analysis

## Overview
TandemKit is a Swift framework for communicating with Tandem t:slim X2 insulin pumps over Bluetooth Low Energy (BLE). It provides a complete protocol stack for device discovery, pairing, authentication, and message exchange.

## Core Library Structure

### Three Main Libraries (from Package.swift)

1. **TandemCore**
   - Message definitions (requests/responses)
   - Message registry and metadata
   - Authentication protocols (JPAKE, pump challenge)
   - Message builders and serialization
   - Crypto utilities (HMAC, SHA256, ECC)
   - Message types: Control, Status, History, Authentication, etc.
   - Dependencies: SwiftECC, BigInt, Logging

2. **TandemBLE**
   - Bluetooth Low Energy abstraction layer
   - BluetoothManager: BLE central manager
   - PeripheralManager: Handles peripheral connection and communication
   - Message packetization (Packet, TronMessageWrapper)
   - Response parsing and packet collection
   - Characteristic and Service UUIDs

3. **TandemKit**
   - High-level pump communication API
   - PumpComm: Main pump communication interface
   - PumpCommSession: Session management for pairing/auth
   - Message transport layer
   - Pump state management
   - Integrates TandemCore and TandemBLE

### Supporting Modules

- **Bluetooth**: Base BLE abstractions for cross-platform support (Linux/iOS)
- **CoreBluetooth**: Apple CoreBluetooth wrapper
- **LoopKit**: Integration with Loop closed-loop system
- **TandemCLI**: Command-line interface for testing

---

## BLE Communication Architecture

### Bluetooth Services and Characteristics

**Services:**
- `PUMP_SERVICE` (0000fdfb-0000-1000-8000-00805f9b34fb): All pump operations
- `DIS_SERVICE` (0000180A): Device Information Service (manufacturer, model)
- `GENERIC_ATTRIBUTE_SERVICE` (00001801): Service Changed notifications

**Characteristics (in PUMP_SERVICE):**
1. **AUTHORIZATION_CHARACTERISTICS** (7B83FFF9-9F77-4E5C-8064-AAE2C24838B9)
   - Authentication messages (JPAKE, pump challenge)
   - Signed with HMAC-SHA1

2. **CURRENT_STATUS_CHARACTERISTICS** (7B83FFF6-9F77-4E5C-8064-AAE2C24838B9)
   - Pump version, battery, mode, bolus/basal status
   - Sensor/CGM information
   - Alerts and notifications

3. **CONTROL_CHARACTERISTICS** (7B83FFFC-9F77-4E5C-8064-AAE2C24838B9)
   - Signed control commands (bolus, temp rate, mode changes)
   - Requires authentication

4. **CONTROL_STREAM_CHARACTERISTICS** (7B83FFFD-9F77-4E5C-8064-AAE2C24838B9)
   - Stream-based responses to control commands
   - Used for pump state transitions

5. **HISTORY_LOG_CHARACTERISTICS** (7B83FFF8-9F77-4E5C-8064-AAE2C24838B9)
   - Pump history logs and events

6. **QUALIFYING_EVENTS_CHARACTERISTICS** (7B83FFF7-9F77-4E5C-8064-AAE2C24838B9)
   - Alarm and alert events

---

## Connection Flow

### 1. BluetoothManager (TandemBLE)

**Responsibilities:**
- Manage CBCentralManager lifecycle
- Scan for and connect to pump peripheral
- Delegate to PeripheralManager

**Key Methods:**
```swift
scanForPeripheral()          // Start scanning for pump
permanentDisconnect()        // Final disconnect
reconnectPeripheral()        // Reconnect if disconnected
```

**Delegate Methods (CBCentralManagerDelegate):**
```swift
centralManagerDidUpdateState()     // Handle BT state changes
centralManager(didDiscover)        // Found peripheral
centralManager(didConnect)         // Connected to peripheral
centralManager(didDisconnect)      // Lost connection
centralManager(didFailToConnect)   // Connection failed
```

### 2. PeripheralManager (TandemBLE)

**Responsibilities:**
- Connect to specific peripheral
- Discover services and characteristics
- Enable notifications
- Send and receive messages
- Manage command queues and locks

**Key Configuration:**
```swift
Configuration.tandemPeripheral
├── serviceCharacteristics: [Service UUID → [Characteristic UUIDs]]
├── notifyingCharacteristics: [Service UUID → [Characteristic UUIDs]]
└── valueUpdateMacros: [Characteristic UUID → (PeripheralManager) → Void]
```

**Initialization Sequence:**
1. Verify MTU ≥ 185 bytes
2. Request high-priority connection latency
3. Read manufacturer and model from DIS
4. Enable notifications on all pump characteristics
5. Signal ready to delegate

**Message Sending:**
```
PeripheralManager.sendMessagePackets()
├── Write packet data to characteristic (withResponse)
├── Wait for BLE write completion
├── Wait for pump acknowledgment
└── Return SendMessageResult
```

**Message Reception:**
- Notifications received on pump characteristics
- valueUpdateMacros add to cmdQueue
- readMessagePacket() retrieves from queue

---

## Message Architecture

### Message Types (TandemCore)

**Protocol:**
```swift
protocol Message: CustomStringConvertible {
    static var props: MessageProps { get }
    var cargo: Data { get }
    init(cargo: Data)
}

struct MessageProps {
    opCode: UInt8                      // Operation code
    size: UInt8                        // Expected payload size
    type: MessageType                  // Request or Response
    characteristic: CharacteristicUUID // Which characteristic to use
    signed: Bool                       // Requires HMAC-SHA1
    modifiesInsulinDelivery: Bool      // Affects insulin delivery
}
```

### Message Registry (TandemCore)

```swift
MessageRegistry
├── all: [MessageMetadata]  // All registered message types
├── metadata(for type)      // Get metadata for message type
├── responseMetadata(for request)  // Find response for request
├── requestMetadata(for response)  // Find request for response
└── bestMatches(opCode, characteristic, payloadLength)
```

**Example Message Pairs:**
- `PumpVersionRequest` (opCode 84) → `PumpVersionResponse` (opCode 85)
- `CurrentBatteryV1Request` → `CurrentBatteryV1Response`
- `Jpake1aRequest` → `Jpake1aResponse`
- `InitiateBolusRequest` → `InitiateBolusResponse`

---

## Packet Format and Serialization

### Packet Structure

```
┌─────────────────────────────────────────┐
│ Packet Format (sent over BLE)          │
├─────────────────────────────────────────┤
│ 1 byte: Packets Remaining (0 = last)   │
│ 1 byte: Transaction ID (TxId)          │
│ 1 byte: Opcode                         │
│ 1 byte: Transaction ID                 │
│ 1 byte: Payload Length                 │
│ N bytes: Message Cargo (opcode-specific)
│ (24 bytes HMAC-SHA1 if signed)        │
│ 2 bytes: CRC16                         │
└─────────────────────────────────────────┘
```

### Packetization Process (Packetize.swift)

1. Build message header: OpCode + TxId + Payload Length
2. Append message cargo
3. If signed:
   - Append 24 zeros for HMAC space
   - Calculate HMAC-SHA1 with auth key
   - Replace zeros with HMAC value
4. Calculate CRC16
5. Chunk into packets (18 bytes for data, 40 bytes for control)
6. Mark remaining packets in header

**Signing Flow:**
```
Message Cargo → [OpCode | TxId | Length | Cargo | TSR | 0s]
                                                      ↓
                        HMAC-SHA1(key=authKey, data) → 20 bytes HMAC
```

### TronMessageWrapper

```swift
public struct TronMessageWrapper {
    public let message: Message           // Original message
    public let requestMetadata: MessageMetadata
    public let responseMetadata: MessageMetadata?
    public let packets: [Packet]         // Ready to transmit
}
```

---

## Response Parsing

### PumpResponseCollector

Statefully accumulates packet fragments until complete message received:

```
Fragment 1 (packets remaining = 2)
     ↓
Fragment 2 (packets remaining = 1)
     ↓
Fragment 3 (packets remaining = 0) → Message complete
     ↓
BTResponseParser.decodeMessage() → Typed Message object
```

### BTResponseParser

```swift
static func parse(message, packetArrayList, output, uuid) → PumpResponseMessage?
├── Validate packet (CRC, HMAC)
├── If needs more packets: return without message
├── If complete:
│   ├── Extract opcode and payload
│   ├── Validate auth (if signed)
│   ├── Look up message type in registry
│   └── Instantiate message: type.init(cargo: payload)
└── Return PumpResponseMessage
```

---

## Communication Flow

### Synchronous Request-Response (Normal Flow)

```
PeripheralManagerTransport.sendMessage(message)
├── Create TronMessageWrapper(message, txId)
│   ├── Get requestMetadata from registry
│   ├── Get expectedResponseMetadata from registry
│   └── Packetize into [Packet]
├── Send packets via PeripheralManager.sendMessagePackets()
│   ├── Write each packet to BLE characteristic
│   └── Wait for write completion
├── Read response packets until complete
│   ├── Ingest packets into PumpResponseCollector
│   ├── Each ingests calls validatePacket() and CRC check
│   ├── When complete, decode to Message
│   └── Return decoded response message
└── Return Message
```

### Asynchronous Notifications (PumpNotificationRouter)

```
BLE Notification on Characteristic
     ↓
PeripheralManagerDelegate.peripheralManager(_:didUpdateValueFor:)
     ↓
ValueUpdateMacro adds to cmdQueue
     ↓
PumpNotificationRouter (optional)
├── Accumulate packets for each (characteristic, txId)
├── When complete:
│   ├── Decode to Message
│   └── Call PumpCommSession.handleIncoming(message)
```

---

## Authentication and Pairing

### Pairing Flows

#### 1. Short Code Pairing (JPAKE - Recommended)

**Prerequisites:** 6-digit pairing code from pump

**Sequence:**
```
Client                           Pump
   │                              │
   ├─────  Jpake1aRequest ────→   │  (165-byte challenge)
   │                              │
   │   ← Jpake1aResponse ─────────┤  (165-byte hash)
   │                              │
   ├─────  Jpake1bRequest ────→   │  (165-byte challenge)
   │                              │
   │   ← Jpake1bResponse ─────────┤  (165-byte hash)
   │                              │
   ├─────  Jpake2Request ────→    │  (165-byte challenge)
   │                              │
   │   ← Jpake2Response ──────────┤  (165-byte hash)
   │                              │
   ├─  Jpake3SessionKeyRequest──→ │
   │  [Derive shared secret]       │
   │                              │
   │ ← Jpake3SessionKeyResponse ──┤ (server nonce for auth)
   │                              │
   ├─ Jpake4KeyConfirmationReq ──→│ (HMAC(serverNonce, derived))
   │                              │
   │ ← Jpake4KeyConfirmation ──────┤ (verify response)
   │                              │
   └─── PAIRED ───────────────────┘
```

**JpakeAuthBuilder State Machine:**
```
BOOTSTRAP_INITIAL
    ↓
ROUND_1A_SENT → ROUND_1A_RECEIVED
    ↓
ROUND_1B_SENT → ROUND_1B_RECEIVED
    ↓
ROUND_2_SENT → ROUND_2_RECEIVED
    ↓
(OR CONFIRM_INITIAL)
    ↓
CONFIRM_3_SENT → CONFIRM_3_RECEIVED
    ↓
CONFIRM_4_SENT → CONFIRM_4_RECEIVED
    ↓
COMPLETE (success) or INVALID (failed)
```

**Cryptography Used:**
- ECC-JPAKE (SwiftECC library)
- HMAC-SHA256
- HKDF key derivation

#### 2. Long Code Pairing (Pump Challenge - Legacy)

**Prerequisites:** Longer alphanumeric pairing code

**Sequence:**
```
CentralChallengeRequest
  ↓
CentralChallengeResponse
  ↓
PumpChallengeRequest (includes pairing code)
  ↓
PumpChallengeResponse (success/failure)
```

### Pump State

```swift
public struct PumpState {
    public let address: UInt32        // Pump address (sometimes 0)
    public var derivedSecret: Data?   // Shared secret from JPAKE
    public var serverNonce: Data?     // Server nonce from Jpake3Response
}
```

**Persistence:**
- State stored via `PumpStateSupplier` (must provide implementation)
- Used to recover authenticated session

### Message Signing

**Signed messages require:**
1. `derivedSecret` from pairing
2. `timeSinceReset` from pump
3. HMAC-SHA1 computation

**Flow:**
```
authKey = HKDF.build(serverNonce, derivedSecret)
hmac = HMAC-SHA1(
    key: authKey,
    data: [opcode, txId, length, cargo, timeSinceReset_bytes]
)
```

---

## PumpComm: High-Level Communication API

### Main Class

```swift
public class PumpComm {
    public func pair(transport: PumpMessageTransport, pairingCode: String)
    
    public func sendMessage(transport: PumpMessageTransport, 
                           message: Message) -> Message
    
    public func sendMessage<T: Message>(transport: PumpMessageTransport,
                                       message: Message,
                                       expecting: T.Type) -> T
    
    public var isDevicePaired: Bool    // Has derivedSecret
    public var isAuthenticated: Bool   // Has derivedSecret
}
```

### PumpCommSession

```swift
public class PumpCommSession {
    public func pair(transport: PumpMessageTransport, pairingCode: String)
    
    public func runSession(withName: String, block: () -> Void)
    
    public func runSynchronously<T>(withName: String, block: () throws -> T) -> T
    
    func handleIncoming(message: Message, metadata: MessageMetadata?, 
                       characteristic: CharacteristicUUID, txId: UInt8)
}
```

---

## PeripheralManagerTransport: Concrete Transport Implementation

```swift
public final class PeripheralManagerTransport: PumpMessageTransport {
    public func sendMessage(_ message: Message) throws -> Message
    
    // History tracking for debugging
    public func getHistory() -> [RequestResponsePair]
    public func getRequestForResponse(_ response: Message) -> Message?
    public func getResponseForRequest(_ request: Message) -> Message?
    public func getPairsForRequestType(_ requestType: Message.Type) -> [RequestResponsePair]
}
```

**Key Operations:**
1. Wrap message in TronMessageWrapper
2. Increment txId
3. Send packets via PeripheralManager.performSync
4. Poll for response packets
5. Ingest into PumpResponseCollector
6. Return fully parsed Message
7. Keep RequestResponsePair history

---

## Key Interfaces and Protocols

### PumpMessageTransport

```swift
public protocol PumpMessageTransport {
    func sendMessage(_ message: Message) throws -> Message
}
```

**Implementations:**
- `PeripheralManagerTransport`: Real BLE communication
- Mock implementations for testing/simulation

### BluetoothManagerDelegate

```swift
public protocol BluetoothManagerDelegate: AnyObject {
    func bluetoothManager(_ manager: BluetoothManager,
                        peripheralManager: PeripheralManager,
                        isReadyWithError error: Error?)
    
    func bluetoothManager(_ manager: BluetoothManager,
                        shouldConnectPeripheral peripheral: CBPeripheral,
                        advertisementData: [String : Any]?) -> Bool
    
    func bluetoothManager(_ manager: BluetoothManager,
                        didCompleteConfiguration peripheralManager: PeripheralManager)
}
```

### PeripheralManagerDelegate

```swift
protocol PeripheralManagerDelegate: AnyObject {
    func completeConfiguration(for manager: PeripheralManager) throws
    func peripheralManager(_ manager: PeripheralManager,
                         didIdentifyDevice manufacturer: String,
                         model: String)
}
```

### PeripheralManagerNotificationHandler

```swift
public protocol PeripheralManagerNotificationHandler: AnyObject {
    func peripheralManager(_ manager: PeripheralManager,
                         didReceiveNotification value: Data,
                         for characteristic: CBCharacteristic)
}
```

### PumpCommDelegate

```swift
public protocol PumpCommDelegate: AnyObject {
    func pumpComm(_ pumpComms: PumpComm, didChange pumpState: PumpState)
    
    func pumpComm(_ pumpComms: PumpComm,
                 didReceive message: Message,
                 metadata: MessageMetadata?,
                 characteristic: CharacteristicUUID,
                 txId: UInt8)
}
```

---

## Error Handling

### Key Error Types

```swift
enum PeripheralManagerError: Error {
    case notReady                      // BT not ready or characteristic not found
    case emptyValue                    // Received empty data
    case timeout([CommandCondition])   // Command timed out
    case cbPeripheralError(Error)      // CoreBluetooth error
}

enum PumpCommError: Error {
    case errorResponse(response: Message)  // Got error response from pump
    case noResponse                        // No response received
    case missingAuthenticationKey          // Not yet authenticated
    case other                             // Generic error
}
```

### Validation

1. **Packet Validation**: CRC16 check
2. **HMAC Validation**: HMAC-SHA1 for signed messages
3. **Message Size Validation**: Expected size matches received

---

## Synchronization and Threading

### Queue Model

```
PeripheralManager
├── queue (main serial queue for CB operations)
│   └── Confinement: Services, characteristics, writes, reads
├── commandLock (NSCondition for command synchronization)
└── queueLock (NSCondition for packet queue)

PumpCommSession
└── sessionQueue (serial queue for session state)

PumpNotificationRouter
└── queue (utility QoS queue for async notification processing)

BluetoothManager
└── managerQueue (unspecified QoS queue for BL operations)
```

### Key Patterns

**PeripheralManager.performSync**: Call block on peripheral queue
```swift
public func performSync<T>(_ block: (_: PeripheralManager) throws -> T) -> T
```

**runConfigured**: Auto-apply configuration if needed, run block
```swift
func runConfigured<T>(_ block: (_ manager: PeripheralManager) throws -> T) throws -> T
```

---

## Configuration and State Management

### PeripheralManager.Configuration

```swift
struct Configuration {
    var serviceCharacteristics: [CBUUID: [CBUUID]]
    var notifyingCharacteristics: [CBUUID: [CBUUID]]
    var valueUpdateMacros: [CBUUID: (_ manager: PeripheralManager) -> Void]
}
```

### Tandem-Specific Configuration

```swift
.tandemPeripheral
├── Services to discover:
│   ├── PUMP_SERVICE (0000fdfb...)
│   ├── DIS_SERVICE (0000180A)
│   └── GENERIC_ATTRIBUTE_SERVICE (00001801)
├── Characteristics to enable notifications:
│   ├── All pump characteristics
│   └── SERVICE_CHANGED
└── Update macros:
    └── Add received data to cmdQueue on each value update
```

---

## Message Examples

### Query Pump Version

```swift
// Request
let request = PumpVersionRequest()
// Properties: opCode=84, size=0, type=Request, characteristic=CURRENT_STATUS

// Expected Response
// opCode=85, size=48, type=Response
// Contains: armSwVer, mspSwVer, serialNum, modelNum, etc.
```

### Initiate Bolus (Signed)

```swift
// Request
let request = InitiateBolusRequest(amount: 2.0, ...)
// Properties: signed=true, modifiesInsulinDelivery=true
// Will be HMAC-signed with derivedSecret

// Response
// opCode=87, size=1, signed=true
// Contains: success flag
```

### JPAKE Authentication (4 roundtrips)

1. **Jpake1aRequest/Response**: Client and server round 1 part A
2. **Jpake1bRequest/Response**: Client and server round 1 part B
3. **Jpake2Request/Response**: Client and server round 2
4. **Jpake3SessionKeyRequest/Response**: Derive shared secret, get server nonce
5. **Jpake4KeyConfirmationRequest/Response**: Verify both sides derived same secret

---

## Building a Simulator

### Key Components to Emulate

1. **BLE Layer**
   - Mock CBPeripheral and CBCentralManager
   - Simulate service/characteristic discovery
   - Queue incoming notifications

2. **Message Handlers**
   - Implement each message type's Request/Response
   - Maintain pump state (battery, bolus active, etc.)
   - Return appropriate responses

3. **Authentication**
   - Implement JPAKE server side (or pre-shared secret)
   - Generate server nonces
   - Verify HMAC on signed messages

4. **Packet Assembly**
   - Reassemble multi-packet messages
   - Generate valid CRC16
   - Validate incoming CRC16 and HMAC

5. **State Machine**
   - Track pump state (connected, authenticated, idle)
   - Handle concurrent requests
   - Implement timeouts

### Mock Transport

```swift
public class MockPumpMessageTransport: PumpMessageTransport {
    public func sendMessage(_ message: Message) throws -> Message {
        // Route message to handler
        // Maintain state
        // Return response
    }
}
```

---

## Summary of Data Flow

```
App
  │
  └→ PumpComm (high-level API)
     │
     └→ PumpCommSession (auth/pairing)
        │
        └→ PeripheralManagerTransport (protocol layer)
           │
           ├→ TronMessageWrapper (packetize)
           │   └→ Packetize (compute CRC/HMAC)
           │
           └→ PeripheralManager (BLE layer)
              │
              ├→ sendMessagePackets() (write to characteristic)
              │
              ├→ readMessagePacket() (read from characteristic)
              │
              └→ CBPeripheralDelegate (raw BLE notifications)
                 │
                 ├→ PumpResponseCollector (reassemble packets)
                 │
                 └→ BTResponseParser (decode to Message)
                    │
                    └→ MessageRegistry (message lookup)
                       │
                       └→ Message.init(cargo:) (instantiate)
```

