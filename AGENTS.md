## Reference material
- See [docs/ARCHITECTURE_ANALYSIS.md](docs/ARCHITECTURE_ANALYSIS.md) for deeper implementation notes.
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
Every `.swift` file under `Tests/` must be a member of the `TandemKitTests` target.
`scripts/check_xcodeproj_source_membership.rb --fix` adds new files and CI runs `--check`. There is
no exclusion list: a test that stops compiling is fixed or deleted.

### Virtual pump build
On Linux: `swift test --build-path .build-virtual -Xswiftc -DTANDEMKIT_VIRTUAL_PUMP`. Test files
import both CoreBluetooth and the types that shadow it, so
`Tests/TandemKitTests/VirtualCoreBluetoothNames.swift` pins the names. `VirtualCoreBluetoothTests`
exists only in a flagged build, which the `integration` job in `.github/workflows/macos.yml` and the
`virtual-pump` job in `.github/workflows/linux.yml` both run. Each names the flagged-only test
classes it runs, so a new one goes on both lists.

Behaviour that returns after being dropped with its code needs tests written against the current
architecture, not restored from git history.

### Harmonize lint rules
Run `swift test --package-path HarmonizeRules` (`--filter` with a rule's name for one rule); the
Linux workflow's `harmonize` job runs it. Don't add to a rule's baseline to get a new violation through.

### LoopKit and Linux
Linux builds compile against the fakes in `LinuxShims/`, which can drift from the real LoopKit; read
`LinuxShims/README.md` before adding to one. Fresh JPAKE pairing (and its tests) run only on Apple
platforms.

## Driver behaviour
Rules that are easy to break without noticing. The overall design is in
[docs/ARCHITECTURE_ANALYSIS.md](docs/ARCHITECTURE_ANALYSIS.md).

### Floating point
Insulin amounts are compared and converted in whole milliunits, through
`TandemPumpCapabilities.milliunits(_:)` and `floor(_:ontoGrid:)`, never by `==` or `Int(x * 1000)`
on the Doubles. A discrepancy that rounding explains never fails a command.

### Delegate queue
`PumpManagerDelegate` methods are only called through `pumpDelegate.notify` or
`delegateQueue.async`. Loop opens them with `dispatchPrecondition(condition: .onQueue(queue))`, so
a direct call from a driver queue crashes it, as a backfill tick reading
`startDateToFilterNewPumpEvents` from the command queue did. `pumpDelegate.call` is a
`queue.sync`, which deadlocks a caller already on the delegate queue. The exception is
`pumpManagerWantsDeletion`, which is async and awaited off it, as LoopKit's default `delete()` does;
`delete()` first takes a turn on the queue, so it follows every batch sent before it.

Nothing goes out until the host has set both the delegate and its queue (`canNotifyDelegate`):
`pumpDelegate.queue` reads `.main` until then, and Trio sets the delegate first. Loop next-dev
sets no queue and takes its pump calls on `.main`, so a delegate still without a queue
`unsetDelegateQueueGrace` later is reported to on `.main`.
`deliverStateMissedByTheDelegate` replays what was held once the second one lands, with the status
but not `pumpManagerDidUpdateState`: Loop and Trio save `rawValue` on the main thread right after
attaching, and a second save from their delegate queue races it (Trio's launch hung in a Thread
Sanitizer report of it).

Both hosts save the whole `rawValue` on every `pumpManagerDidUpdateState`, so a reading the host
doesn't use waits for the next state change instead of notifying: `fetchInsulinOnBoard` answers
every `iobChange`, about once a minute (#567). Status pushes are not skipped when the status is
unchanged: Trio dates its pump battery and pump status from each one, and its Nightscout upload
leaves out a battery reading older than 30 minutes.

Bolus progress observers are called on the queue the host passed
`createBolusProgressReporter(reportingOn:)`, which Trio relies on to serialize its own reporter
state. `TandemDoseProgressReporter` is shared by the command queue, the telemetry queue and every
host queue, so its state stays behind its lock.

### Responses and the shared link
- The pump has one link to the phone, and iOS notifies every app subscribed to a characteristic,
  so the driver also receives the responses to another app's requests, as field logs show after a
  connect (#507).
- History log, control stream and qualifying-event notifications are routed before the pending
  write: none answers a write, and at the 23-byte MTU the second notification of a signed stream
  message is HMAC, whose byte 2 can be any opcode. Control-stream messages that share an opcode are
  told apart by declared length (`ControlStreamMessages.responseType`).

### Pairing
- Only `pairPump` starts a first pairing. `connectIfNeeded` refuses a pump with no derived secret: the
  auto-reconnect after the pump dropped the link would otherwise replay the last code entered, silently,
  at a pump that had just refused it (#399).
- The pump checks the code only at key confirmation. On a first pairing, `Jpake4KeyConfirmationRequest`
  unanswered (a Mobi drops the link) or answered with a digest that does not match fails the connect with
  `PumpCommError.pairingCodeRejected`; any other failed round is `noResponse`. The link drop is the
  signature in field logs, and a glitch at that exact round reads the same.

### Setup history load
- A new manager reports no history from before its ledgers' `trackingSince`, since it cannot tell
  another host's app boluses from the pump's own, so a pump moved between Loop, Trio and Tandem's app
  arrived with the insulin it had just given missing from IOB (#607). Setup therefore offers to load
  the pump's history.
- What a manager may read of the pump's history starts at a sequence number, not a date: a date is
  only as right as the clock arithmetic behind it, which a field log's shelf-mode records got 2,512
  days wrong, and the date floor let them through. Setup's scan step holds the history
  (`holdHistoryBeforePairing`), and the first history status read after pairing, which
  `readDeliveryForSetup` asks for before setup writes anything, saves the pump's newest record
  (`HistoryBackfillState.preServiceThroughSequenceNum`). Nothing at or below it is read or reported.
  A load lifts it while it reads, then leaves the newest record it dated before its window as the floor
  (`historyBeforePairing`), so its window is decided once and no later re-dating moves it; a failed load
  leaves none, since what it read may stop short of the window. `serviceStartDate` keeps the phone time
  each floor stands for, and nothing decides on it. Every tick re-applies the floor setup chose, since a
  tick begun before the choice saves the floor it started with. A manager not paired by setup (set up
  before, the integration harness, the virtual pump) reads as before.
- The Load Pump History step shows the pump's readings whatever they are, none included: a Mobi that
  had reset answered with no last bolus, and another gave one 40 s old by a clock 31 h behind, which
  `hostDate` does not correct past `pumpClockOffsetTrustLimit`. So the last bolus is dated by its age
  on the pump's clock, read again just after it, which holds however far off that clock is.
- The load runs after the setup sync, not at the step: Loop saves no dose from a batch without a
  reconciliation boundary, which only a sync gives, and that sync's first basal reading is what the
  load matches a suspension the pump is in against.
- The load is done once a backfill tick has read the pump's newest record as of a status read under
  `setupHistoryLoadMaximumLag` old, not the newest record's own age: an idle pump writes one only
  every 5 minutes. Basal reconciliation skips the pump's suspended time, so only the reported suspend
  keeps the host from counting its schedule over it.
- History the host already holds (the same pump back in the same app) arrives under the `raw` it was
  told it under, and both hosts keep the row they hold, so every manager keys a dose on the pump's
  own identity: an app bolus on its `bolusId`, a suspend or resume on its
  `PumpingSuspended`/`PumpingResumed` record, a temp basal on its `tempRateId` and a part of one on
  `tempRatePart`. The load reports the temps an app set over Bluetooth before pairing under those
  identities, one still running finished at its programmed end as a deleted manager left it. A
  suspension the pump is already in when a manager first reads it is reported at detection, before
  the load could date it, but under its `PumpingSuspended` record when the session's store holds it.
  Below the pre-service floor the store does not, so a load that reads the record later gives it to
  that suspend (`claimOpenSuspend`) instead of reporting a second, as nothing resumed the pump between.
- Still reported twice: what a build without these identities reported, a suspend or resume reported
  at detection because history could not be read in time, a bolus or temp whose id was not past the
  last minted, and a temp set on the pump that a manager adopted under its `tempRateId`, whose cycles
  the next manager's load corrects.

### Onboarding and the basal schedule
- Loop and Trio never sync the host's delivery limits, basal schedule or clock during onboarding, so
  `applyOnboardingSettings` writes them to a freshly paired pump; without it the pump kept its own
  profile while the driver reported the app's (#206).
- With `quickBolusButtonSupport` off, onboarding also turns the quick bolus button off, which
  otherwise stayed live until the first sync (#353 P20-1).
- A pump that runs Control-IQ refuses the host's automatic doses, and its basal reaches the host only
  with `basalHistoryReporting`, so setup turns it off (`turnOffControlIQForSetup`) and must not finish
  with it on. That write is followed by no sync (a sync would read the pump's profile before the
  host's is written) and no hand-back (the host has not dosed with this pump yet).
- `syncBasalRateSchedule` refuses, before connecting, a schedule with more than
  `maximumBasalScheduleEntryCount` entries, because Trio's editor doesn't enforce the limit and a
  schedule migrated from another pump can exceed it (#443), and one whose first entry is not at 00:00,
  the start time of the pump's segment 0: past the deletes, the pump would refuse it mid-write.
- A segment modify flags in its status mask only the fields it changes (`START_TIME`,
  `BASAL_RATE`), never segment 0's start time, as Tandem's app does: a Mobi refused every
  segment-0 modify flagging all five. Deletes flag all five. A create copies segment 0's carb
  ratio, target BG and correction factor and flags only those segment 0 holds: a Mobi refused a
  create flagging all five with the target BG and correction factor of 0 that a profile holding
  neither reads back. Whether firmware takes a create flagging fewer than five is unconfirmed.
- The schedule's rate up to `basalRateCheckTolerance` either side of a segment change matches the
  pump's: the pump-clock offset trails the pump's clock by up to a second plus the read's latency,
  and the read a segment change triggers lands in that gap (#566). An all-zero schedule is the
  placeholder for one the host never gave, so the check skips it.
- The driver writes the host's schedule over a pump profile that differs, under Control-IQ too,
  since hosts take the pump to hold what they last saved (Trio keeps a profile only once the sync
  takes). A failed update clears `hasSyncedBasalRateSchedule`, which refuses temp basals (see
  Therapy command validation). An all-zero schedule, or one `syncBasalRateSchedule` would refuse, is
  never written, so it fails this way.
- A schedule change that alters the rate in force stops a running non-zero temp basal, since the
  pump rescales it, and restarts the scheduled basal dose at the new rate. A zero temp keeps running.

### Reconciliation boundary
- Loop takes delivery up to `lastReconciliation` as accounted for, and no other answer, a reservoir
  level included, says anything about delivery. So it moves only at a dose change the driver reports
  and at the end of a sync whose `CurrentBolusStatus` and `CurrentBasalStatus` reads the pump
  answered (#449); an unreconciled sync hands the host the boundary it had and arms no poll
  throttle. A bolus the sync defers to, which the host already counts, stands in for its read.
- A reservoir reading reaches the host only once `lastReconciliation` covers it, after the batch
  that carries the boundary: past its boundary, Loop's `DoseStore` counts whole-unit reservoir drops
  in place of pump events, which made IOB alternate. After a sync whose delivery reads went
  unanswered the host has nothing newer than its boundary, so Loop's 15-minute pump data check stops
  it dosing instead of counting reservoir drops. `reconciliationBoundary`'s hold for a pump bolus
  (#353) is behind the reading on purpose, and the gate is the driver's own boundary. Trio doses on
  neither.

### LoopKit alerts
- Loop and Trio register the manager as alert responder and sound vendor under its
  `pluginIdentifier` and route an acknowledgement, or a sound lookup, by the alert's
  `managerIdentifier`. Every alert is issued and retracted under `TandemPumpManager.alertIdentifier`;
  one under `managerIdentifier` (`"Tandem"`, which is the HUD provider's) was acknowledged on the
  phone alone and stayed on the pump (#592).
- Both hosts record an acknowledgement whether or not it reached the pump, and Trio only logs a
  failure. So a failed `acknowledgeAlert` forgets the alert as issued
  (`issueAgainAfterFailedAcknowledgement`), and the reconciler issues it again from the last read
  while the pump still raises it, out of range included. A malfunction, which the pump cannot
  dismiss, stays acknowledged.

### Pump event batches
- Nothing reaches the host that ends before it starts or starts more than a minute ahead of the
  phone (`HostDoseDates`): Trio's Apple Health upload threw on such a temp basal at every launch
  until its row was deleted. Each one it catches is a misdated dose upstream and logs an error.
- A `replacePendingEvents: true` batch makes both hosts delete every mutable dose it leaves out,
  and Loop never revives a deleted one, so `emitPumpEvents` appends the boluses the host holds as
  mutable (`bolusDose`, `pendingBolusFinalization`, `heldExtendedPartEvents`) to each one (#330).
  The temp basal is each call site's job, via `getActivePumpEvents`.
- Loop's `DoseStore` keeps a stored `PumpEvent` row over a non-replacing report with the same
  `raw`, so finalizing a dose the host holds as mutable takes a replacing batch (#452).
- A bolus the pump confirms delivered nothing is finalized at 0 U, not withdrawn as LoopKit's guide
  has it (#455). Loop stores no dose for a 0 U bolus, so its mutable copy stays deleted, the guide's
  end state, and Trio keeps a 0 U row. Withdrawn, it would stay in Loop at its programmed amount
  whenever the batch held nothing else, since an empty batch purges nothing there.
- A temp basal keeps one `raw` from its first report to its last, however it ends (#344). A temp the
  app set or history adopted carries `eventRaw` (persisted), `HistoryLogSyncIdentifier.tempRate` of
  the pump's `tempRateId`. An id not past `lastTempRateEventRaw` mints nothing: the pump's 16-bit
  counter may restart, and a host still holding a row under the id's earlier use would swallow the
  new temp. The part after a segment cut is a dose of its own under
  `HistoryLogSyncIdentifier.tempRatePart`, which a later manager counts alike from history.
- A temp basal's `automatic` and `setByHost` stay what they were at its first report through every
  part, continuation and remainder (`tempBasalPart`), or the host sees a manual temp turn automatic
  partway through. `setByHost` marks the host's own temp, which `automatic` does not: history adopts
  another app's Bluetooth temp as automatic too, and state saved before the flag reads false. History
  knows a temp set from TandemKit's settings only by its `tempRateId`, whose `SetTempRateResponse`
  record reads like the host's, so `manualTempRates` (persisted for `manualTempRateMemory`) keeps it
  manual in adoption and basal reconciliation. The setup load reports any app's temp as automatic.
- A suspend or resume read from history is keyed on its record (`HistoryLogSyncIdentifier.logSequence`).
  A `.basal` marker, and a suspend or resume reported at detection with no record to key it on, is
  keyed on its type and its date to the millisecond (#352): of two rows under one `raw`, both hosts
  keep the first, and two of one type can fall in one second. `getActivePumpEvents(endDate:)` closes
  a temp basal that ran out with a marker at its end only when `endDate` is a second or more later;
  in that second the caller's change says the same, and Trio would order the two rows arbitrarily.
- Nothing may be reported to start after a mutable temp basal's start while the host holds it open,
  and no report starts in the same second as a row the host holds: Trio orders two rows at one
  timestamp arbitrarily and leaves one zero-length, so an override starts a second later. A history
  pass replaces only when it ends or re-states the temp basal the host holds as mutable.
- A sync that moves the boundary re-sends every dose the host holds as mutable as one replacing
  batch (`reportPendingDoses`), so a running dose is refreshed until it finalizes (#330, #450). Loop
  keeps its row over a non-replacing re-send, so it has to replace. With nothing mutable the batch is
  the boundary alone, empty and non-replacing: an empty replacing batch purges every mutable row in
  Trio.
- While a delivery change waits for history, the host still holds the dose the change ended, so
  `getActivePumpEvents()` gives it as last reported, uncut and mutable (#556): leaving it out of a
  replacing batch deletes it for good in Loop. `getActivePumpEvents(endDate:)` ends the temp at the
  caller's own change, so its callers settle the pending change first.

### Deleting the pump manager
- `delete()` sends one replacing batch that finalizes every held dose before
  `pumpManagerWantsDeletion` (#350): left mutable, the host's next replacing batch, from whichever
  pump manager comes next, deletes what it holds. A Tandem pump keeps delivering after the app
  forgets it, so nothing is stopped and no `.suspend` is due. A pending delivery change is reported
  at detection first. The batch also carries a "Pump Removed" `.replaceComponent(.pump)` if the
  manager ever read a pump; with nothing held, that marker goes alone, non-replacing, since an empty
  replacing batch purges Trio's mutable rows.
- A running temp basal is finalized at the deletion, a second after its start at least, and what
  remains of it to its scheduled end is a finalized dose of its own, keyed on its amount and start.
  Loop stores a finalized dose only once it has ended, and a mutable copy it soft-deletes before
  then can never be replaced, so one finalized whole would leave Loop's IOB once a boundary passed
  its end. Loop counts the remainder from its `PumpEvent` row until it can store it, at its first
  save behind a later boundary, which only the next pump manager gives it.
- A remainder the pump rescales at a segment change is still one dose, at the highest rate the pump
  runs it at, so both hosts count at least what it delivers, and under the identity of the temp's
  next part (`tempRatePart`), which a later manager's load reports for the part after the change.
  Cut there, the part after the change started ahead of Trio's clock, Trio stored it at its own, in
  the remainder's second, and its IOB counted only one of the two (conformance K3).
- A held bolus is finalized with its `BolusCompleted` record if backfill has read one, otherwise at
  its programmed amount, ended no later than the deletion so Loop stores it at once. A held extended
  part, which the pump runs on to its programmed end, is cut at the deletion as a temp basal is: the
  share of its programmed amount up to then under its own `raw`, and the rest a finalized dose of its
  own to its programmed end under a new `raw`.
- Still open: Loop next-dev saves on every batch, empty ones included, so the remainder is stored to its
  programmed end once that passes, before the next manager's history reports how the pump ran it, and
  a report from that history starting before then is not stored (conformance K5). Across a
  segment change the remainder over-counts wherever the pump runs it below its highest rate; across two
  or more, a later manager's load reports the parts past the first again, which both hosts count too.

### History backfill and dose reporting
- The pump sends `.bolusChange` at both activation and completion, and each kicks a history tick;
  one requested while a tick runs runs straight after it instead of being dropped.
- While `historyBackfill` is off the pump's history log is never read, and the other two history
  flags are `&&`-ed with it. None is a dry run: a watermark written for entries that were never read
  would mark them read and suppress them once the flag goes on, so `reconciledThrough` only moves
  while basal reporting is on.
- The host's `startDateToFilterNewPumpEvents` bounds neither the walk nor reporting (#345): Trio
  returns `lastEventDate - 15min` and drops nothing itself, so it would bound the walk minutes into
  the past and drop a pump-UI bolus found one sync late. `HistoryBackfillState.firstSeenFloor` bounds
  by date how deep the walk reads, and the undatable and pre-service floors and the store's retention
  watermark by sequence number; `HistoryBackfillPlanner.emitFloor` bounds reporting.
- Suspends, resumes and temp basal ends the pump made on its own (#333, #331). Neither host revises
  one once told: Trio keeps a row per (timestamp, type) and Loop never counts a non-bolus dose older
  than its last finished basal (#354). So the first report carries the pump's date, and reaches the
  host before anything the app commands after it.
  - A change the app did not command stays pending until a history pass dates it from
    `PumpingSuspended`/`PumpingResumed`/`TempRateCompleted`, and is otherwise reported at detection.
    The record is to the pump's second, so a pending change is dated no earlier than the last reading
    before it and a command's send, and no later than its detection (`dateOfChange`): an event the
    host was told of just before must not come after it, Loop ignores a suspend older than its last
    finished basal, and drops a temp basal of no length.
  - A sync that leaves a change pending completes once it is reported, or after
    `transitionHistoryWait` at detection, and is not throttled meanwhile, so the host doses on a sync
    that has reported it. `resumeDelivery` reads the pump first and waits the same way: the resume
    ends the temp basal the host holds, so a stop the driver missed must be reported before it, or
    Loop ignores it. Before an app command that changes basal emits, a pending change is reported at
    detection first, and so is the first of two changes that history has not yet dated.
  - At detection each end is dated the way that counts more insulin: a stop at detection, a
    resume at the last reading that saw the pump suspended, a temp basal below the schedule
    ended at that reading and one above it at detection, against the host's schedule on the
    phone's clock.
  - An occlusion stop leaves the running temp basal set: the pump writes no `TempRateCompleted` for
    it, keeps its programmed end, and runs it again from a resume before then (seen on a Mobi; other
    stops and the t:slim X2 unconfirmed). The host is told it ended at the stop, so the part a stop
    ended is kept as `interruptedTemp` (persisted), and the first reading of a temp at its rate after
    the resume reports the rest, mutable, from a second after the resume to the programmed end under
    a `raw` of its own.
  - Never sent: a suspend whose resume has not been read while the pump delivers (Trio takes a
    trailing suspend as lasting until now), a resume with no suspend before it in the host's
    view (Trio takes the pump as suspended since its history began), a suspend and resume in
    one second (Trio's IOB throws), and a second suspend in a row (Loop keeps only the later).
    Only the same-second pair is marked handled; the others are reconsidered next pass, since
    the other half may be in a gap the next tick fills.
  - Loop still stores but does not count a gap-contained pair it hears about after a later
    finished basal (#354). Trio counts it either way.
- With the serial known, the live path keys an app bolus on its `bolusId` from `InitiateBolus`, as
  history does. Without it the two identify one bolus differently (#344), so `BolusReportLedger`
  records each app bolus's `bolusId`, live `raw` and event date at `InitiateBolus`. It keeps entries
  12 h past the 24 h reporting horizon, since history dates an app bolus at activation on the pump's
  clock, which can be later than its entry. `trackingSince` is stamped on the first decode by a build
  that has the ledger; nothing older is reported, because it cannot be told apart from an app bolus
  reported live without an entry.
- A pump-UI, Control-IQ or lost-acknowledgement bolus is reported once, finalized, when its
  `BolusCompleted` is read, and not while it runs (#452): a mutable report would have to ride every
  replacing batch until then. Its insulin is missing from IOB for roughly the delivery time, since
  the pump's `.bolusChange` at completion kicks a tick.
- An extended bolus programmed off the app (on the pump's screen or in Tandem's app; TandemKit and
  Control-IQ never give one) is reported as two doses with one `bolusId` (#424).
  - The extended part is reported as soon as history reads its BolexActivated, mutable, because it
    can run for hours: at `bolexSize` over its programmed duration, BolusDelivery's
    `extendedDurationRequested` or BolusRequestedMsg2's `duration` on t:slim X2 firmware that writes
    no BolusDelivery records (both minutes). With neither it counts all at its start. Loop spreads it
    over that span; Trio counts it all at its start.
  - Every replacing batch carries it, under its first report's date, until its BolexCompleted is
    read, which finalizes it at `insulinDelivered` and its time, a stop part-way included.
  - A BolexCompleted whose BolexActivated is not in the store is not reported: BolexCompleted has
    no start time.
  - A held part whose BolexCompleted is still unread `extendedPartFinalizationWindow` after its
    programmed end is finalized at its programmed amount, which is what the host counted. History may
    never show its end (another pump, the flags turned off), and the ledger would otherwise drop it
    while still mutable.
  - A BolexActivated in the same second as its up-front part's start is moved a second later,
    because Trio matches a new row on its timestamp.
- A bolus the app did not start that the live bolus status sees running holds
  `reconciliationBoundary` at its start (or at the boundary already given, if later) until history
  reports it (#353). Loop takes delivery up to the boundary as accounted for, and past it falls
  back to reservoir doses, which count the bolus.
- While the pump may bolus on its own (Control-IQ on or handing back, or the quick bolus button not
  read as off: `awaitsHistoryBoluses`), `syncPumpData` waits for its history pass, so the host
  doses after a pump bolus that finished out of contact is reported.
- Basal reconciliation compares what the pump delivered (`PumpBasalTimeline`, P) with what the host
  counts (`ReportedBasalLedger`, H): every non-bolus row `emitPumpEvents` sends, folded as Trio's IOB
  folds them (the latest row at or before an instant wins, a temp basal until its end, a suspend
  until its resume, otherwise the host's schedule).
  - A chunk differs when H at its BasalDelivery record is more than 10 mU/h off its `commandedRate`
    (plus 1% of the profile for a temp chunk, which runs a whole percent). A matching chunk never
    differs, whatever H does later inside it: the host counts a change from its command, the pump
    from its next cycle, and that residual is only logged. A correction's own edges don't count as
    changes: they are the pump's cycles, and H before one is the previous chunk's, so a run of
    cycles at one rate would otherwise get only its first corrected.
  - H for a chunk that differs is the row in force from the last change the host was commanded within
    `transitionMatchTolerance` after its BasalDelivery record; with none, the row at the record. A
    stop that reached the pump just before a record and the next temp just after left the pump on its
    profile for the cycle, while the row the stop ended held a second of it: built against that row,
    the correction was empty and the chunk was passed for good (#564).
  - Temp chunks within `segmentChangeWindow` before a segment change are skipped, which the driver
    reports at the request on purpose.
  - Only with `basalHistoryReporting`, and only for a trusted chunk, is anything reported:
    - H from the host's schedule: a correction, an immutable `.tempBasal` at the pump's rate over
      the chunk, under `HistoryLogSyncIdentifier.logSequence` of the BasalDelivery record, so at
      most one per BasalDelivery record.
    - H from the temp basal the driver holds: ended at its `TempRateCompleted`, or, if the pump runs
      it at another rate, re-stated as at a segment change: finished at the old rate, a mutable
      continuation at the pump's, so the host never projects the pump's rate past the chunk.
    - H from a finalized temp basal: the pump's chunks reported in its place, from the
      difference through its end, the first a second after its start. Neither host revises a
      finalized row, but Trio's IOB cuts one at the next row and does not resume it; Loop counts no
      basal older than its last finished one and ignores them.
    - H from a suspend: nothing.
- Every date a history pass takes from a record goes through `HistoryRecordDates`, which dates it by
  its age on the pump's own clock: the phone's time at a clock read, less that read's pump time less
  the record's stamp, all in the pump's own seconds, which have no zone (#482). That holds however far
  off the pump's clock is. `hostDate`, which stops correcting past `pumpClockOffsetTrustLimit`, dated a
  bolus given on a clock two days ahead two days ahead, and it reached the host starting when it was
  read and ending days out.
  - A clock read stands beside the pump's newest record then (`PumpClockAnchor`, in
    `state.pumpClockAnchors`): every record through it was written by then, every later one after. A
    tick takes one with its history status read, reusing a sync's read under
    `pumpClockReadingReuseWindow` old, and its passes run only once a second read after the history
    agrees with it (`confirmPumpClockAnchor`). A clock set between the history read and a lone clock
    read would misdate everything by the change, for good, since neither host revises a date; a bad
    read (#503) disagrees with a good one the same way. No answer, or two that disagree, and the tick
    dates and reports nothing; the next does. `writePumpTime` takes an anchor before it sets the clock.
  - A record is dated from the anchor above it and from the one below. Where the two differ by more
    than the pump's clock-change records between them explain, the clock jumped unrecorded, and the
    record is on whichever clock puts it between the two anchors. On both, it takes the later date if
    they are within `ambiguityLimit` (more of its insulin still acting), and is otherwise held; on
    neither it is held, and so is any record dated past the anchor above it. Of a run of anchors on one
    untouched clock only the first and last are kept, so the two around a change are the nearest taken.
  - A held record is never reported, as given now or otherwise: it dates to `distantFuture`, and each
    pass keeps what it would have reported under its `raw` in `state.heldHistory`, where it stays
    unhandled until a later pass dates it. Held `warningDelay`, it raises a LoopKit alert and a status
    highlight, since the host's IOB is missing it; `insulinActionWindow` after it was first held (after
    an extended part's programmed end) it stops warning. Basal reconciliation waits while a
    BasalDelivery record is held and unexpired, since `reconciledThrough` would pass its cycles for
    good, then works only from the records after it.
  - With no anchor yet (the walk's own dating inside a manager's first tick) a record is dated by
    `pumpClockOffset`, with no limit. Still open: a jump the pump did not record that falls before a
    manager's first anchor, or between two anchors whose bracket is wider than the jump, and a
    clock-change record below the session's span while the anchors either side of it are kept, which
    reads as an unrecorded jump.
- A `TimeChanged` or `DateChange` is carried back only along the clock it changed. The clock ends at
  an `ArmInitHistoryLog` or `ShelfModeHistoryLog` record, or where a stamp runs back further than the
  changes after it explain, and every record through it (`undatableThroughSequenceNum`) is left
  undated and read by no pass (`HistoryRecordDates.logs`). A Mobi woke from shelf mode at 2008, and
  setup's clock write moved the previous use's boluses 2,512 days ahead, which the host stored as
  given at the time they were read. Each pass reads `HistoryTimestampReconciler.clockHistoryTypes`
  with its own types.
- A record's raw stamp is never compared with a phone date: it is on whatever clock the pump ran when
  it wrote it, which after a reset reads years old. The store has no query by pump time
  (`datedHistory` takes a sequence range and filters by phone date), prunes by sequence number below
  the oldest record it was given within its retention, and the walk keeps where it stopped as a
  sequence range plus the phone date of its oldest record, dated when read. A field log's hourly prune
  by stamp took that record each hour, and the walk, finding no boundary, read a slice deeper each time.
- The newest undatable record the walk finds among the clock records is saved
  (`HistoryBackfillState.undatableThroughSequenceNum`), so the walk reads nothing at or below it and no
  pass reports from it (`TickOutcome.reportableRange`), across relaunches. A bolus delivered before a
  reset that history had not yet read stays out of IOB, and so does one before any `ArmInit`, whether
  or not that reboot lost the clock.
- Still open: a boundary that trails the live reads to the last history pass (#353). Loop's
  `DoseStore` stores nothing while the boundary is at or behind the end of the newest finalized
  basal it holds, and leaves out of IOB a dose that ended before the boundary and was not stored, so
  a boundary held behind the app's own finalized temp basals and then advanced by an empty batch
  drops doses from IOB. A temp rate the app did not set reaches the host only through basal
  reconciliation, after the fact; the live path still ignores it.

### Therapy command validation
- The pump delivers basal in 5-minute cycles: at each it writes a `BasalDelivery` record and
  delivers 300 s at its `commandedRate`. A change of rate (a temp's start or end, a profile segment,
  Control-IQ) takes effect at the next BasalDelivery record, 0–5 minutes after the command, and a
  temp set and replaced between two BasalDelivery records is never delivered. A late or missing
  BasalDelivery record, or a resume inside the suspend's own cycle, delivers nothing until the next.
  Whether a temp or a suspend is in force is unknown where `PumpBasalTimeline`'s replay starts and
  past a store gap, until a record says: the session's store starts mid-temp after a relaunch, and a
  lost `TempRateActivated` or `PumpingResumed` failed every record after it, so their real
  differences went uncorrected (#563).
- `enactTempBasal` decides whether a bolus is running by `bolusIsStillRunning`, not the progress
  reporter's elapsed-time estimate: a pump slower than the estimate is still delivering when it runs
  out (#347).
- `enactBolus` refuses with `bolusIsRunning` while a bolus it started has not been seen to end
  (`isBolusInFlight`), and checks again inside its command job: a host's SMB enacted while a manual
  bolus was being initiated queued behind it and ran right after its `InitiateBolus`, and only the
  pump's permission nack stopped it (#504). Past the bolus's estimated end and its 30 s grace
  (`shouldDeferBolusSync`) it reads `CurrentBolusStatus` first, so a bolus that finished out of
  contact does not block the next; no answer still refuses.
- The bolus state follows each host's display. Loop (and an unknown host, as LoopKit's guide has it)
  shows "Starting Bolus" for `.initiating` only while the command goes out, and its progress and
  cancel for `.inProgress`: so `.initiating` from before `BolusPermission`, `.inProgress` once the
  pump accepts, `.noBolus` again if it refuses. Trio shows its Initiating state for `.initiating`
  until the pump delivers: nothing while the command goes out, `.initiating` once the pump accepts,
  `.inProgress` once it delivers (`holdsInitiatingUntilDelivery`).
- The pump answers `requesting` for about `bolusInitiationDelay` before it delivers an accepted bolus,
  and the read its `.bolusChange` asks for queued behind a sync for 28 s, so `enactBolus`'s job, once
  the host has its answer, reads it about once a second (`followBolusToDeliveryStart`) and gives way
  to a cancel. The progress count starts at the first read of it delivering. Only that bolus
  delivering moves it on: whether the pump answers no bolus before starting one is unconfirmed.
- A Mobi takes a cancel while `requesting`, which Loop offers, and stores nothing of the bolus:
  `LastBolusStatus` keeps naming the one before. So a cancel finalizes at 0 U a bolus never seen
  delivering whose last read, `requestingReadEvidenceWindow` or less before the pump confirmed the
  cancel, was `requesting`, when `LastBolusStatus` then names an earlier bolus. Without that read an
  earlier last bolus stays the unknown it was (#328). Under Loop the bolus is `.canceling` from the
  call, since the cancel can wait seconds behind queued jobs and Loop put its tappable progress row
  back on the next status push, and a second tap sent a second cancel; a failed cancel puts it back.
- The progress reporter is rebuilt from the saved bolus at launch, counting from its delivery start:
  Loop asks for one only when it first reads `.inProgress`, which after a relaunch comes before any
  read of the pump. An unconfirmed bolus still gets none until the pump is seen delivering it.
- A zero temp basal is always allowed, whatever the profile, sync or update state, since 0% of any
  profile is 0. Control-IQ, a running bolus and a duration the pump refuses still refuse it.
- `enactTempBasal` refuses a temp outside 15 minutes to 72 hours before connecting: the pump
  refuses one too, but only after the running temp is stopped. It sends whole minutes and reports
  the temp for the minutes sent.
- `enactTempBasal` refuses every other temp but a cancel until the first successful
  `syncBasalRateSchedule` sets `hasSyncedBasalRateSchedule`: a temp rate is a percent of the
  pump's profile, which until then may not be the app's (#443). State saved before the flag existed
  reads false, and Loop and Trio only sync the schedule when the user saves it, so while it is false
  `enactTempBasal` reads the pump's profile (`adoptMatchingPumpProfile`) and sets the flag if it
  already matches the host's schedule.
- A failed profile update clears `hasSyncedBasalRateSchedule` on every reading that still differs,
  and `adoptMatchingPumpProfile` skips while it stands: a matching profile does not explain a live
  rate that differs. A non-zero temp already running when the update fails is stopped.
- `enactTempBasal` refuses a non-zero temp with `pumpProfileBasalRateIsZero` when the pump's
  `CurrentBasalStatus` reads a profile rate of 0 U/hr, before stopping a running temp basal; a
  Mobi ran a 0 U/hr profile for a day while the host was told its temp rates ran (#335, #343).
- `enactTempBasal` and `enactManualTempBasal` refuse any temp, zero included, with `pumpIsSuspended`
  when the pump's `CurrentBasalStatus` reads suspended, before stopping or setting anything. Commands
  run one job at a time on the command queue, so a suspend from the settings screen queued ahead of
  the host's job has already run when the host's reads the pump, and a Mobi answered the zero temp
  after it with status 1. A cancel still goes through.
- The pump refuses a percent whose share of its rate is under its 0.1 U/hr minimum (a Mobi
  refused 17% of 0.58 U/hr), so `tempBasalPercentAndRate` sends the lowest percent it accepts
  instead, nearer the request than 0%.
- The percent is worked out against the pump's own rate in force, `profileBasalRate` from that
  same read, and the temp is reported at that percent of it. Within `segmentChangeWindow` of the
  pump's next segment change it is worked out against the larger of the two rates and reported at
  the request: delivery never exceeds the request on either side, and the host can only over-count,
  until the change. Segment changes come from the host's schedule on the pump's clock
  (`pumpSegmentChanges`), which is the pump's profile whenever non-zero temps are allowed.
- The host's schedule is read by the phone's wall clock (`getScheduledBasalRate`), the pump's by
  its own, which observes no DST (`pumpScheduledBasalRate`, on `pumpWallClockShift`), and neither by
  the time since midnight, which runs an hour off the wall clock from a DST change to the next
  midnight. On a fall-back day that took a pump's 0.5 U/hr at 05:00 for its 06:00 segment's 0.7,
  refused temp basals for the hour, and cut a running temp at a segment change an hour early.
- A finalized temp basal's `deliveredUnits` is its rate times its run time, rounded to the pump's
  0.001 U (`TandemPumpCapabilities.roundToReportingResolution`). It is computed: the pump reports no
  volume for a temp.
- Neither host counts a `.basal` marker's rate (both keep it zero-length), so it reaches only their
  records and the settings screen.
- The pump rescales a running temp at each segment change, so `splitAtSegmentChanges` cuts its
  record there: finished at the change, and a new mutable part at `tempPercent` of the new rate.
  Every path that finishes a temp cuts it first, since neither host revises a temp basal once told
  it finished. Hosts sync before they dose, so no dosing decision sees the uncut record; while
  disconnected it stays uncut until the next reading.
- After `SetTempRate`, `enactTempBasal` reads `CurrentBasalStatus` back and needs a temp within
  one 0.01 U/hr step of the percent of the pump's own rate (its rounding is unknown; 10% of
  0.15 U/hr is reported as 0). Otherwise it fails with `tempBasalRateMismatch` but keeps the temp
  the pump runs, reported at the pump's rate, so the host counts what goes in: stopping it would
  put the pump on its profile, which over-delivers whenever the temp was below it. No answer to
  the read reports it as commanded. Field logs show the temp in the first status read, within a
  second, every time.
- The pump refuses a `SetTempRate` while a temp rate runs, so a replacement stops the running temp
  first and the pump is on its profile until the set lands. Everything the pump could refuse is
  settled before the stop (a request above its max basal limit becomes the limit), and a set it
  refuses anyway puts the stopped temp back for what remained of it (`restoreStoppedTempBasal`).
- A `SetTempRate` whose answer is lost may still have reached the pump, after the stop of the temp
  it replaces did (#340), so `enactTempBasal` reads `CurrentBasalStatus` and `TempRateRequest` and,
  if the pump runs a temp at that percent, reports it (`adoptUnansweredTempBasal`); the command still
  fails.
- A temp set on the pump, or one whose answer was lost with the link, is found by the next sync
  (`observeReplacedTempBasal`): history ends the held temp at its `TempRateCompleted` and adopts the
  pump's from its `TempRateActivated`. The pump stamps the start on the clock in force when the temp
  began, which a set since (as at a DST change) has moved. So a clock read that finds the pump's
  clock moved since the one before records the step (`lastPumpClockStep`, persisted; a phone zone
  change is none), a start stamped while the held temp ran is also read on the clock before it, and
  one still ahead of the phone is taken for the held temp unless its percent differs, then dated at
  detection. A `timeChange` batch reads the clock before the basal status
  (`QualifyingEventFetch.timeSinceReset`). `PendingTransition.ReplacingTemp` keeps the start and
  percent `TempRateResponse` gives but not its duration (seconds), so the new one is reported
  finished at detection: at the last reading that saw it when above the schedule, at detection when
  below. A temp the driver never sees reaches the host after the fact, through basal reconciliation.
- `write` gives nil for a lost answer and a refusal alike (#340), so after `SuspendPumping` and
  `ResumePumping` the driver reads `CurrentBasalStatus` back unless the answer confirmed it. The
  command succeeds whenever the pump reads suspended, so a cartridge wizard can go on, or delivering,
  so no alarm is acknowledged for a resume that went through. A resume whose answer was lost is dated
  at the send, the earliest the pump could have resumed; a resume where the host holds no suspend is
  never reported at detection.
- A resume the pump refuses while it raises `RESUME_PUMP_ALARM` or `RESUME_PUMP_ALARM2` acknowledges
  those and is retried once (`ResumeWithAlarmAcknowledgement`), from the host's resume and the
  settings screen's alike: the host shows only its own error, and the alarms ask for the resume being
  made (#170). Any other alarm is left for the user to dismiss.
- A pump clock more than `pumpClockSkewThreshold` off the phone's raises a LoopKit alert and a status
  highlight. While skewed, wherever the host counts its own scheduled rate the pump runs a temp at
  the percent of its own rate that delivers it (`maintainPumpClockSkewCompensation`). The host is not
  told of it: what it counts is what runs. A temp the driver did not set is left alone. A request
  equal to the pump's own rate goes out as an explicit 100% temp, reported at that rate, which the
  pump takes and flags as a temp in `CurrentBasalStatus`.
- A pump clock more than `pumpClockOffsetTrustLimit` (24 h) off the phone's is more than a time zone
  or DST change explains, so nothing that adds insulin acts on it: `enactBolus` and `enactTempBasal`
  fail with `pumpClockUntrusted`, except a zero temp and a cancel, which only reduce delivery. It
  follows the latest read, so it clears at the first sync that reads the clock inside the limit. One
  read came 2^32 ms short right after a pump reset (#503), so a single bad read refuses dosing until
  the next sync, up to a loop cycle.
- The driver sets the pump's clock only from the settings screen and at setup (`writePumpTime`),
  never on its own. It reports how far it moved through `didAdjustPumpClockBy`, negative for a pump
  that ran ahead (MinimedKit passes the drift, the other sign). Setup sets it before the host adopts
  the manager, so the report waits for the delegate and its queue.
- There is **no IOB ceiling**. The pump's IOB is read (`fetchInsulinOnBoard`) on every sync and on
  the qualifying events pumpX2 reads it for, into `state.latestInsulinOnBoard`, but nothing doses
  on it. Only `ControlIQIOBRequest` is sent, and only once the pump has answered a Control-IQ
  info read: a pump with Control-IQ answers that opcode whether it is on or off, and a wrong
  opcode waits out the 30 s response timeout.
- The pump's IOB is held against what the host was told (`UnreportedInsulinOnBoardMonitor`), one
  way only, since the host's IOB is out of the driver's sight and runs on another insulin model
  and duration. With Control-IQ off (`iobType` Mudaliar) the pump counts bolus insulin alone, and
  what is left of a bolus never exceeds the bolus. So a reading more than 0.05 U above every bolus
  `BolusReportLedger` reported within the pump's insulin duration, for 30 minutes, logs a warning:
  a pump-UI or extended bolus the host never heard of, or one whose report was lost. Under
  Control-IQ the pump also counts basal above and below the profile, so nothing is compared. Whether
  the pump moves boluses already given to a shortened insulin duration is unknown, so the longer one
  stays the window until that long after the change.
- There is **no app-side rate check on the host's temp basals**; the pump's own max basal limit is
  the only ceiling.

### Temp basal from TandemKit's settings
- `enactManualTempBasal` sends the percent the user confirmed or nothing. A non-zero percent under
  the pump's 0.1 U/hr minimum or over its max basal limit at any profile rate in force over the
  duration (`manualTempBasalPercents`) is refused, not clamped or raised: what the pump does when a
  segment change takes a running temp past either is unconfirmed. 100% goes out as an explicit temp,
  which holds the profile rate and keeps the host from adjusting basal while it runs. The rest of
  the host path's checks apply as they are.
- It is reported manual (`automatic: false`), so Loop and Trio pause automatic dosing while it runs,
  and remembered in `manualTempRates`. A "Manual Temp Basal" status highlight shows while a manual temp
  runs, below every other.
- It replaces only the host's own temp (held `setByHost`, matching the read's percent and end) and the
  clock-skew temp, with nothing more asked: the user asked for a new temp. Any other running temp,
  a manual one included, refuses it with `tempBasalAlreadyRunning` and nothing is stopped.
- Without Control-IQ it is confirmed as the host's temp is (`tempBasalReadbackMatches`), 100%
  included. Under Control-IQ, which may set the rate the basal status reads, it is confirmed by
  `TempRateResponse` active at the percent sent, and a lost answer is adopted from `TempRateResponse`
  alone. A temp the pump took but reports at another percent, or none, fails
  `tempRateReadbackMismatch` and is reported as the pump reports it.
- Under Control-IQ it is sent anyway: some Mobi firmware takes a temp rate then and some refuses, and
  nothing checks which. A refusal says Control-IQ is on. `stopTempBasalFromSettings` is the host's
  cancel without its Control-IQ refusal, so a temp set then can be stopped.
- `readTempRateStatus` dates the end from `TempRateResponse`'s start and duration (seconds), both on
  the pump's clock, so it holds however far off that clock is.

### Unanswered bolus command
- `write` gives nil whether `InitiateBolus` never left the phone, the pump refused it or its answer
  was lost, so `enactBolus` then asks the pump (`settleUnansweredBolus`, #327). Its bolus id running
  in `CurrentBolusStatus`, or in `LastBolusStatus`, is reported as an acknowledged bolus would be,
  and the enact succeeds. Nothing running and a last bolus whose id precedes it on the pump's 16-bit
  counter (`bolusId(_:precedes:)`) means it never started: the permission is released and the enact
  fails as `noResponse`, with nothing reported.
- Otherwise the enact fails with `.uncertainDelivery`, and the bolus is registered as an
  acknowledged one is but with `isUnconfirmed` (persisted) set and no progress reporter.
  `deliveryIsUncertain` reads it, and the status highlight says so, since Trio does not act on the
  flag. The permission is kept: a release could reach a bolus the pump is running.
- Every bolus status read settles it (`confirmUnansweredBolus`): never started is finalized at 0 U,
  as a zero-delivery cancel is (#455); a later bolus in `LastBolusStatus` means only history can
  tell, so it is held in `pendingBolusFinalization` at its programmed amount; no answer leaves it
  unconfirmed.

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
  status. `CartridgeModeRecovery` backs out (exit fill tubing, exit change cartridge, enter change
  cartridge, no refusal stops it) and is offered once, when the wizard's enter is refused with
  delivery suspended and no pump notification to blame. The refusal rule is inferred from a field
  report and not confirmed on firmware.
- A refused enter, the recovery's included, first reads `LoadStatus`. A loading procedure still in
  `changeCartridge`, as a wizard closed mid-change leaves it, resumes the wizard at the cartridge
  swap with nothing sent; one in `loadCartridge` ends it at the tubing fill, with no cartridge
  change recorded. Backing out is wrong there: a Mobi took the recovery's `ExitChangeCartridgeMode`
  as the new cartridge being in, streamed detection, and refused change mode and both exits from
  then on.

### Cartridge wizard screens
- A pump notification takes a step over. On the five steps that watch for them (the change's
  disconnect and replace steps, the tubing fill's disconnect, connect and fill steps) the list
  replaces the graphic and the instructions, and the subtitle asks for it to be dismissed. An empty
  list is not shown, so nothing on screen re-reads it: the first read gates the start
  (`canStartChange`, `canStartFill`), and a refused `EnterFillTubingMode` reads again.
- The tubing fill sends `EnterFillTubingMode` from its connect step, after the disconnect step, so
  the tubing is on the cartridge before the pump will fill.
- Yellow messages are pinned with the bottom action (`WizardWarning`), opaque because the step
  scrolls beneath them. The tubing fill keeps its disconnect warning up with a notification to
  dismiss: the pump still fills while its button is held.
- The animations draw a Mobi, so they show unless the pump is known to be another model
  (`MobiAppGraphic.suits`). `replace_cartridge` is not Tandem's:
  `scripts/make-replace-cartridge-graphic.py` builds it from `remove_cartridge`, keeping the one
  transparent index the source has. gifsicle and ImageMagick give each frame its own, and a decoder
  that clears to the screen's background index then leaves specks where the cartridge was.

### Marker events
Events with no dose, each in a `replacePendingEvents: false` batch under a `raw` of its kind and date.
- Loop derives no doses from reservoir drops within an insulin duration of a `.prime`, so after a
  fill a pump bolus held behind `reconciliationBoundary` (#353) is missing from Loop's IOB until
  history reports it, as it always is from Trio's. A fill done on the pump's screen is not reported
  (conformance D8).
- Alarms and malfunctions are reported once as `.alarm`, dated at the read since the alarm status
  gives no time, and cleared as `.alarmClear` once a read that answered its category no longer finds
  them. Alerts, reminders and CGM alerts are not faults and are not reported. Trio stores an alarm as
  `PumpAlarm`, its title the note, and nothing for a clear.
- A pump change is a `.replaceComponent(.pump)`, which Trio stores as a site change, so it shows in
  both hosts' event history. A serial that differs from `lastPumpSerial` (persisted, and kept through
  `deleteSavedPumpState`) also goes through `pumpManagerPumpWasReplaced`, which both hosts ignore.
  The serial is read with the daily settings, which `deleteSavedPumpState` makes due, so the sync
  after a re-pair reads the next pump's.

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
- **Hardware validation.** [docs/hardware-test-plan.md](docs/hardware-test-plan.md) is the manual
  procedure for the t:slim X2 and the Mobi, but no run of it is recorded, so which pump firmware
  versions work is unknown.
