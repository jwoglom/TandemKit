# Implementation Plan: Wire TandemPump to Real BLE Transport

## Problem Statement
`TandemPump.swift` currently defines placeholder/stub implementations of `BluetoothManager` and `PeripheralManager` instead of using the **fully functional** implementations from `Sources/TandemBLE`. This blocks all actual pump communication.

## Current State Analysis

### What's Already Working ✅
- **TandemBLE module**: Complete BLE stack with:
  - `BluetoothManager`: Full scanning, connection, reconnection logic
  - `PeripheralManager`: Complete packet send/receive, characteristic management
  - `TronMessageWrapper`: Message packetization with HMAC/CRC
  - `BTResponseParser`: Response packet parsing
  - `BluetoothServices.swift`: Pre-configured `.tandemPeripheral` with all notification handlers

### What's Broken ❌
- **TandemPump.swift (lines 13-31)**: Redefines placeholder types instead of importing real ones:
  ```swift
  public protocol PeripheralManager { ... }  // STUB!
  public class BluetoothManager { ... }      // STUB!
  ```
- **TandemPump.send() (line 107-110)**: Just a TODO print statement
- **TandemPump.sendDefaultStartupRequests() (line 98-101)**: TODO
- **PumpMessageTransport**: Protocol only, no concrete implementation

## Implementation Plan

### Phase 1: Import and Wire Real BLE Types
**Goal**: Replace stub types with real implementations from TandemBLE

#### Step 1.1: Update imports in TandemPump.swift
**File**: `Sources/TandemKit/PumpManager/TandemPump.swift`

**Action**: Add TandemBLE import after line 10:
```swift
import Foundation
import CoreBluetooth
import TandemCore
import TandemBLE  // ADD THIS
```

#### Step 1.2: Remove placeholder types
**File**: `Sources/TandemKit/PumpManager/TandemPump.swift`

**Action**: Delete lines 13-31 (all placeholder protocol/class definitions)
- Remove: `public protocol PeripheralManager { ... }`
- Remove: `public protocol BluetoothManagerDelegate { ... }`
- Remove: `public class BluetoothManager { ... }`

#### Step 1.3: Update TandemPumpDelegate protocol
**File**: `Sources/TandemKit/PumpManager/TandemPump.swift`

**Action**: Update `TandemPumpDelegate` to use real TandemBLE types (line 33-36):
```swift
public protocol TandemPumpDelegate: AnyObject {
    func tandemPump(_ pump: TandemPump, shouldConnect peripheral: CBPeripheral, advertisementData: [String: Any]?) -> Bool
    func tandemPump(_ pump: TandemPump, didCompleteConfiguration peripheralManager: TandemBLE.PeripheralManager)
}
```

#### Step 1.4: Update TandemPump to use real BluetoothManager
**File**: `Sources/TandemKit/PumpManager/TandemPump.swift`

**Action**: Change line 40 from stub to real:
```swift
// OLD:
private let bluetoothManager = BluetoothManager()

// NEW:
private let bluetoothManager = TandemBLE.BluetoothManager()
```

#### Step 1.5: Update BluetoothManagerDelegate conformance
**File**: `Sources/TandemKit/PumpManager/TandemPump.swift`

**Action**: Update extension at line 113 to conform to real delegate:
```swift
extension TandemPump: TandemBLE.BluetoothManagerDelegate {
    public func bluetoothManager(_ manager: TandemBLE.BluetoothManager,
                                  peripheralManager: TandemBLE.PeripheralManager,
                                  isReadyWithError error: Error?) {
        guard error == nil else { return }
        onPumpConnected(peripheralManager)
    }

    public func bluetoothManager(_ manager: TandemBLE.BluetoothManager,
                                  shouldConnectPeripheral peripheral: CBPeripheral,
                                  advertisementData: [String : Any]?) -> Bool {
        if let delegate = delegate {
            return delegate.tandemPump(self, shouldConnect: peripheral, advertisementData: advertisementData)
        }
        return true
    }

    public func bluetoothManager(_ manager: TandemBLE.BluetoothManager,
                                  didCompleteConfiguration peripheralManager: TandemBLE.PeripheralManager) {
        delegate?.tandemPump(self, didCompleteConfiguration: peripheralManager)
    }
}
```

### Phase 2: Create Concrete PumpMessageTransport
**Goal**: Bridge PeripheralManager to PumpComm via PumpMessageTransport

#### Step 2.1: Create PeripheralManagerTransport
**File**: `Sources/TandemKit/PumpManager/PeripheralManagerTransport.swift` (NEW FILE)

**Action**: Create concrete implementation:
```swift
import Foundation
import TandemCore
import TandemBLE

@MainActor
class PeripheralManagerTransport: PumpMessageTransport {
    private let peripheralManager: TandemBLE.PeripheralManager
    private var currentTxId: UInt8 = 0

    init(peripheralManager: TandemBLE.PeripheralManager) {
        self.peripheralManager = peripheralManager
    }

    func sendMessage(_ message: Message) throws -> Message {
        // Create wrapper with current TxId
        let wrapper = TronMessageWrapper(message: message, currentTxId: currentTxId)
        currentTxId = currentTxId &+ 1 // Increment with overflow

        // Send packets via PeripheralManager
        var sendResult: SendMessageResult?
        peripheralManager.perform { manager in
            sendResult = manager.sendMessagePackets(wrapper.packets)
        }

        // Handle send errors
        switch sendResult {
        case .unsentWithError(let error):
            throw error
        case .sentWithError(let error):
            throw error
        case .sentWithAcknowledgment, .none:
            break
        }

        // Read response packet
        var responseData: Data?
        peripheralManager.perform { manager in
            responseData = try? manager.readMessagePacket()
        }

        guard let data = responseData else {
            throw PumpCommError.noResponse
        }

        // Parse response using BTResponseParser
        let characteristicUUID = type(of: message).props.characteristic.cbUUID
        guard let pumpResponse = BTResponseParser.parse(wrapper: wrapper,
                                                        output: data,
                                                        characteristic: characteristicUUID) else {
            throw PumpCommError.invalidResponse
        }

        // Get response message (currently returns RawMessage from BTResponseParser)
        guard let responseMessage = pumpResponse.message else {
            throw PumpCommError.invalidResponse
        }

        return responseMessage
    }
}

// Add error cases
extension PumpCommError {
    static let noResponse = PumpCommError.other
    static let invalidResponse = PumpCommError.other
}
```

### Phase 3: Implement TandemPump Message Sending
**Goal**: Complete the TODO methods in TandemPump

#### Step 3.1: Implement send() method
**File**: `Sources/TandemKit/PumpManager/TandemPump.swift`

**Action**: Replace lines 107-110 with:
```swift
@MainActor
private func send(_ message: Message, via manager: TandemBLE.PeripheralManager) {
    let wrapper = TronMessageWrapper(message: message, currentTxId: currentTxId)
    currentTxId = currentTxId &+ 1

    manager.perform { peripheralManager in
        let result = peripheralManager.sendMessagePackets(wrapper.packets)
        switch result {
        case .sentWithAcknowledgment:
            self.log.default("Message sent successfully: %{public}@", String(describing: message))
        case .sentWithError(let error):
            self.log.error("Message sent with error: %{public}@", String(describing: error))
        case .unsentWithError(let error):
            self.log.error("Message failed to send: %{public}@", String(describing: error))
        }
    }
}
```

#### Step 3.2: Implement sendDefaultStartupRequests()
**File**: `Sources/TandemKit/PumpManager/TandemPump.swift`

**Action**: Replace lines 98-101 with:
```swift
@MainActor
private func sendDefaultStartupRequests(_ manager: TandemBLE.PeripheralManager) {
    // Send initial status requests that Loop/Trio need
    let startupMessages: [Message] = [
        ApiVersionRequest(),
        PumpVersionRequest(),
        CurrentBatteryV2Request(),
        InsulinStatusRequest(),
        CurrentBasalStatusRequest(),
        CurrentBolusStatusRequest()
    ]

    for message in startupMessages {
        send(message, via: manager)
    }
}
```

#### Step 3.3: Update onPumpConnected to pass real PeripheralManager
**File**: `Sources/TandemKit/PumpManager/TandemPump.swift`

**Action**: Update method signature (line 94):
```swift
func onPumpConnected(_ manager: TandemBLE.PeripheralManager) {
    sendDefaultStartupRequests(manager)
}
```

#### Step 3.4: Update sendCommand to pass real PeripheralManager
**File**: `Sources/TandemKit/PumpManager/TandemPump.swift`

**Action**: Update method signature (line 103):
```swift
@MainActor
public func sendCommand(_ message: Message, using manager: TandemBLE.PeripheralManager) {
    send(message, via: manager)
}
```

### Phase 4: Wire TandemPumpManager to Transport
**Goal**: Connect TandemPumpManager to the real transport

#### Step 4.1: Update TandemPumpManager.connect()
**File**: `Sources/TandemKit/PumpManager/TandemPumpManager.swift`

**Action**: Replace lines 132-135 with:
```swift
public func connect() {
    tandemPump.startScanning()
}
```

#### Step 4.2: Update TandemPumpManager.disconnect()
**File**: `Sources/TandemKit/PumpManager/TandemPumpManager.swift`

**Action**: Replace lines 137-140 with:
```swift
public func disconnect() {
    // TODO: Call bluetoothManager.permanentDisconnect() through tandemPump
    print("TandemPumpManager: disconnect() - not yet fully implemented")
}
```

#### Step 4.3: Update pairPump to use real transport
**File**: `Sources/TandemKit/PumpManager/TandemPumpManager.swift`

**Action**: Update the pairPump method (around line 143-168) to create transport from peripheralManager:
```swift
#if canImport(UIKit)
public func pairPump(with pairingCode: String, completion: @escaping (Result<Void, Error>) -> Void) {
    do {
        let sanitizedCode = try PumpStateSupplier.sanitizeAndStorePairingCode(pairingCode)
        tandemPump.startScanning()

        // Wait for peripheralManager to be available from BluetoothManager delegate
        // This will be set when didCompleteConfiguration is called
        guard let transport = transportLock.value else {
            completion(.failure(PumpCommError.pumpNotConnected))
            return
        }

        #if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
        DispatchQueue.global(qos: .userInitiated).async { [pumpComm] in
            do {
                try pumpComm.pair(transport: transport, pairingCode: sanitizedCode)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
        #else
        completion(.failure(PumpCommError.other))
        #endif
    } catch {
        completion(.failure(error))
    }
}
#endif
```

#### Step 4.4: Update TandemPumpManager to create transport on connection
**File**: `Sources/TandemKit/PumpManager/TandemPumpManager.swift`

**Action**: Make TandemPumpManager conform to TandemPumpDelegate and create transport:
```swift
// Add this extension at the end of the file
extension TandemPumpManager: TandemPumpDelegate {
    public func tandemPump(_ pump: TandemPump,
                          shouldConnect peripheral: CBPeripheral,
                          advertisementData: [String: Any]?) -> Bool {
        // TODO: Add filtering logic if needed
        return true
    }

    @MainActor
    public func tandemPump(_ pump: TandemPump,
                          didCompleteConfiguration peripheralManager: TandemBLE.PeripheralManager) {
        // Create and store the transport
        let transport = PeripheralManagerTransport(peripheralManager: peripheralManager)
        updateTransport(transport)
    }
}
```

#### Step 4.5: Wire TandemPump delegate
**File**: `Sources/TandemKit/PumpManager/TandemPumpManager.swift`

**Action**: Uncomment and fix delegate assignment in init (lines 95-96):
```swift
public init(state: TandemPumpManagerState) {
    self.lockedState = Locked(state)
    self.tandemPump = TandemPump(state.pumpState)

    self.tandemPump.delegate = self  // UNCOMMENT AND FIX THIS
}
```

### Phase 5: Testing and Validation

#### Step 5.1: Module dependencies check
**File**: `Package.swift`

**Action**: Ensure TandemKit target depends on TandemBLE:
```swift
.target(
    name: "TandemKit",
    dependencies: ["TandemCore", "TandemBLE", "LoopKit"],  // TandemBLE must be included
    path: "Sources/TandemKit"
),
```

#### Step 5.2: Build verification
**Command**:
```bash
swift build
```

**Expected**: Should compile without errors

#### Step 5.3: Unit test updates
**Files**: Create test for PeripheralManagerTransport
- Mock PeripheralManager
- Test message send/receive flow
- Verify TxId incrementation
- Verify error handling

#### Step 5.4: Integration test
**Test**: End-to-end pairing flow
- Start scanning
- Connect to pump
- Complete pairing
- Send/receive messages

## Success Criteria
- ✅ TandemPump uses real BluetoothManager from TandemBLE
- ✅ Messages sent via PeripheralManager.sendMessagePackets()
- ✅ Responses parsed via BTResponseParser
- ✅ PumpMessageTransport concrete implementation exists
- ✅ TandemPumpManager creates transport on connection
- ✅ All placeholder types removed
- ✅ Build succeeds
- ✅ Basic message send/receive works

## Files Modified
1. `Sources/TandemKit/PumpManager/TandemPump.swift` - Remove stubs, use real BLE
2. `Sources/TandemKit/PumpManager/TandemPumpManager.swift` - Wire transport
3. `Sources/TandemKit/PumpManager/PeripheralManagerTransport.swift` - NEW FILE
4. `Package.swift` - Verify dependencies

## Risks and Mitigations
| Risk | Mitigation |
|------|------------|
| Module circular dependency | TandemBLE already imports TandemCore, TandemKit can safely import TandemBLE |
| @MainActor isolation issues | TronMessageWrapper and BTResponseParser already have @MainActor |
| Response parsing returns RawMessage | Phase 2: Extend BTResponseParser to instantiate concrete types from MessageRegistry |
| PumpStateSupplier static state | Already used by TronMessageWrapper, should work |

## Next Steps After This Plan
1. Implement response type instantiation in BTResponseParser (use MessageRegistry)
2. Implement PumpComm.sendMessage() fault handling
3. Add message dispatchers for LoopKit status updates
4. Implement TandemPumpManagerState persistence
5. Add LoopKit PumpManager conformance
