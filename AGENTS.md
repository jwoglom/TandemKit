## Reference material
- See [docs/ARCHITECTURE_ANALYSIS.md](docs/ARCHITECTURE_ANALYSIS.md) and [docs/KEY_FILES_REFERENCE.md](docs/KEY_FILES_REFERENCE.md) for deeper implementation notes and file-level pointers.
- [docs/integration-harness.md](docs/integration-harness.md): the `TandemKitIntegrationTests` target, which runs the real driver against the faketandem emulator (`scripts/integration-test.sh`), and the emulator gaps it currently works around.

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

## Tests and builds

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

### Virtual pump build
`TANDEMKIT_VIRTUAL_PUMP` (a Swift compilation condition, DEBUG only; `xcodebuild -xcconfig
VirtualPump.xcconfig` sets it) compiles `Sources/TandemKit/PumpManager/VirtualPump/`, whose
`CBCentralManager`/`CBPeripheral`/`CBService`/`CBCharacteristic` shadow CoreBluetooth's throughout
the module and talk to faketandem over a socket at `VirtualPump.endpoint`
(`TANDEMKIT_VIRTUAL_PUMP=host:port` in the app's environment). Without the flag that directory
compiles to nothing and the driver runs on real CoreBluetooth, unchanged. On Linux:
`swift test --build-path .build-virtual -Xswiftc -DTANDEMKIT_VIRTUAL_PUMP`. Test files import both, so
`Tests/TandemKitTests/VirtualCoreBluetoothNames.swift` pins the names; `VirtualCoreBluetoothTests`
exists only in a flagged build, which the `integration` job in `.github/workflows/macos.yml` and
the `virtual-pump` job in `.github/workflows/linux.yml` both run.

Coverage that was dropped along with the code it tested (`PumpComm` fault taxonomy and retry
policy, the `TandemBLE` packet layer, `HistoryDeduplicator`/`HistoryReconciler`/
`HistoryToDoseMapper`/`HistoryTimestampReconciler`, `PumpStateSupplier`,
`PumpChallengeRequestBuilder` and the V1 16-character pairing path) is not represented
anywhere now. If any of those behaviours come back, they need tests written against the
current architecture, not restored from git history.

### Message serialization tests
Serialization tests go in `Tests/TandemCoreTests/Messages/<Category>/<Type>Tests.swift`, and
history records in `Tests/TandemCoreTests/HistoryLog/`. They use `MessageTester` /
`HistoryLogMessageTester` with hex taken from pumpX2's tests or captured from a pump. Name the
file after the type, so coverage can be found by filename.

Manager tests go through `StubPumpBluetooth`, which returns constructed response objects and
never encodes or decodes cargo, so they say nothing about the wire format. The integration tests
do exercise it, against pumpX2's encoder via faketandem, but only for the flows they run.

These messages are sent or decoded by the driver and have no serialization test for the request,
the response, or both. Write tests for these before the rest of the catalog:
- Commands that change delivery or delivery limits: `SetTempRate`, `StopTempRate`,
  `SuspendPumping`, `SetMaxBolusLimit`, `SetMaxBasalLimit`, `SetIDPSegment` and `SetModes`
  (both sides); the responses to `InitiateBolus`, `CancelBolus`, `ResumePumping`, `CreateIDP`,
  `DeleteIDP` and `SetActiveIDP`.
- Status reads the driver acts on: `CurrentBasalStatus`, `CurrentBolusStatus`, `InsulinStatus`,
  `TempRate`, `LastBolusStatus`, `LastBolusStatusV2`, `TimeSinceReset`, `PumpVersionB`,
  `PumpGlobals`, `ControlIQInfoV1`, `ControlIQInfoV2`, `ControlIQSleepSchedule`,
  `ProfileStatus`, `IDPSettings`, `IDPSegment`, `HistoryLogStatus`, `HistoryLog`,
  `MalfunctionStatus`, `HighestAam` and `ActiveAamBits` (both sides); `ApiVersionResponse`,
  `BolusPermissionResponse`, `CGMStatusV2Request`, `CurrentBatteryV2Request`,
  `LastBolusStatusV3Request` and `HistoryLogStreamResponse`.
- Cartridge, CGM and settings commands: `SetG6TransmitterId`, `SetSensorType`,
  `StartDexcomG6SensorSession`, `StopDexcomCGMSensorSession`, `SetSleepSchedule`,
  `SetPumpSounds` and `SetPumpAlertSnooze` (both sides); the responses to
  `EnterChangeCartridgeMode`, `ExitChangeCartridgeMode`, `EnterFillTubingMode`,
  `ExitFillTubingMode`, `FillCannula`, `ChangeControlIQSettings`, `ChangeTimeDate`,
  `DismissNotification`, `SetQuickBolusSettings` and `SetDexcomG7PairingCode`; and the
  `DetectingCartridge`, `EnterChangeCartridgeMode`, `FillCannula` and `FillTubing` state streams.

### LoopKit and Linux
- Apple-platform builds resolve `LoopKit`/`LoopKitUI` from the surrounding Xcode workspace, which must build them — Trio's workspace does, via its `loopandlearn/LoopKit` submodule. SwiftPM cannot build these targets at all; see the comment atop `Package.swift`.
- Linux builds compile against the fakes in `LinuxShims/`, which can drift from the real LoopKit;
  read `LinuxShims/README.md` before adding to one. SwiftECC does not build on Linux, so fresh
  JPAKE pairing (and its tests) run only on Apple platforms.

## Driver behaviour
Rules that are easy to break without noticing. The overall design is in
[docs/ARCHITECTURE_ANALYSIS.md](docs/ARCHITECTURE_ANALYSIS.md).

### Qualifying events
`QualifyingEvent.suggestedHandlers` / `groupSuggestedHandlers` are ported from pumpX2's
suggested-handler table, including the version-dependent Control-IQ info / last-bolus / battery /
IOB request selection. `QualifyingEventContext` carries the api version, Control-IQ support, and
in-progress bolus id that pumpX2 reads out of its global `PumpStateSupplier`.
`groupSuggestedHandlers` dedupes by request type *and* cargo (`ActiveAamBitsRequest` differs only
by cargo) and drops requests whose `minApi` is newer than the pump's.

`QualifyingEventFetch` (`Sources/TandemKit/PumpManager`) maps each *suggested-handler request*
onto the `TandemPumpManager` status fetch that both issues it and applies the response, so the
ported catalog stays the single source of truth instead of a second event table that could drift.
`handleQualifyingEvents` runs the deduped set on the command queue and acknowledges afterwards. A
request that maps to no fetch is not sent: nothing in the driver consumes IOB, CGM/EGV, home
screen mirror, profile status, Basal-IQ, temp rate, localization, load status or bolus permission
change reason today, so `iobChange`, `bg`, `cgmChange`, `basalIQ`, `basalIQStatus`,
`controlIQSleep`, `extendedBolusChange`, `pumpingStatus` and `bolusPermissionRevoked` currently
fetch nothing. Two deliberate additions to pumpX2's table: `pumpSuspend`/`pumpResume` refresh the
basal status, since that is what emits the suspend/resume dose to LoopKit, and
`profileChange`/`activeProfileSegmentChange` refresh it so the basal rate check runs on a profile
edit instead of at the next sync.

### Onboarding and the basal schedule
- `applyOnboardingSettings` writes the host's `PumpManagerSetupSettings` to a freshly paired
  pump: delivery limits, basal schedule, pump clock. Loop and Trio never sync these during
  onboarding, so without it the pump kept its own profile while the driver reported the app's
  (issue #206). Setup stops on a failed basal or limits write; a failed clock write does not.
  Pump sounds are not written, since onboarding collects no value for them.
- `syncBasalRateSchedule` reads the profile back and fails with `basalProfileSyncMismatch`
  unless `pendingSegmentWrites` finds nothing left to write. `fetchBasalStatus` compares the
  pump's rate against the schedule every sync, on the pump's clock via `pumpClockOffset`, using
  `profileBasalRate` during a temp basal and skipping suspend and Control-IQ. A mismatch that
  outlives `basalMismatchConfirmationInterval` shows a critical status highlight. Nothing
  auto-corrects. A schedule change that alters the rate in force stops a running temp basal,
  since the pump rescales it, and restarts the scheduled basal dose at the new rate.

### History backfill and dose reporting
- History streaming runs through `HistoryLogFetcher`, and `HistoryBackfillCoordinator` keeps
  the session store caught up from every `syncPumpData` pass: an incremental read from the
  persisted watermark (`TandemPumpManagerState.historyBackfill`), cross-tick gap healing via
  `HistoryLogStore.missingRanges`, and a sliced walk backward to the deep-fetch boundary.
  `HistoryBackfillPlanner` holds that decision as pure arithmetic. A `.bolusChange` qualifying
  event kicks a tick as well; one requested while a tick runs (the pump sends `.bolusChange`
  at both activation and completion) runs straight after it instead of being dropped.
- Two feature flags, both off by default. `historyBackfill` runs the whole thing: while off,
  `runTick` returns immediately and the pump's history log is never read. `historyDoseReporting`
  decides whether boluses found in that history reach the app's insulin history; it is `&&`-ed
  with `historyBackfill`, since there is nothing to report from a log never read. Neither is a
  dry run — a watermark written for entries that were never read would mark them read and
  suppress them once the flag goes on.
- The walk is sliced at one `HistoryLogRequest` (255 entries) so dosing interleaves with it,
  but is not paced one slice per sync: a tick keeps stepping until it reaches
  `deepFetchTarget`, bounded by `maxDeepSlicesPerTick`.
- Two distinct floors. `HistoryBackfillState.firstSeenFloor` is set at first sight, never
  moves, and alone bounds how deep the walk reads. `HistoryBackfillPlanner.emitFloor` bounds
  reporting: the latest of `firstSeenFloor`, `BolusReportLedger.trackingSince` and 24 hours
  ago. The host's `startDateToFilterNewPumpEvents` is in neither (#345): Trio returns
  `lastEventDate - 15min` and drops nothing itself, so it would bound the walk minutes into
  the past and drop a pump-UI bolus found one sync late.
- Reporting (`TandemPumpManager+HistoryDoseReporting.swift`) runs as a command job after every
  tick that read something. Boluses only: temp basals and suspends stay with the live path,
  since DoseStore would not count backfilled ones toward IOB and both would report them
  (#354). Batches are `replacePendingEvents: false`, ascending, through `emitPumpEvents`.
- The live path and history identify one bolus differently (#344), so `BolusReportLedger`
  (persisted, 24 h) records each app bolus's `bolusId`, live `raw` and event date at
  `InitiateBolus`, and `emitPumpEvents` marks it finalized when an immutable report with that
  `raw` goes out. A history bolus the ledger:
  - has finalized — is skipped;
  - holds as an unfinalized app bolus — is finalized under the live `raw`/date once the live
    path is no longer tracking it (relaunch mid-bolus, unknown delivered volume), releasing
    `pendingBolusFinalization`/`bolusDose`;
  - doesn't hold — is a pump-UI, Control-IQ or lost-acknowledgement bolus, reported under
    `HistoryLogSyncIdentifier.bolus`, dated at activation, mutable while in flight, with
    `automatic` from the bolus source and `wasProgrammedByPumpUI` set.
  `trackingSince` is stamped on the first decode by a build that has the ledger; nothing older
  is reported, because it cannot be told apart from an app bolus reported live without an
  entry.
- Still open: gap-aware `lastReconciliation` (#353), extended boluses (Bolex records are only
  logged; #424), and a pump clock offset from the phone's (history dates use the phone's UTC
  offset, not `pumpClockOffset`). `UnfinalizedDose.tempRateId` is recorded from
  `SetTempRateResponse` but not yet used; it is for re-keying live temp basals (#344).
- `docs/tandemkit-history-integration-plan.md` predates this design and still describes a
  history reconciler that no longer exists (#355). Where the two disagree, this section is right.

### Therapy command validation
- `enactBolus` rejects non-positive amounts and anything above `state.settings.maxBolus`
  (seeded from `PumpManagerSetupSettings` at setup, then whatever the host app last synced).
  The pump enforces the same ceiling in firmware, because `syncDeliveryLimits` pushes it down
  via `SetMaxBolusLimitRequest`.
- `enactBolus` refuses automatic boluses while Control-IQ is active. `enactTempBasal` refuses
  while Control-IQ is active or a bolus is running.
- There is **no IOB ceiling**: nothing in the driver polls `ControlIQIOBRequest` /
  `NonControlIQIOBRequest`, so `state.latestInsulinOnBoard` is never assigned. Wiring up
  IOB telemetry is a prerequisite for reinstating that check.
- There is **no app-side temp basal rate check**; the pump's own max basal limit is the
  only ceiling. (`maximumTempBasalRateExceeded` was never wired up in any revision and has
  been removed rather than left as a dead enum case.)

## Open work
Beyond the missing tests and the history items above. The `loopkit-conformance` issues track
where dose reporting departs from LoopKit's guide; `docs/conformance-test-plan.md` maps them to
integration scenarios.

- **CGM data.** Glucose from the pump's sensor (`CurrentEGVGuiDataRequest`) does not reach the
  host; TandemKit is not a `CGMManager`. The CGM screens only pair, start, stop and monitor the
  pump's sensor session.
- **Reconnect.** An automatic reconnect restores the session but does not sync or report to the
  host; the next report waits for `ensureCurrentPumpData` (#351).
- **Pairing.**
  - `JpakeRound1Framing` is unit-tested and pairs against faketandem, whose JPAKE is pumpX2's,
    but has not been confirmed against pump firmware.
  - A failed pairing is not shown properly in the onboarding UI (#399).
  - The legacy 16-character pump-challenge pairing is not implemented; only the 6-digit JPAKE
    code is.
- **Delivery-uncertainty recovery.** `deliveryUncertaintyRecoveryViewController` returns the
  general `TandemUICoordinator`; there is no dedicated recovery screen.
- **Response validation.** `BTResponseParser` does not check the CRC, HMAC or `txId` of received
  packets; it only rejects cargo shorter than the message's declared size.
- **Hardware validation.** There is no written manual test procedure for pairing, bolus, temp
  basal and suspend/resume on the t:slim X2 and the Mobi, and no record of which pump firmware
  versions are supported.
