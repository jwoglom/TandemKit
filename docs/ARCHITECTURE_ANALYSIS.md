# TandemKit architecture

TandemKit is a LoopKit `PumpManager` for the Tandem t:slim X2 and Mobi, talking to the pump over
Bluetooth LE. The protocol is ported from [pumpX2](https://github.com/jwoglom/pumpX2); where
TandemKit deliberately departs from it, the code says so at the point of departure.

The rules that are easy to break are in [AGENTS.md](../AGENTS.md). The faketandem integration
harness is described in [integration-harness.md](integration-harness.md).

## Build layout

`TandemKit.xcodeproj` is the supported build. It compiles `Sources/TandemCore`,
`Sources/TandemKit` and `Sources/TandemKitUI` into a single `TandemKit` framework, and the sources
rely on that: they reference each other without imports, and every test does
`@testable import TandemKit`. `Package.swift` is the Linux build; see the comment at its top and
[LinuxShims/README.md](../LinuxShims/README.md).

## Layers

```
LoopKit host (Trio / Loop)
  │  PumpManager, PumpManagerUI, Alert, hasNewPumpEvents
  ▼
TandemPumpManager  (and its + extensions, one per concern)
  │  state: TandemPumpManagerState  →  rawState, persisted by the host
  │  history: HistoryBackfillCoordinator → HistoryLogFetcher → HistoryLogStore
  ▼
PumpBluetoothConnection           ← StubPumpBluetooth in unit tests
  └─ TandemBluetoothManager       CBCentralManager, the command queue, connect and reconnect
       └─ TandemPeripheralManager CBPeripheral, session setup, write/response, notification routing
            ├─ Packetize          request → signed, CRC'd packets
            ├─ PacketAssembler    packets → one checked message, by txId and countdown
            ├─ BTResponseParser   message → typed response via MessageRegistry
            └─ JpakeAuthBuilder   pairing and per-connection authentication
  ▼
CoreBluetooth                     ← VirtualPump/ shims under TANDEMKIT_VIRTUAL_PUMP
```

Everything above `PumpBluetoothConnection` (the manager, its extensions, `HistoryLogFetcher` and
the UI view models) reaches the pump only through that protocol.

## Concurrency

`TandemBluetoothManager` runs every connect attempt and every command job on one serial
`commandQueue`. `ensureConnected(completion:)` connects if needed and then runs `completion` on
that queue. `write(_:)` blocks until the response arrives, so it must only be called from inside
an `ensureConnected` job. Serializing everything on one queue is what keeps a loop command, a
sync and a qualifying-event fetch from interleaving on the write path.

A connect attempt waits on a semaphore with a timeout rather than a timer on the command queue, so
a blocked queue cannot starve it. `TandemPumpManager.watchdogQueue` is separate from the command
queue for the same reason: a wedged command cannot starve its own watchdog.

`TandemPeripheralManager.performInitialSetup` runs on a global queue once service discovery
finishes, while `connectIfNeeded` is still parked in its wait, so nothing else can be writing.
Qualifying events that arrive before the session is up are acknowledged and held, then handled
once it is.

Each BLE operation waits on its own `TandemDispatchGroup`. Disconnecting or losing Bluetooth
cancels these waits, so a blocked write returns at once instead of waiting out its timeout.

`TandemPumpManagerState` is read and written by the command queue, the notification path and the
host, behind `stateLock`, a recursive lock.

## Test seams

`TandemClock` with `ManualClock`: every time-based decision reads `TandemPumpManager.clock`, so a
test moves time without waiting.
