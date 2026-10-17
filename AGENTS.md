## Reference material
- See [docs/ARCHITECTURE_ANALYSIS.md](docs/ARCHITECTURE_ANALYSIS.md) and [docs/KEY_FILES_REFERENCE.md](docs/KEY_FILES_REFERENCE.md) for deeper implementation notes and file-level pointers.
- [docs/integration-harness.md](docs/integration-harness.md): the `TandemKitIntegrationTests` target, which runs the real driver against the faketandem emulator (`scripts/integration-test.sh`), and the emulator gaps it currently works around.
- [docs/hardware-test-plan.md](docs/hardware-test-plan.md): the manual procedure on a real pump, including the quick bolus and Control-IQ configurations, and the firmware behaviour only a pump can confirm.

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
- Refer to a history record by its bare type number (`279`). Name it (`BasalDelivery`), in comments,
  log and assertion messages and docs alike.

Comment-worthy, in one line where possible:
- A pump quirk, firmware race, or host behaviour being worked around.
- The safety direction of a fallback — which way it biases IOB, and why that way.
- Units, resolution, and whose clock a timestamp is on.
- A non-obvious ordering or a rejected alternative that looks better than it is.

Tests: the test name carries the behaviour. Comment only a setup line whose purpose is opaque
(why *this* stub value, why state is poked directly). A test that pins a fix may cite its issue
number; no other code, comment or log message does.

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
the `virtual-pump` job in `.github/workflows/linux.yml` both run. Each names the flagged-only test
classes it runs, so a new one goes on both lists.

The same build carries `VirtualPumpControl`: with `TANDEMKIT_VIRTUAL_PUMP_CONTROL=<port>` in the
host app's environment, the driver listens on 127.0.0.1 for a test to make the calls the host and
the driver's own screens make (pair, onboarding settings, sync, bolus and cancel, basal schedule,
temp basal, suspend, resume, cartridge and site changes, feature flags), and logs every batch it
hands the host's delegate with the host's completion. `TrioIntegrationTests` (macOS only;
`scripts/trio-test.sh`, the `trio` job) use it to run Trio itself in the simulator, a new install
per test from `scripts/app-launcher.py`, through each dosing journey and Trio's own closed loop,
and compare its stored pump history with `TrioDoseStoreOracle`
([docs/integration-harness.md](docs/integration-harness.md#trio-in-the-simulator)).
`LoopIntegrationTests` (`scripts/loop-test.sh`, the `loop` job) do the same with Loop, built from
LoopWorkspace with TandemKit as its plugin, and compare both of LoopKit `DoseStore`'s tables with
`LoopDoseStoreOracle` ([docs/integration-harness.md](docs/integration-harness.md#loop-in-the-simulator)).

Coverage that was dropped along with the code it tested (the `PumpComm` fault taxonomy and retry
policy, `HistoryDeduplicator`/`HistoryReconciler`, `PumpChallengeRequestBuilder` and the V1
16-character pairing path) is not represented anywhere now. If any of those behaviours come back,
they need tests written against the current architecture, not restored from git history. Some have
come back, with tests of their own: the packet layer `TandemBLE` held is `Packetize`,
`PacketAssembler` and `BTResponseParser` in TandemCore, pumpX2's `PumpStateSupplier` is `QualifyingEventContext`,
`HistoryToDoseMapper` and `HistoryTimestampReconciler` are back, and `BolusReportLedger`,
`DeliveryTransitionLedger` and `BasalReconciler` match history against what the host was told.

### Commit stamp
The `Stamp Git Commit` phase on the `TandemKit` framework target writes the short commit, with
`-dirty` for a modified tree, into the built framework's Info.plist as `TandemKitGitCommit`, which
`TandemPumpManager` logs at init so a field log can be tied to a build. It reads the git directory
(a submodule's lives in the host's) and edits the built plist, neither of which the script sandbox
allows, so that target sets `ENABLE_USER_SCRIPT_SANDBOXING = NO`. A phase runs only if the target
lists it: the first version of this one was never listed, and every log read `commit unknown`
(#568). SwiftPM builds have no Info.plist and log `unknown`.

### Doc references
`scripts/check_doc_references.py` fails when a markdown doc names a code identifier, a path or a
`.swift` file the repository does not have, or links to a file or heading that is not there. The
Linux workflow's `docs` job runs it, and its tests, on every change, documentation-only ones
included. A name from another codebase goes in its `EXTERNAL`; a name a doc cites as gone goes in
`REMOVED`, which fails once the code has it again. Both fail on an entry that is no longer needed.

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
what was held once the second one lands, with the status but not `pumpManagerDidUpdateState`: Loop
and Trio save `rawValue` on the main thread right after attaching, and a second save from their
delegate queue races it (Trio's launch hung in a Thread Sanitizer report of it).
`MockPumpManagerDelegate` fails the test on any call that carries the manager and arrives off its
`delegateQueue`; a test attaches one queue for the manager's life, as hosts do.

Both hosts save the whole `rawValue` on every `pumpManagerDidUpdateState`, so a reading the host
doesn't use waits for the next state change instead of notifying: `fetchInsulinOnBoard` answers
every `iobChange`, about once a minute (#567). Status pushes are not skipped when the status is
unchanged: Trio dates its pump battery and pump status from each one, and its Nightscout upload
leaves out a battery reading older than 30 minutes. TandemKitUI's settings, troubleshooting and HUD
views re-read `connectionIssue` and the reservoir on each, and the first two `lastKnownBasalDelivery`.

Bolus progress observers are called on the queue the host passed
`createBolusProgressReporter(reportingOn:)`, which Trio relies on to serialize its own reporter
state. `TandemDoseProgressReporter` is shared by the command queue, the telemetry queue and every
host queue, so its state stays behind its lock, as does the manager's reference to it.

### Responses and the shared link
- The pump has one link to the phone, and iOS notifies every app subscribed to a characteristic,
  so the driver also receives the responses to another app's requests, as field logs show after a
  connect (#507). `PendingWrite` takes only its own answer: on the request's characteristic, under
  the request's txId (byte 1 of every notification and byte 3 of the first, as pumpX2 checks),
  starting with the response's opcode, and then each next piece by txId and `remaining` countdown
  (`PacketAssembler`). A refusal is an `ErrorResponse` under that txId, on `CURRENT_STATUS` or the
  request's characteristic: faketandem sends it on the first, pumpX2 expects the second.
- `PacketAssembler` checks the CRC and declared length of every message, as pumpX2's
  `PacketArrayList` does. A corrupt message under the pending txId is dropped and the write waits
  on; one that does not decode as the response type ends it as unanswered.
- History log, control stream and qualifying-event notifications are routed before the pending
  write. None answers a write, and at the 23-byte MTU the second notification of a signed stream
  message is HMAC, whose byte 2 can be any opcode. Both streams are reassembled, and a piece that
  starts a message drops one that lost a piece. Control-stream messages that share an opcode are
  told apart by declared length (`ControlStreamMessages.responseType`).
- Anything else on a request characteristic is reassembled and logged once
  (`UnsolicitedNotificationLog`): as the late answer of a write that timed out under its txId in
  the last two minutes, otherwise as another app's, at info for the first of a burst and at debug
  for the rest.
- Still open: another app's response under the pending write's txId and opcode is taken as the
  answer. It answers the same request, so it reads the same pump state. Nothing tells the user
  that another app talks to the pump, and nothing checks the HMAC of a signed response.

### Handshake failures
`TandemBluetoothManager` counts JPAKE handshakes the pump ended or left unanswered
(`recordJpakeFailure`, from the setup task). At `jpakeFailureLimit` (3) in a row it stops the
connects the driver starts itself: the backoff retry, the one after a disconnect and the one when
Bluetooth powers on (`reconnectAutomatically`). A host command still tries, since only an attempt
can tell that the pump has stopped refusing. A successful handshake clears the count, and so does
Bluetooth powering back on, which is the one thing a person can do to ask for a fresh attempt. Until
then `connectionIssue` is `.handshakeFailing`, shown at once on the status highlight, settings and
troubleshooting screens. The count is not persisted, so a relaunch tries afresh. A first pairing is
not counted: its attempts are the user's own, and a refused code is theirs to fix (see Pairing).

Only a round the pump may have ended counts (`WriteFailure.countsAsJpakeFailure`, #565). The
disconnect's reason reaches the setup task through `linkWentDown`, before any wait is cancelled. A
link lost to `CBError.connectionTimeout` (the phone stopped hearing the pump, as in a weak-signal
stretch) or to Bluetooth going off is not counted, and neither is a write that never went out. A
far-end drop (`peripheralDisconnected`, the signature of a second host on the pump, #400), a
disconnect the driver made itself (a connect out of time), an unanswered round on a live link, a
refusal and an answered but invalid handshake all count. Once its link is gone a setup task stops at
its next step: every operation after `linkWentDown` is refused, so it never writes to the peripheral
the next connect reuses. Whether a Mobi refusing a stored key ever drops as `connectionTimeout` is
unconfirmed (hardware test plan P4).

### Reconnect
- Every connect job that brings a session up queues `syncPumpData(onlyIfIdle: true)` through
  `didReconnect` (#351), whoever started it: the reconnect retry, a history tick or report, a host
  command. The pump's qualifying events are lost while the link is down, so what it did meanwhile
  reaches the host only through a sync, and the host's poll is throttled for 4.5 minutes after the
  last one. A job of the driver's own that reconnected first left the retry nothing to do, so
  limiting this to the automatic connects missed it. A sync that reconnected is already in flight,
  and the reconnect's joins it. Not before the host has adopted the manager (`canNotifyDelegate`),
  whose first poll syncs, so not during onboarding; not for pairing's connect.
- A poll (`onlyIfIdle`) that finds a sync in flight queues nothing and is handed that sync's result
  (`SyncResult`) when it completes, not the `lastSync` from before it: Trio loops as soon as its
  poll completes, and the sync in flight may be the first to read the pump since an outage.

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
request that maps to no fetch is not sent: nothing in the driver consumes CGM/EGV, home screen
mirror, Basal-IQ, temp rate, localization, load status or bolus permission change reason today,
so `bg`, `cgmChange`, `basalIQ`, `basalIQStatus`, `controlIQSleep`, `extendedBolusChange`,
`pumpingStatus` and `bolusPermissionRevoked` currently fetch nothing.
Control-IQ support in the context is whether the pump has answered a Control-IQ info read
(`controlIQEnabled != nil`), so a pump with Control-IQ off is still asked for IOB under the
Control-IQ opcode. Three deliberate additions to pumpX2's table: `pumpSuspend`/`pumpResume` refresh
the basal status, since that is what emits the suspend/resume dose to LoopKit; `alarm`/`malfunction`
refresh it, so a stop the pump makes on an occlusion, empty cartridge, auto-off or malfunction is
seen at its alarm, not at the next sync, whether or not the pump also raises `pumpSuspend` (a Mobi
raised it with the alarm for an occlusion; other stops are unconfirmed on hardware); and
`profileChange`/`activeProfileSegmentChange` refresh it so the basal rate check runs on a profile
edit instead of at the next sync.

### Pairing
- Only `pairPump` starts a first pairing. `connectIfNeeded` refuses a pump with no derived secret: the
  auto-reconnect after the pump dropped the link would otherwise replay the last code entered, silently,
  at a pump that had just refused it (#399). `pairPump` forgets a code whose attempt failed, unless a
  newer attempt has replaced it.
- The pump checks the code only at key confirmation. On a first pairing, `Jpake4KeyConfirmationRequest`
  unanswered (a Mobi drops the link) or answered with a digest that does not match fails the connect with
  `PumpCommError.pairingCodeRejected`; any other failed round is `noResponse`. The link drop is the
  signature in field logs, and a glitch at that exact round reads the same.
- Every error `pairPump` completes with has to reach `TandemKitScanViewModel.onPairFailure`, which ends
  the pairing step (alert, back to the double-tap step, scan restarts when the alert is dismissed). The
  step has no exit of its own.
- `pairPump`'s connect is a command job, bounded at `pairingTimeout` (120 s). Its setup writes bypass the
  command queue, and a command that connected meanwhile took over its completion, so pairing never ended.
  A command queued during pairing waits, then runs on the session pairing opened or is refused as unpaired.
  One queued before it can connect a pump that already holds a key (a re-pair), and pairing then completes
  on that session: a second connect to a connected peripheral is never answered. A lost link ends a reconnect's wait at once, but not pairing's, so the setup reports the round it lost:
  only then does a link dropped at key confirmation reach `pairPump` as `pairingCodeRejected`.

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
- Then, with `quickBolusButtonSupport` off, it reads the pump globals and turns the quick bolus
  button off, which otherwise stayed live until the first sync (#353 P20-1). A failed read or a
  refused write is logged, doesn't stop setup, and is left to the first sync.
- Before `applyOnboardingSettings`, whatever the feature flags, `TandemKitScanViewModel` asks
  `controlIQNeedsTurningOffForSetup` whether the pump runs Control-IQ, which refuses the host's
  automatic doses and whose basal reaches the host only with `basalHistoryReporting`. If it does,
  an alert says Control-IQ will be turned off, and its OK runs `turnOffControlIQForSetup`: one
  `ChangeControlIQSettingsRequest`, no sync (a sync would read the pump's profile before the
  host's is written) and no hand-back, since the host has not dosed with this pump yet. A refused
  or unanswered write is read back, and a pump that reads Control-IQ off goes on with setup;
  otherwise the alert offers only Try Again, so setup does not finish with Control-IQ on. An
  unanswered read asks nothing, and the first sync only reads Control-IQ.
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
  `profileBasalRate` during a temp basal and under Control-IQ, and skipping suspend and an
  all-zero schedule, the placeholder for one the host never gave. The schedule's rate up to
  `basalRateCheckTolerance` (1 min) either side matches: the offset trails the pump's clock by up to
  a second plus the read's latency, and the read a segment change triggers lands in that gap (#566).
- The driver writes the host's schedule over a pump profile that differs, under Control-IQ too,
  since hosts take the pump to hold what they last saved (Trio keeps a profile only once the sync
  takes). A rate read off the schedule, or a profile `adoptMatchingPumpProfile` finds different,
  stamps `basalRateMismatchDetectedAt` (persisted) and starts `updatePumpBasalProfile`, a command
  job queued behind the one that saw it: "Syncing Basal Profiles" in the status highlight and
  settings, with no LoopKit alert. The update ends, clearing the stamp, only when the profile
  reads back matching and the rate in force agrees; any successful `syncBasalRateSchedule` or
  adoption ends it too. Until then every reading retries it, at most once per
  `basalProfileUpdateRetryInterval`. A mismatch read `basalProfileUpdateTimeout` (5 min) after
  the stamp sets `basalProfileUpdateFailed`, clears `hasSyncedBasalRateSchedule` and refuses
  temp basals with `failedUpdatePumpProfile` (see Therapy command validation). An all-zero
  schedule, or one `syncBasalRateSchedule` would refuse, is never written, so it fails this way.
- A schedule change that alters the rate in force (the pump's profile before the write against
  the schedule after) stops a running non-zero temp basal, since the pump rescales it, and
  restarts the scheduled basal dose at the new rate. A zero temp keeps running.

### Reconciliation boundary
- `lastReconciliation` moves at a dose change the driver reports, and at the end of a sync whose
  `CurrentBolusStatus` and `CurrentBasalStatus` reads the pump answered (#449). A bolus the sync
  defers to, which the host already counts, stands in for its read. Loop takes delivery up to the
  boundary as accounted for, and no other answer, a reservoir level included, says anything about
  delivery. So an unreconciled sync hands the host the boundary it had and arms no poll throttle.
- A reservoir reading reaches the host only once `lastReconciliation` covers it, after the batch
  that carries the boundary (`flushPendingReservoirReading`): past its boundary, Loop's `DoseStore`
  counts whole-unit reservoir drops in place of pump events, which made IOB alternate. A reading
  between syncs (a `.remainingInsulin` event, the cartridge screen) waits for the next sync, whose
  own read supersedes it. After a sync whose delivery reads went unanswered the host has nothing
  newer than its boundary, so Loop's 15-minute pump data check stops it dosing instead of counting
  reservoir drops. `reconciliationBoundary`'s hold for a pump bolus (#353) is behind the reading on
  purpose, and the gate is the driver's own boundary. Trio doses on neither.

### Pump event batches
- A `replacePendingEvents: true` batch makes both hosts delete every mutable dose it leaves out,
  and Loop never revives a deleted one. `emitPumpEvents` appends the boluses the host holds as
  mutable, `bolusDose`, `pendingBolusFinalization` and the extended parts history holds
  (`heldExtendedPartEvents`), to each one (#330). The temp basal is still each call site's job, via
  `getActivePumpEvents`.
- Loop's `DoseStore` keeps a stored `PumpEvent` row over a non-replacing report with the same
  `raw`, so finalizing a dose the host holds as mutable takes a replacing batch (#452).
- A bolus the pump confirms delivered nothing is finalized at 0 U, not withdrawn as LoopKit's guide
  has it (#455). Loop stores no dose for a 0 U bolus, so its mutable copy stays deleted, the guide's
  end state, and Trio keeps a 0 U row. Withdrawn, it would stay in Loop at its programmed amount
  whenever the batch held nothing else, since an empty batch purges nothing there.
- A temp basal keeps one `raw` from its first report to its last, however it ends (#344):
  `NewPumpEvent.tempBasal(dose:of:)` takes it from the `UnfinalizedDose`, not the entry. A temp the
  app set or history adopted carries `eventRaw` (persisted), `HistoryLogSyncIdentifier.tempRate`
  of the pump's `tempRateId`, minted when it starts if the serial is known. Without one,
  `tempBasalRaw` keys it on its programmed amount and start, as builds before `eventRaw` did while
  it ran. An id not past `lastTempRateEventRaw` mints nothing: the pump's 16-bit counter may
  restart, and a host still holding a row under the id's earlier use would swallow the new temp.
  The part after a segment cut or a restatement is a dose of its own, keyed the second way.
- A `.basal` marker, suspend or resume is reported once, keyed on its type and its date to the
  millisecond (#352): of two rows under one `raw`, both hosts keep the first, and two of one type
  can fall in one second. `getActivePumpEvents(endDate:)` closes a temp basal that ran out with a
  marker at its end only when `endDate`, where each caller reports its own change, is a second or
  more later; in that second the caller's change says the same, and Trio would order the two rows
  arbitrarily.
- A history pass sends all its non-bolus reports (suspends, resumes, temp basal ends, basal
  corrections) as one batch, ascending (`HistoryReportBatch`, `emitHistoryReports`). It replaces
  only when it ends or re-states the temp basal the host holds as mutable, and then carries
  `getActivePumpEvents()`. Nothing may be reported to start after a mutable temp basal's start while
  the host holds it open, and no report starts in the same second as a row the host holds: Trio
  orders two rows at one timestamp arbitrarily and leaves one zero-length, so an override starts a
  second later.
- A sync that moves the boundary ends with `reportPendingDoses`: every dose the host holds as
  mutable, the temp basal from `getActivePumpEvents()` and the boluses `emitPumpEvents` appends,
  re-sent as one replacing batch, so a running dose is refreshed until it finalizes (#330, #450).
  Loop keeps its row over a non-replacing re-send, so it has to replace. The batch is the boundary
  alone, empty and non-replacing, with nothing mutable (an empty replacing batch purges every
  mutable row in Trio).
- While a delivery change waits for history, `basalDose` is a placeholder and the host still holds
  the dose the change ended, so `getActivePumpEvents()` gives `pending.prior`, as last reported and
  uncut, mutable (#556). A bolus that finishes or is cancelled meanwhile, and the sync's re-send,
  carry it: leaving it out deletes it for good in Loop, and the change keeps its history dating.
  `getActivePumpEvents(endDate:)` ends the temp at the caller's own change, so its callers settle
  the pending change first, as the app commands do.

### Deleting the pump manager
- `prepareForDeactivation` tears the transport down, then sends one replacing batch before
  `pumpManagerWillDeactivate` (`finalizeHeldDosesForDeactivation`, #350). Left mutable, the host's
  next replacing batch, from whichever pump manager comes next, deletes what it holds. A Tandem
  pump keeps delivering after the app forgets it, so nothing is stopped and no `.suspend` is due.
  A pending delivery change is reported at detection first. `lastReconciliation` moves to the deletion.
- A running temp basal is finalized at the deletion, a second after its start at least, and what
  remains of it to its scheduled end is a finalized dose of its own, keyed as a segment cut's part
  and cut at the segment changes in it. Loop stores a finalized dose only once it has ended, and a
  mutable copy it soft-deletes before then can never be replaced, so one finalized whole would
  leave Loop's IOB once a boundary passed its end. Loop counts the remainder from its `PumpEvent`
  row until it can store it, at its first save behind a later boundary, which only the next pump
  manager gives it.
- A held bolus is finalized with its `BolusCompleted` record if backfill has read one; otherwise a
  running bolus at its programmed amount, ended no later than the deletion so Loop stores it at
  once, and one with an unconfirmed volume at the fallback it was held with. A held extended part,
  which the pump runs on to its programmed end, is cut at the deletion as a temp basal is: the share
  of its programmed amount up to then under its own `raw`, and the rest a finalized dose of its own
  to its programmed end under a new `raw`.
- Still open: Loop leaves the remainder out of IOB from a boundary past its end that came with no
  save (the next pump manager's empty batch) until that manager's next non-empty batch.
- The integration harness's `shutDownDriver()` is the app going away (a relaunch), which tells the
  host nothing; `deactivateDriver()` is the deletion. Scenarios: conformance D7 and J5; unit tests
  in `DeactivationDoseReportingTests` and `ExtendedBolusReportingTests`.

### History backfill and dose reporting
- History streaming runs through `HistoryLogFetcher`, and `HistoryBackfillCoordinator` keeps
  the session store caught up from every `syncPumpData` pass: an incremental read from the
  persisted watermark (`TandemPumpManagerState.historyBackfill`), cross-tick gap healing via
  `HistoryLogStore.missingRanges`, and a sliced walk backward to the deep-fetch boundary.
  `HistoryBackfillPlanner` holds that decision as pure arithmetic. A `.bolusChange` qualifying
  event kicks a tick as well; one requested while a tick runs (the pump sends `.bolusChange`
  at both activation and completion) runs straight after it instead of being dropped.
- Three feature flags: `historyBackfill` and `historyDoseReporting` are on by default,
  `basalHistoryReporting` is off. The flags screen reveals itself when any flag is off its
  default, so a user who turned the backfill off can still find it. `historyBackfill` runs the
  whole thing: while off, `runTick` returns immediately and the pump's history log is never read.
  `historyDoseReporting` decides whether boluses found in that history reach the app's insulin
  history, and `basalHistoryReporting` whether basal corrections do; both are `&&`-ed with
  `historyBackfill`, since there is nothing to report from a log never read. None is a dry run — a
  watermark written for entries that were never read would mark them read and suppress them once
  the flag goes on, so `reconciledThrough` only moves while basal reporting is on.
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
    events, `enactTempBasal`'s own read, `fetchSuspendStatus`, `resumeDelivery`). With
    `historyBackfill` on, a change the app did not command is left as a `PendingTransition` in
    `DeliveryTransitionLedger`, with a placeholder in `basalDose` for status, until a history
    pass dates it from `PumpingSuspended`/`PumpingResumed`/`TempRateCompleted`. The first tick
    that starts after the change dates it if it read the log to its end and reaches back to
    the last reading before the change, and otherwise reports it at detection.
  - A sync, or a wizard's `fetchSuspendStatus`, that leaves a change pending completes once it
    is reported, or after `transitionHistoryWait` (30 s) at detection; `ensureCurrentPumpData`
    is not throttled while one is pending, so the host doses on a sync that has reported it.
    `resumeDelivery` reads the pump first and waits the same way:
    the resume ends the temp basal the host holds, so a stop the driver missed must be reported
    before it, or Loop ignores it. A failed read still resumes. Before an app command that changes
    basal emits (temp basal, cancel, suspend, resume, enabling Control-IQ over a temp) a pending
    change is reported at detection first. A second change before history dates the first reports
    the first at detection.
  - At detection each end is dated the way that counts more insulin: a stop at detection, a
    resume at the last reading that saw the pump suspended, a temp basal below the schedule
    ended at that reading and one above it at detection, against the host's schedule on the
    phone's clock. A pump-side resume is always a `.resume`, never a `.basal` marker. With the
    flag off everything is reported this way. A temp basal whose `TempRateCompleted` has
    `timeLeft` 0, within a minute of its programmed end, ends exactly then: it ran its whole
    programmed duration.
  - An occlusion stop leaves the running temp basal set: the pump writes no `TempRateCompleted` for
    it, keeps its programmed end, and runs it again from a resume before then (seen on a Mobi; other
    stops and the t:slim X2 unconfirmed). The host is told it ended at the stop, so the part a stop
    ended is kept as `interruptedTemp` (persisted), and the first reading of a temp at its rate after
    the resume reports the rest, mutable, from a second after the resume to the programmed end under
    a `raw` of its own. A `TempRateCompleted` at the stop, scheduled basal or another temp rate after the
    resume, or an app temp basal, cancel or suspend forgets it.
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
- An extended bolus programmed off the app (on the pump's screen or in Tandem's app; TandemKit and
  Control-IQ never give one) is reported as two doses with one `bolusId` (#424).
  - The up-front part runs from BolusActivated to BolusCompleted, whose amount covers this part
    only. It is reported like any pump bolus. A 100% extended bolus has no up-front part.
  - The extended part runs from BolexActivated to BolexCompleted. It is a dose of its own under
    `HistoryLogSyncIdentifier.extendedBolus`, with its own ledger entry
    (`BolusReportLedger.Part.extended`), so neither part reads as the other already reported.
  - Unlike a pump bolus, the extended part is reported as soon as history reads its
    BolexActivated, because it can run for hours. It goes out mutable, at BolexActivated's
    `bolexSize`, from BolexActivated's time over its programmed duration: BolusDelivery's
    `extendedDurationRequested`, or BolusRequestedMsg2's `duration` on t:slim X2 firmware that
    writes no BolusDelivery records (both minutes). With neither it counts all at its start. Loop
    spreads it over that span; Trio counts it all at its start.
  - Every replacing batch carries it, under its first report's date, until its BolexCompleted is
    read. That finalizes it in a replacing batch, at BolexCompleted's `insulinDelivered` and time,
    a stop part-way included.
  - A BolexCompleted whose BolexActivated is not in the store is not reported: BolexCompleted has
    no start time.
  - A held part whose BolexCompleted is still unread `extendedPartFinalizationWindow` (1 h) after
    its programmed end is finalized at its programmed amount, which is what the host counted, in the
    next replacing batch. History may never show its end (another pump, the flags turned off), and
    the ledger would otherwise drop it while still mutable.
  - A BolexActivated in the same second as its up-front part's start is moved a second later,
    because Trio matches a new row on its timestamp. Reporting either part releases a
    `reconciliationBoundary` hold on the bolus.
  - Scenarios: conformance D13, D13b, D13c and group J (`ExtendedBolusConformanceTests`); unit
    tests in `ExtendedBolusReportingTests` and `HistoryToDoseMapperTests`.
- A bolus the app did not start that the live bolus status sees running is recorded, with
  `historyDoseReporting` on, as `BolusReportLedger.unreported` (#353). Until the batch that
  reports it from history, the `lastReconciliation` the host is given (`reconciliationBoundary`)
  stops at its start, or at the boundary already given if that is later. Loop takes delivery up to
  the boundary as accounted for, and past it falls back to reservoir doses, which count the bolus.
  Not for a bolus before the emit floor, which history never reports; dropped past the reporting
  horizon. `state.lastReconciliation`, `lastSync` and the sync throttle are unaffected.
- With `historyDoseReporting` on, while the pump may bolus on its own (Control-IQ on or handing
  back, or the quick bolus button not read as off: `awaitsHistoryBoluses`), `syncPumpData` waits
  for its history pass (`afterHistoryIsReported`), so the host doses after a pump bolus that
  finished out of contact is reported. A failed tick releases it at once.
- Basal reconciliation (`TandemPumpManager+BasalReconciliation.swift`) runs after the transitions
  pass on every history pass while `historyBackfill` is on. It compares what the pump delivered
  (`PumpBasalTimeline`, P) with what the host counts (`ReportedBasalLedger`, H): every non-bolus
  row `emitPumpEvents` sends, folded as Trio's IOB folds them (the latest row at or before an
  instant wins, a temp basal until its end, a suspend until its resume, otherwise the host's
  schedule). `trackingSince` is stamped on the first decode; rows are kept 36 hours.
  - A chunk differs when H at its BasalDelivery record is more than 10 mU/h off its `commandedRate`
    (plus 1% of the profile for a temp chunk, which runs a whole percent), H either side of a change
    the host was commanded to make within `transitionMatchTolerance` of the BasalDelivery record
    doesn't match either, and no correction carries its BasalDelivery record. A correction's own
    edges don't count as changes: they are the pump's cycles, and H before one is the previous
    chunk's, so a run of cycles at one rate would otherwise get only its first corrected. A matching
    chunk never differs, whatever H does later inside it: the host counts a change from its command,
    the pump from its next cycle, and that residual is only logged, once each day is over: net, the
    host's insulin less the pump's, and gross, since a temp's early start and early end cancel.
  - H for a chunk that differs is the row in force from the last change the host was commanded within
    `transitionMatchTolerance` after its BasalDelivery record, and the action starts there; with none,
    the row at the record. A stop that reached the pump just before a record and the next temp just
    after left the pump on its profile for the cycle, while the row the stop ended held a second of
    it: built against that row, the correction was empty and the chunk was passed for good (#564).
  - Skipped: suspended time (the pump's or the host's), chunks before the latest of
    `firstSeenFloor`, 24 hours ago and `trackingSince`, chunks still running, and temp chunks within
    `segmentChangeWindow` before a segment change, which the driver reports at the request on
    purpose.
  - Each difference is logged once a session, with the action it calls for, and each record that
    fails the cross-check once a session, from past `reconciledThrough` and the floor. Only with
    `basalHistoryReporting`, and only for a trusted chunk, is anything reported:
    - H from the host's schedule: a correction, an immutable `.tempBasal` at the pump's rate over
      the chunk (cut at the host's next row inside it), with `deliveredUnits` to 0.001 U, under
      `HistoryLogSyncIdentifier.logSequence` of the BasalDelivery record, so at most one per
      BasalDelivery record. `automatic` for Control-IQ chunks and temps with a `SetTempRateResponse`
      (309) record; `wasProgrammedByPumpUI` for Control-IQ chunks and temps without one.
    - H from the temp basal the driver holds: ended at its `TempRateCompleted` through
      `closeTransition`, or, if the pump runs it at another rate, re-stated as at a segment
      change: finished at the old rate, a mutable continuation at the pump's. When the BasalDelivery
      record that ends the chunk runs it at its own rate again, the pump's rate is a finished part up
      to that record and the continuation resumes the temp's rate there, so the host never projects
      the pump's rate past the chunk.
    - H from a finalized temp basal: the pump's chunks reported in its place, from the
      difference through its end, the first a second after its start. Neither host revises a
      finalized row, but Trio's IOB cuts one at the next row and does not resume it; Loop counts no
      basal older than its last finished one and ignores them. Every chunk through its end has to
      be read and trusted first.
    - H from a suspend: nothing.
  - A chunk waits, with everything after it, behind an open chunk, a store gap for
    `basalGapPatience` (2) passes (then the gap is skipped, with a warning), a pending delivery
    change, or a temp basal the host still holds open before it. `reconciledThrough` (persisted,
    reset on a new serial or an erased log) is the last BasalDelivery record a pass is done with.
  - Control-IQ hand-back: when `useControlIQ` goes off (`configureControlIQMode`,
    `fetchControlIQStatus`) `controlIQEndedAt` is persisted. While it is set, with reporting on,
    `isAwaitingHistory` holds: `ensureCurrentPumpData` does not throttle and `syncPumpData` waits
    for a history pass (`afterHistoryIsReported`, `transitionHistoryWait`), as for a pending
    delivery change. A pass that started after it, read to the pump's end and left nothing open
    before it clears it. A pass that sees Control-IQ in the BasalDelivery records while
    `useControlIQ` is off, or PCM 1 while it is on, reads the Control-IQ status.
  - Each pass records what it compared and did in `ReconciliationLog` (in memory, lock-guarded on the
    manager): the pass's counts and what held it back, every difference with its outcome, the records
    that fail their cross-check, the open residual days and the IOB monitor's finding. The
    Reconciliation screen under Debug Options shows it with the ledgers' open items; nothing reads it
    to dose. Unit tests in `ReconciliationLogTests` and `TandemKitReconciliationViewModelTests`.
  - Scenarios: unit tests in `BasalReconciliationReportingTests`; conformance group H.
- Every date a history pass takes from a record goes through `HistoryRecordDates.phoneDate(of:)`:
  past the pump's own clock changes (`HistoryTimestampReconciler`), then the pump clock offset
  (`hostDate(forPumpDate:)`), so boluses, transitions and the emit floor compare on the phone's
  clock. Build one per pass from the records it reads. Pump dates decode with the phone's current
  UTC offset, so `pumpClockOffset` moves by any change in it since the clock was read
  (`pumpTimeCheckUTCOffset`): a phone zone change between syncs does not misdate history (#482).
- Still open: a boundary that trails the live reads to the last history pass (#353). Loop's
  `DoseStore` stores nothing while the boundary is at or behind the end of the newest finalized
  basal it holds, and leaves out of IOB a dose that ended before the boundary and was not stored, so
  a boundary held behind the app's own finalized temp basals and then advanced by an empty batch
  drops doses from IOB. A temp rate the app did not set reaches the host only through basal
  reconciliation, after the fact; the live path still ignores it.

### Therapy command validation
- The pump delivers basal in 5-minute cycles: at each it writes a `BasalDelivery` (279) record and
  delivers 300 s at its `commandedRate`. A change of rate (a temp's start or end, a profile segment,
  Control-IQ) takes effect at the next BasalDelivery record, 0–5 minutes after the command, and a
  temp set and replaced between two BasalDelivery records is never delivered. A late or missing
  BasalDelivery record, or a resume inside the suspend's own cycle, delivers nothing until the next.
  `PumpBasalTimeline` reads this back: one chunk per BasalDelivery record, used once closed, and
  trusted only if it, the chunks either side, and its `DailyBasal` stretch agree with the pump's
  other records. Whether a temp or a suspend is in force is unknown where the replay starts and past
  a store gap, until a record says: the session's store starts mid-temp after a relaunch, and a lost
  `TempRateActivated` or `PumpingResumed` failed every record after it, so their real differences
  went uncorrected (#563). Meanwhile a BasalDelivery record consistent with itself passes: source 0
  at 0, 1 at its `profileBasalRate`, 2 at its own `tempRate`.
- `enactBolus` rejects non-positive amounts and anything above `state.settings.maxBolus`
  (seeded from `PumpManagerSetupSettings` at setup, then whatever the host app last synced).
  The pump enforces the same ceiling in firmware, because `syncDeliveryLimits` pushes it down
  via `SetMaxBolusLimitRequest`.
- A command the pump answers with a non-zero status fails as `.deviceState` carrying
  `PumpCommError.errorResponse` (`PumpRefusal`), naming the command and the status; an unanswered
  write is `noResponse`, and nothing reports `invalidPacket`. The pump gives no reason, so the
  message adds only what the driver can read off the command: a temp whose percent of the pump's
  rate works out under its 0.1 U/hr minimum or over the synced max basal limit, whether the temp it
  replaced was already stopped, a bolus's nack reason. A refused bolus cancel says the bolus may
  still be delivering.
- `enactBolus` refuses automatic boluses while Control-IQ is active. `enactTempBasal` refuses
  while Control-IQ is active, and with `bolusIsRunning` while a bolus is running, by the same test
  as `enactBolus` below (`bolusIsStillRunning`), not the progress reporter's elapsed-time
  estimate: a pump slower than the estimate is still delivering when it runs out, and no reporter
  survives a relaunch (#347).
- `enactBolus` refuses with `bolusIsRunning` while a bolus it started has not been seen to end
  (`isBolusInFlight`), and checks again inside its command job: a host's SMB enacted while a manual
  bolus was being initiated queued behind it and ran right after its `InitiateBolus`, and only the
  pump's permission nack stopped it (#504). Past the bolus's estimated end and its 30 s grace
  (`shouldDeferBolusSync`) it reads `CurrentBolusStatus` first, so a bolus that finished out of
  contact does not block the next; no answer still refuses.
  `cancelBolus` resets `bolusState` with `bolusDose`, or the next bolus is refused.
- A zero temp basal is always allowed, whatever the profile, sync or update state below, since 0%
  of any profile is 0. Control-IQ, a running bolus and a duration the pump refuses still refuse it.
- `enactTempBasal` refuses a temp outside 15 minutes to 72 hours (`supportedTempBasalMinutes`)
  before connecting: the pump refuses one too, but only after the running temp is stopped. It sends
  whole minutes and reports the temp for the minutes sent.
- `enactTempBasal` refuses every other temp but a cancel until the first successful
  `syncBasalRateSchedule` sets `hasSyncedBasalRateSchedule`: a temp rate is a percent of the
  pump's profile, which until then may not be the app's (#443). `deleteSavedPumpState` clears it.
  State saved before the flag existed reads false, and Loop and Trio only sync the schedule
  when the user saves it, so while it is false `enactTempBasal` reads the pump's profile
  (`adoptMatchingPumpProfile`) and sets the flag if it already matches the host's schedule. If
  it differs, that temp is refused and the queued update writes the schedule for the next one.
- A failed profile update clears `hasSyncedBasalRateSchedule` on every reading that still
  differs, a retry's included, and `adoptMatchingPumpProfile` skips while it stands: a matching
  profile does not explain a live rate that differs. Temp basals resume once a retry or a host
  sync reads the profile back matching. A non-zero temp already running when the update fails
  is stopped.
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
- A finalized temp basal's `deliveredUnits` is its rate times its run time, rounded to the pump's
  0.001 U (`TandemPumpCapabilities.roundToReportingResolution`). It is computed: the pump reports no
  volume for a temp.
- A `.basal` marker carries the rate the pump runs with no temp (`scheduledBasalRateInForce`): the
  `profileBasalRate` of a reading taken then, else the host's schedule on the pump's clock; while
  skewed, the host's own, which the clock skew temp runs. Neither host counts a marker's rate (both
  keep it zero-length), so it reaches only their records and the settings screen.
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
- A `SetTempRate` whose answer is lost may still have reached the pump, after the stop of the temp
  it replaces did (#340). `enactTempBasal` then reads `CurrentBasalStatus` and `TempRateRequest`
  and, if the pump runs a temp at that percent, reports it (`adoptUnansweredTempBasal`), ending
  the one it replaced; the command still fails. Otherwise the reading goes to
  `observeDeliveryState`.
- When those reads fail too (the link dropped with the answer), or a temp is set on the pump, the
  next sync sees it: with `historyBackfill` on, a `fetchBasalStatus` reading of a temp while the
  driver holds one also reads `TempRateRequest` (`observeReplacedTempBasal`). A temp at another
  percent, or one the pump started more than `transitionMatchTolerance` after the held dose's start
  (a held temp cut at a segment change starts at the cut, after the pump's record), is a
  `PendingTransition` with a `replacement`; `basalDose` keeps the held temp, and nothing cuts it at
  a segment change meanwhile. History ends the held temp at its `TempRateCompleted` and adopts the
  pump's from its `TempRateActivated` (start, duration, `tempRateId`; `automatic` if a
  SetTempRateResponse record has its id), at its percent of the pump's rate, mutable until its
  completion. If that activation is the held temp's own, nothing replaced it and the pending change
  is dropped. At detection the held temp ends at the pump's record of the new one's start, and the
  new one, whose duration only history gives (`TempRateResponse.duration`'s unit is unknown), is
  reported finished: at the last reading that saw it when above the schedule, at detection when
  below. The `.basal` marker after it is left out when a command reports in that same second. A temp
  the driver never sees reaches the host after the fact, through basal reconciliation.
- `suspendDelivery` stops a running temp, then sends `SuspendPumping`; `write` gives nil for a lost
  answer and a refusal alike (#340). Unless the suspend is confirmed it reads `CurrentBasalStatus`.
  Suspended after a nil, where the driver held no suspend, is the app's suspend, reported at the
  reading; any other reading goes to `observeDeliveryState`, which ends a temp the stop ended. The
  command succeeds whenever the pump reads suspended, so a cartridge wizard can go on.
- `ResumePumping` is read back the same way. Delivering after a nil, where the driver held a
  suspend, is the app's resume, reported at the send, the earliest the pump could have resumed. The
  command succeeds whenever the pump reads delivering, so no alarm is acknowledged for a resume that
  went through. One the pump refuses while it raises `RESUME_PUMP_ALARM` or `RESUME_PUMP_ALARM2`
  acknowledges those and is retried once (`ResumeWithAlarmAcknowledgement`), from the host's resume
  and the settings screen's alike: the host shows only its own error, and the alarms ask for the
  resume being made (#170). Any other alarm is left for the user to dismiss.
- A pump clock more than `pumpClockSkewThreshold` (5 min) off the phone's (`isPumpClockSkewed`)
  raises a LoopKit alert, retracted once the clock agrees (`pumpClockSkewAlertIssued`, persisted),
  and a status highlight; the settings screen syncs the clock. While skewed, wherever the host
  counts its own scheduled rate the pump runs a temp at the percent of its own rate that delivers
  it (`maintainPumpClockSkewCompensation`, every basal read and after a cancel). The host is not
  told of it: what it counts is what runs. A temp the driver did not set is left alone. A request
  equal to the pump's own rate goes out as an explicit 100% temp, reported at that rate; whether
  firmware accepts 100% is unconfirmed, and a refusal fails the command.
  `syncPumpData` reads the pump's clock before its basal status for this.
- A pump clock more than `pumpClockOffsetTrustLimit` (24 h) off the phone's
  (`isPumpClockUntrusted`) is more than a time zone or DST change explains, so nothing that adds
  insulin acts on it. `enactBolus` and `enactTempBasal` fail with `pumpClockUntrusted`, except a zero
  temp and a cancel, which only reduce delivery. `maintainPumpClockSkewCompensation` starts nothing
  and stops the temp it has running, `verifyDeliveredBasalRate` skips its profile check, which
  looks the schedule up on that clock, and `pumpSegmentChanges` finds none. It follows the latest
  read, so it clears at the first sync that reads the clock inside the limit, as after the settings
  screen sets it. One read came 2^32 ms short right after a pump reset (#503), so a single bad read
  refuses dosing until the next sync, up to a loop cycle. `hostDate(forPumpDate:)` leaves a date
  alone under such an offset.
- The driver sets the pump's clock only from the settings screen and at setup (`writePumpTime`),
  never on its own. It reads the clock first and reports how far it moved through
  `didAdjustPumpClockBy`, negative for a pump that ran ahead (MinimedKit passes the drift, the
  other sign). Setup sets it before the host adopts the manager, so the report waits for the
  delegate and its queue.
- There is **no IOB ceiling**. The pump's IOB is read (`fetchInsulinOnBoard`) on every sync and on
  the qualifying events pumpX2 reads it for, into `state.latestInsulinOnBoard`, but nothing doses
  on it. Only `ControlIQIOBRequest` is sent, and only once the pump has answered a Control-IQ
  info read: a pump with Control-IQ answers that opcode whether it is on or off, and a wrong
  opcode waits out the 30 s response timeout. `NonControlIQIOBRequest` is never sent.
- The pump's IOB is held against what the host was told (`UnreportedInsulinOnBoardMonitor`), one
  way only, since the host's IOB is out of the driver's sight and runs on another insulin model
  and duration. With Control-IQ off (`iobType` Mudaliar) the pump counts bolus insulin alone, and
  what is left of a bolus never exceeds the bolus. So a reading more than 0.05 U above every bolus
  `BolusReportLedger` reported within the pump's insulin duration, for 30 minutes, logs a warning:
  a pump-UI or extended bolus the host never heard of, or one whose report was lost. The ledger's
  `units` is what the host counts (programmed while mutable, delivered once finalized); the check
  skips while the ledger is younger than the window or an entry in it has no amount. Under
  Control-IQ the pump also counts basal above and below the profile, so nothing is compared.
- The window is the active profile's insulin duration (`PumpInsulinDuration`, persisted), read by
  `fetchInsulinDuration` (`ProfileStatusRequest`, then `IDPSettingsRequest` for slot 0) in the
  daily settings read, on any sync while it is unknown, and on the qualifying events that suggest
  `ProfileStatusRequest` (`profileChange`, `activeProfileSegmentChange`, `pumpResume`). Nothing is
  compared until it is known. Whether the pump moves boluses already given to a shortened duration
  is unknown, so the longer one stays the window until that long after the change.
- Scenarios: conformance group I, `InsulinOnBoardConformanceTests`, against faketandem's model of
  both IOB figures; unit tests in `UnreportedInsulinOnBoardTests`.
- There is **no app-side temp basal rate check**; the pump's own max basal limit is the
  only ceiling. (`maximumTempBasalRateExceeded` was never wired up in any revision and has
  been removed rather than left as a dead enum case.)

### Unanswered bolus command
- `write` gives nil whether `InitiateBolus` never left the phone, the pump refused it or its answer
  was lost, so `enactBolus` then asks the pump (`settleUnansweredBolus`, #327). Its bolus id running
  in `CurrentBolusStatus`, or in `LastBolusStatus`, is reported as an acknowledged bolus would be,
  and the enact succeeds. Nothing running and a last bolus whose id precedes it on the pump's 16-bit
  counter (`bolusId(_:precedes:)`) means it never started: the permission is released and the enact
  fails as `noResponse`, with nothing reported.
- Otherwise the enact fails with `.uncertainDelivery`, and the bolus is registered as an
  acknowledged one is (ledger entry, `bolusDose`, a mutable event at the programmed amount, dated
  when `InitiateBolus` was sent) but with `isUnconfirmed` (persisted) set and no progress reporter.
  `deliveryIsUncertain` reads it, and the status highlight says so, since Trio does not act on the
  flag. The permission is kept: a release could reach a bolus the pump is running.
- Every bolus status read settles it (`confirmUnansweredBolus`): `shouldDeferBolusSync` never
  defers for it, `ensureCurrentPumpData` is not throttled while it stands, and the next
  `enactBolus` reads the pump before refusing with `bolusIsRunning`.
  Running, or in `LastBolusStatus`: tracked as any app bolus. Never started: the permission is
  released and the bolus finalized at 0 U, as a zero-delivery cancel is (#455). A later bolus in
  `LastBolusStatus`: only history can tell, so it is held in `pendingBolusFinalization` at its
  programmed amount. No answer: it stays unconfirmed. History that reads its `BolusCompleted`
  finalizes it under the live `raw`, through its ledger entry.

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

### Marker events
Events with no dose, each in a `replacePendingEvents: false` batch under a `raw` of its kind and date.
- The wizards report a change once the pump has done its part: `recordCartridgeChange` a `.rewind`,
  `recordTubingFill` a `.prime` when insulin flowed before fill tubing mode was left, and
  `recordSiteChange(primeAmount:)` a `.prime` with its `.replaceComponent(.infusionSet)`. Loop
  derives no doses from reservoir drops within an insulin duration of a `.prime`, so meanwhile a pump
  bolus held behind `reconciliationBoundary` (#353) is missing from Loop's IOB until history reports
  it, as it always is from Trio's. A fill done on the pump's screen is not reported (conformance D8).
- `reportPumpAlarms`, at every `fetchNotifications`, reports each alarm and malfunction once as an
  `.alarm` with its `pumpAlarmType`, dated at the read since the alarm status gives no time, and an
  `.alarmClear` once a read that answered its category no longer finds it. `TandemAlertReconciler`
  diffs them against `reportedPumpAlarmIdentifiers` (persisted), as it does the LoopKit alerts.
  Alerts, reminders and CGM alerts are not faults and are not reported. Trio stores an alarm as
  `PumpAlarm`, its title the note, and nothing for a clear.
- A pump whose serial differs from `lastPumpSerial` (persisted, and kept through
  `deleteSavedPumpState`) is reported as `.replaceComponent(.pump)`, which Trio stores as a site
  change, and through `pumpManagerPumpWasReplaced`, which both hosts ignore. The first pump paired is
  not a replacement. The serial is read with the daily settings, which `deleteSavedPumpState` makes
  due, so the sync after a re-pair reads the next pump's.

## Open work
Beyond the missing tests and the history items above. The `loopkit-conformance` issues track
where dose reporting departs from LoopKit's guide; `docs/conformance-test-plan.md` maps them to
integration scenarios.

- **CGM data.** Glucose from the pump's sensor (`CurrentEGVGuiDataRequest`) does not reach the
  host; TandemKit is not a `CGMManager`. The CGM screens only pair, start, stop and monitor the
  pump's sensor session.
- **Pairing.**
  - `JpakeRound1Framing` frames round 1 as pumpX2's client and server do (one stream cut at byte
    165, zero-padded at its end) and pairs against faketandem, whose JPAKE is pumpX2's, but has
    not been confirmed against pump firmware.
  - The legacy 16-character pump-challenge pairing is not implemented; only the 6-digit JPAKE
    code is.
- **Delivery-uncertainty recovery.** `deliveryIsUncertain` is set only for an unconfirmed bolus,
  which the next read of the pump settles on its own; `deliveryUncertaintyRecoveryViewController`
  returns the general `TandemUICoordinator`, and there is no dedicated recovery screen.
- **Response validation.** `PacketAssembler` checks the txId, packet countdown, declared length
  and CRC of every received message, but nothing checks the HMAC of a signed response.
- **Hardware validation.** [docs/hardware-test-plan.md](docs/hardware-test-plan.md) is the manual
  procedure for the t:slim X2 and the Mobi, but no run of it is recorded, so which pump firmware
  versions work is unknown.
