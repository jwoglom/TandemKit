## Message types by category

### Authentication

| Area | Status | Notes |
| --- | --- | --- |
| Message catalog (`Sources/TandemCore/Messages/Authentication`) | ✅ Complete | All authentication requests and responses serialize/deserialize correctly per the audit’s protocol review. |
| Unit tests | ✅ Complete | `TandemCoreTests` exercises JPake rounds, pump challenges, and the central challenge flow; no outstanding gaps were identified in the audit. |
| Pairing flow implementation (`PumpCommSession`, `PumpChallengeRequestBuilder`) | ✅ Complete | Legacy 16-character and JPake PIN flows advance correctly and persist derived secrets/nonces as required for PumpManager reconnection. |
| Cross-platform dependency story | ⚠️ Partial | SwiftECC/BigInt remain required for JPake; Linux builds function through the shim, but deterministic RNG configuration for CI is still pending. |

### Control

| Area | Status | Notes |
| --- | --- | --- |
| Message catalog (`Sources/TandemCore/Messages/Control`) | ✅ Complete | Full suite of Tandem control requests/responses is implemented with correct serialization metadata. |
| Command validation (`TandemPumpManager`, `PumpStateSupplier`) | ✅ Complete | Bolus, temp basal, suspend/resume, and configuration requests enforce LoopKit `PumpManager` safety limits before dispatch. |
| Unit tests (requests) | ✅ Complete | Core therapy commands and high-risk configuration requests are covered in `TandemCoreTests`. |
| Unit tests (responses & long tail) | ⚠️ Partial | Many responses and less frequently used configuration messages lack direct coverage; additional fixtures needed to satisfy LoopKit QA expectations. |
| Transport orchestration (`PumpComm`, `PeripheralManagerTransport`) | ⚠️ Partial | Message dispatch works, but retry/backoff handling for pump faults is pending per audit. |

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
   - [ ] Tests for ExitFillTubingModeStateStreamResponse
- [x] FillCannulaStateStreamResponse
   - [ ] Tests for FillCannulaStateStreamResponse
- [x] FillTubingStateStreamResponse
   - [ ] Tests for FillTubingStateStreamResponse
- [x] PumpingStateStreamResponse

### CurrentStatus
Requests:
- [x] AlarmStatusRequest
   - [ ] Tests for AlarmStatusRequest
- [x] AlertStatusRequest
   - [ ] Tests for AlertStatusRequest
- [x] ApiVersionRequest
   - [x] Tests for ApiVersionRequest
- [x] BasalIQAlertInfoRequest
   - [ ] Tests for BasalIQAlertInfoRequest
- [x] BasalIQSettingsRequest
   - [ ] Tests for BasalIQSettingsRequest
- [x] BasalIQStatusRequest
   - [ ] Tests for BasalIQStatusRequest
- [x] BasalLimitSettingsRequest
   - [ ] Tests for BasalLimitSettingsRequest
- [x] BolusCalcDataSnapshotRequest
   - [ ] Tests for BolusCalcDataSnapshotRequest
- [x] BolusPermissionChangeReasonRequest
   - [ ] Tests for BolusPermissionChangeReasonRequest
- [x] CGMAlertStatusRequest
   - [ ] Tests for CGMAlertStatusRequest
- [x] CGMGlucoseAlertSettingsRequest
   - [ ] Tests for CGMGlucoseAlertSettingsRequest
- [x] CGMHardwareInfoRequest
   - [ ] Tests for CGMHardwareInfoRequest
- [x] CGMOORAlertSettingsRequest
   - [ ] Tests for CGMOORAlertSettingsRequest
- [x] CGMRateAlertSettingsRequest
   - [ ] Tests for CGMRateAlertSettingsRequest
- [x] CGMStatusRequest
   - [ ] Tests for CGMStatusRequest
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
   - [ ] Tests for CurrentBatteryV1Request
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
   - [ ] Tests for GlobalMaxBolusSettingsRequest
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
   - [ ] Tests for AlarmStatusResponse
- [x] AlertStatusResponse
   - [ ] Tests for AlertStatusResponse
- [x] ApiVersionResponse
   - [ ] Tests for ApiVersionResponse
- [x] BasalIQAlertInfoResponse
   - [ ] Tests for BasalIQAlertInfoResponse
- [x] BasalIQSettingsResponse
   - [ ] Tests for BasalIQSettingsResponse
- [x] BasalIQStatusResponse
   - [ ] Tests for BasalIQStatusResponse
- [x] BasalLimitSettingsResponse
   - [ ] Tests for BasalLimitSettingsResponse
- [x] BolusCalcDataSnapshotResponse
   - [ ] Tests for BolusCalcDataSnapshotResponse
- [x] BolusPermissionChangeReasonResponse
   - [ ] Tests for BolusPermissionChangeReasonResponse
- [x] CGMAlertStatusResponse
   - [ ] Tests for CGMAlertStatusResponse
- [x] CGMGlucoseAlertSettingsResponse
   - [ ] Tests for CGMGlucoseAlertSettingsResponse
- [x] CGMHardwareInfoResponse
   - [ ] Tests for CGMHardwareInfoResponse
- [x] CGMOORAlertSettingsResponse
   - [ ] Tests for CGMOORAlertSettingsResponse
- [x] CGMRateAlertSettingsResponse
   - [ ] Tests for CGMRateAlertSettingsResponse
- [x] CGMStatusResponse
   - [ ] Tests for CGMStatusResponse
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
   - [ ] Tests for CurrentBatteryV1Response
- [x] CurrentBatteryV2Response
   - [ ] Tests for CurrentBatteryV2Response
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
   - [ ] Tests for GlobalMaxBolusSettingsResponse
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

---

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
* **Utility surface area** – ✅ **FULLY IMPLEMENTED**: `PumpStateSupplier` provides complete pairing code validation/sanitization (`sanitizeAndStorePairingCode`), authentication key derivation (`authenticationKey`), and configuration flags for insulin-affecting actions. Command-line target (`Sources/TandemCLI`) exposes decode/encode/list tooling.
* **Existing validation** – ⚠️ **PARTIAL**: Unit tests cover message metadata, pairing-code validation, and JPake builder behavior. Many message types in AGENTS.md checklist are marked as lacking tests.

### Gaps Blocking a Functional Loop/Trio Pump Driver

#### 1. LoopKit/Trio Integration (STUBS)
* **`Sources/LoopKit/LoopKit.swift`** – ❌ **STUB**: Only minimal protocol definitions (`PumpManager`, `PumpManagerDelegate`, `PumpManagerUI`, `CGMManagerUI`). No actual LoopKit framework integration.
* **`TandemPumpManager`** (`Sources/TandemKit/PumpManager/TandemPumpManager.swift`) – ❌ **MOSTLY STUB**:
  - `connect()` and `disconnect()` are just print statements (lines 133-140)
  - Delegate assignments are commented out (lines 96-97, 109-110)
  - `pairPump()` has basic implementation but only for UIKit platforms
  - No dosing interfaces (bolus, temp basal, suspend/resume) implemented
  - No status reporting to LoopKit delegates
  - No reservoir, battery, or CGM data surfaces
* **`TandemPumpManagerState`** (`Sources/TandemKit/PumpManager/TandemPumpManagerState.swift`) – ⚠️ **PARTIALLY IMPLEMENTED**:
  - Serializes/deserializes `PumpState` including derived secret and server nonce
  - Still lacks storage for therapy settings, pump status snapshots, and LoopKit-facing metadata

#### 2. Pump Session Orchestration (INCOMPLETE)
* **`TandemPump`** (`Sources/TandemKit/PumpManager/TandemPump.swift`) – ⚠️ **PARTIALLY IMPLEMENTED**:
  - Uses the production `BluetoothManager`/`PeripheralManager` from `TandemBLE` for scanning, connection management, and startup message dispatch (`startScanning`, `disconnect`, `sendDefaultStartupRequests`).
  - Still exposes configuration helpers (`enableActionsAffectingInsulinDelivery`, etc.) that only print diagnostics and do not yet toggle any real pump state.
* **`PumpComm`** (`Sources/TandemKit/PumpManager/PumpComm.swift`) – ⚠️ **PARTIALLY IMPLEMENTED**:
  - Delegates to `PumpCommSession` for pairing and state updates and relays typed notifications back to the manager.
  - Core send/receive flows work through the transport, but higher-level fault/retry logic is still minimal.
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
* **Status updates** – ⚠️ Basal/bolus/battery/reservoir polling and notification handling feed LoopKit delegates, but history streaming and alert/CGM pipelines remain unimplemented.

#### 5. Safety and Gating
* **Insulin delivery toggles** – ⚠️ `PumpStateSupplier` exposes enablement flags, but the TandemPump configuration helpers remain stubs and there is no UI/persistence yet.
* **Therapy command safeguards** – ⚠️ `TandemPumpManager` validates bolus amounts, max temp basal rates, and IOB limits before issuing commands, but additional safety interlocks (e.g. user acknowledgements) are still pending.
* **Error handling** – ⚠️ Transport/pump communication errors bubble back through delegate callbacks with state resets, yet pump fault classification and retry strategies remain to be built.

### Proposed Roadmap
1. **Phase 0 – Environment & dependency alignment** – ❌ *Not yet started*
   * Ensure Carthage frameworks (LoopKit, etc.) build locally; replace the `LoopKit` stub with the actual dependency surfaces or modular shims required for Linux testing (still pending; Linux builds rely on the stub).
   * Document and script any additional SwiftECC/BigInt/CryptoKit requirements so the JPake path builds in CI (no automation or documentation present).

2. **Phase 1 – Transport consolidation** – ⚠️ *Partially completed*
   * `TandemPump` now uses the real `BluetoothManager`/`PeripheralManager` and wires delegate callbacks for connection readiness and configuration completion.
   * `PeripheralManagerTransport` provides the concrete `PumpMessageTransport` bridge with packet assembly and typed response parsing.
   * Pump fault/retry handling inside `PumpComm.sendMessage` is still minimal compared to the desired design.

3. **Phase 2 – Authentication and pairing** – ✅ *Completed*
   * Complete `PumpChallengeRequestBuilder.createV2` to cover the JPake/short-PIN handshake used by newer firmware and Trio hardware, and persist resulting derived secrets/nonces into `PumpState`. ✅ *Done*
   * Extend `PumpCommSession.pair` to store authentication artifacts via `PumpStateSupplier` and surface errors meaningfully to the manager delegate. ✅ *Done*
   * Add persistence for pairing details inside `TandemPumpManagerState.rawValue` so Loop/Trio can survive restarts without re-pairing. ✅ *Done*

4. **Phase 3 – Pump session lifecycle** – ⚠️ *Partially completed*
   * `TandemPump` initiates startup status polls and bridges notifications through `PumpNotificationRouter`, but auto-reconnect logic and configuration helpers still need work.
   * Basal/bolus/temp basal/suspend flows are dispatched via `TandemPumpManager`, yet history streaming and device-model detection are still outstanding.
   * Add support for identifying pump models (t:slim X2, Mobi, Trio) via BLE advertisement or version responses and update `SupportedDevices`/`MessageProps` accordingly (still missing).

5. **Phase 4 – LoopKit/Trio integration** – ⚠️ *Partially completed*
   * Apple platforms import the real LoopKit framework, but Linux builds still rely on the stub found in `Sources/LoopKit/LoopKit.swift`.
   * `TandemPumpManagerState` persists pairing artifacts, battery/reservoir readings, basal state, and uncertainty flags, yet additional therapy settings storage is limited.
   * Pump data surfaces for battery, reservoir, basal, and bolus are wired; CGM data, alerts, and alarm propagation remain to be implemented.

6. **Phase 5 – Trio-specific validation** – ❌ *Not yet started*
   * Confirm message compatibility with Trio hardware/firmware, updating opcodes or parsers where Trio deviates (e.g., Control-IQ variants, CGM sessions) — no Trio-specific coverage available.
   * Add targeted tests/fixtures for Trio logs and status responses, ensuring the driver negotiates the correct API version and pairing code path — tests not written.

7. **Phase 6 – Safety, tooling, and QA** – ❌ *Not yet started*
   * Provide user-facing controls or configuration surfaces for insulin-affecting toggles managed by `PumpStateSupplier`, including persistence and audit logging — no UI or persistence implemented.
   * Expand unit and integration tests to cover BLE packetization, authentication failure handling, and critical therapy commands; automate end-to-end smoke tests via `tandemkit-cli` where possible — coverage still absent.
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
1. **Finalize TandemPump configuration toggles** (`TandemPump.swift:63-86`)
   - Replace diagnostic printouts with real `PumpStateSupplier` wiring for insulin-delivery gating and connection sharing.
   - Location: `Sources/TandemKit/PumpManager/TandemPump.swift`

2. **Harden PumpComm fault handling** (`PumpComm.swift`)
   - Add retry/backoff logic and detailed fault decoding when `sendMessage` receives pump error responses.
   - Surface categorized errors back through `PumpManager` delegates for UI/LoopKit consumption.

3. **Extend telemetry surfaces** (`TandemPumpManager.swift`)
   - Implement CGM, alert, and alarm pipelines using `CurrentEGVGuiDataRequest`, `AlarmStatusRequest`, and `AlertStatusRequest`.

4. **Implement pump model detection**
   - Parse advertisements or `PumpVersionResponse` values to populate `SupportedDevices` with t:slim X2 vs. Mobi/Trio identifiers.
   - Persist the detected model inside `TandemPumpManagerState` for LoopKit UI.

5. **Add history/log streaming** (`TandemPumpManager.swift`)
   - Provide message dispatchers for pump history packets and expose results via LoopKit-style callbacks or storage.

6. **Implement TandemPumpManagerState persistence** (`TandemPumpManagerState.swift`) ✅ *Done*
   - Raw state now stores derived secret + server nonce so pairing survives restarts.

7. **Implement TandemPumpManager.connect() and disconnect()** (`TandemPumpManager.swift:133-140`) ✅ *Done*
   - Connection logic now routes through `TandemPump.startScanning()` and `PeripheralManagerTransport` instead of print stubs.

### LoopKit Integration (Required for Loop/Trio)

| Requirement | Status | Notes |
| --- | --- | --- |
| Replace placeholder LoopKit target (`Sources/LoopKit/LoopKit.swift`) | ⚠️ Partial | Apple builds import the real `LoopKitBinary`/`LoopKitUIBinary` xcframeworks, but Linux continues to compile against the pared-down shim. Contributors need to finish aligning the shim to LoopKit’s production `PumpManager` APIs or gate Linux behind the binaries. |
| `TandemPumpManager` PumpManager conformance | ✅ Complete | `TandemPumpManager` satisfies LoopKit’s `PumpManager` and `PumpManagerStatusReporting` protocols, exposing dosing commands and status accessors backed by `TandemPumpManagerState`. |
| PumpManager delegate data surfaces | ⚠️ Partial | Reservoir, battery, basal, and bolus updates reach LoopKit delegates, yet CGM streams, alert/alarm routing, and `DeviceStatus` history needed by LoopKit clients remain to be implemented. |
| PumpManagerUI integration | ⚠️ Partial | The UI target re-exports the xcframeworks, but setup/fault-recovery flows still rely on placeholder views and lack production LoopKit `PumpManagerUI` screens. |

### Authentication and Pairing
11. **Implement V2 pairing (6-digit PIN)** (`PumpChallengeRequestBuilder.swift:39-44`) ✅ *Done*
    - `createV2()` now advances the JPake auth builder after a `Jpake1aResponse` and returns the next message in the flow.

12. **Implement TandemPump configuration methods** (`TandemPump.swift:63-86`) ❌ *Not done*
    - Replace print statements with actual calls to `PumpStateSupplier` for connection sharing and insulin gating.

### Response Handling and Device Support
13. **Implement device model detection** ❌ *Not done*
    - Parse pump model from BLE advertisement data or `PumpVersionResponse` and persist the result.

14. **Implement message dispatchers for key operations** – ⚠️ *Partially completed*
    - Basal/bolus/temp basal/suspend dispatchers exist; history streaming is still absent.

15. **Implement BLE notification → PumpComm bridge** ✅ *Done*
    - `PumpNotificationRouter` validates packets and forwards typed messages into `PumpCommSession`.

### Safety and Error Handling
16. **Implement insulin delivery safety toggles** ❌ *Not done*
    - UI and persisted consent for insulin-affecting actions remain outstanding.

17. **Implement comprehensive error handling** – ⚠️ *Partially completed*
    - Basic communication errors surface today, but pump-fault decoding and retry logic are still missing.

18. **Implement therapy command validation** ✅ *Done*
    - `TandemPumpManager` enforces bolus limits, max temp basal rates, and IOB ceilings before sending commands.

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
- Trim SwiftECC start-up latency: first-round generation still takes >10 s, so we need either a pre-warm hook or an alternative ECC backend to keep the UX within expected pairing windows.
- Exercise the full multi-round exchange (including the legacy challenge) under real hardware to ensure `PumpComm.pair` handles back-to-back responses and that background pairing does not race the timeout scheduler.
- Add coverage for failure surfaces (e.g. invalid pairing codes, mid-handshake disconnects) so the CLI and manager surface actionable errors instead of generic timeouts.

### LoopKit Compatibility Risks & Dependencies
- Apple-platform builds now rely on the Carthage-sourced `LoopKit.xcframework` and `LoopKitUI.xcframework`; consumers must supply matching binaries or the SPM package will fail to resolve these binary targets. Document the required versions and distribution story alongside the package.
- `LoopKitUI` re-exports `LoopKitUIBinary`, and `TandemKitPlugin` expects the full `PumpManagerUI` APIs. Verify the shipped binaries expose the same protocol surface as our Linux stubs to avoid compile-time drift when swapping in official LoopKit frameworks.
