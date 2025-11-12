# TandemKit Key Files Reference

## Core Architecture Files

### Communication Layer
- **PeripheralManagerTransport** `/Sources/TandemKit/PumpManager/PeripheralManagerTransport.swift`
  - Implements PumpMessageTransport protocol
  - Handles message send/receive with packet management
  - Maintains request/response history

- **PumpComm** `/Sources/TandemKit/PumpManager/PumpComm.swift`
  - High-level pump communication API
  - Delegates to PumpCommSession
  - Manages pairing and authentication

- **PumpCommSession** `/Sources/TandemKit/PumpManager/PumpCommSession.swift`
  - Handles JPAKE and legacy pairing flows
  - Manages session state on serial queue
  - Routes incoming and outgoing messages

### Bluetooth Layer
- **BluetoothManager** `/Sources/TandemBLE/Bluetooth/BluetoothManager.swift`
  - Manages CBCentralManager
  - Handles peripheral discovery and connection
  - Implements CBCentralManagerDelegate

- **PeripheralManager** `/Sources/TandemBLE/Bluetooth/PeripheralManager.swift`
  - Manages individual peripheral connection
  - Discovers services and characteristics
  - Enables notifications
  - Implements CBPeripheralDelegate
  - **Key Extension:** `/Sources/TandemBLE/Bluetooth/PeripheralManager+TandemKit.swift`
    - sendMessagePackets()
    - readMessagePacket()
    - performSync()
    - enableNotifications()

- **BluetoothServices** `/Sources/TandemBLE/Bluetooth/BluetoothServices.swift`
  - Defines Tandem-specific BLE configuration
  - Service discovery requirements
  - Notification subscriptions
  - Value update macros

### Message Handling
- **Message** `/Sources/TandemCore/Messages/Message.swift`
  - Protocol for all pump messages
  - MessageProps structure (opCode, size, type, characteristic)

- **MessageRegistry** `/Sources/TandemCore/Messages/MessageRegistry.swift`
  - Registry of all message types (~300+ messages)
  - Request/response pair mappings
  - Message lookup by opCode, characteristic, size
  - Metadata generation

- **TronMessageWrapper** `/Sources/TandemBLE/Bluetooth/TronMessageWrapper.swift`
  - Wraps message for transmission
  - Creates packets from message
  - Manages metadata lookups

### Packet Layer
- **Packetize** `/Sources/TandemBLE/Bluetooth/Packetize.swift`
  - Converts messages to packets
  - Computes HMAC-SHA1 for signed messages
  - Calculates CRC16
  - Chunks into BLE-sized packets

- **Packet** `/Sources/TandemBLE/Bluetooth/Packet.swift`
  - Represents single BLE packet
  - Contains: packets remaining, txId, internal cargo

- **CRC16** `/Sources/TandemBLE/Bluetooth/CRC16.swift`
  - CRC16 calculation using lookup table

### Response Parsing
- **PumpResponseCollector** `/Sources/TandemBLE/Bluetooth/PumpResponseCollector.swift`
  - Accumulates packet fragments
  - Assembles into complete message
  - Handles multi-packet responses

- **BTResponseParser** `/Sources/TandemBLE/Bluetooth/BTResponseParser.swift`
  - Parses raw BLE data into typed messages
  - Validates CRC and HMAC
  - Uses MessageRegistry to decode messages

- **PacketArrayList** (in PeripheralManager.swift extension)
  - Manages packet assembly state
  - Validates packets
  - Calculates expected message size

### Notification Handling
- **PumpNotificationRouter** `/Sources/TandemKit/BLE/PumpNotificationRouter.swift`
  - Routes asynchronous pump notifications
  - Accumulates packets per characteristic/txId
  - Decodes and dispatches to PumpCommSession

### Authentication & Pairing
- **JpakeAuthBuilder** `/Sources/TandemCore/Builders/JpakeAuthBuilder.swift`
  - Manages JPAKE short-code pairing flow
  - State machine (BOOTSTRAP_INITIAL → COMPLETE)
  - 5 message roundtrips
  - Derives shared secret and server nonce

- **CentralChallengeRequestBuilder** `/Sources/TandemCore/Builders/CentralChallengeRequestBuilder.swift`
  - Builds central challenge for pump challenge pairing

- **PumpChallengeRequestBuilder** `/Sources/TandemCore/Builders/PumpChallengeRequestBuilder.swift`
  - Builds pump challenge request
  - Used for legacy (long code) pairing

- **Authentication Message Types** `/Sources/TandemCore/Messages/Authentication/`
  - Jpake1a/1b/2/3/4 request/response pairs
  - CentralChallenge request/response
  - PumpChallenge request/response

### Cryptography
- **HmacSha1** `/Sources/TandemCore/Common/HmacSha1.swift`
  - HMAC-SHA1 computation for message signing

- **HmacSha256** `/Sources/TandemCore/Builders/HmacSha256.swift`
  - HMAC-SHA256 for JPAKE confirmation

- **Hkdf** `/Sources/TandemCore/Builders/Hkdf.swift`
  - HKDF key derivation from shared secret

- **EcJpake** `/Sources/TandemCore/Builders/EcJpake.swift`
  - Elliptic Curve JPAKE implementation (via SwiftECC)

### State Management
- **PumpState** `/Sources/TandemKit/PumpManager/PumpState.swift`
  - Holds pump address, derivedSecret, serverNonce
  - RawRepresentable for persistence

- **PumpStateSupplier** `/Sources/TandemCore/Builders/PumpStateSupplier.swift`
  - Provides access to current authentication key
  - Stores pairing artifacts
  - Must be implemented by consumer

## Message Examples

### Status Messages
- `/Sources/TandemCore/Messages/CurrentStatus/`
  - PumpVersion (opCode 84/85)
  - CurrentBattery (V1 and V2)
  - CurrentBasalStatus, CurrentBolusStatus
  - PumpFeatures (V1 and V2)
  - AlertStatus, AlarmStatus
  - CGMStatus, ControlIQInfo

### Control Messages
- `/Sources/TandemCore/Messages/Control/`
  - InitiateBolus, CancelBolus
  - SetTempRate, StopTempRate
  - SetModes, ResumePumping, SuspendPumping
  - SetMaxBolusLimit, SetMaxBasalLimit
  - SetIDPSettings, etc.

### History & Logs
- `/Sources/TandemCore/Messages/HistoryLog/`
  - HistoryLogRecord, HistoryLogStream
  - Various log types: BasalDelivery, BolusRequested, etc.

### Device Information
- `/Sources/TandemCore/CharacteristicUUID.swift`
  - Device manufacturer and model characteristics
  - Used during initialization

## Protocols & Interfaces

### Transport Protocol
- **PumpMessageTransport** - Primary interface for message sending
  - Implemented by: PeripheralManagerTransport
  - Used by: PumpComm

### Delegate Protocols
- **BluetoothManagerDelegate** - Peripheral discovery/connection events
- **PeripheralManagerDelegate** - Service discovery completion
- **PeripheralManagerNotificationHandler** - Notification routing
- **PumpCommDelegate** - Pump state and message receipt
- **PumpCommSessionDelegate** - Session state changes

## Utility Files

### Common Utilities
- **Bytes** `/Sources/TandemCore/Common/Extensions/Data.swift`
  - Byte manipulation (readUint32, writeString, combine, etc.)

- **PumpLogger** `/Sources/TandemCore/Common/PumpLogger.swift`
  - Structured logging throughout system

- **OSLog** `/Sources/TandemCore/Common/OSLog.swift`
  - OS logging integration

### Configuration
- **ServiceUUID** `/Sources/TandemCore/ServiceUUID.swift`
  - BLE service UUIDs (PUMP_SERVICE, DIS_SERVICE, etc.)

- **CharacteristicUUID** `/Sources/TandemCore/CharacteristicUUID.swift`
  - All characteristic UUIDs and pretty names

## Test Files

- `/Tests/TandemCoreTests/` - Message serialization tests
- `/Tests/TandemKitTests/` - Integration tests

## Architecture Layers (Bottom to Top)

```
┌─────────────────────────────────────────┐
│  App / High-Level API                   │
├─────────────────────────────────────────┤
│  PumpComm (Public API)                  │
│  - pair()                               │
│  - sendMessage()                        │
├─────────────────────────────────────────┤
│  PumpCommSession (Session Management)   │
│  - Authentication/Pairing logic         │
├─────────────────────────────────────────┤
│  PeripheralManagerTransport (Protocol)  │
│  - Message/Response correlation         │
│  - History tracking                     │
├─────────────────────────────────────────┤
│  Packetization & Serialization          │
│  - TronMessageWrapper                   │
│  - Packetize (CRC, HMAC, chunking)      │
├─────────────────────────────────────────┤
│  PeripheralManager (BLE Operations)     │
│  - Send/receive packets                 │
│  - Notification management              │
├─────────────────────────────────────────┤
│  BluetoothManager (BLE Connection)      │
│  - Device discovery                     │
│  - Peripheral connection                │
├─────────────────────────────────────────┤
│  CBPeripheralDelegate / CBCentralManager│
│  - Raw CoreBluetooth operations         │
└─────────────────────────────────────────┘
```

## Key Concepts for Simulator

1. **Message Routing**: Use MessageRegistry to map opCodes to handlers
2. **Packet Assembly**: Reassemble multi-packet messages before decoding
3. **Authentication**: Implement JPAKE server side or accept pre-shared secrets
4. **CRC/HMAC**: Validate incoming and generate outgoing
5. **State Management**: Track authenticated sessions and pump state
6. **Async Notifications**: Queue unsolicited pump messages for async delivery

