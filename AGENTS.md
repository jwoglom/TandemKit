## Reference material
- See [ARCHITECTURE_ANALYSIS.md](ARCHITECTURE_ANALYSIS.md) and [KEY_FILES_REFERENCE.md](KEY_FILES_REFERENCE.md) for deeper implementation notes and file-level pointers.

## Comments
**Default to no comment.** Most code needs none. Before writing one, ask what a reader who has the
code in front of them still gets wrong without it. If there is no such thing, delete it.

Never:
- Narrate the code (`// Query the pump`, `// Clean up state`, `// Loop over the entries`).
- Restate a signature, a type, or a name in prose. A doc comment that adds nothing to the name is
  worse than none — it has to be maintained.
- Explain the obvious half of a line to get to the useful half. Write only the useful half.
- Pad. One line unless the reason genuinely needs two; never three.
- Repeat in a comment what an adjacent log message, test name, or assertion message already says.

Comment-worthy, in one line where possible:
- A pump quirk, firmware race, or host behaviour being worked around.
- The safety direction of a fallback — which way it biases IOB, and why that way.
- Units, resolution, and whose clock a timestamp is on.
- A non-obvious ordering or a rejected alternative that looks better than it is.
- An issue number, when the motivation lives there. Often the issue number alone is the comment.

Tests: the test name carries the behaviour. Comment only a setup line whose purpose is opaque
(why *this* stub value, why state is poked directly).

When editing existing code, delete comments that the edit made redundant. Leaving them is how they
rot into lies.

## Message types by category

### Authentication

| Area | Status | Notes |
| --- | --- | --- |
| Message catalog (`Sources/TandemCore/Messages/Authentication`) | ✅ Complete | Fully described in [ARCHITECTURE_ANALYSIS.md](ARCHITECTURE_ANALYSIS.md) and the serialization audit. |
| Unit tests | ✅ Complete | `TandemCoreTests` exercises JPake rounds, pump challenges, and the central challenge flow; no outstanding gaps were identified in the audit. |
| Pairing flow implementation (`PumpCommSession`, `PumpChallengeRequestBuilder`) | ✅ Complete | Legacy 16-character and JPake PIN flows advance correctly and persist derived secrets/nonces as required for PumpManager reconnection (see [wire_bt_transport.md](TandemKit/docs/plans/wire_bt_transport.md)). |
| Cross-platform dependency story | ⚠️ Partial | SwiftECC/BigInt remain required for JPake; Linux builds function through the shim, but deterministic RNG configuration for CI is still pending. |

### Control

| Area | Status | Notes |
| --- | --- | --- |
| Message catalog (`Sources/TandemCore/Messages/Control`) | ✅ Complete | Full suite of Tandem control requests/responses is implemented with correct serialization metadata (see [ARCHITECTURE_ANALYSIS.md](ARCHITECTURE_ANALYSIS.md#control)). |
| Command validation (`TandemPumpManager`, `PumpStateSupplier`) | ✅ Complete | Bolus, temp basal, suspend/resume, and configuration requests enforce LoopKit `PumpManager` safety limits before dispatch. |
| Unit tests (requests) | ✅ Complete | Core therapy commands and high-risk configuration requests are covered in `TandemCoreTests`. |
| Unit tests (responses & long tail) | ⚠️ Partial | Many responses and less frequently used configuration messages lack direct coverage; additional fixtures needed to satisfy LoopKit QA expectations. |
| Transport orchestration (`PumpComm`, `PeripheralManagerTransport`) | ⚠️ Partial | Message dispatch works with bounded retry/backoff on pump faults and fault-event surfacing through delegates; reconnection/bootstrap mechanics are documented in [ARCHITECTURE_ANALYSIS.md](ARCHITECTURE_ANALYSIS.md#authenticated-session-bootstrap), with taxonomy/UI mapping still in progress. |

### ControlStream
Requests:
- [x] NonexistentDetectingCartridgeStateStreamRequest
   - [ ] Tests for NonexistentDetectingCartridgeStateStreamRequest
- [x] NonexistentEnterChangeCartridgeModeStateStreamRequest
   - [ ] Tests for NonexistentEnterChangeCartridgeModeStateStreamRequest
- [x] NonexistentExitFillTubingModeStateStreamRequest
   - [ ] Tests for NonexistentExitFillTubingModeStateStreamRequest
- [x] NonexistentFillCannulaStateStreamRequest
   - [ ] Tests for NonexistentFillCannulaStateStreamRequest
- [x] NonexistentFillTubingStateStreamRequest
   - [ ] Tests for NonexistentFillTubingStateStreamRequest
- [x] NonexistentPumpingStateStreamRequest

Responses:
- [x] ControlStreamMessages
- [x] DetectingCartridgeStateStreamResponse
   - [ ] Tests for DetectingCartridgeStateStreamResponse
- [x] EnterChangeCartridgeModeStateStreamResponse
   - [ ] Tests for EnterChangeCartridgeModeStateStreamResponse
- [x] ExitFillTubingModeStateStreamResponse
   - [x] Tests for ExitFillTubingModeStateStreamResponse
- [x] FillCannulaStateStreamResponse
   - [ ] Tests for FillCannulaStateStreamResponse
- [x] FillTubingStateStreamResponse
   - [ ] Tests for FillTubingStateStreamResponse
- [x] PumpingStateStreamResponse
   - [x] Tests for PumpingStateStreamResponse

### CurrentStatus
_Remaining unchecked CurrentStatus tests: 94_
Requests:
- [x] AlarmStatusRequest
   - [x] Tests for AlarmStatusRequest
- [x] AlertStatusRequest
   - [x] Tests for AlertStatusRequest
- [x] ApiVersionRequest
   - [x] Tests for ApiVersionRequest
- [x] BasalIQAlertInfoRequest
   - [ ] Tests for BasalIQAlertInfoRequest
- [x] BasalIQSettingsRequest
   - [ ] Tests for BasalIQSettingsRequest
- [x] BasalIQStatusRequest
   - [ ] Tests for BasalIQStatusRequest
- [x] BasalLimitSettingsRequest
   - [x] Tests for BasalLimitSettingsRequest
- [x] BolusCalcDataSnapshotRequest
   - [x] Tests for BolusCalcDataSnapshotRequest
- [x] BolusPermissionChangeReasonRequest
   - [ ] Tests for BolusPermissionChangeReasonRequest
- [x] CGMAlertStatusRequest
   - [x] Tests for CGMAlertStatusRequest
- [x] CGMGlucoseAlertSettingsRequest
   - [x] Tests for CGMGlucoseAlertSettingsRequest
- [x] CGMHardwareInfoRequest
   - [x] Tests for CGMHardwareInfoRequest
- [x] CGMOORAlertSettingsRequest
   - [x] Tests for CGMOORAlertSettingsRequest
- [x] CGMRateAlertSettingsRequest
   - [x] Tests for CGMRateAlertSettingsRequest
- [x] CGMStatusRequest
   - [x] Tests for CGMStatusRequest
- [x] CommonSoftwareInfoRequest
   - [ ] Tests for CommonSoftwareInfoRequest
- [x] ControlIQIOBRequest
   - [ ] Tests for ControlIQIOBRequest
- [x] ControlIQInfoV1Request
   - [ ] Tests for ControlIQInfoV1Request
- [x] ControlIQInfoV2Request
   - [ ] Tests for ControlIQInfoV2Request
- [x] ControlIQSleepScheduleRequest
   - [ ] Tests for ControlIQSleepScheduleRequest
- [x] CurrentBasalStatusRequest
   - [ ] Tests for CurrentBasalStatusRequest
- [x] CurrentBatteryV1Request
   - [x] Tests for CurrentBatteryV1Request
- [x] CurrentBatteryV2Request
   - [ ] Tests for CurrentBatteryV2Request
- [x] CurrentBolusStatusRequest
   - [ ] Tests for CurrentBolusStatusRequest
- [x] CurrentEGVGuiDataRequest
   - [ ] Tests for CurrentEGVGuiDataRequest
- [x] ExtendedBolusStatusRequest
   - [ ] Tests for ExtendedBolusStatusRequest
- [x] GetG6TransmitterHardwareInfoRequest
   - [ ] Tests for GetG6TransmitterHardwareInfoRequest
- [x] GetSavedG7PairingCodeRequest
   - [ ] Tests for GetSavedG7PairingCodeRequest
- [x] GlobalMaxBolusSettingsRequest
   - [x] Tests for GlobalMaxBolusSettingsRequest
- [x] HistoryLogRequest
   - [ ] Tests for HistoryLogRequest
- [x] HistoryLogStatusRequest
   - [ ] Tests for HistoryLogStatusRequest
- [x] HomeScreenMirrorRequest
   - [ ] Tests for HomeScreenMirrorRequest
- [x] IDPSegmentRequest
   - [ ] Tests for IDPSegmentRequest
- [x] IDPSettingsRequest
   - [ ] Tests for IDPSettingsRequest
- [x] InsulinStatusRequest
   - [ ] Tests for InsulinStatusRequest
- [x] LastBGRequest
   - [ ] Tests for LastBGRequest
- [x] LastBolusStatusRequest
   - [ ] Tests for LastBolusStatusRequest
- [x] LastBolusStatusV2Request
   - [ ] Tests for LastBolusStatusV2Request
- [x] LocalizationRequest
   - [ ] Tests for LocalizationRequest
- [x] MalfunctionStatusRequest
   - [ ] Tests for MalfunctionStatusRequest
- [x] NonControlIQIOBRequest
   - [ ] Tests for NonControlIQIOBRequest
- [x] OtherNotification2StatusRequest
   - [ ] Tests for OtherNotification2StatusRequest
- [x] OtherNotificationStatusRequest
   - [ ] Tests for OtherNotificationStatusRequest
- [x] ProfileStatusRequest
   - [ ] Tests for ProfileStatusRequest
- [x] PumpFeaturesV1Request
   - [ ] Tests for PumpFeaturesV1Request
- [x] PumpFeaturesV2Request
   - [ ] Tests for PumpFeaturesV2Request
- [x] PumpGlobalsRequest
   - [ ] Tests for PumpGlobalsRequest
- [x] PumpSettingsRequest
   - [ ] Tests for PumpSettingsRequest
- [x] PumpVersionRequest
   - [ ] Tests for PumpVersionRequest
- [x] ReminderStatusRequest
   - [ ] Tests for ReminderStatusRequest
- [x] RemindersRequest
   - [ ] Tests for RemindersRequest
- [x] TempRateRequest
   - [ ] Tests for TempRateRequest
- [x] TimeSinceResetRequest
   - [ ] Tests for TimeSinceResetRequest
- [x] UnknownMobiOpcode110Request
   - [ ] Tests for UnknownMobiOpcode110Request
- [x] UnknownMobiOpcode20Request
   - [ ] Tests for UnknownMobiOpcode20Request
- [x] UnknownMobiOpcode30Request
   - [ ] Tests for UnknownMobiOpcode30Request
- [x] UnknownMobiOpcodeNeg124Request
   - [ ] Tests for UnknownMobiOpcodeNeg124Request
- [x] UnknownMobiOpcodeNeg66Request
   - [ ] Tests for UnknownMobiOpcodeNeg66Request
- [x] UnknownMobiOpcodeNeg70Request
   - [ ] Tests for UnknownMobiOpcodeNeg70Request

Responses:
- [x] AlarmStatusResponse
   - [x] Tests for AlarmStatusResponse
- [x] AlertStatusResponse
   - [x] Tests for AlertStatusResponse
- [x] ApiVersionResponse
   - [ ] Tests for ApiVersionResponse
- [x] BasalIQAlertInfoResponse
   - [ ] Tests for BasalIQAlertInfoResponse
- [x] BasalIQSettingsResponse
   - [ ] Tests for BasalIQSettingsResponse
- [x] BasalIQStatusResponse
   - [ ] Tests for BasalIQStatusResponse
- [x] BasalLimitSettingsResponse
   - [x] Tests for BasalLimitSettingsResponse
- [x] BolusCalcDataSnapshotResponse
   - [x] Tests for BolusCalcDataSnapshotResponse
- [x] BolusPermissionChangeReasonResponse
   - [ ] Tests for BolusPermissionChangeReasonResponse
- [x] CGMAlertStatusResponse
   - [x] Tests for CGMAlertStatusResponse
- [x] CGMGlucoseAlertSettingsResponse
   - [x] Tests for CGMGlucoseAlertSettingsResponse
- [x] CGMHardwareInfoResponse
   - [x] Tests for CGMHardwareInfoResponse
- [x] CGMOORAlertSettingsResponse
   - [x] Tests for CGMOORAlertSettingsResponse
- [x] CGMRateAlertSettingsResponse
   - [x] Tests for CGMRateAlertSettingsResponse
- [x] CGMStatusResponse
   - [x] Tests for CGMStatusResponse
- [x] CommonSoftwareInfoResponse
   - [ ] Tests for CommonSoftwareInfoResponse
- [x] ControlIQIOBResponse
   - [ ] Tests for ControlIQIOBResponse
- [x] ControlIQInfoAbstractResponse
   - [ ] Tests for ControlIQInfoAbstractResponse
- [x] ControlIQInfoV1Response
   - [ ] Tests for ControlIQInfoV1Response
- [x] ControlIQInfoV2Response
   - [ ] Tests for ControlIQInfoV2Response
- [x] ControlIQSleepScheduleResponse
   - [ ] Tests for ControlIQSleepScheduleResponse
- [x] CurrentBasalStatusResponse
   - [ ] Tests for CurrentBasalStatusResponse
- [x] CurrentBatteryAbstractResponse
- [x] CurrentBatteryV1Response
   - [x] Tests for CurrentBatteryV1Response
- [x] CurrentBatteryV2Response
   - [x] Tests for CurrentBatteryV2Response
- [x] CurrentBolusStatusResponse
   - [ ] Tests for CurrentBolusStatusResponse
- [x] CurrentEGVGuiDataResponse
   - [ ] Tests for CurrentEGVGuiDataResponse
- [x] ExtendedBolusStatusResponse
   - [ ] Tests for ExtendedBolusStatusResponse
- [x] GetG6TransmitterHardwareInfoResponse
   - [ ] Tests for GetG6TransmitterHardwareInfoResponse
- [x] GetSavedG7PairingCodeResponse
   - [ ] Tests for GetSavedG7PairingCodeResponse
- [x] GlobalMaxBolusSettingsResponse
   - [x] Tests for GlobalMaxBolusSettingsResponse
- [x] HistoryLogResponse
   - [ ] Tests for HistoryLogResponse
- [x] HistoryLogStatusResponse
   - [ ] Tests for HistoryLogStatusResponse
- [x] HomeScreenMirrorResponse
   - [ ] Tests for HomeScreenMirrorResponse
- [x] IDPSegmentResponse
   - [ ] Tests for IDPSegmentResponse
- [x] IDPSettingsResponse
   - [ ] Tests for IDPSettingsResponse
- [x] InsulinStatusResponse
   - [ ] Tests for InsulinStatusResponse
- [x] LastBGResponse
   - [ ] Tests for LastBGResponse
- [x] LastBolusStatusAbstractResponse
- [x] LastBolusStatusResponse
   - [ ] Tests for LastBolusStatusResponse
- [x] LastBolusStatusV2Response
   - [ ] Tests for LastBolusStatusV2Response
- [x] LocalizationResponse
   - [ ] Tests for LocalizationResponse
- [x] MalfunctionStatusResponse
   - [ ] Tests for MalfunctionStatusResponse
- [x] NonControlIQIOBResponse
   - [ ] Tests for NonControlIQIOBResponse
- [x] OtherNotification2StatusResponse
   - [ ] Tests for OtherNotification2StatusResponse
- [x] OtherNotificationStatusResponse
   - [ ] Tests for OtherNotificationStatusResponse
- [x] ProfileStatusResponse
   - [ ] Tests for ProfileStatusResponse
- [x] PumpFeaturesAbstractResponse
   - [ ] Tests for PumpFeaturesAbstractResponse
- [x] PumpFeaturesV1Response
   - [ ] Tests for PumpFeaturesV1Response
- [x] PumpFeaturesV2Response
   - [ ] Tests for PumpFeaturesV2Response
- [x] PumpGlobalsResponse
   - [ ] Tests for PumpGlobalsResponse
- [x] PumpSettingsResponse
   - [ ] Tests for PumpSettingsResponse
- [x] PumpVersionResponse
   - [ ] Tests for PumpVersionResponse
- [x] ReminderStatusResponse
   - [ ] Tests for ReminderStatusResponse
- [x] RemindersResponse
   - [ ] Tests for RemindersResponse
- [x] TempRateResponse
   - [ ] Tests for TempRateResponse
- [x] TimeSinceResetResponse
   - [ ] Tests for TimeSinceResetResponse
- [x] UnknownMobiOpcode110Response
   - [ ] Tests for UnknownMobiOpcode110Response
- [x] UnknownMobiOpcode20Response
   - [ ] Tests for UnknownMobiOpcode20Response
- [x] UnknownMobiOpcode30Response
   - [ ] Tests for UnknownMobiOpcode30Response
- [x] UnknownMobiOpcodeNeg124Response
   - [ ] Tests for UnknownMobiOpcodeNeg124Response
- [x] UnknownMobiOpcodeNeg66Response
   - [ ] Tests for UnknownMobiOpcodeNeg66Response
- [x] UnknownMobiOpcodeNeg70Response
   - [ ] Tests for UnknownMobiOpcodeNeg70Response

### HistoryLog
Requests:
- [x] NonexistentHistoryLogStreamRequest

Responses:
- [x] AlarmActivatedHistoryLog
- [x] AlertActivatedHistoryLog
- [x] BGHistoryLog
- [x] BasalDeliveryHistoryLog
- [x] BasalRateChangeHistoryLog
- [x] BolexActivatedHistoryLog
- [x] BolexCompletedHistoryLog
- [x] BolusActivatedHistoryLog
- [x] BolusCompletedHistoryLog
- [x] BolusDeliveryHistoryLog
- [x] BolusRequestedMsg1HistoryLog
- [x] BolusRequestedMsg2HistoryLog
- [x] BolusRequestedMsg3HistoryLog
- [x] CGMHistoryLog
- [x] CannulaFilledHistoryLog
- [x] CarbEnteredHistoryLog
- [x] CartridgeFilledHistoryLog
- [x] CgmCalibrationGxHistoryLog
- [x] CgmCalibrationHistoryLog
- [x] CgmDataGxHistoryLog
- [x] CgmDataSampleHistoryLog
- [x] ControlIQPcmChangeHistoryLog
- [x] ControlIQUserModeChangeHistoryLog
- [x] CorrectionDeclinedHistoryLog
- [x] DailyBasalHistoryLog
- [x] DataLogCorruptionHistoryLog
- [x] DateChangeHistoryLog
- [x] FactoryResetHistoryLog
- [x] HistoryLog
- [x] HistoryLogParser
- [x] HistoryLogStreamResponse
- [x] HypoMinimizerResumeHistoryLog
- [x] HypoMinimizerSuspendHistoryLog
- [x] IdpActionHistoryLog
- [x] IdpActionMsg2HistoryLog
- [x] IdpBolusHistoryLog
- [x] IdpListHistoryLog
- [x] IdpTimeDependentSegmentHistoryLog
- [x] LogErasedHistoryLog
- [x] NewDayHistoryLog
- [x] ParamChangeGlobalSettingsHistoryLog
- [x] ParamChangePumpSettingsHistoryLog
- [x] ParamChangeRemSettingsHistoryLog
- [x] ParamChangeReminderHistoryLog
- [x] PumpingResumedHistoryLog
- [x] PumpingSuspendedHistoryLog
- [x] TempRateActivatedHistoryLog
- [x] TempRateCompletedHistoryLog
- [x] TimeChangedHistoryLog
- [x] TubingFilledHistoryLog
- [x] UnknownHistoryLog
- [x] UsbConnectedHistoryLog
- [x] UsbDisconnectedHistoryLog
- [x] UsbEnumeratedHistoryLog

### QualifyingEvent
Responses:
- [x] QualifyingEvent
   - [x] Tests for QualifyingEvent

Callbacks (`QualifyingEvent.suggestedHandlers` / `groupSuggestedHandlers`):
- [x] Ported from pumpX2's suggested-handler table, including the version-dependent
  Control-IQ info / last-bolus / battery / IOB request selection. `QualifyingEventContext`
  carries the api version, Control-IQ support, and in-progress bolus id that pumpX2 reads out
  of its global `PumpStateSupplier`. `groupSuggestedHandlers` dedupes by request type *and*
  cargo (`ActiveAamBitsRequest` differs only by cargo) and drops requests whose `minApi` is
  newer than the pump's.
- [x] `QualifyingEventFetch` (`Sources/TandemKit/PumpManager`) maps each *suggested-handler
  request* onto the `TandemPumpManager` status fetch that both issues it and applies the
  response, so the ported catalog stays the single source of truth instead of a second event
  table that could drift. `handleQualifyingEvents` runs the deduped set on the command queue and
  acknowledges afterwards. A request that maps to no fetch is not sent: nothing in the driver
  consumes IOB, CGM/EGV, home screen mirror, profile status, Basal-IQ, temp rate, localization,
  load status or bolus permission change reason today, so `iobChange`, `bg`, `cgmChange`,
  `basalIQ`, `basalIQStatus`, `controlIQSleep`, `extendedBolusChange`, `pumpingStatus` and
  `bolusPermissionRevoked` currently fetch nothing. Two deliberate additions to pumpX2's table:
  `pumpSuspend`/`pumpResume` refresh the basal status, since that is what emits the
  suspend/resume dose to LoopKit, and `profileChange`/`activeProfileSegmentChange` refresh it so
  the basal rate check runs on a profile edit instead of at the next sync.

---

### TODO – Documentation accuracy audit
- [x] Align PumpComm transport row with the implemented retry/backoff handling and fault-event delegate surfacing.
- [x] Refresh `TandemPumpManager` capability notes to reflect existing bolus/temp basal/suspend flows and status reconciliation.
- [x] Alert/alarm/malfunction surfacing now flows through LoopKit `Alert` issuance; revisit the CGM data bullets once that pipeline is implemented.

## Pump Driver Implementation Plan (Loop/Trio)

### Current Capabilities Implemented
* **Pump protocol modeling (`Sources/TandemCore`)** – ✅ **FULLY IMPLEMENTED**: The repository defines a complete catalog of 200+ Tandem request/response message types with real parsing/serialization logic (not stubs). All message categories are implemented: Authentication (10 types), Control (37 requests, 37 responses), ControlStream (6 requests, 6 responses), CurrentStatus (63 requests, 63 responses), HistoryLog (50+ types), and QualifyingEvent. `MessageRegistry` provides metadata mapping for opcodes, sizes, signing requirements, and characteristics. All messages have complete `init(cargo:)` deserializers and `buildCargo()` serializers.
* **BLE transport primitives (`Sources/TandemBLE`)** – ✅ **FULLY IMPLEMENTED**: Complete operational Bluetooth stack with:
  - `BluetoothManager`: Full scanning/reconnect logic, connection management, peripheral discovery, delegate callbacks
  - `PeripheralManager`: Complete BLE operations including service/characteristic discovery, packet sending (`sendMessagePacket`), packet receiving (`readMessagePacket`), command queue management, notification handling
  - All Tandem-specific service/characteristic configurations via `.tandemPeripheral` configuration
  - Packet helpers for assembling/disassembling Tron messages with HMAC/CRC
* **Authentication and pairing** – ⚠️ **MOSTLY IMPLEMENTED**:
  - `JpakeAuthBuilder`: ✅ Complete JPake authentication flow (requires SwiftECC/BigInt/CryptoKit dependencies)
  - `PumpCommSession.pair()`: ✅ Supports both legacy pump-challenge and JPake PIN flows
- V1 pairing (16-char code via `PumpChallengeRequestBuilder.createV1`): ✅ Fully implemented
- V2 pairing (6-digit PIN via `PumpChallengeRequestBuilder.createV2`): ✅ Uses JPAKE builder to advance pairing flow
  - Pairing state persistence: ✅ TandemPumpManagerState persists derived secrets/server nonces
* **Utility surface area** – ✅ **FULLY IMPLEMENTED**: `PumpStateSupplier` provides complete pairing code validation/sanitization (`sanitizeAndStorePairingCode`), authentication key derivation (`authenticationKey`), and configuration flags for insulin-affecting actions.
* **Existing validation** – ⚠️ **PARTIAL**: Unit tests cover message metadata, pairing-code validation, and JPake builder behavior. Many message types in AGENTS.md checklist are marked as lacking tests.

### Gaps Blocking a Functional Loop/Trio Pump Driver

#### 1. LoopKit/Trio Integration (STUBS)
* **`Sources/LoopKit/LoopKit.swift`** – ❌ **STUB**: Only minimal protocol definitions (`PumpManager`, `PumpManagerDelegate`, `PumpManagerUI`, `CGMManagerUI`). No actual LoopKit framework integration.
* **`TandemPumpManager`** (`Sources/TandemKit/PumpManager/TandemPumpManager.swift`) – ⚠️ **PARTIALLY IMPLEMENTED**:
  - `connect()`/`disconnect()` wire `BluetoothManager`/`PeripheralManager` delegates, persist state, and coordinate session lifecycle.
  - Configuration toggles (`enableActionsAffectingInsulinDelivery`, etc.) write through to `PumpStateSupplier`, persist into manager state, and drive delegate notifications; UI affordances remain to be finished.
  - `pairPump()` drives the UIKit/CBPeripheral pairing path; non-Apple/on-device initiation flows still need polish.
  - Dosing interfaces for bolus, temp basal, and suspend/resume are implemented with LoopKit safety validation and delegate updates.
  - Reservoir, battery, basal, bolus, and history reconciliation now propagate through LoopKit delegate callbacks; alerts, alarms, and malfunctions surface as LoopKit `Alert`s via `TandemAlertReconciler` (qualifying-event driven plus every `ensureCurrentPumpData` sync, ~5 minutes), while CGM data surfaces remain unimplemented.
* **`TandemPumpManagerState`** (`Sources/TandemKit/PumpManager/TandemPumpManagerState.swift`) – ⚠️ **PARTIALLY IMPLEMENTED**:
  - Serializes/deserializes `PumpState` including derived secret and server nonce
  - Still lacks storage for therapy settings, pump status snapshots, and LoopKit-facing metadata

#### 2. Pump Session Orchestration (INCOMPLETE)
* **`TandemPump`** (`Sources/TandemKit/PumpManager/TandemPump.swift`) – ⚠️ **PARTIALLY IMPLEMENTED**:
  - Uses the production `BluetoothManager`/`PeripheralManager` from `TandemBLE` for scanning, connection management, and startup message dispatch (`startScanning`, `disconnect`, `sendDefaultStartupRequests`).
  - Configuration helpers (`enableActionsAffectingInsulinDelivery`, etc.) now forward to `PumpStateSupplier` and persist enablement for delegate consumers, though UI gating remains outstanding.
* **`PumpComm`** (`Sources/TandemKit/PumpManager/PumpComm.swift`) – ⚠️ **PARTIALLY IMPLEMENTED**:
  - Delegates to `PumpCommSession` for pairing and state updates and relays typed notifications back to the manager.
  - Core send/receive flows incorporate retry/backoff around pump faults and surface `PumpCommFaultEvent` details through delegate callbacks.
* **`PumpMessageTransport`** (`Sources/TandemKit/PumpManager/PumpMessageTransport.swift`) – ✅ **IMPLEMENTED**:
  - `PeripheralManagerTransport` now bridges `TronMessageWrapper` packets onto `PeripheralManager`, streams responses through `PumpResponseCollector`, and retains request/response history for introspection.

#### 3. Authentication Gaps
* **V2 pairing (6-digit PIN)** – ✅ **IMPLEMENTED**: `PumpChallengeRequestBuilder.createV2()` advances the JPakeAuthBuilder and `PumpCommSession` now branches between JPAKE and legacy pump-challenge flows.
* **Pairing state persistence** – ✅ **IMPLEMENTED**: `TandemPumpManagerState` serializes derived secrets and nonces, and `PumpCommSession` updates `PumpStateSupplier` artifacts.
* **Dependency management** – ⚠️ All JPake functionality requires SwiftECC/BigInt/CryptoKit dependencies which may not be available on all platforms

#### 4. Response Decoding and Device Targeting
* **BLE notification handling** – ✅ `PumpNotificationRouter` attaches to the active `PeripheralManager`, validates packets, and forwards typed messages into `PumpCommSession` for handling.
* **Message response parsing** – ✅ `PeripheralManagerTransport` + `PumpResponseCollector` decode responses via `BTResponseParser`, returning concrete message types back to callers.
* **Device targeting** – ❌ No logic yet to infer pump model (t:slim X2, Mobi, Trio) from advertisements or `PumpVersionResponse` values.
* **Status updates** – ⚠️ Basal/bolus/battery/reservoir polling and notification handling feed LoopKit delegates; history streaming now runs through `HistoryLogFetcher` with telemetry scheduler hooks, and pump alerts/alarms/malfunctions are issued/retracted as LoopKit `Alert`s from every `fetchNotifications()` pass; CGM data pipelines remain unimplemented.

#### 5. Safety and Gating
* **Insulin delivery toggles** – ⚠️ `PumpStateSupplier` exposes enablement flags and TandemPump helpers now persist and forward them; UI/user-consent affordances are still missing.
* **Therapy command safeguards** – ⚠️ `TandemPumpManager` validates bolus amounts, max temp basal rates, and IOB limits before issuing commands, but additional safety interlocks (e.g. user acknowledgements) are still pending.
* **Error handling** – ⚠️ Transport/pump communication errors bubble back through delegate callbacks with decoded fault events; richer taxonomy and UI mapping are still needed.

### Proposed Roadmap
1. **Phase 0 – Environment & dependency alignment** – ❌ *Not yet started*
   * LoopKit/LoopKitUI come from the host app's workspace (Trio pulls `loopandlearn/LoopKit` in as a git submodule); TandemKit.xcodeproj links them from `BUILT_PRODUCTS_DIR`. Carthage is no longer used by TandemKit or by Trio.
   * Document and script any additional SwiftECC/BigInt/CryptoKit requirements so the JPake path builds in CI (no automation or documentation present).

2. **Phase 1 – Transport consolidation** – ⚠️ *Partially completed*
   * `TandemPump` now uses the real `BluetoothManager`/`PeripheralManager` and wires delegate callbacks for connection readiness and configuration completion.
   * `PeripheralManagerTransport` provides the concrete `PumpMessageTransport` bridge with packet assembly and typed response parsing.
   * Pump fault handling now includes bounded retry/backoff and fault event propagation, though further classification remains.

3. **Phase 2 – Authentication and pairing** – ✅ *Completed*
   * Complete `PumpChallengeRequestBuilder.createV2` to cover the JPake/short-PIN handshake used by newer firmware and Trio hardware, and persist resulting derived secrets/nonces into `PumpState`. ✅ *Done*
   * Extend `PumpCommSession.pair` to store authentication artifacts via `PumpStateSupplier` and surface errors meaningfully to the manager delegate. ✅ *Done*
   * Add persistence for pairing details inside `TandemPumpManagerState.rawValue` so Loop/Trio can survive restarts without re-pairing. ✅ *Done*

4. **Phase 3 – Pump session lifecycle** – ⚠️ *Partially completed*
   * `TandemPump` initiates startup status polls and bridges notifications through `PumpNotificationRouter`, but auto-reconnect logic and configuration helpers still need work.
   * Basal/bolus/temp basal/suspend flows are dispatched via `TandemPumpManager`; history streaming now flows through `HistoryLogFetcher` with telemetry scheduling hooks, but device-model detection is still outstanding.
   * Add support for identifying pump models (t:slim X2, Mobi, Trio) via BLE advertisement or version responses and update `SupportedDevices`/`MessageProps` accordingly (still missing).
   * `applyOnboardingSettings` writes the host's `PumpManagerSetupSettings` to a freshly paired
     pump: delivery limits, basal schedule, pump clock. Loop and Trio never sync these during
     onboarding, so without it the pump kept its own profile while the driver reported the app's
     (issue #206). Setup stops on a failed basal or limits write; a failed clock write does not.
     Pump sounds are not written, since onboarding collects no value for them.
   * `syncBasalRateSchedule` reads the profile back and fails with `basalProfileSyncMismatch`
     unless `pendingSegmentWrites` finds nothing left to write. `fetchBasalStatus` compares the
     pump's rate against the schedule every sync, on the pump's clock via `pumpClockOffset`, using
     `profileBasalRate` during a temp basal and skipping suspend and Control-IQ. A mismatch that
     outlives `basalMismatchConfirmationInterval` shows a critical status highlight. Nothing
     auto-corrects.

5. **Phase 4 – LoopKit/Trio integration** – ⚠️ *Partially completed*
   * Apple platforms import the real LoopKit framework, but Linux builds still rely on the stub found in `Sources/LoopKit/LoopKit.swift`.
   * `TandemPumpManagerState` persists pairing artifacts, battery/reservoir readings, basal state, and uncertainty flags, yet additional therapy settings storage is limited.
   * Pump data surfaces for battery, reservoir, basal, and bolus are wired, and alert/alarm/malfunction propagation flows through LoopKit `Alert` issuance with pump-side acknowledgement; CGM data remains to be implemented.

6. **Phase 5 – Trio-specific validation** – ❌ *Not yet started*
   * Confirm message compatibility with Trio hardware/firmware, updating opcodes or parsers where Trio deviates (e.g., Control-IQ variants, CGM sessions) — no Trio-specific coverage available.
   * Add targeted tests/fixtures for Trio logs and status responses, ensuring the driver negotiates the correct API version and pairing code path — tests not written.

7. **Phase 6 – Safety, tooling, and QA** – ❌ *Not yet started*
   * Provide user-facing controls or configuration surfaces for insulin-affecting toggles managed by `PumpStateSupplier`, including persistence and audit logging — no UI or persistence implemented.
   * Expand unit and integration tests to cover BLE packetization, authentication failure handling, and critical therapy commands — coverage still absent.
   * Document manual validation steps for hardware testing (pairing, bolus, suspend/resume), and capture known limitations or required pump firmware versions before releasing to Loop/Trio users — documentation not written.

This roadmap keeps the existing protocol/BLE groundwork intact while layering the missing pump-manager functionality required for a production Loop or Trio integration.

### Recent Automation
- [e] CentralChallengeRequestBuilder: generate 8-byte challenges, not 10
- [e] HmacSha1/HmacSha256: switch to CryptoKit/CommonCrypto-backed implementations
- [e] PumpCommSession: add DEBUG override to bypass JPake in tests
- [t] PumpChallengeRequestBuilderTests/testCreateV2AdvancesJpakeFlow: use debug hook
- [t] TandemPairingIntegrationTests/testJPAKEPairingFlowWithMockTransport: inject overrides, assert artifacts

---

## Summary: Unimplemented Behaviors (Running List)

### Critical Path Items (Blocking Basic Functionality)
1. **Finalize TandemPump configuration toggles** (`TandemPump.swift:63-86`) ✅ *Done*
   - Configuration helpers now write through to `PumpStateSupplier`, persist enablement inside manager state, and notify delegates; remaining UI gating lives elsewhere.
   - Location: `Sources/TandemKit/PumpManager/TandemPump.swift`

2. **Harden PumpComm fault handling** (`PumpComm.swift`)
   - `sendMessage` applies bounded retry/backoff on pump faults and emits decoded `PumpCommFaultEvent` details through the delegate alongside state resets.
   - Continue refining fault taxonomy for UI/LoopKit consumption.

3. **Extend telemetry surfaces** (`TandemPumpManager.swift`)
   - Alert/alarm/malfunction pipelines are implemented: `fetchNotifications()` polls the `NotificationBundle` requests and `TandemAlertReconciler` issues/retracts LoopKit `Alert`s, driven by qualifying events and by every `ensureCurrentPumpData` sync (LoopKit's ~5-minute cadence).
   - CGM pipelines using `CurrentEGVGuiDataRequest` remain to be implemented.

4. **Implement pump model detection**
   - Parse advertisements or `PumpVersionResponse` values to populate `SupportedDevices` with t:slim X2 vs. Mobi/Trio identifiers.
   - Persist the detected model inside `TandemPumpManagerState` for LoopKit UI.

5. **Add history/log streaming** (`TandemPumpManager.swift`)
   - History streaming runs through `HistoryLogFetcher`, and `HistoryBackfillCoordinator` keeps
     the session store caught up from every `syncPumpData` pass: an incremental read from the
     persisted watermark (`TandemPumpManagerState.historyBackfill`), cross-tick gap healing via
     `HistoryLogStore.missingRanges`, and a sliced walk backward to the deep-fetch boundary.
     `HistoryBackfillPlanner` holds that decision as pure arithmetic. A `.bolusChange` qualifying
     event kicks a tick as well.
   - Two feature flags, both off by default. `historyBackfill` runs the whole thing: while off,
     `runTick` returns immediately and the pump's history log is never read. `historyDoseReporting`
     decides whether doses found in that history reach the app's insulin history; it is `&&`-ed
     with `historyBackfill`, since there is nothing to report from a log never read. Neither is a
     dry run — a watermark written for entries that were never read would mark them read and
     suppress them once the flag goes on. **`historyDoseReporting` has no consumer yet**: the
     emission layer that must check it does not exist, so today it only fixes the contract that
     layer will be built against.
   - The walk is sliced at one `HistoryLogRequest` (255 entries) so dosing interleaves with it,
     but is not paced one slice per sync: a tick keeps stepping until it reaches
     `deepFetchTarget`, bounded by `maxDeepSlicesPerTick`.
   - Two distinct floors. `HistoryBackfillState.firstSeenFloor` is set at first sight, never
     moves, and alone bounds how deep the walk reads. `HistoryBackfillPlanner.emitFloor` maxes it
     with the host's `startDateToFilterNewPumpEvents` for the emission layer, and is never
     persisted — the host's date marches to ≈now as the driver reports events (Trio returns
     `lastEventDate - 15min`), so letting it bound the walk ends the backfill minutes into the
     past.
   - Still open: nothing consumes the store's contents. `HistoryToDoseMapper` is not wired to any
     emission path, so mapped doses, in-place finalization of interrupted boluses, and
     gap-aware `lastReconciliation` advancement all remain to be done.

6. **Implement TandemPumpManagerState persistence** (`TandemPumpManagerState.swift`) ✅ *Done*
   - Raw state now stores derived secret + server nonce so pairing survives restarts.

7. **Implement TandemPumpManager.connect() and disconnect()** (`TandemPumpManager.swift:133-140`) ✅ *Done*
   - Connection logic now routes through `TandemPump.startScanning()` and `PeripheralManagerTransport` instead of print stubs.

### LoopKit Integration (Required for Loop/Trio)

| Requirement | Status | Notes |
| --- | --- | --- |
| Replace placeholder LoopKit target (`Sources/LoopKit/LoopKit.swift`) | ⚠️ Partial | Apple builds import the real `LoopKitBinary`/`LoopKitUIBinary` xcframeworks, but Linux continues to compile against the pared-down shim. Contributors need to finish aligning the shim to LoopKit’s production `PumpManager` APIs or gate Linux behind the binaries. |
| `TandemPumpManager` PumpManager conformance | ✅ Complete | `TandemPumpManager` satisfies LoopKit’s `PumpManager` and `PumpManagerStatusReporting` protocols, exposing dosing commands and status accessors backed by `TandemPumpManagerState`. |
| PumpManager delegate data surfaces | ⚠️ Partial | Reservoir, battery, basal, and bolus updates reach LoopKit delegates, and alert/alarm/malfunction routing issues LoopKit `Alert`s with acknowledgement round trips. `lastReconciliation` reaches the host only through `hasNewPumpEvents`, so every successful sync, every qualifying-event fetch and every reservoir read reports it — an empty batch with `replacePendingEvents: false` when there is no dose to go with it — and a report emitted before the host attaches a delegate and queue is held and replayed from `deliverStateMissedByTheDelegate`, alongside the reservoir flush. CGM streams and `DeviceStatus` history needed by LoopKit clients remain to be implemented. |
| PumpManagerUI integration | ⚠️ Partial | The UI target re-exports the xcframeworks, but setup/fault-recovery flows still rely on placeholder views and lack production LoopKit `PumpManagerUI` screens. |

### Authentication and Pairing
11. **Implement V2 pairing (6-digit PIN)** (`PumpChallengeRequestBuilder.swift:39-44`) ✅ *Done*
    - `createV2()` now advances the JPake auth builder after a `Jpake1aResponse` and returns the next message in the flow.

12. **Implement TandemPump configuration methods** (`TandemPump.swift:63-86`) ✅ *Done*
    - Configuration helpers now forward to `PumpStateSupplier`, persist enablement into manager state, and trigger delegate updates instead of printing.

### Response Handling and Device Support
13. **Implement device model detection** ❌ *Not done*
    - Parse pump model from BLE advertisement data or `PumpVersionResponse` and persist the result.

14. **Implement message dispatchers for key operations** – ⚠️ *Partially completed*
    - Basal/bolus/temp basal/suspend dispatchers exist; history streaming now routes through `HistoryLogFetcher`, with remaining work focused on CGM/alert pathways.

15. **Implement BLE notification → PumpComm bridge** ✅ *Done*
    - `PumpNotificationRouter` validates packets and forwards typed messages into `PumpCommSession`.

### Safety and Error Handling
16. **Implement insulin delivery safety toggles** ❌ *Not done*
    - UI and persisted consent for insulin-affecting actions remain outstanding.

17. **Implement comprehensive error handling** – ⚠️ *Partially completed*
    - Basic communication errors surface today, but pump-fault decoding and retry logic are still missing.

18. **Implement therapy command validation** – ⚠️ *Partially completed*
    - `enactBolus` rejects non-positive amounts and anything above `state.settings.maxBolus`
      (seeded from `PumpManagerSetupSettings` at setup, then whatever the host app last synced).
      The pump enforces the same ceiling in firmware, because `syncDeliveryLimits` pushes it down
      via `SetMaxBolusLimitRequest`.
    - `enactBolus`/`enactTempBasal` also block while Control-IQ is active or a bolus is running.
    - There is **no IOB ceiling**: nothing in the driver polls `ControlIQIOBRequest` /
      `NonControlIQIOBRequest`, so `state.latestInsulinOnBoard` is never assigned. Wiring up
      IOB telemetry is a prerequisite for reinstating that check.
    - There is **no app-side temp basal rate check**; the pump's own max basal limit is the
      only ceiling. (`maximumTempBasalRateExceeded` was never wired up in any revision and has
      been removed rather than left as a dead enum case.)

### Testing and Validation
19. **Add missing message tests**
    - Many messages marked with "[ ] Tests" in checklist above
    - Focus on Control messages that modify insulin delivery
    - Focus on CurrentStatus messages used for Loop feedback

20. **Add integration tests**
    - BLE packetization end-to-end
    - Authentication flow (V1 and V2)
    - Critical therapy commands with mock pump
    - Error handling and fault recovery

### Test target membership
Every `.swift` file under `Tests/` must be a member of the `TandemKitTests` target, and
`scripts/check_xcodeproj_source_membership.rb` discovers `Tests/*` directories rather than
taking a registered list, so a test cannot be silently left out of CI. There is no exclusion
list — a test that stops compiling is fixed or deleted. `--fix` adds newly created files;
CI runs `--check` in every workflow.

`TandemPumpManager` takes its BLE layer through the `PumpBluetoothConnection` protocol
(`init(state:bluetooth:)`), so command sequences can be driven from tests via
`StubPumpBluetooth` without CoreBluetooth. Production still goes through `init(state:)`, which
constructs the real `TandemBluetoothManager`.

Coverage that was dropped along with the code it tested (`PumpComm` fault taxonomy and retry
policy, the `TandemBLE` packet layer, `HistoryDeduplicator`/`HistoryReconciler`/
`HistoryToDoseMapper`/`HistoryTimestampReconciler`, `PumpStateSupplier`,
`PumpChallengeRequestBuilder` and the V1 16-character pairing path) is not represented
anywhere now. If any of those behaviours come back, they need tests written against the
current architecture, not restored from git history.

21. **Add hardware validation procedures**
    - Document manual testing steps for pairing
    - Document manual testing for bolus, suspend/resume
    - Capture firmware version requirements
    - Test with t:slim X2, Mobi, and Trio hardware

### Implementation Status Legend
- ✅ **FULLY IMPLEMENTED**: Complete, working implementation
- ⚠️ **PARTIALLY IMPLEMENTED**: Some functionality exists but incomplete
- ❌ **STUB** or **NOT IMPLEMENTED**: Placeholder or missing entirely

## Recent Session Notes (Mar 2025 Audit)

### Pairing & BLE Status
- The CLI pairing path now completes a full BLE exchange: once `PeripheralManager` finishes configuration, `PairingCoordinator` spins up a background `Task.detached` that primes `JpakeAuthBuilder`, sends the first JPAKE frame through `PeripheralManagerTransport`, and then hands control to `PumpComm.pair` to finish the session. Logs capture round-trip packets plus derived-secret/server-nonce updates for post-run analysis. 
- SwiftECC still performs a heavy first-use warm-up (~10–15 s) before `builder.nextRequest()` returns, but the work happens off the main thread so BLE notifications stay live and the CLI no longer deadlocks while waiting.
- Pump-side notifications are streamed back through the delegate hooks, giving visibility into manufacturer/model detection and any unsolicited pump messages during pairing.

### Applied Changes Since Prior Notes
- JPAKE initialization moved to a detached task so the CLI remains responsive while the first round key material is generated, and the initial JPAKE request is pushed immediately after notifications come online.
- Pairing completion now logs truncated derived-secret/server-nonce values alongside the stored `PumpState`, simplifying retrieval of credentials for follow-on commands.

### Outstanding Pairing Tasks
- **JPAKE round 1 is not always 330 bytes.** `EcJpake.getRound1()` emits two length-prefixed
  `(point, ZKP)` groups, and each ZKP ends in a scalar written by `writeNum`, which uses
  `BInt.asMagnitudeBytes()` and so drops leading zero bytes. A scalar is 32 bytes only about
  255/256 of the time, so a group is 165 bytes and the payload 330 bytes only about 99.2% of the
  time; roughly 0.78% of pairings produce a short payload.
  `JpakeAuthBuilder` used to slice `clientRound1` at fixed offsets `0..<165` and `165..<330`, which
  broke both ways: a short first scalar misaligned the 1b frame, and a short second scalar failed
  the `count >= 330` guard and dropped the builder into `.INVALID`. Either way pairing failed
  non-deterministically with no actionable error.
  Fixed by `JpakeRound1Framing`: split on the real group boundary and right-pad each frame to 165
  with zero bytes. The pump's parser is length-prefixed, so it stops at the end of the group and
  never reads the padding — the same reason `Jpake1aRequest.normalizeChallenge` could already pad.
  The reassembly side (`joinRound1`) strips the first frame's padding before concatenating, because
  the pump pads its own halves for the same reason and raw concatenation would misalign the second
  group.
  Note pumpX2 has the same fixed-offset slicing and is *not* fully correct here: Java's
  `Arrays.copyOfRange` zero-fills past the end of the array, which happens to cover the short-second
  -scalar case, but the short-first case still misaligns its 1b frame. Verified against
  `jwoglom/pumpX2` `JpakeAuthBuilder.java` / `io.particle.crypto.EcJpake`.
  The framing is unit-tested; the end-to-end behaviour against real pump firmware is not, so this
  wants confirmation on hardware.
- Trim SwiftECC start-up latency: first-round generation still takes >10 s, so we need either a pre-warm hook or an alternative ECC backend to keep the UX within expected pairing windows.
- Exercise the full multi-round exchange (including the legacy challenge) under real hardware to ensure `PumpComm.pair` handles back-to-back responses and that background pairing does not race the timeout scheduler.
- Add coverage for failure surfaces (e.g. invalid pairing codes, mid-handshake disconnects) so the CLI and manager surface actionable errors instead of generic timeouts.

### LoopKit Compatibility Risks & Dependencies
- Apple-platform builds resolve `LoopKit`/`LoopKitUI` from the surrounding Xcode workspace, which must build them — Trio's workspace does, via its `loopandlearn/LoopKit` submodule. SwiftPM cannot build these targets at all; see the comment atop `Package.swift`.
- `LoopKitUI` re-exports `LoopKitUIBinary`, and `TandemKitPlugin` expects the full `PumpManagerUI` APIs. Verify the shipped binaries expose the same protocol surface as our Linux stubs to avoid compile-time drift when swapping in official LoopKit frameworks.
