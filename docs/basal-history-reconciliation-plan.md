# Basal history reconciliation: implementation plan

Plan for #514, written against `dev` at 1b7d89b.

The driver reads the basal rates the pump actually commanded from its history log, compares them
with what it told the host, and reports the difference. That fixes #213 (Control-IQ's basal changes
never reach the host) and gives #340 an after-the-fact backstop. It also catches anything else that
leaves the host believing a rate the pump did not run: a temp the driver lost track of, a temp set
on the pump's screen, or a pump profile that differs from the app's schedule. #340's immediate fix
is phase 5 below and stays tracked in #340.

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

| Record | Fields used | When it is written | How sure we are |
| --- | --- | --- | --- |
| `BasalDelivery` (279) | `commandedRateSource`, `commandedRate`, `profileBasalRate`, `algorithmRate`, `tempRate`, all mU/h; 0xFFFF means n/a | Every 5 min, Control-IQ on or off | Sources 0, 1 and 2 confirmed on a Mobi with Control-IQ off; 3 seen in X2 and Mobi Control-IQ captures; 4 (temp rate and algorithm) never seen |
| `TempRateActivated` (2), `TempRateCompleted` (15) | `percent`, `durationMilliseconds`, `tempRateId`; `tempRateId`, `timeLeft` | When the temp starts, and when it ends, is stopped or is replaced | Used today by `reportHistoryDeliveryTransitions` |
| `BasalRateChange` (3) | `commandBasalRate`, `baseBasalRate` (U/h floats), `changeTypeId` | When a timed segment starts, a profile changes, a temp starts or ends, or the pump suspends or resumes | Only pumpX2's X2 fixtures. Tidepool's Tandem uploader builds its basal records from it ("used to create all other basals", its checklist says). Not confirmed on a Mobi (Q3) |
| `PumpingSuspended` (11), `PumpingResumed` (12) | — | When delivery stops and restarts | Used today |
| `AaEnableSettingChange` (244), `ControlIQPcmChange` (230) | `enabled`; `currentPcm` | Presumably when Control-IQ is switched on or off | Unconfirmed (Q2). 244 has no serialization test and pumpX2 has no vector for it |

Control-IQ's rate changes exist only in 279, which is a 5-minute sample of the commanded rate, so a
Control-IQ interval runs from one record to the next. The `ControlIQCycle` record (227) that comes
before each one is not used. For temp rates, the pump's own absolute numbers (279's `tempRate`, 3's
`commandBasalRate`) beat `percent × a profile rate`, because the pump's rounding is unknown
(`TandemPumpManager.tempBasalReadbackMatches`).

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

- **P, the pump's timeline:** what the pump commanded, built from history by a pure
  `PumpBasalTimeline`.
- **H, the host's timeline:** what the host was told, from a ledger the driver keeps of its own
  reports (`ReportedBasalLedger`). Where the driver reported nothing, it is the host's schedule.

A pure `BasalReconciler` compares the two over closed, contiguous stretches of the store.
`TandemPumpManager+BasalReconciliation.swift` runs it on every history pass and acts on the
differences.

### 2.2 P: the rate the pump commanded

P is a sequence of pieces, each starting at a change point. Every record is dated through the
shared `phoneDate(of:)` from phase 0a (`HistoryTimestampReconciler.utcDate`, then
`hostDate(forPumpDate:)`).

| Change point | Rate from there |
| --- | --- |
| 279 | `commandedRate`. Its source gives the kind: algorithm (3, 4), temp (2), profile (1), suspended (0). 0xFFFF: unknown, no piece |
| `TempRateActivated` | The temp's absolute rate: `BasalRateChange` `commandBasalRate` at the same time (Q3); else the next 279's `tempRate`, if nothing changes in between; else `percent ×` the last 279's `profileBasalRate` |
| `TempRateCompleted` | The profile rate (the last 279's `profileBasalRate`) |
| `PumpingSuspended` / `PumpingResumed` | 0 / the profile rate |
| `BasalRateChange` (if the pump writes it) | `commandBasalRate`, at its exact time |
| The record that ends Control-IQ, if there is one (Q2) | The profile rate |

- **Profile segment boundaries** go where the pump's profile changes. That is the host schedule on
  the pump's clock (`pumpSegmentChanges`) while the profile is verified (`hasSyncedBasalRateSchedule`
  and no confirmed mismatch); otherwise a `BasalRateChange` timed-segment record (Q3); otherwise
  the next 279, at most a cycle late. A temp running across a boundary is rescaled there, as the
  pump does.
- **One piece per 279 record.** Under Control-IQ every record starts its own piece, identified by
  its own sequence number. Merging equal-rate records would make a piece's identity depend on the
  record before the run (the backward walk may not have read it yet) and on its last record (not
  known until the rate changes), so it would change identity or stay open indefinitely.
- **Closed pieces only.** A piece is used once the change point that ends it has been read and
  nothing between the two is missing from the store (`HistoryLogStore.missingRanges`). The open
  piece at the top of the log waits for the next pass (§2.8).

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
- Skew compensation temps and a temp stopped after a mismatched readback need no special case. The
  first delivers what the host already counts, and the second lasts seconds, under the 1-minute
  floor (§2.4).

### 2.4 Comparing

- Rates are compared in milliunits, with a tolerance of 10 mU/h, one pump step, as in
  `tempBasalReadbackMatches`.
- Boundaries within a minute (`transitionMatchTolerance`) of each other are the same change: a pump
  record and the phone's report of the same command differ by seconds.
- Differences shorter than a minute are ignored.
- Not compared:
  - suspended time on either side, which the transitions pass owns;
  - store gaps;
  - anything before the floor, `max(firstSeenFloor, now − 24 h)` on phone dates, or ahead of the
    phone.
- Exempt: the over-count the driver makes on purpose inside `segmentChangeWindow` (#500). There the
  host is told the request while the pump runs the lower rate until the change.

What should show up as a difference: Control-IQ (every cycle); a temp the driver lost (#340); a temp
set on the pump's screen; a pump profile that is not the app's schedule (#400); the pump clock's
segments around a host segment change; a held temp the pump ended without any reading noticing.
Normal operation should produce none, and phase 2 checks exactly that in the field before anything
is reported.

### 2.5 Acting on a difference

| H at that time comes from | With `basalHistoryReporting` on |
| --- | --- |
| Nothing: the host assumes its schedule (no row, a `.basal` marker, an ended temp) | Report P's pieces there as closed `.tempBasal` corrections |
| The temp the driver holds, still mutable | Act through the live path. If history shows that temp completed, finalize it at that record with `reportTransition(_:tempRateEnd:events:)`; what follows is then compared against the schedule. If the pump still runs it at another rate, re-state it from where they diverge, the way `splitAtSegmentChanges` cuts a temp: the finished part at the old rate, and a mutable continuation at the pump's rate |
| A row the host already finalized | Phase 4, Trio only. Report P from where they diverge (at least a second after the row's start, R4) through the row's end; the later row cuts the old one off, and the rest of it is re-asserted at P's rates. Loop drops these through its IDS window, harmlessly |
| A suspend or resume | Left to the transitions pass, and logged |

With the flag off, each difference is logged once (interval, P, H, kind, and the action it would
take) and nothing is reported. That log is the sanity check in the field, and it is phase 2's
deliverable.

### 2.6 Identities and fields

- **Identity:** a new `HistoryLogSyncIdentifier` scheme, `basalPiece = 4`. The identifier is the
  sequence number of the record that starts the piece. When a host change point or a profile
  boundary splits a piece, a part number goes in the top 8 bits. Sequence numbers are around 2
  million after years of use, so 2^24 is decades away; a pump past it gets no corrections and a log
  line. Adding a scheme keeps the frozen 10-byte format.
- **Fields:** `.tempBasal`, `deliveredUnits` (R5), and `insulinType`. `automatic` is true for
  algorithm pieces and the app's own temps, and false otherwise. `wasProgrammedByPumpUI` is true
  for algorithm pieces (as history boluses do) and for temps the app did not set. The title is
  "Control-IQ Basal" for algorithm pieces and "Temp Basal" otherwise.

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
  since Trio drops it (Q5).
- A persisted `reconciledThrough` sequence number only bounds the work per pass. Correctness comes
  from H (§2.3). It resets on a new serial or an erased log, like `DeliveryTransitionLedger.track`.

### 2.8 The interval still running

v1 reports closed pieces only, so the host hears about an interval one tick after the record that
ends it is written: at most about 10 minutes behind, typically 5–10. A mutable report of the
current interval would cut that to one tick (at most about 5 minutes). Its costs:

- **It must ride in every replacing batch until it is finalized.** Otherwise both hosts delete it,
  and Loop never brings a deleted dose back (#330). This can live in one place, `emitPumpEvents`,
  next to `inProgressBolusEvents()`, but a missed path silently deletes insulin.
- **Finalizing it takes a replacing batch.** Loop keeps the stored row over a non-replacing report
  with the same `raw` (#452). So every history pass while the pump and host disagree, which is all
  of Control-IQ, becomes a replacing batch carrying the live temp and the boluses.
- **Its end is a guess, one cycle.** Every live command that changes delivery (a temp, a cancel, a
  suspend, Control-IQ off) has to close it first, as `settleDeliveryTransition()` does for pending
  transitions.
- **It can only stand where the host holds no temp.** Two open temps break Loop, which drops the
  earlier one once the later one is finalized first.
- **Trio reads its current temp from `basalDeliveryState`.** That would have to show the interval
  too, or Trio's current temp and its history disagree.
- **Churn:** Nightscout re-uploads the row on every update.

The lag matters only while the host doses on that IOB. Under Control-IQ the host makes no automatic
doses, though a manual bolus is computed from it. At hand-back the wait in §2.9 covers it. A running
temp the driver lost is phase 5's job, done live. So v1 ships without a mutable current interval,
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
    it. The last algorithm piece ends at the earliest of the next 279, the record that ends
    Control-IQ, and `controlIQEndedAt`.
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
  live path's reports. Reporting only the differences gives the host the same IOB.
- **Converting history temps against the host's schedule.** The schedule is right only when it is
  the pump's profile, which is what #400 and #500 moved the live path away from. It is used only to
  place segment boundaries, and only while the profile is verified.

## 3. Phases

Each phase is one PR to `dev`. The driver change goes in with its CLAUDE.md update. Conformance work
goes in with a faketandem branch of the same name when it needs one.

| Phase | Scope | Host-visible change | Done when |
| --- | --- | --- | --- |
| **0a** | #482: one shared history-date helper (reconciler + `hostDate`), used for boluses and the emit floor | History bolus dates after a time change | G1, G3 and G4 markers flip and are removed |
| **0b** | `TrioDoseStoreOracle` brought up to Trio `dev` (§1.2), with a `getTempBasals`-style cut-off for an IOB check | Tests only | `DoseOracleTests` cover each rule. Every Trio-only marker is rechecked; those citing #329 may now pass unexpectedly, since nightscout/Trio#1300 stores finalized temps and cuts them off at `.basal` rows |
| **0c** | faketandem branch, §5 | Emulator only | Group H can stage a Control-IQ session |
| **1** | `PumpBasalTimeline`; `HistoryToDoseMapper` made bolus-only (its temp, `BasalRateChange`, suspend, resume and alarm branches go, with `scheduledBasalRate: { _ in 0 }`) | None | Unit tests |
| **2** | `ReportedBasalLedger`, H, `BasalReconciler`; differences logged on every pass while `historyBackfill` is on | None | Unit tests. Then field logs from testers: no differences in normal operation, and the expected ones under Control-IQ |
| **3** | `basalHistoryReporting`; corrections where the host assumes its schedule; the held-temp actions; one batch per pass; hand-back; `useControlIQ` from history; `verifyDeliveredBasalRate` under Control-IQ | Behind the flag. **Fixes #213**, the #340 backstop, temps set on the pump's screen, IOB under a profile mismatch | Unit and manager tests; conformance H1–H8 |
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
  capture hex already in `ControlIQCycleHistoryLogTests` and `BasalDeliveryHistoryLogTests`. Cases:
  - a piece per 279 record, at `commandedRate`, with its kind;
  - the top piece stays open;
  - a store gap keeps pieces open;
  - a suspend ends a piece;
  - the temp rate source order;
  - segment boundaries with and without a verified profile;
  - a clock change and a pump clock offset move pieces onto the phone's clock;
  - 0xFFFF gives no piece.
- **`ReportedBasalLedgerTests`.** The fold matches Trio: a later row cuts off an earlier one;
  `.basal` markers; suspend and resume; a replacing batch purges unmentioned mutable rows; raw-value
  round trip; pruning; `trackingSince`.
- **`BasalReconcilerTests`.** Cases:
  - app temps, segment cuts and skew compensation produce nothing;
  - the boundary and rate tolerances hold;
  - the `segmentChangeWindow` exemption;
  - Control-IQ differs every cycle;
  - a lost temp, a pump profile off the schedule, and a held temp the pump ended;
  - suspended time is not compared;
  - after its corrections are in the ledger, a second run finds nothing.
- **`BasalReconciliationReportingTests`,** at manager level through `StubPumpBluetooth` and
  `storeHistoryLogs`, like `HistoryDoseReportingTests`. Cases:
  - corrections go out once, ascending, immutable, with `deliveredUnits`;
  - nothing goes out twice, across a relaunch included;
  - one batch with the transitions pass (R1);
  - the held temp is ended or re-stated in a replacing batch with no extra `.basal` marker (R2, R4);
  - hand-back: the sync completes only after the last algorithm piece is reported, plus the timeout
    and unreadable-history paths, and `ensureCurrentPumpData` does not throttle meanwhile;
  - with the flag off, differences are logged and nothing is reported.
- **State.** `TandemPumpManagerStateEqualityTests` and the raw-value round trip for the new fields
  (Harmonize's `EqualityComparesEveryStoredProperty` and `StateTypesAreEquatable`); feature flag
  tests; new strings through `String(localized:)`.
- **Harmonize `DriverMessagesHaveSerializationTests`.** 279, 3, 230, 2, 15 and `TempRateRequest`
  already have tests. Reading 244 needs `AaEnableSettingChangeHistoryLogTests` from a capture first,
  since the baseline takes no additions.

### 4.2 Conformance group H, "Basal reconciliation" (`docs/conformance-test-plan.md`)

| ID | Scenario | Assert |
| --- | --- | --- |
| H1 | An app temp is running. Control-IQ is switched on and runs an hour with rates above and below the profile, with a sync every 5 minutes. Control-IQ is switched off, then the app sets a temp | The app temp ends at its completion record. There is one correction per 279 record whose rate differs from the schedule, at the pump's rate, the last ending at Control-IQ's end. The sync after the switch-off returns only after that. Loop counts every correction and its IOB over the hour matches `PumpTimeline`'s. Trio stores every correction |
| H2 | The radio is off for 2 h during Control-IQ, then on, then a sync | Every correction arrives in one ascending batch and Loop holds them all |
| H3 | Relaunch from `rawValue` during Control-IQ | Nothing is reported twice, and corrections after the relaunch carry on |
| H4 | A pump suspend and resume during Control-IQ | The algorithm piece ends at the suspend, and the suspend, resume and corrections go in one batch |
| H5 | A5 with history reporting on (#340) | Once the temp the pump ran is in history, it is reported at its pump times and rate. Trio's IOB is right. Loop's is right only if that lands before the next app temp is finalized; phase 5 removes that race |
| H6 | Normal operation: app temps, cancels, a temp across a segment change, skew compensation from D5 | No difference is logged and nothing is reported |
| H7 | A temp set on the pump's screen (an X2) | Reported once its pieces close, with `wasProgrammedByPumpUI` |
| H8 | The pump's profile is not the app's schedule (#400) | Corrections at the pump's profile rate; IOB matches `PumpTimeline`; the existing mismatch alert still shows |

`PumpTimeline` gains basal pieces built from the feed's `BasalDelivery` records, and its diff
matches host temp rows against them.

## 5. faketandem companion work

1. `BasalDelivery` (279) records every 5 minutes of pump time, for every kind of delivery: source 0
   while suspended, 1 on profile, 2 during a temp (with `tempRate`), 3 under Control-IQ.
2. A Control-IQ basal driver while `closed_loop_enabled` is set: algorithm rates scripted through
   the API, delivery arithmetic and `CurrentBasalStatus.currentBasalRate` following them, and the
   switch-on/switch-off records once Q2 settles which they are.
3. `BasalRateChange` (3) records at temp start and end, segment changes, suspend and resume, once Q3
   is confirmed.
4. Nothing for phase 5. It reads `TempRateRequest`, which faketandem answers from state. It avoids
   `TempRateStatusRequest`, which would give the temp's id, because faketandem answers it with
   zeroes and there is no captured vector for its serialization test.

Until items 1 and 2 land, group H can stage history with `appendHistory(records:)`, as
`HistoryBackfillIntegrationTests` already does for 279. `docs/integration-harness.md` lists the gap
until then.

## 6. Docs

- CLAUDE.md, "History backfill and dose reporting": the reconciliation, the ledger and hand-back.
  Phase 3 rewrites "Temp rates the app did not set are still not reported".
- CLAUDE.md, "Pump event batches": R1, R2 and R4. "Therapy command validation": the mismatch check
  under Control-IQ.
- `HistoryLogSyncIdentifier`'s doc comment: the new scheme, and which reports use which identity.
- `docs/conformance-test-plan.md` (group H), `docs/integration-harness.md` (gaps) and
  `docs/ARCHITECTURE_ANALYSIS.md` ("History").

## 7. Open questions

To answer from the maintainer's pump history exports:

- **Q1.** Is 279 written on a fixed 5-minute cadence, or also at events? This sets how far apart two
  records can be before the piece between them counts as a gap.
- **Q2.** When Control-IQ is switched on or off, does the pump write a record at that moment (244,
  230, or a 279 straight away)? If so, the last algorithm piece ends exactly there. If not, it ends
  at the next 5-minute record, up to 5 minutes late, unless the app made the switch and so knows the
  time.
- **Q3.** On a Mobi, does every temp start and end, and every segment boundary during a temp, write
  a `BasalRateChange` carrying the absolute rate?
- **Q4.** Can a temp rate run under Control-IQ (source 4)? If so, what do 2, 15 and 279 show?
- **Q5.** Does Control-IQ stay within the pump's max basal limit? Trio drops anything above its
  `maxBasal`.
- **Q6.** Under Control-IQ, is `CurrentBasalStatus.profileBasalRate` still the profile rate?
- **Q7.** With no CGM, which 279 source does Control-IQ write?
- **Q8** (phase 5). What unit is `TempRateResponse.duration`? faketandem guesses seconds.

Pump logs stay out of the repository. Fixtures are rebuilt with `buildCargo` from what the logs
show, with no capture copied in, except for a single record a serialization test needs, and then
only with the maintainer's agreement and its time and sequence number changed.

## 8. Risks

- **Misreading the pump's records gives wrong IOB.** Phase 2 runs the comparison in the field,
  logging only, before any correction reaches a host, and Q1–Q7 are settled from real exports.
- **Segment boundaries are a cycle late without a verified profile or `BasalRateChange` records.**
  Around each boundary that produces a small correction, which is wrong by up to one cycle × Δrate.
- **H models Trio.** Loop may have dropped a row the driver counts as told (IDS window), and that is
  never corrected for Loop. A batch held for a missing delegate and later dropped (#342) is also
  counted as told.
- **Trio's 0.05 U rounding** of each 5-minute piece hides small Control-IQ adjustments, as it does
  for Trio's own temps.
- **Loop's IDS window.** R1–R3 and hand-back cover the driver's side. A gap given up on, and a #340
  temp reported after the next app temp is finalized, are the known residuals.
- **Event volume** is up to 288 corrections a day under Control-IQ, about what Trio's own loop
  writes.
