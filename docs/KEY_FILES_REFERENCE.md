# TandemKit key files

A map of where things live. [ARCHITECTURE_ANALYSIS.md](ARCHITECTURE_ANALYSIS.md) explains how the
pieces fit together. Paths are relative to the repository root.

## Pump manager — `Sources/TandemKit/PumpManager/`

| File | What it holds |
| --- | --- |
| `TandemPumpManager.swift` | The `PumpManager` conformance, including the dosing commands (`enactBolus`, `cancelBolus`, `enactTempBasal`, `suspendDelivery`, `resumeDelivery`), `syncPumpData`, `handleQualifyingEvents`, alert acknowledgement, pump event delivery to the host (`emitPumpEvents`) and `CommandWatchdog`. |
| `TandemPumpManager+StateSync.swift` | The `fetch…` status reads applied to state on every sync, bolus finalization, and the basal rate check (`verifyDeliveredBasalRate`). |
| `TandemPumpManager+SyncBasal.swift` | Writes the basal schedule to the pump's IDP profile through `IDPManager` and reads it back. |
| `TandemPumpManager+Onboarding.swift` | `applyOnboardingSettings`: delivery limits, basal schedule and clock for a newly paired pump (#206). |
| `TandemPumpManager+Alerts.swift` | Maps pump notifications to LoopKit `Alert`s and reconciles them. |
| `TandemPumpManager+HistoryStore.swift` | Stores and prunes streamed history logs in the session store. |
| `TandemPumpManager+HistoryDoseReporting.swift` | Reports boluses found in pump history that the live path missed. |
| `QualifyingEventFetch.swift` | Maps pumpX2's suggested handlers for each qualifying event onto the manager's fetches. |
| `PumpBluetoothConnection.swift` | The protocol everything above the BLE layer talks through. |
| `TandemBluetoothManager.swift` | `CBCentralManager`, the serial command queue (`ensureConnected`), connect, reconnect and scan. |
| `TandemPeripheralManager.swift` | `CBPeripheral`: session setup (`performInitialSetup`), the write/response path, and routing notifications by characteristic. |
| `HistoryLogFetcher.swift` | Reads a window of history logs in 255-entry chunks with gap healing, using the store before the pump. |
| `PumpTelemetryScheduler.swift` | Timer helper. Used today only for the 1 s bolus progress poll. |
| `TandemDoseProgressReporter.swift` | LoopKit `DoseProgressReporter` for a running bolus. |
| `BolusEndDate.swift` | Dates a finished bolus from the pump's timestamps rather than from when completion was noticed (#339). |
| `PumpConnectionIssue.swift` | Why the pump is unreachable (Bluetooth off, unauthorized, out of range), for the UI. |
| `ControlIQConfigurationError.swift` | Validation errors from `configureControlIQMode`. |
| `TandemSilentToneManager.swift` | Plays silent audio in the background to keep the app alive when silent mode is on. |
| `VirtualPump/` | CoreBluetooth stand-ins that talk to faketandem over a socket. Compiled only under `TANDEMKIT_VIRTUAL_PUMP`. |

### History — `Sources/TandemKit/PumpManager/History/`

| File | What it holds |
| --- | --- |
| `HistoryBackfillCoordinator.swift` | Runs a backfill tick from each sync and each `.bolusChange` event. |
| `HistoryBackfillPlanner.swift` | Pure arithmetic: the next range to read and the reporting floor. |
| `HistoryBackfillState.swift` | The persisted watermark and `firstSeenFloor`. |
| `HistoryFetchGate.swift` | Lets one history reader at a time hold the pump's history stream. |
| `HistoryLogStore.swift`, `InMemoryHistoryLogStore.swift`, `StoredHistoryLog.swift` | The session-scoped raw history store. It is not persisted (#232). |
| `HistoryToDoseMapper.swift` | History records → `NewPumpEvent`s. |
| `HistoryTimestampReconciler.swift` | Pump timestamps → UTC, corrected for clock changes recorded in the log. |
| `HistoryLogSyncIdentifier.swift` | Stable `raw` identifiers for history-derived doses (#344). |
| `BolusReportLedger.swift` | Persisted record of recent boluses, so history does not report app boluses a second time. |

## State — `Sources/TandemKit/State/`

| File | What it holds |
| --- | --- |
| `TandemPumpManagerState.swift` | The host-persisted `rawState`. |
| `PumpState.swift` | Pairing artifacts (`derivedSecret`, `serverNonce`, `pincode`, `peripheralUuid`), `timeSinceReset`, API version, serial number and `pumpModel`. `getAuthKey()` derives the signing key. |
| `TandemPumpManagerSettings.swift` | Max bolus, max temp basal and max schedule entry. |
| `TandemFeatureFlags.swift` | `controlIQSupport`, `quickBolusButtonSupport`, `historyBackfill`, `historyDoseReporting`. |

## Protocol — `Sources/TandemCore/`

| Path | What it holds |
| --- | --- |
| `Messages/Message.swift` | `Message`, `PumpRequest` and `MessageProps`. |
| `Messages/MessageRegistry.swift` | The catalog: response lookup by opcode and characteristic, request/response pairing, lookup by name. |
| `Messages/Packetizer.swift` | `Packetize.parse` (header, HMAC-SHA1 signing, CRC, chunking) and `Packet`. |
| `Messages/BTResponseParser.swift` | Reassembles notification packets into a typed response. |
| `Messages/ErrorResponse.swift` | The pump's refusal of a request. |
| `Messages/Authentication/`, `Control/`, `ControlStream/`, `CurrentStatus/`, `HistoryLog/`, `QualifyingEvent/` | Message types. A request and its response share a file; history records have one file per type, decoded by `HistoryLog/HistoryLogParser.swift`. |
| `Messages/Models/` | Shared message models: `KnownApiVersion`, `SupportedDevices`, `MessageSupport` (`isSupported(pumpModel:apiVersion:)`), `PumpFaultCode` and others. |
| `CharacteristicUUID.swift`, `ServiceUUID.swift` | BLE UUIDs and the list of characteristics subscribed for notifications. |
| `Builders/JpakeAuthBuilder.swift`, `JpakeStep.swift` | The JPAKE state machine: full pairing, or confirmation only from a stored secret. |
| `Builders/JpakeRound1Framing.swift` | Splits round 1 on the real group boundary and pads each frame. |
| `Builders/EcJpake.swift`, `SwiftECCJpakeProvider.swift` | EC-JPAKE on SwiftECC. Apple platforms only; a trapping stub on Linux. |
| `Builders/Hkdf.swift`, `HmacSha256.swift`, `Common/HmacSha1.swift`, `Common/SHA1.swift`, `Common/SHA256.swift`, `Common/CRC16.swift` | Crypto and checksum primitives. |
| `Builders/IDPManager.swift` | Reads and edits insulin delivery profiles (pumpX2's `IDPManager`). |
| `Builders/*RequestBuilder.swift` | Pick the request variant for the pump's API version. |
| `NotificationBundle.swift`, `MergedNotification.swift`, `PumpNotificationAlert.swift`, `TandemAlertReconciler.swift` | Pump alerts, alarms, reminders and malfunctions: collection, grouping, severity and LoopKit alert reconciliation. |
| `PumpCommError.swift` | Driver error type surfaced to LoopKit. |
| `Common/TandemClock.swift` | `TandemClock`, `SystemClock` and `ManualClock`. |
| `Common/TandemDispatchGroup.swift` | Single-shot wait/signal used for every BLE operation. |
| `Common/TandemLogger.swift` | OSLog plus file logging on Apple platforms; swift-log on Linux. |
| `Common/UnfinalizedDose.swift` | An in-flight bolus, temp basal or suspend before it is finalized. |
| `Common/TandemPumpCapabilities.swift` | Supported bolus volumes and basal rates. |
| `Common/HistoryLogTimeIndex.swift` | Maps between sequence numbers and dates for the history viewer. |

## UI — `Sources/TandemKitUI/`, `Sources/TandemKitPlugin/`

| Path | What it holds |
| --- | --- |
| `TandemPumpManager+UI.swift` | `PumpManagerUI`: setup, settings and delivery-uncertainty view controllers, HUD, status highlights. |
| `TandemUICoordinator.swift` | `TandemScreen` and navigation between the SwiftUI screens. |
| `TandemKitHUDProvider.swift` | The HUD shown in the host's status bar. |
| `Views/`, `ViewModels/` | Onboarding (scan and pair), settings, cartridge/tubing/cannula wizards, CGM setup, notifications, Control-IQ, quick bolus, debug tools, the history log viewer. |
| `Sources/TandemKitPlugin/TandemKitPlugin.swift` | Loop-style plugin entry point. Not used by Trio. |

## Tests

| Path | What it covers |
| --- | --- |
| `Tests/TandemCoreTests/` | Message serialization (`TestHelpers/MessageTester.swift`, `HistoryLogMessageTester.swift`), JPAKE, framing, notification bundle, alert reconciliation. |
| `Tests/TandemKitTests/` | `TandemPumpManager` behaviour through `StubPumpBluetooth.swift`, history backfill and reporting, UI view models, and the virtual CoreBluetooth. |
| `Tests/TandemKitIntegrationTests/` | The real driver against faketandem, including `Conformance/` (LoopKit dose-reporting scenarios and oracles). See [integration-harness.md](integration-harness.md) and [conformance-test-plan.md](conformance-test-plan.md). |

## Build and CI

| Path | What it holds |
| --- | --- |
| `TandemKit.xcodeproj` | The supported build. |
| `Package.swift` | Linux build only (see the comment at its top). |
| `LinuxShims/` | Fakes of LoopKit, HealthKit, CoreBluetooth and Combine for Linux. Read its README before adding to one. |
| `VirtualPump.xcconfig` | Sets `TANDEMKIT_VIRTUAL_PUMP`. |
| `scripts/test-local.sh`, `scripts/integration-test.sh` | Local unit and integration test runs. |
| `scripts/check_xcodeproj_source_membership.rb` | Checks that every test file is in `TandemKitTests` (`--check`, `--fix`). |
| `scripts/claude-web-setup.sh` | Toolchain setup for Linux agent sessions. |
| `.github/workflows/linux.yml`, `macos.yml` | CI: Linux plain, virtual-pump, faketandem and two integration jobs; macOS unit and integration jobs. |
