# Basal history reconciliation: implementation plan

Plan for #514, written against `dev` at 1b7d89b.

The driver reads the basal the pump actually delivered from its history log, compares it
with what it told the host, and reports the difference. That fixes #213 (Control-IQ's basal changes
never reach the host) and gives #340 an after-the-fact backstop. It also catches anything else that
leaves the host believing a rate the pump did not run: a temp the driver lost track of, a temp set
on the pump's screen, a temp the pump resumed after an alarm suspend, or a pump profile that differs
from the app's schedule. #340's immediate fix is phase 5 below and stays tracked in #340.

Decided by the maintainer:

- A new `basalHistoryReporting` flag gates every report. The comparison itself runs whenever
  `historyBackfill` is on and logs what it finds.
- One span per 279 record.
- The check is general, not special-cased to Control-IQ: it is a sanity check that the basal rate
  the host believes is the one the pump runs.
- No warning when Control-IQ is switched on with history reporting off, since history reporting
  will eventually be on by default.

## 1. Constraints

### 1.1 What the pump writes

"The Mobi exports" below are three pump history exports, analysed in §7.1: two consecutive ones
from a Mobi on Control-IQ+ 7.9.0.1 with Control-IQ off and Trio closed-looping (10,000 records over
43 hours, then 30,000 over 6 days), and an older one from a Mobi on Control-IQ 7.7.0.1 running
Control-IQ (24,864 records over 8 days).

| Record | Fields used | When it is written | How sure we are |
| --- | --- | --- | --- |
| `BasalDelivery` (279) | `commandedRateSource`, `commandedRate`, `profileBasalRate`, `algorithmRate`, `tempRate`, all mU/h; 0xFFFF means n/a | At each 5-minute delivery cycle, Control-IQ on or off, usually 30 s after the cycle's `ControlIQCycle` (227). About 1% come up to 4 minutes late, and once in 16 days of exports a cycle had none. Also at every resume after a suspend that lasted through a cycle (18 of 18), and the cadence restarts from it. Not at a suspend the app makes | The pump's basal total follows it (below). Sources 0, 1 and 2 confirmed with Control-IQ off; 0, 1 and 3 with it on, 1 while the CGM is unavailable; 4 (temp rate and algorithm) never seen |
| `TempRateActivated` (2), `TempRateCompleted` (15) | `percent`, `durationMilliseconds`, `tempRateId`; `tempRateId`, `timeLeft` | When the temp is commanded, and when it ends, is stopped or is replaced. Delivery follows at the next cycle (below) | Used today. `timeLeft` is in milliseconds and always a whole number of minutes (every completion in both exports) |
| `PumpingSuspended` (11), `PumpingResumed` (12) | `reasonId` | When delivery stops and restarts. Reason 1 at an alarm, 0 for the app's suspends | Used today. The temp running at an alarm suspend resumed with delivery (2 of 2, cartridge alarms): no `TempRateCompleted` at the suspend, and the first 279 after the resume showed it. The app stops its temp before it suspends, so its suspends cannot show this |
| `SetTempRateResponse` (309), `ControlRequest` (290) | `tempRateId`, `status`; `requestOpCode` (164 `SetTempRate`, 166 `StopTempRate`) | As the pump answers each control request it is sent | Both exports: one 309 with status 0 for every `TempRateActivated`, with the same `tempRateId`; the only others were two refusals (status 1, `tempRateId` 0). Logged by the pump as it answers, so it should survive an answer lost on the way (to confirm) |
| `ControlIQPcmChange` (230), `AaEnableSettingChange` (244) | `currentPcm`; `enabled` | 230 at every suspend and resume (PCM 1 → 0 → 1 with Control-IQ off, 3 → 0 → 3 with it on), and at the cycle where Control-IQ loses the CGM or gets it back (3 ↔ 2). Presumably 230 or 244 when Control-IQ is switched on or off | Under Control-IQ the PCM in force predicts every 279's source: 3 in PCM 3, 1 in PCM 2, 0 in PCM 0 (2,155 of 2,155). The switch is unconfirmed (Q2). 230 has a serialization test; 244 has none and pumpX2 has no vector for it |
| `DailyBasal` (81) | `dailyTotalBasal` (U), `lastBasalRate` (U/h) | Every 10 min, at each bolus's completion, and at other events | The pump's basal total for the day. It grows by one cycle's insulin per 279, about 10 s after the record, and `lastBasalRate` is the latest 279's `commandedRate` (2,731 of 2,734 records) |
| `BasalRateChange` (3) | — | On 7.7 with Control-IQ on: at every rate change, within a second before the cycle's 279, and at each suspend and resume. On 7.9 with Control-IQ off: never, across 1,439 temps, every profile segment boundary and 12 suspends | Where it exists it repeats the 279: its `commandedbasalrate` and `basebasalrate` matched the next 279's `commandedRate` and `profileBasalRate` every time (1,011 of 1,011). Tidepool's Tandem uploader builds X2 basal from it. Not used |

**The pump applies a rate at its next 5-minute cycle, not when it is set.** At each 279 it delivers
5 minutes of the rate in force and records it there; the exact-time records say when the command
changed. In both exports, one 300-second chunk at each 279's `commandedRate` reproduced the change in
`dailyTotalBasal` exactly (within 0.002 U) in 97–98% of the intervals between `DailyBasal` records,
and nearly all the rest was credit timing that the next interval cancels. A model that switches rate
at the temp records matched under half. Under Control-IQ (7.7) the chunks matched the pump's total to
the last digit over every stretch of an hour or more (785 of 785). So:

- a temp delivers from the first 279 after its `TempRateActivated`, 0–5 minutes later (over a
  minute for 9 in 10 of Trio's temps), until the first 279 after it ends;
- a temp set and replaced between two records is never delivered (1% of Trio's temps);
- a profile segment boundary also takes effect at the next 279, and leaves no record of its own;
- a suspend does not take back the cycle under way. A late 279 leaves the time before it
  undelivered, and the cycle without one delivered nothing;
- rarely (4 times in 6 days) a cycle delivered less than its record says, each time with a temp
  change or bolus in the seconds after the record.

While a temp runs, `commandedRate` is exactly `percent × profileBasalRate` in mU/h, with no rounding
to 0.01 U/h: all 2,218 samples, 70 of them at rates that such rounding would change. 104% of a
0.6 U/h profile runs at 0.624 U/h, not 0.62. Control-IQ's rates exist only in 279 (and, on 7.7, in
its `BasalRateChange` copy). Control-IQ's own changes of state follow the cycle too: it notes a lost
or regained CGM in a 230 at the cycle, and that cycle's 279, 30 s later, carries the new rate. The
`ControlIQCycle` record (227) is not used.

### 1.2 What the hosts do with a basal report

**Trio** (`dev` since nightscout/Trio#1300; jwoglom/Trio `dev` 1802999c):

- `.basal` is stored as a zero-length scheduled row (`PumpHistoryStorage.storedSpan`). Only
  `.tempBasal` rows carry insulin, so everything here is reported as `.tempBasal` doses.
- `PumpEventStored.toPumpHistoryEvents` turns every temp-basal row, scheduled rows included, into a
  `TempBasal` and duration pair. `IobHistory.getTempBasals` sorts them by timestamp and cuts each
  one off at the next row's timestamp. Net insulin is counted against Trio's own schedule.
  - Arrival order does not matter: a row reported late still cuts off the row before it. A later
    row is therefore how an earlier, wrong row gets corrected.
  - Two rows with the same timestamp leave one of them zero-length, whichever sorts first.
  - `extractTempBoluses` rounds each piece's net insulin to 0.05 U. A 5-minute piece with
    |net| below about 0.3 U/h counts zero. The same rounding applies to Trio's own temps, which
    the loop often replaces after one cycle.
  - Trio reads the current temp from `basalDeliveryState`, not from its history.
- Rows are matched by `syncIdentifier`, then by `(timestamp, type, isScheduledBasal)`. A finalized
  row never changes. A replacing batch deletes every mutable row it does not mention.
- `DeviceDataManager` drops a temp basal above `pumpSettings.maxBasal` before storing anything.

**Loop** (Trio's LoopKit fork, as `LoopDoseStoreOracle` models it):

- A non-bolus dose reaches the insulin delivery store, and so IOB, only if it starts at or after
  `lastImmutableBasalEndDate`, the newest end among immutable non-bolus doses. A history dose
  reported after a later live dose is stored and never counted (#354).
- An immutable temp basal without `deliveredUnits` counts `unitsInDeliverableIncrements`, in
  0.05 U steps. A 5-minute span at 0.79 U/h, 0.066 U, would count 0.05 U.
- A replacing batch deletes every mutable dose it leaves out. A non-replacing batch cannot
  finalize a mutable dose whose `raw` changed (#452).

**The test oracle has drifted.** `TrioDoseStoreOracle` was written the day nightscout/Trio#1300
merged, against the code before it: it skips any temp basal carrying `deliveredUnits` and dedupes on
`(date, type)`. It would show every finalized correction as skipped. Phase 0b brings it up to date.

### 1.3 Rules that follow

- **R1.** Every non-bolus event a history pass produces goes out in one batch, in ascending order:
  the corrections together with that pass's suspends, resumes and temp ends. Loop would otherwise
  drop a span older than something the previous batch finalized.
- **R2.** A pass that acts on the temp the driver holds (ends it or re-states it) reports that in
  the same batch as anything after it, and that batch is a replacing one. Nothing history reports
  may start after a held mutable temp's start while that temp stays open, because Loop would drop
  the temp when it is finalized later.
- **R3.** Whatever the host must hear before it next doses reaches it before the sync completes,
  as pending delivery transitions do today (`afterDeliveryTransitionIsReported`).
- **R4.** A correction never starts in the same second as a row the host already has (Trio, see
  the equal-timestamp bullet above). To override a row, it starts at least a second after it.
- **R5.** Every correction carries `deliveredUnits` (rate × duration, rounded to 0.001 U), an
  absolute rate, and an identity that never changes.

## 2. Design

### 2.1 Two timelines

- **P, the pump's timeline:** what the pump delivered, one chunk per 279, built from history by a
  pure `PumpBasalTimeline`.
- **H, the host's timeline:** what the host was told, from a ledger the driver keeps of its own
  reports (`ReportedBasalLedger`). Where the driver reported nothing, it is the host's schedule.

A pure `BasalReconciler` compares the two over closed, contiguous stretches of the store.
`TandemPumpManager+BasalReconciliation.swift` runs it on every history pass and acts on the
differences.

### 2.2 P: what the pump delivered

P is a sequence of chunks, one per 279 record (§1.1). Every record is dated through the shared
`phoneDate(of:)` from phase 0a (`HistoryTimestampReconciler.utcDate`, then `hostDate(forPumpDate:)`).

- **A chunk** starts at its record and runs 300 s at `commandedRate`, or until the next 279 or a
  suspend if one comes sooner. Its source gives the kind: algorithm (3, 4), temp (2), profile (1),
  suspended (0). 0xFFFF: unknown, no chunk.
- **A suspend cuts a chunk short, but not its delivery:** the pump delivered the whole cycle
  (§1.1). The rest, at most one cycle at one rate, is left out of P, since the host has the suspend
  from then, and the check in §2.4 counts it.
- **Time no chunk covers delivered nothing:** before a late record, a cycle without one, and from a
  resume that has no record to the next one. It is not compared (§2.4).
- **One chunk per record,** as decided, is the pump's own unit of delivery. Each chunk is identified
  by its record's sequence number (§2.6). Merging equal-rate records would make a piece's identity
  depend on the record before the run (the backward walk may not have read it yet) and on its last
  record (not known until the rate changes), so it would change identity or stay open indefinitely.
- **No profile is needed.** Each chunk's rate is in its record, segment boundaries included, so P
  does not depend on the host's schedule or on a verified profile.
- **The exact-time records cross-check P.** Read in sequence order (a 279 can fall between a stop
  and the next set in the same second), records 2, 15, 11 and 12 predict every 279's source and rate,
  using the record's own `profileBasalRate` and letting a temp running at an alarm suspend resume
  with delivery: 2,279 of 2,279 in the 7.9 exports. Under Control-IQ the PCM in force (230)
  predicts the source instead: 3 in closed loop, 1 while the CGM is unavailable, 0 while suspended
  (2,155 of 2,155 in the 7.7 export). A 279 they do not predict is logged and the chunks around it
  are not corrected, since one of the records is being misread. They also give a temp chunk its
  `tempRateId`, for §2.6.
- **Closed chunks only.** A chunk is used once the record after it (a 279 or a suspend) has been
  read, or the log has been read 300 s past it, and nothing between is missing from the store
  (`HistoryLogStore.missingRanges`). The chunk at the top of the log waits for the next pass (§2.8).

### 2.3 H: what the host was told

`ReportedBasalLedger` is new, persisted in `TandemPumpManagerState` and modelled on
`BolusReportLedger`. It is fed in `emitPumpEvents(_:replacePendingEvents:)`, which every report goes
through (23 call sites). It records every non-bolus event the driver reports:

- temp basal rows: `raw`, start, end, rate, mutable, and `tempRateId` where the live path has one;
- `.basal` markers;
- suspends and resumes.

A replacing batch drops the mutable rows it does not mention, as both hosts do. `trackingSince` is
stamped on the first decode, and rows are kept 36 hours.

H(t) folds the ledger the way Trio does. The latest row starting at or before t wins, and a temp row
counts until its end. A `.basal` marker, an ended temp or no row at all means the host's schedule
(`state.basalRateSchedule`, on the phone's clock). After a reported suspend H is 0 until the resume,
then the schedule. Before `trackingSince`, H is unknown and nothing is compared.

H includes the driver's own corrections, so once a correction is reported H agrees with P there.
The comparison is therefore idempotent: a relaunch's re-read of the 7-hour lookback reports nothing
twice. This also replaces the temp ledger keyed by `tempRateId` that #514 proposes:

- An app temp the host was told of agrees with the pump and produces nothing.
- A temp the host was never told of differs, whatever caused it.
- Skew compensation temps need no special case: they deliver what the host already counts.
- A temp stopped after a mismatched readback lasts seconds. In the rare cycle whose record falls
  inside it the pump delivered that cycle at its rate, and the correction says so.

### 2.4 Comparing

- **Per chunk.** H's rate at the chunk's record is compared with the chunk's `commandedRate`, in
  milliunits, with a tolerance of 10 mU/h, one pump step, as in `tempBasalReadbackMatches`. H's rate
  at any time within a minute of the record (`transitionMatchTolerance`) also matches, since the
  phone dates a command by its clock and the pump by its own.
- A chunk that matches is not a difference, whatever H does later in it (cycle timing, below).
- Not compared:
  - suspended time on either side (source 0, or a suspend H holds), which the transitions pass
    owns;
  - time no chunk covers;
  - store gaps;
  - anything before the floor, `max(firstSeenFloor, now − 24 h)` on phone dates, or ahead of the
    phone.
- Exempt: the over-count the driver makes on purpose inside `segmentChangeWindow` (#500). There the
  host is told the request while the pump runs the lower rate until the change.
- **P is checked against the pump's own total first.** Between two `DailyBasal` records written at
  least a minute after their latest 279, P's insulin, with any chunk a suspend cut short counted in
  full, must match the change in `dailyTotalBasal` to within 0.01 U. A shortfall is accepted where
  the stretch holds a chunk with a temp change or bolus in the seconds after its record, since such
  a cycle can deliver less than its record says (§1.1). Any other mismatch is logged and the stretch
  is not corrected, so a misread record cannot reach the host. In the Mobi exports every stretch of
  an hour or more passed: 1,170 of 1,182 within 0.01 U, and the other 12 each held one or more of
  those short cycles.

What should show up as a difference: Control-IQ (48% of its cycles in the 7.7 export; it ran the
profile rate in the rest); a temp the driver lost (#340); a temp set on the pump's screen; a temp
resumed after an alarm suspend (§7.1); a pump profile that is not the app's schedule (#400); the
pump clock's segments around a host segment change; a held temp the pump ended without any reading
noticing. Normal operation should produce none, and phase 2 checks exactly that in the field before
anything is reported.

**Cycle timing is not a difference.** The host counts a temp from when it was set. The pump delivers
it from its next cycle until the cycle after it ends, and never delivers one replaced within a
cycle (§1.1). So with every rate right, the host's basal is still up to a cycle off at each change.
In the Mobi exports, over any trailing 1 to 6 hours, the host's basal stayed within 6 minutes' worth
of the highest temp rate in use of what the pump delivered, over and under about equally often, and
within 0.5% over each whole export. v1 does not correct it:

- Loop would drop every such correction. Each starts before the app's next temp, which is finalized
  by the time the correction is read (#354).
- Trio would need two finalized rows per app temp: the old rate from a second after the temp's start
  (R4) to the pump's cycle, then the temp from the cycle. That is about 600 rows a day for a
  5-minute loop, each uploaded to Nightscout.
- Dating the app's temps at the pump's next cycle instead would give a dose a start minutes in the
  future, which neither host expects from `enactTempBasal`.

Phase 2 logs the cycle residual per day (the insulin H and P differ by, chunk by chunk), so whether
Trio should get those rows (Q9) can be settled from field data.

### 2.5 Acting on a difference

| H at that time comes from | With `basalHistoryReporting` on |
| --- | --- |
| Nothing: the host assumes its schedule (no row, a `.basal` marker, an ended temp) | Report P's chunks there as closed `.tempBasal` corrections |
| The temp the driver holds, still mutable | Act through the live path. If history shows that temp completed, finalize it at that record with `reportTransition(_:tempRateEnd:events:)`; what follows is then compared against the schedule. If the pump still runs it at another rate, re-state it from the chunk where they diverge, the way `splitAtSegmentChanges` cuts a temp: the finished part at the old rate, and a mutable continuation at the pump's rate |
| A row the host already finalized | Phase 4, Trio only. Report P from where they diverge (at least a second after the row's start, R4) through the row's end; the later row cuts the old one off, and the rest of it is re-asserted at P's rates. Loop drops these through its IDS window, harmlessly |
| A suspend or resume | Left to the transitions pass, and logged |

With the flag off, each difference is logged once (interval, P, H, kind, and the action it would
take) and nothing is reported. That log is the sanity check in the field, and it is phase 2's
deliverable.

### 2.6 Identities and fields

- **Identity:** a new `HistoryLogSyncIdentifier` scheme, `basalPiece = 4`, whose identifier is the
  sequence number of the chunk's record. Adding a scheme keeps the frozen 10-byte format.
- **Extent:** a correction runs from its chunk's record to the chunk's end, or to the host's next
  change inside the chunk if that comes first, so it never runs over a later row the host holds. A
  chunk gives at most one correction, and needs no part number.
- **Fields:** `.tempBasal`, `deliveredUnits` (R5), and `insulinType`. `automatic` is true for
  algorithm chunks and the app's own temps, and false otherwise. `wasProgrammedByPumpUI` is true
  for algorithm chunks (as history boluses do) and for temps the app did not set. The title is
  "Control-IQ Basal" for algorithm chunks and "Temp Basal" otherwise.
- **Who set a temp:** a temp whose `tempRateId` has a `SetTempRateResponse` (309) record was set
  over Bluetooth, by the app. One without was set on the pump's screen. That needs no bookkeeping
  of the app's own commands, and covers a command whose answer was lost (#340).

### 2.7 Emission

- `reportHistoryDoses` (`TandemPumpManager+HistoryDoseReporting.swift:7`) runs the transitions pass
  and the reconciliation, and emits their events as one batch (R1), then the boluses. The
  transitions pass returns its events to that single emission instead of emitting them itself
  (`TandemPumpManager+DeliveryTransitions.swift:182` and `:321`).
- A batch is replacing only when it acts on the held temp (R2). It then carries
  `getActivePumpEvents()`, and `emitPumpEvents` adds the boluses. `reportTransition` currently
  decides replacing by `events.contains { $0.dose?.type == .tempBasal }`, which every correction
  batch would now meet, so it needs an explicit flag instead.
- The reconciliation never runs past a store gap. Otherwise a healed gap's corrections would arrive
  after newer ones and Loop would drop them. A gap the coordinator has not healed within two ticks
  is skipped and logged.
- A correction above the pump's max basal limit (`maxBasalLimitMilliunits`) is logged as an error,
  since Trio drops anything above its `maxBasal`. Control-IQ stayed under the limit (Q5, §7.1).
- A persisted `reconciledThrough` sequence number only bounds the work per pass. Correctness comes
  from H (§2.3). It resets on a new serial or an erased log, like `DeliveryTransitionLedger.track`.

### 2.8 The chunk still running

v1 reports closed chunks only, so the host hears of a chunk on the first tick after the record that
follows it: 5–10 minutes after the chunk starts. A mutable report of the current chunk would cut that
to one tick (at most about 5 minutes). Its costs:

- **It must ride in every replacing batch until it is finalized.** Otherwise both hosts delete it,
  and Loop never brings a deleted dose back (#330). This can live in one place, `emitPumpEvents`,
  next to `inProgressBolusEvents()`, but a missed path silently deletes insulin.
- **Finalizing it takes a replacing batch.** Loop keeps the stored row over a non-replacing report
  with the same `raw` (#452). So every history pass while the pump and host disagree, which is all
  of Control-IQ, becomes a replacing batch carrying the live temp and the boluses.
- **It cannot be finalized early.** Its end is known, 300 s after its record, but a finalized dose
  that ends in the future would make Loop drop the app's next temp, which starts before that end
  (#354).
- **Every live command has to cut it first.** A temp, a cancel, a suspend or Control-IQ off is
  reported from the command, so the open chunk must end there, as `settleDeliveryTransition()` ends
  a pending transition.
- **It can only stand where the host holds no temp.** Two open temps break Loop, which drops the
  earlier one once the later one is finalized first.
- **Trio reads its current temp from `basalDeliveryState`.** That would have to show the chunk
  too, or Trio's current temp and its history disagree.
- **Churn:** Nightscout re-uploads the row on every update.

The lag matters only while the host doses on that IOB. Under Control-IQ the host makes no automatic
doses, though a manual bolus is computed from it. At hand-back the wait in §2.9 covers it. A running
temp the driver lost is phase 5's job, done live. So v1 ships without a mutable current chunk,
and it can be added later through `emitPumpEvents` if the phase 2 logs show the lag matters.

### 2.9 Handing back from Control-IQ

Today a sync completes before its history tick runs (`TandemPumpManager.swift:549-565`). At the
moment Control-IQ ends, the host doses on that sync, so the last minutes of Control-IQ would arrive
after the app's first temp. For Loop that loses them for good.

- When `useControlIQ` goes from true to false (in `configureControlIQMode`'s success path, or in
  `fetchControlIQStatus`), persist `controlIQEndedAt`.
- While it is set, `ensureCurrentPumpData` does not throttle, and `syncPumpData` waits as it does
  for a pending transition (`afterDeliveryTransitionIsReported`, generalised; bounded by
  `transitionHistoryWait`, 30 s).
  - It is cleared by a pass that started after it, read to the pump's end and reconciled through
    it. The last algorithm chunk is closed once the record after it is read, like any other.
    Control-IQ's own changes of state take effect at a cycle (§1.1), so the last chunk presumably
    runs its 300 s; a switch-off from the app is unobserved (Q2). The app's first temp is reported
    from its command, and the correction stops there (§2.6).
  - If the wait times out, the sync completes anyway, as it does for a pending transition, and the
    corrections go out with a later pass.
- A pass that finds Control-IQ's state in history differing from `useControlIQ` calls
  `fetchControlIQStatus` in the same command job. Today that status is read only every 24 hours or
  on the `controlIQInfo` qualifying event, so a missed event leaves the dosing guards wrong for up
  to a day.
- When Control-IQ starts while the driver still holds an app temp, the temp's completion record
  ends it (§2.5). That also closes #353's G07: a pump-side switch to Control-IQ leaves the app's
  temp running in the host.
- `verifyDeliveredBasalRate` returns early under Control-IQ (`TandemPumpManager+StateSync.swift:811`).
  It should compare `profileBasalRate` instead (Q6), so that `hasSyncedBasalRateSchedule` and the
  confirmed mismatch are current at hand-back and the app's first temp runs on a verified profile.

### 2.10 Rejected alternatives

- **Reporting Control-IQ basal only.** Superseded by the general comparison.
- **A temp ledger keyed by `tempRateId`, deciding ownership by origin** (#514's item 3). Comparing
  against H dedupes by construction and needs no per-origin rules (§2.3).
- **Reporting P everywhere, so history owns the basal timeline** (MinimedKit). That would fight the
  live path's reports, and Loop would drop most of it (§2.4, cycle timing). Reporting only the
  differences gives the host the same IOB, but for the cycle timing.
- **Building P from the exact-time records and the profile,** the previous revision of this plan.
  The pump delivers on its 5-minute cycle (§1.1): that model matched the pump's own total in under
  half of the intervals between `DailyBasal` records, the chunks in 97–98%. It also needed the
  profile's segment boundaries, which the pump does not record.
- **Converting history temps against the host's schedule.** The schedule is right only when it is
  the pump's profile, which is what #400 and #500 moved the live path away from. Each chunk carries
  the pump's own rate instead.

## 3. Phases

Each phase is one PR to `dev`. The driver change goes in with its CLAUDE.md update. Conformance work
goes in with a faketandem branch of the same name when it needs one.

| Phase | Scope | Host-visible change | Done when |
| --- | --- | --- | --- |
| **0a** | #482: one shared history-date helper (reconciler + `hostDate`), used for boluses and the emit floor | History bolus dates after a time change | G1, G3 and G4 markers flip and are removed |
| **0b** | `TrioDoseStoreOracle` brought up to Trio `dev` (§1.2), with a `getTempBasals`-style cut-off for an IOB check | Tests only | `DoseOracleTests` cover each rule. Every Trio-only marker is rechecked; those citing #329 may now pass unexpectedly, since nightscout/Trio#1300 stores finalized temps and cuts them off at `.basal` rows |
| **0c** | faketandem branch, §5 | Emulator only | Group H can stage a Control-IQ session |
| **1** | `PumpBasalTimeline` (chunks, and the cross-check against the exact-time records); `HistoryToDoseMapper` made bolus-only (its temp, `BasalRateChange`, suspend, resume and alarm branches go, with `scheduledBasalRate: { _ in 0 }`) | None | Unit tests |
| **2** | `ReportedBasalLedger`, H, `BasalReconciler`; differences and the cycle residual logged on every pass while `historyBackfill` is on | None | Unit tests. Then field logs from testers: no differences in normal operation, the expected ones under Control-IQ, and the cycle residual's size (Q9) |
| **3** | `basalHistoryReporting`; corrections where the host assumes its schedule; the held-temp actions; one batch per pass; hand-back; `useControlIQ` from history; `verifyDeliveredBasalRate` under Control-IQ | Behind the flag. **Fixes #213**, the #340 backstop, temps set on the pump's screen and resumed after an alarm suspend, IOB under a profile mismatch | Unit and manager tests; conformance H1–H10 |
| **4** | Corrections of rows the host already finalized (Trio) | Behind the flag | Manager tests; H5 extended |
| **5** (#340) | After an unanswered `SetTempRate`, read `CurrentBasalStatus` and `TempRateRequest` and record the temp if the pump runs it. On a `tempBasal` reading while a temp is held, a `TempRateResponse.startTime` that is not the held temp's start makes a pending transition: history ends the held temp and adopts the new one into `basalDose` | A live-path fix, not behind the flag | A5's #340 marker flips. Needs Q8 |

The flag:

- Title "History Basal Reporting".
- Description: checks the basal rates the pump delivered, from its history log, against what the
  app was told, and reports the difference to the app's insulin history: Control-IQ's basal
  changes, temp rates the app did not set or lost track of, and a pump profile that differs from
  the app's schedule. Only has any effect while History Backfill is on.

## 4. Tests

### 4.1 Unit (`TandemKitTests`)

- **`PumpBasalTimelineTests`.** Fixtures are built with each record's `buildCargo`, shaped like the
  capture hex already in `ControlIQCycleHistoryLogTests` and `BasalDeliveryHistoryLogTests`, and
  like the Mobi exports' patterns (§7.1): a temp replaced every cycle, 0% and 250% temps, a temp
  across a segment boundary, a suspend and resume, and under Control-IQ a CGM dropout (PCM 3 → 2 →
  3) and a suspend. Cases:
  - a chunk per 279 record, 300 s at `commandedRate`, with its kind;
  - a late record, a cycle without one, and a resume without one leave uncovered time; a resume
    with one starts a chunk;
  - the top chunk stays open until the next record or 300 s of log past it; a store gap keeps it
    open;
  - a suspend ends a chunk;
  - the cross-check: a temp at exactly `percent ×` the record's `profileBasalRate`, a stop and set
    in a record's second, a temp resumed after an alarm suspend, the source the PCM in force gives
    under Control-IQ; a record it does not predict stops corrections around it;
  - P's insulin against `DailyBasal` totals: exact, a short cycle after a temp change, and a failing
    stretch;
  - a clock change and a pump clock offset move chunks onto the phone's clock;
  - 0xFFFF gives no chunk.
- **`ReportedBasalLedgerTests`.** The fold matches Trio: a later row cuts off an earlier one;
  `.basal` markers; suspend and resume; a replacing batch purges unmentioned mutable rows; raw-value
  round trip; pruning; `trackingSince`.
- **`BasalReconcilerTests`.** Cases:
  - app temps, segment cuts and skew compensation produce nothing;
  - cycle timing produces nothing: a change inside a chunk, and a temp replaced within one cycle;
    the residual is measured;
  - the one-minute window around a record and the rate tolerance;
  - the `segmentChangeWindow` exemption;
  - Control-IQ cycles at the schedule's rate produce nothing, and the others differ;
  - a lost temp, a temp resumed after an alarm suspend, a pump profile off the schedule, and a held
    temp the pump ended;
  - a refused set after a stop produces nothing once the transitions pass has reported the stop;
  - suspended and uncovered time are not compared;
  - after its corrections are in the ledger, a second run finds nothing.
- **`BasalReconciliationReportingTests`,** at manager level through `StubPumpBluetooth` and
  `storeHistoryLogs`, like `HistoryDoseReportingTests`. Cases:
  - corrections go out once, ascending, immutable, with `deliveredUnits`, each ending at its
    chunk's end or the host's next change inside it;
  - nothing goes out twice, across a relaunch included;
  - one batch with the transitions pass (R1);
  - the held temp is ended or re-stated in a replacing batch with no extra `.basal` marker (R2, R4);
  - hand-back: the sync completes only after the last algorithm chunk is reported, plus the timeout
    and unreadable-history paths, and `ensureCurrentPumpData` does not throttle meanwhile;
  - with the flag off, differences are logged and nothing is reported.
- **State.** `TandemPumpManagerStateEqualityTests` and the raw-value round trip for the new fields
  (Harmonize's `EqualityComparesEveryStoredProperty` and `StateTypesAreEquatable`); feature flag
  tests; new strings through `String(localized:)`.
- **Harmonize `DriverMessagesHaveSerializationTests`.** 279, 2, 15, 11, 12, 81, 230, 309 and
  `TempRateRequest` already have tests. Reading 244 needs `AaEnableSettingChangeHistoryLogTests`
  from a capture first, since the baseline takes no additions.

### 4.2 Conformance group H, "Basal reconciliation" (`docs/conformance-test-plan.md`)

| ID | Scenario | Assert |
| --- | --- | --- |
| H1 | An app temp is running. Control-IQ is switched on and runs an hour with rates above and below the profile, with a sync every 5 minutes. Control-IQ is switched off, then the app sets a temp | The app temp ends at its completion record. There is one correction per 279 record whose rate differs from the schedule, at the pump's rate, the last ending at its chunk's end or at the app's first temp. The sync after the switch-off returns only after that. Loop counts every correction and its IOB over the hour matches `PumpTimeline`'s. Trio stores every correction |
| H2 | The radio is off for 2 h during Control-IQ, then on, then a sync | Every correction arrives in one ascending batch and Loop holds them all |
| H3 | Relaunch from `rawValue` during Control-IQ | Nothing is reported twice, and corrections after the relaunch carry on |
| H4 | A pump suspend and resume during Control-IQ | The algorithm chunk ends at the suspend, and the suspend, resume and corrections go in one batch |
| H5 | A5 with history reporting on (#340) | Once the temp the pump ran is in history, it is reported at its pump times and rate. Trio's IOB is right. Loop's is right only if that lands before the next app temp is finalized; phase 5 removes that race |
| H6 | Normal operation: app temps, cancels, a temp across a segment change, skew compensation from D5 | No difference is logged and nothing is reported |
| H7 | A temp set on the pump's screen (an X2) | Reported once its chunks close, with `wasProgrammedByPumpUI` |
| H8 | The pump's profile is not the app's schedule (#400) | Corrections at the pump's profile rate; IOB matches `PumpTimeline`; the existing mismatch alert still shows |
| H9 | An alarm suspend while an app temp runs, then a resume, with the temp resuming (§5) | The temp's chunks after the resume are reported, at its rate, until the app's next temp |
| H10 | A CGM dropout during Control-IQ (PCM 3 → 2 → 3) | The pump runs its profile while it lasts; nothing is reported for those chunks when the profile is the app's schedule |

`PumpTimeline` gains basal chunks built from the feed's `BasalDelivery` records, and its diff
compares the host's rows with them at each record, as §2.4 does.

## 5. faketandem companion work

1. `BasalDelivery` (279) records every 300 s of pump time, for every kind of delivery: source 0
   while suspended, 1 on profile, 2 during a temp (with `tempRate` = `percent × profileBasalRate`,
   exactly), 3 under Control-IQ. Also one at a resume after a suspended cycle, restarting the
   cadence.
2. Delivery on that cycle (§1.1): each cycle delivers 5 minutes at the rate in force at its record,
   and the reservoir follows it, while `CurrentBasalStatus` shows a new command at once.
3. A Control-IQ basal driver while `closed_loop_enabled` is set: algorithm rates scripted through
   the API, delivery arithmetic and `CurrentBasalStatus.currentBasalRate` following them, a 230 at
   the cycle where the CGM drops out (PCM 3 → 2, profile rate with source 1) or comes back, 3 → 0 →
   3 around a suspend, and the switch-on/switch-off records once Q2 settles which they are.
4. `DailyBasal` (81) records whose `dailyTotalBasal` grows by each cycle's insulin and whose
   `lastBasalRate` is the latest 279's rate, so the check in §2.4 runs in the harness.
5. The records the Mobi writes around app commands: `SetTempRateResponse` (309) with the temp's id,
   and `ControlIQPcmChange` (230) at suspend and resume.
6. `TempRateCompleted.timeLeft` in milliseconds, rounded to whole minutes, as the Mobi writes it.
   faketandem writes seconds today. The driver only tests it against 0, so nothing breaks, but the
   emulator should match.
7. An alarm suspend that leaves the running temp in force: no `TempRateCompleted` at the suspend,
   and the temp resumes with delivery, as the Mobi did (§7.1). faketandem's `SuspendDelivery` ends a
   running temp at every suspend today, and conformance F4 (an occlusion) relies on that; whether an
   occlusion ends the temp is Q11.
8. Nothing for phase 5. It reads `TempRateRequest`, which faketandem answers from state. It avoids
   `TempRateStatusRequest`, which would give the temp's id, because faketandem answers it with
   zeroes and there is no captured vector for its serialization test.

Until items 1 to 3 land, group H can stage history with `appendHistory(records:)`, as
`HistoryBackfillIntegrationTests` already does for 279. `docs/integration-harness.md` lists the gap
until then.

## 6. Docs

- CLAUDE.md, "History backfill and dose reporting": the reconciliation, the ledger and hand-back.
  Phase 3 rewrites "Temp rates the app did not set are still not reported".
- CLAUDE.md, "Pump event batches": R1, R2 and R4. "Therapy command validation": the mismatch check
  under Control-IQ, and that the pump applies a temp at its next 5-minute cycle (§1.1), with phase 1.
- `HistoryLogSyncIdentifier`'s doc comment: the new scheme, and which reports use which identity.
- `docs/conformance-test-plan.md` (group H), `docs/integration-harness.md` (gaps) and
  `docs/ARCHITECTURE_ANALYSIS.md` ("History").

## 7. Open questions

### 7.1 What the Mobi exports showed

**On 7.9.0.1, Control-IQ off.** Two consecutive exports from one Mobi with Trio closed-looping:
10,000 records over 43 hours, then 30,000 over 6 days, with one record missing. Trio replaced its
temp in most 5-minute intervals. They hold 1,439 temps, 12 suspends (10 by the app, 2 by cartridge
alarms) and one change of the pump's clock.

- **The pump delivers on a 5-minute cycle** (§1.1). One 300 s chunk at each 279's `commandedRate`
  reproduced `dailyTotalBasal` exactly in 97–98% of the intervals between `DailyBasal` records, and
  every stretch of an hour or more to 0.01 U but those holding one of four short cycles.
  `lastBasalRate` was the latest 279's rate in 1,694 of 1,695 records. Switching the rate at the
  temp records matched under half. 9 in 10 temps began delivering more than a minute after they were
  set, and 9 were never delivered. Counting every temp from when it was set, as the host does, came
  to −0.1% and +0.4% of what the pump delivered over the two exports.
- **Q1, answered.** 279 comes at each cycle, usually 30 s after its `ControlIQCycle`. About 1% are
  up to 4 minutes late, and the time before a late one delivered nothing; once in six days a cycle
  had none and delivered nothing. One is written at a resume after a suspend that lasted through a
  cycle (11 of 11), and the cadence restarts from it. A resume within the suspend's own cycle had
  none (1 of 1), and delivery restarted at the next cycle. None at the app's suspends (10 of 10),
  and one at one of the two alarm suspends.
- **The exact-time records explain every 279.** Read in sequence order, with each record's
  `profileBasalRate`, records 2, 15, 11 and 12 predict the source and rate of all 2,279 279 records,
  across the clock change. A temp's rate is exactly `percent × profileBasalRate` (2,218 samples, 70
  of them where rounding to 0.01 U/h would show).
- **A temp survives an alarm suspend.** Both alarm suspends came during an app temp at 0%. Neither
  wrote a `TempRateCompleted`, and the first 279 after each resume showed the temp running; the app
  replaced it within 2½ minutes. The app stops its own temp before it suspends (10 of 10), so its
  suspends cannot show this. See §7.3.
- **Q3.** No `BasalRateChange` at all on 7.9. A segment boundary leaves no record, and the next 279
  shows the new rate.
- **`timeLeft`** is milliseconds, always whole minutes. No temp ran to its end, so `timeLeft` 0 at
  a natural end is still unobserved.
- **`SetTempRateResponse` (309)** is logged for every app temp: one per activation, with the same id
  and status 0, right after a `ControlRequest` (290) for `SetTempRate` (opcode 164); a stop is a 290
  with opcode 166. Twice the pump refused a `SetTempRate` (status 1, `tempRateId` 0) right after the
  app's stop had ended the running temp, and ran its profile until the app's next temp. The driver
  holds the stopped temp until its next reading, which the transitions pass then dates from history.
- **`ControlIQPcmChange` (230)** is written at every suspend (PCM 1 → 0) and resume (0 → 1).

**On 7.7.0.1, Control-IQ on.** An older export from a Mobi running Tandem's Control-IQ with a CGM:
24,864 consecutive records over 8 days, with no temps and 7 suspends, all with reason 0.

- **The same 5-minute cycle.** The chunks matched `dailyTotalBasal` to the last digit over every
  stretch of an hour or more (785 of 785), and exactly in 98% of the intervals between `DailyBasal`
  records, the rest being credit timing. `lastBasalRate` was the latest 279's rate in 1,037 of
  1,039 records. 279 came about 30 s after its cycle's 227, 1% of them late, none missing.
- **Q7, answered.** In closed loop (PCM 3) the source is 3, with `algorithmRate` equal to
  `commandedRate`. When the CGM is unavailable Control-IQ moves to PCM 2 and the pump runs its
  profile, source 1 at `profileBasalRate` (19 times, from 5 minutes to over an hour). Suspended is
  PCM 0 and source 0. Each change is a 230 in the same second as the cycle's 227, and that cycle's
  279, 30 s later, carries the new rate.
- **Q5, answered for this pump.** The highest algorithm rate was 90% of the pump's max basal limit
  (the `maxbasalrate` that `BasalRateChange` carries).
- **Q6, answered for history.** Under Control-IQ, 279's `profileBasalRate` follows the profile
  schedule (one value per 10-minute slot of the day across all 8 days), and `BasalRateChange`'s
  `basebasalrate` matches it. `CurrentBasalStatus` was not captured.
- **Control-IQ ran exactly the profile rate in 52% of its cycles,** so the comparison would correct
  about half of them: about 130 a day here.
- **`BasalRateChange` (3) is written on this firmware:** changetype 1 at every rate change (1,004),
  within a second before that cycle's 279 and with the same rates; 16 at a suspend; 32 or 33 at a
  resume. Where 7.9 wrote none, 7.7 repeats the 279.
- **At a resume** (7 of 7) the pump writes the resume, a 230 (PCM 0 → 3), a `BasalRateChange` and a
  279 in the same second.
- **Not answerable here:** nobody switched Control-IQ on or off (no 244 record), and no temp ran
  (Q4).

### 7.2 Still open

- **Q2.** When Control-IQ is switched on or off, what does the pump write, and when does the rate
  change? Its own changes of state are written at the cycle and take effect at that cycle's 279
  (§7.1), so a switch likely does the same. The record is likely a 230 between PCM 1 and 3, or a
  244. It matters most for knowing when Control-IQ ended (§2.9).
- **Q4.** Can a temp rate run under Control-IQ (source 4)? If so, what do 2, 15 and 279 show?
- **Q6.** Under Control-IQ, is `CurrentBasalStatus.profileBasalRate` the profile rate, as 279's is
  (§7.1)?
- **Q8** (phase 5). What unit is `TempRateResponse.duration`? faketandem guesses seconds.
- **Q9** (the maintainer, after phase 2). Should Trio be sent the cycle timing (§2.4)?
- **Q10.** Does an X2 deliver on the same 5-minute cycle? Only Mobis, on 7.7 and 7.9, have been
  observed.
- **Q11.** Which other suspends leave the running temp in force: an occlusion, one from Tandem's
  app or an X2's screen, other alarms? Only cartridge alarms during a 0% temp have been seen.

Pump logs stay out of the repository. Fixtures are rebuilt with `buildCargo` from what the logs
show, with no capture copied in, except for a single record a serialization test needs, and then
only with the maintainer's agreement and its time and sequence number changed.

### 7.3 Outside #514: the temp an alarm suspend leaves running

When the driver has seen an alarm suspend, it reports the resume as a `.resume`
(`reportTransition`), and then ignores the temp the pump resumed: once the host holds a resume,
`observeDeliveryState` leaves a `tempBasal` reading alone ("A temp rate the app did not set is not
reported"). The host counts its schedule while the pump runs the old temp for the rest of its
duration, up to 2 hours for one of Trio's 0% temps, until the host sets another. A host that wants
its scheduled rate and believes no temp runs sends nothing: Loop, and Trio when it skips neutral
temps. That is a delivery error, not just a reporting one. Phase 3 reports the delivered chunks
after the fact (H9), but the fix belongs in the live path: on that reading, adopt the temp back into
`basalDose` and report it from the resume, or stop it. It needs its own issue, which should also
revisit conformance F4 and faketandem item 7 (§5).

## 8. Risks

- **Misreading the pump's records gives wrong IOB.** Phase 2 runs the comparison in the field,
  logging only, before any correction reaches a host. The open questions are settled from real
  exports. P is checked against the exact-time records and the pump's own `DailyBasal` total before
  a stretch is corrected.
- **P rests on the pump's own accounting.** The chunks reproduce the pump's basal total and its
  `lastBasalRate`, but the motor's timing is not in the history log. The pump's total is the best
  evidence there is.
- **Cycle timing stays in the host's IOB** (§2.4), within about 6 minutes of the highest temp rate
  in use, either way, unless Q9 decides otherwise.
- **H models Trio.** Loop may have dropped a row the driver counts as told (IDS window), and that is
  never corrected for Loop. A batch held for a missing delegate and later dropped (#342) is also
  counted as told.
- **Trio's 0.05 U rounding** of each 5-minute chunk hides small Control-IQ adjustments, as it does
  for Trio's own temps.
- **Loop's IDS window.** R1–R3 and hand-back cover the driver's side. A gap given up on, and a #340
  temp reported after the next app temp is finalized, are the known residuals.
- **Event volume** under Control-IQ is one correction per cycle off the schedule: about 130 a day
  in the 7.7 export, at most 288, about what Trio's own loop writes.
