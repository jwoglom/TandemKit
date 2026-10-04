# Basal delivery from pump history: implementation plan

Plan for #514, written against `dev` at 1b7d89b. It fixes #213 (Control-IQ's basal changes never
reach the host's IOB) and gives #340 an after-the-fact backstop. #340's immediate fix is phase 4
below and stays tracked in #340.

Phases 1–3 change nothing until a new `historyBasalReporting` flag is turned on. Phase 0a changes
history bolus dates, which are already behind `historyDoseReporting`.

## 1. Constraints

### 1.1 What the pump writes

| Record | Fields this plan reads | When it is written | How sure we are |
| --- | --- | --- | --- |
| `BasalDelivery` (279) | `commandedRateSource`, `commandedRate`, `profileBasalRate`, `algorithmRate`, `tempRate`, all mU/h; 0xFFFF means n/a | Every 5 min, Control-IQ on or off. In the captures it follows that cycle's `ControlIQCycle` (227) by 65–91 s on an X2 and by 30 s on a Mobi | Sources 0, 1 and 2 confirmed on a Mobi with Control-IQ off; 3 seen in X2 and Mobi Control-IQ captures; 4 (temp rate and algorithm) never seen |
| `TempRateActivated` (2), `TempRateCompleted` (15) | `percent`, `durationMilliseconds`, `tempRateId`; `tempRateId`, `timeLeft` | When the temp starts and when it ends, stops or is replaced | Used today by `reportHistoryDeliveryTransitions` |
| `BasalRateChange` (3) | `commandBasalRate`, `baseBasalRate` (U/h floats), `changeTypeId` | When a timed segment starts, a profile changes, a temp starts or ends, or the pump suspends or resumes | Only pumpX2's X2 fixtures. Tidepool's Tandem uploader builds its basal records from it ("used to create all other basals", its checklist says). Not confirmed on a Mobi (Q3) |
| `PumpingSuspended` (11), `PumpingResumed` (12) | — | When delivery stops and restarts | Used today |
| `AaEnableSettingChange` (244) | `enabled` | Presumably when Control-IQ is switched on or off | Unconfirmed (Q2). It has no serialization test and pumpX2 has no vector, so the Harmonize rule needs a pump capture before the driver can read it |
| `ControlIQPcmChange` (230) | `currentPcm` | When the pump control mode changes | Has a test. What it shows at a switch is unconfirmed (Q2) |

Two things follow. Control-IQ's rate changes exist only in 279, as #514 says, and 279 is a 5-minute
sample of the commanded rate, so a Control-IQ interval runs from one record to the next. For temp
rates, the pump's own absolute numbers (279's `tempRate`, 3's `commandBasalRate`) beat
`percent × a profile rate`, because the pump's rounding is unknown
(`TandemPumpManager.tempBasalReadbackMatches`).

### 1.2 What the hosts do with a basal report

**Trio** (`dev` since nightscout/Trio#1300; jwoglom/Trio `dev` 1802999c):

- `.basal` is stored as a zero-length scheduled row (`PumpHistoryStorage.storedSpan`). Only
  `.tempBasal` rows carry insulin, which is why #514 reports basal as `.tempBasal` doses.
- `PumpEventStored.toPumpHistoryEvents` turns every temp-basal row, scheduled rows included, into a
  `TempBasal` and duration pair. `IobHistory.getTempBasals` sorts them by timestamp and cuts each
  one off at the next row's timestamp. Net insulin is counted against Trio's own schedule.
  - Arrival order does not matter: a row reported late still cuts off the row before it.
  - Two rows with the same timestamp leave one of them zero-length, whichever sorts first.
  - `extractTempBoluses` rounds each piece's net insulin to 0.05 U. A 5-minute piece with
    |net| below about 0.3 U/h counts zero. The same rounding applies to Trio's own temps, which
    the loop often replaces after one cycle.
- Rows are matched by `syncIdentifier`, then by `(timestamp, type, isScheduledBasal)`. A finalized
  row never changes. A replacing batch deletes every mutable row it does not mention.
- `DeviceDataManager` drops a temp basal above `pumpSettings.maxBasal` before storing anything.
- A row's timestamp is clamped to now.

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
`(date, type)`. It would show every finalized history span as skipped. Phase 0b brings it up to
date.

### 1.3 Rules that follow

- **R1.** Every non-bolus event a history pass produces goes out in one batch, in ascending order:
  the basal spans together with that pass's suspends, resumes and temp ends. Loop would otherwise
  drop a span older than something the previous batch finalized.
- **R2.** If the host holds a mutable temp that started before a history span's start, the same
  batch finalizes that temp no later than the span's start (earlier if its own `TempRateCompleted`
  says so, R6). The pump runs one rate at a time, so the span proves the temp had ended by then.
  That batch is a replacing one.
- **R3.** Whatever the host must hear before it next doses reaches it before the sync completes,
  as pending delivery transitions do today (`afterDeliveryTransitionIsReported`).
- **R4.** No `.basal` marker is emitted at an instant where a history span starts (Trio, see the
  equal-timestamp bullet above).
- **R5.** Every reported span carries `deliveredUnits` (rate × duration, rounded to 0.001 U), an
  absolute rate, and an identity that never changes.

## 2. Design

### 2.1 `HistoryBasalTimeline`: one pure builder

New `Sources/TandemKit/PumpManager/History/HistoryBasalTimeline.swift`, in the same spirit as
`HistoryBackfillPlanner`: no I/O, given the stored records of a contiguous stretch of the store and
a `phoneDate(of:)` function, it returns basal spans:

```swift
struct BasalSpan {
    enum Kind { case controlIQ(sequenceNum: UInt32), tempRate(tempRateId: Int, part: Int) }
    let kind: Kind
    let start: Date
    let end: Date?          // nil while open
    let unitsPerHour: Double
    let firstSequenceNum: UInt32, lastSequenceNum: UInt32
}
```

**Dates.** Every record is dated through the same `phoneDate(of:)` that
`reportHistoryDeliveryTransitions` uses: `HistoryTimestampReconciler.utcDate` and then
`hostDate(forPumpDate:)`. Phase 0a moves it into one shared helper and puts the bolus path on it,
which is the #482 fix.

**Control-IQ spans.** There is one span per 279 record whose source is `algorithm` (3) or
`tempRateAndAlgorithm` (4), at `commandedRate / 1000` U/h. A record with `commandedRate == 0xFFFF`
produces no span and is logged.

- A span starts at its record's time. It ends at the earliest of: the next 279 record, a
  `PumpingSuspended`, the record that ends Control-IQ (244 or 230, once Q2 confirms which), the time
  the driver itself turned Control-IQ off, or a cap of one cycle plus the jitter seen in captures
  (7 min until Q1 says otherwise).
- A span is closed only when the record that ends it has been read and nothing between the two is
  missing from the store (`HistoryLogStore.missingRanges`). Only closed spans are reported (§2.8).
- **No merging.** #514 suggests merging consecutive equal-rate records under a sequence-range
  identity. Each record gets its own span instead, identified by its own sequence number. A merged
  run's identity depends on the record before the run, which the backward walk may not have read
  yet, and on its last record, which is not known until the rate changes. The run would either
  change identity or stay open indefinitely. Per-record spans are final the moment the next record
  is read. They cost little: a closed-looping Trio often sets a new temp every cycle, and
  Control-IQ changes rate almost every cycle, so there would be little to merge. Merging can come
  later, for runs whose first and last records are both read.
- Profile spans (source 1) and suspended spans (source 0) are not reported. The host already
  assumes its schedule, and the pass already reports suspends.

**Temp-rate spans** (phase 3). A temp runs from its `TempRateActivated` to the earlier of its
`TempRateCompleted` and its programmed end. One whose completion says it ran out (`timeLeft` 0,
within a minute of the programmed end) ends exactly at the programmed end, the rule the transitions
pass already uses. A temp with no completion yet is open. It is split wherever the pump's rate
changed, and each part takes its rate from the first of these that the store holds:

1. `BasalRateChange` `commandBasalRate` at the part's start (exact time and rate; needs Q3);
2. 279 `tempRate` while the source is `tempRate`. A change shows up at most a cycle late, so the
   cut goes on the pump's segment boundary when the host's schedule is the verified pump profile,
   and on the record otherwise;
3. `percent ×` 279 `profileBasalRate`, or `BasalRateChange` `baseBasalRate`;
4. `percent ×` the host's schedule on the pump's clock, only while `hasSyncedBasalRateSchedule` and
   no mismatch is confirmed. This is the same arithmetic as `splitAtSegmentChanges`.

If none of these is available, the temp is held back and logged. A temp that overlaps Control-IQ
spans ends at the first one, since `commandedRate` already includes it.

**`HistoryToDoseMapper` becomes bolus-only.** Its temp-rate, `BasalRateChange`, suspend, resume
and alarm branches, and the `scheduledBasalRate: { _ in 0 }` and `roundBasalRate` parameters, are
deleted along with their tests. Nothing reports them, the transitions pass owns suspends and
resumes, and a `.basal` event per `BasalRateChange` would give Trio scheduled rows that cut off real
temps (R4).

### 2.2 Who reports what

| Delivery | Start reported by | End reported by |
| --- | --- | --- |
| Control-IQ span | History (phase 2). The live path never reports Control-IQ | History, together with the start |
| Temp the app set (`TempRateReportLedger`, origin `commanded`) | Live path, as today | Live path, or the transitions pass from its `TempRateCompleted`, as today; plus R2 and R6 |
| Temp the driver set and the host is never told of (skew compensation, a temp stopped after a mismatched readback) | Nobody (ledger origin `suppressed`) | Nobody |
| Foreign temp: a lost acknowledgement (#340) or set on the pump's screen | History, once completed (phase 3); adopted by the live path while it runs (phase 4) | History (phase 3) or the live path after adoption (phase 4) |

The ledger is what makes this table work. Without it, history would report every app temp a second
time, and every skew-compensation temp, which by design the host is never told of.

- **R6** (phase 3). If the store holds a `TempRateCompleted` for the temp the driver holds, dated
  after that temp's start, the temp is finalized at that record even when no reading noticed. This
  is `reportTransition(_:tempRateEnd:events:)` with a pending transition built from the record. It
  covers the #340(b) shape: the held temp was stopped and the reading after still said `tempBasal`.
  What the driver holds next is decided by what history shows after the completion: a suspend, a
  foreign temp (status placeholder only, nothing emitted, per R4), or scheduled basal.

### 2.3 `TempRateReportLedger` (phase 3)

New `Sources/TandemKit/PumpManager/History/TempRateReportLedger.swift`, persisted in
`TandemPumpManagerState`, modelled on `BolusReportLedger`:

- Entries keyed by `(pumpSerial, tempRateId)`: origin (`commanded`, `suppressed`, `history`,
  `adopted`), start date, percent, and whether the host has been told the temp ended.
- Unconfirmed commands: a `SetTempRate` whose answer was lost records its percent, duration and the
  time it was sent. A `TempRateActivated` with an unknown id that matches one within a tolerance is
  attributed to the app (`automatic: true`, not programmed on the pump), not to the pump's screen.
- `trackingSince` is stamped on the first decode by a build that has the ledger. Temps activated
  before it are never reported from history, because they cannot be told apart from app temps
  reported live without an entry. Entries are kept 36 hours, as `BolusReportLedger.retention`.
- Written by `recordTempBasal` (`TandemPumpManager.swift:976`), the unanswered branch of
  `enactTempBasal` (`:940`), `rejectMismatchedTempBasal` (`:1024`) and
  `maintainPumpClockSkewCompensation` (`TandemPumpManager+StateSync.swift:918`).
  `skewCompensationTemp` is in memory only, so without the ledger a relaunch would also forget
  which running temp was compensation.

### 2.4 Identities

- **Control-IQ span:** `HistoryLogSyncIdentifier.logSequence(pumpSerial:sequenceNum:)` of its 279
  record. That fits the type's own rule: it is reported once, already final.
- **Foreign temp:** `tempRate(pumpSerial:tempRateId:)` for the first part. Later parts need a new
  scheme, `tempRatePart = 4`, with identifier `tempRateId | part << 16`. Adding a scheme keeps the
  frozen 10-byte format.
- **Adopted temp** (phase 4): the live path's `raw`, as for an app temp. Re-keying live temps on
  `tempRateId` (#344) stays separate, because switching identity schemes for doses already in a host
  risks duplicates on upgrade.

### 2.5 Emission

- History spans are reported immutable only. A batch is replacing exactly when it finalizes a dose
  the host holds as mutable (R2, R6). Every replacing batch carries `getActivePumpEvents()` for a
  live temp it does not finalize, and `emitPumpEvents` adds the boluses. Today `reportTransition`
  decides replacing by `events.contains { $0.dose?.type == .tempBasal }`, which every basal batch
  would now meet. It needs the explicit flag instead.
- `reportHistoryDoses` (`TandemPumpManager+HistoryDoseReporting.swift:7`) runs the non-bolus pass,
  meaning transitions and basal merged into one batch (R1), then boluses. The transitions pass
  returns its events to that single emission instead of emitting them itself
  (`TandemPumpManager+DeliveryTransitions.swift:182` and `:321`). On the transitions pass's early
  returns (tick too early, history not read), the spans wait for the next pass.
- Each span is reported as `.tempBasal` with `deliveredUnits` (R5), `insulinType`, and a title of
  "Control-IQ Basal" or "Temp Basal". `automatic` is true except for a temp set on the pump's
  screen. `wasProgrammedByPumpUI` is true for Control-IQ (as history boluses do) and for
  screen-set temps.
- **Floors:** `max(firstSeenFloor, now − 24 h)`, compared on phone dates (#482). Not the bolus
  ledger's `trackingSince`: no live report of Control-IQ basal exists to collide with. Temps do
  start at or after the temp ledger's `trackingSince`. Spans that start ahead of the phone are
  ignored.
- **Bookkeeping:** a persisted `HistoryBasalReportState { pumpSerial, reportedThrough }` records the
  sequence number through which spans have been reported. A relaunch's re-read of the 7-hour
  lookback then sends nothing twice. It resets on a new serial or an erased log, like
  `DeliveryTransitionLedger.track`.
- **Gaps:** spans are reported in sequence order and never past a store gap. Otherwise a healed
  gap's spans would arrive after newer ones and Loop would drop them. A gap the coordinator has not
  healed within two ticks is skipped and logged.
- **Sanity check:** a span above the pump's max basal limit (`maxBasalLimitMilliunits`) is logged as
  an error, since Trio drops it (Q5).
- Under Control-IQ the live path already emits no `.basal` marker of its own: app temps are refused
  and `restartBasalDoseAfterScheduleChange` is guarded. The remaining source is a transition that
  ends a held temp, which R4 covers.

### 2.6 Handing back from Control-IQ (phase 2)

Today a sync completes before its history tick runs (`TandemPumpManager.swift:549-565`). At the
moment Control-IQ ends, the host doses on that sync, so the last minutes of Control-IQ would arrive
after the app's first temp. For Loop that loses them for good.

- When `useControlIQ` goes from true to false (in `configureControlIQMode`'s success path, or in
  `fetchControlIQStatus`), persist `controlIQEndedAt` in `HistoryBasalReportState`.
- While it is set, `ensureCurrentPumpData` does not throttle, and `syncPumpData` waits as it does
  for a pending transition (`afterDeliveryTransitionIsReported`, generalised; bounded by
  `transitionHistoryWait`, 30 s). It is cleared by a pass that started after it, reads to the
  pump's end and reports the last Control-IQ span. That span ends at the earliest of its next 279
  record, the record that ends Control-IQ, and `controlIQEndedAt`. If the wait times out, the sync
  completes anyway, as it does for a pending transition, and the spans go out with a later pass.
- A pass that finds Control-IQ's state in history differing from `useControlIQ` calls
  `fetchControlIQStatus` in the same command job. Today that status is read only every 24 hours or
  on the `controlIQInfo` qualifying event, so a missed event leaves the dosing guards wrong for up
  to a day.
- When Control-IQ starts, R2 ends a live temp still held at the first span. That also closes #353's
  G07, where a pump-side switch to Control-IQ leaves the app's temp running in the host.

### 2.7 Profile alignment (#514 item 5)

An absolute-rate span makes the host's IOB right for the time it covers, whatever the pump's
profile, because the host computes net against its own schedule. Two consequences:

- Report every Control-IQ span, including those at the profile rate. Skipping them would leave gaps
  the host fills with its schedule, which is only right if the pump's profile matches it.
- Profile alignment then matters only for the gaps (the first cycle after Control-IQ starts, a
  resume before the next record, a gap given up on) and for the app's temps after hand-back.
  `verifyDeliveredBasalRate` returns early under Control-IQ (`TandemPumpManager+StateSync.swift:811`).
  Under Control-IQ it should compare `profileBasalRate` instead (Q6), so `hasSyncedBasalRateSchedule`
  and the confirmed mismatch are current at hand-back, and the app's first temp runs on a verified
  profile.

### 2.8 Rejected alternatives

- **A mutable span for the Control-IQ interval still running.** It would cut the lag, which is at
  most a cycle plus a tick, but it has to ride in every replacing batch until it is finalized,
  which is the #330/#452 problem. Hand-back (§2.6) is the only point where that lag matters for
  dosing, and the wait covers it. While Control-IQ runs, the host makes no automatic doses, though
  a manual bolus is computed from an IOB missing up to ~10 minutes of Control-IQ's adjustment.
- **Reporting profile spans as well, so history owns the whole basal timeline (as MinimedKit
  does).** That would fight the live path's temps and `.basal` markers. It is out of scope.
- **Converting history temps against the host's schedule.** The schedule is right only when it is
  the pump's profile, which is what #400 and #500 moved the live path away from. It is kept only as
  the last fallback, and only behind the verified-profile check.

## 3. Phases

Each phase is one PR to `dev`. The driver change goes in with its CLAUDE.md update. Conformance work
goes in with a faketandem branch of the same name when it needs one.

| Phase | Scope | Behaviour change | Done when |
| --- | --- | --- | --- |
| **0a** | #482: one shared history-date helper (reconciler + `hostDate`), used for boluses and for the emit floor | History bolus dates after a time change | G1, G3 and G4 markers flip and are removed |
| **0b** | `TrioDoseStoreOracle` brought up to Trio `dev`: stores finalized temps, `syncIdentifier` upsert with the scheduled-aware fallback, finalized rows frozen, replacing batches purge unmentioned mutable rows, `.basal` stored as a zero-length row, the `maxBasal` filter, and `getTempBasals`-style cut-off for an IOB check | Tests only | `DoseOracleTests` cover each rule. Every Trio-only marker is rechecked; those citing #329 may now pass unexpectedly, since nightscout/Trio#1300 stores finalized temps and cuts them off at `.basal` rows |
| **0c** | faketandem branch: see §5 | Emulator only | Phase 2's conformance tests can stage a Control-IQ session |
| **1** | `HistoryBasalTimeline` with Control-IQ spans (temp spans come in phase 3), and `HistoryToDoseMapper` made bolus-only | None | Unit tests below |
| **2** | `historyBasalReporting` flag; Control-IQ spans reported (R1, R2, R4, R5); `HistoryBasalReportState`; hand-back (§2.6); `verifyDeliveredBasalRate` under Control-IQ; the Control-IQ settings screen warns when switching Control-IQ on with either history reporting flag off | Behind the flag. **Fixes #213** | Unit and manager tests; conformance H1–H4 |
| **3** | `TempRateReportLedger` and its four writers; temp spans in the timeline; foreign temps reported once completed; R6; the `tempRatePart` scheme | Behind the flag. **#340 backstop**, and screen-set temps on an X2 | Manager tests; conformance H5–H7 |
| **4** (#340) | After an unanswered `SetTempRate`, read `CurrentBasalStatus` and `TempRateRequest` and record the temp if the pump runs it. On a `tempBasal` reading while a temp is held, compare `TempRateResponse.startTime` with the held temp's start on the pump's clock; a different temp becomes a pending transition, and history ends the held one and adopts the new one into `basalDose` | A live-path fix, not behind `historyBasalReporting`. With `historyBackfill` on, the change is dated from history like any pending transition | A5's #340 marker flips. Needs Q8 |

**Flag (decision 1).** `historyBasalReporting`, off by default and effective only with
`historyBackfill`, separate from `historyDoseReporting` while each is validated:

- Title "History Basal Reporting".
- Description: lets basal delivery found in the pump's history log, meaning Control-IQ's basal
  changes and temp rates the app did not set, reach the app's insulin history.

Correct IOB after Control-IQ needs both reporting flags, since Control-IQ's automatic boluses come
through `historyDoseReporting`. Hence the settings warning in phase 2. The alternative is to fold
basal into `historyDoseReporting`, whose description already says "doses".

## 4. Tests

### 4.1 Unit (`TandemKitTests`)

- **`HistoryBasalTimelineTests`**, built from capture hex the repo already has:
  `ControlIQCycleHistoryLogTests` (X2 at 1697 and 467 mU/h; Mobi at 788 mU/h) and
  `BasalDeliveryHistoryLogTests` (Mobi, sources 0/1/2). Cases:
  - one span per algorithm record, at `commandedRate`;
  - the last record stays open;
  - a suspend or a Control-IQ-off record ends a span;
  - the cap applies;
  - a store gap keeps a span open;
  - 0xFFFF and source 1/2/0 records produce no span;
  - a clock change and a pump clock offset move spans onto the phone's clock;
  - temp spans take each rate source in order of preference, are cut at rate changes, end at
    `timeLeft` 0 at the programmed end, and end at the first Control-IQ span.
- **`HistoryBasalReportingTests`**, at manager level through `StubPumpBluetooth` and
  `storeHistoryLogs`, like `HistoryDoseReportingTests`. Cases:
  - spans go out once, ascending, immutable, with `deliveredUnits`;
  - a second pass sends nothing, and neither does a relaunch through `rawValue`;
  - the floor, future-dated spans and a serial change are respected;
  - a pass with a suspend and spans emits one batch (R1);
  - a held app temp is finalized at the first span, with no `.basal` marker (R2, R4);
  - the batch is replacing only then;
  - hand-back: the sync after Control-IQ ends completes only once the last span is reported;
    timeout and unreadable-history paths; `ensureCurrentPumpData` does not throttle meanwhile;
  - with the flag off, nothing is reported.
- **Phase 3:**
  - app temps (live, rejected, skew compensation) are never reported from history, including after
    a relaunch;
  - a lost-acknowledgement temp is reported once completed, attributed to the app;
  - a screen-set temp is reported with `wasProgrammedByPumpUI`;
  - R6 ends a held temp from its completion;
  - ledger round trip, pruning and `trackingSince`.
- State: `TandemPumpManagerStateEqualityTests` and the raw-value round trip for the new fields (the
  Harmonize `EqualityComparesEveryStoredProperty` and `StateTypesAreEquatable` rules). Feature flag
  and Control-IQ settings view-model tests; new strings go through `String(localized:)`.
- Harmonize `DriverMessagesHaveSerializationTests`: 279, 3, 230, 2, 15 and `TempRateRequest`
  already have tests. Reading 244 needs `AaEnableSettingChangeHistoryLogTests` from a capture
  first, since the baseline takes no additions.

### 4.2 Conformance group H, "Basal from history" (`docs/conformance-test-plan.md`)

| ID | Scenario | Assert |
| --- | --- | --- |
| H1 | An app temp is running. Control-IQ is switched on and runs an hour with rates above and below the profile, with a sync every 5 minutes. Control-IQ is switched off, then the app sets a temp | The app temp ends at Control-IQ's start. There is one temp basal per 279 record, at its rate, contiguous, the last ending at Control-IQ's end. The sync after the switch-off returns only after that. Loop counts every span (none falls before its IDS window) and its IOB over the hour matches `PumpTimeline`'s. Trio stores every span |
| H2 | The radio is off for 2 h during Control-IQ, then on, then a sync | Every span arrives in one ascending batch and Loop holds them all |
| H3 | Relaunch from `rawValue` during Control-IQ | No span is reported twice, and the spans after the relaunch carry on |
| H4 | A pump suspend and resume during Control-IQ | The span ends at the suspend, and the suspend, resume and spans go in one batch |
| H5 | A5 with both history flags on (#340) | Once the temp the pump ran ends, it is reported at its pump times and absolute rate, attributed to the app. Trio's IOB is right. Loop's is right only if this lands before the next app temp is finalized; phase 4 removes that race |
| H6 | App temps run out and are replaced; relaunch; backfill; skew compensation from D5 | Nothing is reported from history |
| H7 | A temp set on the pump's screen (an X2) | Reported once completed, with `wasProgrammedByPumpUI` |

`PumpTimeline` gains Control-IQ spans built from the feed's `BasalDelivery` records, and its diff
matches host temp rows against them.

## 5. faketandem companion work

1. `BasalDelivery` (279) records every 5 minutes of pump time, for every kind of delivery: source 0
   while suspended, 1 on profile, 2 during a temp (with `tempRate`), 3 under Control-IQ.
2. A Control-IQ basal driver while `closed_loop_enabled` is set: algorithm rates scripted through
   the API, delivery arithmetic and `CurrentBasalStatus.currentBasalRate` following them, and the
   switch-on/switch-off records once Q2 settles which they are.
3. `BasalRateChange` (3) records at temp start and end, segment changes, suspend and resume, once Q3
   is confirmed.
4. Nothing for phase 4: it reads `TempRateRequest`, which faketandem answers from state. It avoids
   `TempRateStatusRequest`, which would give the temp's id, because faketandem answers it with
   zeroes and there is no captured vector for its serialization test.

Until items 1 and 2 land, H1–H4 can stage history with `appendHistory(records:)`, as
`HistoryBackfillIntegrationTests` already does for 279. `docs/integration-harness.md` lists the gap
until then.

## 6. Docs

- CLAUDE.md, "History backfill and dose reporting": a bullet for Control-IQ spans and hand-back;
  the ledger and ownership rules; "Temp rates the app did not set are still not reported" rewritten
  in phase 3.
- CLAUDE.md, "Pump event batches": R1, R2 and R4. "Therapy command validation": the mismatch check
  under Control-IQ.
- `HistoryLogSyncIdentifier`'s doc comment: the new scheme, and which reports now use the
  temp-rate and log-sequence identities (the live path still does not, #344).
- `docs/conformance-test-plan.md` (group H), `docs/integration-harness.md` (gaps) and
  `docs/ARCHITECTURE_ANALYSIS.md` ("History").

## 7. Open questions

**Answerable from captures**, before phase 2 merges unless marked:

- **Q1.** Is 279 written on a fixed 5-minute cadence, and does its rate take effect at the record
  or at the `ControlIQCycle` before it (30 s earlier on a Mobi, 65–91 s on an X2)? This sets the
  cap and whether a span should start at the 227.
- **Q2.** What does the pump write when Control-IQ is switched on and off: 244, 230, a 279 straight
  away? Using 244 needs a capture for its serialization test.
- **Q3** (phase 3). On a Mobi, does every temp start and end, and every segment boundary during a
  temp, write a `BasalRateChange` carrying the absolute rate?
- **Q4.** Can a temp rate run under Control-IQ (source 4)? If so, what do 2/15 and 279 show?
- **Q5.** Does Control-IQ stay within the pump's max basal limit? Trio drops anything above its
  `maxBasal`, which `syncDeliveryLimits` pushes to the pump.
- **Q6.** Under Control-IQ, is `CurrentBasalStatus.profileBasalRate` the profile rate?
- **Q7.** With no CGM, which source does Control-IQ write (PCM `cgmInactive`/`openLoop`)?
- **Q8** (phase 4). What unit is `TempRateResponse.duration`? faketandem guesses seconds.

**Decisions for the maintainer:**

1. A separate `historyBasalReporting` flag, or basal folded into `historyDoseReporting` (§3).
2. Per-record Control-IQ spans rather than merged runs (§2.1).
3. Closed spans plus the hand-back wait, rather than a mutable running span (§2.8).
4. Whether switching Control-IQ on from the app should warn, or refuse, while history reporting is
   off.

## 8. Risks

- Misreading 279 gives wrong IOB for everyone using Control-IQ. Mitigations: capture-backed
  fixtures, Q1–Q7 settled first, and the flag. A later check of reported basal against the pump's
  own daily total (`DailyBasal`, 81) would catch a misreading in the field; it belongs with #354's
  P21-3.
- Trio rounds each 5-minute piece to 0.05 U, so small Control-IQ adjustments count as zero. This is
  inherent to oref and matches its handling of Trio's own temps.
- Loop's IDS window drops anything reported after a later basal dose. R1–R3 and hand-back cover the
  driver's side. A gap given up on, and a #340 temp reported after the next app temp is finalized,
  are the known residuals.
- Event volume is up to 288 temp rows a day under Control-IQ, about what Trio's own loop writes.
