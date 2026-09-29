# TandemKit architecture

TandemKit is a LoopKit `PumpManager` for the Tandem t:slim X2 and Mobi, talking to the pump over
Bluetooth LE. The protocol is ported from [pumpX2](https://github.com/jwoglom/pumpX2); where
TandemKit deliberately departs from it, the code says so at the point of departure.

File-level pointers are in [KEY_FILES_REFERENCE.md](KEY_FILES_REFERENCE.md). The faketandem
integration harness is described in [integration-harness.md](integration-harness.md).

## Build layout

`TandemKit.xcodeproj` is the supported build. It compiles `Sources/TandemCore`,
`Sources/TandemKit` and `Sources/TandemKitUI` into a single `TandemKit` framework, and the sources
rely on that: they reference each other without imports, and every test does
`@testable import TandemKit`. `Sources/TandemKitPlugin` builds a Loop-style plugin bundle that
nothing currently uses. Trio links the framework directly.

LoopKit and LoopKitUI are not package dependencies. The project links them from
`BUILT_PRODUCTS_DIR`, so another project in the same workspace has to build them, and it must be
the `loopandlearn/LoopKit` fork Trio uses. Upstream LoopKit has no `Pluggable`.

`Package.swift` has two halves:

- **Apple.** It describes four targets but cannot compile them, because LoopKit is missing and the
  module split does not match the code. The comment at the top of the manifest explains this.
- **Linux.** `Sources/TandemCore` and `Sources/TandemKit` compile into one module named
  `TandemKit`, against the fakes in `LinuxShims/` (LoopKit, HealthKit, CoreBluetooth, Combine).
  SwiftECC and BigInt do not build on Linux, so the JPAKE provider there is a stub that traps.
  Fresh pairing therefore cannot run on Linux; everything that starts from a stored derived
  secret can. `TandemKitUI` is SwiftUI and is not built on Linux.

## Layers

```
LoopKit host (Trio / Loop)
  │  PumpManager, PumpManagerUI, Alert, hasNewPumpEvents
  ▼
TandemPumpManager  (+Alerts, +StateSync, +SyncBasal, +Onboarding, +HistoryStore, +HistoryDoseReporting)
  │  state: TandemPumpManagerState  →  rawState, persisted by the host
  │  history: HistoryBackfillCoordinator → HistoryLogFetcher → HistoryLogStore
  ▼
PumpBluetoothConnection           ← StubPumpBluetooth in unit tests
  └─ TandemBluetoothManager       CBCentralManager, the command queue, connect and reconnect
       └─ TandemPeripheralManager CBPeripheral, session setup, write/response, notification routing
            ├─ Packetize          request → signed, CRC'd packets
            ├─ BTResponseParser   packets → typed response via MessageRegistry
            └─ JpakeAuthBuilder   pairing and per-connection authentication
  ▼
CoreBluetooth                     ← VirtualPump/ shims under TANDEMKIT_VIRTUAL_PUMP
```

Everything above `PumpBluetoothConnection` (the manager, its extensions, `HistoryLogFetcher` and
the UI view models) reaches the pump only through that protocol. Production uses
`init(state:)`, which builds a `TandemBluetoothManager`. Tests use `init(state:bluetooth:)` with
`StubPumpBluetooth`.

## Bluetooth surface

| Service | UUID | Use |
| --- | --- | --- |
| Pump | `0000fdfb-0000-1000-8000-00805f9b34fb` | Every pump message |
| Device Information | `0000180A-…` | Manufacturer and model number, read once during setup |
| Generic Attribute | `00001801-…` | Service Changed |
| Tandem Device Update | `0000fdfa-…` | Discovered but unused |

| Characteristic (Pump service) | UUID prefix | Carries |
| --- | --- | --- |
| `AUTHORIZATION` | `7B83FFF9` | JPAKE and challenge messages |
| `CURRENT_STATUS` | `7B83FFF6` | Status requests/responses, and `ErrorResponse` |
| `QUALIFYING_EVENTS` | `7B83FFF7` | Unsolicited 4-byte event bitmasks |
| `HISTORY_LOG` | `7B83FFF8` | Unsolicited `HistoryLogStreamResponse` only |
| `CONTROL` | `7B83FFFC` | Signed commands |
| `CONTROL_STREAM` | `7B83FFFD` | Unsolicited progress streams for cartridge, tubing and cannula operations |

All six are subscribed for notifications during setup. They share the suffix
`-9F77-4E5C-8064-AAE2C24838B9`.

## Connection lifecycle

### Command queue

`TandemBluetoothManager` runs every connect attempt and every command job on one serial
`commandQueue`. `ensureConnected(completion:)` connects if needed and then runs `completion` on
that queue. `write(_:)` blocks until the response arrives, so it must only be called from inside
an `ensureConnected` job. Serializing everything on one queue is what keeps a loop command, a
sync and a qualifying-event fetch from interleaving on the write path.

`connectIfNeeded` tries three paths in turn:

1. Reconnect the cached `CBPeripheral`.
2. Adopt a pump that iOS already reports as connected (`retrieveConnectedPeripherals`).
3. Scan for the pump's stored `peripheralUuid`.

After two consecutive failures it discards the cached references and goes straight to scanning.
Each attempt is bounded by `connectTimeout` (30 s). The wait is a semaphore with a timeout rather
than a timer on the command queue, so a blocked queue cannot starve it.

After an unexpected disconnect, or when Bluetooth comes back on, the manager reconnects on its own
unless the pump has been deactivated. A reconnect restores the session but does not sync or report
to the host; nothing reaches the host until the next `ensureCurrentPumpData` (#351).

### Session setup

`TandemPeripheralManager.performInitialSetup` runs on a global queue once service discovery
finishes. `connectIfNeeded` is still parked in its wait at that point, so nothing else can be
writing. The steps are:

1. Ask for low connection latency. This is an optimisation only.
2. Read the DIS manufacturer and model number.
3. Enable notifications on all six pump characteristics.
4. Authenticate with JPAKE (next section).
5. Send `TimeSinceResetRequest`. Its value is part of every signature.
6. Set `state.isConnected`, mark the session established, and complete the connect attempt.

Qualifying events that arrive before step 6 are acknowledged and held, then handled once the
session is up.

## Authentication

Pairing uses the 6-digit code shown on the pump. `JpakeAuthBuilder` has two starting points:

| Situation | Rounds sent |
| --- | --- |
| No derived secret (first pairing) | `Jpake1a` → `Jpake1b` → `Jpake2` → `Jpake3SessionKey` → `Jpake4KeyConfirmation` |
| Stored derived secret (every later connection) | `Jpake3SessionKey` → `Jpake4KeyConfirmation` |

Round 1 is two length-prefixed `(point, ZKP)` groups sent as the `1a` and `1b` frames. Each ZKP
scalar drops its leading zero bytes, so a group is 165 bytes only about 255/256 of the time.
`JpakeRound1Framing` splits on the real group boundary and right-pads each frame to 165 bytes,
which is safe because the pump's parser is length-prefixed. The receive side strips the pump's
padding before reassembling. pumpX2 slices at fixed offsets and still misaligns its `1b` frame
when the first scalar is short.

A successful exchange yields `derivedSecret` and `serverNonce`, which are stored in `PumpState`
along with `peripheralUuid` and the pairing code. The signing key is
`Hkdf.build(nonce: serverNonce, keyMaterial: derivedSecret)` (`PumpState.getAuthKey()`).

The legacy 16-character pump-challenge pairing is not implemented. `CentralChallenge` and
`PumpChallenge` exist as message types and have serialization tests, but no builder or flow uses
them.

SwiftECC is slow on its first curve operation because it warms up `Domain.instance`. This is one
reason setup runs off the main thread.

## Wire format

### Sending (`Packetize.parse`)

```
[opCode][txId][payloadLength][cargo…]                        unsigned
[opCode][txId][payloadLength][cargo…][TSR:4][HMAC-SHA1:20]   signed (payloadLength includes the 24)
                                                          + [CRC16:2]
```

For a signed message, the 4 bytes after the cargo hold `timeSinceReset` (little-endian), and the
HMAC-SHA1 over everything before it is keyed with the auth key. A CRC-16 (CCITT table) is
appended, and the result is chunked. Each chunk goes out as `[packetsRemaining][txId][chunk]`.
Chunks are 18 bytes by default and 40 bytes for control requests; any signed message uses at
least 40. `txId` increments with each write and wraps.

Each chunk is written with response. `TandemPeripheralManager.writeUntyped` waits up to 2 s for
each write acknowledgement, then up to `responseTimeout` (30 s) for the reply. The timeout is
sized for `EnterChangeCartridgeMode`, which can take 20 s to answer; timing out early would invite
re-sending an insulin-affecting request.

### Receiving (`BTResponseParser.parse`)

Reassembly is driven by the low nibble of the first byte (packets remaining), never by fragment
length. The first packet's opcode is at byte 2 and its cargo starts at byte 5; continuation
packets carry cargo from byte 2. Once complete, the opcode and characteristic select the response
type in `MessageRegistry.findResponse`. A fixed-size message whose cargo is shorter than
`props.size` is dropped rather than parsed, because the parsers slice at fixed offsets and would
trap. JPAKE responses are allowed a short scalar.

Neither the CRC nor the HMAC of a received message is verified. The assembled cargo still has the
CRC (and, for signed responses, the 24-byte trailer) on the end; the parsers ignore those bytes.

When the pump refuses a request, it sends an `ErrorResponse` on `CURRENT_STATUS` naming the
refused opcode. The waiting write ends immediately and returns `nil`, the same result as a
timeout.

### Notification routing

`TandemPeripheralManager.peripheral(_:didUpdateValueFor:)` routes each notification in this
order:

1. A pending characteristic read (DIS during setup).
2. `HISTORY_LOG`: reassembled and published on `pumpManager.historyLogStream`. This is checked
   before the pending write so a continuation packet cannot alias an expected opcode.
3. The pending write's response, claimed by characteristic and opcode.
4. `QUALIFYING_EVENTS`: decoded by `QualifyingEvent.fromRawBytes` and passed to
   `handleQualifyingEvents`. The pump is acknowledged afterwards by writing four zero bytes.
5. `CONTROL_STREAM` progress messages: published on the manager's Combine subjects
   (`fillTubingStateStream`, `pumpingStateStream`, …), which the cartridge and fill view models
   observe. Two pairs share an opcode and are told apart by length: opcode −29 is
   Detecting/LoadCartridge and −23 is ExitFillTubingMode/PumpingState.
6. `ErrorResponse`, as above.

## Messages

`Message` is the base protocol: `static props`, `cargo`, `init(cargo:)`. `PumpRequest` adds an
associated `Response` type, so `bluetooth.write(SomeRequest())` returns a typed response. The
`Nonexistent*StreamRequest` placeholders stand in for unsolicited streams and deliberately do not
conform to `PumpRequest`.

`MessageProps` carries the opcode, size, characteristic, and the `signed`, `variableSize`,
`stream` and `modifiesInsulinDelivery` flags. It also carries `minApi` and `supportedDevices`.
`props.isSupported(pumpModel:apiVersion:)` and `TandemPumpManager.supports(_:)` use those two
fields to skip requests the connected pump cannot answer, such as the Mobi-only
`CGMStatusV2Request`. The API version and model come from `ApiVersionRequest` and
`PumpVersionBRequest`, which `fetchPumpInformation` reads on the first sync and then about once
a day.

`MessageRegistry` is the catalog. It resolves responses by opcode and characteristic, pairs
requests with responses by name, and provides the lookup the debug view uses to send any message
by name. `PumpRequestResponsePairingTests` checks the pairing across the whole catalog.

A few builders in `Sources/TandemCore/Builders` choose the request variant by API version:
`ControlIQInfoRequestBuilder`, `CurrentBatteryRequestBuilder`, `IOBRequestBuilder` and
`LastBolusRequestBuilder`.

History log records (`Sources/TandemCore/Messages/HistoryLog`) are a separate hierarchy: each is
a 26-byte record keyed by type ID, parsed by `HistoryLogParser` out of `HistoryLogStreamResponse`.

## TandemPumpManager

### State

`TandemPumpManagerState` is the host-persisted `rawState`. It holds `PumpState` (pairing
artifacts and pump identity), `TandemPumpManagerSettings` (max bolus, max temp basal, max
schedule entry), feature flags, the basal schedule, in-flight doses (`bolusDose`,
`pendingBolusFinalization`, `basalDose`), last reservoir and battery readings, the history
backfill watermark (`historyBackfill`) and the `BolusReportLedger`. Access goes through
`stateLock`, a recursive lock, because the command queue, the notification path and the host all
touch it. `notifyDelegateStateUpdated()` tells the host to persist it.

### Sync cycle

The host calls `ensureCurrentPumpData` about every 5 minutes. It returns immediately if
`lastReconciliation` is less than 4.5 minutes old; otherwise it calls
`syncPumpData(onlyIfIdle: true)`. The sync runs as one command job:

1. Every 24 hours: `fetchControlIQStatus`, `fetchDeliveryLimits`, `fetchGlobalPumpSettings` and
   `fetchPumpInformation`.
2. `enforceQuickBolusDisabled`, unless the quick-bolus feature flag is on.
3. Every time: reservoir, battery, bolus status and pending-bolus finalization, basal status
   (including the basal rate check), notifications, time since reset, and CGM session.
4. `lastReconciliation` advances only if the pump actually answered something during this sync
   (`responseCount` rose). The boundary is reported even when there are no doses.
5. `historyBackfillCoordinator.runTick()` is started and not awaited.

A sync that is already queued makes later automatic polls stand down. A sync the user asks for
runs regardless.

### Commands

| Host call | Pump messages | Notes |
| --- | --- | --- |
| `enactBolus` | `BolusPermissionRequest`, `InitiateBolusRequest` | Rejects ≤ 0 U and anything over `settings.maxBolus`. Rejects automatic boluses while Control-IQ is on. Records the bolus in `BolusReportLedger`. Progress is polled every second through `PumpTelemetryScheduler` until the bolus finishes. |
| `cancelBolus` | `CancelBolusRequest`, then after 2 s `LastBolusStatus*` for the delivered volume | |
| `enactTempBasal` | `CurrentBasalStatusRequest`, `StopTempRateRequest` if a temp basal is running, `SetTempRateRequest` | Blocked while Control-IQ is on or a bolus is running. The percentage is computed against the app's schedule, not the pump's profile (#400). |
| `suspendDelivery` / `resumeDelivery` | `TempRateRequest`, `StopTempRateRequest` if a temp basal is running, `SuspendPumpingRequest` / `ResumePumpingRequest` | The in-app resume button uses `resumeDeliveryAcknowledgingResumeAlarms`: if the pump refuses, it acknowledges the resume-pump alarms and retries once. |
| `syncDeliveryLimits` | `SetMaxBolusLimitRequest`, `SetMaxBasalLimitRequest` | |
| `syncBasalRateSchedule` | IDP reads and `SetIDPSegmentRequest` via `IDPManager` | Reads the profile back afterwards and fails with `basalProfileSyncMismatch` if it differs. |
| `syncPumpTime` | `ChangeTimeDateRequest` | |

Every host-facing command is wrapped by `watchdogged`, which guarantees exactly one completion
even if the lower layers wedge. `commandWatchdogTimeout` (180 s) is deliberately much longer than
the longest real command, because a false failure on a bolus could prompt the host to retry.

### Qualifying events

`handleQualifyingEvents` maps each event to status fetches through
`QualifyingEventFetch.fetches(for:context:)`. That function is derived from
`QualifyingEvent.groupSuggestedHandlers`, pumpX2's suggested-handler table, and adds two things:
a basal read on suspend/resume and on profile changes. Requests the driver has no consumer for
are not sent. A `.bolusChange` event also starts a history backfill tick, so a bolus given from the
pump screen is found without waiting for the next sync.

### Alerts

`fetchNotifications` reloads `NotificationBundle`, which contains the alert, alarm, reminder,
CGM-alert, malfunction and AAM status responses. `TandemAlertReconciler` then compares the active
items with the LoopKit `Alert`s already issued and issues or retracts alerts to match. Alerts,
alarms and malfunctions are forwarded; CGM alerts are forwarded only if the user opts in, and
reminders stay in the app. When the host acknowledges an alert, `DismissNotificationRequest`
clears it on the pump. Basal min/max alerts are acknowledged automatically, because oref sets
zero temp basals routinely and the pump would otherwise alert on each one.

### History

- Every `HistoryLogStreamResponse` goes through `historyLogStream` into `historyLogStore`, an
  in-memory `InMemoryHistoryLogStore` that is not persisted (#232).
- `HistoryLogFetcher` reads a window: it sends `HistoryLogStatusRequest`, then walks backward in
  `HistoryLogRequest` chunks of up to 255 entries, heals gaps, and serves anything already in the
  store without asking the pump again. `HistoryFetchGate` lets only one reader hold the stream at a
  time (the backfill and the log viewer).
- `HistoryBackfillCoordinator` keeps the store caught up with the pump using
  `HistoryBackfillPlanner`, which is pure arithmetic, and the persisted `HistoryBackfillState`
  watermark. `HistoryToDoseMapper` and `HistoryTimestampReconciler` turn records into
  `NewPumpEvent`s, and `TandemPumpManager+HistoryDoseReporting` reports boluses not already
  reported by the live path.
- The backfill and the dose reporting are behind the `historyBackfill` and `historyDoseReporting`
  feature flags; the backfill is on by default, dose reporting is off. AGENTS.md has the full
  rules.

### Reporting to the host

Doses reach the host through `emitPumpEvents` / `hasNewPumpEvents`. The pump is read before the
host attaches a delegate and a delegate queue, so batches emitted before then are held
(`PendingPumpEventBatch`). They are replayed from `deliverStateMissedByTheDelegate`, along with
any pending reservoir reading.

## Threads, queues and timeouts

| Where | What runs there |
| --- | --- |
| `TandemBluetoothManager.managerQueue` | `CBCentralManager` and `CBPeripheral` delegate callbacks |
| `TandemBluetoothManager.commandQueue` | Every connect attempt and command job |
| Global `.userInitiated` | `performInitialSetup`, while the connect attempt waits |
| `TandemPumpManager.watchdogQueue` | Command watchdog timeouts. Kept separate so a wedged command cannot starve its own watchdog. |
| `PumpTelemetryScheduler` queue | The 1 s bolus progress timer |

Each BLE operation waits on its own `TandemDispatchGroup`. Disconnecting or losing Bluetooth
cancels these waits, so a blocked write returns at once instead of waiting out its timeout.

| Timeout | Value |
| --- | --- |
| Connect attempt | 30 s |
| Characteristic read (setup) | 10 s |
| Write acknowledgement, per packet | 2 s |
| Response | 30 s |
| Write lock | 45 s (must exceed the response timeout) |
| Command watchdog | 180 s |

The virtual pump build can override the connect and response timeouts (`VirtualPump`).

## Test seams

- `PumpBluetoothConnection` with `StubPumpBluetooth`: stubs responses per request type and
  records what was sent.
- `TandemClock` with `ManualClock`: every time-based decision reads `TandemPumpManager.clock`.
- `TANDEMKIT_VIRTUAL_PUMP`: replaces CoreBluetooth with a socket to faketandem, so the real stack
  runs end to end (see [integration-harness.md](integration-harness.md)).
