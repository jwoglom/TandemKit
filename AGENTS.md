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

The Harmonize rule `DriverMessagesHaveSerializationTests` (below) works out from the code which
messages the driver sends or decodes; its baseline lists those still without a serialization test,
which come before the rest of the catalog. None of them has a usable vector in pumpX2's tests, so
each needs a pump capture. Delete a type from the baseline when you add its test.

### Harmonize lint rules
`HarmonizeRules/` is a separate SwiftPM package of
[Harmonize](https://github.com/perrystreetsoftware/Harmonize) rules: XCTest cases that parse
`Sources/` and `Tests/` (rooted by `.harmonize.yaml`) and assert on their structure. It lives
outside `Tests/`, so it is not part of `TandemKitTests`. Run it with `swift test --package-path
HarmonizeRules` (`--filter <RuleName>` for one rule); the Linux workflow's `harmonize` job runs it.
A failing rule prints what it enforces, why, how to fix it and an example, at the offending line:
fix the code, not the rule. Each rule's baseline lists the violations that predate it, and
Harmonize fails on an entry that no longer violates, so remove it in the change that fixes it.
Don't add to a baseline to get a new violation through.

### LoopKit and Linux
- Apple-platform builds resolve `LoopKit`/`LoopKitUI` from the surrounding Xcode workspace, which must build them — Trio's workspace does, via its `loopandlearn/LoopKit` submodule. SwiftPM cannot build these targets at all; see the comment atop `Package.swift`.
- Linux builds compile against the fakes in `LinuxShims/`, which can drift from the real LoopKit;
  read `LinuxShims/README.md` before adding to one. SwiftECC does not build on Linux, so fresh
  JPAKE pairing (and its tests) run only on Apple platforms.

## Driver behaviour
Rules that are easy to break without noticing. The overall design is in
[docs/ARCHITECTURE_ANALYSIS.md](docs/ARCHITECTURE_ANALYSIS.md).

### Delegate queue
`PumpManagerDelegate` methods are only called through `pumpDelegate.notify` or
`delegateQueue.async`. Loop opens them with `dispatchPrecondition(condition: .onQueue(queue))`, so
a direct call from a driver queue crashes it, as a backfill tick reading
`startDateToFilterNewPumpEvents` from the command queue did. `pumpDelegate.call` is a
`queue.sync`, which deadlocks a caller already on the delegate queue. Nothing goes out until the
host has set both the delegate and its queue (`canNotifyDelegate`): `pumpDelegate.queue` reads
`.main` until then, and Trio sets the delegate first. `deliverStateMissedByTheDelegate` replays
what was held once the second one lands. `MockPumpManagerDelegate`
fails the test on any call that carries the manager and arrives off its `delegateQueue`; a test
attaches one queue for the manager's life, as hosts do.

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
- The onboarding sound screen runs before pairing, so `applyOnboardingSettings` also writes its
  choices, the `*Annun` values it stored: one `SetPumpSoundsRequest` flagging the sounds that are
  set. `pumpSoundsAwaitingWrite` stops a qualifying event's pump-globals read from replacing them
  before then. It clears once the write is tried, so a failed one is logged, doesn't stop setup and
  isn't retried, and the next read shows what the pump holds.
- `syncBasalRateSchedule` fails with `BasalScheduleSyncError.tooManyEntries`, before connecting,
  when the schedule has more entries than `maximumBasalScheduleEntryCount` (16). Trio's editor
  doesn't enforce the limit, and a schedule migrated from another pump can exceed it (#443).
  It fails the same way with `firstEntryNotAtMidnight` when the first entry is not at 00:00, the
  start time of the pump's segment 0; past the deletes, the pump would refuse it mid-write.
- A segment modify flags in its status mask only the fields it changes (`START_TIME`,
  `BASAL_RATE`), never segment 0's start time, as Tandem's app does: a Mobi refused every
  segment-0 modify flagging all five. Creates and deletes flag all five.
- `syncBasalRateSchedule` reads the profile back and fails with `basalProfileSyncMismatch`
  unless `pendingSegmentWrites` finds nothing left to write. `fetchBasalStatus` compares the
  pump's rate against the schedule every sync, on the pump's clock via `pumpClockOffset`, using
  `profileBasalRate` during a temp basal and skipping suspend and Control-IQ. A mismatch that
  outlives `basalMismatchConfirmationInterval` shows a critical status highlight and clears
  `hasSyncedBasalRateSchedule`, so temp basals stop (see Therapy command validation). Nothing
  rewrites the pump's profile. A schedule change that alters the rate in force stops a running
  temp basal, since the pump rescales it, and restarts the scheduled basal dose at the new rate.

### Pump event batches
- A `replacePendingEvents: true` batch makes both hosts delete every mutable dose it leaves out,
  and Loop never revives a deleted one. `emitPumpEvents` appends the boluses the host holds as
  mutable, `bolusDose` and `pendingBolusFinalization`, to each one (#330). The temp basal is still
  each call site's job, via `getActivePumpEvents`.
- Loop's `DoseStore` keeps a stored `PumpEvent` row over a non-replacing report with the same
  `raw`, so finalizing a dose the host holds as mutable takes a replacing batch (#452).
- Still open: a sync re-sends nothing while a dose runs, since its boundary batch is empty and
  non-replacing (#330, #450).

### History backfill and dose reporting
- History streaming runs through `HistoryLogFetcher`, and `HistoryBackfillCoordinator` keeps
  the session store caught up from every `syncPumpData` pass: an incremental read from the
  persisted watermark (`TandemPumpManagerState.historyBackfill`), cross-tick gap healing via
  `HistoryLogStore.missingRanges`, and a sliced walk backward to the deep-fetch boundary.
  `HistoryBackfillPlanner` holds that decision as pure arithmetic. A `.bolusChange` qualifying
  event kicks a tick as well; one requested while a tick runs (the pump sends `.bolusChange`
  at both activation and completion) runs straight after it instead of being dropped.
- Two feature flags: `historyBackfill` is on by default, `historyDoseReporting` is off. The
  flags screen reveals itself when any flag is off its default, so a user who turned the backfill
  off can still find it. `historyBackfill` runs the whole thing: while off,
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
  tick. Boluses need `historyDoseReporting` as well; their batches go out ascending through
  `emitPumpEvents`, and replace only when they finalize a bolus already reported.
  App-commanded temp basals stay with the live path.
- Suspends, resumes and temp basal ends the pump made on its own
  (`TandemPumpManager+DeliveryTransitions.swift`, #333, #331). Neither host revises one once
  told: Trio keeps a row per (timestamp, type) and Loop never counts a non-bolus dose older than
  its last finished basal (#354). So the first report carries the pump's date, and reaches the
  host before anything the app commands after it.
  - Every `CurrentBasalStatus` reading goes through `observeDeliveryState` (sync, qualifying
    events, `enactTempBasal`'s own read, `fetchSuspendStatus`). With `historyBackfill` on, a
    change the app did not command is left as a `PendingTransition` in
    `DeliveryTransitionLedger`, with a placeholder in `basalDose` for status, until a history
    pass dates it from `PumpingSuspended`/`PumpingResumed`/`TempRateCompleted`. The first tick
    that starts after the change dates it if it read the log to its end and reaches back to
    the last reading before the change, and otherwise reports it at detection.
  - A sync, or a wizard's `fetchSuspendStatus`, that leaves a change pending completes once it
    is reported, or after `transitionHistoryWait` (30 s) at detection; `ensureCurrentPumpData`
    is not throttled while one is pending, so the host doses on a sync that has reported it.
    Before an app command emits (temp basal, cancel, suspend, resume) a pending change is
    reported at detection first. A second change before history dates the first reports the
    first at detection.
  - At detection each end is dated the way that counts more insulin: a stop at detection, a
    resume at the last reading that saw the pump suspended, a temp basal below the schedule
    ended at that reading and one above it at detection, against the host's schedule on the
    phone's clock. A pump-side resume is always a `.resume`, never a `.basal` marker. With the
    flag off everything is reported this way. A temp basal whose `TempRateCompleted` has
    `timeLeft` 0, within a minute of its programmed end, ends exactly then, so it keeps the
    identity it was reported under.
  - The history pass also reports suspend/resume pairs that fell inside an outage, which no
    reading can see. The ledger records every suspend and resume the driver reports with the
    span its pump record can fall in, so a record is matched rather than reported twice. It
    tracks one pump from the last record of the first history status it sees (`trackedAfter`),
    so nothing written before the driver watched the pump is reported; a new serial or an
    erased log starts it again. Records older than 24 hours or dated ahead of the phone are
    ignored.
  - Never sent: a suspend whose resume has not been read while the pump delivers (Trio takes a
    trailing suspend as lasting until now), a resume with no suspend before it in the host's
    view (Trio takes the pump as suspended since its history began), a suspend and resume in
    one second (Trio's IOB throws), and a second suspend in a row (Loop keeps only the later).
    Only the same-second pair is marked handled; the others are reconsidered next pass, since
    the other half may be in a gap the next tick fills. The host's view falls back to the dose
    it holds when the ledger has no entry (a suspend from before the ledger, or pruned).
  - History dates are moved onto the phone's clock with `hostDate(forPumpDate:)`.
  - Loop still stores but does not count a gap-contained pair it hears about after a later
    finished basal (#354). Trio counts it either way.
  - Scenarios: conformance group F, `OutageConformanceTests`; unit tests in
    `DeliveryTransitionReportingTests`.
- The live path and history identify one bolus differently (#344), so `BolusReportLedger`
  (persisted) records each app bolus's `bolusId`, live `raw` and event date at `InitiateBolus`,
  and `emitPumpEvents` marks it finalized when an immutable report with that `raw` goes out. It
  keeps entries 12 h past the 24 h reporting horizon, since history dates an app bolus at
  activation on the pump's clock, which can be later than its entry. A history bolus the ledger:
  - has finalized — is skipped;
  - holds as an unfinalized app bolus — is finalized under the live `raw`/date once the live
    path is no longer tracking it (relaunch mid-bolus, unknown delivered volume), releasing
    `pendingBolusFinalization`/`bolusDose`;
  - doesn't hold — is a pump-UI, Control-IQ or lost-acknowledgement bolus, reported under
    `HistoryLogSyncIdentifier.bolus`, dated at activation, with `automatic` from the bolus
    source and `wasProgrammedByPumpUI` set. It is reported once, finalized, when its
    `BolusCompleted` is read, and not while it runs (#452): a mutable report would have to ride
    every replacing batch until then. Its insulin is missing from IOB for that long, roughly the
    delivery time, since the pump's `.bolusChange` at completion kicks a tick.
  `trackingSince` is stamped on the first decode by a build that has the ledger; nothing older
  is reported, because it cannot be told apart from an app bolus reported live without an
  entry.
- Still open: gap-aware `lastReconciliation` (#353), extended boluses (Bolex records are only
  logged; #424), and a pump clock offset from the phone's for boluses (bolus history dates use
  the phone's UTC offset, not `pumpClockOffset`, so after a trip or a pump clock change they
  land hours off; #482, conformance group G). `UnfinalizedDose.tempRateId` matches a live
  temp basal to its `TempRateCompleted`; re-keying live temp basals on it is still open (#344).
  Temp rates the app did not set are still not reported.

### Therapy command validation
- `enactBolus` rejects non-positive amounts and anything above `state.settings.maxBolus`
  (seeded from `PumpManagerSetupSettings` at setup, then whatever the host app last synced).
  The pump enforces the same ceiling in firmware, because `syncDeliveryLimits` pushes it down
  via `SetMaxBolusLimitRequest`.
- `enactBolus` refuses automatic boluses while Control-IQ is active. `enactTempBasal` refuses
  while Control-IQ is active or a bolus is running.
- A zero temp basal is always allowed for the duration asked, whatever the profile, sync or
  mismatch state below, since 0% of any profile is 0. Control-IQ and a running bolus still refuse it.
- `enactTempBasal` refuses every other temp but a cancel until the first successful
  `syncBasalRateSchedule` sets `hasSyncedBasalRateSchedule`: a temp rate is a percent of the
  pump's profile, which until then may not be the app's (#443). `deleteSavedPumpState` clears it.
  State saved before the flag existed reads false, and Loop and Trio only sync the schedule
  when the user saves it, so while it is false `enactTempBasal` reads the pump's profile
  (`adoptMatchingPumpProfile`) and sets the flag if it already matches the host's schedule.
- A confirmed basal rate mismatch clears `hasSyncedBasalRateSchedule` on every reading that
  still differs, a sync's included, and `adoptMatchingPumpProfile` skips while it stands: a
  matching profile does not explain a live rate that differs. Temp basals resume after a
  reading that matches, through adoption or a sync. A non-zero temp already running when the
  mismatch is confirmed is stopped.
- `enactTempBasal` refuses a non-zero temp with `pumpProfileBasalRateIsZero` when the pump's
  `CurrentBasalStatus` reads a profile rate of 0 U/hr, before stopping a running temp basal; a
  Mobi ran a 0 U/hr profile for a day while the host was told its temp rates ran (#335, #343).
- The percent is worked out against the pump's own rate in force, `profileBasalRate` from that
  same read, and the temp is reported at that percent of it. Within `segmentChangeWindow`
  (5 min) of the pump's next segment change it is worked out against the larger of the two
  rates and reported at the request: delivery never exceeds the request on either side, and the
  host can only over-count, until the change. Segment changes come from the host's schedule on
  the pump's clock (`pumpSegmentChanges`), which is the pump's profile whenever non-zero temps
  are allowed.
- The pump rescales a running temp at each segment change, so `splitAtSegmentChanges` cuts its
  record there: finished at the change, and a new mutable part at `tempPercent` of the new rate.
  The first basal read after a change reports the cut; every path that finishes a temp
  (`getActivePumpEvents`, `reportTransition`) cuts it first, since neither host revises a temp
  basal once told it finished. Hosts sync before they dose, so no dosing decision sees the
  uncut record; while disconnected it stays uncut until the next reading.
- After `SetTempRate`, `enactTempBasal` reads `CurrentBasalStatus` back and needs a temp within
  one 0.01 U/hr step of the percent of the pump's own rate (its rounding is unknown; 10% of
  0.15 U/hr is reported as 0). Otherwise it stops the temp, reports none and fails with
  `tempBasalRateMismatch`, as when the pump's max basal limit caps it; one it can't stop is
  reported at the pump's rate. No answer to the read reports it as commanded. Field logs show
  the temp in the first status read, within a second, every time.
- A pump clock more than `pumpClockSkewThreshold` (5 min) off the phone's (`isPumpClockSkewed`)
  raises a LoopKit alert, retracted once the clock agrees (`pumpClockSkewAlertIssued`, persisted),
  and a status highlight; the settings screen syncs the clock. While skewed, wherever the host
  counts its own scheduled rate the pump runs a temp at the percent of its own rate that delivers
  it (`maintainPumpClockSkewCompensation`, every basal read and after a cancel). The host is not
  told of it: what it counts is what runs. A temp the driver did not set is left alone. A request
  equal to the pump's own rate goes out as an explicit 100% temp, reported at that rate; whether
  firmware accepts 100% is unconfirmed, and a refusal fails the command.
  `syncPumpData` reads the pump's clock before its basal status for this.
- There is **no IOB ceiling**: nothing in the driver polls `ControlIQIOBRequest` /
  `NonControlIQIOBRequest`, so `state.latestInsulinOnBoard` is never assigned. Wiring up
  IOB telemetry is a prerequisite for reinstating that check.
- There is **no app-side temp basal rate check**; the pump's own max basal limit is the
  only ceiling. (`maximumTempBasalRateExceeded` was never wired up in any revision and has
  been removed rather than left as a dead enum case.)

### Unconfirmed bolus volume
- A bolus whose `LastBolusStatus` can't be read is held mutable in `pendingBolusFinalization` and
  retried every sync. The retry also takes its `BolusCompleted` record from the session
  `historyLogStore`, which only history backfill fills: it never reads history itself, so the
  flag's promise that the app reads no pump history while it is off still holds.
- `holdForFinalization` takes the fallback used once `bolusFinalizationWindow` passes (#448): the
  programmed amount for a bolus the pump finished, which is what Loop counted while the dose was
  mutable, and for a cancel the elapsed time at the pump's rate from the delivery start (from
  programming if it was never seen). Never the progress reporter's sample, which is 0 U until a
  second delivering status. A fallback is only logged; nothing tells the user yet (#464).

### Cartridge change
- The pump refuses `EnterChangeCartridgeMode` while another cartridge procedure is open, and a
  fill-tubing left open also refuses `ExitChangeCartridgeMode`; the only reason it gives is a nonzero
  status. When the wizard's enter is refused with delivery suspended and no pump notification to
  blame, `stuckModeRecoveryOffered` makes the view ask the user to remove the pump. On OK,
  `recoverAndReenterChangeCartridgeMode` runs `CartridgeModeRecovery`: exit fill tubing, exit change
  cartridge, enter change cartridge, and no refusal stops it. It is offered once, not again after a
  refused retry. The refusal rule is inferred from a field report and not confirmed on firmware.

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
