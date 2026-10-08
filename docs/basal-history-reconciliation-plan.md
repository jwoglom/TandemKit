# Basal history reconciliation: implementation plan

Plan for #514, against `dev` at 1b7d89b.

Read the basal the pump delivered from its history log (P), compare it cycle by cycle with what the
driver told the host (H), and report the differences. Fixes #213 (Control-IQ basal never reaches the
host) and backstops #340. Also covers a temp set on the pump, a temp the pump resumed after an alarm
suspend, and a pump profile that differs from the app's schedule.

Decided by the maintainer:

- A new `basalHistoryReporting` flag (default off) gates every report. The comparison runs and logs
  whenever `historyBackfill` is on.
- At most one correction per `BasalDelivery` (279) record.
- The check is general, not Control-IQ-only.
- No warning when Control-IQ is switched on with reporting off.
- `profileBasalRate` is always the pump's profile rate. A temp can run under Control-IQ only on
  newer firmware.

## 1. Pump facts

Established from Mobi history exports (7.9.0.1 with Control-IQ off, 7.7.0.1 with it on).

- **Basal is delivered in 5-minute cycles.** At each cycle the pump writes a 279 and delivers 300 s
  at that record's `commandedRate`. `DailyBasal.dailyTotalBasal` grows by exactly that, about 10 s
  after the 279, and `DailyBasal.lastBasalRate` is the latest 279's rate.
- **A change takes effect at the next 279**, 0–5 minutes later: a temp's start or end, a profile
  segment boundary, a Control-IQ state change. A temp set and replaced between two 279s is never
  delivered.
- **279 timing:** about 30 s after the cycle's `ControlIQCycle` (227). About 1% are up to 4 minutes
  late; rarely a cycle has none. Nothing is delivered before a late 279 or in a cycle without one.
  A resume after a suspend that spans a cycle writes a 279, and the cadence restarts from it. A
  resume within the suspend's own cycle writes none, and delivery restarts at the next cycle. A
  suspend does not take back the cycle under way.
- **Short cycles:** rarely a cycle delivers less than its 279 says, when a temp change or bolus
  starts within 20 s after it.
- **279 fields** (mU/h, 0xFFFF = n/a): `commandedRateSource` 0 suspended, 1 profile, 2 temp,
  3 Control-IQ, 4 temp under Control-IQ (newer firmware). With source 2, `commandedRate` is exactly
  `percent × profileBasalRate`, not rounded to 0.01 U/h.
- **`ControlIQPcmChange` (230) `currentPcm`:** 1 Control-IQ off, 3 closed loop, 2 Control-IQ on
  without a CGM (the pump runs its profile, source 1), 0 suspended. Written at each suspend and
  resume, and at the cycle where the CGM is lost or comes back.
- **Temps:** `TempRateActivated` (2) and `TempRateCompleted` (15) give command times and
  `tempRateId`; `timeLeft` is in milliseconds. `SetTempRateResponse` (309) is written for every temp
  set over Bluetooth, with its `tempRateId` (status 1 with id 0 is a refusal).
- **Suspends:** an alarm suspend (reason 1) can leave the running temp in force, with no
  `TempRateCompleted`, and the temp runs again after the resume. The driver stops its temp before
  its own suspends.
- **Not used:** `BasalRateChange` (3, written by 7.7 only, a copy of the 279), `ControlIQCycle`
  (227), `AaEnableSettingChange` (244).

## 2. Host constraints

**Trio** (`dev` since nightscout/Trio#1300):

- Only `.tempBasal` rows carry insulin; `.basal` is a zero-length scheduled row. Report corrections
  as `.tempBasal`.
- `IobHistory.getTempBasals` sorts rows by timestamp and cuts each at the next row's timestamp, so a
  later row corrects an earlier one whatever the arrival order. Two rows with the same timestamp
  leave one zero-length.
- Rows match by `syncIdentifier`, then `(timestamp, type, isScheduledBasal)`. A finalized row never
  changes. A replacing batch deletes every mutable row it does not mention.
- `DeviceDataManager` drops a temp above `pumpSettings.maxBasal`.
- The current temp comes from `basalDeliveryState`.

**Loop:**

- A non-bolus dose counts only if it starts at or after `lastImmutableBasalEndDate` (#354).
- An immutable temp without `deliveredUnits` counts in 0.05 U steps.
- A replacing batch deletes omitted mutable doses. A non-replacing batch cannot finalize a mutable
  dose whose `raw` changed (#452).

`TrioDoseStoreOracle` predates nightscout/Trio#1300: it skips temps carrying `deliveredUnits` and
dedupes on `(date, type)`. Phase 0b fixes it.

**Rules:**

- **R1.** A history pass emits all its non-bolus events (corrections, suspends, resumes, temp ends)
  in one batch, ascending.
- **R2.** A pass that ends or re-states the held mutable temp does it in a replacing batch with
  everything after it. Nothing reported may start after a held mutable temp's start while it is
  open.
- **R3.** Anything the host needs before it doses is reported before the sync completes, as
  `afterDeliveryTransitionIsReported` does.
- **R4.** A correction never starts in the same second as an existing host row. To override a row it
  starts at least 1 s after it.
- **R5.** A correction carries `deliveredUnits` (rate × duration, to 0.001 U), an absolute rate, and
  an identity that never changes.

## 3. Design

### 3.1 P: `PumpBasalTimeline` (pure)

- **One chunk per 279:** from the record, at `commandedRate`, for 300 s, ending sooner at the next
  279 or a suspend. Kind from the source: algorithm (3, 4), temp (2), profile (1), suspended (0).
  0xFFFF: no chunk. A temp chunk carries the `tempRateId` of the temp in force.
- **Uncovered time** (a late or missing 279, a resume without one) delivered nothing and is not
  compared.
- **Dates** go through phase 0a's shared `phoneDate(of:)` (`HistoryTimestampReconciler.utcDate`,
  then `hostDate(forPumpDate:)`).
- **Closed chunks only:** a chunk is used once the next record (a 279 or a suspend) has been read,
  or the log has been read 300 s past it, with no `HistoryLogStore.missingRanges` gap in between.
- **Cross-check.** A 279 that fails it is logged, and its chunk and the chunks either side are not
  corrected.
  - Source 3 or 4 passes unless the PCM in force (last 230) is 1 or 0.
  - Any other 279: replay 2, 15, 11 and 12 in sequence order, using the 279's own
    `profileBasalRate`. Expect (0, 0) while suspended; (2, `percent × profileBasalRate`) while a
    temp is active (activated, not completed, within its duration); (1, `profileBasalRate`)
    otherwise. A temp with no `TempRateCompleted` stays active across a suspend.
- **`DailyBasal` check.** Take a stretch of at least an hour within one pump day, between two
  `DailyBasal` records each written at least 60 s after its latest 279. The chunks' insulin, with a
  chunk cut by a suspend counted for its full 300 s, must equal the change in `dailyTotalBasal` to
  within 0.01 U. A shortfall is allowed if the stretch holds a chunk with a temp change or bolus
  within 20 s after its 279. A failing stretch is logged and not corrected.

### 3.2 H: `ReportedBasalLedger`

- New, persisted in `TandemPumpManagerState`, modelled on `BolusReportLedger`.
- Fed in `emitPumpEvents(_:replacePendingEvents:)` with every non-bolus event the driver reports,
  corrections included: temp rows (`raw`, start, end, rate, mutable, `tempRateId` if known),
  `.basal` markers, suspends, resumes.
- A replacing batch drops the mutable rows it does not mention. Rows are kept 36 hours.
  `trackingSince` is stamped on the first decode; nothing before it is compared.
- H(t), folded as Trio does: the latest row starting at or before t wins, and a temp row counts
  until its end. A `.basal` marker, an ended temp or no row means the host's schedule
  (`state.basalRateSchedule`, phone clock). After a suspend H is 0 until the resume.
- This replaces #514's proposed `tempRateId` ledger. Because H holds the corrections, a second run
  over the same history reports nothing.

### 3.3 `BasalReconciler` (pure)

- **A chunk differs** when H's rate at its record is more than 10 mU/h from `commandedRate` and no H
  rate within ±1 minute of the record (`transitionMatchTolerance`) matches.
- **A matching chunk never differs,** whatever H does later inside it. That residual is cycle
  timing: the host counts a change from its command, the pump from its next cycle. v1 does not
  correct it.
- **Skipped:** suspended time (source 0, or H suspended), which the transitions pass owns; uncovered
  time; store gaps; chunks before `max(firstSeenFloor, now − 24 h)` or after now.
- **Exempt:** chunks inside `segmentChangeWindow` where the driver over-reports on purpose (#500).
- **Logged per day:** the cycle residual, the sum over chunks of |H's insulin − P's insulin|.

Expected differences: Control-IQ chunks off the schedule (about half of them), a temp the driver
lost (#340), a temp set on the pump, a temp resumed after an alarm suspend, a pump profile that is
not the app's schedule (#400), and a held temp the pump ended unseen. Normal operation produces
none.

### 3.4 Acting: `TandemPumpManager+BasalReconciliation.swift`

With the flag off, each difference is logged once (interval, P, H, kind, intended action) and
nothing is reported. With `basalHistoryReporting` on:

| H at the chunk comes from | Action |
| --- | --- |
| The host's schedule (no row, a `.basal` marker, an ended temp) | Report the chunk as a closed `.tempBasal` correction |
| The held mutable temp | If history shows it completed, `reportTransition(_:tempRateEnd:events:)` at its `TempRateCompleted`. If the pump runs another rate, re-state it like `splitAtSegmentChanges`: the finished part at the old rate, a mutable continuation at the pump's rate |
| A finalized host row | Phase 4, Trio only: report P from 1 s after the row's start through its end |
| A suspend or resume | Left to the transitions pass; logged |

**Corrections:**

- Identity: the existing `HistoryLogSyncIdentifier.logSequence(pumpSerial:sequenceNum:)` with the
  279's sequence number. Phase 1 removes its other users, none of which reach a host.
- Extent: from the chunk's start to its end, or to the start of the host's next row inside the chunk
  if that is earlier.
- Fields: `.tempBasal`, `deliveredUnits`, `insulinType`. `automatic` for algorithm chunks and temps
  with a 309 record. `wasProgrammedByPumpUI` for algorithm chunks and temps without one. Profile
  chunks set neither. Title "Control-IQ Basal" for algorithm chunks, "Temp Basal" otherwise.

**Emission:**

- `reportHistoryDoses` (`TandemPumpManager+HistoryDoseReporting.swift:7`) runs the transitions pass
  and the reconciliation, emits their events as one batch (R1), then the boluses. The transitions
  pass returns its events instead of emitting them
  (`TandemPumpManager+DeliveryTransitions.swift:182` and `:321`).
- A batch is replacing only when it acts on the held temp (R2), and then carries
  `getActivePumpEvents()`. `reportTransition` gets an explicit replacing flag in place of
  `events.contains { $0.dose?.type == .tempBasal }`.
- Never reconcile past an unhealed store gap. A gap not healed within two ticks is skipped and
  logged.
- A correction above `maxBasalLimitMilliunits` is logged as an error, since Trio drops it.
- A persisted `reconciledThrough` sequence number bounds the work per pass. It resets on a new
  serial or an erased log, like `DeliveryTransitionLedger.track`.
- Closed chunks only, so corrections lag 5–10 minutes. The open chunk is not reported.

### 3.5 Control-IQ

- When `useControlIQ` goes from true to false (`configureControlIQMode`'s success path, or
  `fetchControlIQStatus`), persist `controlIQEndedAt`. While it is set, `ensureCurrentPumpData` does
  not throttle, and `syncPumpData` waits as for a pending transition
  (`afterDeliveryTransitionIsReported`, generalized, bounded by `transitionHistoryWait`, 30 s).
  Today the sync completes before its history tick (`TandemPumpManager.swift:549-565`).
- Clear `controlIQEndedAt` after a pass that started after it, read the log to the pump's end and
  reconciled through it. On a timeout the sync completes and the corrections go out with a later
  pass.
- A pass that sees source 3 or 4 while `useControlIQ` is false, or PCM 1 while it is true, calls
  `fetchControlIQStatus` in the same command job.
- An app temp the driver still holds when Control-IQ starts ends at its `TempRateCompleted` (closes
  #353's G07).
- `verifyDeliveredBasalRate` (`TandemPumpManager+StateSync.swift:811`) compares `profileBasalRate`
  with the schedule under Control-IQ instead of returning early.

## 4. Phases

One PR to `dev` per phase, each with its CLAUDE.md update; conformance work with a faketandem branch
of the same name.

| Phase | Scope | Done when |
| --- | --- | --- |
| **0a** | #482: one shared history-date helper (reconciler + `hostDate`), used for boluses and the emit floor | G1, G3 and G4 markers flip and are removed |
| **0b** | `TrioDoseStoreOracle` brought up to the Trio rules in §2, with a `getTempBasals`-style IOB | `DoseOracleTests` cover each rule; Trio-only markers rechecked (those citing #329 may now pass) |
| **0c** | faketandem, §6 | Group H can stage a Control-IQ session |
| **1** | `PumpBasalTimeline` with the cross-check and the `DailyBasal` check. `HistoryToDoseMapper` made bolus-only: its temp, `BasalRateChange`, suspend, resume and alarm branches go, with `scheduledBasalRate: { _ in 0 }` | Unit tests |
| **2** | `ReportedBasalLedger` and `BasalReconciler`; differences and the cycle residual logged on every pass while `historyBackfill` is on | Unit tests; field logs show no differences in normal use and the expected ones under Control-IQ |
| **3** | `basalHistoryReporting`; corrections over the schedule; held-temp actions; R1 batching; §3.5 | Unit and manager tests; conformance H1–H10. Fixes #213 |
| **4** | Corrections over finalized rows (Trio) | Manager tests; H5 extended |
| **5** (#340) | After an unanswered `SetTempRate`, read `CurrentBasalStatus` and `TempRateRequest`, and record the temp, with the duration it requested, if the pump runs it. On a `tempBasal` reading while a temp is held, a `TempRateResponse.startTime` other than the held temp's start makes a pending transition: history ends the held temp and adopts the new one into `basalDose` | A5's #340 marker flips |

The flag: title "History Basal Reporting". Description: "Checks the basal rates the pump delivered,
from its history log, against what the app was told, and reports the difference to the app's insulin
history: Control-IQ's basal changes, temp rates the app did not set or lost track of, and a pump
profile that differs from the app's schedule. Only has any effect while History Backfill is on."

## 5. Tests

Fixtures are built with each record's `buildCargo`. No pump logs go in the repository.

**Unit (`TandemKitTests`):**

- `PumpBasalTimelineTests`: a chunk per 279 with its kind; a late 279, a missing one, and a resume
  with and without one; the open top chunk and a store gap; a suspend ends a chunk; the cross-check
  (exact temp rate, a stop and set in a 279's second, a temp resumed after an alarm suspend, a temp
  past its duration, source 3 under each PCM); the `DailyBasal` check passing, with a short cycle,
  and failing; a clock change and a pump clock offset; 0xFFFF.
- `ReportedBasalLedgerTests`: the Trio fold; `.basal` markers; suspend and resume; a replacing batch
  purges unmentioned mutable rows; raw-value round trip; pruning; `trackingSince`.
- `BasalReconcilerTests`:
  - nothing from app temps, segment cuts, skew compensation, a change inside a chunk, or a temp
    replaced within a cycle;
  - the ±1 minute and 10 mU/h tolerances and the `segmentChangeWindow` exemption;
  - Control-IQ chunks on and off the schedule, a lost temp, a temp resumed after an alarm suspend, a
    profile mismatch, and a held temp the pump ended;
  - nothing from a refused set after a stop once the transitions pass has reported the stop;
  - suspended and uncovered time skipped; a second run finds nothing.
- `BasalReconciliationReportingTests`, at manager level through `StubPumpBluetooth` and
  `storeHistoryLogs`, like `HistoryDoseReportingTests`:
  - corrections go out once, ascending, immutable, with `deliveredUnits` and the right extent;
  - nothing is repeated across a relaunch;
  - one batch with the transitions pass (R1);
  - the held temp is ended or re-stated in a replacing batch with no extra `.basal` marker (R2, R4);
  - the hand-back wait, its timeout, unreadable history, and no throttling meanwhile;
  - with the flag off, differences are logged and nothing is reported.
- State: equality and raw-value round trip for the new fields (Harmonize
  `EqualityComparesEveryStoredProperty`, `StateTypesAreEquatable`); feature flag tests; strings
  through `String(localized:)`. `DriverMessagesHaveSerializationTests` needs nothing new: 279, 2,
  15, 11, 12, 81, 230, 309 and `TempRateRequest` have tests.

**Conformance group H** (`docs/conformance-test-plan.md`). `PumpTimeline` gains basal chunks from
the feed's 279 records, compared with the host's rows at each record as in §3.3.

| ID | Scenario | Assert |
| --- | --- | --- |
| H1 | An app temp runs. Control-IQ is switched on for an hour, with rates above and below the profile and a sync every 5 minutes, then switched off, then the app sets a temp | The app temp ends at its completion record. One correction per 279 off the schedule, at the pump's rate, the last ending at its chunk's end or the app's first temp. The sync after the switch-off returns only after that. Loop counts every correction and its IOB matches `PumpTimeline`'s. Trio stores every correction |
| H2 | The radio is off for 2 h during Control-IQ, then a sync | One ascending batch; Loop keeps every correction |
| H3 | Relaunch from `rawValue` during Control-IQ | Nothing reported twice; corrections continue |
| H4 | A suspend and resume during Control-IQ | The chunk ends at the suspend; the suspend, resume and corrections go in one batch |
| H5 | A5 with reporting on (#340) | The pump's temp is reported at its pump times and rate. Trio's IOB is right; Loop's only if it lands before the next app temp is finalized (phase 5 removes that race) |
| H6 | App temps, cancels, a temp across a segment change, skew compensation (D5) | No difference, nothing reported |
| H7 | A temp set on an X2's screen | Reported as its chunks close, with `wasProgrammedByPumpUI` |
| H8 | The pump's profile is not the app's schedule (#400) | Corrections at the pump's rate; IOB matches `PumpTimeline`; the mismatch alert still shows |
| H9 | An alarm suspend during an app temp; the temp resumes with delivery | The temp's chunks after the resume are reported until the app's next temp |
| H10 | A CGM dropout during Control-IQ (PCM 3 → 2 → 3) | Profile chunks; nothing reported while the profile is the app's schedule |

## 6. faketandem

1. A 279 every 300 s with sources 0, 1, 2 and 3 (`tempRate` exactly `percent × profileBasalRate`),
   and one at a resume after a suspended cycle, restarting the cadence.
2. Delivery and the reservoir follow the 279 cycle, while `CurrentBasalStatus` shows a command at
   once.
3. A Control-IQ basal driver while `closed_loop_enabled` is set: algorithm rates scripted through the
   API; a 230 with PCM 3 → 2 at the cycle where the CGM drops out (source 1 at the profile rate) and
   back; 3 → 0 → 3 around a suspend; PCM 1 while Control-IQ is off.
4. `DailyBasal` growing by each cycle's insulin, with `lastBasalRate` the latest 279's rate.
5. A 309 with the temp's id for each app temp, and a 230 at each suspend and resume.
6. `TempRateCompleted.timeLeft` in milliseconds, in whole minutes (faketandem writes seconds today).
7. An alarm suspend that keeps the running temp: no `TempRateCompleted`, and the temp resumes.
   faketandem's `SuspendDelivery` ends the temp at every suspend today, and conformance F4 relies on
   that.

Until items 1–3 land, group H stages history with `appendHistory(records:)`, as
`HistoryBackfillIntegrationTests` does for 279; `docs/integration-harness.md` lists the gap.

## 7. Docs

- CLAUDE.md, "History backfill and dose reporting": the reconciliation, the ledger and the
  hand-back. Phase 3 replaces "Temp rates the app did not set are still not reported".
- CLAUDE.md, "Pump event batches": R1, R2 and R4. "Therapy command validation": the 5-minute
  delivery cycle (phase 1) and `verifyDeliveredBasalRate` under Control-IQ (phase 3).
- `HistoryLogSyncIdentifier`'s doc comment: `logSequence` identifies basal corrections.
- `docs/conformance-test-plan.md` (group H), `docs/integration-harness.md` and
  `docs/ARCHITECTURE_ANALYSIS.md` ("History").

## 8. Out of scope

- **Cycle timing** is not corrected in v1. Loop would drop such corrections, and Trio would need
  about two rows per app temp. Revisit with phase 2's residual logs.
- **A temp the pump resumes after an alarm suspend** is ignored by the live path
  (`observeDeliveryState`: "A temp rate the app did not set is not reported"), so the host assumes
  its schedule while the old temp runs. Separate issue, which also revisits F4 and §6 item 7.
  Phase 3 corrects it after the fact (H9).

## 9. Risks

- **A misread record gives wrong IOB.** Phase 2 is log-only in the field first, and every corrected
  stretch must pass the cross-check and the `DailyBasal` check.
- **Only Mobis (7.7, 7.9) have been observed.** An X2 that delivers differently fails the
  `DailyBasal` check and gets no corrections.
- **H models Trio.** A row Loop dropped (IDS window) or a batch dropped for a missing delegate
  (#342) still counts as told.
- **Loop residuals:** a gap given up on, and a #340 temp reported after the next app temp is
  finalized.
- **Trio rounds** each chunk's net insulin to 0.05 U.
- **Volume:** one correction per Control-IQ cycle off the schedule, about 130 a day observed, at
  most 288.
