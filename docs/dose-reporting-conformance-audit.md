# TandemKit dose-reporting conformance audit

## Scope

This audit checks the TandemKit pump driver against LoopKit's guide
[Reporting Insulin Doses to Loop](https://github.com/loopkitdev/LoopKit/blob/next-dev/Documentation/PumpManagerDoseReporting.md),
point by point. It is a review of source code, not of hardware behaviour. Where a conclusion depends on how pump firmware behaves,
the report says so and lists it as an open question.

- TandemKit commit audited: `7d20b2dc2bed69f0ae94224bd2be1f92d384828c`.
- LoopKit variants compared: the `loopandlearn/LoopKit` fork at the commit Trio pins (this is what TandemKit builds against
  today; its `DoseEntry` has no `decisionId`), and `loopkitdev/LoopKit` `next-dev`, which the guide was written against.
  The Linux build shim in `LinuxShims/LoopKit/LoopKit.swift` was also compared where it diverges.
- Host consumer: the guide describes Loop's `DoseStore`. TandemKit ships inside Trio, whose `DeviceDataManager` and
  `PumpHistoryStorage` treat pump events differently. Both consumers are considered; point G01 covers the Trio side.
- Pump context: Tandem t:slim X2 and Tandem Mobi are UI-capable pumps in the guide's sense. The X2 lets the user bolus, set temp
  rates and suspend on the pump. The Mobi has a quick-bolus button and Tandem's own phone app. Control-IQ on both delivers
  automatic correction boluses and modulates basal on the pump itself.

Points P01 to P10 are the guide's conformance checklist (§9). P11 to P14 are the four pitfalls in §10. P15 to P21 are the seven
testing recommendations in §11. P22 to P24 cover the data model (§2), the zero-delivery transition in §3, and the `DoseStore`
consequences in §8. G-points are gaps found outside that structure.

Verdict legend: **Conforms** means the requirement holds on every path traced. **Partial** means it holds on some paths, or only
behind a non-default feature flag, or with a concrete gap. **Non-conforming** means it is violated or not implemented. **Unsure**
means the code alone could not settle it. **Not applicable** means the requirement does not apply to TandemKit's targets. A
point's overall verdict is the most conservative verdict among its findings, so one non-conforming finding makes the point
non-conforming even when most of its findings conform.

Verification legend: **verified** means an independent reviewer re-read the cited code and confirmed the finding. **amended**
means the reviewer changed the verdict or impact; the auditor's original is shown. **contested** means one reviewer disagreed.
**unverified** means no independent review completed for that finding (see the method section for why). Findings marked "added
by a verifier" were raised during review rather than by the point's auditor.

Safety impact is about insulin accounting. **high** means Loop or Trio could count IOB wrong by a clinically meaningful amount, or
lose or duplicate a dose. **medium** means wrong metadata or timing that degrades accounting. **low** means cosmetic or upstream
only. Nothing in this report is medical advice; it is engineering review material for the maintainers.

## Summary table

| Point | Guide section | Requirement | Overall | Highest impact | Findings |
| --- | --- | --- | --- | --- | --- |
| P01 | §9 item 1 (with §1, §6, §8) | hasNewPumpEvents is called on every sync with the pump, even when there are no new doses, so... | Non-conforming | medium | 8 |
| P02 | §9 item 2 (with §6) | A current, correct lastReconciliation is always passed: for a UI-capable pump this must be the time of the... | Non-conforming | high | 7 |
| P03 | §9 item 3 (with §4) | Each dose has a raw/syncIdentifier that is byte-for-byte constant for the entire life of that dose,... | Non-conforming | medium | 7 |
| P04 | §9 item 4 (with §3 report-or-delete rule) | In-progress doses are reported with isMutable: true and re-reported on EVERY sync until they finalize;... | Non-conforming | high | 7 |
| P05 | §9 item 5 (with §3 finalization) | Finalized doses are reported with isMutable: false, a real endDate, and the actual deliveredUnits | Non-conforming | high | 7 |
| P06 | §9 item 6 (with §5) | replacePendingEvents is true when a batch is the complete current set of pending delivery and false only... | Non-conforming | high | 6 |
| P07 | §9 item 7 | value carries the programmed amount and deliveredUnits the actual amount, both rounded to the pump's... | Non-conforming | high | 8 |
| P08 | §9 item 8 (with §7) | UI-capable pump: wasProgrammedByPumpUI is set for user-initiated doses and they are reconciled from pump... | Non-conforming | high | 6 |
| P09 | §9 item 9 | decisionId is threaded from enactBolus/enactTempBasal through to the DoseEntry | Partial | medium | 4 |
| P10 | §9 item 10 | Suspend/resume, prime, alarm, and pump-replacement events are emitted with appropriate PumpEventType values | Non-conforming | high | 8 |
| P11 | §10 pitfall: temp basal finalization and overwrite | A running temp basal keeps a stable syncIdentifier across every update, is finalized (not dropped) on... | Non-conforming | medium | 6 |
| P12 | §10 pitfall: bolus during BLE loss | A bolus is registered up front as a mutable dose before contact can be lost, its in-progress state is... | Non-conforming | high | 7 |
| P13 | §10 pitfall: suspend / resume events | Suspend and resume are modeled as real dose events with correct timing: a suspend is emitted whenever... | Non-conforming | high | 7 |
| P14 | §10 pitfall: faults, alarms, pump replacement | Pump faults are surfaced as NewPumpEvent with type .alarm / alarmType, and .replaceComponent is emitted on... | Non-conforming | low | 6 |
| P15 | §11 testing: interrupt everything | Tests cover BLE loss mid-bolus and mid-temp-basal, verifying the dose is recovered and finalized with the... | Non-conforming | high | 6 |
| P16 | §11 testing: cancel everything | Tests cancel a bolus and a temp basal at various points and verify the finalized dose shows the partial... | Non-conforming | medium | 5 |
| P17 | §11 testing: idempotency | Tests re-report the same in-progress dose many times and confirm it stays a single dose with identical raw... | Non-conforming | medium | 6 |
| P18 | §11 testing: empty syncs | Tests confirm a sync with no new doses still calls hasNewPumpEvents and advances lastReconciliation | Non-conforming | medium | 9 |
| P19 | §11 testing: rounding | Tests verify value and deliveredUnits are rounded to the pump's supported increment | Non-conforming | low | 7 |
| P20 | §11 testing: external doses (UI pumps) | Tests bolus on the pump directly and confirm Loop picks it up from history with wasProgrammedByPumpUI =... | Non-conforming | high | 7 |
| P21 | §11 testing: timeline diff vs pump history | Reported dose timeline is diffed against the pump's own delivery history and expected IOB, so small... | Non-conforming | high | 6 |
| P22 | §2 data model | NewPumpEvent/DoseEntry fields are populated with the documented semantics: type, startDate/endDate (TBR... | Non-conforming | high | 8 |
| P23 | §3 transitions: never happened / zero-delivery cancel | A dose that never happened or was canceled with zero delivery stops being sent (with... | Non-conforming | high | 6 |
| P24 | §8 DoseStore consequences | Event dates and ordering are chosen so DoseStore behaves predictably: pumpEventQueryAfterDate only... | Partial | high | 6 |

## Findings that need action first

Many points reached the same defect from different directions. This list names each underlying defect once, with the finding ids
that describe it, the single most important code location, and the fix the findings recommend. High impact first. Details and
full evidence are in the per-point sections.

### High impact

1. **A bolus in flight across an app relaunch is lost from insulin history.** (P04-2, P05-4, P12-3, P23-5; also P15-5)
   `state.bolusDose` is persisted but the object that builds the finalizing event, `bolusProgressReport`, lives only in memory
   (`Sources/TandemKit/PumpManager/TandemPumpManager.swift:70`). After relaunch, `fetchBolusStatus` either clears the persisted
   dose silently or returns early (`TandemPumpManager+StateSync.swift:217-226`), so no finalized event is ever emitted. The
   mutable bolus emitted at enact time survives in Loop only until the next `replacePendingEvents: true` batch purges it.
   Fix: rebuild the finalizer from the persisted dose on init, and when there is a persisted `bolusDose` but no reporter,
   query `LastBolusStatus` for that bolus id and finalize with the pump's delivered volume before clearing state.

2. **A lost InitiateBolus acknowledgement leaves a possibly-running bolus untracked.** (P12-1)
   When the write times out (`TandemPumpManager.swift:564`), permission is released, a communication error is returned and
   nothing is recorded; `deliveryIsUncertain` is never set. If the pump did start the bolus, Loop has no IOB for it and may
   retry. Fix: on a nil response keep the bolus id and units in `state.bolusDose`, emit the mutable dose, flag delivery as
   uncertain, and confirm or retract from `CurrentBolusStatus` / `LastBolusStatus` on the next contact.

3. **The running bolus is never re-reported and is purged by any complete batch emitted while it runs.** (P04-1, P06-1, P13-7, P04-4)
   `getActivePumpEvents` (`TandemPumpManager.swift:1703`) returns only the temp basal, so every `replacePendingEvents: true`
   batch built while a bolus is delivering (a basal-type change seen by `fetchBasalStatus`, a suspend, a Control-IQ toggle, a
   temp basal once the time-based guard releases, a resume) omits the bolus and LoopKit deletes it. In steady state it
   reappears when the bolus completes, so IOB dips for minutes; combined with item 1 it disappears for good. The resume path
   also omits a still-recorded temp basal. Fix: make the complete-batch builder return the mutable bolus (same `raw`) and any
   live temp basal, and use it in every `true` batch including resume.

4. **Unknown delivery is finalized as a guess: cancel assumes zero, completion assumes everything.** (P05-2, P07-1, P23-2, P22-3, P23-4, P05-1, P21-2, P23-1)
   `cancelBolus` coerces a failed or mismatched `LastBolusStatus` read to `deliveredUnits = 0` and finalizes immutably
   (`TandemPumpManager.swift:639-641`); the completion path falls back to the full programmed amount
   (`TandemDoseProgressReporter.swift:33`). A mismatch is realistic on a UI-capable pump because a quick bolus or a Control-IQ
   correction can become the pump's "last bolus". The two paths also disagree on what unknown means. Fix: never finalize on a
   guess. Keep the dose mutable with the same `raw`, retry the read on the next sync, or finalize from
   `BolusCompletedHistoryLog` for that bolus id. Retract, rather than finalize at 0 U, when the pump confirms nothing was
   delivered.

5. **A resume performed on the pump is reported as a `.basal` dose, never as `.resume`.** (P10-2, P13-3)
   In `fetchBasalStatus` (`TandemPumpManager+StateSync.swift:166-173`), when the pump returns to basal after a suspend the
   driver emits a scheduled-basal dose. LoopKit's `InsulinMath.reconciled()` closes an open suspend only on a `.resume` or a
   `.tempBasal`, so the suspend stays open and basal is treated as not delivered until a later temp basal arrives. Trio
   ignores `.basal` events entirely, so it never records the resume either. The one path that does emit a resume for this
   case, `handleHomeScreenMirrorResponse`, has no callers. Fix: emit a `.resume` event (then the basal dose) whenever the
   previous recorded state is suspend and the pump reports basal or temp basal.

6. **Doses started on the pump, and Control-IQ's own dosing, are invisible on every live path, and the history path that would
   catch them is not wired.** (P02-3, P08-1, P08-2, P08-3, P20-2, P20-3, P22-4)
   `fetchBolusStatus` returns before building anything when no app-created reporter exists
   (`TandemPumpManager+StateSync.swift:226`), so a touchscreen bolus, a Mobi quick bolus or a Control-IQ correction produces no
   event; `fetchBasalStatus` has no branch for a pump-set temp rate and reports Control-IQ basal modulation as the app's
   scheduled rate. `HistoryToDoseMapper`, the only code that sets `wasProgrammedByPumpUI`, has no production caller, and both
   history flags default off. Fix: build the history emission layer; until then, treat a `CurrentBolusStatus` bolus id the app
   did not issue as a pump-UI dose (the response carries `bolusSource`), and add a `.tempBasal` branch to `fetchBasalStatus`.

7. **`lastReconciliation` follows the Loop-only-pump pattern on a UI-capable pump.** (P02-1, P02-2, P02-5, P01-A2)
   Every assignment is `Date.now` after a status read or a single accepted command (`TandemPumpManager.swift:445`,
   `TandemPumpManager+StateSync.swift:410`, and the enact, cancel, suspend and resume paths). None follows a history read,
   and the backfill watermark never feeds it. Combined with item 6 this tells Loop that delivery is fully accounted for while
   pump-side doses are unseen, which is the §6 safety pitfall in the guide. Trio ignores the parameter, so the exposure today
   is Loop-specific. Fix: keep a separate status-sync time for the UI, and pass as `lastReconciliation` only a time through
   which pump history has actually been read and reported.

8. **`hasNewPumpEvents` is not called on a quiet sync, and events emitted before the delegate attaches are dropped.** (P01-1, P18-2, P01-3, P18-5)
   `syncPumpData` stamps the driver's own boundary but never calls the delegate unless a basal type changed or a bolus
   finished (`TandemPumpManager.swift:445-457`). Loop's `DoseStore` boundary therefore lags to the last dose transition, and a
   freshly paired pump never seeds it at all. Events emitted during the pairing-time sync, before the host adopts the manager,
   are logged and discarded. Fix: emit the complete pending set (or an empty batch) at the end of every successful sync, and
   queue pre-delegate events for replay alongside the existing reservoir flush.

9. **Dose identity changes over a dose's life, and the live and history identities for the same bolus differ.**
   (P03-1, P03-2, P03-3, P11-1, P16-4, P17-2, P24-1, P03-6, P08-6)
   The bolus `raw` embeds `units`, which is the programmed amount at enact and the delivered amount at completion or cancel
   (`Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:10`, `TandemPumpManager.swift:652`,
   `TandemDoseProgressReporter.swift:44`). The temp basal `raw` embeds `programmedUnits`, which is rate times duration and
   shrinks whenever the temp basal ends early (`NewPumpEvent.swift:20`). Finalization therefore works only through the
   `replacePendingEvents` purge, the MedtrumKit pattern the guide warns against. Separately, the history mapper mints a
   different identity (`HistoryLogSyncIdentifier`) for the same bolus, so switching on history emission today would double-count
   every Loop-commanded bolus. Fix: key on values fixed at enact time, ideally the pump's bolus id or temp rate id encoded with
   `HistoryLogSyncIdentifier`, and never change the key on cancel or completion.

10. **The planned history emission floor would drop the very doses the backfill exists to find.** (P24-4)
    `HistoryBackfillPlanner.emitFloor` (`HistoryBackfillPlanner.swift:98`) is the maximum of the host's
    `startDateToFilterNewPumpEvents` and the first-seen floor. Trio's host date marches to about fifteen minutes before the
    last reported event, so a pump-UI bolus discovered on the next sync would be older than the floor and filtered out. Fix
    before the emission layer is built: floor only on the first-seen date and the store's own retention.

### Medium impact

- **Reservoir arbitration is silenced.** (P02-4) `fetchReservoirStatus` stamps `lastReconciliation` with the reservoir
  reading's own timestamp and the sync then stamps a later time, so Loop's reservoir-derived doses can never be newer than the
  reconciliation point. On a pump where event history misses pump-side doses this removes the one remaining signal.
- **`manuallyEntered` is set for a normal pump-delivered bolus.** (P22-2) `DoseEntry.bolus` sets it when the activation type is
  `manualNoRecommendation` (`Sources/TandemCore/Common/Extensions/DoseEntry.swift:24`). LoopKit and Trio use that flag for
  insulin the pump did not deliver, and it also flips between the mutable and finalized report of the same dose.
- **Delivered volume is floored to a 0.05 U grid.** (P07-2, P05-5, P19-2) The pump reports milliunits and delivers partial
  boluses; `roundToSupportedBolusVolume` floors, while the history mapper rounds to 0.001 U, so the two paths disagree.
- **Temp basal `value` and `deliveredUnits` are computed from the app's schedule, not read from the pump.** (P07-4, P11-6, P05-6,
  P07-5) The reported rate is the app's scheduled basal times the percent it requested; the pump's `currentBasalRate` is not
  consulted, and `deliveredUnits` is programmed rate times elapsed time.
- **Pump-side suspends and temp basal ends are stamped at detection time.** (P13-4, P11-4) Detection is the next sync, up to
  about five minutes later or longer after a BLE outage, so basal delivered between the real stop and detection is credited.
- **No `.prime` event is emitted for tubing or cannula fills.** (P10-5) Both flows know the volume. `.prime` is the one non-dose
  event `DoseStore` acts on, marking reservoir data non-continuous; Trio also stores it.
- **Suspend and temp basal `true` batches can drop each other.** (P04-4, P06-4) The resume path builds its batch without the
  active temp basal and overwrites a temp-basal `basalDose` without finalizing it.

### Low impact, listed for completeness

Alarms are never emitted as pump events on a live path and `alarmType` is never populated (P14-1, P14-2, P10-6). A cartridge
change is reported as `.rewind` rather than `.replaceComponent(.reservoir)` (P10-3, P14-4). No `.replaceComponent(.pump)` is
emitted when a different pump is paired (P14-5). The basal, suspend and resume `raw` strings have one-second resolution and no
discriminator (P03-5). The Linux shim cannot express `alarmType` and does not couple `raw` to `syncIdentifier` (P14-6, P03-7,
P22-6).

## Cross-cutting observations

**What conforms.** The shapes are right where the code is reached. App-commanded boluses are emitted mutable at enact time with
`replacePendingEvents: false` and finalized immutable with a pump-reported delivered volume on the normal completion path
(P05-1, P07-8, P22-1). App-commanded suspend and resume carry the right types (P10-1, P13-1, P13-2). Replacing or cancelling a
running temp basal finalizes the old one rather than overwriting it (P11-2), the temp basal record survives BLE reconnect and
app relaunch (P11-3), and a mutable temp basal re-report has a stable identity when it runs to its scheduled end (P03-4). Site
and cartridge changes are emitted with `replacePendingEvents: false` so they cannot disturb a live dose (P06-3). Failed,
unanswered and throttled syncs correctly leave `lastReconciliation` alone (P01-2, P02-7). The history-log path is designed to
the guide's rules, with pump-assigned identifiers, pump timestamps and `wasProgrammedByPumpUI` derived from the bolus id
(P03-6, P05-7), but none of it is reachable.

**Two consumers, two sets of semantics.** The guide describes Loop's `DoseStore`. TandemKit ships in Trio, whose
`DeviceDataManager` ignores both `lastReconciliation` and `replacePendingEvents`, and whose `PumpHistoryStorage` keys events by
`(event.date, type)` rather than by `raw`, updates a duplicate bolus only if the new amount is smaller, skips any temp basal
event that carries `deliveredUnits`, and ignores `.basal` events. Several findings therefore have different consequences per
host. The relaunch loss (item 1) is a lost dose in Loop but an over-count in Trio, because Trio stores the mutable bolus at its
full programmed amount immediately and never sees a smaller final. The quiet-sync and `lastReconciliation` findings (items 7
and 8) affect Loop only. The pump-side-resume finding (item 5) affects both. Point G01 audits the Trio side directly.

**Feature flags.** Everything history-related sits behind `historyBackfill` and `historyDoseReporting`, both default off
(`Sources/TandemKit/State/TandemFeatureFlags.swift`). Even with both on, the coordinator only fills the session store and
persists a watermark; there is no emission layer, so the flags change nothing about what Loop or Trio receive today. The
existing documentation in `CLAUDE.md` states this accurately. `docs/tandemkit-history-integration-plan.md` sketches the
emission layer with a `replacePendingEvents: true` batch; as drawn it would need to include the live bolus and temp basal or it
would purge them (P06 open question).

**Dependence on the LoopKit variant.** `decisionId` exists only in `loopkitdev/LoopKit` `next-dev`. The fork Trio pins has no
such field and neither does the Linux shim, so P09 is not applicable today. When TandemKit adopts a LoopKit with `decisionId`,
the enact signatures change and the id needs to be carried on `UnfinalizedDose` and persisted, alongside the bolus id that
already is (P09-2). The shim also lacks `alarmType` on `NewPumpEvent` and does not derive `syncIdentifier` from `raw`, so
Linux tests cannot observe two of the behaviours the guide depends on (P03-7, P14-6, P22-6).

**Contradictions and near-contradictions between points.** The auditors did not contradict each other on facts, but they
weighted the same facts differently. P09 scored `decisionId` as not applicable while also flagging the `activationType`
surrogate as lossy (P09-3), and P22-2 treats the same `manuallyEntered` mapping as a defect; the two are consistent once P09-3 is
read as forward-looking. P17-3 scores "the driver never re-reports an in-progress dose" as not applicable to a test point,
while P04-1 scores the same fact as a high non-conformance; P04's reading is the one that matters for accounting. P23-1 rates
finalizing a truly zero-delivery cancel as 0 U immutable at medium because IOB is unaffected, while P23-2 rates the same code
high because the 0 U also swallows a failed read; both are right about different inputs to the same line.

**Dead and unreachable code that would matter if reached.** `handleHomeScreenMirrorResponse` emits the correct suspend to
resume transition but has no callers and wraps the resume dose in `NewPumpEvent.basal` (P10-2, P06-4). `HistoryToDoseMapper`
is correct in shape and untested in situ. Deciding whether these are to be wired or removed changes where several fixes belong.

**Documentation accuracy.** `CLAUDE.md` is accurate about the history layer not being wired and about the feature flags. The
`HistoryBackfillPlanner` comment that events below the host floor "are discarded on arrival" does not describe the
Trio-pinned `DoseStore`, which purges only by age (P24-4).

**Open questions that need hardware or firmware knowledge.** Whether `CurrentBasalStatusResponse` reports `.suspend` during a
Basal-IQ or Control-IQ zero-basal period and during an occlusion alarm; whether `SuspendPumping` cancels a running bolus and
how `CurrentBolusStatus` then reports it; whether `LastBolusStatus.timestamp` is start or completion time; whether a
`.bolusChange` qualifying event fires for quick-bolus and Control-IQ boluses on all firmware; whether `SetTempRateRequest`,
marked Mobi-only in the message registry, works on a t:slim X2; and whether `LastBolusStatusV3` is required on newer Mobi
firmware. Each is listed under the point that raised it.

## Suggested test additions

All seven testing recommendations in §11 of the guide are unmet (P15 to P21). The common blocker is the test double:
`Tests/TandemKitTests/MockPumpManagerDelegate.swift` records the events passed to `hasNewPumpEvents` but discards
`lastReconciliation` and `replacePendingEvents` and does not count calls, so none of the §11 assertions can be written against
it today (P06-6, P15-4, P16-3, P17-1, P18-4). The existing `StubPumpBluetooth` can drop or substitute responses but cannot
model a disconnect and reconnect (P15-3). In order:

1. **Extend the mock delegate** to record, per call, the events, `lastReconciliation` and `replacePendingEvents`, and to expose
   a call count. Every item below depends on this.
2. **Empty sync.** Drive `syncPumpData` with a stub that answers every status request with unchanged values and assert that
   `hasNewPumpEvents` is called with an empty (or complete-pending) batch and a `lastReconciliation` later than before; assert it
   is not called when the pump answers nothing (P18).
3. **Bolus lifecycle identity.** Enact a bolus, complete it with a stubbed `LastBolusStatus` that reports less than the
   programmed amount, and assert the `raw` bytes of the mutable and finalized events are identical, `isMutable` flips, and
   `deliveredUnits` equals the stubbed pump volume. Repeat for cancel at several delivered amounts (P16, P17, P03).
4. **Failed delivery read.** Cancel and complete a bolus with the `LastBolusStatus` response omitted, and with a response
   carrying a different bolus id, and assert the dose stays mutable rather than finalizing at 0 U or at the programmed total
   (P05, P07, P23).
5. **Relaunch mid-bolus.** Construct a manager from the `rawValue` of a state that holds an in-progress `bolusDose`, run a
   sync, and assert a finalized event with the same `raw` reaches the delegate (P12, P15, P23).
6. **Lost InitiateBolus acknowledgement.** Swallow the `InitiateBolusResponse` and assert the bolus is registered as mutable
   and marked uncertain, then confirmed or retracted on the next status read (P12).
7. **Complete batches.** With a bolus in progress, trigger a basal-type change, a suspend and a resume, and assert every
   `replacePendingEvents: true` batch contains the mutable bolus and any live temp basal (P04, P06, P13).
8. **Temp basal lifecycle.** Enact, then replace early, cancel, and let one expire; assert stable `raw`, correct `endDate`, and
   `deliveredUnits` rounded to the pump increment (P11, P16, P19).
9. **Pump-side transitions.** Stub `CurrentBasalStatus` through basal to suspend to basal and assert a `.suspend` then a
   `.resume` event; stub a pump-set temp rate and assert a `.tempBasal` event with `wasProgrammedByPumpUI` true (P10, P13, P08).
10. **External bolus.** Stub `CurrentBolusStatus` as delivering a bolus id the app never issued and assert it is reported with
    `wasProgrammedByPumpUI` true and finalized from `LastBolusStatus`; when the history emission layer exists, drive a
    `BolusCompletedHistoryLog` through `HistoryBackfillCoordinator` to `hasNewPumpEvents` (P20).
11. **Rounding.** Unit-test `roundToSupportedBolusVolume`, `roundToSupportedBasalRate`, `TandemPumpCapabilities.supportedBasalRates`
    and `TandemDoseProgressReporter` against the pump's increments, and the milliunit conversions in the bolus and temp rate
    messages (P19).
12. **Timeline diff.** Once history emission exists, add an integration test that replays a recorded history log against the
    live-path events for the same period and asserts no dose is missing or duplicated (P21).

## Per-point detail

Points P01 to P24 follow the guide. G-points are gaps found by the completeness pass and by reading the host app.

### P01. hasNewPumpEvents is called on every sync with the pump, even when there are no new doses, so lastReconciliation advances

Guide section: §9 item 1 (with §1, §6, §8).

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 1 of 2 verifier passes completed

TandemKit does not call hasNewPumpEvents on every sync. syncPumpData (the body behind ensureCurrentPumpData) stamps state.lastReconciliation = Date.now after a responsive pump and returns it via lastSync/completion, but never calls emitPumpEvents itself and there is no hasNewPumpEvents(events: []) anywhere in Sources. The delegate is reached only when fetchBasalStatus sees a basal-type transition or fetchBolusStatus sees a bolus finish, so in steady state the host's DoseStore lastPumpEventsReconciliation lags to the last dose transition while the driver's own lastSync advances. After fresh pairing the first sync typically emits nothing (nil stays nil), pre-delegate emissions are dropped without replay, and a BLE reconnect triggers no sync. Failed/unanswered syncs correctly leave the boundary alone.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P01-1 | Non-conforming | medium | verified | syncPumpData never reports to DoseStore on a no-change sync |
| P01-2 | Conforms | none | verified | Failed, unanswered, throttled or stood-down syncs |
| P01-3 | Non-conforming | medium | verified | First sync after pairing: nil boundary and pre-delegate drops |
| P01-4 | Partial | low | verified | BLE auto-reconnect does not sync or report |
| P01-5 | Partial | low | verified | Throttle keyed on a timestamp that command paths also stamp |
| P01-6 | Non-conforming | none | verified | No test covers delegate calls during a sync |
| P01-A1 | Partial | low | unverified | Qualifying-event fetches stamp lastReconciliation with no delegate call |
| P01-A2 | Partial | medium | unverified | Host boundary advances via enact path only while Loop is enacting; not under Control-IQ |

**P01-1 syncPumpData never reports to DoseStore on a no-change sync** (Non-conforming, impact medium, verified)

All 14 emitPumpEvents call sites are transition-driven (enact/cancel/suspend/resume/Control-IQ toggle, cartridge/site change, basal-type change, bolus completion). syncPumpData runs fetchReservoirStatus, fetchBatteryStatus, fetchBolusStatus(fromSync:), fetchBasalStatus, fetchNotifications, fetchTimeSinceReset and fetchCGMSessionStatus; on a steady-state cycle none of these emits, so the sync ends with notifyDelegateStateUpdated and completion only. The driver's own boundary (state.lastReconciliation, returned by lastSync) advances every ~5 minutes while the host's DoseStore.lastPumpEventsReconciliation stays at the last dose transition. In Loop that leaves the reservoir-vs-events arbitration point and the InsulinDeliveryStore save range stale between transitions; the pinned LoopKit fork would honour an empty call exactly as the guide describes.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:445` self.state.lastReconciliation = Date.now — stamped after status reads, no emitPumpEvents follows
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:457` completion(self.state.lastReconciliation) ends the sync; delegate never called in this function
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:141` if activeBasalType != state.basalDose.type { — the only sync-path gate on emitting basal events
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:268` emitPumpEvents(events) — only when response.bolusId == 0 (bolus just finished)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1743` lastReconciliation: self.state.lastReconciliation — the value only reaches the host piggybacked on a dose emission

- Recommendation: At the end of the successful branch of syncPumpData (after line 445), call emitPumpEvents(getActivePumpEvents(), replacePendingEvents: true) or at minimum emitPumpEvents([]) so every sync carries the new lastReconciliation to the host. Do the same in handleQualifyingEvents after runFetch.

- Verifier notes:
  - [code:confirm] Verified: syncPumpData stamps lastReconciliation at 445 and calls only notifyDelegateStateUpdated/completion; every emitPumpEvents site (13, not 14) is transition-driven; pinned DoseStore sets lastPumpEventsReconciliation before the empty guard. Caveat on the fix: getActivePumpEvents returns only the temp basal (1701), so emitting it with replacePendingEvents:true during a mutable bolus would purge that bolus at the host — emit [] or include the bolus.

**P01-2 Failed, unanswered, throttled or stood-down syncs** (Conforms, impact none, verified)

Every path that ends a sync without talking to the pump (connect failure, zero responses via the responseCount guard, a sync already in flight, the watchdog timeout that returns the captured prior value, and the 4.5-minute short-circuit) returns the previous lastReconciliation and does not call the delegate. This is the correct side of the guide's safety pitfall: the trust boundary is never advanced past a point the pump did not answer for. These paths are pinned by tests. This finding only certifies the negative cases; the positive case is P01-1.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:409` completion(self.state.lastReconciliation) on connect failure — no stamp, no emit
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:447` "Sync got no response from the pump; leaving lastSync where it was"
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:392` completion?(state.lastReconciliation) when onlyIfIdle stands down
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:78` "A failed sync must not advance lastReconciliation"
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:140` unanswered sync leaves lastReconciliation at previousSync

- Recommendation: Keep this behaviour when adding the every-sync emission in P01-1: the new call must sit inside the responseCount > responsesBefore branch so an unanswered sync still leaves DoseStore's boundary untouched.

- Verifier notes:
  - [code:confirm] All negative paths verified: onlyIfIdle stand-down (392), connect failure (409), responseCount guard (444-448), watchdog returns captured prior value (400-401). None stamps or emits. Tests at ConnectionTests 63-78 and 122-140 pin the state and completion values.

**P01-3 First sync after pairing: nil boundary and pre-delegate drops** (Non-conforming, impact medium, verified)

On a freshly paired pump state.lastReconciliation is nil and basalDose defaults to a synthetic .basal dose. If the pump is in normal basal delivery (the common case) the first fetchBasalStatus sees no type change and emits nothing, and no bolus is finishing, so the first sync ends with lastReconciliation stamped locally but DoseStore never told; per the guide, a nil lastPumpEventsReconciliation blocks any pump-event dose from reaching the InsulinDeliveryStore until the first dose transition is emitted. Separately, the pairing-time sync runs before the delegate is attached; emitPumpEvents drops events in that window with only a warning, and deliverStateMissedByTheDelegate replays state and the reservoir reading but not pump events, so a suspend or finished-bolus emitted during pairing is lost.

- Evidence:
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:199` lastReconciliation = nil when absent from raw state
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:161` basalDose = .defaultBasalDose(...) — type .basal before any pump read
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:142` if activeBasalType == .basal, state.basalDose.type == .resume { return } — .basal == .basal also skips the whole block
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1736` "No pump delegate, not notifying..." — events dropped, no queue/replay
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:421` "the pairing sync runs before the host adopts the manager" — reservoir gets a flush, pump events do not

- Recommendation: Emit on every successful sync (P01-1) so the first post-pairing sync seeds the host boundary; queue events emitted while pumpDelegate.delegate is nil and flush them from deliverStateMissedByTheDelegate, mirroring flushPendingReservoirReading.

- Verifier notes:
  - [code:confirm] Verified: rawValue init leaves lastReconciliation nil (199); defaultBasalDose builds a basalRate dose so type is .basal (UnfinalizedDose 221-223) and fetchBasalStatus skips on equality (141); emitPumpEvents drops with a warning when delegate is nil (1735-1737); deliverStateMissedByTheDelegate replays only state and reservoir (303-308); onboarding calls syncPumpData before adoption (ScanViewModel 91). DoseStore 968 returns [] while the boundary is nil.

**P01-4 BLE auto-reconnect does not sync or report** (Partial, impact low, verified)

A reconnect completes a JPake/authenticated setup and one TimeSinceResetRequest, then only flips isConnected and notifies state. No status read, no lastReconciliation stamp and no hasNewPumpEvents happens until Loop's next ensureCurrentPumpData passes the 4.5-minute throttle. Any bolus that completed or basal change that occurred during the outage is therefore reported only if the next poll happens to observe a transition (fetchBolusStatus reconciles a stale bolus at StateSync:207-208; fetchBasalStatus catches suspend/basal flips but silently ignores a pump-side temp rate, StateSync:151-186). Not calling the delegate on reconnect is not itself a §9-1 violation (reconnect is not a sync), but combined with P01-1 the host boundary can lag a full outage plus a cycle. The docs describing a reconnect-triggered history fetch are stale.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemBluetoothManager.swift:426` ensureConnected { error in ... "Auto-reconnected completed!" } — no syncPumpData
  - `Sources/TandemKit/PumpManager/TandemBluetoothManager.swift:494` didDisconnectPeripheral auto-reconnect path likewise only reconnects
  - `Sources/TandemKit/PumpManager/TandemPeripheralManager.swift:589` pumpManager.state.isConnected = true after TimeSinceResetRequest; finishSetup(nil) with no sync
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:360` 4.5-minute throttle decides when the next poll actually reaches the pump
  - `docs/tandemkit-history-integration-plan.md:38` claims reconnects call trigger(kind: .history) — no such code exists at HEAD

- Recommendation: After a successful auto-reconnect (both TandemBluetoothManager paths), kick syncPumpData(onlyIfIdle: true) so reconnection itself produces a delegate call with a fresh lastReconciliation; update docs/tandemkit-history-integration-plan.md line 38.

- Verifier notes:
  - [code:confirm] Verified both auto-reconnect closures only log (426-432, 494-499); peripheral setup ends with isConnected=true and finishSetup(nil) (589-594); no syncPumpData is called from TandemBluetoothManager or TandemPeripheralManager; no trigger(kind: .history) exists in Sources, so docs line 38 is stale. Pump-side temp rate claim holds: basalModifiedBitmask 0x02 maps to .tempBasal and fetchBasalStatus has no branch for it.

**P01-5 Throttle keyed on a timestamp that command paths also stamp** (Partial, impact low, verified)

state.lastReconciliation is written by seven command paths and by the reservoir read, none of which reads bolus/basal status or history, yet ensureCurrentPumpData treats any value under 4.5 minutes old as "already in sync" and returns it with no pump contact and no delegate call. Loop issues enactTempBasal ~10-40 s after each poll, so the next poll lands 4m20s-4m50s after the stamp; a slow enact can therefore suppress the following sync entirely, stretching the real status cadence to ~10 minutes. On app relaunch the persisted value has the same effect for the first poll. The completion hands the host a lastSync date that DoseStore may never have received. This degrades the every-sync cadence the guide relies on rather than violating it outright.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:360` if let lastSync = state.lastReconciliation, Date.now.timeIntervalSince(lastSync) < .minutes(4.5) { ... return }
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:775` self.state.lastReconciliation = dose.startDate in enactTempBasal — no status/history read
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:596` enactBolus stamps lastReconciliation = Date.now at initiation
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:410` fetchReservoirStatus stamps lastReconciliation from a reservoir read alone
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:196` lastReconciliation restored from persisted raw state on relaunch

- Recommendation: Track the last status-sync time separately from lastReconciliation (e.g. lastStatusSyncAt set only in syncPumpData) and throttle on that; stop stamping lastReconciliation from fetchReservoirStatus, or emit on that path too.

- Verifier notes:
  - [code:confirm] Verified the seven command stamps (596, 655, 740, 775, 825, 907, 1328) and the reservoir stamp (StateSync 410); ensureCurrentPumpData returns without pump contact or delegate call when the stamp is under 4.5 minutes old (360-364); the persisted value is restored on relaunch (196-197). The cadence arithmetic depends on host timing, so medium confidence is appropriate.

**P01-6 No test covers delegate calls during a sync** (Non-conforming, impact none, verified)

The guide's §11 asks drivers to confirm that a sync with no new doses still advances lastReconciliation at the host. The test suite pins the driver-side state (advance on one response, hold on none, hold on connect failure) but no test in the five files that call syncPumpData/ensureCurrentPumpData attaches MockPumpManagerDelegate and asserts a hasNewPumpEvents call or the lastReconciliation argument it carried. This is why the gap in P01-1 is invisible to CI.

- Evidence:
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:119` XCTAssertEqual(reportedLastSync, manager.state.lastReconciliation) — only state/completion asserted
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:128` mock records hasNewPumpEvents into pumpEvents, but no sync test attaches it
  - `Tests/TandemKitTests/TandemPumpManagerTelemetryTests.swift:133` XCTAssertNotNil(manager.state.lastReconciliation) after reservoir fetch, no event assertion

- Recommendation: Add a test that stubs the sync reads, attaches MockPumpManagerDelegate, runs syncPumpData, and asserts exactly one hasNewPumpEvents call whose lastReconciliation equals manager.state.lastReconciliation; add the mirror test that an unanswered sync makes no call.

- Verifier notes:
  - [code:confirm] Verified and stronger than stated: a case-insensitive grep of Tests/ for pumpEvents/hasNewPumpEvents matches only MockPumpManagerDelegate (recorder) and a startDateToFilterNewPumpEvents reference in HistoryBackfillCoordinatorTests. No test asserts a hasNewPumpEvents call or its lastReconciliation argument on any path, sync or otherwise.

**P01-A1 Qualifying-event fetches stamp lastReconciliation with no delegate call** (Partial, impact low, unverified, added by a verifier)

Beyond the command paths in P01-5, unsolicited qualifying events also move the driver boundary without telling the host. `.remainingInsulin`, `.pumpSuspend` and `.pumpResume` all map to `.reservoirStatus`, so `fetchReservoirStatus` stamps `lastReconciliation` on the pump's schedule (e.g. a low-cartridge event) with no `hasNewPumpEvents` call, and the stamp then arms the 4.5-minute short-circuit in `ensureCurrentPumpData`. `handleQualifyingEvents` itself never emits or stamps; it relies on the individual fetches, of which only `fetchBasalStatus` (on a type change) and `fetchBolusStatus` (on completion) emit. The pumpSuspend/pumpResume addition of `.basalStatus` matches CLAUDE.md and does emit the suspend/resume when the type actually changed.

- Evidence:
  - `Sources/TandemCore/Messages/QualifyingEvent/QualifyingEvent.swift:178` case .remainingInsulin: return [InsulinStatusRequest()]
  - `Sources/TandemKit/PumpManager/QualifyingEventFetch.swift:50` case is InsulinStatusRequest: -> .reservoirStatus
  - `Sources/TandemKit/PumpManager/QualifyingEventFetch.swift:78` if !events.isDisjoint(with: [.pumpSuspend, .pumpResume]) { needed.insert(.basalStatus) }
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1659` for fetch in fetches { self.runFetch(fetch) }; completion() — no stamp, no emit of its own
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:410` fetchReservoirStatus stamps lastReconciliation

- Recommendation: Treat qualifying-event handling like a sync: after the fetches run successfully, emit with the current lastReconciliation (or stop stamping from fetchReservoirStatus), so pump-initiated reads cannot advance the driver boundary silently or suppress the next poll.

**P01-A2 Host boundary advances via enact path only while Loop is enacting; not under Control-IQ** (Partial, impact medium, unverified, added by a verifier)

Both branches of `enactTempBasal` stamp and emit, so in ordinary closed-loop operation the host's `lastPumpEventsReconciliation` does advance roughly once per cycle as a side effect of Loop's own dosing, which bounds the practical exposure of P01-1. That bound disappears exactly where it matters most: with `useControlIQ` true, `enactTempBasal` is refused outright and automatic boluses are refused, so no enact path runs and the pump is delivering autonomous corrections and basal modulation on its own. In that mode the host boundary moves only on suspend/resume, bolus completion or a Control-IQ toggle, while the driver's own `lastSync` advances every ~5 minutes. The same holds in open loop and on cycles where Loop decides no new temp basal is needed.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:673` guard !state.useControlIQ else { — enactTempBasal refused under Control-IQ
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:517` if state.useControlIQ, activationType.isAutomatic { — automatic boluses refused
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:740` lastReconciliation = Date.now then emitPumpEvents on the cancel/100% branch
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:775` lastReconciliation = dose.startDate then emitPumpEvents on the set-temp branch

- Recommendation: When implementing the every-sync emission, verify it specifically in a Control-IQ configuration (useControlIQ true) where no enact path runs, since that is the operating mode with no incidental boundary advance today.

Open questions raised by this point:

- How Trio's DeviceDataManager consumes lastReconciliation is not on disk: Trio stores pump events in its own PumpHistoryStorage rather than LoopKit's DoseStore, so the practical effect of the missing per-sync call in Trio (versus Loop) needs confirmation from Trio's source before the safety impact of P01-1 is finalized.
- Loop is believed to seed DoseStore.lastPumpEventsReconciliation from pumpManager.lastSync at startup (DoseStore.init takes it as a parameter at loopkit-trio/DoseStore.swift:203); if so, a relaunch would import the driver's status-ping timestamp as the trust boundary. Verify against the host app.
- §6 archetype: lastReconciliation is stamped after status reads only. History reading exists behind the historyBackfill flag (default false, TandemFeatureFlags.swift:32-39) and even when on emits nothing (HistoryBackfillCoordinator.swift:9-10; CLAUDE.md:541). Whether the status-sync timestamp is an acceptable lastReconciliation for a UI-capable pump belongs to P02.
- fetchBasalStatus (StateSync.swift:151-186) handles only .suspend and .basal transitions; a pump-side temp rate (.tempBasal from the t:slim X2 UI) is neither emitted nor stamped. That is an external-dose gap for P07/P08 rather than this point.
- handleHomeScreenMirrorResponse (StateSync.swift:473-514) emits without stamping lastReconciliation, but QualifyingEventFetch never issues HomeScreenMirrorRequest, so this path appears dead; confirm no other caller exists.
### P02. A current, correct lastReconciliation is always passed: for a UI-capable pump this must be the time of the last full history read/reconcile, never advanced past delivery that has not actually been accounted for

Guide section: §9 item 2 (with §6).

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

TandemKit treats lastReconciliation as a Loop-only-pump "last status poll" timestamp, but Tandem is UI-capable (t:slim X2 touchscreen, Mobi quick-bolus and Tandem app, Control-IQ automatic boluses and basal modulation). Every assignment is Date.now after a status read or a single successful command; none follows a history read, and the history backfill watermark (behind the default-off historyBackfill flag, with no dose-emission layer) never feeds it. The status poll cannot see pump-UI or Control-IQ boluses (fetchBolusStatus exits when no app-initiated bolus is tracked), so the boundary is routinely advanced past unaccounted delivery. Because the stamp also lands after the reservoir read, DoseStore's reservoir fallback is permanently disabled. The no-response guard, failed-sync handling and persistence across relaunch are correct.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P02-1 | Non-conforming | high | unverified | Archetype: status-poll timestamp used for a UI-capable pump |
| P02-2 | Non-conforming | high | unverified | History watermark never feeds lastReconciliation; flags default off |
| P02-3 | Non-conforming | high | unverified | Status poll cannot observe pump-UI or Control-IQ doses |
| P02-4 | Non-conforming | medium | unverified | Reservoir arbitration defeated by stamping after the reservoir read |
| P02-5 | Non-conforming | medium | unverified | Command paths stamp reconciliation on a single round trip |
| P02-6 | Partial | low | unverified | lastReconciliation doubles as sync-freshness and connection-staleness gate |
| P02-7 | Conforms | none | unverified | No-response guard, failed sync and relaunch persistence |

**P02-1 Archetype: status-poll timestamp used for a UI-capable pump** (Non-conforming, impact high, unverified)

The guide (§6) and the LoopKit protocol doc TandemKit builds against both say a pump with its own UI and dosing history must set lastReconciliation to the time of a full history read/reconcile. Tandem qualifies: the X2 lets the user bolus, set temp rates and suspend on the pump; the Mobi has a quick-bolus button and Tandem's phone app; Control-IQ delivers automatic corrections on both. TandemKit instead stamps Date.now whenever any status request was answered (line 445) or a reservoir value was read (line 410) — the OmnipodKit/MedtrumKit Loop-only pattern. No code path ties the value to pump history. This holds in steady state, on the first post-pairing sync, after BLE reconnect and after relaunch.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:445` syncPumpData: `self.state.lastReconciliation = Date.now` after status reads only (reservoir/battery/bolus/basal/notifications)
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:410` fetchReservoirStatus: `state.lastReconciliation = timestamp` on every reservoir read, including qualifying-event reads
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1743` emitPumpEvents passes `lastReconciliation: self.state.lastReconciliation` on every delegate call
  - `reference: loopkit-trio/PumpManager.swift:61` Trio-pinned LoopKit: UI-capable pumps must reflect 'the last time we reconciled fully with pump history'

- Recommendation: Introduce a distinct `lastHistoryReconciliation` set only when a history read through the pump's current lastSequenceNum has completed and its doses have been reported; pass that (not the status-poll time) as lastReconciliation. Keep the status-poll time as a separate `lastStatusSync` for `lastSync`/UI.

**P02-2 History watermark never feeds lastReconciliation; flags default off** (Non-conforming, impact high, unverified)

The only history-reading machinery is HistoryBackfillCoordinator, gated on the default-off `historyBackfill` flag. Even when enabled it fills an in-memory store and advances `HistoryBackfillState.watermark`; nothing maps stored logs to NewPumpEvents (HistoryToDoseMapper has no caller) and nothing derives lastReconciliation from the watermark or the tick outcome. The tick is kicked after lastReconciliation has already been set to now (455 follows 445), so a history read that later fails or is skipped has no effect on the boundary already reported. The docs acknowledge this as unfinished. So under every flag combination lastReconciliation is independent of history.

- Evidence:
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:36` `.historyBackfill, .historyDoseReporting: return false` — both default off
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:9` "Nothing is mapped to doses or emitted here — that is the emission layer's job"
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:379` persist() writes only `pumpManager.state.historyBackfill = bookkeeping`, never lastReconciliation
  - `CLAUDE.md:541` "gap-aware `lastReconciliation` advancement all remain to be done"
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:455` runTick() is fire-and-forget after lastReconciliation was already stamped at 445

- Recommendation: When the emission layer lands, set lastReconciliation from the tick outcome: the pump-time (clock-reconciled) of the newest entry read, only if sessionCovered reaches lastSequenceNum with no store gaps and mapped doses were emitted. Until then, do not present the status-poll time as reconciliation.

**P02-3 Status poll cannot observe pump-UI or Control-IQ doses** (Non-conforming, impact high, unverified)

This is the concrete §6 pitfall. A quick-bolus on the Mobi, a touchscreen bolus on the X2, or a Control-IQ automatic correction produces no NewPumpEvent: fetchBolusStatus returns early when there is no app-created progress reporter, LastBolusStatus is only queried for a known bolusId, and fetchBasalStatus keys on basal *type*, not rate. Yet the same syncPumpData pass stamps lastReconciliation = now, telling DoseStore that delivery is fully accounted for up to that instant. Loop/Trio then under-counts IOB by the entire external dose. The reservoir fallback that could partially compensate is also disabled (P02-4). The `.bolusChange` hook only fills the history store.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:226` fetchBolusStatus: `guard let progressReport = bolusProgressReport else { return }` — a bolus the app did not start is ignored
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:141` fetchBasalStatus only emits when `activeBasalType != state.basalDose.type`; Control-IQ rate modulation within `.basal` is invisible
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:517` enactBolus blocks only `activationType.isAutomatic` under Control-IQ; manual boluses and Control-IQ's own doses coexist
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1637` .bolusChange qualifying event runs a backfill tick, but nothing emits from it

- Recommendation: Until history-derived dose emission exists, do not advance lastReconciliation past a point where an unobserved bolus could have occurred; at minimum, detect LastBolusStatus.bolusId changes or `.bolusChange` events and hold the boundary (or report the dose) before stamping.

**P02-4 Reservoir arbitration defeated by stamping after the reservoir read** (Non-conforming, impact medium, unverified)

DoseStore supplements IOB from reservoir drops only when the last reservoir reading is *newer* than lastPumpEventsReconciliation. TandemKit stamps lastReconciliation with the reservoir timestamp itself (equal, so not newer) and then, in syncPumpData, with a later Date.now. The reservoir reading is therefore always older than or equal to the reconciliation date, and reservoir-derived doses are never used. For a Loop-only pump this would be harmless; for Tandem, where event history misses pump-UI and Control-IQ doses (P02-3), the reservoir path was the only remaining signal that could reveal them, and the stamping order silences it.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:410` reservoir read: `state.lastReconciliation = timestamp` equals the reservoir value's own startDate
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:437` fetchReservoirStatus() runs first in the sync; line 445 then stamps a later Date.now
  - `reference: loopkit-trio/DoseStore.swift:1217` reservoir doses used only if `reservoirEndDate > self.lastPumpEventsReconciliation`

- Recommendation: Stop setting lastReconciliation in fetchReservoirStatus, and record the reservoir reading after (or with a later timestamp than) whatever reconciliation value is reported, so DoseStore can use reservoir data past the trust boundary as the guide describes.

**P02-5 Command paths stamp reconciliation on a single round trip** (Non-conforming, impact medium, unverified)

enactBolus, cancelBolus, enactTempBasal (both branches), suspendDelivery, sendResumePumping, configureControlIQMode and the basal/bolus state-change handlers each set lastReconciliation to now after one accepted command. A command acknowledgement proves the link works and that this one dose was accepted; it does not account for anything else the pump did since the last stamp. enactBolus stamps before a single unit is delivered, then emits the mutable dose with replacePendingEvents:false. The `dose.startDate` at 775 is just Date.now captured a few lines earlier, so it is not a distinct semantic, but it shows the value is being used as 'time of my last action' rather than 'time delivery is accounted through'.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:596` enactBolus: `self.state.lastReconciliation = Date.now` immediately after InitiateBolusRequest, before delivery
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:775` enactTempBasal: `self.state.lastReconciliation = dose.startDate` (UnfinalizedDose sets startDate = Date.now)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:655` cancelBolus stamps Date.now; likewise 740, 825, 907, 1328
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:265` fetchBolusStatus finished: stamps Date.now after LastBolusStatus for the app's bolus only

- Recommendation: Remove lastReconciliation writes from command paths; commands should emit their dose with the existing (unchanged) reconciliation value. Advance the boundary only from the reconciliation routine.

**P02-6 lastReconciliation doubles as sync-freshness and connection-staleness gate** (Partial, impact low, unverified)

The same field drives three unrelated behaviours: the trust boundary handed to DoseStore, the 4.5-minute poll suppression, and the 15-minute 'no recent sync' banner. That coupling is why every status read stamps it. If the value were corrected to a history-reconcile time (which will lag, be nil while historyBackfill is off, or stall while a backfill is failing), ensureCurrentPumpData would poll on every call and the troubleshooting UI would show a false connection problem. Conversely, keeping it as a poll timestamp to serve those gates is exactly what makes the reported reconciliation wrong. This is a design constraint the fix for P02-1 must address, not an independent accounting bug.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:360` ensureCurrentPumpData short-circuits when `Date.now.timeIntervalSince(lastSync) < .minutes(4.5)`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:234` `public var lastSync: Date? { state.lastReconciliation }`
  - `Sources/TandemKit/PumpManager/PumpConnectionIssue.swift:46` `return .noRecentSync` when lastReconciliation older than 15 min

- Recommendation: Split into `lastStatusSync` (feeds lastSync, the 4.5-min gate and PumpConnectionIssue) and `lastReconciliation` (feeds hasNewPumpEvents only), persisting both.

**P02-7 No-response guard, failed sync and relaunch persistence** (Conforms, impact none, unverified)

Within its (incorrect) status-poll semantics, the driver does not fabricate trust: a sync on a link that answers nothing leaves the value alone, a failed connect reports the previous value, and the value survives relaunch so the first post-relaunch emitPumpEvents carries the genuinely old date rather than nil or now. After a BLE reconnect, performInitialSetup only sets isConnected (TandemPeripheralManager.swift:589) and does not stamp; the next Loop poll does. These are the right mechanics and should be retained when the value's source is corrected. Note they do not cure P02-1..P02-5: an answered poll still advances past unseen pump-side delivery.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:444` `if self.bluetooth.responseCount > responsesBefore` guards the stamp; else logs 'leaving lastSync where it was'
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:409` connect failure: `completion(self.state.lastReconciliation)` returns the previous value, not nil or now
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:196` lastReconciliation decoded from rawValue; encoded at line 365
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:78` asserts 'A failed sync must not advance lastReconciliation'

- Recommendation: Keep the responseCount guard, previous-value-on-failure and persistence; add a test that a sync during which LastBolusStatus reports an unknown bolusId does not advance the boundary once P02-3 is addressed.

Open questions raised by this point:

- P01 overlap: syncPumpData does not call hasNewPumpEvents on every sync — emitPumpEvents fires only from fetchBasalStatus/fetchBolusStatus on a state change — so lastReconciliation advances in TandemKit state without reaching DoseStore on quiet syncs, and ensureCurrentPumpData's 4.5-minute short-circuit skips the delegate entirely. Audited under P01, not here.
- Does the pump emit a `.bolusChange` qualifying event for Mobi quick-bolus and Control-IQ automatic boluses on all firmware? If not, even a future history-driven reconcile has no prompt to read before the next poll.
- Whether Control-IQ's basal modulation appears in the history log as BasalRateChangeHistoryLog/BasalDeliveryHistoryLog entries the mapper can turn into doses; HistoryToDoseMapper handles BasalRateChangeHistoryLog but the emission layer does not exist yet.
- The guide's §6 quote of the protocol doc matches the Trio-pinned LoopKit verbatim (PumpManager.swift:58-63); no divergence between the two LoopKit snapshots affects this point.
### P03. Each dose has a raw/syncIdentifier that is byte-for-byte constant for the entire life of that dose, including in-progress re-reports and cancellation

Guide section: §9 item 3 (with §4).

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

TandemKit's optimistic (Loop-commanded) doses key `raw` as "<type> <units> <ISO8601 start, second precision>". The start component is stable on every path (all call sites pass dose.startDate; no Date.now default is used; persisted UnfinalizedDose round-trips the Date). The units component is not: cancelBolus keys on deliveredUnits, bolus completion keys on the pump-reported delivered amount, and temp basals key on programmedUnits = rate x duration, which shrinks whenever a temp basal is cut short (the normal case when Loop re-issues every ~5 min). Correct end state currently depends on the replacePendingEvents:true mutable purge, not on identity. The history mapper mints stable pump-assigned ids but is not wired, and uses a different identity scheme than the optimistic path. No test asserts raw stability for the manager path.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P03-1 | Non-conforming | medium | unverified | Bolus cancellation changes raw (deliveredUnits in key) |
| P03-2 | Partial | medium | unverified | Bolus completion re-keys on pump-reported delivered volume |
| P03-3 | Non-conforming | medium | unverified | Temp basal raw derived from programmedUnits (rate x duration) |
| P03-4 | Conforms | none | unverified | Mutable temp-basal re-reports and start-date component are stable |
| P03-5 | Partial | low | unverified | Basal/suspend/resume raw has 1-second resolution and no discriminator |
| P03-6 | Partial | medium | unverified | History identity scheme differs from optimistic scheme; not yet wired |
| P03-7 | Partial | low | unverified | Linux shim omits raw-to-syncIdentifier coupling; no lifecycle test |

**P03-1 Bolus cancellation changes raw (deliveredUnits in key)** (Non-conforming, impact medium, unverified)

The initial mutable bolus is keyed on the programmed amount, but cancelBolus re-keys the same dose on the partially delivered amount (or 0 if the LastBolusStatus query fails), so the raw and therefore syncIdentifier change mid-life. This is exactly the MedtrumKit pattern the guide flags in section 4. Because the cancel batch is emitted with replacePendingEvents:true, DoseStore purges the stale mutable row by its mutable flag and InsulinDeliveryStore soft-deletes the unmatched mutable dose, so the end state is a single finalized dose. Correctness rests on that safety net rather than on identity matching: the in-progress row is deleted and a new one inserted, never updated in place.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:10` raw: "\(DoseType.bolus.rawValue) \(units) \(dateFormatter.string(from: date))"
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:599` initial report: NewPumpEvent.bolus(dose: doseEntry, units: units, date: dose.startDate) -- programmed units
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:653` cancel: .bolus(dose: canceledDose, units: canceledDose.deliveredUnits ?? 0, date: canceledDose.startDate)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:657` self.emitPumpEvents(events) -- replacePendingEvents defaults to true

- Recommendation: Key the bolus raw on the programmed amount only (pass `units: canceledDose.programmedUnits`, or better a bolusId-based HistoryLogSyncIdentifier.bolus minted at enactBolus), and finalize by flipping isMutable and setting deliveredUnits. Add a manager test asserting raw equality across enact/cancel.

**P03-2 Bolus completion re-keys on pump-reported delivered volume** (Partial, impact medium, unverified)

On natural completion the finalized event is built from getPumpEvent(actualDeliveredUnits:), whose raw units component is the pump-reported delivered volume. When the pump delivered exactly the programmed amount the string usually matches the initial report (both are Double(n)/1000 grid values), so identity holds on the happy path. It diverges whenever delivery was interrupted on the pump (occlusion, pump-UI cancel, reconciliation after BLE loss) or if the host passes an unrounded `units` value, since enactBolus does not round before keying. The mismatch is again masked only by the replacePendingEvents:true purge. Note also that after app relaunch bolusProgressReport is nil, so this completion path never runs (StateSync 217-224 clears state without emitting), which is a P04/P05 concern.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:33` let delivered = actualDeliveredUnits ?? total
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:44` units: delivered, -- raw component is the delivered, not programmed, amount
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:256` actualDelivered = queryLastBolusDeliveredVolume(bolusId: bolusId)
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:268` emitPumpEvents(events) -- replacePendingEvents true
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1881` stride(...).map { Double($0) / multiplier } -- grid values equal decimal literals, so full delivery usually matches

- Recommendation: Have getPumpEvent pass `units: total` (programmed) into the raw while still setting deliveredUnits to the pump-reported value. Round `units` with roundToSupportedBolusVolume before building the UnfinalizedDose so the key is grid-exact.

**P03-3 Temp basal raw derived from programmedUnits (rate x duration)** (Non-conforming, impact medium, unverified)

The mutable temp-basal report has endDate = estimatedEndDate, so programmedUnits = rate x full duration. Finalization via getActivePumpEvents(endDate:) uses min(endDate, estimatedEndDate), so whenever the temp basal is replaced or stopped before its programmed end (every Loop re-issue in enactTempBasal, suspendDelivery, configureControlIQMode, fetchBasalStatus, handleHomeScreenMirrorResponse) programmedUnits shrinks and the raw changes. Only a temp basal that runs to its programmed end keeps its identity. All these finalizations use replacePendingEvents:true, so the stale mutable row is purged and a new immutable row inserted; the end state is correct but each finalized TBR is a delete-plus-insert, not an update. This is the section 10 'TBR overwritten' shape the guide warns about.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:20` raw: "\(DoseType.tempBasal.rawValue) \(dose.programmedUnits) \(...date)"
  - `reference: loopkit-trio/DoseEntry.swift:73` case .unitsPerHour: return value * hours -- programmedUnits scales with endDate
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:177` var actualEndDate = isMutable ? estimatedEndDate : endDate
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` state.basalDose.toDoseEntry(isMutable: endDate == nil, endDate: endDate ?? Date.now)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:765` var events = self.getActivePumpEvents(endDate: dose.startDate) -- finalizes previous TBR early on every re-issue

- Recommendation: Key temp basals on values fixed at enact time: the rate (`dose.unitsPerHour` or UnfinalizedDose.value) plus start, or a per-dose UUID/tempRateId stored in UnfinalizedDose and persisted. Add a test that enacts, then replaces, a temp basal and asserts identical raw bytes.

**P03-4 Mutable temp-basal re-reports and start-date component are stable** (Conforms, impact none, unverified)

When a temp basal is re-reported while still running (from cancelBolus and from bolus completion), toDoseEntry(isMutable:true) uses estimatedEndDate exactly as the initial report did, so programmedUnits and the ISO8601 start string are byte-identical to the enact-time raw. Every NewPumpEvent factory call in the driver passes `date:` explicitly from the dose's own startDate; none rely on the Date.now default. ISO8601DateFormatter truncates to whole seconds, and UnfinalizedDose persists startDate as a Date, so the string is unchanged across BLE reconnect and app relaunch. The instability in P03-1/2/3 is entirely in the units component, not the timestamp.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:647` var events = self.getActivePumpEvents() -- endDate nil => isMutable true re-report
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:259` var events = getActivePumpEvents() -- same re-report at bolus completion
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1711` date: basalEntry.startDate -- explicit start, not Date.now
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:136` raw["startDate"] = startDate -- persisted as Date, restored at line 88-93
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:272` basalDose = UnfinalizedDose(rawValue: rawDoseEntry) ?? ... -- survives relaunch

- Recommendation: Keep the explicit `date: dose.startDate` discipline; if the key is redesigned, retain a start-anchored or id-anchored component and drop the mutable units component.

**P03-5 Basal/suspend/resume raw has 1-second resolution and no discriminator** (Partial, impact low, unverified)

Scheduled-basal, suspend and resume events are immutable and reported once, so per-dose constancy is trivially met. However their raw is only the type plus a whole-second timestamp. Two events of the same type inside one second collide on DoseStore's unique raw constraint and the second is silently deduplicated. The enactTempBasal 100%-percent path and suspend/configureControlIQ paths can append a scheduled-basal marker from getActivePumpEvents(endDate:) and another from their own code in one batch; only fetchBasalStatus guards against this. Basal markers carry no insulin beyond the schedule, so accounting impact is small, but a lost suspend marker in a rapid suspend/resume/suspend sequence would be more serious.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:31` raw: "\(DoseType.basal.rawValue) \(dateFormatter.string(from: date))"
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1721` events.append(NewPumpEvent.basal(... date: basalEntry.endDate)) -- appended by getActivePumpEvents
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:737` events.append(NewPumpEvent.basal(dose: dose.toDoseEntry(isMutable: false), date: dose.startDate)) -- second basal in same batch, no dedupe guard
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:167` if !events.contains(where: { $0.type == .basal }) -- guard exists only here
  - `reference: loopkit-trio/DoseEntry.swift:31` init(suspendDate: ..., isMutable: Bool = false ...) -- these are single-shot immutable events

- Recommendation: Include a discriminator (sequence counter, UUID, or sub-second component) in basal/suspend/resume raws, and reuse the fetchBasalStatus duplicate-basal guard in the other paths that append a scheduled-basal marker.

**P03-6 History identity scheme differs from optimistic scheme; not yet wired** (Partial, impact medium, unverified)

The history path is designed correctly for this point: bolus activation and completion, and temp-rate activation and completion, share a pump-assigned id in a frozen 10-byte encoding, and tests pin the golden values. But mapToEvents has no caller in Sources, nothing under History/ reaches emitPumpEvents, and historyDoseReporting has no consumer, so none of this is live. Meanwhile the optimistic path keys the same bolus as a text string despite already holding bolusId. If history reporting is wired without first migrating enactBolus to the same identity (or reconciling by bolusId before emit), a Loop-commanded bolus will appear under two identities and be double-counted. Today the impact is nil; the design gap is acknowledged in the code comment.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryLogSyncIdentifier.swift:45` Nothing emits these identifiers yet -- `NewPumpEvent`'s raw values are still built from the dose type, volume and timestamp.
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:183` let raw = HistoryLogSyncIdentifier.bolus(pumpSerial: pumpSerial, bolusId: completion.bolusId)
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:207` in-flight bolus uses the same bolusId key as its completion
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:584` bolusId: permissionResponse.bolusId -- id known at enact time but not used in raw
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:173` self[.historyBackfill] && self[.historyDoseReporting] -- both default false

- Recommendation: Before wiring history dose reporting, switch enactBolus/cancel/completion to HistoryLogSyncIdentifier.bolus(pumpSerial, bolusId) when the serial is known (fall back to the text key otherwise), and add a test that an optimistic bolus and its history confirmation share raw bytes.

**P03-7 Linux shim omits raw-to-syncIdentifier coupling; no lifecycle test** (Partial, impact low, unverified)

On Linux the shim's NewPumpEvent does not derive dose.syncIdentifier from raw the way the pinned LoopKit does, so Linux CI cannot observe the identity coupling that section 2 describes; the history mapper works around this by stamping syncIdentifier itself, but the optimistic factories in NewPumpEvent.swift do not. Separately, the mock delegate records every hasNewPumpEvents batch, yet no test inspects those events, so the raw drift in P03-1/2/3 is unguarded by any test on either platform. This is test-infrastructure quality rather than a runtime accounting defect on Apple builds.

- Evidence:
  - `LinuxShims/LoopKit/LoopKit.swift:552` self.date = date ... self.raw = raw -- dose.syncIdentifier is never set from raw
  - `reference: loopkit-trio/NewPumpEvent.swift:33` dose?.syncIdentifier = raw.hexadecimalString
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:36` var pumpEvents: [NewPumpEvent] -- recorded, but no test reads .pumpEvents or compares raw
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:192` syncIdentifier: raw.hexadecimalString -- mapper sets it explicitly to compensate

- Recommendation: Make the shim init mirror LoopKit (set dose.syncIdentifier = raw.hexadecimalString). Add lifecycle tests using MockPumpManagerDelegate that assert byte-equal raw across enact/re-report/cancel/complete for one bolus and one temp basal.

Open questions raised by this point:

- Does the host (Trio/Loop) always pass `units` to enactBolus already rounded via roundToSupportedBolusVolume? enactBolus (TandemPumpManager.swift:578-599) keys the raw on the unrounded argument while completion keys on the grid-rounded pump value; an unrounded input would break identity even on full delivery. Checking the host call site would settle it.
- Is a tempRateId available at command time (e.g. in SetTempRateResponse or TempRateResponse cargo)? If so the optimistic temp basal could use HistoryLogSyncIdentifier.tempRate; if not, a persisted per-dose UUID in UnfinalizedDose is the fallback.
- After app relaunch, bolusProgressReport is in-memory only (TandemPumpManager.swift:70) and fetchBolusStatus clears a completed bolus without emitting a finalization (StateSync.swift:217-224); the persisted mutable bolus is then purged on the next replacePendingEvents:true batch. This is a P04/P05 (re-report/finalize) concern rather than an identity one, but it means identity constancy can never be exercised across relaunch today.
- The guide (written against loopkitdev next-dev) expects decisionId threading; the pinned loopandlearn LoopKit DoseEntry has no decisionId, so that checklist item is not applicable to what TandemKit builds against today (outside P03).
- docs/tandemkit-history-integration-plan.md:295 and :596 plan 'syncIdentifier preservation' between pending doses and history; that plan is not reflected in code yet and should be reconciled with the HistoryLogSyncIdentifier design once history reporting is wired.
### P04. In-progress doses are reported with isMutable: true and re-reported on EVERY sync until they finalize; nothing mutable is silently omitted from a replacePendingEvents:true batch

Guide section: §9 item 4 (with §3 report-or-delete rule).

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

TandemKit reports only two kinds of mutable dose: the Loop-commanded bolus and the Loop-commanded temp basal. The bolus is emitted mutable exactly once (enactBolus, replacePendingEvents:false) and is never re-sent; the `.inProgress` bolusState only feeds PumpManagerStatus. Every later replacePendingEvents:true batch (basal-type change on sync, suspend, resume, Control-IQ enable, next enactTempBasal) omits it, so the Trio-pinned DoseStore purges it until finalization is detected; after an app relaunch it is cleared silently and never finalized. The TBR is not re-reported on routine syncs either, but it is finalized inside most replace:true batches, so it is only lost on the resume path. No test observes replacePendingEvents.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P04-1 | Non-conforming | high | unverified | Running bolus never re-reported; purged by any replace:true batch |
| P04-2 | Non-conforming | high | unverified | After app relaunch a persisted in-progress bolus is cleared without finalization |
| P04-3 | Partial | medium | unverified | Running temp basal not re-reported on routine syncs, but finalized in most replace:true batches |
| P04-4 | Non-conforming | medium | unverified | Resume path omits live TBR and bolus from a replace:true batch |
| P04-5 | Conforms | none | unverified | Suspend/resume/basal reported immutable; only bolus and TBR are ever mutable |
| P04-6 | Partial | medium | unverified | Estimate-based bolus guard opens the omission window before pump confirms |
| P04-7 | Non-conforming | low | unverified | No test observes replacePendingEvents or mutable re-reporting |

**P04-1 Running bolus never re-reported; purged by any replace:true batch** (Non-conforming, impact high, unverified)

The in-progress bolus is a mutable DoseEntry (deliveredUnits nil, UnfinalizedDose.swift:161) sent once with replacePendingEvents:false. Nothing re-sends it: syncs update bolusState/progress observers only, and getActivePumpEvents (1702) covers only the temp basal. While the bolus runs, realistic replace:true batches fire: a routine sync whose fetchBasalStatus sees the 30-min TBR expire (149-183), a user suspend (828), Control-IQ enable (1330), or the next enactTempBasal once the estimate-based guard releases (679). Each purges the bolus from DoseStore and the InsulinDeliveryStore. It reappears only when fetchBolusStatus sees bolusId==0 (StateSync:249-268), under a different raw (NewPumpEvent.swift:10 keys on delivered units). In between, Loop/Trio compute IOB without the bolus.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:598` only mutable bolus emission: `self.emitPumpEvents(` ... `replacePendingEvents: false`
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:236` `state.bolusState = .inProgress(dose.toDoseEntry(isMutable: true))` — status only, no NewPumpEvent
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:149` fetchBasalStatus batch `var events = getActivePumpEvents(endDate: now)` has no bolus; emitted at 161/183 with default replace:true
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:828` suspendDelivery emits [finalized TBR, suspend] with default replace:true; bolus omitted (also 910, 1330)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1733` `func emitPumpEvents(_ events: [NewPumpEvent], replacePendingEvents: Bool = true)`

- Recommendation: Include the running bolus (same raw, isMutable:true) in every batch built by getActivePumpEvents and re-emit it on every sync; or emit all intra-bolus batches with replacePendingEvents:false until the bolus is finalized.

**P04-2 After app relaunch a persisted in-progress bolus is cleared without finalization** (Non-conforming, impact high, unverified)

The manager persists bolusDose but not the progress reporter. On relaunch mid-bolus (or after a bolus whose completion event was missed), fetchBolusStatus takes the reporter-nil branch: if the pump says already-delivered it silently drops bolusDose (217-224); if still delivering it returns at 226 without re-reporting. No finalized event is ever emitted for that bolus. Its mutable row survives in DoseStore only until the first replacePendingEvents:true batch — typically the next loop cycle's enactTempBasal — and is then deleted permanently. BLE reconnect within the same process is different: performInitialSetup (TandemPeripheralManager.swift:493) runs no sync and the reporter survives, so only relaunch hits this. History backfill/emission that could recover the dose does not exist.

- Evidence:
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:60` `public var bolusDose: UnfinalizedDose?` persisted (restored at 244-247)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:70` `internal var bolusProgressReport: TandemDoseProgressReporter?` — in-memory only, nil after relaunch
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:217` `if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil` → clears bolusDose, emits nothing
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:226` `guard let progressReport = bolusProgressReport else { return }` — .delivering and finish paths unreachable without the reporter
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:778` next enactTempBasal emits with replace:true; the stale mutable bolus row is purged

- Recommendation: On init, if state.bolusDose exists, rebuild the reporter (or make finalization independent of it) and re-report the bolus mutable; on the first status read, finalize via LastBolusStatus deliveredVolume (queryLastBolusDeliveredVolume) rather than clearing silently.

**P04-3 Running temp basal not re-reported on routine syncs, but finalized in most replace:true batches** (Partial, impact medium, unverified)

The TBR is emitted mutable when enacted (772) and again only in cancelBolus and bolus-finish batches. A quiet 5-minute sync sends no hasNewPumpEvents at all, so the guide's "re-reported on every sync" is not met. However, TandemKit does not silently omit the TBR from the replace:true batches it does send: fetchBasalStatus, enactTempBasal, suspendDelivery and configureControlIQMode all call getActivePumpEvents(endDate:) first, which converts the live TBR into a finalized entry in the same batch. Under the Trio-pinned DoseStore the mutable row therefore persists between syncs and is replaced, not dropped — the exception is the resume path (P04-4). Steady-state IOB from the TBR is preserved; the gap is contractual rather than an observed loss.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` `toDoseEntry(isMutable: endDate == nil, endDate: endDate ?? Date.now)` — mutable only when endDate nil
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:648` cancelBolus `var events = self.getActivePumpEvents()` — one of two mutable re-reports (other: StateSync:259)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:437` syncPumpData calls fetchBasalStatus; nothing emits when basal type is unchanged (StateSync:141)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:736` enactTempBasal includes finalized old TBR `getActivePumpEvents(endDate: dose.startDate)` (also 771, 821, 1324)
  - `reference: loopkit-trio/DoseStore.swift:682` `guard events.count > 0 else { completion(nil); return }` — empty batches neither purge nor re-resolve

- Recommendation: Re-emit the live TBR (same raw, isMutable:true) from every syncPumpData pass, alongside the empty-batch lastReconciliation update, so the batch is always the complete pending set.

**P04-4 Resume path omits live TBR and bolus from a replace:true batch** (Non-conforming, impact medium, unverified)

sendResumePumping builds a batch of only the resume event. If state.basalDose is still .tempBasal (pump was suspended on its own UI and no sync has run since; the fill-tubing flow checks suspension against the pump rather than state), the live TBR's mutable row is purged by replacePendingEvents:true and the TBR is never finalized because state.basalDose is overwritten — insulin delivered under that TBR before the suspend disappears from Loop's history. The settings-screen resume is gated on state, so only the fill-tubing resume (and any host-app resume issued from a stale status) reaches this. Any running bolus (P04-1) is omitted here too.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:904` `let events = [NewPumpEvent.resume(dose: dose.toDoseEntry(), date: dose.startDate)]` — no getActivePumpEvents
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:906` `state.basalDose = dose` overwrites a possibly still-tempBasal basalDose, so it can never be finalized later
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:910` `emitPumpEvents(events)` — default replacePendingEvents:true
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitFillTubingViewModel.swift:128` `pumpManager?.fetchSuspendStatus` reads the pump directly, not state.basalDose
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:130` fetchSuspendStatus `completion(response.basalType == .suspend)` does not update state.basalDose

- Recommendation: Build the resume batch with getActivePumpEvents(endDate: resumeStart) like suspendDelivery does, or refresh basal state from the pump before emitting; never overwrite a .tempBasal basalDose without finalizing it.

**P04-5 Suspend/resume/basal reported immutable; only bolus and TBR are ever mutable** (Conforms, impact none, unverified)

An open suspend is reported as an immutable point event, as are resume and scheduled-basal markers. That matches the in-tree reference drivers (Omnipod/Medtrum also report suspend without a duration), so these are never at risk of the report-or-delete purge and nothing mutable of these types can be silently omitted. The guide's §3 wording ("an open suspend — all are mutable") is stricter than LoopKit's own suspend model; noted for completeness, not as a defect. The mutable surface to keep re-reporting is therefore exactly the Loop bolus and Loop TBR examined in P04-1..4.

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:197` `.suspend` → `DoseEntry(suspendDate: startDate, automatic: automatic)` — isMutable defaults false
  - `reference: loopkit-trio/DoseEntry.swift:31` `init(suspendDate:..., isMutable: Bool = false, ...)`
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:168` `.basal` DoseEntry has no isMutable argument — always immutable
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:519` `.tempBasal(basalDose.toDoseEntry(isMutable: true))` — status surface, not DoseStore

- Recommendation: No change required; keep suspend/resume immutable, consistent with reference drivers.

**P04-6 Estimate-based bolus guard opens the omission window before pump confirms** (Partial, impact medium, unverified)

enactTempBasal is blocked only while the reporter's elapsed-time estimate says the bolus is unfinished. Once the estimate completes — before the pump has confirmed via qualifying event or the deferred sync — Loop's next enactTempBasal is accepted and its replace:true batch omits the still-mutable bolus, deleting it (P04-1 mechanism) deterministically rather than only on rarer paths. If the bolusChange event was lost, the deletion persists until the next sync past the 30s grace finalizes it. With the reporter nil (P04-2) the guard is absent entirely.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:679` `if let bolusProgressReport, bolusProgressReport.isUnfinalized()` — only guard against enactTempBasal mid-bolus
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:58` `deliveredUnits < total` where deliveredUnits is elapsed-time estimate (line 77)
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:198` sync finalization deferred until `estimatedEndDate + 30s`; a lost bolusChange event is never replayed (comment 192-193)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:771` enactTempBasal batch `getActivePumpEvents(endDate:)` + new TBR, replace:true, no bolus

- Recommendation: Gate on pump-confirmed completion (state.bolusDose == nil) rather than the estimate, and have enactTempBasal carry the mutable bolus in its batch until it is finalized.

**P04-7 No test observes replacePendingEvents or mutable re-reporting** (Non-conforming, impact low, unverified)

The mock delegate appends events but drops replacePendingEvents, so no test can assert that a batch marked as the complete pending set actually contains every live mutable dose, nor that a running bolus/TBR is re-sent across syncs. The bolus finish path (StateSync:249-268), cancelBolus (648-657) and enactTempBasal (736-778) have no event-level tests. This is why P04-1/P04-2 have gone unnoticed.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:130` `replacePendingEvents _: Bool,` — flag discarded by the test delegate
  - `Tests/TandemKitTests/TandemPumpManagerBolusSyncTests.swift:24` bolus tests cover only shouldDeferBolusSync; no event assertions
  - `Tests/TandemKitTests/TandemPumpManagerSuspendDeliveryTests.swift:98` testSuspendRecordsASuspendDose asserts state only, not the emitted batch contents

- Recommendation: Record replacePendingEvents in the mock and add tests: mid-bolus sync with TBR expiry, suspend mid-bolus, relaunch mid-bolus, and TBR re-report, asserting each replace:true batch contains all live mutable doses.

Open questions raised by this point:

- The Trio-pinned DoseStore.addPumpEvents returns early on empty events (line 682) before the mutable purge and before syncPumpEventsToInsulinDeliveryStore, so the guide's §8 claim that an empty call re-resolves the InsulinDeliveryStore does not hold for the LoopKit TandemKit builds against (lastReconciliation is still set at line 680).
- Does Trio's DeviceDataManager/pump delegate use PumpManagerStatus.bolusState (.inProgress) for anything IOB-related? If so, the status surface partially masks P04-1 in Trio; settle by reading Trio's PumpManagerDelegate implementation.
- Bolus raw changes between the mutable report (units: programmed, TandemPumpManager.swift:599) and the finalized report (units: delivered, TandemDoseProgressReporter.swift:44 / cancelBolus:652) — a §4/P03 identity issue that compounds P04-1 (finalized bolus is inserted as a new row rather than matched).
- handleHomeScreenMirrorResponse (StateSync.swift:473-514) emits a replace:true batch but has no callers in Sources/; dead code or pending wiring?
- Domain fact to verify on hardware: does SuspendPumpingRequest cancel a running bolus on t:slim X2/Mobi? It determines whether the suspend-path omission in P04-1 is followed by a finalization with the partial volume.
- docs/tandemkit-history-integration-plan.md:468 describes a history-driven hasNewPumpEvents(replacePendingEvents: true) emission that does not exist in the current code (HistoryBackfillCoordinator.swift:9); the doc is stale relative to HEAD.
### P05. Finalized doses are reported with isMutable: false, a real endDate, and the actual deliveredUnits

Guide section: §9 item 5 (with §3 finalization).

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

App-commanded boluses that complete or are cancelled while the app process is alive are finalized with isMutable:false and a pump-reported deliveredUnits (LastBolusStatus, milliunits/1000), which is the right shape. But endDate is always Date.now at detection rather than the pump's completion time; the cancel path substitutes 0 U and the completion path substitutes the full programmed amount when the pump query fails; delivered volume is floored to a 0.05 U grid; and after an app relaunch a persisted in-flight bolus is never finalized because the progress reporter is in-memory only, so Loop purges the mutable dose and the insulin is lost. Temp basals finalize with programmed-rate x elapsed and detection-time endDate. The history mapper finalizes correctly but has no production caller and sits behind two default-off flags.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P05-1 | Partial | medium | unverified | Bolus natural completion via CurrentBolusStatus (steady state) |
| P05-2 | Partial | high | unverified | cancelBolus finalization falls back to zero delivered |
| P05-3 | Partial | medium | unverified | Bolus endDate is detection time, not pump completion time |
| P05-4 | Non-conforming | high | unverified | Persisted in-flight bolus is never finalized after app relaunch |
| P05-5 | Partial | low | unverified | Delivered volume floored to 0.05 U grid |
| P05-6 | Partial | medium | unverified | Temp basal finalization: programmed x elapsed, detection-time end |
| P05-7 | Partial | low | unverified | History-log finalization: correct shape, unreachable; extended boluses ignored |

**P05-1 Bolus natural completion via CurrentBolusStatus (steady state)** (Partial, impact medium, unverified)

In the common path the finalized event has isMutable:false, an endDate and deliveredUnits taken from the pump (LastBolusStatus.deliveredVolume / 1000). That satisfies the guide's shape. The gap is the fallback: when LastBolusStatus fails or its bolusId does not match (e.g. the user delivered a quick bolus on the pump after Loop's bolus), the dose is finalized as fully delivered. A bolus stopped early by occlusion, alarm or a pump-side cancel would then be permanently over-counted, since a finalized row is never revised. There is no unit test of this path; the mock delegate records events but nothing asserts on finalization.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:249` `if response.bolusId == 0 {` is the completion trigger, requires bolusProgressReport non-nil (guard at 226)
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:256` `actualDelivered = queryLastBolusDeliveredVolume(bolusId: bolusId)` reads LastBolusStatus deliveredVolume
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:33` `let delivered = actualDeliveredUnits ?? total` falls back to programmed amount
  - `Sources/TandemCore/Common/Extensions/DoseEntry.swift:25` `isMutable: false` when endDate supplied
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:527` `guard response.bolusId == bolusId else {` mismatch returns nil, so a pump-UI bolus after ours forces the programmed-total fallback

- Recommendation: Do not finalize on a guessed amount. If LastBolusStatus fails or mismatches, keep the dose mutable and retry (or read BolusCompletedHistoryLog for that bolusId). Add a StubPumpBluetooth test that drives enact -> completion and asserts isMutable:false and deliveredUnits equal the stubbed pump volume.

**P05-2 cancelBolus finalization falls back to zero delivered** (Partial, impact high, unverified)

Cancellation correctly waits 2 s, queries LastBolusStatus and finalizes with isMutable:false. But when that query returns nil (no response, or bolusId mismatch) the dose is finalized with deliveredUnits = 0. A bolus that had already delivered several units before the cancel is then recorded as zero, and because the row is immutable it is never corrected. This is the unsafe direction (IOB under-count -> Loop over-delivers), and it is the opposite fallback from the completion path (P05-1), so the two paths disagree on what an unknown delivery means. The completion callback also returns nil instead of the canceled DoseEntry, so the host cannot display or reconcile it.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` `bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:641` `let canceledDose = bolusDose.toDoseEntry(endDate: Date.now)` -> immutable
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:161` `deliveredUnits: isMutable ? nil : deliveredUnits` carries the 0 into the finalized entry
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:659` `completion(.success(nil))` — the finalized DoseEntry is not returned to the host

- Recommendation: On a failed/mismatched LastBolusStatus query, leave the dose mutable (re-report it) and re-query on the next sync or via BolusCompletedHistoryLog; never finalize at 0. Return the canceled DoseEntry in the completion. Cover with a test where the stub omits LastBolusStatusResponse.

**P05-3 Bolus endDate is detection time, not pump completion time** (Partial, impact medium, unverified)

The finalized bolus gets endDate = the moment the app noticed completion. Steady state that is the completion poll or the next ~5-minute sync; after a BLE drop mid-bolus it is whenever the link comes back, possibly much later. The pump exposes its own timestamp on LastBolusStatus (and BolusCompletedHistoryLog carries pumpTimeSec) but neither is used. LoopKit treats a bolus whose window exceeds roughly one 5-minute delta as continuous delivery across startDate..endDate, so an inflated endDate smears IOB later than it was actually delivered. The wider the reconnect gap, the larger the distortion. The 'real endDate' requirement is only approximately met.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:42` `endDate: Date.now` on the finalized completion event
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:641` `bolusDose.toDoseEntry(endDate: Date.now)` on cancel
  - `Sources/TandemCore/Messages/CurrentStatus/LastBolusStatus.swift:54` `timestamp = Bytes.readUint32(cargo, 5)` — pump-side bolus timestamp is parsed but unused
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:198` sync defers until `estimatedEndDate + 30s`, so completion is detected at earliest ~30 s late and at most one sync (~5 min) late

- Recommendation: Compute the finalized endDate from pump data: LastBolusStatus.timestampDate (or startDate + deliveredUnits / bolus speed, clamped to now) rather than Date.now. Validate on hardware whether LastBolusStatus.timestamp is the start or completion time before relying on it.

**P05-4 Persisted in-flight bolus is never finalized after app relaunch** (Non-conforming, impact high, unverified)

enactBolus emits the mutable bolus and persists state.bolusDose, but the object that builds the finalized event lives only in memory. If the app is killed mid-bolus (or before the completion sync), on relaunch fetchBolusStatus either clears bolusDose silently (status alreadyDelivered, reporter nil) or returns early (status delivering, reporter nil). No isMutable:false event is ever sent for that bolusId, and the mutable dose is not re-reported either. The next emitPumpEvents with replacePendingEvents:true — any basal-type change, temp basal, suspend — purges it from DoseStore, so the insulin vanishes from IOB. The history path that could recover it (HistoryToDoseMapper) has no production caller and its flags default off. This is exactly the MedtrumKit #92 failure the guide warns about.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:70` `internal var bolusProgressReport: TandemDoseProgressReporter?` — in-memory only, nil after relaunch
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:244` `if let bolusDoseRaw = rawValue["bolusDose"]` — the UnfinalizedDose itself is restored
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:217` `if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil {` clears bolusDose without emitting any event
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:226` `guard let progressReport = bolusProgressReport else { return }` — every finalize path needs the reporter
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:600` initial mutable bolus emitted with `replacePendingEvents: false`; the next `true` batch (e.g. StateSync:161/183) purges it

- Recommendation: Make finalization depend only on persisted state: rebuild the progress reporter from state.bolusDose on init, or move getPumpEvent onto UnfinalizedDose. On relaunch with a persisted bolusDose, re-report it mutable, then finalize from LastBolusStatus/BolusCompletedHistoryLog by bolusId. Add a relaunch test (init from rawValue, then sync).

**P05-5 Delivered volume floored to 0.05 U grid** (Partial, impact low, unverified)

The pump reports delivered volume in milliunits, i.e. 0.001 U resolution. The status path floors that to the 0.05 U command grid, so a cancelled bolus that delivered 1.049 U is finalized as 1.00 U. The error is bounded (< 0.05 U per bolus) but always understates delivery, which is the direction that lets Loop over-deliver. The repository already recognises this: HistoryToDoseMapper.roundToReportingResolution rounds to nearest 0.001 U precisely to avoid it, so the two finalization surfaces disagree. The guide asks for deliveredUnits rounded to the pump's supported increment; Tandem's reported increment is the milliunit, not 0.05 U.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:532` `return roundToSupportedBolusVolume(units: Double(response.deliveredVolume) / 1000.0)`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:226` `supportedBolusVolumes.last(where: { $0 <= units }) ?? 0` — floor, not nearest
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:27` `strideRange(from: 0.05, through: 25.0, by: 0.05)` is the grid
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:161` mapper instead rounds to nearest milliunit and documents why floor-to-grid is the unsafe direction

- Recommendation: Use HistoryToDoseMapper.roundToReportingResolution (nearest 0.001 U) for deliveredUnits in queryLastBolusDeliveredVolume; keep roundToSupportedBolusVolume for programming only. Add a test with deliveredVolume = 1049.

**P05-6 Temp basal finalization: programmed x elapsed, detection-time end** (Partial, impact medium, unverified)

Every path that ends a temp basal (enactTempBasal, suspendDelivery, configureControlIQMode, fetchBasalStatus, handleHomeScreenMirrorResponse) finalizes it through getActivePumpEvents(endDate:), producing isMutable:false, an endDate and deliveredUnits. Natural expiry is handled well: the end is clamped to the programmed end. Two gaps remain. First, deliveredUnits is programmed rate x elapsed time, not a measured amount, and is not rounded to any pump increment; Tandem gives no direct measured TBR volume, so this is the reasonable estimate but should be documented as such. Second, when the pump itself stops the TBR (user suspend on the t:slim screen, Control-IQ enable) and TandemKit only learns at the next sync, endDate is the sync time, over-reporting delivery by up to one sync interval at the temp rate.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` `state.basalDose.toDoseEntry(isMutable: endDate == nil, endDate: endDate ?? Date.now)`
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` `deliveredUnits: isMutable ? nil : value * (duration / .hours(1))` — programmed rate, unrounded
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:178` `if !isMutable, actualEndDate > estimatedEndDate {` clamps natural expiry to the programmed end
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:149` `var events = getActivePumpEvents(endDate: now)` — pump-side suspend/stop detected at sync gets the sync time as endDate
  - `Sources/TandemCore/Messages/HistoryLog/TempRateCompletedHistoryLog.swift:16` `timeLeft` plus pumpTimeSec give the true stop time but are unused by the status path

- Recommendation: For pump-initiated stops detected at sync, derive endDate from the pump (PumpingSuspendedHistoryLog / TempRateCompletedHistoryLog pumpTimeSec, or CurrentBasalStatus if it carries a change time) rather than Date.now. Round deliveredUnits to 0.001 U. Document that TBR deliveredUnits is computed, not measured.

**P05-7 History-log finalization: correct shape, unreachable; extended boluses ignored** (Partial, impact low, unverified)

The history mapper is the one place that finalizes exactly as the guide describes: pump completion timestamp as endDate, insulinDelivered rounded to nearest milliunit, isMutable:false, stable bolusId-based raw, and in-flight activations reported mutable under the same identity. HistoryToDoseMapperTests asserts these fields. However, nothing in Sources calls mapToEvents, and both governing flags default to false, so on every real path (steady state, first sync, reconnect, relaunch) this finalization never reaches the delegate. Within the mapper, finalized temp basals omit deliveredUnits (LoopKit then rounds programmedUnits to Minimed's 1/20 U increments via unitsInDeliverableIncrements), and extended-bolus records are dropped, so a t:slim extended bolus would be finalized with only its immediate portion once the layer is wired.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:175` `let endDate = reconciler.utcDate(pumpTimeSec: completion.pumpTimeSec, ...)` — real pump completion time
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:190` `deliveredUnits: Self.roundToReportingResolution(Double(completion.insulinDelivered))`, isMutable defaults false
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:261` TBR `isMutable: completion == nil` but no deliveredUnits, so LoopKit falls back to programmedUnits
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:118` `default: continue` — BolexActivated/BolexCompletedHistoryLog (extended bolus) are never mapped
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:9` "Nothing is mapped to doses or emitted here" — mapToEvents has no caller outside tests

- Recommendation: When wiring the emission layer, set deliveredUnits on finalized TBRs (rate x min(programmed, actual) duration) and add BolexActivated/BolexCompleted handling so the extended portion is counted. Until then, document clearly that history-based finalization is not active in shipped builds.

Open questions raised by this point:

- Identity vs finalization (P03/P04 territory): the finalized bolus raw embeds deliveredUnits (`NewPumpEvent.bolus(... units: delivered ...)`, TandemDoseProgressReporter.swift:44, TandemPumpManager.swift:652) and the TBR raw embeds programmedUnits = rate x (endDate - startDate) (NewPumpEvent.swift:20), so any finalization with a shorter duration or partial delivery changes the syncIdentifier. Finalization therefore works only through the replacePendingEvents:true purge, not in-place matching — and the relaunch case in P05-4 is where that safety net fails.
- LastBolusStatusResponse.timestamp semantics: is it the bolus start or completion time on Tandem firmware? Confirming on hardware decides whether it can be used as the finalized endDate (P05-3).
- Does BolusCompletedHistoryLog.insulinDelivered for an extended bolus cover only the immediate portion, with the remainder in BolexCompletedHistoryLog? pumpX2 field semantics should be checked before the emission layer is built.
- Pump-UI boluses (Mobi quick bolus, t:slim touchscreen boluses, Control-IQ automatic corrections) are never reported by the status path at all — fetchBolusStatus only finalizes a dose TandemKit itself enacted. That belongs to the wasProgrammedByPumpUI point but compounds P05-4: today no path finalizes them.
- LastBolusRequestBuilder never selects LastBolusStatusV3Request on Mobi API >= 3.5; if the V2 message is deprecated on that firmware, queryLastBolusDeliveredVolume would fail on every bolus and the fallbacks in P05-1/P05-2 would become the normal path.
- CLAUDE.md states `historyDoseReporting` has no consumer and that HistoryToDoseMapper is not wired to emission; the code confirms this at HEAD 7d20b2d, so the docs are accurate on this point.
### P06. replacePendingEvents is true when a batch is the complete current set of pending delivery and false only when appending an event that must not disturb a live mutable dose

Guide section: §9 item 6 (with §5).

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

The flag is used with the right intent: `false` only for the initial mutable bolus (MedtrumKit pattern) and for dose-less site/cartridge events (OmnipodKit pattern); every other batch is `true`. But `true` batches are not the "complete current set": they are assembled from `getActivePumpEvents`, which only ever contributes the temp basal in `state.basalDose` and never the live bolus in `state.bolusDose`. Any `true` batch emitted while a bolus is running purges that mutable bolus. In steady state it is re-inserted immutable at finalization; after an app relaunch (`bolusProgressReport` is nil) it is never finalized and the next temp basal enact deletes it from IOB. `sendResumePumping` also emits `true` without the temp basal. No test asserts the flag.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P06-1 | Partial | high | unverified | true batches omit the live mutable bolus |
| P06-2 | Partial | medium | unverified | initial bolus emitted with false |
| P06-3 | Conforms | none | unverified | siteChange / cartridgeChange emitted with false |
| P06-4 | Partial | medium | unverified | resume emits true without the active TBR; dead HSM path |
| P06-5 | Conforms | none | unverified | flag semantics across LoopKit variants and Linux shim |
| P06-6 | Non-conforming | low | unverified | no test observes replacePendingEvents |

**P06-1 true batches omit the live mutable bolus** (Partial, impact high, unverified)

The initial bolus is appended with `false` (correct), but every later `true` batch is assembled from `getActivePumpEvents`, which only includes the temp basal. While a bolus is live, `fetchBasalStatus` (every sync and on qualifying events), `suspendDelivery`, `configureControlIQMode`, and `enactTempBasal` once the time-based `isUnfinalized()` flips false all emit `true` and purge the mutable bolus. Steady state: `fetchBolusStatus` later re-inserts it immutable (StateSync:268), so IOB only dips temporarily. After relaunch `bolusProgressReport` is nil: the guard at 679 no longer blocks, `fetchBolusStatus` clears `bolusDose` without emitting (217-224, 226), and the next Loop temp basal enact purges the persisted mutable bolus permanently — a lost dose. Same on BLE reconnect if the bolusChange event was missed and the bolus finished during the outage.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1703` getActivePumpEvents: `guard state.basalDose.type == .tempBasal else { return [] }` — never consults state.bolusDose
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:161` fetchBasalStatus emits `true` batch (TBR finalize + suspend) with no bolus event; also 183
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:828` suspendDelivery emits `true` batch built only from getActivePumpEvents + suspend
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:679` enactTempBasal bolus guard: `if let bolusProgressReport, bolusProgressReport.isUnfinalized()` — nil after relaunch
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:58` isUnfinalized is a timer estimate `deliveredUnits < total`, not pump state

- Recommendation: Make `getActivePumpEvents` (or a new `pendingEvents()`) also return `state.bolusDose` as a mutable bolus event whenever it is non-nil, so every `true` batch is genuinely complete. On relaunch, rebuild the bolus tracker from persisted `bolusDose` or finalize it from `LastBolusStatus` before any `true` emit.

**P06-2 initial bolus emitted with false** (Partial, impact medium, unverified)

Using `false` here is correct and matches MedtrumKit: it appends the mutable bolus without wiping a running temp basal, and because the TBR row survives at the PumpEvent tier it is re-resolved (not deleted) at the InsulinDeliveryStore tier. The §5 compound pitfall (changed identity + `false`) does not fire, because every finalizing emit (`fetchBolusStatus` StateSync:268, `cancelBolus` 657) uses `true`. However the identity is not stable: initial raw uses programmed units, finalization and cancel use delivered units, so on partial delivery the driver relies on the mutable-purge safety net exactly as the guide warns for MedtrumKit. Correct end state today, latent duplicate if any finalizing path ever switches to `false`.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:600` `replacePendingEvents: false` on the initial mutable bolus event
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:10` raw = `"\(DoseType.bolus.rawValue) \(units) \(ISO date)"` — units is programmed here
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:44` finalizer passes `units: delivered`, so raw differs from the initial when delivery is partial
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:652` cancelBolus: `units: canceledDose.deliveredUnits ?? 0` — raw changes on cancel
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:657` cancel finalization uses default `true`, so the stale mutable row is purged by flag, not identity

- Recommendation: Keep `false` on the initial emit, but build the bolus raw from programmed units and bolusId/startDate in all three sites (initial, finalize, cancel) so identity never changes; finalize by flipping isMutable and setting deliveredUnits only.

**P06-3 siteChange / cartridgeChange emitted with false** (Conforms, impact none, unverified)

Both events carry no dose, are immutable, and have a raw fixed at creation from a single date, so they are emitted once and never re-reported. Passing `false` is exactly the OmnipodKit pod-change pattern the guide endorses: a running bolus or temp basal is left untouched. `lastReconciliation` is forwarded unchanged from state, so these emits do not move the trust boundary. No feature flag gates them.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1062` `emitPumpEvents([NewPumpEvent.siteChange(date: date)], replacePendingEvents: false)`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1071` `emitPumpEvents([NewPumpEvent.cartridgeChange(date: date)], replacePendingEvents: false)`
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:62` siteChange: `dose: nil`, raw `"siteChange <ISO date>"`, type .replaceComponent
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:75` cartridgeChange: `dose: nil`, raw `"cartridgeChange <ISO date>"`, type .rewind
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitFillCannulaViewModel.swift:172` UI calls recordSiteChange after a successful cannula fill

- Recommendation: No change needed for the flag. (Whether cartridge change should be `.replaceComponent(.reservoir)` rather than `.rewind` belongs to the event-type checklist item, not this one.)

**P06-4 resume emits true without the active TBR; dead HSM path** (Partial, impact medium, unverified)

`sendResumePumping` is the one `true` batch that does not fold in `getActivePumpEvents`. When `state.basalDose` is `.suspend` (the normal case after `suspendDelivery` or a sync that saw the pump suspended) nothing mutable is outstanding and `true` is correct. But if the user suspended on the pump and pressed the app's resume button before the next sync/qualifying-event fetch, `state.basalDose` is still the temp basal: the `true` emit purges that mutable TBR with no finalized replacement, losing its delivered insulin. Window is bounded (~5 min or the pumpSuspend qualifying event). Suspend, resume and basal entries are immutable in the pinned LoopKit, so omitting them from later `true` batches is harmless. `handleHomeScreenMirrorResponse` is unreachable code.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:904` `let events = [NewPumpEvent.resume(...)]` — getActivePumpEvents not called
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:910` `emitPumpEvents(events)` with default `true`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:854` resumeDeliveryAcknowledgingResumeAlarms is a user button path, callable whatever state.basalDose holds
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:473` handleHomeScreenMirrorResponse builds and emits a `true` batch but has no callers in Sources/ or Tests/
  - `reference: loopkit-trio/DoseEntry.swift:31` `init(suspendDate:..., isMutable: Bool = false)` — suspend/resume/basal entries are immutable, so only TBR and bolus are at risk

- Recommendation: In `sendResumePumping`, prepend `getActivePumpEvents(endDate: dose.startDate)` (finalizing any lingering TBR) before the resume event, mirroring suspendDelivery. Delete or wire `handleHomeScreenMirrorResponse`.

**P06-5 flag semantics across LoopKit variants and Linux shim** (Conforms, impact none, unverified)

The purge semantics TandemKit relies on are identical in the LoopKit fork it builds against and in next-dev, and both default the flag to `true`, matching `emitPumpEvents`' default. The driver therefore does not need variant-specific handling. On Linux the shim only type-checks the call: nothing purges, and the shim's `NewPumpEvent` differs structurally from real LoopKit (event-level `isMutable`, no raw-derived syncIdentifier), so a Linux test run cannot observe misuse of the flag. `notify` dispatches FIFO on the delegate queue, so the `false` initial bolus emit is never reordered after a later `true` batch.

- Evidence:
  - `reference: loopkit-trio/DoseStore.swift:679` `addPumpEvents(..., replacePendingEvents: Bool = true, ...)` — Trio-pinned default true, purge at 704-706
  - `reference: loopkit-nextdev/DoseStore.swift:624` next-dev: identical `if replacePendingEvents { purge mutable == YES }`
  - `LinuxShims/LoopKit/LoopKit.swift:183` shim delegate protocol carries `replacePendingEvents: Bool` but has no DoseStore behind it
  - `LinuxShims/LoopKit/LoopKit.swift:539` shim NewPumpEvent has its own `isMutable` and does not derive syncIdentifier from raw
  - `LinuxShims/LoopKit/LoopKit.swift:844` `notify` is `queue.async` — emits are serialized in call order, so the false-then-true sequence is preserved

- Recommendation: None for conformance. If Linux CI is meant to catch dose-reporting regressions, add a tiny in-test DoseStore stand-in that applies the mutable purge and raw-based matching.

**P06-6 no test observes replacePendingEvents** (Non-conforming, impact low, unverified)

The mock delegate is the only place the flag can be observed in tests, and it drops it; no test inspects the accumulated events either. The P06-1 and P06-4 gaps (a `true` batch missing a live mutable dose) are exactly the kind of regression a batch-content assertion would catch, and the guide's §11 explicitly recommends idempotency and cancel tests. Given CLAUDE.md notes that earlier dose-path coverage was dropped and not re-created, this is a real, current gap rather than a stale note.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:130` `replacePendingEvents _: Bool,` — the mock discards the flag
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:133` `_pumpEvents += events` accumulates, but no test file reads `pumpEvents`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1733` `func emitPumpEvents(_ events:, replacePendingEvents: Bool = true)` — the only chokepoint, untested

- Recommendation: Record `(events, replacePendingEvents)` pairs in the mock and add StubPumpBluetooth-driven tests: bolus start (`false`, one mutable bolus), TBR enact during bolus (`true` must contain the bolus), cancel (`true`, same raw), relaunch-then-enactTempBasal (bolus still present).

Open questions raised by this point:

- Does the host (Loop/Trio) ever call enactTempBasal while a bolus is in progress? If not, the steady-state purge in P06-1 is limited to fetchBasalStatus/suspend paths; the relaunch case stands regardless.
- Does SuspendPumpingRequest cancel an in-progress bolus on Tandem firmware? If so, suspendDelivery's `true` batch purge is always followed by a fetchBolusStatus finalization; if not, the bolus resumes and the purge/reinsert gap is longer.
- The scratchpad LoopKit copies do not include WeakSynchronizedDelegate; the FIFO-ordering claim in P06-5 is verified against the Linux shim and LoopKit's known implementation, not the pinned source.
- docs/tandemkit-history-integration-plan.md:468 shows a planned history-reconciliation emit with `replacePendingEvents: true`; if built as drawn, that batch would also need to include the live bolus/TBR or it will purge them (same class as P06-1).
- fetchBasalStatus emits a `true` batch that does not update lastReconciliation in one branch order (StateSync:159-162 sets it before emit, but handleHomeScreenMirrorResponse never sets it) — relevant to P02, not this point.
### P07. value carries the programmed amount and deliveredUnits the actual amount, both rounded to the pump's supported increment

Guide section: §9 item 7.

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

The bolus shape is right: mutable doses carry deliveredUnits nil, and finalized doses carry value=programmed and deliveredUnits from the pump's LastBolusStatus. But the actual amount is floored to the driver's declared 0.05 U grid, coarser than the milliunit wire resolution (and Tandem's 0.01 U bolus increment), systematically under-counting partial deliveries; cancelBolus reports deliveredUnits=0 when the LastBolusStatus read fails or its bolusId mismatches, while the completion path assumes full delivery in the same situation. Temp basal value is derived from the app-side schedule times an integer percent and never reconciled with the pump-reported profile/current rate fetched in the same command; temp basal deliveredUnits is an unrounded value x hours. The history mapper rounds differently (0.001 nearest) but is unwired and behind default-off flags.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P07-1 | Non-conforming | high | unverified | cancelBolus deliveredUnits fallback to zero |
| P07-2 | Partial | medium | unverified | deliveredUnits floored to 0.05 U grid, coarser than pump |
| P07-3 | Partial | medium | unverified | Completion path assumes full delivery when pump read fails |
| P07-4 | Partial | medium | unverified | Temp basal value derived from app schedule, pump rate ignored |
| P07-5 | Partial | low | unverified | Temp basal deliveredUnits computed, unrounded, not pump-sourced |
| P07-6 | Partial | low | unverified | Declared increments coarser than protocol; value not re-rounded |
| P07-7 | Unsure | none | unverified | History mapper rounding vs live path; unwired |
| P07-8 | Conforms | none | unverified | Mutable/finalized bolus shape (value vs deliveredUnits) |

**P07-1 cancelBolus deliveredUnits fallback to zero** (Non-conforming, impact high, unverified)

On cancel, the finalized dose's deliveredUnits is taken from LastBolusStatus; when that read times out, returns a different bolusId (e.g. the pump has not yet stored the cancelled bolus after the 2 s sleep, or a pump-UI bolus intervened), the code substitutes 0. The dose is then emitted immutable with deliveredUnits = 0, so a bolus that delivered several units before cancellation is recorded as delivering nothing. Because the dose is immutable, nothing later corrects it (history emission is not wired). This is the under-count direction: Loop/Trio IOB drops by the full partially-delivered amount.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:641` canceledDose = bolusDose.toDoseEntry(endDate: Date.now) -> immutable, deliveredUnits carried as-is
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:527` guard response.bolusId == bolusId else { ... return nil } — mismatch also yields nil
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:522` write(request) as? LastBolusStatusAbstractResponse else { ... return nil } — no response yields nil
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:636` Thread.sleep(2s) 'Allow the Mobi to store the bolus' — timing-dependent read

- Recommendation: On a failed/mismatched LastBolusStatus read, do not finalize with 0: keep the dose mutable and retry the read (or fall back to the progress-reporter estimate, clearly bounded), and only finalize once the pump reports the delivered volume for the matching bolusId.

**P07-2 deliveredUnits floored to 0.05 U grid, coarser than pump** (Partial, impact medium, unverified)

The pump reports the actual delivered volume in milliunits, and Tandem's bolus delivery increment is finer than 0.05 U (0.01 U per the t:slim X2 / Mobi specifications, to be verified). Both finalization paths (natural completion via fetchBolusStatus and cancel) pass that value through roundToSupportedBolusVolume, which is the LoopKit *command* rounding (floor to the driver's 0.05 grid). A cancelled bolus that delivered 1.041 U is reported as 1.00 U; 1.049 U becomes 1.00 U. The error is always downward (up to 0.049 U per bolus) and accumulates across boluses. The repo's own history mapper documents this as the unsafe direction and uses round-to-nearest 0.001 instead, but that path is not wired.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:532` return roundToSupportedBolusVolume(units: Double(response.deliveredVolume) / 1000.0)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:226` supportedBolusVolumes.last(where: { $0 <= units }) ?? 0 — floor, not nearest
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:27` onboardingSupportedBolusVolumes = strideRange(from: 0.05, through: 25.0, by: 0.05)
  - `Sources/TandemCore/Messages/CurrentStatus/LastBolusStatus.swift:46` deliveredVolume = Bytes.readUint32(cargo, 9) — milliunit resolution on the wire
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:158` comment: floor-to-command-grid 'could drop a whole increment and understate delivered IOB (the unsafe direction)'

- Recommendation: Report deliveredUnits at the pump's native reporting resolution using round-to-nearest (reuse HistoryToDoseMapper.roundToReportingResolution) rather than the floor-to-command-grid helper; reserve roundToSupportedBolusVolume for outgoing commands. Confirm the hardware bolus increment (0.01 U) and consider aligning supportedBolusVolumes with it.

**P07-3 Completion path assumes full delivery when pump read fails** (Partial, impact medium, unverified)

When CurrentBolusStatus reports bolusId 0 (finished), the driver queries LastBolusStatus for the real delivered volume — the right source. If that read fails or the bolusId mismatches, it finalizes with deliveredUnits = programmed total, i.e. assumes full delivery. A bolus stopped by an occlusion/alarm or a BLE-initiated stop (bolusStatus .stoppedAlarm/.stoppedWireless) that then fails the follow-up read is over-counted. This is the opposite fallback direction from cancelBolus (P07-1), so the two paths disagree about what an unknown delivered amount means. The bolusStatus field, which would at least flag an incomplete delivery, is never read.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:255` if let bolusId = state.bolusDose?.bolusId { actualDelivered = queryLastBolusDeliveredVolume(bolusId: bolusId) }
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:260` events.append(progressReport.getPumpEvent(actualDeliveredUnits: actualDelivered))
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:33` let delivered = actualDeliveredUnits ?? total — falls back to programmed
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:36` units: total, deliveredUnits: delivered — value/deliveredUnits split is correct when the read succeeds
  - `Sources/TandemCore/Messages/CurrentStatus/LastBolusStatusAbstractResponse.swift:15` BolusStatus stopped/stoppedAlarm/stoppedMalfunction/stoppedWireless exist but are never consulted

- Recommendation: Treat a failed LastBolusStatus read as 'delivered amount unknown': keep the dose mutable and retry on the next sync rather than finalizing with a guess. When the read succeeds, also log/assert bolusStatus == .complete when deliveredVolume equals requested.

**P07-4 Temp basal value derived from app schedule, pump rate ignored** (Partial, impact medium, unverified)

The reported value is baseline x integer percent, floored to the 0.01 grid, which correctly reflects the percent actually programmed (not Loop's raw request) — good. But the baseline is the app's cached schedule via Calendar.current, not the pump's own profileBasalRate returned by the CurrentBasalStatusRequest sent two lines earlier. If the pump profile differs (partial syncBasalRateSchedule failure, segment edited on the pump, segment-boundary off-by-one with strict '<'), or a profile segment changes mid-temp-rate, the pump runs percent x its own rate while the reported value stays fixed; deliveredUnits then inherits the error (P07-5). The finalized dose is never checked against currentBasalRate on later syncs either.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:685` let baselineRate = getScheduledBasalRate() — app-side state.basalRateSchedule, not the pump
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:699` guard let currentBasal = self.bluetooth.write(CurrentBasalStatusRequest()) — fetched but only basalType is used
  - `Sources/TandemCore/Messages/CurrentStatus/CurrentBasalStatus.swift:45` profileBasalRate / currentBasalRate available at 0.001 U/h resolution
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:721` percent = percentForTempBasal(...); absoluteRate = roundToSupportedBasalRate(baselineRate * percent/100)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:284` Int((requestedRate / baseline * 100.0).rounded()) clamped 0...250 — 1% resolution

- Recommendation: Compute the baseline from currentBasal.profileBasalRate (pump truth) and report value from it; on each sync, compare state.basalDose.value with CurrentBasalStatusResponse.currentBasalRate and correct/split the mutable temp basal when a profile segment change alters the running rate.

**P07-5 Temp basal deliveredUnits computed, unrounded, not pump-sourced** (Partial, impact low, unverified)

A finalized temp basal's deliveredUnits is value x elapsed hours with full double precision (e.g. 1.13 U/h x 27.5 min = 0.51792 U), not rounded to any pump increment, and not read back from the pump. Trio's LoopKit consumes it verbatim. The guide asks for deliveredUnits rounded to the pump's increment; Medtrum's plotting/IOB bug was exactly this. Magnitude here is sub-milliunit per dose so the accounting impact is cosmetic, but the value is only as accurate as `value` (see P07-4), and there is no pump-side confirmation (BasalDeliveryHistoryLog / BasalRateChangeHistoryLog are parsed but unused for reconciliation).

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` deliveredUnits: isMutable ? nil : value * (duration / .hours(1))
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:177` actualEndDate = isMutable ? estimatedEndDate : endDate, capped at estimatedEndDate
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` getActivePumpEvents finalizes the running temp basal with endDate ?? Date.now
  - `reference: loopkit-trio/DoseEntry.swift:152` unitsInDeliverableIncrements uses deliveredUnits verbatim when present

- Recommendation: Round temp basal deliveredUnits to the milliunit (0.001 U) reporting resolution, and when the history backfill is enabled use BasalRateChangeHistoryLog/TempRateCompletedHistoryLog to confirm start/end and rate.

**P07-6 Declared increments coarser than protocol; value not re-rounded** (Partial, impact low, unverified)

The wire carries milliunits for boluses, profile rates and current rate (Tandem specs: 0.001 U/h basal at >=0.1 U/h, 0.01 U bolus — verify), but the driver declares 0.01 U/h and 0.05 U grids and floors to them when reporting. enactBolus does not itself round: value is whatever the host passed, while the wire gets round(units*1000); Loop and Trio round to supportedBolusVolumes first, so in practice value sits on the 0.05 grid, but the driver relies on the host for that. Reported `value` for temp/scheduled basal is floored to 0.01, up to 0.00999 U/h below the pump's 0.001-resolution rate. Small, but it means 'rounded to the pump's supported increment' is only approximately true.

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:238` step = Int(round(0.01 * multiplier)) — supportedBasalRates in 0.01 U/h steps
  - `Sources/TandemCore/Messages/CurrentStatus/IDPSegment.swift:62` profileBasalRate = Bytes.readShort(cargo, 4) — milliunit profile rates on the wire
  - `Sources/TandemKit/PumpManager/TandemPumpManager+SyncBasal.swift:222` basalMilliunits = Int((scheduleItem.value * 1000.0).rounded())
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:551` milliUnits = max(0, Int((units * 1000).rounded())) — bolus sent at 0.001 U resolution
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:578` UnfinalizedDose(units: units, ...) — value is the host's unrounded request

- Recommendation: Round `value` inside the driver (roundToSupportedBolusVolume in enactBolus) so the reported amount equals the wire amount regardless of host; document that the declared grids are UI-selection grids and use milliunit round-to-nearest for anything read back from the pump.

**P07-7 History mapper rounding vs live path; unwired** (Unsure, impact none, unverified)

The history-derived path correctly keeps value=bolusSize (programmed) and deliveredUnits=insulinDelivered (actual), rounded to nearest 0.001 U with Float32 noise stripped, and leaves temp basal deliveredUnits nil so LoopKit derives it. This is the better-conforming implementation, but it has no production caller (only tests reference HistoryToDoseMapper) and is gated by two default-off flags. Because it rounds differently from the live path (0.05 floor) and mints different raw identifiers, once wired the same bolus could be reported twice with different deliveredUnits. BasalRateChange value is a raw Float (0.8999999 style noise) and unrounded. Cannot judge steady-state behaviour of an emission layer that does not exist yet.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:162` (units * 1000).rounded() / 1000 — round-to-nearest milliunit
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:188` value from activation.bolusSize (Float), deliveredUnits from completion.insulinDelivered (Float)
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:277` value: Double(basalChange.commandBasalRate) — Float noise not rounded
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:36` historyBackfill / historyDoseReporting default false
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:173` historyDoseReporting is self[.historyBackfill] && self[.historyDoseReporting]

- Recommendation: When wiring the emission layer, make the live paths adopt roundToReportingResolution so both report identical deliveredUnits, apply it to BasalRateChangeHistoryLog.commandBasalRate too, and add tests asserting live-path bolus/temp-basal value and deliveredUnits rounding (none exist today).

**P07-8 Mutable/finalized bolus shape (value vs deliveredUnits)** (Conforms, impact none, unverified)

Across enact, natural completion and cancel, the DoseEntry keeps value = the programmed units and puts the pump-reported amount in deliveredUnits; in-progress doses carry deliveredUnits nil, the MedtrumKit shape the guide endorses. The 1 s progress estimate (floored to 0.05) is confined to the DoseProgressReporter and never reaches hasNewPumpEvents. Persisted UnfinalizedDose round-trips value and deliveredUnits unchanged, so an app relaunch does not alter amounts. The remaining P07 defects (P07-1..P07-6) are about *which* number lands in deliveredUnits and how it is rounded, not about the field split itself.

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:161` deliveredUnits: isMutable ? nil : deliveredUnits — no delivered amount while in progress
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:587` dose.toDoseEntry(isMutable: true) emitted at enact time with value = programmed units
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:37` finalized: units: total (programmed), deliveredUnits: delivered (pump-reported)
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:77` progress estimate floored to 0.05 only feeds DoseProgress UI, not the DoseStore
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:244` bolusDose value/deliveredUnits persisted as Doubles, not re-rounded on relaunch

- Recommendation: Keep this shape; add a unit test pinning value=programmed and deliveredUnits=pump-reported for completion and cancel so the rounding fixes above cannot regress the split.

Open questions raised by this point:

- Hardware increments should be confirmed against the current t:slim X2 and Mobi user guides: this audit assumes 0.001 U/h basal (at >=0.1 U/h) and 0.01 U bolus delivery increments; if the bolus increment is actually 0.05 U the severity of P07-2 drops to low.
- After an app relaunch, bolusProgressReport is nil (not persisted); fetchBolusStatus then clears state.bolusDose on .alreadyDeliveredOrInvalid (StateSync 217-224) without emitting a finalized dose, so the deliveredUnits for that bolus is never reported at all. This is a P04/P05 (finalization/re-report) issue rather than P07 but directly affects whether any 'actual amount' reaches Loop.
- cancelBolus mints the finalized bolus raw as 'bolus <deliveredUnits> <startDate>' (TandemPumpManager.swift 652) while enactBolus used the programmed units, so the identity changes at cancel; covered under P03, but it interacts with P07-1 because the zero-delivered dose is inserted under a new identity while the mutable original is purged only via replacePendingEvents.
- SetTempRateRequest is declared mobiOnly / minApi mobiApiV3_5 (SetTempRate.swift 12-13); whether t:slim X2 has any temp-rate path in this driver was not verified and affects which pump the temp basal findings apply to.
- fetchBasalStatus never emits anything when the pump reports .tempBasal while the driver thinks it is on scheduled basal (StateSync 141-187), so a temp rate set on the pump UI has no reported value/deliveredUnits at all (P08 territory).
- handleHomeScreenMirrorResponse (StateSync 473) emits basal doses but has no caller; if it is revived it should use the same rounding rules.
- The guide's decisionId and the historyDoseReporting emission layer do not exist in the Trio-pinned LoopKit / this codebase; the CLAUDE.md claim that HistoryToDoseMapper is 'not wired to any emission path' matches the code at HEAD.
### P08. UI-capable pump: wasProgrammedByPumpUI is set for user-initiated doses and they are reconciled from pump history

Guide section: §9 item 8 (with §7).

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

TandemKit does not meet §9 item 8 on any path. wasProgrammedByPumpUI is set only inside HistoryToDoseMapper, which has no production caller (tests only); HistoryBackfillCoordinator reads history into a store but emits nothing, and the historyDoseReporting flag (default off, gated on historyBackfill, also default off) has no consumer. The live status paths never emit a dose Loop did not command: fetchBolusStatus returns when there is no Loop-side progress report, fetchBasalStatus has no temp-rate branch and reads Control-IQ modulation as plain scheduled basal, and handleHomeScreenMirrorResponse is dead code. Pump-UI suspends are emitted but unflagged. The design for future history reconciliation also has gaps: no commanded-bolus-id source, no identity bridge between optimistic raw and HistoryLogSyncIdentifier, no flag on temp basals, no `automatic` on Control-IQ boluses.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P08-1 | Non-conforming | high | unverified | History-derived doses never reach the delegate |
| P08-2 | Non-conforming | high | unverified | Live status path ignores pump-UI and Control-IQ boluses |
| P08-3 | Non-conforming | high | unverified | Live basal path misses pump-UI temp rates and Control-IQ modulation |
| P08-4 | Partial | low | unverified | Pump-initiated suspend/resume emitted without pump-UI flag |
| P08-5 | Partial | medium | unverified | Mapper metadata gaps for the future history path |
| P08-6 | Non-conforming | high | unverified | No reconciliation of pending doses against history (identity bridge) |

**P08-1 History-derived doses never reach the delegate** (Non-conforming, impact high, unverified)

CLAUDE.md's claim is confirmed against HEAD: HistoryToDoseMapper.mapToEvents has no production caller, HistoryBackfillCoordinator only fills HistoryLogStore and persists a watermark, and a grep for historyDoseReporting outside TandemFeatureFlags.swift returns nothing. So no history-derived NewPumpEvent ever reaches emitPumpEvents / pumpManager(_:hasNewPumpEvents:). This holds in steady state, after pairing, after reconnect, and after relaunch regardless of flag values: even with both flags on, the backfill reads the log and stops. The only history-derived output today is the store itself.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:194` wasProgrammedByPumpUI: !isCommandedBolus(completion.bolusId) — only place the flag is set
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:19` HistoryToDoseMapper().mapToEvents( — the sole caller of mapToEvents in the repo
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:9` Nothing is mapped to doses or emitted here — that is the emission layer's job
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:59` guard pumpManager?.state.featureFlags.historyBackfill == true else { return }
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:38` historyBackfill and historyDoseReporting both default to false

- Recommendation: Build the emission layer: after each tick, map new/changed store entries above emitFloor with HistoryToDoseMapper and emit them (gated on historyDoseReporting). Until then, document that pump-side boluses are not counted in IOB.

**P08-2 Live status path ignores pump-UI and Control-IQ boluses** (Non-conforming, impact high, unverified)

fetchBolusStatus (from sync and from the .bolusChange qualifying event) only acts when bolusProgressReport exists, i.e. a bolus enactBolus started in this process. A bolus started on the t:slim X2 touchscreen, via Tandem's Mobi app, or by Control-IQ's auto-correction shows up as status .delivering with a bolusId Loop did not issue, and the code returns without emitting anything; when it completes, state is cleared silently. The response already carries bolusSource, which would let the driver set wasProgrammedByPumpUI/automatic correctly, but it is never read. The quick-bolus-button lockout (default) is a partial mitigation only: it does not cover the touchscreen, the Mobi phone app, or Control-IQ, which remains enactable for manual Loop boluses.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:227` guard let progressReport = bolusProgressReport else { return }
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:218` if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil { ...clear state, no event }
  - `Sources/TandemCore/Messages/CurrentStatus/CurrentBolusStatus.swift:85` public var bolusSource: BolusSource? — quickBolus/gui/controlIQAutoBolus/bluetoothRemoteBolus, unused by TandemKit
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:517` if state.useControlIQ, activationType.isAutomatic — only automatic Loop boluses are blocked under Control-IQ
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:362` guard !state.featureFlags.quickBolusButtonSupport, state.quickBolusEnabled == true — driver turns the quick-bolus button off

- Recommendation: In fetchBolusStatus, when status is .delivering/.alreadyDeliveredOrInvalid for a bolusId not in bolusDose, emit a dose keyed by HistoryLogSyncIdentifier.bolus with wasProgrammedByPumpUI = (bolusSource != .bluetoothRemoteBolus) and automatic = (bolusSource == .controlIQAutoBolus), finalizing via LastBolusStatus.

**P08-3 Live basal path misses pump-UI temp rates and Control-IQ modulation** (Non-conforming, impact high, unverified)

When the user sets a temp rate on the pump, CurrentBasalStatusResponse.basalType becomes .tempBasal; fetchBasalStatus enters the change block, computes getActivePumpEvents (empty when basalDose is .basal), then hits neither branch and returns with no emission and no state change, so the check repeats every sync forever. Control-IQ basal increases/attenuation arrive with other bitmask values, map to .basal, and are reported as the app's scheduled rate, never the pump's currentBasalRate. HomeScreenMirror's BasalStatusIcon does distinguish tempRate/increaseBasal/attenuatedBasal, but handleHomeScreenMirrorResponse is unreachable and QualifyingEventFetch drops HomeScreenMirrorRequest. No wasProgrammedByPumpUI is possible because no dose is produced.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:141` if activeBasalType != state.basalDose.type { — only .suspend and .basal branches follow; .tempBasal falls through
  - `Sources/TandemCore/Messages/CurrentStatus/CurrentBasalStatus.swift:44` basalType: 0x01 → .suspend, 0x02 → .tempBasal, default → .basal
  - `Sources/TandemCore/Messages/CurrentStatus/CurrentBasalStatus.swift:56` currentBasalRate (pump's actual delivered rate) is never read by the driver
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:170` basalRate: getScheduledBasalRate() — emitted basal uses the app's schedule, not the pump's rate
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:474` func handleHomeScreenMirrorResponse — no callers anywhere in Sources/

- Recommendation: Add a .tempBasal branch to fetchBasalStatus (TempRateRequest gives percent/remaining; multiply by profileBasalRate, key by tempRateId, set wasProgrammedByPumpUI=true, isMutable=true). For Control-IQ modulation, report currentBasalRate as a .basal/.tempBasal dose with automatic=true.

**P08-4 Pump-initiated suspend/resume emitted without pump-UI flag** (Partial, impact low, unverified)

Unlike boluses and temp rates, a suspend or resume performed on the pump is detected (via sync or the pumpSuspend/pumpResume qualifying event) and does produce a dose event, so the insulin-stopped window is accounted for. However UnfinalizedDose.toDoseEntry never passes wasProgrammedByPumpUI, so a pump-UI suspend is indistinguishable from a Loop-commanded one; the same applies to the mapper's suspend/resume builders. The start time is the detection time, not the pump's, which is a timing gap (covered elsewhere) rather than a flag gap.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:153` let dose = UnfinalizedDose(suspendStartTime: now) — pump-detected suspend emitted at detection time
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:197` DoseEntry(suspendDate: startDate, automatic: automatic) — wasProgrammedByPumpUI left at default false
  - `Sources/TandemKit/PumpManager/QualifyingEventFetch.swift:80` pumpSuspend/pumpResume → .basalStatus so the suspend/resume dose is emitted
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:98` history suspend dose also built without wasProgrammedByPumpUI

- Recommendation: Thread a wasProgrammedByPumpUI parameter through UnfinalizedDose.toDoseEntry and set it true in fetchBasalStatus/handleHomeScreenMirrorResponse and in the mapper's suspend/resume builders.

**P08-5 Mapper metadata gaps for the future history path** (Partial, impact medium, unverified)

The mapper's shape is right for boluses (flag derived from a commanded-id predicate, as MinimedKit derives it from wasRemotelyTriggered), but nothing in the driver can supply that predicate: only the in-flight bolusDose.bolusId is kept and it is cleared on completion, so a completed Loop bolus later found in history would be marked wasProgrammedByPumpUI=true. Temp rates from history carry no pump-UI flag at all, and neither `automatic` nor bolusSource (available on BolusDeliveryHistoryLog) is used, so a Control-IQ auto-correction would be reported as a user bolus with automatic=nil. Not exercised today because of P08-1.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:42` isCommandedBolus: (Int) -> Bool — caller-supplied; no production implementation exists
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:9` public var bolusId: Int? — only one commanded id tracked, on the current bolusDose
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:263` state.bolusDose = nil — commanded bolusId forgotten at completion
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:252` tempBasal DoseEntry built with no wasProgrammedByPumpUI argument
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:184` bolus DoseEntry built with no automatic: argument — Control-IQ auto boluses indistinguishable from user boluses

- Recommendation: Persist a bounded set of commanded bolusIds (and tempRateIds) in TandemPumpManagerState for the predicate; read BolusDeliveryHistoryLog.bolusSource to set automatic for controlIQAutoBolus; add wasProgrammedByPumpUI to tempBasalEvent for non-commanded tempRateIds.

**P08-6 No reconciliation of pending doses against history (identity bridge)** (Non-conforming, impact high, unverified)

§7 expects Loop-commanded doses to be reconciled against pump history (MinimedKit: 1-minute window). TandemKit's intended mechanism is stronger — pump-assigned bolusId/tempRateId in a stable raw — but it is half-built: enactBolus/cancelBolus/fetchBolusStatus still mint raw from type+units+ISO date, while the mapper mints HistoryLogSyncIdentifier bytes. If the emission layer were switched on today, every Loop-commanded bolus would appear twice (optimistic row plus history row) because the identities do not match and replacePendingEvents only purges mutable rows. Today, finalization relies solely on LastBolusStatus by bolusId; a bolus whose completion is missed (disconnect past the 30 s grace, relaunch) is never recovered from history.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:10` raw: "\(DoseType.bolus.rawValue) \(units) \(dateFormatter.string(from: date))" — optimistic identity
  - `Sources/TandemKit/PumpManager/History/HistoryLogSyncIdentifier.swift:45` Nothing emits these identifiers yet — NewPumpEvent's raw values are still built from the dose type, volume and timestamp
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:183` raw = HistoryLogSyncIdentifier.bolus(pumpSerial:bolusId:) — different bytes from the optimistic raw
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:584` bolusId: permissionResponse.bolusId — pump id known at command time but not used in raw
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:257` actualDelivered = queryLastBolusDeliveredVolume(bolusId: bolusId) — finalization comes from status, never history

- Recommendation: Before wiring emission, make enactBolus/cancelBolus/getPumpEvent use HistoryLogSyncIdentifier.bolus (and enactTempBasal use tempRateId from TempRateRequest) as raw once pumpSerial is known, so history confirmations update in place instead of duplicating.

Open questions raised by this point:

- lastReconciliation (P05/P06 scope) is advanced by status reads in syncPumpData and by fetchReservoirStatus, not by a full history read; for a UI-capable pump the guide requires the latter, so once history emission exists lastReconciliation semantics need revisiting.
- After app relaunch, state.bolusDose is restored but bolusProgressReport is nil; fetchBolusStatus then clears bolusDose with no event (+StateSync.swift:218-224), so the previously-reported mutable Loop bolus is purged by the next replacePendingEvents:true emission — a P03/P04 concern, not P08.
- fetchBasalStatus emits a .basal dose (not .resume) when the pump leaves suspend, and returns early on .resume→.basal; whether Loop/Trio needs a .resume event here belongs to P10.
- BolusDeliveryHistoryLog.BolusType bitmask differs from Models/BolusDelivery.swift BolusType (validated vs guessed); enactBolus uses the latter's .food2 = 8 for InitiateBolusRequest — worth confirming against pumpX2, outside P08.
- Whether Tandem's Mobi app and Control-IQ boluses appear in CurrentBolusStatusResponse with bolusSource .gui/.controlIQAutoBolus (vs only in history) would need a hardware capture to confirm the P08-2 recommendation.
### P09. decisionId is threaded from enactBolus/enactTempBasal through to the DoseEntry

Guide section: §9 item 9.

Overall: **Partial** (auditor's own overall: Not applicable; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

decisionId does not exist in the LoopKit TandemKit builds against. Trio's pinned loopandlearn fork (rev 0229bb18, unit-tests.yml:46) declares enactBolus(units:activationType:) and enactTempBasal(unitsPerHour:for:) with no decisionId, and its DoseEntry has no such field; the Linux shim matches. TandemKit's signatures mirror the fork exactly and the repo has zero references to decisionId, so the item is not applicable today. Forward-looking: next-dev makes decisionId a required DoseEntry init parameter, and TandemKit has no slot for a host-side id — UnfinalizedDose carries only a pump-assigned bolusId (persisted) and reduces activationType to a Bool. The surrogate metadata actually used (automatic/manuallyEntered) is lossy and inconsistent between the mutable and finalized bolus, with manuallyEntered=true applied to pump-delivered boluses.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P09-1 | Not applicable | none | unverified | decisionId absent from the pinned LoopKit API |
| P09-2 | Partial | none | unverified | Readiness: correlation id slot for a future decisionId |
| P09-3 | Partial | medium | unverified | activationType surrogate is lossy and inconsistent across bolus lifecycle |
| P09-4 | Partial | low | unverified | Temp basal and history-derived doses: automatic flag conventions |

**P09-1 decisionId absent from the pinned LoopKit API** (Not applicable, impact none, unverified)

The guide's §9 item 9 presupposes the next-dev API where enactBolus/enactTempBasal receive `decisionId: UUID?` and DoseEntry stores it. TandemKit is built (per Package.swift and CI) against Trio's loopandlearn fork, whose PumpManager protocol and DoseEntry have no decisionId at all, and the Linux shim matches. TandemKit's method signatures are the fork's verbatim; a repo-wide grep for `decisionId` returns nothing. There is therefore nothing to thread and nothing to violate on the current target, on any path (steady state, first sync, reconnect, relaunch).

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:510` enactBolus takes `activationType: BolusActivationType,` and no decisionId
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:663` enactTempBasal(unitsPerHour:for:completion:) — no decisionId parameter
  - `reference: loopkit-trio/PumpManager.swift:199` fork protocol: `func enactBolus(units: Double, activationType: BolusActivationType, completion:`
  - `reference: loopkit-trio/DoseEntry.swift:40` fork DoseEntry init has no decisionId parameter
  - `LinuxShims/LoopKit/LoopKit.swift:272` Linux shim enactBolus likewise has no decisionId

- Recommendation: No action for the current Trio target. Track the requirement against the LoopKit bump that introduces decisionId (see P09-2).

**P09-2 Readiness: correlation id slot for a future decisionId** (Partial, impact none, unverified)

For boluses a durable correlation key exists: the pump-assigned bolusId is stored on UnfinalizedDose, persisted in manager state, and used by HistoryLogSyncIdentifier so a history confirmation can match the optimistic report. A future decisionId could be stored alongside it. But nothing in UnfinalizedDose, its rawValue, or toDoseEntry has a slot for a host-supplied UUID, and temp basals carry no id of any kind. On next-dev, DoseEntry's initializer makes decisionId a required argument, so every construction site (UnfinalizedDose.toDoseEntry, the DoseEntry extension, HistoryToDoseMapper) would need changes, and the value would have to be persisted in rawValue — not in the in-memory TandemDoseProgressReporter — to survive relaunch.

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:9` `public var bolusId: Int?` — the only correlation id on a tracked dose
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:585` `bolusId: permissionResponse.bolusId` — id is pump-assigned, not host-assigned
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:141` `raw["bolusId"] = bolusId` — bolusId survives relaunch via rawValue
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:444` `raw["bolusDose"] = bolusDose.rawValue` persists the in-flight bolus
  - `Sources/TandemKit/PumpManager/History/HistoryLogSyncIdentifier.swift:102` `static func bolus(pumpSerial:bolusId:)` mints a stable identity from the pump bolusId

- Recommendation: When adopting a decisionId-bearing LoopKit: add `decisionId: UUID?` to UnfinalizedDose (bolus and tempBasal inits, rawValue round-trip) and pass it through toDoseEntry; give temp basals a stable identity (pump tempRateId if the set response exposes it).

**P09-3 activationType surrogate is lossy and inconsistent across bolus lifecycle** (Partial, impact medium, unverified)

Because the fork has no decisionId, the only Loop-side provenance TandemKit records is `automatic`/`manuallyEntered`. The in-progress and cancel representations (UnfinalizedDose.toDoseEntry) carry `automatic` only, while the normal-completion representation (TandemDoseProgressReporter → DoseEntry.bolus) also sets `manuallyEntered = true` for `.manualNoRecommendation`. So the same bolus flips metadata between mutable and finalized, and differs depending on whether it completed or was cancelled. In LoopKit, `manuallyEntered` denotes insulin the user logged that the pump did not deliver; `getManuallyEnteredDoses`/`deleteAllManuallyEnteredDoses` select on it. Flagging a pump-delivered bolus this way misdescribes it and exposes it to host flows that manage external insulin. The fork's getNormalizedDoseEntries does not filter on the flag, so IOB inside LoopKit is unaffected.

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:33` `automatic = activationType.isAutomatic` — five-case enum collapsed to a Bool
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:163` mutable/cancel bolus DoseEntry sets `automatic:` only; manuallyEntered left false
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:17` `private let activationType: BolusActivationType` kept only in memory
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:35` finalized event built via DoseEntry.bolus(... activationType:)
  - `Sources/TandemCore/Common/Extensions/DoseEntry.swift:24` `manuallyEntered: activationType == .manualNoRecommendation` on a pump-delivered bolus

- Recommendation: Never set manuallyEntered on pump-delivered doses; derive `automatic` from activationType in one place (UnfinalizedDose) and use it for mutable, cancelled and finalized entries alike. Persist activationType (or automatic) in rawValue rather than the reporter.

**P09-4 Temp basal and history-derived doses: automatic flag conventions** (Partial, impact low, unverified)

With no decisionId or activation type available for temp basals in the fork API, TandemKit assumes every enacted temp basal is automatic, matching the common Loop-only-driver convention; this is acceptable but is duplicated in an unused DoseEntry.tempBasal helper that can drift. History-derived boluses (the path that would surface Control-IQ automatic corrections and pump-UI quick boluses on this UI-capable pump) leave `automatic` nil and rely solely on wasProgrammedByPumpUI. That mapper is not connected to any emission path today (only tests call it), so this is a design note rather than a live defect.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:768` `automatic: true,` hard-coded for every Loop-commanded temp basal
  - `reference: loopkit-trio/PumpManager.swift:215` fork enactTempBasal passes no automatic/activation info to the driver
  - `Sources/TandemCore/Common/Extensions/DoseEntry.swift:60` unused DoseEntry.tempBasal helper also hard-codes `automatic: true`
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:194` history bolus sets `wasProgrammedByPumpUI: !isCommandedBolus(...)` but never `automatic`
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:19` only caller of HistoryToDoseMapper().mapToEvents is a test — mapper not wired into emission

- Recommendation: Remove or route through the unused DoseEntry.tempBasal helper. When the history mapper is wired, set `automatic` for Control-IQ-originated boluses (distinguishable from user quick boluses via bolus type/source fields) so host UIs classify them correctly.

Open questions raised by this point:

- Does Trio ever call DoseStore.deleteAllManuallyEnteredDoses or present manuallyEntered==YES doses as 'external insulin' in its UI? If so, a finalized .manualNoRecommendation bolus (P09-3) could be deleted or misclassified by the host; this cannot be verified from the TandemKit repo.
- Does SetTempRateResponse (or TempRateResponse) expose the pump's tempRateId at command time? If it does, temp basals could get a stable pump-side identity analogous to bolusId, which any future decisionId mapping could ride on. Not verified in this audit.
- After an app relaunch mid-bolus, bolusProgressReport is nil (TandemPumpManager.swift:70, in-memory) and fetchBolusStatus returns before emitting the finalized bolus event (TandemPumpManager+StateSync.swift:226 `guard let progressReport = bolusProgressReport else { return }`). This concerns finalization (other checklist items), not decisionId, but it also means any provenance kept on the reporter is lost across relaunch.
- The guide (§2) describes DoseEntry.decisionId as an existing field; that is true only for loopkitdev/LoopKit next-dev. Trio's pinned loopandlearn fork and the Linux shim have no such field, so guide and target API disagree on this point.
### P10. Suspend/resume, prime, alarm, and pump-replacement events are emitted with appropriate PumpEventType values

Guide section: §9 item 10.

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

App-commanded suspend/resume are emitted as proper .suspend/.resume dose events, and the UI cartridge/cannula wizards emit .rewind and .replaceComponent(.infusionSet). Gaps: a resume performed on the pump itself is detected by CurrentBasalStatus polling and emitted as a .basal dose with no .resume, which can leave an open suspend in Loop/Trio (the only correct handler, handleHomeScreenMirrorResponse, has no callers). No .prime event is ever emitted despite tubing/cannula fill volumes being known. No live path emits NewPumpEvent(type: .alarm); the history mapper does (without alarmType) but is unwired and behind two default-off flags. Site/cartridge changes made on the pump UI are never detected (CannulaFilled/CartridgeFilled logs ignored). No tests assert emitted PumpEventType on manager paths.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P10-1 | Conforms | none | unverified | App-commanded suspend/resume event types |
| P10-2 | Non-conforming | high | unverified | Pump-UI resume emitted as .basal, never .resume |
| P10-3 | Partial | low | unverified | Cartridge change as .rewind, wizard-only |
| P10-4 | Partial | low | unverified | Site change as .replaceComponent(.infusionSet), wizard-only |
| P10-5 | Non-conforming | medium | unverified | No .prime event for tubing or cannula fills |
| P10-6 | Non-conforming | low | unverified | Alarms not emitted as pump events on any live path |
| P10-7 | Not applicable | none | unverified | Pump replacement / deactivation events |
| P10-8 | Partial | none | unverified | Test coverage of emitted PumpEventType |

**P10-1 App-commanded suspend/resume event types** (Conforms, impact none, unverified)

suspendDelivery and sendResumePumping build DoseEntry(suspendDate:)/DoseEntry(resumeDate:) and wrap them with NewPumpEvent.suspend/.resume. The factories pass no explicit PumpEventType, so the type comes from LoopKit's `type ?? dose?.type.pumpEventType` inference, which yields .suspend/.resume on Apple builds (Trio-pinned and next-dev LoopKit behave identically here). A suspend performed on the pump and seen by CurrentBasalStatus polling (fetchBasalStatus) is also emitted as .suspend. Holds in steady state, after reconnect (qualifying .pumpSuspend/.pumpResume force a basalStatus fetch) and after relaunch (basalDose persisted). Only the Linux shim leaves `type` nil, which affects Linux tests, not production.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:822` events.append(NewPumpEvent.suspend(dose: suspendDose.toDoseEntry(), date: suspendDose.startDate))
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:904` let events = [NewPumpEvent.resume(dose: dose.toDoseEntry(), date: dose.startDate)]
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:197` case .suspend: return DoseEntry(suspendDate: startDate, automatic: automatic)
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:46` static func suspend(...) passes no explicit `type:`; relies on LoopKit inference
  - `reference: loopkit-trio/NewPumpEvent.swift:37` self.type = type ?? dose?.type.pumpEventType

- Recommendation: Pass `type: .suspend` / `type: .resume` explicitly in the NewPumpEvent factories so the type does not depend on LoopKit inference and is identical on the Linux shim. Confirm `DoseType.pumpEventType` in the pinned LoopKit maps suspend/resume as expected (file not in the reference set).

**P10-2 Pump-UI resume emitted as .basal, never .resume** (Non-conforming, impact high, unverified)

When the user resumes on the pump (t:slim X2 touchscreen, Tandem app, or after clearing an alarm), the only live detection path is fetchBasalStatus, which sees basalType .basal while state.basalDose is .suspend and emits a .basal dose only — no .resume. The trio-pinned DoseStore extends an unclosed suspend to `end`, and InsulinMath.reconciled() (not in the reference set, so unverified on disk) closes a suspend only at a .resume, so Loop can keep treating delivery as suspended after the pump has resumed, under-counting basal IOB. The correct suspend->resume transition exists in handleHomeScreenMirrorResponse, but grep finds no caller (dead code) and it mislabels the resume as NewPumpEvent.basal. The history mapper emits .resume correctly but is unwired and behind default-off flags.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:166` if activeBasalType == .basal { ... } — branch reached when state.basalDose.type == .suspend
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:173` events.append(NewPumpEvent.basal(dose: dose.toDoseEntry(), ...)) — no resume event
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:492` handleHomeScreenMirrorResponse: if state.basalDose.type == .suspend { dose = UnfinalizedDose(resumeStartTime: ...) }
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:504` ...but wraps it as NewPumpEvent.basal (title "Basal", raw "basal ...")
  - `Sources/TandemKit/PumpManager/QualifyingEventFetch.swift:80` pumpSuspend/pumpResume -> .basalStatus -> fetchBasalStatus (the only live detection path)

- Recommendation: In fetchBasalStatus, when the previous basalDose is .suspend and the pump reports .basal (or .tempBasal), emit NewPumpEvent.resume first, then the basal dose. Fix or delete handleHomeScreenMirrorResponse's NewPumpEvent.basal wrapping of a resume dose. Add a test asserting the delegate receives a .resume event.

**P10-3 Cartridge change as .rewind, wizard-only** (Partial, impact low, unverified)

A cartridge change performed through TandemKit's wizard is reported as a dose-less .rewind event with replacePendingEvents:false (correct per guide §5) and a date-stamped raw. .rewind is the legacy Medtronic-era reservoir-change type that Loop/Trio have historically consumed (e.g. Nightscout 'Insulin Change'); .replaceComponent(.reservoir) is the newer semantic type the guide's §10 points to. DoseStore itself does not act on either (it only inspects .prime), so this is metadata only. The gap is coverage: a cartridge change done on the pump's own UI (t:slim X2) is never detected — CartridgeFilledHistoryLog is parsed by TandemCore but HistoryToDoseMapper drops it, and the mapper is unwired anyway.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:78` type: .rewind
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1071` emitPumpEvents([NewPumpEvent.cartridgeChange(date: date)], replacePendingEvents: false)
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitChangeCartridgeViewModel.swift:319` pumpManager?.recordCartridgeChange() — only caller, inside the app's wizard
  - `Sources/TandemCore/Messages/HistoryLog/CartridgeFilledHistoryLog.swift:4` public static let typeId = 33 — parsed but never mapped
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:118` default: continue — CartridgeFilled/CannulaFilled/TubingFilled logs dropped

- Recommendation: Keep .rewind unless Trio/Loop consumers are confirmed to handle .replaceComponent(.reservoir); document the choice. Add CartridgeFilledHistoryLog -> cartridgeChange mapping (raw = HistoryLogSyncIdentifier) so pump-UI cartridge changes are captured once history emission is wired.

**P10-4 Site change as .replaceComponent(.infusionSet), wizard-only** (Partial, impact low, unverified)

The fill-cannula wizard emits .replaceComponent(.infusionSet) only after the pump's FillCannulaStateStream reports .cannulaFilled, with a stable date-stamped raw and replacePendingEvents:false so an in-flight mutable dose is not purged. That is the appropriate type. As with the cartridge event, a cannula fill done on the pump itself is never surfaced: CannulaFilledHistoryLog (typeId 61) is parsed by TandemCore but ignored by the mapper's switch, and the mapper is unwired. The event carries no dose, so accounting impact is limited to upstream site-age tracking.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:65` type: .replaceComponent(componentType: .infusionSet)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1062` emitPumpEvents([NewPumpEvent.siteChange(date: date)], replacePendingEvents: false)
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitFillCannulaViewModel.swift:172` pumpManager?.recordSiteChange(primeAmount: primeAmount) — after .cannulaFilled stream
  - `Sources/TandemCore/Messages/HistoryLog/CannulaFilledHistoryLog.swift:7` public let primeSize: Float — available but never mapped

- Recommendation: Map CannulaFilledHistoryLog (completionStatus == .completed) to the same siteChange event, keyed by HistoryLogSyncIdentifier, so pump-UI site changes are reported once history emission exists.

**P10-5 No .prime event for tubing or cannula fills** (Non-conforming, impact medium, unverified)

grep over Sources finds no NewPumpEvent with type .prime; the only mentions are the shim enum and UI strings. Both fill flows know the volume (cannula prime in units from the wizard; TubingFilled/CannulaFilled history logs carry primeSize) but nothing reports it. TandemKit correctly does not report fills as insulin doses. However .prime is the one non-dose type DoseStore acts on: it marks reservoir data non-continuous so a tubing fill (a large reservoir drop) is not mistaken for delivery when reservoir-derived doses are in use. Exposure therefore depends on whether TandemKit ever leaves reservoir data newer than lastReconciliation (another point). Trio's Nightscout uploads also derive site-change markers from prime events (not verifiable from the reference set).

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1045` FillCannulaRequest(primeSizeMilliUnits: Int(amount * 1000)) — prime volume known, no event
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1029` ExitFillTubingModeRequest — tubing fill completes with no pump event
  - `Sources/TandemCore/Messages/HistoryLog/TubingFilledHistoryLog.swift:15` public let primeSize: Float — parsed, never mapped
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:118` default: continue — TubingFilled/CannulaFilled dropped
  - `reference: loopkit-trio/DoseStore.swift:723` if case .prime? = event.type { primeValueAdded = true }

- Recommendation: Emit NewPumpEvent(type: .prime, dose: nil, title: "Prime N U") with replacePendingEvents:false when the tubing fill exits successfully and alongside recordSiteChange (cannula prime). Later, map TubingFilled/CannulaFilledHistoryLog(completed) to .prime via HistoryLogSyncIdentifier.

**P10-6 Alarms not emitted as pump events on any live path** (Non-conforming, impact low, unverified)

Pump alarms/malfunctions reach the host only as LoopKit Alerts (reconcileLoopKitAlerts), never as NewPumpEvent(type: .alarm, alarmType:). The only code that builds a .alarm event is HistoryToDoseMapper.alarmEvent, which (a) has no production caller — mapToEvents is invoked only from tests and HistoryBackfillCoordinator explicitly emits nothing, (b) is gated by two default-off flags, (c) leaves alarmType nil although AlarmActivatedHistoryLog.alarmResponseType could map occlusion/no-delivery/low-power, and (d) also maps AlertActivatedHistoryLog (e.g. reminders/low reservoir) as .alarm and never emits .alarmClear. Alarm events do not change IOB, but an alarm-induced auto-suspend is only picked up via the basalStatus fetch (P10-2), not via the alarm.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+Alerts.swift:114` delegate.issueAlert(item.loopKitAlert(managerIdentifier:)) — Alert issuance only
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:296` type: .alarm — but no alarmType, dose nil; alerts also mapped as .alarm (line 90)
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:9` Nothing is mapped to doses or emitted here — that is the emission layer's job
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:37` historyBackfill / historyDoseReporting default false
  - `Sources/TandemCore/Messages/HistoryLog/AlarmActivatedHistoryLog.swift:76` alarmResponseType available for a PumpAlarmType mapping

- Recommendation: When fetchNotifications first sees an active alarm/malfunction, emit NewPumpEvent(type: .alarm, alarmType:) keyed by notification id+timestamp with replacePendingEvents:false, and .alarmClear on retraction. In the mapper, map AlarmActivated to PumpAlarmType, and reconsider emitting alerts as .alarm.

**P10-7 Pump replacement / deactivation events** (Not applicable, impact none, unverified)

Tandem t:slim X2 and Mobi are durable pumps, not pods/patches: removing the driver does not stop insulin (the pump continues its own basal), so the MedtrumKit lesson of emitting a suspend on force-remove does not transfer, and emitting one would falsely zero basal in Loop. Replacing the physical pump requires re-pairing and a new manager instance, at which point .replaceComponent(.pump) has no continuous dose timeline to annotate. The two replaceable Tandem components (cartridge, infusion set) are covered by P10-3/P10-4.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1117` prepareForDeactivation: tears down transport, emits no suspend or replaceComponent(.pump)
  - `reference: loopkit-trio/PumpEventType.swift:89` case pump // Base, pod or patch full replacement

- Recommendation: No change. Optionally document in the driver README why no suspend/pump-replacement event is emitted on deactivation, so a future contributor does not add one by analogy with patch pumps.

**P10-8 Test coverage of emitted PumpEventType** (Partial, impact none, unverified)

The mapper's suspend/resume/alarm types are unit-tested, but no test inspects the NewPumpEvent.type or replacePendingEvents flag actually delivered to the delegate by suspendDelivery, resumeDelivery, fetchBasalStatus, recordSiteChange or recordCartridgeChange, which is exactly where P10-2 hides. On Linux, the shim's NewPumpEvent does not infer type from the dose, so such a test would need the explicit `type:` recommended in P10-1 to pass on both platforms.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:36` var pumpEvents: [NewPumpEvent] — captured but no test asserts .type on manager paths
  - `Tests/TandemKitTests/TandemPumpManagerSuspendDeliveryTests.swift:104` XCTAssertEqual(manager.state.basalDose.type, .suspend) — checks state, not the emitted event
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:273` XCTAssertEqual(suspend.type, .suspend) — mapper-only coverage
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:293` XCTAssertEqual(event.type, .alarm)

- Recommendation: Add delegate-level tests via StubPumpBluetooth asserting: suspend emits .suspend; pump-side resume emits .resume then .basal; site/cartridge emit their types with replacePendingEvents:false; fill flows emit .prime.

Open questions raised by this point:

- InsulinMath.reconciled() (LoopKit/InsulinKit/InsulinMath.swift) and DoseType.pumpEventType (DoseType.swift) are not in the reference set; P10-2's severity and P10-1's inference claim rest on their well-known behaviour and should be confirmed against the Trio-pinned LoopKit checkout.
- How Trio (nightscout/Trio PumpHistoryStorage / NightscoutManager) consumes .rewind vs .replaceComponent(.reservoir) and .prime for its cannula/insulin-age display and Nightscout Site Change / Insulin Change uploads was not verifiable from disk; it decides whether .rewind should be replaced.
- After sendResumePumping the driver stores a .resume basalDose and fetchBasalStatus deliberately returns early for basalType .basal, so no scheduled .basal dose follows the resume; whether LoopKit's basal overlay covers this is a basal-reporting question outside P10.
- handleHomeScreenMirrorResponse (StateSync.swift:473) has no callers; the pump's HomeScreenMirror is also not in QualifyingEventFetch. Whether it is intended to be wired or removed affects where the P10-2 fix belongs.
- The Linux shim's NewPumpEvent lacks `alarmType` and type inference (LinuxShims/LoopKit/LoopKit.swift:537-557); any future alarmType-carrying event will need a shim update to compile on Linux.
### P11. A running temp basal keeps a stable syncIdentifier across every update, is finalized (not dropped) on reconnect, and its deliveredUnits are rounded to the pump increment

Guide section: §10 pitfall: temp basal finalization and overwrite.

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

A running TBR is finalized, not overwritten, when Loop replaces or cancels it, and it survives BLE reconnect and app relaunch because state.basalDose is persisted and the next sync's fetchBasalStatus finalizes it (clamped to the programmed end on natural expiry). However the raw key is "tempBasal <programmedUnits> <start>", and LoopKit computes programmedUnits from the entry's endDate, so every early finalization (Loop's 5-minute re-issue, suspend, Control-IQ enable, pump-side cancel) changes the syncIdentifier; the correct end state depends on the replacePendingEvents purge, the §4 anti-pattern. Pump-side cancellation is stamped at sync time rather than the pump's stop time, deliveredUnits is an unrounded rate×duration product, and the reported rate is derived from the app's schedule rather than the pump's profileBasalRate just fetched.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P11-1 | Partial | medium | unverified | Temp basal syncIdentifier stability through finalization |
| P11-2 | Conforms | none | unverified | Replacing/cancelling a running TBR finalizes instead of overwriting |
| P11-3 | Conforms | none | unverified | TBR survives BLE reconnect and app relaunch |
| P11-4 | Partial | medium | unverified | Pump-side TBR stop stamped at sync time, not pump time |
| P11-5 | Non-conforming | low | unverified | deliveredUnits rounding to pump increment |
| P11-6 | Partial | medium | unverified | Reported rate derived from app schedule, not pump's profile rate |

**P11-1 Temp basal syncIdentifier stability through finalization** (Partial, impact medium, unverified)

The mutable TBR re-reports (endDate = estimatedEndDate) and the natural-expiry finalization (clamped to estimatedEndDate) produce byte-identical raw, so identity is stable on those paths. But when a TBR is ended early — Loop re-issuing a TBR via enactTempBasal, suspendDelivery, configureControlIQMode, or fetchBasalStatus detecting a pump-side stop — the finalized entry's endDate is now, programmedUnits shrinks, and the raw/syncIdentifier changes. DoseStore still reaches the right end state because replacePendingEvents:true purges every mutable row regardless of identity, and InsulinDeliveryStore soft-deletes unmatched mutables. This is exactly the MedtrumKit pattern §4 warns against: correctness rests on the purge safety net, not identity matching, and no test asserts key stability across cancellation.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:20` raw: "\(DoseType.tempBasal.rawValue) \(dose.programmedUnits) \(date)" — key embeds programmedUnits
  - `reference: loopkit-trio/DoseEntry.swift:72` case .unitsPerHour: return value * hours — hours = endDate - startDate
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:177` var actualEndDate = isMutable ? estimatedEndDate : endDate — finalized entry gets a different endDate
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:178` clamp to estimatedEndDate only when endDate exceeds it (natural expiry keeps key stable)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` toDoseEntry(isMutable: endDate == nil, endDate: endDate ?? Date.now) — early finalization uses now

- Recommendation: Build the raw key from the UnfinalizedDose's own stable fields (value × programmed duration, or startDate alone) rather than DoseEntry.programmedUnits, so cancellation never changes it. Add a test asserting the mutable and finalized raw are equal for early cancel.

**P11-2 Replacing/cancelling a running TBR finalizes instead of overwriting** (Conforms, impact none, unverified)

On enactTempBasal with a TBR already running the driver stops the pump's temp rate, then emits in one batch: the old TBR as an immutable DoseEntry with endDate = the new dose's startDate and computed deliveredUnits, plus the new TBR as mutable. The zero-duration/100% path likewise finalizes the old TBR and emits the scheduled basal. suspendDelivery and configureControlIQMode follow the same finalize-then-replace shape. The old TBR's end is stamped a few seconds after the actual StopTempRate (at the new dose's Date.now), which is negligible. There is no code path that re-emits a different TBR under the old dose's slot without first finalizing it.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:705` if currentBasal.basalType == .tempBasal { StopTempRateRequest ... }
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:771` var events = self.getActivePumpEvents(endDate: dose.startDate) — old TBR finalized at new start
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:772` events.append(NewPumpEvent.tempBasal(dose: dose.toDoseEntry(isMutable: true) ...)) — new TBR mutable
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:738` cancel-only path (duration 0 / 100%) finalizes via getActivePumpEvents(endDate:) and emits a basal
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1715` if endDate != nil, basalEntry.endDate == estimatedEndDate — scheduled basal appended on natural expiry

- Recommendation: Keep the finalize-then-start ordering; consider stamping the old TBR's end at the StopTempRate response time rather than the new dose's start to remove the small overlap gap.

**P11-3 TBR survives BLE reconnect and app relaunch** (Conforms, impact none, unverified)

Neither the disconnect callback nor the Bluetooth-off path modifies basalDose or emits events, and auto-reconnect only re-establishes the link. Because UnfinalizedDose is persisted inside TandemPumpManagerState, the same startDate/estimatedEndDate/value regenerate an identical raw after relaunch (ISO8601 formatting drops sub-seconds, so precision is not a factor). At the next ensureCurrentPumpData (≈5 min) or .basalChange qualifying event, fetchBasalStatus sees the pump back on profile basal and finalizes the TBR with endDate clamped to estimatedEndDate on natural expiry. No path emits replacePendingEvents:true while omitting the running TBR except sendResumePumping, which is only reachable when state already says suspended (so no TBR is pending).

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemBluetoothManager.swift:473` didDisconnectPeripheral cancels in-flight ops, marks link down, auto-reconnects — no dose state touched
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:386` raw["basalDose"] = basalDose.rawValue — TBR persisted with start/estimatedEnd/value
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:272` basalDose restored from rawValue on relaunch
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:141` if activeBasalType != state.basalDose.type — next sync finalizes the TBR when pump reports basal
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:149` var events = getActivePumpEvents(endDate: now) — finalized, not dropped

- Recommendation: Add a test that drives disconnect → reconnect → fetchBasalStatus with a stubbed CurrentBasalStatusResponse(basal) and asserts the TBR is emitted immutable with the original raw and deliveredUnits.

**P11-4 Pump-side TBR stop stamped at sync time, not pump time** (Partial, impact medium, unverified)

Natural expiry is handled correctly because toDoseEntry clamps to estimatedEndDate. But if the temp rate stops early on the pump (user cancels on the t:slim X2 screen, pump alarm, cartridge change), fetchBasalStatus finalizes the TBR at the time of the poll that noticed it. Unless the pump also emits a .basalChange qualifying event (hardware behavior, not verifiable here), that can be up to ≈5 minutes after the real stop, and deliveredUnits = rate × (poll − start) over-counts by rate × delay. The pump exposes the truth twice — TempRateResponse (start, duration) and TempRateCompletedHistoryLog — and HistoryToDoseMapper already computes min(programmedEnd, completion), but nothing consumes it.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:148` let now = Date.now; var events = getActivePumpEvents(endDate: now) — end = time of the poll
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:360` lastSync < 4.5 min short-circuits — polls are ≈5 min apart
  - `Sources/TandemCore/Messages/CurrentStatus/TempRate.swift:41` TempRateResponse carries startTimeRaw and duration but is only read in suspendDelivery
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:240` endDate = min(programmedEndDate, completionDate) — correct logic exists here
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:35` mapToEvents has no caller anywhere in Sources (grep) — mapper is not wired

- Recommendation: When fetchBasalStatus sees the TBR gone, read TempRateResponse (or the TempRateCompleted history record) and finalize at the pump's reported stop time; wire HistoryToDoseMapper's temp-rate output to reconcile the optimistic entry in place.

**P11-5 deliveredUnits rounding to pump increment** (Non-conforming, impact low, unverified)

The finalized TBR's deliveredUnits is value × elapsed hours with arbitrary double precision (e.g. 0.85 U/h × 17m23s = 0.24626… U). Tandem reports insulin in milliunits, so the guide's expectation is a value rounded to 0.001 U (or the pump's delivery increment). Only the programmed rate is snapped to the 0.01 U/h grid. This is an estimate anyway — the pump is never asked what it actually delivered for the temp rate — so the unrounded figure also misrepresents precision. Impact on IOB is sub-milliunit, but it feeds HealthKit and plotting.

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` deliveredUnits: isMutable ? nil : value * (duration / .hours(1)) — raw product, no rounding
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:229` roundToSupportedBasalRate floors the rate to the 0.01 U/h grid — value is rounded, delivered is not
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:161` roundToReportingResolution (0.001 U) exists but tempBasalEvent leaves deliveredUnits nil
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:252` history temp basal DoseEntry has no deliveredUnits argument

- Recommendation: Round the finalized temp basal deliveredUnits with HistoryToDoseMapper.roundToReportingResolution (or a shared TandemCore helper) before building the DoseEntry; do the same in the mapper's tempBasalEvent once wired.

**P11-6 Reported rate derived from app schedule, not pump's profile rate** (Partial, impact medium, unverified)

Tandem temp rates are a percent of the active profile segment. The driver converts Loop's absolute U/h to an integer percent (clamped to 250 %), then reports value = round(baseline × percent/100), which correctly reflects the quantized/clamped rate the pump will deliver rather than Loop's request. But baseline comes from the app's cached basalRateSchedule, while the pump's own profileBasalRate is in the CurrentBasalStatusResponse just fetched and ignored. If the pump's profile differs (edited on the X2 screen, a segment boundary crossed, or a failed syncBasalRateSchedule), both the percent sent and the value reported are wrong, and the finalized deliveredUnits inherits the error. Duration is truncated to whole minutes with no handling of Tandem's 15-minute minimum.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:690` let baselineRate = getScheduledBasalRate() — from state.basalRateSchedule
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:702` CurrentBasalStatusResponse fetched here exposes profileBasalRate, which is not used
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:284` percent = Int((requestedRate / baseline * 100).rounded()); clamped 0…250
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:722` absoluteRate = roundToSupportedBasalRate(baselineRate * percent/100) — reported value is the quantized rate
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:749` SetTempRateRequest(minutes: Int(duration.minutes), percent:) — no 15-minute minimum handling

- Recommendation: Use currentBasal.profileBasalRate from the fetched CurrentBasalStatusResponse as the percent baseline and reported value; after SetTempRate, read TempRateResponse to confirm percent/duration and set estimatedEndDate from it; reject or clamp durations below the pump minimum explicitly.

Open questions raised by this point:

- Does the pump emit a .basalChange qualifying event when a temp rate expires or is cancelled on the pump? That determines whether P11-4's detection latency is seconds or the ~5-minute sync interval; it is hardware behavior not determinable from the code.
- SetTempRateRequest.props is marked supportedDevices: .mobiOnly / minApi: .mobiApiV3_5, yet enactTempBasal does not check supports(). What happens on a t:slim X2 (rejected, or works) affects whether any TBR record exists to finalize on that model.
- Does Trio's implementation of pumpManager(_:hasNewPumpEvents:...) honor replacePendingEvents exactly as LoopKit's DoseStore does? P11-1's correct end state relies on that purge.
- fetchBasalStatus silently does nothing when the pump reports .tempBasal while state.basalDose is .basal (StateSync 141-187 has no branch for that case), so a TBR set on the pump UI, or one whose local record was lost, is never reported. This is a §7 (wasProgrammedByPumpUI) matter rather than P11 but interacts with it.
- Ordinary syncs with a running TBR do not call hasNewPumpEvents at all (fetchBasalStatus emits only on type change; fetchReservoirStatus only sets lastReconciliation), so the guide's 'the mutable dose is re-reported every sync' expectation is not met even though nothing purges it; this belongs to the every-sync/lastReconciliation point.
- sendResumePumping emits [resume] with replacePendingEvents:true and no getActivePumpEvents(); it is only reachable when the driver already believes delivery is suspended, but a direct resumeDelivery call while state.basalDose is .tempBasal would drop the mutable TBR unfinalized.
### P12. A bolus is registered up front as a mutable dose before contact can be lost, its in-progress state is persisted, and on reconnect the pump's own history/status supplies the delivered amount before finalizing

Guide section: §10 pitfall: bolus during BLE loss.

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

TandemKit persists the in-progress bolus (UnfinalizedDose with pump bolusId) and, when the app stays alive across a BLE drop, finalizes it from the pump's own LastBolusStatus delivered volume after the estimated end plus a 30 s grace. Two gaps break the pitfall's intent. First, the mutable dose is only registered after the pump acknowledges InitiateBolusRequest; a response timeout on a request the pump did receive yields a clean failure, no dose, and deliveryIsUncertain stays false. Second, finalization is gated on the memory-only TandemDoseProgressReporter, so after an app relaunch mid-bolus the persisted dose is cleared silently and the earlier mutable event is never finalized (later purged). Additionally the mutable bolus is not re-reported during delivery and its raw changes on partial delivery.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P12-1 | Partial | high | unverified | enactBolus registration vs InitiateBolus ack timeout |
| P12-2 | Conforms | none | unverified | In-progress bolus state persistence |
| P12-3 | Non-conforming | high | unverified | Recovery after app relaunch mid-bolus |
| P12-4 | Conforms | none | unverified | Reconnect with app alive: pump supplies delivered amount |
| P12-5 | Partial | medium | unverified | Fallbacks when the pump query fails; rounding of delivered amount |
| P12-6 | Partial | medium | unverified | Mutable bolus not re-reported during delivery; raw changes on partial delivery |
| P12-7 | Partial | low | unverified | History-log path as recovery source |

**P12-1 enactBolus registration vs InitiateBolus ack timeout** (Partial, impact high, unverified)

In steady state the mutable dose, bolusId, and lastReconciliation are recorded and emitted as soon as the pump acks InitiateBolusRequest, which is the earliest point the app knows a bolus exists — acceptable. But the write helper returns nil both when the request never left the phone and when the pump received it and the response was lost (30 s responseTimeout, or the 180 s CommandWatchdog). On that path enactBolus releases permission, reports a clean communication error and registers nothing; PumpManagerStatus never flags deliveryIsUncertain. If the pump did start the bolus, Loop/Trio has zero IOB for it and may retry, which the code's own comment identifies as a double-dose risk.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:564` guard let initiateResponse = self.bluetooth.write(bolusRequest) else { ... completion(.communication(PumpCommError.noResponse)) } — no dose registered
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:598` self.emitPumpEvents([NewPumpEvent.bolus(...)], replacePendingEvents: false) — mutable dose emitted only after wasBolusInitiated
  - `Sources/TandemKit/PumpManager/TandemPeripheralManager.swift:207` writeQ.waitForOutcome(timeout: .now() + Self.responseTimeout) ... return nil — request already written at line 200
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:131` deliveryIsUncertain: false — hard-coded in makeStatus
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:84` comment: on a bolus timeout, surfacing uncertain delivery would be safer than a clean failure. Tracked separately.

- Recommendation: On a nil/timed-out InitiateBolus response, keep bolusId and units in state.bolusDose, emit the mutable dose, and set deliveryIsUncertain until CurrentBolusStatus/LastBolusStatus confirms or denies the bolus; only then finalize or retract. Add a test with a stub that swallows the InitiateBolus response.

**P12-2 In-progress bolus state persistence** (Conforms, impact none, unverified)

The guide asks that UnfinalizedDose state not live only in memory. TandemKit persists state.bolusDose (type, value, startDate, estimatedEndDate, deliveredUnits, bolusId) and the LoopKit bolusState into rawState on every notifyDelegateStateUpdated, and decodes both on init. BLE disconnects (markLinkDown / didDisconnectPeripheral) do not touch bolusDose or bolusState, so the record survives both link loss and app termination. Whether that persisted record is actually used to recover is a separate matter (P12-3).

- Evidence:
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:443` if let bolusDose { raw["bolusDose"] = bolusDose.rawValue }
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:244` if let bolusDoseRaw = rawValue["bolusDose"] as? UnfinalizedDose.RawValue { bolusDose = UnfinalizedDose(rawValue:) }
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:141` raw["bolusId"] = bolusId — pump-assigned id survives relaunch
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:652` case let .inProgress(dose): raw["dose"] = PropertyListEncoder().encode(dose)
  - `Tests/TandemKitTests/TandemPumpManagerStateTests.swift:115` testInProgressBolusRoundTrips asserts bolusId 2004, startDate, estimatedEndDate survive

- Recommendation: No change needed for persistence itself. Consider also persisting the dose's original raw/syncIdentifier so any relaunch recovery re-reports the identical identity (see P12-3, P12-6).

**P12-3 Recovery after app relaunch mid-bolus** (Non-conforming, impact high, unverified)

The mutable bolus was reported to Loop with replacePendingEvents:false at enact time. If the app is killed and relaunched mid-bolus, state.bolusDose and bolusId are restored but bolusProgressReport is nil. On the next sync (after the grace window) fetchBolusStatus takes the `alreadyDeliveredOrInvalid && bolusProgressReport == nil` branch: it clears bolusDose/bolusState and returns without querying LastBolusStatus or emitting anything. While still delivering it hits the guard and returns. The earlier mutable event is therefore never finalized; the next replacePendingEvents:true batch (fetchBasalStatus, enactTempBasal, suspend/resume) deletes it, so the bolus vanishes from IOB. No test covers this path.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:70` internal var bolusProgressReport: TandemDoseProgressReporter? — memory-only, assigned only in enactBolus (line 588)
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:217` if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil { state.bolusDose = nil ... return } — no emitPumpEvents
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:226` guard let progressReport = bolusProgressReport else { return } — delivering branch also emits nothing
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:255` if let bolusId = state.bolusDose?.bolusId { actualDelivered = queryLastBolusDeliveredVolume(bolusId:) } — reachable only with a progressReport
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1733` func emitPumpEvents(_ events:, replacePendingEvents: Bool = true) — later batches purge the still-mutable bolus

- Recommendation: Rebuild finalization from persisted state: when state.bolusDose has a bolusId and no progress reporter exists, query LastBolusStatus for that id and emit the finalized dose (isMutable:false, deliveredUnits from the pump, same raw) before clearing state. Add a relaunch test using StubPumpBluetooth.

**P12-4 Reconnect with app alive: pump supplies delivered amount** (Conforms, impact none, unverified)

When BLE drops but the process survives, nothing resets bolusDose or bolusProgressReport (TandemBluetoothManager only flips isConnected). The pump does not replay the missed bolusChange qualifying event, so the driver relies on the periodic sync: it defers CurrentBolusStatus until estimatedEndDate + 30 s, then, once the pump reports no active bolus, reads LastBolusStatus for the tracked bolusId and finalizes with the pump's deliveredVolume rather than the time-based TandemDoseProgressReporter estimate. This matches the guide's 'pump is the source of truth' rule. ensureCurrentPumpData's 4.5-minute freshness check delays this to the next Loop poll, which is acceptable.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:194` shouldDeferBolusSync: date < bolusDose.estimatedEndDate.addingTimeInterval(bolusSyncReconcileGrace) — 30 s grace, then reconcile
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:249` if response.bolusId == 0 { ... actualDelivered = queryLastBolusDeliveredVolume(bolusId: bolusId) }
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:527` guard response.bolusId == bolusId else { return nil } — LastBolusStatus matched to the tracked bolus
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:260` events.append(progressReport.getPumpEvent(actualDeliveredUnits: actualDelivered)) — finalized with pump value
  - `Tests/TandemKitTests/TandemPumpManagerBolusSyncTests.swift:44` testSyncReconcilesAfterGraceExpires — regression for bolusChange lost to a disconnect

- Recommendation: Keep this path; consider triggering fetchBolusStatus(fromSync:true) directly from the auto-reconnect completion so a bolus interrupted by link loss is reconciled within seconds of reconnect rather than at the next poll.

**P12-5 Fallbacks when the pump query fails; rounding of delivered amount** (Partial, impact medium, unverified)

The recovery path finalizes from the pump only when LastBolusStatus answers and its bolusId matches. If that single read times out (plausible right after a reconnect) the completion path finalizes with the full programmed amount, while the cancel path finalizes with zero. Both silently commit a guess as an immutable dose that Loop will never revise, in opposite directions. Separately, the pump's milliunit deliveredVolume is floored to the 0.05 U command grid, so an interrupted bolus of e.g. 1.041 U is recorded as 1.00 U; the history mapper explicitly rounds to nearest to avoid this.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:33` let delivered = actualDeliveredUnits ?? total — assumes full delivery when LastBolusStatus fails or bolusId mismatches
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0 — cancel path assumes zero
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:532` return roundToSupportedBolusVolume(units: Double(response.deliveredVolume) / 1000.0) — floors to 0.05 U grid
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:161` roundToReportingResolution: round-to-nearest mU; comment warns flooring understates delivered IOB

- Recommendation: If LastBolusStatus fails or mismatches, keep the dose mutable and retry on the next sync instead of committing programmed or zero. Round delivered volume with round-to-nearest milliunits (as HistoryToDoseMapper does) rather than flooring to the command grid.

**P12-6 Mutable bolus not re-reported during delivery; raw changes on partial delivery** (Partial, impact medium, unverified)

After the single replacePendingEvents:false emission at enact time, the in-progress bolus is never re-sent. Any replacePendingEvents:true batch during delivery — most plausibly fetchBasalStatus detecting a temp basal that expired during a BLE outage, since enactTempBasal is blocked while the bolus runs — purges the mutable bolus from Loop, leaving IOB short until finalization re-inserts it. Finalization also mints raw from delivered units, so an interrupted bolus (delivered < programmed) gets a different syncIdentifier than the mutable one; the end state is correct only because the purge removes the stale row, the MedtrumKit safety-net pattern the guide advises against.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:230` if response.status == .delivering { ... state.bolusState = .inProgress(...) ... return } — no emitPumpEvents
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1702` getActivePumpEvents: guard state.basalDose.type == .tempBasal else { return [] } — bolus never included
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:183` fetchBasalStatus: emitPumpEvents(events) — default replacePendingEvents:true, runs even while bolus sync is deferred
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:95` raw: "\(DoseType.bolus.rawValue) \(units) \(date)" — units is part of the identity
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:44` units: delivered — final event's raw uses delivered, not programmed, units

- Recommendation: Include the in-progress bolus (same raw, isMutable:true) in getActivePumpEvents so every batch re-reports it, and build the bolus raw from programmed units (or the pump bolusId) so cancellation and partial delivery keep the identity constant.

**P12-7 History-log path as recovery source** (Partial, impact low, unverified)

The guide's reconnect recovery names the pump's history. TandemKit's recovery uses LastBolusStatus (P12-4), which is a valid pump-side source, but the richer history-log path cannot yet serve as a backstop: HistoryToDoseMapper is referenced nowhere outside its own file, HistoryBackfillCoordinator explicitly emits nothing, and both flags default to off. The mapper also keys boluses by pumpSerial+bolusId while the live path keys by units+date, so if history emission is wired on later without aligning identities, an interrupted bolus would be double-counted rather than finalized in place.

- Evidence:
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:176` historyBackfill / historyDoseReporting defaultValue: false
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:9` Nothing is mapped to doses or emitted here — that is the emission layer's job
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:207` raw = HistoryLogSyncIdentifier.bolus(pumpSerial:, bolusId:) — identity differs from the optimistic "bolus units date" raw
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1634` if events.contains(.bolusChange) { historyBackfillCoordinator.runTick() } — gated by the off-by-default flag

- Recommendation: When the history emission layer lands, mint the optimistic bolus raw from HistoryLogSyncIdentifier.bolus(pumpSerial, bolusId) so the history completion finalizes the same dose; until then document that LastBolusStatus is the sole recovery source.

Open questions raised by this point:

- What does CurrentBolusStatusResponse carry after a bolus completes: bolusId 0, or the finished bolus's id with status 0? fetchBolusStatus finalizes only on `response.bolusId == 0` (StateSync.swift:249); if the pump echoes the last id, an interrupted bolus would never finalize via this path. No TandemCoreTests fixture settles it; a captured response from hardware would.
- If the pump did start a bolus whose InitiateBolusResponse was lost, does BolusPermissionReleaseRequest for that bolusId succeed, fail, or cancel the bolus? This determines whether the P12-1 timeout path is merely unrecorded or actively harmful.
- CLAUDE.md states the history mapper's bolus identity is one 'an optimistic report can mint from the pump-assigned id at command time', but the live path (NewPumpEvent.bolus, Extensions/NewPumpEvent.swift:95) uses units+date instead; the doc appears ahead of the code.
- Does a Tandem pump continue a Loop-initiated bolus across a BLE drop, or stop it with LastBolusStatus bolusStatus .stoppedWireless (LastBolusStatusAbstractResponse.swift:130)? The driver reads deliveredVolume but ignores bolusStatus, so it cannot distinguish the two for logging or uncertainty flags.
### P13. Suspend and resume are modeled as real dose events with correct timing: a suspend is emitted whenever delivery actually stops (including pump-initiated stops and teardown) and a resume restores the basal picture

Guide section: §10 pitfall: suspend / resume events.

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

Loop-initiated suspend and resume are modeled correctly: suspendDelivery finalizes any running temp basal at the suspend instant and emits an immutable .suspend point event; sendResumePumping emits a .resume carrying insulinType, and with pumpRecordsBasalProfileStartEvents=false LoopKit re-inserts scheduled basal itself. Pump-initiated stops are only partly handled. The live detection path (fetchBasalStatus) stamps a pump-side suspend at detection time, not the pump's time, and—critically—reports a pump-side resume as a .basal dose, which LoopKit's reconciled() does not accept as closing a suspend, so the suspend stays open. The pump-timestamped PumpingSuspended/Resumed history mapping exists but is unwired and behind default-off flags. Teardown correctly emits no suspend because a Tandem pump keeps delivering after the driver is removed.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P13-1 | Conforms | none | unverified | Loop-initiated suspend (suspendDelivery) |
| P13-2 | Conforms | none | unverified | Loop-initiated resume (sendResumePumping) |
| P13-3 | Non-conforming | high | unverified | Pump-initiated resume reported as .basal, not .resume |
| P13-4 | Partial | medium | unverified | Pump-initiated suspend timing and coverage |
| P13-5 | Not applicable | none | unverified | Teardown / prepareForDeactivation |
| P13-6 | Partial | medium | unverified | Cartridge/cannula/tubing flows with pump already suspended |
| P13-7 | Partial | medium | unverified | Suspend batch drops an in-flight mutable bolus |

**P13-1 Loop-initiated suspend (suspendDelivery)** (Conforms, impact none, unverified)

A Loop-commanded suspend is a real dose event with correct timing: it is stamped when the pump acknowledges SuspendPumpingRequest, the in-flight temp basal is finalized at that same instant, and the batch is sent with replacePendingEvents: true. The suspend is an immutable zero-duration entry, which is what LoopKit's reconciled() and DoseStore ('extend an unfinished suspend out to end time') expect; the in-tree Omnipod driver uses the identical DoseEntry(suspendDate:) shape, so not re-reporting it as mutable is the established convention rather than a gap. After app relaunch the persisted basalDose keeps basalDeliveryState at .suspended. Tests exercise the wire sequence and state but not the emitted NewPumpEvent contents.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:820` let suspendDose = UnfinalizedDose(suspendStartTime: Date.now) after SuspendPumpingResponse status 0
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:821` getActivePumpEvents(endDate: suspendDose.startDate) finalizes a running temp basal at the suspend instant
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:828` emitPumpEvents(events) with default replacePendingEvents: true
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:197` case .suspend returns DoseEntry(suspendDate: startDate, automatic: automatic)
  - `reference: loopkit-trio/DoseEntry.swift:31` init(suspendDate:...) defaults isMutable: false — immutable point event, same shape as OmnipodKit

- Recommendation: Add a test asserting the emitted batch (finalized temp basal + .suspend, replacePendingEvents true) via StubPumpBluetooth and a recording delegate.

**P13-2 Loop-initiated resume (sendResumePumping)** (Conforms, impact none, unverified)

The resume emitted after a successful ResumePumpingRequest is a real .resume DoseEntry stamped at the acknowledgement time and carries insulinType. It does not carry scheduledBasalRate, but in the LoopKit fork TandemKit builds against that property is internal(set) and is filled in by DoseStore's annotated(with: basalProfile), so the MedtrumKit 'resume missing basal rate' failure cannot be reproduced from the driver side. No explicit .basal dose follows the resume; that is correct because pumpRecordsBasalProfileStartEvents is false and LoopKit's overlayBasalSchedule inserts scheduled basal. LoopKit's reconciled() pairs this .resume with the prior .suspend, restoring the basal picture. Status also flips to .active. (next-dev makes scheduledBasalRate public var; still optional there.)

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:900` let dose = UnfinalizedDose(resumeStartTime: Date.now, insulinType: state.insulinType)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:904` let events = [NewPumpEvent.resume(dose: dose.toDoseEntry(), date: dose.startDate)]
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:203` case .resume returns DoseEntry(resumeDate:insulinType:automatic:)
  - `reference: loopkit-trio/DoseEntry.swift:29` public internal(set) var scheduledBasalRate — a driver cannot set it in the pinned LoopKit; DoseStore.annotated(with:) supplies it
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:216` pumpRecordsBasalProfileStartEvents returns false, so LoopKit inserts scheduled basal after the resume

- Recommendation: No change required. If TandemKit later builds against next-dev LoopKit, consider populating scheduledBasalRate on the resume from getScheduledBasalRate().

**P13-3 Pump-initiated resume reported as .basal, not .resume** (Non-conforming, impact high, unverified)

When the user resumes on the pump (or the pump resumes after an alarm/Basal-IQ suspend), fetchBasalStatus sees basalType .basal while state.basalDose is .suspend and emits a zero-length .basal dose instead of a .resume. LoopKit's reconciled() closes an open suspend only on a .resume or a .tempBasal; a .basal leaves lastSuspend set, so the suspend is appended with endDate nil and DoseStore extends it to the query end. Loop/Trio therefore keeps treating basal as suspended after the pump has actually resumed, until a later temp basal or Loop-issued resume arrives. That under-counts delivered basal for an unbounded period and can drive over-delivery. The only code that emits a .resume for a pump-side resume (handleHomeScreenMirrorResponse) is unreachable. No test covers fetchBasalStatus transitions.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:166` if activeBasalType == .basal { ... } — branch taken when the pump resumes on its own after state.basalDose.type == .suspend
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:168` let dose = UnfinalizedDose(basalRate: getScheduledBasalRate(), ...) — a .basal dose, no .resume is created
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:168` case .basal returns DoseEntry(type: .basal, ...) with no endDate
  - `reference: InsulinMath_loopandlearn.swift:415` } else if let suspend = lastSuspend, dose.type == .tempBasal { // Handle missing resume — only a temp basal (not .basal) closes an open suspend
  - `reference: InsulinMath_loopandlearn.swift:501` if let suspend = lastSuspend { reconciled.append(... endDate: nil ...) } — the suspend is emitted still open

- Recommendation: In fetchBasalStatus, when state.basalDose.type == .suspend and the pump reports .basal, emit UnfinalizedDose(resumeStartTime:insulinType:) with wasProgrammedByPumpUI where LoopKit allows, mirroring handleHomeScreenMirrorResponse; add a StubPumpBluetooth test for suspend→basal and basal→suspend transitions.

**P13-4 Pump-initiated suspend timing and coverage** (Partial, impact medium, unverified)

Pump-initiated stops (user 'Stop Insulin', occlusion/empty-cartridge alarms, malfunction, Basal-IQ auto-suspend — all reasons carried by PumpingSuspendedHistoryLog) are detected only by polling CurrentBasalStatus: on a pumpSuspend qualifying event while connected, or on the next Loop sync (up to ~5 min, or after a BLE outage arbitrarily longer, since reconnect does not sync). The suspend is then stamped Date.now, so Loop credits basal delivered between the real stop and detection. The pump's own ledger (PumpingSuspended/ResumedHistoryLog, pump-timestamped) is mapped by HistoryToDoseMapper but never emitted, and the whole history path is behind two default-off flags. HypoMinimizerSuspend/Resume logs are not mapped at all. Whether Basal-IQ or Control-IQ zero-basal sets bitmask exactly 0x01 is not verifiable from code.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:148` let now = Date.now — pump-side suspend is stamped at detection time, not the pump's suspend time
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:152` let dose = UnfinalizedDose(suspendStartTime: now) emitted only when basalType flips to .suspend
  - `Sources/TandemCore/Messages/CurrentStatus/CurrentBasalStatus.swift:45` case 0x01: return .suspend — exact-match switch on basalModifiedBitmask
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:360` ensureCurrentPumpData skips a sync if lastReconciliation is < 4.5 min old; reconnect itself triggers no sync
  - `Sources/TandemKit/PumpManager/TandemBluetoothManager.swift:427` auto-reconnect calls ensureConnected only; no fetchBasalStatus/syncPumpData follows

- Recommendation: Wire pump-timestamped PumpingSuspended/Resumed history events into emission (dedup against the polled suspend by replacing its raw), trigger fetchBasalStatus on reconnect, map HypoMinimizer logs, and confirm bitmask values for Basal-IQ/Control-IQ on hardware.

**P13-5 Teardown / prepareForDeactivation** (Not applicable, impact none, unverified)

The guide's 'emit a suspend on teardown' lesson comes from patch pumps whose removal ends delivery. A t:slim X2 or Mobi keeps running its own basal profile (and Control-IQ, if enabled) after the driver is deleted, so emitting a .suspend at deactivation would tell Loop insulin stopped when it did not. Not emitting one is therefore correct for this hardware; TandemKit does nothing but tear down BLE and notify the host. A remaining, separate concern is that a mutable temp basal in flight at deactivation is not finalized (outside this point).

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1119` bluetooth.deactivate() then notifyDelegateOfDeactivation — no SuspendPumpingRequest, no suspend event
  - `Sources/TandemKit/PumpManager/TandemBluetoothManager.swift:386` deactivate(): sets isDeactivated, disconnect(), drops pumpManager — transport only
  - `reference: loopkit-trio/PumpManager.swift:281` notifyDelegateOfDeactivation only calls pumpManagerWillDeactivate

- Recommendation: Keep as is. Document in contributor docs why no suspend is emitted at deactivation, and consider finalizing any running temp basal there.

**P13-6 Cartridge/cannula/tubing flows with pump already suspended** (Partial, impact medium, unverified)

The change-cartridge, fill-cannula and fill-tubing wizards normally suspend via suspendDelivery (emits the suspend dose) and resume via resumeDelivery (emits the resume, then syncs), which is correct. However each wizard first calls fetchSuspendStatus and, if the pump is already suspended (user pressed Stop Insulin on the pump), skips the suspend step. fetchSuspendStatus only returns a Bool; it does not update state.basalDose or emit a suspend, so the whole cartridge change can proceed with Loop still believing basal is running until the next sync's fetchBasalStatus notices. Combined with P13-3, the later resume from the wizard is fine (Loop-initiated), but the pre-existing pump-side suspend is late.

- Evidence:
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitChangeCartridgeViewModel.swift:127` pumpManager?.fetchSuspendStatus { isSuspended in ... currentStep = .enterMode } — skips the suspend step if pump is already suspended
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:130` completion(response.basalType == .suspend) — fetchSuspendStatus returns a Bool and neither updates state.basalDose nor emits a suspend
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitChangeCartridgeViewModel.swift:142` pumpManager?.suspendDelivery — the normal path does go through the event-emitting suspend
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitFillCannulaViewModel.swift:183` pumpManager?.resumeDelivery then syncPumpData — resume path emits .resume and re-syncs

- Recommendation: Have fetchSuspendStatus delegate to fetchBasalStatus (which emits the suspend and updates basalDose) and return state.basalDose.type == .suspend, so a pump-side suspend seen by the wizards is recorded immediately.

**P13-7 Suspend batch drops an in-flight mutable bolus** (Partial, impact medium, unverified)

A Tandem 'stop insulin' halts a running bolus as well as basal. suspendDelivery does not include the in-progress mutable bolus in its replacePendingEvents:true batch, so LoopKit soft-deletes it at the moment of suspend and the partially delivered bolus disappears from IOB. state.bolusDose is retained, so the next fetchBolusStatus (deferred until estimated end + 30 s) may finalize it with the pump's LastBolusStatus delivered volume if CurrentBolusStatus reports bolusId 0. Recovery is plausible but time-delayed and not tested; whether the pump reports the interrupted bolus that way is unverified. This is bolus accounting, but the trigger is the suspend batch's contents.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:598` bolus emitted with replacePendingEvents: false as a mutable dose
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1706` getActivePumpEvents: guard state.basalDose.type == .tempBasal else { return [] } — never re-reports the bolus
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:828` suspendDelivery emits [tempBasal?, suspend] with replacePendingEvents true, purging the mutable bolus
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:249` if response.bolusId == 0 { ... queryLastBolusDeliveredVolume ... emitPumpEvents } — later sync can re-add the finalized bolus

- Recommendation: In suspendDelivery, finalize the active bolus in the same batch (query LastBolusStatus for delivered volume) or include the mutable bolus in getActivePumpEvents; add a test for suspend-during-bolus.

Open questions raised by this point:

- Does CurrentBasalStatusResponse.basalModifiedBitmask read exactly 0x01 during a Basal-IQ hypo-suspend and during Control-IQ zero-basal, and can bits combine (e.g. 0x03)? The switch at CurrentBasalStatus.swift:44-52 matches exact values only; a hardware capture would settle it.
- After SuspendPumping interrupts a running bolus, does CurrentBolusStatusResponse report bolusId 0 with .alreadyDeliveredOrInvalid so fetchBolusStatus finalizes it (P13-7 recovery)? Not determinable from code.
- For P13-3 the sign of the error depends on which DoseStore pipeline Trio uses for IOB (live getNormalizedDoseEntries extends the open suspend to now; the InsulinDeliveryStore save path overlays schedule after a zero-length suspend). Both are wrong; the direction should be confirmed against Trio.
- The guide describes an 'open suspend' as a mutable dose, but LoopKit-trio's reconciled() and the in-tree OmnipodKit treat suspend as an immutable point event closed by the resume; TandemKit follows the in-tree convention.
- prepareForDeactivation leaves a running mutable temp basal un-finalized (outside P13 scope).
- docs/tandemkit-history-integration-plan.md:214 states suspend/resume are injected by UI flows rather than synthesized from history; that matches the code today, but the mapper's suspend/resume support (and its test) is otherwise unused.
### P14. Pump faults are surfaced as NewPumpEvent with type .alarm / alarmType, and .replaceComponent is emitted on component replacement

Guide section: §10 pitfall: faults, alarms, pump replacement.

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

TandemKit emits .replaceComponent(.infusionSet) on cannula fill and .rewind on cartridge change, both from the TandemKitUI wizards only, with replacePendingEvents:false. Pump faults never reach the pump-event log: HistoryToDoseMapper does map Alarm/AlertActivated logs to type .alarm (alarmType nil, alerts conflated with alarms), but mapToEvents has no caller in Sources, historyBackfill defaults off, and every traced emitPumpEvents call site carries only dose/suspend/resume/basal or the two component events. Alarms and malfunctions reach the host solely through LoopKit Alert issuance (a different channel). Nothing emits .replaceComponent(.pump) when a different pump is paired; only the history-backfill bookkeeping notices a serial change. Faults/alarms done on the pump UI (cartridge/tubing/cannula history logs) are ignored.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P14-1 | Non-conforming | low | unverified | Alarm events never reach hasNewPumpEvents |
| P14-2 | Partial | low | unverified | alarmType not populated; alerts conflated with alarms |
| P14-3 | Partial | low | unverified | Cannula fill emits .replaceComponent(.infusionSet) |
| P14-4 | Partial | low | unverified | Cartridge change reported as .rewind, no prime event |
| P14-5 | Non-conforming | low | unverified | No .replaceComponent(.pump) on pairing a different pump |
| P14-6 | Partial | none | unverified | Linux shim cannot express alarmType |

**P14-1 Alarm events never reach hasNewPumpEvents** (Non-conforming, impact low, unverified)

grep over Sources shows `mapToEvents`/`HistoryToDoseMapper` referenced only inside its own file, so the mapper's .alarm events are dead code today. Traced emission sites: TandemPumpManager.swift 598 (bolus), 657 (cancel), 743/778 (temp basal), 828/910 (suspend/resume), 1062/1071 (site/cartridge), 1330 (Control-IQ basal); +StateSync 161/183 (basal status), 268 (bolus done), 512 (home-screen mirror). Pump alarms (occlusion, empty cartridge, auto-off, cartridge removed — AlarmStatus.swift:62-85) and malfunctions are surfaced only as LoopKit Alerts via reconcileLoopKitAlerts. That satisfies user notification but not §10's 'NewPumpEvent with type .alarm'. Same on steady state, first sync, reconnect and relaunch; the historyBackfill flag does not change it because the store is never mapped.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:296` alarmEvent builds NewPumpEvent(type: .alarm) — the only .alarm construction in Sources
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:318` fetchNotifications() ends in reconcileLoopKitAlerts(), not emitPumpEvents
  - `Sources/TandemKit/PumpManager/TandemPumpManager+Alerts.swift:114` delegate.issueAlert(item.loopKitAlert(...)) — LoopKit Alert channel, not the pump-event log
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1733` func emitPumpEvents(_ events:, replacePendingEvents:) — all 13 call sites traced; none passes an .alarm event
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:36` historyBackfill / historyDoseReporting default false

- Recommendation: When the history emission layer is wired (historyDoseReporting), include the mapper's .alarm events; until then, consider emitting an .alarm NewPumpEvent from fetchNotifications for newly active alarms/malfunctions, keyed by a stable raw (serial + alarm id + activation time), with replacePendingEvents:false.

**P14-2 alarmType not populated; alerts conflated with alarms** (Partial, impact low, unverified)

The (currently unused) mapper populates type .alarm but leaves alarmType nil and uses the generic title "Alarm" for both AlarmActivated and AlertActivated logs. Tandem alerts (low insulin, high BG, reminders) are not faults; reporting them as .alarm would overstate fault history once the mapper is wired. The alarm id is available (alarmId, alarmResponseType) and several Tandem alarms map cleanly onto LoopKit's PumpAlarmType (OCCLUSION_ALARM→occlusion, EMPTY_CARTRIDGE_ALARM→noInsulin, AUTO_OFF_ALARM→autoOff, BATTERY_SHUTDOWN_ALARM→noPower). Test HistoryToDoseMapperTests.swift:285-299 asserts type and raw only. Identity is good: raw is HistoryLogSyncIdentifier.logSequence(pumpSerial, sequenceNum), stable across re-reads.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:87` case let alarm as AlarmActivatedHistoryLog: events.append(alarmEvent(...))
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:89` case let alert as AlertActivatedHistoryLog: also emitted as .alarm
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:291` NewPumpEvent(date:, dose: nil, raw:, title: "Alarm", type: .alarm) — no alarmType argument
  - `Sources/TandemCore/Messages/HistoryLog/AlarmActivatedHistoryLog.swift:76` alarmResponseType exposes the typed alarm id the mapper could translate
  - `reference: loopkit-trio/NewPumpEvent.swift:26` init(..., type: PumpEventType? = nil, alarmType: PumpAlarmType? = nil) — defaults nil

- Recommendation: Restrict .alarm to AlarmActivatedHistoryLog (and malfunctions); map alarmResponseType to PumpAlarmType (.occlusion, .noInsulin, .autoOff, .noPower, else .other(name)) and pass it as alarmType; use a descriptive title. Add a test asserting alarmType.

**P14-3 Cannula fill emits .replaceComponent(.infusionSet)** (Partial, impact low, unverified)

The app-driven fill-cannula wizard reports a site change with the correct LoopKit type and, per §5, replacePendingEvents:false so a live mutable bolus/temp basal is not purged. raw is "siteChange <ISO8601>" — unique per event and not re-reported, so no identity churn. Gap: on a t:slim X2 the user can fill the cannula on the pump's own screen; CannulaFilledHistoryLog exists in the catalog but is ignored by the mapper (and the mapper is not wired anyway), so pump-UI site changes are never reported. No test asserts the emitted event.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:65` type: .replaceComponent(componentType: .infusionSet)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1062` emitPumpEvents([NewPumpEvent.siteChange(date: date)], replacePendingEvents: false)
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitFillCannulaViewModel.swift:172` pumpManager?.recordSiteChange(primeAmount: primeAmount) on successful fill only
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:118` default: continue — CannulaFilledHistoryLog is dropped

- Recommendation: Keep the UI path; additionally map CannulaFilledHistoryLog to .replaceComponent(.infusionSet) with a logSequence raw so pump-UI site changes are captured once history emission is wired. Add a MockPumpManagerDelegate assertion for the emitted event.

**P14-4 Cartridge change reported as .rewind, no prime event** (Partial, impact low, unverified)

Cartridge replacement is emitted as .rewind (Medtronic idiom) rather than the guide's .replaceComponent(componentType: .reservoir), which the pinned LoopKit supports. LoopKit accepts either; the difference is only how the consumer app renders/handles it. The fill-tubing wizard (TandemKitFillTubingViewModel) records no event at all, so no .prime event exists. Both flows fire only from the TandemKitUI wizards; CartridgeFilledHistoryLog and TubingFilledHistoryLog are ignored by the mapper, so cartridge/tubing changes done on the pump screen are not reported. Timing: the event date is app-side Date.now at detection completion, not the pump's timestamp.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:78` type: .rewind for cartridgeChange (not .replaceComponent(.reservoir))
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1071` emitPumpEvents([NewPumpEvent.cartridgeChange(date: date)], replacePendingEvents: false)
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitChangeCartridgeViewModel.swift:319` pumpManager?.recordCartridgeChange() in finishDetecting()
  - `Tests/TandemKitTests/TandemKitChangeCartridgeViewModelTests.swift:214` asserts lastCartridgeChangeDate only, not the emitted NewPumpEvent
  - `reference: loopkit-trio/PumpEventType.swift:89` ReplaceableComponent has case reservoir

- Recommendation: Consider emitting .replaceComponent(.reservoir) (optionally alongside .rewind) for cartridge change and a .prime event after fill tubing; map CartridgeFilled/TubingFilled history logs for pump-UI changes. Confirm which type the host app (Trio) handles.

**P14-5 No .replaceComponent(.pump) on pairing a different pump** (Non-conforming, impact low, unverified)

A grep for replaceComponent across Sources finds only the .infusionSet case. When a user pairs a replacement t:slim X2/Mobi (new serial), fetchPumpInformation silently overwrites pumpSerial; the only serial-change logic is HistoryBackfillState.matching, which restarts backfill bookkeeping and does not emit anything. So the host never receives .replaceComponent(.pump), unlike OmnipodKit's pod-change event that §5/§10 reference. This holds on first sync after pairing and after relaunch. Dose accounting is unaffected (Loop's IOB is app-side), but the pump-event log lacks the marker that lets the consumer reset pump-specific state or display the change.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1112` pairPump stores pincode and connects; no event emitted
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:103` state.pumpState.pumpSerial = pumpVersionResponse.serialNumber — overwritten without comparing to the prior serial
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1137` deleteSavedPumpState resets PumpState() before re-setup; nothing reported
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillState.swift:67` guard self.pumpSerial == pumpSerial — only the backfill bookkeeping reacts to a replacement pump

- Recommendation: In fetchPumpInformation, compare the new serialNumber with the persisted pumpSerial; when it differs (or on first successful pairing), emit NewPumpEvent(type: .replaceComponent(componentType: .pump)) with raw derived from the new serial, replacePendingEvents:false. Test via StubPumpBluetooth.

**P14-6 Linux shim cannot express alarmType** (Partial, impact none, unverified)

Any fix for P14-2 (passing alarmType) would not compile on Linux until the shim gains PumpAlarmType and the alarmType initializer parameter, since CI runs the Linux build. The shim's PumpComponent name differs from LoopKit's ReplaceableComponent, but TandemKit only uses the associated-value shorthand so no drift is exposed today. Purely a build-surface issue, no accounting impact.

- Evidence:
  - `LinuxShims/LoopKit/LoopKit.swift:538` NewPumpEvent has no alarmType field; PumpAlarmType is not defined in the shim
  - `LinuxShims/LoopKit/LoopKit.swift:517` public enum PumpComponent — real LoopKit names this ReplaceableComponent
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:65` uses inferred .replaceComponent(componentType: .infusionSet), so it compiles against both

- Recommendation: Extend LinuxShims/LoopKit/LoopKit.swift with PumpAlarmType (autoOff, lowInsulin, lowPower, noDelivery, noInsulin, noPower, occlusion, other(String)) and an alarmType parameter on NewPumpEvent.init before populating alarmType in the mapper.

Open questions raised by this point:

- The real LoopKit PumpAlarmType.swift is not among the reference files on disk; the case list assumed above (autoOff, lowInsulin, lowPower, noDelivery, noInsulin, noPower, occlusion, other) should be verified against the loopandlearn fork Trio pins.
- Whether Trio (the consumer) handles .replaceComponent and .rewind pump events (guide §10 notes MedtrumKit #114 was a Trio-side gap) is outside this repo and was not verified.
- When an occlusion/empty-cartridge alarm stops delivery, does CurrentBasalStatusResponse.basalType report .suspend so fetchBasalStatus (+StateSync.swift:150-165) emits a suspend dose? If not, delivery stops caused by faults are not captured as doses either; needs hardware confirmation.
- docs/tandemkit-history-integration-plan.md:211 presents the AlarmActivated/AlertActivated -> NewPumpEvent(.alarm) mapping as part of the plan; CLAUDE.md states the mapper is not wired to any emission path. The code matches CLAUDE.md.
- LoopKit also defines .alarmClear; TandemKit never emits it. The guide does not require it, so it is not scored here.
### P15. Tests cover BLE loss mid-bolus and mid-temp-basal, verifying the dose is recovered and finalized with the pump's delivered amount, not dropped or duplicated

Guide section: §11 testing: interrupt everything.

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

No test interrupts a bolus or a temp basal and asserts on the NewPumpEvents Loop receives. The only "BLE dropped mid-bolus" test (TandemPumpManagerBolusSyncTests.testSyncReconcilesAfterGraceExpires) checks a boolean gate, not that the dose is finalized with the pump's delivered volume. Nothing exercises a temp basal across a drop at all. State-persistence round-trips are tested, but no test rebuilds a manager from persisted in-progress state and syncs. The harness can model unanswered requests and connect failures, but has no link-drop/reconnect event, and MockPumpManagerDelegate discards lastReconciliation/replacePendingEvents and flattens batches, so "not dropped, not duplicated" cannot be asserted today. Reading the code, the relaunch path clears an in-progress bolus without a finalizing event, which such a test would have caught.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P15-1 | Non-conforming | high | unverified | Mid-bolus BLE loss: recovery/finalization untested |
| P15-2 | Non-conforming | high | unverified | Mid-temp-basal BLE loss: no coverage at all |
| P15-3 | Partial | low | unverified | Harness can model drops, not disconnect/reconnect events |
| P15-4 | Non-conforming | low | unverified | MockPumpManagerDelegate cannot verify drop/duplicate semantics |
| P15-5 | Partial | medium | unverified | App relaunch: persistence tested, recovery-after-restore not |
| P15-6 | Partial | low | unverified | History-based recovery tested in isolation, not end to end |

**P15-1 Mid-bolus BLE loss: recovery/finalization untested** (Non-conforming, impact high, unverified)

The single test that mentions BLE loss mid-bolus verifies only that the sync gate reopens after the 30 s grace; it never drives enactBolus, drops the link, reconnects, and inspects hasNewPumpEvents. Nothing asserts that the finalized bolus carries the LastBolusStatus deliveredVolume rather than the programmed total. An interruption test would also expose that when bolusProgressReport is nil (app relaunch, or any path that recreated the manager) fetchBolusStatus clears state.bolusDose without emitting a finalized event, so the mutable bolus emitted at enactBolus is left for DoseStore's next replacePendingEvents:true purge.

- Evidence:
  - `Tests/TandemKitTests/TandemPumpManagerBolusSyncTests.swift:41` Doc comment names the scenario: 'BLE dropped mid-bolus; the pump does not replay missed qualifying events'
  - `Tests/TandemKitTests/TandemPumpManagerBolusSyncTests.swift:48` Only assertion: XCTAssertFalse(manager.shouldDeferBolusSync(at: now)) — no delegate, no events
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:256` Finalize path queries pump: actualDelivered = queryLastBolusDeliveredVolume(bolusId:) — never asserted by any test
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:217` if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil { state.bolusDose = nil } — no event emitted
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:70` internal var bolusProgressReport — in-memory only, not part of persisted state

- Recommendation: Add a StubPumpBluetooth test: enactBolus succeeds, CurrentBolusStatusRequest is unanswered (enqueue nil), then answered with bolusId 0 and a LastBolusStatus deliveredVolume; assert exactly one bolus NewPumpEvent with isMutable false and deliveredUnits == pump value. Repeat with a manager rebuilt from persisted state.

**P15-2 Mid-temp-basal BLE loss: no coverage at all** (Non-conforming, impact high, unverified)

No test enacts a temp basal, loses the pump (connect failure or unanswered CurrentBasalStatusRequest), reconnects, and checks that the temp basal is re-reported as mutable while running and later finalized with deliveredUnits derived from actual elapsed time — the MedtrumKit failure the guide calls out ('TBR discarded after a BLE reconnect'). The only test with a temp rate and a lost response is in the suspend flow and asserts on the command sequence, not on NewPumpEvents.

- Evidence:
  - `Tests/TandemKitTests/TandemPumpManagerSyncBasalTests.swift:5` File covers syncBasalRateSchedule (IDP segments), not temp basals
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1702` getActivePumpEvents is the only path that re-reports/finalizes a running temp basal; no test calls a caller of it after a drop
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` basalEntry = state.basalDose.toDoseEntry(isMutable: endDate == nil, ...) — finalization semantics untested
  - `Tests/TandemKitTests/TandemPumpManagerSuspendDeliveryTests.swift:51` Only temp-rate test with a lost response: StopTempRateRequest unanswered, asserts SuspendPumpingRequest still sent, not events
  - `Tests/TandemKitTests/TandemPumpManagerControlIQTests.swift:119` Temp basal seeded into state only to assert it is not cancelled; no event assertions

- Recommendation: Add tests: enactTempBasal → syncPumpData with connectError set (assert no event change, lastReconciliation unchanged) → sync succeeds with CurrentBasalStatus reporting .basal after estimatedEndDate; assert the temp basal event is finalized once, with stable raw, and a basal event follows.

**P15-3 Harness can model drops, not disconnect/reconnect events** (Partial, impact low, unverified)

The stub can express the two observable consequences of a BLE loss (connect failure, unanswered request) and can vary answers across successive syncs, so P15-1/P15-2 scenarios are expressible today. What cannot be expressed is the disconnect notification itself: the reconnect path in TandemBluetoothManager (cancel in-flight operations, mark link down, auto-reconnect) runs only against CoreBluetooth and is never reached through StubPumpBluetooth, so any dose-state side effects of that path are untestable without a hook on the protocol.

- Evidence:
  - `Tests/TandemKitTests/StubPumpBluetooth.swift:16` var connectError: Error? — makes ensureConnected fail
  - `Tests/TandemKitTests/StubPumpBluetooth.swift:44` 'Returning nil simulates a request the pump never answered'
  - `Tests/TandemKitTests/StubPumpBluetooth.swift:53` enqueue(_:responses:) answers successive writes differently — enough to sequence 'answered, then silent, then answered'
  - `Sources/TandemKit/PumpManager/PumpBluetoothConnection.swift:9` protocol PumpBluetoothConnection has no link-dropped/reconnected callback
  - `Sources/TandemKit/PumpManager/TandemBluetoothManager.swift:473` didDisconnectPeripheral → cancelPendingOperations/markLinkDown/auto-reconnect lives outside the stubbed surface

- Recommendation: Either add a test-visible 'linkDidDrop' entry point on TandemPumpManager driven from markLinkDown, or document that unit tests cover only the command-level consequences and hardware tests cover reconnect itself.

**P15-4 MockPumpManagerDelegate cannot verify drop/duplicate semantics** (Non-conforming, impact low, unverified)

Whether a mutable dose survives DoseStore depends on which call re-sent it and with what replacePendingEvents value (§3/§5 of the guide). The mock records neither the flag nor the per-call batch, and no test reads delegate.pumpEvents at all. So even if an interruption test were written today, it could not distinguish 'dose dropped' (omitted from a replacePendingEvents:true batch) from 'dose re-reported', nor detect a duplicate created by a changed raw.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:129` lastReconciliation _: Date? — discarded
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:130` replacePendingEvents _: Bool — discarded
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:133` _pumpEvents += events — batches flattened, call boundaries lost
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:45` didReceivePumpEventsExpectation exists but no test sets it (grep: no callers outside the mock)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:600` enactBolus emits with replacePendingEvents: false — the flag the mock cannot observe

- Recommendation: Record each hasNewPumpEvents call as (events, lastReconciliation, replacePendingEvents) and add a helper that folds the calls the way DoseStore.addPumpEvents would, keyed by raw, so tests can assert the surviving dose set.

**P15-5 App relaunch: persistence tested, recovery-after-restore not** (Partial, impact medium, unverified)

The guide's 'persist the UnfinalizedDose' advice is honoured and its serialization is tested. But no test constructs a TandemPumpManager from a state carrying an in-progress bolus or temp basal and runs syncPumpData/fetchBolusStatus to check what Loop is told. That is the exact scenario where bolusProgressReport (memory only) is nil, so the code path differs from steady state; the missing test hides that the restored bolus is either cleared silently (status .alreadyDeliveredOrInvalid) or never finalized.

- Evidence:
  - `Tests/TandemKitTests/TandemPumpManagerStateTests.swift:115` testInProgressBolusRoundTrips: bolusDose incl. deliveredUnits/bolusId survives rawValue round-trip
  - `Tests/TandemKitTests/TandemPumpManagerStateTests.swift:145` testTempBasalRoundTripsThroughBasalDose: basalDose tempBasal survives round-trip
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:226` guard let progressReport = bolusProgressReport else { return } — restored bolus can never reach the finalize branch
  - `Tests/TandemKitTests/TandemPumpManagerBolusSyncTests.swift:6` makeManager seeds state.bolusDose directly but only queries shouldDeferBolusSync

- Recommendation: Add a relaunch test: build state with bolusDose past estimatedEndDate, construct manager, stub CurrentBolusStatus (bolusId 0 or alreadyDelivered) and LastBolusStatus; assert a finalized bolus event with the pump's deliveredVolume and same raw as the original.

**P15-6 History-based recovery tested in isolation, not end to end** (Partial, impact low, unverified)

The component that would recover a dose from the pump's own log after a drop (HistoryToDoseMapper) has good unit coverage for interrupted and completed records and stable raw identity, and the fetcher is tested for duplicate suppression. However grep finds no production caller of HistoryToDoseMapper and both history flags default off, so these tests verify a component that has no emission path; nothing tests that a bolus interrupted by BLE loss is finalized from history at the manager level. The project's own plan still lists disconnect/reconnect dedup as an unchecked hardware item.

- Evidence:
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:124` testActivationWithoutCompletionIsMutable — interrupted-bolus record maps to isMutable true, deliveredUnits nil
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:33` testMatchedBolusProducesFinalizedDose — completion record yields deliveredUnits from insulinDelivered
  - `Tests/TandemKitTests/TandemPumpManagerHistoryIntegrationTests.swift:194` testDuplicateStreamEntriesAreReportedOnce — re-streamed chunks reach onLog once
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:32` historyBackfill and historyDoseReporting defaultValue false
  - `docs/tandemkit-history-integration-plan.md:625` '[ ] Disconnect/reconnect, verify deduplication' — listed as unchecked manual hardware step

- Recommendation: When the emission layer is wired, add a manager-level test under historyBackfill+historyDoseReporting: mutable bolus from enactBolus, drop, then history stream returns BolusCompleted; assert one finalized event and no duplicate of the command-path event.

Open questions raised by this point:

- Outside P15's scope but observed while tracing: TandemPumpManager+StateSync.swift:217-224 clears state.bolusDose on .alreadyDeliveredOrInvalid when bolusProgressReport is nil without emitting a finalized bolus event; whether DoseStore then purges the mutable bolus emitted at enactBolus (TandemPumpManager.swift:598-600) on the next replacePendingEvents:true call should be confirmed by whichever point owns the mutable-dose lifecycle (P3/P4).
- The command-path raw for a bolus is built from units and the ISO8601 date (NewPumpEvent.swift:10) while the finalize path passes deliveredUnits as `units` (StateSync:260 via TandemDoseProgressReporter.getPumpEvent:44); whether that changes the raw between the mutable and final report is a P4 (stable syncIdentifier) question, not settled here.
- Whether the auto-reconnect path in TandemBluetoothManager (didDisconnectPeripheral → ensureConnected) triggers any dose-state reconciliation on reconnect could not be determined from the stubbed test surface; hardware or an added hook would settle it.
### P16. Tests cancel a bolus and a temp basal at various points and verify the finalized dose shows the partial delivered amount and an unchanged syncIdentifier

Guide section: §11 testing: cancel everything.

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

TandemKit has no test that cancels an app-initiated bolus or temp basal and inspects the finalized dose. `cancelBolus` (TandemPumpManager.swift:607) and the zero-duration/percent-100 temp-basal cancel branch (663-747) are never exercised by TandemKitTests; the only cancel-named coverage is CancelBolusRequest serialization and HistoryToDoseMapper tests for a layer with no emission consumer. No test reads the mock delegate's `pumpEvents`, and the mock drops `lastReconciliation`/`replacePendingEvents`, so the §11 assertions (partial deliveredUnits, isMutable false, real endDate, unchanged syncIdentifier) cannot be made today. Had they existed, the bolus assertion would fail: enact keys the event on programmed units, cancel re-keys it on delivered units. Temp-basal identity is stable but equally untested.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P16-1 | Non-conforming | medium | unverified | App-side bolus cancel has no test |
| P16-2 | Non-conforming | medium | unverified | Temp basal cancel has no dose-level test |
| P16-3 | Non-conforming | low | unverified | Test harness cannot observe hasNewPumpEvents arguments |
| P16-4 | Non-conforming | medium | unverified | Bolus cancel changes syncIdentifier; test would fail |
| P16-5 | Partial | low | unverified | Only history-mapper layer has cancel coverage |

**P16-1 App-side bolus cancel has no test** (Non-conforming, impact medium, unverified)

A repo-wide search of Tests/ finds no call to `manager.cancelBolus`. The path that §11 asks to exercise — cancel after N units, query LastBolusStatus, finalize with partial `deliveredUnits`, `isMutable:false`, `endDate: Date.now` (line 641) — is untested on every route (steady state, first sync, reconnect, relaunch). The `?? 0` fallback on line 639 (a failed or mismatched LastBolusStatus reply finalizes the cancelled bolus as 0 U delivered) is exactly the kind of behaviour such tests would pin down; it is currently unverified. `StubPumpBluetooth` can already stub `CancelBolusRequest` and `LastBolusStatus*Request`, so the harness is sufficient to write these.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:607` public func cancelBolus(completion:) exists and emits a finalized dose
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0
  - `Tests/TandemCoreTests/Messages/Control/CancelBolusRequestTests.swift:5` only cancel-named test: wire serialization of CancelBolusRequest
  - `Tests/TandemKitTests/TandemPumpManagerBolusSyncTests.swift:24` BolusSync tests cover shouldDeferBolusSync only, never cancelBolus

- Recommendation: Add TandemPumpManagerCancelBolusTests: stub BolusPermission/InitiateBolus, enact, stub CancelBolusResponse(wasCancelled) and LastBolusStatus with a partial volume, call cancelBolus, assert the finalized event's deliveredUnits, isMutable, endDate and raw. Include a case where LastBolusStatus fails to decide what 0-vs-nil should mean.

**P16-2 Temp basal cancel has no dose-level test** (Non-conforming, impact medium, unverified)

The cancel branch of `enactTempBasal` (zero duration or percent 100) and the StopTempRate sent by `suspendDelivery` (line 802) and by Control-IQ enable (line 1317) all finalize the running temp basal through `getActivePumpEvents(endDate:)`, computing partial `deliveredUnits` from the elapsed window. No test asserts on that finalized dose: SuspendDeliveryTests check only the command sequence and `state.basalDose.type`; ControlIQTests:129 checks StopTempRate was *not* sent; ValidationTests check only the block. Nothing verifies deliveredUnits, endDate, isMutable, or raw stability at early, mid, or near-end cancel points, nor the `endDate == estimatedEndDate` scheduled-basal append at line 1715.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:725` if duration < .ulpOfOne || percent == 100 { // We only needed to cancel
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:736` var events = self.getActivePumpEvents(endDate: dose.startDate) finalizes the running TBR
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` deliveredUnits: isMutable ? nil : value * (duration / .hours(1))
  - `Tests/TandemKitTests/TandemPumpManagerValidationTests.swift:99` only enactTempBasal test asserts the Control-IQ block, never a cancel
  - `Tests/TandemKitTests/TandemPumpManagerSuspendDeliveryTests.swift:58` XCTAssertEqual(sentTypes, ["TempRateRequest", "StopTempRateRequest", "SuspendPumpingRequest"])

- Recommendation: Add cancel-temp-basal tests: enact a TBR, advance the clock (inject a date provider or set basalDose.startDate), call enactTempBasal(rate, for: 0) and suspendDelivery; assert the finalized tempBasal event's deliveredUnits = rate * elapsed, endDate, isMutable false, and raw equal to the enact-time raw.

**P16-3 Test harness cannot observe hasNewPumpEvents arguments** (Non-conforming, impact low, unverified)

No test in the repo reads `delegate.pumpEvents` (search for `.pumpEvents` in Tests/ returns nothing); the mock is used only for reservoir readings and status updates. The mock also drops `replacePendingEvents` and `lastReconciliation` and merges all batches, so a test could not distinguish the enact-time `replacePendingEvents:false` (TandemPumpManager.swift:600) from the cancel-time `true` (657), which is what makes the current cancel end-state correct. Additionally, on Linux the shim's `NewPumpEvent` does not derive `syncIdentifier` from `raw`, so a §11 assertion on `dose.syncIdentifier` would pass vacuously there; TandemKitTests run on the simulator against real LoopKit (unit-tests.yml:258), where it would be meaningful.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:129` lastReconciliation _: Date?, replacePendingEvents _: Bool — both discarded
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:133` synchronized { _pumpEvents += events } flattens batches into one array
  - `LinuxShims/LoopKit/LoopKit.swift:544` shim NewPumpEvent.init never sets dose.syncIdentifier from raw
  - `reference: loopkit-trio/NewPumpEvent.swift:33` real LoopKit: dose?.syncIdentifier = raw.hexadecimalString

- Recommendation: Record each hasNewPumpEvents call as a struct (events, lastReconciliation, replacePendingEvents) in MockPumpManagerDelegate. In cancel tests assert on `event.raw` equality (as HistoryToDoseMapperTests:131 does) rather than only `dose.syncIdentifier`, so the check holds on both Linux and Xcode.

**P16-4 Bolus cancel changes syncIdentifier; test would fail** (Non-conforming, impact medium, unverified)

The §11 cancel test asserts the `syncIdentifier` never changed. TandemKit would fail it: the bolus `raw` embeds the units argument, which is the programmed amount at enact and the delivered amount at cancel (and at sync-side completion via `getPumpEvent`), so any partial delivery yields a different `raw`/`syncIdentifier`. This is the MedtrumKit anti-pattern the guide's §4 names. The end state is still correct only because cancel emits with `replacePendingEvents: true` (657 → 1733 default), purging the original mutable row by flag rather than by identity. The absence of the test is what lets this latent identity change persist unnoticed.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:599` enact: NewPumpEvent.bolus(dose: doseEntry, units: units, ...) — programmed units in key
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:652` cancel: .bolus(dose: canceledDose, units: canceledDose.deliveredUnits ?? 0, ...) — delivered units in key
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:251` raw: "\(DoseType.bolus.rawValue) \(units) \(date)"
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:44` natural completion also keys on `units: delivered`

- Recommendation: Key the bolus event on programmed units (or bolusId + startDate) in both enact and finalize paths so raw is byte-identical, then add the §11 assertion. Until fixed, the cancel test should at least assert the stale mutable row is purged (replacePendingEvents true) so the reliance is explicit.

**P16-5 Only history-mapper layer has cancel coverage** (Partial, impact low, unverified)

The repo does contain cancel-shaped tests, but only for `HistoryToDoseMapper`, which maps pump history records to doses with a bolusId-keyed stable `raw` and partial `deliveredUnits`. That layer is not wired to any emission path (no reference to HistoryToDoseMapper outside Sources/TandemKit/PumpManager/History/), and the `historyBackfill`/`historyDoseReporting` flags default off. So the tests that do satisfy the §11 shape exercise code Loop/Trio never sees, while the live cancel paths (`cancelBolus`, `fetchBolusStatus` bolusId==0, `getActivePumpEvents(endDate:)`) have none. Coverage exists in the wrong place.

- Evidence:
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:105` testCancelledBolusKeepsProgrammedAndDeliveredDistinct: programmed 2.5, delivered 1.041
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:195` testEarlyCancelledTempBasalEndsAtCompletion: endDate = completion time
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:131` raw == HistoryLogSyncIdentifier.bolus(pumpSerial:bolusId:) — stable identity
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:217` live driver finalizes via CurrentBolusStatus/LastBolusStatus, not the mapper

- Recommendation: Keep the mapper tests, but add equivalent driver-level tests against the live paths. When the mapper is wired to emission, add a test that a history-finalized cancelled bolus and the live-path finalized one share one raw (today they cannot: bolusId-keyed vs units+date-keyed).

Open questions raised by this point:

- After an app relaunch `bolusProgressReport` is nil, so `fetchBolusStatus` (TandemPumpManager+StateSync.swift:217-223) clears a persisted in-progress `bolusDose` on `.alreadyDeliveredOrInvalid` without emitting a finalized dose; the mutable event from enact would then be purged on the next replacePendingEvents:true emission. This belongs to the interrupt/relaunch point but a relaunch-then-cancel test would expose it.
- `cancelBolus` finalizes with `deliveredUnits = 0` when `queryLastBolusDeliveredVolume` returns nil (line 639), while the sync-side completion path passes nil through to `getPumpEvent`, which falls back to the full programmed total (TandemDoseProgressReporter.swift:33). The two failure fallbacks under-count and over-count respectively; which is intended should be settled and tested.
- The bolus `raw` uses ISO8601 to seconds and `Date.now` at UnfinalizedDose init; a cancel test should confirm `dose.startDate` (not a new Date) is passed as the event date on both enact (line 599) and cancel (652), which the code appears to do.
### P17. Tests re-report the same in-progress dose many times and confirm it stays a single dose with identical raw and no IOB drift

Guide section: §11 testing: idempotency.

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

No test in the repository re-reports an in-progress dose and checks that it remains a single dose with identical raw. On the live path this is unexercised end to end: no test reads MockPumpManagerDelegate.pumpEvents (the mock even discards lastReconciliation/replacePendingEvents), no test drives enactBolus/enactTempBasal followed by repeated syncs, and no test touches DoseStore/InsulinDeliveryStore or IOB. The history path has identity-level tests (HistoryLogSyncIdentifierTests, HistoryToDoseMapperTests raw asserts) plus fetch/store-tier dedupe tests, but never maps the same log twice and the path is not wired to hasNewPumpEvents. The live raw scheme (bolus units, temp-basal programmedUnits) is phase-dependent, which is exactly the latent bug an idempotency test would catch.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P17-1 | Non-conforming | medium | unverified | Live path: no repeated-report test against the delegate |
| P17-2 | Non-conforming | medium | unverified | Live raw is phase-dependent; nothing tests raw equality across phases |
| P17-3 | Not applicable | none | unverified | Driver never re-reports an in-progress dose in steady state |
| P17-4 | Partial | low | unverified | History path: identity tests exist but never re-map the same log |
| P17-5 | Partial | low | unverified | Fetch/store-tier dedupe is tested, but not at the dose tier |
| P17-6 | Non-conforming | medium | unverified | No IOB or DoseStore-backed assertion anywhere in the test target |

**P17-1 Live path: no repeated-report test against the delegate** (Non-conforming, impact medium, unverified)

A grep of Tests/ for `.pumpEvents` and `didReceivePumpEventsExpectation` finds no consumer outside the mock itself; the recording is dead infrastructure. The only tests that run more than one sync (ConnectionTests 178-233) stub no active dose and assert connection counts. No test calls enactTempBasal/cancelBolus/handleBolusResponse to completion with a delegate attached and then compares the raw of the mutable and finalized reports. The guide's §11 idempotency check (re-report many times, one dose, identical raw) is therefore not represented for the live path in any of the four states: steady state, first sync after pairing, after BLE reconnect, or after relaunch.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:133` mock records events: `synchronized { _pumpEvents += events }`
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:129` `lastReconciliation _: Date?, replacePendingEvents _: Bool` are discarded, so neither can be asserted
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:219` only test running two syncs asserts `ensureConnectedCount`, not events
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:25` `stubSyncResponses` stubs ApiVersion/InsulinStatus/Battery only — no running bolus or temp basal
  - `Tests/TandemKitTests/TandemPumpManagerValidationTests.swift:50` enactBolus tests cover only pre-flight rejection, no emitted events

- Recommendation: Add a manager-level test: stub SetTempRate/CurrentBasalStatus, enact a temp basal, run syncPumpData N times, then assert exactly one tempBasal raw across all delegate calls and identical raw on finalize. Extend the mock to record lastReconciliation and replacePendingEvents per call.

**P17-2 Live raw is phase-dependent; nothing tests raw equality across phases** (Non-conforming, impact medium, unverified)

The live bolus raw is keyed on whichever units value the call site passes: programmed at enact, delivered at completion/cancel. Whenever delivered differs from programmed (any cancel, any pump-side rounding) the finalized event carries a different raw and syncIdentifier than the mutable one. Temp basal raw embeds programmedUnits, which for unitsPerHour is value*hours (loopkit-trio DoseEntry.swift:68-74); the mutable report uses estimatedEndDate, the finalized one the actual endDate, so an early stop changes raw. This is the MedtrumKit anti-pattern the guide flags in §4. The end state is rescued only by the `replacePendingEvents: true` purge. No test asserts raw equality between an enact-time event and its completion/cancel event, so this is invisible to CI.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:10` bolus raw: `"\(DoseType.bolus.rawValue) \(units) \(date)"` — units is a caller argument
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:599` enactBolus passes programmed `units: units`
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:44` completion passes `units: delivered` (pump-reported volume)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:651` cancelBolus passes `units: canceledDose.deliveredUnits ?? 0`
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:20` tempBasal raw embeds `dose.programmedUnits` (= value * hours, so it moves with endDate)

- Recommendation: Add tests asserting `raw` byte-equality between the enact-time mutable event and the completion and cancel events for bolus and temp basal; key raw on programmed units and a fixed start (or bolusId/tempRateId) so the tests pass.

**P17-3 Driver never re-reports an in-progress dose in steady state** (Not applicable, impact none, unverified)

An idempotency test presupposes the driver re-sends the same mutable dose on each sync. TandemKit does not: emitPumpEvents is reached only on transitions (enact, cancel, completion, suspend/resume, basal-type change, site/cartridge change). A running temp basal or bolus is reported once at enact and then silent until it ends, and the periodic sync never sends an events batch (empty or otherwise). So there is currently no repeated-report behaviour to test — the §11 scenario is not applicable to the code as written. This is itself a §3 report-or-delete concern (a mutable dose reported once and then omitted from a later `replacePendingEvents: true` batch is deleted by DoseStore), but that belongs to the P-points covering §3/§6, not this one.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:430` syncPumpData runs fetchBolusStatus(fromSync:)/fetchBasalStatus, no unconditional emit
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:141` fetchBasalStatus emits only `if activeBasalType != state.basalDose.type`
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:202` `if fromSync, shouldDeferBolusSync() { ... return }` — bolus in progress is skipped entirely
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:238` delivering branch updates state.bolusState and progress observers, no emitPumpEvents
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:303` deliverStateMissedByTheDelegate re-pushes status/reservoir only, not doses

- Recommendation: Once re-reporting on every sync is implemented (see §3 findings), add the idempotency test from P17-1 at the same time; write it first so it fails until re-reporting lands.

**P17-4 History path: identity tests exist but never re-map the same log** (Partial, impact low, unverified)

The history scheme is designed for idempotency — raw is derived from (pumpSerial, bolusId/tempRateId/sequenceNum), never from delivered units or end time — and the tests lock the wire format and check that the mutable activation and the finalized activation+completion each produce the scheme identifier. What is missing is the §11 shape: no test runs mapToEvents twice over the same logs (or over activation alone, then activation+completion) and asserts the raw is byte-identical across the two calls and that a consumer would see one dose. Also, per CLAUDE.md and the grep, HistoryToDoseMapper is not wired to any emission path and `historyBackfill`/`historyDoseReporting` default off, so even a perfect mapper test does not demonstrate delegate-level idempotency today.

- Evidence:
  - `Tests/TandemKitTests/HistoryLogSyncIdentifierTests.swift:39` testSameBolusIdFromDifferentPhasesMatches compares two constructions of the same id
  - `Tests/TandemKitTests/HistoryLogSyncIdentifierTests.swift:16` testWireFormatIsFrozen pins golden bytes so identity cannot silently drift
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:131` mutable activation asserts `event.raw == HistoryLogSyncIdentifier.bolus(..., bolusId: 9)`
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:49` finalized bolus asserts the same scheme with bolusId 7 — but a different test, different id
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:18` mapper class exists; grep finds no emitPumpEvents/hasNewPumpEvents in the History layer

- Recommendation: Add a mapper test that maps [activation] then [activation, completion] for the same bolusId and asserts equal raw and a single event per call; when the emission layer is wired, promote it to a delegate-level test behind the historyDoseReporting flag.

**P17-5 Fetch/store-tier dedupe is tested, but not at the dose tier** (Partial, impact low, unverified)

These tests establish that re-delivering the same history entries does not create duplicate rows in the session store and that a re-streamed chunk reaches the fetcher's callback once. That is a necessary precondition for dose-level idempotency and is well covered. It is not the §11 check, though: nothing here converts entries to NewPumpEvent or checks what a DoseStore would hold. Note testRepeatFetchIsServedFromStore shows that a repeat fetch does re-deliver every stored entry to onLog, so whatever emission layer is built on top will receive the same logs again on every window — making the raw-stability tests in P17-4 load-bearing rather than optional.

- Evidence:
  - `Tests/TandemKitTests/TandemPumpManagerHistoryIntegrationTests.swift:194` testDuplicateStreamEntriesAreReportedOnce — pump re-streams chunk, onLog fires once
  - `Tests/TandemKitTests/HistoryLogStoreTests.swift:88` testInsertIgnoresDuplicateSequenceNumbers — insert-ignore on (pumpSerial, sequenceNum)
  - `Sources/TandemKit/PumpManager/History/HistoryLogStore.swift:48` contract: `Idempotent by contract, matching ControlX2's onConflict = IGNORE`
  - `Tests/TandemKitTests/TandemPumpManagerHistoryIntegrationTests.swift:308` testRepeatFetchIsServedFromStoreWithoutChunkRequests — second fetch replays stored entries to onLog

- Recommendation: Keep these; add the dose-tier counterpart described in P17-4 so the store's idempotency is shown to carry through to identical raw on repeated emission.

**P17-6 No IOB or DoseStore-backed assertion anywhere in the test target** (Non-conforming, impact medium, unverified)

The guide's idempotency criterion is stated as 'stays a single dose in the InsulinDeliveryStore and IOB doesn't drift'. A grep for DoseStore, InsulinDeliveryStore and insulinOnBoard across Tests/TandemKitTests finds no code references — only comments and pump-message `iob` fields. The test target never feeds reported events into anything that computes IOB, and the Linux shim has no store types, so such a test would need a lightweight in-test model of DoseStore's purge/un-delete semantics (mutable==YES purge on replacePendingEvents, syncIdentifier matching) rather than real LoopKit. Absent that, IOB drift from duplicate or dropped mutable doses cannot be detected by CI on any path.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:9` the only delegate in tests is a recording mock; no DoseStore/InsulinDeliveryStore is instantiated
  - `Tests/TandemKitTests/HistoryBackfillCoordinatorTests.swift:210` IOB appears only in comments explaining why the walk depth matters
  - `LinuxShims/LoopKit/LoopKit.swift:1` Linux shim defines no DoseStore/InsulinDeliveryStore, so a store-backed test could not compile on Linux CI

- Recommendation: Add a small test double that mirrors DoseStore.addPumpEvents semantics (purge mutable when replacePendingEvents, dedupe by raw) and feed the mock's recorded calls through it; assert one dose and stable summed units after N re-reports.

Open questions raised by this point:

- The driver does not re-report a running bolus or temp basal on subsequent syncs (fetchBasalStatus emits only on basal-type change; fetchBolusStatus(fromSync:) defers while a bolus runs). Under the guide's §3 report-or-delete rule, a mutable dose omitted from a later replacePendingEvents: true batch is deleted by DoseStore. This affects §3/§5/§6 points more than P17 and should be assessed there.
- MockPumpManagerDelegate discards lastReconciliation and replacePendingEvents, so §6 empty-sync and §5 flag-choice tests cannot currently be written either; the same mock extension would unblock P17 and those points.
- Whether Apple-platform test runs (real LoopKit linked) could instantiate a DoseStore in-process for a true InsulinDeliveryStore-level idempotency check was not determined from the code; the Linux shim clearly cannot.
### P18. Tests confirm a sync with no new doses still calls hasNewPumpEvents and advances lastReconciliation

Guide section: §11 testing: empty syncs.

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 1 of 2 verifier passes completed

No test confirms that an empty sync calls hasNewPumpEvents, and none could: MockPumpManagerDelegate discards the lastReconciliation and replacePendingEvents arguments and no test reads its recorded pumpEvents or arms the events expectation. The reason is structural: syncPumpData advances state.lastReconciliation but never calls emitPumpEvents; fetchBasalStatus and fetchBolusStatus emit only on a change, so a steady-state sync makes no delegate dose call and DoseStore.lastPumpEventsReconciliation is not advanced. Existing ConnectionTests do pin the state/completion-callback half well (advances on any response, not on connect failure or a silent pump, persisted across relaunch). The delegate half of the §6/§11 contract is untested and, in production, unimplemented.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P18-1 | Non-conforming | medium | amended | No test asserts hasNewPumpEvents on a sync |
| P18-2 | Non-conforming | medium | verified | Empty sync never calls hasNewPumpEvents in production |
| P18-3 | Partial | low | verified | State-level lastReconciliation advancement is well tested |
| P18-4 | Non-conforming | low | verified | Mock delegate cannot observe lastReconciliation or call count |
| P18-5 | Non-conforming | medium | verified | First sync after pairing: no delegate, events dropped, untested |
| P18-6 | Partial | low | verified | Relaunch: skip-if-fresh path returns persisted date without delegate call |
| P18-A1 | Partial | medium | unverified | Reservoir read alone advances lastReconciliation without any delegate event call |
| P18-A2 | Partial | medium | unverified | Test pins lastReconciliation advancing on any single response, not a delivery read |
| P18-A3 | Partial | low | unverified | emitPumpEvents reads lastReconciliation lazily on the delegate queue |

**P18-1 No test asserts hasNewPumpEvents on a sync** (Non-conforming, impact medium, amended)

A repo-wide search of Tests/ finds no reference to delegate.pumpEvents, didReceivePumpEventsExpectation, hasNewPumpEvents or replacePendingEvents outside the mock itself. The only tests that attach MockPumpManagerDelegate (telemetry reservoir, PumpConnectionIssue, ReservoirReportDelivery, HistoryBackfillCoordinator) assert on reservoir readings, status updates or the emit floor. The sync tests in ConnectionTests run syncPumpData without any delegate. Git history (9e551d0, 33d2445) shows earlier inline test delegates also discarded hasNewPumpEvents, so this coverage never existed. The §11 'Empty syncs' recommendation is therefore not represented in the suite.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:133` synchronized { _pumpEvents += events } -- events recorded, but no test reads pumpEvents
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:45` var didReceivePumpEventsExpectation: XCTestExpectation? -- never set by any test
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:104` testSuccessfulSyncAdvancesLastReconciliation attaches no delegate at all
  - `Tests/TandemKitTests/TandemPumpManagerTelemetryTests.swift:133` XCTAssertNotNil(manager.state.lastReconciliation) -- state-level only, delegate events unchecked

- Recommendation: Add a ConnectionTests case: attach MockPumpManagerDelegate, stub sync responses with basal type equal to state.basalDose.type and no bolus, run syncPumpData, and assert hasNewPumpEvents was invoked once with [] and lastReconciliation == state.lastReconciliation.

- Verifier notes:
  - [code:amend] Core claim verified: no current test references delegate.pumpEvents, didReceivePumpEventsExpectation, or asserts hasNewPumpEvents; ConnectionTests attach no delegate. One key fact is wrong: at 33d2445 TandemPumpManagerHistoryIntegrationTests had a CapturingPumpManagerDelegate that captured hasNewPumpEvents and asserted XCTAssertNotNil(lastReconciliation) (deleted in 9e551d0). So coverage of the delegate argument existed for history events, though never for an empty sync. Verdict and impact stand.

**P18-2 Empty sync never calls hasNewPumpEvents in production** (Non-conforming, impact medium, verified)

The behaviour P18's test would confirm is absent. Every emitPumpEvents call site (enactBolus, cancelBolus, enactTempBasal, suspend, resume, fetchBasalStatus/fetchBolusStatus change branches, home-screen mirror, site/cartridge change) fires only when a dose event exists. A steady-state sync with unchanged basal type and no bolus therefore updates state.lastReconciliation (which feeds lastSync and the connection-issue logic) but never reaches DoseStore.addPumpEvents, so the host's lastPumpEventsReconciliation stays at the last dose event. This contradicts the delegate doc comment the Trio-pinned LoopKit carries (PumpManager.swift:58) and guide §6/§8. Note historyBackfillCoordinator.runTick (line 455) also emits nothing today.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:445` self.state.lastReconciliation = Date.now -- advanced in syncPumpData
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:450` self.notifyDelegateStateUpdated() -- the only delegate traffic syncPumpData itself produces
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:253` delegate.pumpManagerDidUpdateState(self) -- notifyDelegateStateUpdated sends no pump events
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:141` if activeBasalType != state.basalDose.type { -- fetchBasalStatus emits only on a type change
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:217` if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil { -- returns without emitting

- Recommendation: After the response-count check in syncPumpData, call emitPumpEvents([]) (replacePendingEvents: true) whenever lastReconciliation was advanced and no fetch already emitted, then add the test in P18-1. Reassess the impact on Trio's own hasNewPumpEvents handler before shipping.

- Verifier notes:
  - [code:confirm] Verified literally: syncPumpData stamps lastReconciliation at 445 and calls only notifyDelegateStateUpdated (450), which sends pumpManagerDidUpdateState/didUpdate status (253-254), never hasNewPumpEvents. fetchBasalStatus emits only inside `activeBasalType != state.basalDose.type` (141); fetchBolusStatus returns at 217 without emitting. HistoryBackfillCoordinator contains no emitPumpEvents call. Trio-pinned DoseStore.addPumpEvents sets lastPumpEventsReconciliation only when called (680). Doc comment at PumpManager.swift:57-58 confirmed.

**P18-3 State-level lastReconciliation advancement is well tested** (Partial, impact low, verified)

The 'advances lastReconciliation' half of P18 is covered at the state and ensureCurrentPumpData-completion level: a sync with no doses but at least one pump response advances it (these stubs return only reservoir/battery/API version, i.e. an empty-dose sync), a connect failure or fully silent session leaves it untouched, and the completion value equals state. This is the right guard for a UI-capable pump. What is missing is any assertion that the same date is handed to Loop through the hasNewPumpEvents lastReconciliation parameter, which is the value DoseStore actually stores.

- Evidence:
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:119` XCTAssertEqual(reportedLastSync, manager.state.lastReconciliation) -- successful sync
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:78` A failed sync must not advance lastReconciliation
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:140` silent pump: XCTAssertEqual(manager.state.lastReconciliation, previousSync)
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:170` single response advances: XCTAssertNotEqual(manager.state.lastReconciliation, previousSync)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:447` Sync got no response from the pump; leaving lastSync where it was

- Recommendation: Keep these tests; extend testSuccessfulSyncAdvancesLastReconciliation and testSyncAdvancesLastSyncOnASingleResponse to also assert the delegate received the identical lastReconciliation via hasNewPumpEvents.

- Verifier notes:
  - [code:confirm] All cited assertions exist at the cited lines (78, 119, 140, 170) and the response-count gate is at 443-447. The stubs in stubSyncResponses (ApiVersion, InsulinStatus, CurrentBatteryV1) indeed produce a dose-free sync. Verdict partial and low impact are appropriate: state-level advancement is tested; delivery of that date to the host via hasNewPumpEvents is not.

**P18-4 Mock delegate cannot observe lastReconciliation or call count** (Non-conforming, impact low, verified)

Even if a test were written, the current harness flattens all hasNewPumpEvents calls into one events array and drops lastReconciliation and replacePendingEvents. An invocation with events == [] is indistinguishable from no invocation, and the reconciliation date Loop would store is unobservable. The stub bluetooth (StubPumpBluetooth.responseCount) already provides what is needed on the pump side, so the gap is entirely in the delegate recorder.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:129` lastReconciliation _: Date?, -- argument discarded
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:130` replacePendingEvents _: Bool, -- argument discarded
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:36` var pumpEvents: [NewPumpEvent] -- flattened; an empty call leaves no trace

- Recommendation: Record each hasNewPumpEvents call as a struct {events, lastReconciliation, replacePendingEvents} in an ordered array, alongside the existing flattened pumpEvents, so tests can assert count, emptiness and the reported date.

- Verifier notes:
  - [code:confirm] Verified: the mock's hasNewPumpEvents signature discards lastReconciliation (129) and replacePendingEvents (130) with `_`, and appends events into one flattened array (133); the expectation at 45 is optional and unset by every test. An empty-events call is therefore unobservable except via the expectation, and the reported date is never observable. StubPumpBluetooth.responseCount exists (StubPumpBluetooth.swift:26).

**P18-5 First sync after pairing: no delegate, events dropped, untested** (Non-conforming, impact medium, verified)

The pairing-time sync runs before the host adopts the manager (per the comment above reportReservoirReading). On that path emitPumpEvents discards anything it would have sent and no later flush replays it, so the first lastReconciliation is never delivered to DoseStore until a dose-changing event occurs. ReservoirReportDeliveryTests pin the analogous reservoir problem; no test covers the pump-event/lastReconciliation side of the same first-sync path.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1736` self.logger.warning("No pump delegate, not notifying...") -- pump events are dropped, not held
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:447` func flushPendingReservoirReading() -- reservoir has a replay path; pump events/lastReconciliation do not
  - `Tests/TandemKitTests/ReservoirReportDeliveryTests.swift:6` tests exist for the reservoir flush, none for pump events or lastReconciliation after the delegate attaches

- Recommendation: Mirror the reservoir flush: when a delegate attaches and state.lastReconciliation is set, emit hasNewPumpEvents with the current active events (or []) and that date; add a ReservoirReportDelivery-style test for it.

- Verifier notes:
  - [code:confirm] Verified: emitPumpEvents drops events when no delegate (1736) with no pending flag; deliverStateMissedByTheDelegate (called from the pumpManagerDelegate setter, 295) only calls notifyDelegateStateUpdated and flushPendingReservoirReading (306-307), so no pump event or lastReconciliation is replayed. The pairing path (TandemKitScanViewModel.onPairSuccess -> syncPumpData at :91) runs before the host adopts the manager, as the comment at StateSync 428-430 states. ReservoirReportDeliveryTests cover only the reservoir side.

**P18-6 Relaunch: skip-if-fresh path returns persisted date without delegate call** (Partial, impact low, verified)

Persistence of lastReconciliation and the ensureCurrentPumpData fresh-skip are both tested, and skipping is legitimate (no pump contact occurred, so no new trust is claimed). But after an app relaunch the persisted date is returned via the completion only; nothing re-asserts it to the host through hasNewPumpEvents, and once the 4.5-minute window passes the real sync also emits nothing (P18-2). No test distinguishes the relaunch case, so whether Loop's DoseStore ever learns the driver's persisted reconciliation point before the next dose event is unverified.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:360` if let lastSync = state.lastReconciliation, Date.now.timeIntervalSince(lastSync) < .minutes(4.5) { -- no sync, no delegate call
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:251` XCTAssertEqual(bluetooth.ensureConnectedCount, 0, "A fresh sync should not touch the pump")
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:365` raw["lastReconciliation"] = lastReconciliation?.timeIntervalSinceReferenceDate
  - `Tests/TandemKitTests/TandemPumpManagerStateTests.swift:80` XCTAssertEqual(restored.lastReconciliation, timestamp) -- persistence round-trip tested

- Recommendation: Add a test constructing a manager from persisted rawValue with a recent lastReconciliation, attaching a delegate, and asserting the expected delegate behaviour on the first ensureCurrentPumpData; decide explicitly whether the skip path should re-emit the persisted date.

- Verifier notes:
  - [code:confirm] Verified: the 4.5-minute skip at 360-363 returns the persisted date through completion only; test at 251 pins that no pump contact occurs; persistence round trip at State 196-197/365 and StateTests 80. Additionally the in-flight stand-down (392) returns state.lastReconciliation without any delegate call, another path where the persisted date is handed only to completion. No test constructs a manager from a persisted rawValue with a delegate attached.

**P18-A1 Reservoir read alone advances lastReconciliation without any delegate event call** (Partial, impact medium, unverified, added by a verifier)

The auditor treated syncPumpData:445 as the place an empty sync advances lastReconciliation, but fetchReservoirStatus stamps it independently of the response-count gate, and is reachable on its own from the cartridge-change UI and from qualifying-event fetches (TandemPumpManager.swift:1688). Each of those advances state.lastReconciliation (feeding lastSync and the next emitPumpEvents date) with no hasNewPumpEvents call, so it is a second production path with the P18-2 gap. TelemetryTests:133 is actually pinning this reservoir-path behaviour, which the auditor attributed to sync.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:410` state.lastReconciliation = timestamp -- stamped by fetchReservoirStatus itself
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:392` completion(self.fetchReservoirStatus()) -- standalone command job callable outside syncPumpData
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitChangeCartridgeViewModel.swift:169` pumpManager?.fetchReservoirStatus { units in -- UI caller
  - `Tests/TandemKitTests/TandemPumpManagerTelemetryTests.swift:133` XCTAssertNotNil(manager.state.lastReconciliation) -- this asserts the reservoir-path stamp, not syncPumpData's

- Recommendation: Either drop the stamp from fetchReservoirStatus (let syncPumpData own it) or follow it with an empty hasNewPumpEvents; add a test that a standalone reservoir fetch does not advance lastReconciliation without informing the host.

**P18-A2 Test pins lastReconciliation advancing on any single response, not a delivery read** (Partial, impact medium, unverified, added by a verifier)

The existing 'advances lastReconciliation' test enshrines that one answer of any kind (here a reservoir reading, with CurrentBasalStatusRequest and CurrentBolusStatusRequest unanswered) moves the trust boundary to now. For a UI-capable pump (guide §6) that claims delivery is accounted for when neither basal nor bolus status was read and no history was reconciled. The test suite therefore confirms advancement under conditions the guide says should not advance it; any P18 test added should not copy this fixture as the 'empty sync' case.

- Evidence:
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:158` only InsulinStatusRequest stubbed; basal/bolus reads return nil
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:170` XCTAssertNotEqual(manager.state.lastReconciliation, previousSync) -- asserted as desired behaviour
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:444` if self.bluetooth.responseCount > responsesBefore { -- any response, including alerts/time, counts

- Recommendation: Gate the stamp on the basal and bolus status reads (or a history reconcile) succeeding rather than responseCount, and change testSyncAdvancesLastSyncOnASingleResponse to assert non-advancement when only a non-delivery read answers.

**P18-A3 emitPumpEvents reads lastReconciliation lazily on the delegate queue** (Partial, impact low, unverified, added by a verifier)

The date passed to hasNewPumpEvents is whatever state.lastReconciliation holds when the delegate queue runs the block, not when the event was produced. Ordering is preserved on a serial queue, but a test asserting the reported date equals the sync's completion value must run the delegate queue to completion first, and a later stamp (e.g. a reservoir read at StateSync:410 on another job) can be observed by an earlier event's delegate call. Relevant to how a P18 test should be written and to the accuracy of the reported boundary.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1743` lastReconciliation: self.state.lastReconciliation, -- read inside the async notify closure
  - `LinuxShims/LoopKit/LoopKit.swift:845` queue.async { block(delegate) } -- notify defers the block

- Recommendation: Capture lastReconciliation at the call site and pass it into the notify closure; in tests, drain the delegate queue (queue.sync {}) before asserting the recorded date.

Open questions raised by this point:

- How does Trio's DeviceDataManager implement pumpManager(_:hasNewPumpEvents:lastReconciliation:...)? If Trio ignores lastReconciliation and only stores events into its own pump history, the accounting impact of P18-2 is Loop-specific; Trio source was not available to verify.
- The emitPumpEvents site at Sources/TandemKit/PumpManager/TandemPumpManager.swift:1318-1332 creates a scheduled-basal dose; its trigger (reconnect, qualifying event or Control-IQ transition) was not traced for this point and should be characterised when auditing the reconnect path.
- Guide vs. repo: the guide treats an empty hasNewPumpEvents call as required on every sync; CLAUDE.md line 541 lists 'gap-aware lastReconciliation advancement' as future work tied to history emission, suggesting the team plans to gate reconciliation advancement on a full history read (§6 UI-capable archetype) rather than on status polls. Which archetype TandemKit intends to follow should be settled before P18-2's fix is chosen.
- CI runs TandemKitTests only via xcodebuild on macOS; no Linux swift test job was found, so the LinuxShims delegate signature is not exercised by tests.
### P19. Tests verify value and deliveredUnits are rounded to the pump's supported increment

Guide section: §11 testing: rounding.

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

Rounding is unit-tested only in HistoryToDoseMapper (bolus value/deliveredUnits rounded to 0.001 U reporting resolution, deliberately not the 0.05 U command grid) and at the wire layer (InitiateBolusRequest milliunit encoding, Float32 noise in BolusCompletedHistoryLog). But the mapper has no production caller, so those tests cover nothing Loop receives today. The live paths that do reach Loop are untested for rounding: roundToSupportedBolusVolume/roundToSupportedBasalRate and the capability tables, LastBolusStatus -> deliveredUnits (which floors to 0.05 U, contradicting the mapper's own rationale), TandemDoseProgressReporter, and temp-basal value/deliveredUnits (deliveredUnits is never rounded). Verdict: partial.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P19-1 | Partial | none | unverified | HistoryToDoseMapper bolus rounding tests |
| P19-2 | Non-conforming | low | unverified | Live bolus finalization deliveredUnits floors to 0.05 U, untested |
| P19-3 | Non-conforming | low | unverified | roundToSupported* helpers and capability tables have no tests |
| P19-4 | Non-conforming | low | unverified | TandemDoseProgressReporter untested |
| P19-5 | Partial | low | unverified | Temp basal value and deliveredUnits rounding untested |
| P19-6 | Partial | low | unverified | Wire-level milliunit and Float32 tests |
| P19-7 | Partial | low | unverified | Basal profile change value not rounded; test tolerates Float noise |

**P19-1 HistoryToDoseMapper bolus rounding tests** (Partial, impact none, unverified)

The history mapper has explicit rounding tests for both value and deliveredUnits, and they pin a documented, defensible choice: round to nearest 0.001 U (the pump's milliunit reporting resolution), not the 0.05 U bolus command increment, because Tandem reports genuine partial deliveries (e.g. 1.041 U) and flooring would understate IOB. This deviates in letter from the guide's 'supported increment' wording but is the safer interpretation. However, grep shows no production caller of HistoryToDoseMapper.mapToEvents outside its own file, so these tests currently verify a path that never reaches the host app.

- Evidence:
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:84` testBolusUnitsRoundedToReportingResolution: Float 0.9 -> programmedUnits/deliveredUnits == 0.9
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:121` XCTAssertEqual(dose.deliveredUnits, 1.041) — partial delivery preserved at 0.001 U
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:161` roundToReportingResolution: (units * 1000).rounded() / 1000
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:160` comment: floor-to-command-grid rounding called the 'unsafe direction'

- Recommendation: Keep these tests; when the mapper is wired to emission, add an end-to-end test asserting the emitted NewPumpEvent dose values through the delegate. Document the 0.001 U choice in a docs file so reviewers do not 'fix' it to 0.05.

**P19-2 Live bolus finalization deliveredUnits floors to 0.05 U, untested** (Non-conforming, impact low, unverified)

The path that actually reaches Loop today (cancel and natural completion, steady state and after reconnect while bolusProgressReport is still in memory) converts LastBolusStatus.deliveredVolume (milliunits) to units and then floors to the 0.05 U command grid. A cancelled bolus that delivered 1.041 U is reported as 1.00 U — the exact 'unsafe direction' the mapper comment warns about. No test in Tests/ references LastBolusStatus or deliveredVolume (only QualifyingEventTests in TandemCoreTests), so neither the milliunit conversion nor the flooring is verified. Two rounding policies for the same quantity coexist without a test pinning either.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:532` return roundToSupportedBolusVolume(units: Double(response.deliveredVolume) / 1000.0)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:226` supportedBolusVolumes.last(where: { $0 <= units }) ?? 0 — floor, not nearest
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` cancelBolus: deliveredUnits = queryLastBolusDeliveredVolume(...) ?? 0
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:256` natural completion also uses queryLastBolusDeliveredVolume

- Recommendation: Add StubPumpBluetooth tests stubbing LastBolusStatus responses (e.g. 1041, 1049, 0 mU) and asserting emitted deliveredUnits; switch queryLastBolusDeliveredVolume to round-to-nearest 0.001 U to match the mapper, or document why flooring is intended.

**P19-3 roundToSupported* helpers and capability tables have no tests** (Non-conforming, impact low, unverified)

Grep of Tests/ for roundToSupportedBolusVolume, roundToSupportedBasalRate, strideRange, TandemPumpCapabilities, onboardingSupportedBolusVolumes and supportedBasalRates returns nothing. These are the functions LoopKit calls to round requested values before enactBolus/enactTempBasal and that the driver uses to round reported values. On reading, the integer-stride construction is correct (values are the nearest doubles to k*0.05 / k*0.01, so exact literals like 1.0 are found by the <= search), and rounding 0 U returns 0 as the comment intends, but none of this is pinned. A future edit to the tables (e.g. Mobi vs X2 ranges) could silently change rounding of every reported dose.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:224` public func roundToSupportedBolusVolume(units:) — no test references it
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:229` public func roundToSupportedBasalRate(unitsPerHour:)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1870` strideRange builds tables via integer stride / 1000 (avoids FP drift)
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:234` TandemPumpCapabilities.supportedBasalRates: [0.0] + 0.1...15.0 by 0.01

- Recommendation: Add unit tests: table endpoints and counts (0.05...25.0 step 0.05; 0.0 then 0.1...15.0 step 0.01), exact-literal membership (1.0, 0.15, 2.35), floor behaviour for off-grid inputs, and 0/negative inputs.

**P19-4 TandemDoseProgressReporter untested** (Non-conforming, impact low, unverified)

No test file references TandemDoseProgressReporter or DoseProgress. The reporter rounds its time-estimated progress to the 0.05 U grid (UI-only), and builds the finalized bolus NewPumpEvent with value = programmed total and deliveredUnits = pump-reported (already floored by P19-2) or the programmed total. Whether the finalized event's value and deliveredUnits land on a supported increment is therefore never asserted. Note also that `units: delivered` participates in the raw identity string, so a rounding change would change the bolus syncIdentifier (outside this point, see open questions).

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:77` deliveredUnits = pumpManager.roundToSupportedBolusVolume(units: min(runningFor * unitsDeliveredPerSec, total))
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:33` getPumpEvent: delivered = actualDeliveredUnits ?? total (no rounding applied here)
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:47` units: delivered feeds NewPumpEvent.bolus raw key

- Recommendation: Add tests for getPumpEvent with nil and explicit actualDeliveredUnits asserting value, deliveredUnits and isMutable == false; add a notify() test with an injected clock asserting progress is on the 0.05 U grid and capped at total.

**P19-5 Temp basal value and deliveredUnits rounding untested** (Partial, impact low, unverified)

enactTempBasal does the right thing for `value`: it quantizes the request to an integer percent of the scheduled basal (what the pump actually delivers) and rounds the resulting absolute rate to the 0.01 U/hr grid. But no test drives enactTempBasal through StubPumpBluetooth (SyncBasalTests cover profile writes only), so the percent quantization and the reported rate are unverified — e.g. requesting 0.53 U/hr on a 0.8 U/hr baseline yields 66% -> 0.528 -> 0.52 U/hr, and the test suite would not notice a regression. The finalized deliveredUnits is value*hours with no rounding at all; mathematically correct, but not what the guide asks and untested.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:670` let unitsPerHour = roundToSupportedBasalRate(unitsPerHour: unitsPerHour)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:723` absoluteRate re-rounded from baseline * percent/100 (integer percent, capped 250)
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` deliveredUnits: isMutable ? nil : value * (duration / .hours(1)) — never rounded
  - `Tests/TandemKitTests/TandemPumpManagerStateTests.swift:166` only assertion on a temp basal rate: round-trip of 1.75, not rounding

- Recommendation: Add enactTempBasal tests asserting SetTempRateRequest.percent and the emitted mutable/finalized DoseEntry value; decide whether deliveredUnits should be rounded to 0.001 U and pin it in a UnfinalizedDose.toDoseEntry test.

**P19-6 Wire-level milliunit and Float32 tests** (Partial, impact low, unverified)

The TandemCore message tests verify the milliunit encoding of InitiateBolusRequest and the Float32 parsing of history bolus records, including a real capture showing Float noise (0.89000005). That covers the wire representation, and the manager's units->milliunits conversion uses rounded() so 0.13 U cannot become 129 mU. There are, however, no tests for LastBolusStatus/V2/V3 responses (the source of finalized deliveredUnits), for SetTempRateRequest, or for the manager-side conversion at line 551 itself — so the chain from wire bytes to the DoseEntry Loop receives is only tested at one end.

- Evidence:
  - `Tests/TandemCoreTests/Messages/Control/InitiateBolusRequestTests.swift:30` XCTAssertEqual(1000, Int(parsed.totalVolume)) — 1 U = 1000 mU round trip
  - `Tests/TandemCoreTests/Messages/Control/InitiateBolusRequestTests.swift:66` 0.13 U encoded as 130 mU
  - `Tests/TandemCoreTests/HistoryLog/BolusCompletedHistoryLogTests.swift:29` testBolusCompletedHistoryLog_mismatchingFloats: insulinDelivered 0.89000005 vs requested 0.89
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:551` let milliUnits = max(0, Int((units * 1000).rounded()))

- Recommendation: Add LastBolusStatus response parsing tests with milliunit deliveredVolume fixtures and a SetTempRateRequest test; add one manager test asserting InitiateBolusRequest.totalVolume for an off-grid Double like 0.13.

**P19-7 Basal profile change value not rounded; test tolerates Float noise** (Partial, impact low, unverified)

Within the same mapper, bolus amounts are cleaned of Float32 noise but the .basal rate is passed through unrounded, and the corresponding test is written with an accuracy tolerance rather than asserting the exact 1.15 the pump displays. The mapper's temp-basal test also supplies its own round-to-nearest closure, so the production floor (roundToSupportedBasalRate) is never exercised through the mapper. Impact is cosmetic today (scheduled-basal values with 1e-8 noise, and the mapper is unwired), but it is an inconsistency the tests currently enshrine rather than catch.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:277` value: Double(basalChange.commandBasalRate) — raw Float32 widened, no rounding
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:260` XCTAssertEqual(dose.unitsPerHour, 1.15, accuracy: 1e-6) — accepts 1.14999997
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:16` tests inject roundBasalRate = nearest 0.01, not the production floor helper

- Recommendation: Apply roundToReportingResolution (or the basal 0.01 grid) to commandBasalRate and tighten the test to an exact 1.15; add one mapper test that passes the production roundToSupportedBasalRate closure.

Open questions raised by this point:

- The guide asks for rounding to the pump's 'supported increment'; Tandem reports delivered volume in 0.001 U and genuinely delivers partial boluses, so the mapper's 0.001 U policy (HistoryToDoseMapper.swift:161) is arguably more correct than the guide's wording. The live path floors to 0.05 U instead (StateSync:532). Which policy is intended should be decided once and tested.
- cancelBolus falls back to deliveredUnits = 0 when LastBolusStatus fails or returns a different bolusId (TandemPumpManager.swift:639), which would report a possibly-delivered bolus as zero delivery; this is a finalization/accounting concern for other points, not rounding.
- NewPumpEvent.bolus embeds `units` (programmed on enact, delivered on cancel/complete) in the raw identity string (Extensions/NewPumpEvent.swift:9), so any change in rounding of deliveredUnits also changes the bolus syncIdentifier between the mutable and final report — relevant to the §4 stable-identity points.
- After an app relaunch, bolusProgressReport is in-memory only, so fetchBolusStatus returns before finalizing a persisted bolusDose (StateSync:239); rounding of that dose is moot because it is never emitted — relevant to the persistence/reconnect points.
- HistoryToDoseMapper.mapToEvents has no production caller at HEAD, so CLAUDE.md's description of history-derived doses should be read as aspirational for all P19 findings about the mapper.
### P20. Tests bolus on the pump directly and confirm Loop picks it up from history with wasProgrammedByPumpUI = true and accounts for it in IOB

Guide section: §11 testing: external doses (UI pumps).

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

No test exercises the guide's external-dose scenario end to end. The only `wasProgrammedByPumpUI` assertions are mapper-only unit tests (HistoryToDoseMapperTests:61, 81) that feed a stub `isCommandedBolus` closure; no test in the repo ever reads `MockPumpManagerDelegate.pumpEvents`, so nothing asserts what `hasNewPumpEvents` received. The path cannot be tested today because it does not exist: `HistoryToDoseMapper` has no production caller, `HistoryBackfillCoordinator` explicitly emits nothing, `historyDoseReporting` (default off, and gated on `historyBackfill`, also default off) has no consumer, and the status-poll bolus path returns early for any bolus the app did not command. Pump-UI and Control-IQ boluses are therefore neither reported nor flagged, and lastReconciliation still advances past them.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P20-1 | Non-conforming | medium | unverified | Test coverage: pump-UI bolus to hasNewPumpEvents |
| P20-2 | Non-conforming | high | unverified | History-to-delegate emission path does not exist |
| P20-3 | Non-conforming | high | unverified | Status-poll bolus path ignores pump-UI boluses |
| P20-4 | Non-conforming | medium | unverified | Feature flags gate history doses and default off |
| P20-5 | Non-conforming | medium | unverified | No production source for isCommandedBolus |
| P20-6 | Partial | medium | unverified | Mitigations narrow but do not remove external doses |
| P20-7 | Non-conforming | low | unverified | Docs and manual test plan omit the external-dose case |

**P20-1 Test coverage: pump-UI bolus to hasNewPumpEvents** (Non-conforming, impact medium, unverified)

The guide's §11 item asks for a test that a bolus made on the pump is picked up from history and reaches Loop with `wasProgrammedByPumpUI = true`. TandemKit's coverage stops at the mapper: HistoryToDoseMapperTests asserts the flag on a `NewPumpEvent` returned by `mapToEvents`, with `isCommandedBolus` stubbed. TandemPumpManagerHistoryIntegrationTests streams logs through the fetcher into `historyLogStore` and asserts counts/sequence numbers, never doses. No test anywhere inspects `MockPumpManagerDelegate.pumpEvents` or sets `didReceivePumpEventsExpectation`, so there is no assertion on any `hasNewPumpEvents` payload, let alone one carrying a pump-UI bolus.

- Evidence:
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:61` Only positive assertion: `XCTAssertTrue(dose.wasProgrammedByPumpUI)` on mapper output, not delegate output
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:17` Flag derives from a test-supplied stub `isCommandedBolus: ... = { _ in false }`
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:36` `var pumpEvents: [NewPumpEvent]` is recorded but no test file reads it (grep: 3 hits, all in the mock)
  - `Tests/TandemKitTests/TandemPumpManagerHistoryIntegrationTests.swift:6` Integration suite drives `HistoryLogFetcher` and the store only; no delegate assertions

- Recommendation: Add a manager-level test: stub `HistoryLogStatusRequest`/`HistoryLogRequest`, stream a Quick Bolus activation+completion, run the sync/backfill, and assert `delegate.pumpEvents` contains a `.bolus` with `wasProgrammedByPumpUI == true`, `isMutable == false`, and a `HistoryLogSyncIdentifier.bolus` raw.

**P20-2 History-to-delegate emission path does not exist** (Non-conforming, impact high, unverified)

The scenario cannot currently be tested to pass because no production code turns stored history into delegate events. `HistoryToDoseMapper.mapToEvents` (which sets `wasProgrammedByPumpUI`) has zero callers outside its test. `HistoryBackfillCoordinator.runTick`, the only history work kicked from `syncPumpData`, reads logs into `historyLogStore` and persists a watermark but by design emits nothing. Every `emitPumpEvents` call site (TandemPumpManager 598/657/743/778/828/910/1062/1071/1330; StateSync 161/183/268/512) originates from app-commanded doses or status polls, not from history. This holds on steady state, first sync, reconnect and relaunch alike. The LoopKit fork Trio pins does expose the field, so the gap is TandemKit-side.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:18` `final class HistoryToDoseMapper` — referenced only by its own file and its unit test (repo-wide grep)
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:9` "Nothing is mapped to doses or emitted here — that is the emission layer's job"
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:455` `self.historyBackfillCoordinator.runTick()` is the only history hook in `syncPumpData`
  - `Tests/TandemKitTests/HistoryBackfillCoordinatorTests.swift:506` "Nothing consumes the store yet, so this only fixes the contract the emission layer will be built against"
  - `reference: loopkit-trio/DoseEntry.swift:26` `public let wasProgrammedByPumpUI: Bool` — the field exists in the LoopKit TandemKit builds against

- Recommendation: Build the emission layer: after a tick, map `historyLogStore` entries above `emitFloor` via `HistoryToDoseMapper`, reconcile against pending app doses, and call `emitPumpEvents`. Gate on `historyDoseReporting`. Then write the P20-1 test against it.

**P20-3 Status-poll bolus path ignores pump-UI boluses** (Non-conforming, impact high, unverified)

Besides history, the only other place the driver could notice an external bolus is `fetchBolusStatus` on each sync. If `CurrentBolusStatusResponse` reports `.delivering` for a Quick Bolus or Control-IQ correction, `bolusProgressReport` is nil (it is created only in `enactBolus`), so the function returns before any event is built; when the bolus later finishes, `bolusId == 0` is also unreachable for the same reason. `UnfinalizedDose.toDoseEntry` never sets `wasProgrammedByPumpUI`, so even a hypothetical status-derived report would be mis-flagged. TandemPumpManagerBolusSyncTests contain no pump-UI or `wasProgrammedByPumpUI` scenario (grep empty). Net effect: an external bolus is invisible to Loop on every path, which is the IOB under-count the guide's §6/§7 warn about.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:226` `guard let progressReport = bolusProgressReport else { return }` — no report means nothing emitted
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:231` `if let dose = state.bolusDose {` — delivering status only updates an app-owned dose
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:588` `self.bolusProgressReport = TandemDoseProgressReporter(` — sole creation site, inside enactBolus
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:155` `DoseEntry(type: .bolus, ...)` built without `wasProgrammedByPumpUI` (defaults false)

- Recommendation: Until history emission lands, add a test that a `.delivering` status with no app dose does not silently return, and consider reporting such a bolus as mutable with `wasProgrammedByPumpUI: true`, finalizing from `LastBolusStatus` or history.

**P20-4 Feature flags gate history doses and default off** (Non-conforming, impact medium, unverified)

Conformance for external doses depends on two opt-in flags. With defaults, the pump's history log is never read (`runTick` returns immediately), so no pump-UI bolus can be discovered. Even with both flags on, `historyDoseReporting` has no consumer (P20-2), so the flag is a contract placeholder. The existing tests codify this non-reporting (`testDoseReportingIsOffEvenWithTheBackfillRunning`) rather than the guide's expected behaviour. For a UI-capable pump where the user can bolus from the touchscreen and Control-IQ auto-corrects, shipping with external-dose accounting off by default means the default configuration under-counts IOB whenever those happen.

- Evidence:
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:36` `.historyBackfill, .historyDoseReporting:` both `return false` by default
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:173` `self[.historyBackfill] && self[.historyDoseReporting]` — reporting requires backfill too
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:59` `guard pumpManager?.state.featureFlags.historyBackfill == true else {` — off means no history read at all
  - `Tests/TandemKitTests/HistoryBackfillCoordinatorTests.swift:477` `XCTAssertFalse(manager.state.featureFlags.historyBackfill, "Off unless a user turns it on")`

- Recommendation: Once emission exists, revisit defaults: for t:slim X2/Mobi consider `historyBackfill` and `historyDoseReporting` on by default, or block closed-loop dosing while they are off. Add tests for both flag states at the delegate level.

**P20-5 No production source for isCommandedBolus** (Non-conforming, impact medium, unverified)

The mapper's `wasProgrammedByPumpUI` logic is correct in shape (mirrors MinimedKit's `!wasRemotelyTriggered`), but nothing in production implements `isCommandedBolus`. Repo grep finds no persisted set of app-commanded `bolusId`s; `TandemPumpManagerState` keeps only `bolusDose` for the current bolus and clears it on completion. A future emission layer that backfills a window after the bolus finished would have no way to distinguish an app bolus from a Quick Bolus and would either flag all as pump-UI or none. This is a prerequisite for the P20 test to be meaningful and is currently untested beyond the stub closure.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:194` `wasProgrammedByPumpUI: !isCommandedBolus(completion.bolusId)` — caller must supply the predicate
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:594` `self.state.bolusDose = dose` — only the single in-flight bolus id is retained
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:263` `state.bolusDose = nil` on completion — the commanded id is forgotten before history is read

- Recommendation: Persist app-commanded bolus ids (bounded ring, keyed by pump serial) in `TandemPumpManagerState`, survive relaunch, and pass a lookup as `isCommandedBolus`. Test that a history window containing one commanded and one Quick Bolus flags only the latter.

**P20-6 Mitigations narrow but do not remove external doses** (Partial, impact medium, unverified)

TandemKit does reduce the external-dose surface: by default every sync turns the pump's Quick Bolus button off, and this is tested. However, the t:slim X2 touchscreen bolus cannot be disabled by the app, Control-IQ auto-corrections and basal modulation run on the pump, and `enactBolus` only blocks *automatic* boluses under Control-IQ (manual ones still pass), while temp basals are blocked. So the guide's UI-pump archetype applies and the external-dose test remains necessary; the mitigations do not make P20 not_applicable. No test models a touchscreen bolus or a Control-IQ correction reaching Loop.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:434` `self.enforceQuickBolusDisabled()` each sync (flag `quickBolusButtonSupport` default off)
  - `Tests/TandemKitTests/QuickBolusEnforcementTests.swift:54` `testSyncDisablesTheQuickBolusButtonWhenTheFlagIsOff` covers the enforcement
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:517` `if state.useControlIQ, activationType.isAutomatic {` — only automatic boluses blocked under Control-IQ
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:673` `guard !state.useControlIQ else {` — temp basal blocked under Control-IQ

- Recommendation: Keep quick-bolus enforcement, but add tests for the un-mitigable cases: a touchscreen bolus and a Control-IQ correction bolus appearing in history and reaching the delegate flagged `wasProgrammedByPumpUI`.

**P20-7 Docs and manual test plan omit the external-dose case** (Non-conforming, impact low, unverified)

The only written test/validation plan for history integration lists Loop-issued boluses in its manual hardware checklist and never the guide's "bolus on the pump directly" case. Its progress notes also assert a `fetchPumpHistory` delegate-delivery path exists, which the current tree contradicts (no such symbol; CLAUDE.md confirms `HistoryReconciler`/`HistoryToDoseMapper` wiring was dropped). Anyone using the doc as a QA script would believe external doses are covered when neither the code nor a manual step exists.

- Evidence:
  - `docs/tandemkit-history-integration-plan.md:619` Manual list has "Issue bolus from Loop, verify appears in history" but no bolus-on-pump item
  - `docs/tandemkit-history-integration-plan.md:681` Claims Phase 6 `fetchPumpHistory` wired "with delegate delivery" — symbol absent from Sources (grep)
  - `docs/tandemkit-history-integration-plan.md:666` Plans `HistoryReconcilerTests.swift` — type no longer exists in Sources or Tests

- Recommendation: Update the plan: mark Phase 6 emission as not implemented, add manual steps "Quick Bolus / touchscreen bolus on pump → appears in Loop with pump-UI flag and IOB rises" and "Control-IQ correction → same", and add the corresponding automated test to Phase 8.

Open questions raised by this point:

- §6 (likely another point): `syncPumpData` sets `state.lastReconciliation = Date.now` after status-only reads (TandemPumpManager.swift:445; also StateSync 159/181/265) without any history read, so for this UI-capable pump Loop is told delivery is trusted past unread pump-UI boluses. This is the mechanism by which the P20 scenario would fail on IOB even once emission exists, unless lastReconciliation is tied to the history watermark.
- When the emission layer is built, will `wasProgrammedByPumpUI` also be set on Control-IQ auto-correction boluses (they are pump-initiated but automatic)? The guide's MinimedKit precedent flags them as pump-UI; confirm whether Trio treats `automatic` and `wasProgrammedByPumpUI` together as intended.
- Should the P20 test cover the app-relaunch case: a Quick Bolus completed while the app was closed, discovered on the first backfill tick after relaunch, still flagged pump-UI given `state.bolusDose` is nil and no commanded-id set is persisted?
### P21. Reported dose timeline is diffed against the pump's own delivery history and expected IOB, so small persistent discrepancies surface

Guide section: §11 testing: timeline diff vs pump history.

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

TandemKit never diffs the doses it reports against the pump's own delivery history or against an expected IOB. History log entries are fetched into an in-memory store (only behind the default-off `historyBackfill` flag), but `HistoryToDoseMapper` has no caller, the coordinator explicitly emits nothing, and no code compares store contents with the live-path doses sent via `emitPumpEvents`. The pump's IOB is never read; `latestInsulinOnBoard` is never assigned. The only pump-side cross-check is a `LastBolusStatus` read at bolus end, whose failure is silently absorbed (full programmed units on completion, 0 U on cancel). Tests are component unit tests; the log viewer shows raw records only; docs describe a `HistoryReconciler` that does not exist.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P21-1 | Non-conforming | medium | unverified | Live-path vs history-path dose reconciliation |
| P21-2 | Partial | high | unverified | Live-path cross-check against pump status at bolus end |
| P21-3 | Non-conforming | medium | unverified | Expected-IOB comparison |
| P21-4 | Non-conforming | low | unverified | Test coverage for timeline diffing |
| P21-5 | Partial | low | unverified | Diagnostic tooling for manual diffing |
| P21-6 | Non-conforming | low | unverified | Documentation claims a reconciler that does not exist |

**P21-1 Live-path vs history-path dose reconciliation** (Non-conforming, impact medium, unverified)

Every path that reaches `emitPumpEvents` (enactBolus/cancelBolus/enactTempBasal/suspend/resume, fetchBasalStatus, handleBolusResponse, home-screen mirror) builds doses from app-side `UnfinalizedDose` state plus status polls. History records, when fetched at all (flag default off), land in the session store and are never mapped, never compared to what was emitted, and never surfaced as a discrepancy. This holds in steady state, on first sync after pairing, after BLE reconnect, and after relaunch (where the store is additionally empty). So a persistent gap such as a Control-IQ correction bolus or a pump-UI quick bolus missing from the reported timeline has no detector in the driver.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:8` "nothing is emitted to a delegate, reconciled against pending optimistic doses, or persisted"
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:9` "Nothing is mapped to doses or emitted here"
  - `CLAUDE.md:539` "nothing consumes the store's contents. `HistoryToDoseMapper` is not wired" — confirmed by grep: no caller outside its own file
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:36` historyBackfill and historyDoseReporting default to false
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:59` guard featureFlags.historyBackfill == true else return — no history read by default

- Recommendation: Add a reconciliation pass (the planned emission layer) that maps stored history for the window since last emission and compares by bolusId/tempRateId and amount against emitted doses; log and surface any dose present in one timeline and absent from the other.

**P21-2 Live-path cross-check against pump status at bolus end** (Partial, impact high, unverified)

The driver does consult the pump once per Loop-commanded bolus (`LastBolusStatus.deliveredVolume`), which is a partial form of diffing against the pump's record. But a discrepancy is not surfaced: if the read fails or the pump's last bolus has a different bolusId (e.g. a Control-IQ bolus started after ours), natural completion is finalized at the full programmed amount and cancellation at 0 U delivered, both immutable, with only a log line. Temp basals and suspend/resume are finalized purely from elapsed time with no pump cross-check at all. No aggregate or persistent mismatch is tracked.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:254` "Query the pump for actual delivered volume rather than assuming full delivery"
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:528` bolusId mismatch only logs a warning and returns nil
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:33` let delivered = actualDeliveredUnits ?? total
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` temp basal deliveredUnits = value * elapsed; never checked against the pump

- Recommendation: When the status read fails or the bolusId mismatches, finalize from history (BolusCompletedHistoryLog for that bolusId) rather than 0/programmed; until then leave the dose mutable and record a visible discrepancy counter in state/debugDescription.

**P21-3 Expected-IOB comparison** (Non-conforming, impact medium, unverified)

The pump exposes its own IOB (ControlIQIOBRequest / NonControlIQIOBRequest, and the `iob` field on BolusCompletedHistoryLog), which would be the natural 'expected IOB' to diff Loop's computed IOB against. Grep of Sources/TandemKit finds no read of any of these; `latestInsulinOnBoard` is persisted but never populated, so the debugDescription value is always nil. There is therefore no way, in code or diagnostics, to notice that Loop's IOB has drifted from what the pump believes it has delivered.

- Evidence:
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:47` public var latestInsulinOnBoard: Double? — only assigned from rawValue at line 167
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1641` "Nothing to fetch (e.g. iobChange only)" — iobChange qualifying event fetches nothing
  - `Sources/TandemCore/Messages/HistoryLog/BolusCompletedHistoryLog.swift:17` public let iob: Float — parsed but never read by the mapper
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:176` completedBolusEvent uses insulinRequested/insulinDelivered only; completion.iob ignored

- Recommendation: Poll the version-appropriate IOB request on sync (the suggested-handler table already names it for iobChange), store it in `latestInsulinOnBoard`, and log a warning when it differs from the host-reported IOB by more than the pump increment for several consecutive syncs.

**P21-4 Test coverage for timeline diffing** (Non-conforming, impact low, unverified)

HistoryTimestampReconcilerTests, HistoryLogStoreTests (missingRanges, prune), HistoryToDoseMapperTests and HistoryBackfillCoordinatorTests each test their component in isolation. No test drives `enactBolus`/`enactTempBasal` and a history fixture through the same manager and asserts the two timelines agree (grep finds no test file using both). No test computes IOB from emitted events or compares it to a pump-reported value. The word 'reconcile' in TandemPumpManagerBolusSyncTests refers to un-deferring the sync path, not to diffing against history.

- Evidence:
  - `Tests/TandemKitTests/HistoryBackfillCoordinatorTests.swift:507` "Nothing consumes the store yet, so this only fixes the contract"
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:133` synchronized { _pumpEvents += events } — records events, no comparison helper
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:32` pure mapper unit tests; mapper referenced by no other test file
  - `Tests/TandemKitTests/HistoryTimestampReconcilerTests.swift:13` clock-delta arithmetic only
  - `Tests/TandemKitTests/TandemPumpManagerBolusSyncTests.swift:44` testSyncReconcilesAfterGraceExpires asserts only shouldDeferBolusSync == false

- Recommendation: Add an integration test with StubPumpBluetooth that enacts a bolus and temp basal, streams the matching Bolus/TempRate Activated+Completed history logs, maps them, and asserts identity (syncIdentifier), amounts and IOB match the events recorded by MockPumpManagerDelegate.

**P21-5 Diagnostic tooling for manual diffing** (Partial, impact low, unverified)

A developer can open the debug History Log Viewer to read raw pump records and the state dump to see the live-path bookkeeping, so a manual diff against Loop's insulin history is possible on-device. Nothing automates it: no view or log line juxtaposes reported doses with history, `scripts/` contains only an xcodeproj membership check and a web-setup script, Package.swift declares no executable/CLI target, and the store is in-memory so nothing survives a relaunch for offline analysis.

- Evidence:
  - `Sources/TandemKitUI/ViewModels/Settings/TandemKitHistoryLogViewerViewModel.swift:84` logsBySequence / logsByType / logsDescending — raw records only
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:459` debugDescription lists lastReconciliation, latestInsulinOnBoard (always nil), historyBackfill bookkeeping
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:182` manager debugDescription is just the state dump
  - `Sources/TandemKit/PumpManager/History/HistoryLogStore.swift:30` "Dose reconciliation only ever looks back hours" — describes intended, not implemented, use

- Recommendation: Add a debug screen or exportable dump that lists, side by side, the last N emitted NewPumpEvents (kept in state or a ring buffer) and the mapped history doses for the same window, highlighting unmatched entries and the pump's IOB.

**P21-6 Documentation claims a reconciler that does not exist** (Non-conforming, impact low, unverified)

The plan document marks Phase 4 (matching pending doses to history within ±0.05 U / ±0.01 U/hr, flagging unreconciled doses after 24 h) and Phase 6 (delegate delivery of reconciled events) as done, and KEY_FILES_REFERENCE describes `HistoryReconciler` and `HistoryDeduplicator` as present. Neither file exists in `Sources/TandemKit/PumpManager/History/`, and CLAUDE.md says the coverage was dropped with the code. A reviewer reading the docs would conclude the timeline diff this point asks for is implemented; it is not.

- Evidence:
  - `docs/tandemkit-history-integration-plan.md:680` "Implemented Phase 4 pending dose reconciliation primitives (`PendingDose`, `HistoryReconciler`)"
  - `docs/tandemkit-history-integration-plan.md:708` "- [x] Create `HistoryReconciler.swift`"
  - `docs/KEY_FILES_REFERENCE.md:189` lists /Sources/TandemKit/PumpManager/History/HistoryReconciler.swift — file absent from the directory
  - `CLAUDE.md:539` contradicts the above: "nothing consumes the store's contents"

- Recommendation: Update tandemkit-history-integration-plan.md and KEY_FILES_REFERENCE.md to mark Phases 4/6 as removed/not implemented and point to the current HistoryBackfillCoordinator/HistoryLogStore design; keep CLAUDE.md as the source of truth.

Open questions raised by this point:

- Does the host app (Trio or Loop) provide its own pump-history-vs-DoseStore comparison tooling that the project intends to rely on instead of driver-side diffing? Nothing in the repo references one.
- What are the exact semantics of `BolusCompletedHistoryLog.iob` and of ControlIQIOBResponse/NonControlIQIOBResponse (IOB after the bolus? including basal?) — this determines whether either is a usable 'expected IOB' baseline for a diff.
- Is `LastBolusStatus.deliveredVolume` reliable immediately after CancelBolusRequest on Mobi? The 2 s `Thread.sleep` before the read (TandemPumpManager.swift ~636) suggests uncertainty; hardware confirmation would settle whether the live-path cross-check itself can be trusted.
- The guide (§11) frames this point as a testing recommendation; the project may consider hardware validation procedures (CLAUDE.md item 21, not yet written) the intended venue rather than driver code — the audit treated in-code/in-test tooling as the conformance bar.
### P22. NewPumpEvent/DoseEntry fields are populated with the documented semantics: type, startDate/endDate (TBR endDate = scheduled end while mutable), value+unit programmed, deliveredUnits actual, isMutable, wasProgrammedByPumpUI, automatic, manuallyEntered, insulinType, and syncIdentifier left to be derived from raw

Guide section: §2 data model.

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

The DoseEntry shape on TandemKit's live (optimistic) emission paths is mostly right: type, startDate, mutable TBR endDate = scheduled end, deliveredUnits nil while mutable, isMutable, insulinType and a raw-derived syncIdentifier all follow the guide. Four semantic gaps remain: (1) every finalized commanded bolus with activationType .manualNoRecommendation is stamped manuallyEntered = true, which LoopKit/Trio read as non-pump ("external") insulin; (2) cancelBolus finalizes with deliveredUnits = 0 when the LastBolusStatus read fails, and delivered volumes are floored to 0.05 U; (3) wasProgrammedByPumpUI is never true on any path that runs today (only the unwired, flag-gated HistoryToDoseMapper sets it, and only for boluses); (4) `automatic` is nil for all history-derived doses including Control-IQ auto-boluses, and TBR value/deliveredUnits derive from the host's schedule rather than the pump's profile.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P22-1 | Conforms | none | unverified | type / startDate / endDate / isMutable shape on optimistic paths |
| P22-2 | Non-conforming | medium | unverified | manuallyEntered mis-set on finalized commanded boluses |
| P22-3 | Partial | high | unverified | deliveredUnits actual: cancel-path zeroing and floor rounding |
| P22-4 | Non-conforming | medium | unverified | wasProgrammedByPumpUI never true on any live path |
| P22-5 | Partial | medium | unverified | automatic flag semantics across sources |
| P22-6 | Conforms | low | unverified | syncIdentifier derivation, NewPumpEvent date/type, Linux shim divergence |
| P22-7 | Conforms | none | unverified | insulinType propagation |
| P22-8 | Partial | medium | unverified | value (programmed) for temp basal and basal markers |

**P22-1 type / startDate / endDate / isMutable shape on optimistic paths** (Conforms, impact none, unverified)

On every live path traced (enactBolus, cancelBolus, enactTempBasal, suspend, resume, fetchBasalStatus, handleHomeScreenMirrorResponse, configureControlIQMode, getActivePumpEvents) doses are built through UnfinalizedDose.toDoseEntry. Bolus and temp basal use the correct unit (.units / .unitsPerHour), mutable entries have deliveredUnits nil and endDate = programmed end, finalized entries flip isMutable and carry a real endDate. Suspend/resume use LoopKit's dedicated initializers; .basal markers have endDate == startDate and no deliveredUnits, which is how LoopKit models scheduled-basal boundaries. The DoseEntry.bolus helper's mutable branch (Date.now + duration) is dead code — its sole caller (TandemDoseProgressReporter.getPumpEvent) always passes endDate. State persists UnfinalizedDose (rawValue) so shape survives relaunch.

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:149` bolus: `endDate = isMutable || useEstimatedEndDate ? estimatedEndDate : endDate` — mutable bolus carries estimated end
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:161` `deliveredUnits: isMutable ? nil : deliveredUnits` — Medtrum-style shape the guide endorses
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:177` tempBasal: `actualEndDate = isMutable ? estimatedEndDate : endDate` — mutable TBR endDate is the scheduled end
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:178` finalized TBR endDate clipped to estimatedEndDate; deliveredUnits = rate x elapsed hours (line 190)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` `toDoseEntry(isMutable: endDate == nil, endDate: endDate ?? Date.now)` — running TBR re-emitted mutable, finalized at the next dose's start

- Recommendation: No change needed for shape. Consider deleting the unreachable mutable branch of DoseEntry.bolus and the unused DoseEntry.tempBasal/basal/resume/suspend helpers so the only DoseEntry factory is UnfinalizedDose.toDoseEntry.

**P22-2 manuallyEntered mis-set on finalized commanded boluses** (Non-conforming, impact medium, unverified)

In LoopKit, manuallyEntered marks insulin the user logged that the pump did not deliver (pen/manual entry); Trio maps it to `isExternal` ("delivered outside Trio, e.g. pen injection", per Trio's data model). BolusActivationType.manualNoRecommendation is a normal pump-delivered bolus the user requested when no recommendation existed. TandemKit therefore finalizes such boluses flagged as external/manual insulin, and the flag also changes between the mutable and finalized report of the same dose. Steady-state Loop UIs and Trio's Nightscout upload will classify these as external insulin; whether any consumer excludes them from pump-delivery reconciliation depends on the host, so accounting drift is possible but not proven here. Trio normally passes .manualRecommendationAccepted, so the path is hit mostly under Loop or custom hosts.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/DoseEntry.swift:24` `manuallyEntered: activationType == .manualNoRecommendation,`
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:35` getPumpEvent builds the finalized bolus via `DoseEntry.bolus(...)` with the stored activationType
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:260` `events.append(progressReport.getPumpEvent(actualDeliveredUnits: actualDelivered))` — the only finalize path for a completed bolus
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:155` initial mutable bolus (enactBolus) omits manuallyEntered -> false; the flag flips to true at finalization
  - `reference: loopkit-trio/InsulinDeliveryStore.swift:253` LoopKit queries `manuallyEntered == YES` as the 'manually entered doses' set (non-pump insulin)

- Recommendation: Always pass `manuallyEntered: false` for pump-delivered doses (it is never true for anything TandemKit reports). Use `automatic: activationType.isAutomatic` alone to distinguish SMB/automatic from user boluses. Add a test asserting manuallyEntered == false for every activationType.

**P22-3 deliveredUnits actual: cancel-path zeroing and floor rounding** (Partial, impact high, unverified)

The guide requires deliveredUnits to be the pump's actual delivered amount at finalization. Natural completion does read LastBolusStatus (good) but falls back to the programmed total on read failure. cancelBolus is worse: if the LastBolusStatus read fails or returns a different bolusId (e.g. a Control-IQ or quick bolus started after the cancel on a UI-capable pump), the partially delivered bolus is finalized immutable with deliveredUnits = 0, so Loop drops all delivered insulin for it — IOB under-count, over-delivery risk. Separately, delivered volumes are floored to 0.05 U although the pump reports milliunits; HistoryToDoseMapper.swift:155-163 itself documents that flooring understates delivered IOB and uses round-to-nearest 0.001, so the two paths disagree.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` `bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:641` `let canceledDose = bolusDose.toDoseEntry(endDate: Date.now)` — immutable, so deliveredUnits 0 is final
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:527` `guard response.bolusId == bolusId else { ... return nil }` — mismatch or no response yields nil
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:532` `roundToSupportedBolusVolume(units: Double(response.deliveredVolume) / 1000.0)` — floors milliunit value to the 0.05 grid
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:226` `supportedBolusVolumes.last(where: { $0 <= units }) ?? 0` — floor, not nearest

- Recommendation: On cancel, if the LastBolusStatus read fails, keep the dose mutable (or fall back to the progress reporter's estimate) and retry on the next sync rather than finalizing at 0. Use round-to-nearest milliunit for deliveredUnits, matching HistoryToDoseMapper.roundToReportingResolution; reserve floor rounding for outgoing commands.

**P22-4 wasProgrammedByPumpUI never true on any live path** (Non-conforming, impact medium, unverified)

Tandem is UI-capable (t:slim X2 touchscreen, Mobi quick-bolus button, Control-IQ). The guide (§2, §7) requires wasProgrammedByPumpUI = true on doses that originated on the pump. Every path that emits today — including the two that exist specifically to pick up pump-side state changes (fetchBasalStatus, handleHomeScreenMirrorResponse) — leaves the flag false, because UnfinalizedDose.toDoseEntry cannot express it. The only code that sets it is HistoryToDoseMapper, which has no production caller and sits behind two default-off flags; even there, pump-set temp rates and pump-side suspend/resume are not flagged. Applies in steady state, after reconnect and after relaunch alike.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:152` suspend detected from CurrentBasalStatus: `UnfinalizedDose(suspendStartTime: now)` — default wasProgrammedByPumpUI false
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:486` home-screen-mirror suspend/basal doses likewise carry no wasProgrammedByPumpUI
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:146` toDoseEntry has no wasProgrammedByPumpUI parameter; every DoseEntry it builds uses the default false
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:194` `wasProgrammedByPumpUI: !isCommandedBolus(completion.bolusId)` — set for boluses only
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:252` temp-rate DoseEntry omits wasProgrammedByPumpUI (and suspend/resume at lines 98, 109)

- Recommendation: Add a `wasProgrammedByPumpUI` field to UnfinalizedDose (persisted in rawValue) and set it true for doses discovered from pump status rather than commanded. When HistoryToDoseMapper is wired, also flag temp rates (tempRateId not commanded) and suspend/resume records not matching an app-issued command.

**P22-5 automatic flag semantics across sources** (Partial, impact medium, unverified)

For doses the host commands, `automatic` is right: boluses take it from activationType, and temp basals are always loop-issued (enactTempBasal is blocked under Control-IQ and only Loop/Trio call it), so `true` is defensible. The gap is doses the pump originates. Control-IQ correction boluses and basal modulation are the guide's canonical 'automatic' case, yet the history mapper emits `automatic: nil` for every dose type, and the records it reads (BolusActivated/Completed) do not carry the source; BolusDeliveryHistoryLog.BolusSource / CurrentBolusStatus.bolusSource do. Trio reads `automatic` as isSMB, so once history reporting is wired, Control-IQ auto-boluses would be classified as manual. Today the mapper is unwired, so the practical effect is that these doses are not reported at all (outside this point).

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:33` commanded bolus: `automatic = activationType.isAutomatic` — correct
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:768` enactTempBasal: `automatic: true,` hardcoded
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:60` `automatic = false // OSAID does not use suspend function` — also applied to pump-detected suspends
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:184` completed-bolus DoseEntry passes no `automatic:` — nil for Control-IQ auto-boluses and user boluses alike
  - `Sources/TandemCore/Messages/Models/BolusDelivery.swift:6` `case controlIQAutoBolus = 7` — the pump does expose bolus source

- Recommendation: When wiring HistoryToDoseMapper, join BolusDeliveryHistoryLog (or LastBolusStatus bolusSource) by bolusId and set `automatic: source == .controlIQAutoBolus`, `false` for .gui/.quickBolus, and activationType.isAutomatic for .bluetoothRemoteBolus matched to a commanded bolus. Set `automatic: true` on Control-IQ-driven TBRs if they are ever reported.

**P22-6 syncIdentifier derivation, NewPumpEvent date/type, Linux shim divergence** (Conforms, impact low, unverified)

On Apple builds (the only production target) the guide's rule holds: the DoseEntry's syncIdentifier is whatever LoopKit derives from raw, because NewPumpEvent.init overwrites it. The mapper's explicit assignment is redundant but harmless — same bytes — and the file's header comment says so. Two low-grade caveats: the Linux shim's NewPumpEvent neither derives syncIdentifier nor falls back type to dose.type, so Linux-only tests cannot catch a raw/syncIdentifier divergence or a missing `type`; and the mapper stamps a completed bolus's event date with endDate while every other path uses startDate, so a dose's `date` moves when it finalizes (identity is unaffected since raw is stable). Titles and .replaceComponent/.rewind types for site/cartridge change are appropriate.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:7` optimistic events pass DoseEntry with syncIdentifier nil; LoopKit derives it from raw
  - `reference: loopkit-trio/NewPumpEvent.swift:33` `dose?.syncIdentifier = raw.hexadecimalString` — overwrites whatever the driver set
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:192` `syncIdentifier: raw.hexadecimalString,` — set manually but byte-identical to what LoopKit derives
  - `LinuxShims/LoopKit/LoopKit.swift:544` shim NewPumpEvent.init stores dose as-is: no syncIdentifier derivation, no type-from-dose fallback
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:196` completed bolus event `date: dose.endDate`, while in-flight (line 219) and optimistic events use startDate

- Recommendation: Drop the manual `syncIdentifier:` in HistoryToDoseMapper to match the guide, or keep it and add a test asserting it equals raw.hexadecimalString. Bring the shim's NewPumpEvent.init in line with LoopKit (derive syncIdentifier and type). Use startDate for the completed-bolus event date for consistency.

**P22-7 insulinType propagation** (Conforms, impact none, unverified)

state.insulinType is threaded into bolus, temp basal, basal and resume doses on every live path (enactBolus:583, enactTempBasal:769, basal fallbacks:732/1321/1718, resume:902), into the history mapper via its insulinType parameter, and into PumpManagerStatus so LoopKit's 'nil means pump insulin' fallback is consistent. Suspend doses carry nil, matching LoopKit's DoseEntry(suspendDate:) API. The type is captured on the UnfinalizedDose at command time and persisted, so a bolus finalized after relaunch keeps the type it was enacted with even if the user changes the setting meanwhile.

- Evidence:
  - `Sources/TandemKitUI/TandemUICoordinator.swift:172` `self.pumpManager.state.insulinType = type` — the only writer, from the settings UI
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:259` insulinType round-trips through rawValue, so it survives relaunch
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:139` `raw["insulinType"] = insulinType?.rawValue` — persisted per in-flight dose
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:130` `insulinType: state.insulinType,` on PumpManagerStatus, so nil-typed doses resolve to the pump's type
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:40` finalized bolus reuses `dose.insulinType` captured at enact time

- Recommendation: None required. Optionally warn in UI if state.insulinType is nil after onboarding, since a nil type falls back to the host's pump-level default.

**P22-8 value (programmed) for temp basal and basal markers** (Partial, impact medium, unverified)

The guide wants `value` to be the programmed amount. For boluses it is (units requested, milliunits on the wire). For temp basals, Tandem programs a percent of the pump's active profile rate; TandemKit reports value = host-schedule-rate x percent, so `value` and the derived `deliveredUnits` are correct only while the pump's profile equals the host's schedule and the segment does not change during the TBR (the rate is also looked up at Date.now, not startDate, which matters for re-emission and history mapping). The `.basal` marker's rate is floored to the 0.1 U/hr grid, so a 0.05 U/hr segment reports 0. There is no evidence the driver verifies pump-profile equality before enacting, so this is partial rather than conforming.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:685` `let baselineRate = getScheduledBasalRate()` — host's schedule, not the pump's active profile segment
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:722` `absoluteRate = roundToSupportedBasalRate(baselineRate * percent/100)` — what is reported as `value`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:749` pump is sent only `SetTempRateRequest(minutes:, percent:)`; actual U/hr is pump-profile x percent
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1759` getScheduledBasalRate evaluates the schedule at `Date.now`, not at the dose's startDate
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` finalized TBR `deliveredUnits: value * (duration / .hours(1))` inherits any error in value

- Recommendation: Read the pump's current profile segment rate (CurrentBasalStatusResponse / IDPSegment) and report value = pumpRate x percent/100; or reject enactTempBasal when the pump profile differs from the host schedule. Evaluate the schedule at the dose's startDate. Use round-to-nearest for the basal marker's rate.

Open questions raised by this point:

- §4 (identity), not P22: NewPumpEvent.bolus builds raw from the `units` argument, and the same bolus is emitted with programmed units at enact (TandemPumpManager.swift:599), delivered units at completion (TandemDoseProgressReporter.swift:44) and `deliveredUnits ?? 0` at cancel (TandemPumpManager.swift:652) — raw changes over the dose's life.
- §3, not P22: getActivePumpEvents (TandemPumpManager.swift:1702) returns only the running temp basal, so the mutable bolus emitted at enact is not re-reported on subsequent syncs; combined with enactBolus using replacePendingEvents: false and later syncs using true, its survival depends on DoseStore purge behaviour.
- §7, not P22: fetchBasalStatus (StateSync.swift:141-187) has no branch for activeBasalType == .tempBasal, so a temp rate set on the t:slim X2 screen is never turned into a dose on the optimistic path.
- fetchBolusStatus (StateSync.swift:233) recomputes estimatedEndDate as now + full duration on every poll; this reaches PumpManagerStatus.bolusState and shouldDeferBolusSync but not hasNewPumpEvents — worth confirming it is intentional.
- The claim that Trio maps DoseEntry.automatic -> isSMB and manuallyEntered -> isExternal is from Trio's PumpHistoryStorage as I know it and the Trio skill's data-model note; verify against the Trio revision the host builds.
- TandemFeatureFlags defaults were taken from CLAUDE.md ('both off by default') plus the grouping at TandemFeatureFlags.swift:36-37; confirm the default table if the flag state matters for the final report.
### P23. A dose that never happened or was canceled with zero delivery stops being sent (with replacePendingEvents:true) so LoopKit removes it, rather than being finalized as a 0 U immutable dose; and no live dose is dropped by silence

Guide section: §3 transitions: never happened / zero-delivery cancel.

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

TandemKit never retracts a dose. `cancelBolus` finalizes the bolus as an immutable 0 U dose (with a changed `raw`) when the pump reports zero or the LastBolusStatus query fails, conflating "unknown" with "nothing delivered". Natural completion (`fetchBolusStatus`, bolusId==0) does the opposite on query failure: it finalizes at the full programmed amount. After an app relaunch the persisted in-progress bolus is never re-reported, finalized or explicitly retracted — it is silently dropped by the next `replacePendingEvents:true` batch or lingers mutable. Only the pre-report rejection paths in `enactBolus`/`enactTempBasal` conform: state and events are written after the pump confirms, so a dose that never happened is never sent. No tests cover the cancel or finalization emissions.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P23-1 | Non-conforming | medium | unverified | cancelBolus finalizes as immutable 0 U instead of retracting |
| P23-2 | Non-conforming | high | unverified | cancelBolus treats a failed LastBolusStatus query as 0 U delivered |
| P23-3 | Conforms | none | unverified | enactBolus: pump rejection precedes the mutable report |
| P23-4 | Non-conforming | high | unverified | Completion path finalizes a never-run/pump-canceled bolus at full or 0 U |
| P23-5 | Non-conforming | high | unverified | App relaunch: persisted in-progress bolus dropped by silence |
| P23-6 | Conforms | none | unverified | Temp basal: never-happened and immediate-cancel paths |

**P23-1 cancelBolus finalizes as immutable 0 U instead of retracting** (Non-conforming, impact medium, unverified)

When a bolus is canceled with zero delivery, the guide says stop sending it so LoopKit removes it. TandemKit instead emits an immutable `.bolus` DoseEntry with `deliveredUnits = 0`, and because `units:` is the delivered amount the `raw` changes from "bolus <programmed> <start>" to "bolus 0.0 <start>". With `replacePendingEvents: true` the mutable row is purged and a new permanent 0 U bolus is inserted, advances `pumpEventQueryAfterDate`, and is offered to HealthKit. IOB is unaffected (Trio DoseEntry.netBasalUnits returns deliveredUnits = 0), so the impact is metadata/upstream noise plus the identity break, not miscounted insulin.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:641` let canceledDose = bolusDose.toDoseEntry(endDate: Date.now) — isMutable defaults to false
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:652` .bolus(dose: canceledDose, units: canceledDose.deliveredUnits ?? 0, ...) — raw built from delivered, not programmed, units
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:657` self.emitPumpEvents(events) — replacePendingEvents defaults to true (line 1733)
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:10` raw: "\(DoseType.bolus.rawValue) \(units) \(date)" — units are part of the identity

- Recommendation: In `cancelBolus`, when the pump reports 0 delivered, emit `getActivePumpEvents()` only (replacePendingEvents: true) so the mutable bolus is removed; when delivered > 0 finalize with the original programmed `units` in `raw` so the syncIdentifier stays constant.

**P23-2 cancelBolus treats a failed LastBolusStatus query as 0 U delivered** (Non-conforming, impact high, unverified)

The zero-delivery retraction rule only applies when the driver knows nothing was delivered. `cancelBolus` cannot distinguish that from a BLE timeout or a LastBolusStatus answer for a different bolus: both return nil and are coerced to 0. A bolus that the pump had already partly delivered (the CancelBolusRequest succeeded only because delivery was in progress) is then finalized as a permanent 0 U dose. Loop/Trio drops that insulin from IOB entirely and may re-dose it. Line 636 sleeps 2 s for the Mobi to log the bolus, which suggests the author knows the query can miss.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` `?? 0` — nil (no response / bolusId mismatch) becomes zero delivered
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:522` guard let response = bluetooth.write(request) ... else { return nil } — no response yields nil
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:527` guard response.bolusId == bolusId else { ... return nil } — mismatch also yields nil
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:161` deliveredUnits: isMutable ? nil : deliveredUnits — the 0 is written into the immutable entry
  - `reference: loopkit-trio/DoseEntry.swift:95` netBasalUnits for .bolus: deliveredUnits ?? programmedUnits — a 0 here removes the bolus from IOB

- Recommendation: Never coerce nil to 0. On query failure keep the dose mutable (re-report with the same raw) or finalize with the estimated delivered amount from the progress reporter, and retry the LastBolusStatus read on the next sync before finalizing.

**P23-3 enactBolus: pump rejection precedes the mutable report** (Conforms, impact none, unverified)

The guide's "never happened" transition requires that a dose the pump refused is not left in LoopKit. In `enactBolus` every rejection (connect failure, no BolusPermission response, permission denied, no InitiateBolus response, initiation not successful) returns before `state.bolusDose` is set and before the mutable NewPumpEvent is emitted, so there is nothing to retract. This holds in steady state, on first sync after pairing and after reconnect alike, because the ordering is within one synchronous command body.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:545` guard permissionResponse.isPermissionGranted else { ... completion(...); return } — no state/event written
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:571` guard initiateResponse.wasBolusInitiated else { releaseBolusPermission; completion; return }
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:594` self.state.bolusDose = dose — only after wasBolusInitiated
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:598` emitPumpEvents([...bolus mutable...], replacePendingEvents: false) — first report, after acceptance
  - `Sources/TandemCore/Messages/Control/InitiateBolus.swift:164` wasBolusInitiated: status == 0 && statusType == .success

- Recommendation: Keep this ordering; add a unit test with StubPumpBluetooth asserting that a rejected InitiateBolusRequest produces zero `hasNewPumpEvents` calls, so a future refactor cannot move the report ahead of the pump's confirmation.

**P23-4 Completion path finalizes a never-run/pump-canceled bolus at full or 0 U** (Non-conforming, impact high, unverified)

A bolus the user cancels on the t:slim X2 screen (or that the pump aborts after accepting InitiateBolus) reaches the same `bolusId == 0` branch as a normal completion. If LastBolusStatus reports 0 delivered, the dose is finalized as an immutable 0 U bolus instead of being retracted (same shape as P23-1). If the query fails or returns another bolus id, `getPumpEvent` assumes full delivery and finalizes at the programmed total — a dose that never happened is made permanent, over-counting IOB. In both cases `raw` changes, so identity matching is bypassed and only the `replacePendingEvents` purge prevents a duplicate.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:249` if response.bolusId == 0 { // Bolus is finished — reached for any non-delivering status incl. pump-side cancel
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:256` actualDelivered = queryLastBolusDeliveredVolume(bolusId: bolusId) — nil on failure/mismatch
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:260` events.append(progressReport.getPumpEvent(actualDeliveredUnits: actualDelivered))
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:33` let delivered = actualDeliveredUnits ?? total — nil becomes the full programmed amount
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:44` units: delivered — raw changes to the delivered amount, so identity differs from the mutable report

- Recommendation: In the bolusId==0 branch: if the pump reports 0 delivered, emit only `getActivePumpEvents()` to retract; if the query fails, keep the dose mutable (same raw) and retry next sync; never default to `total`. Build raw from programmed units in all reports.

**P23-5 App relaunch: persisted in-progress bolus dropped by silence** (Non-conforming, impact high, unverified)

The guide's corollary is that silence must only remove doses that truly did not happen. If the app is killed mid-bolus and relaunched, `bolusProgressReport` is gone while `state.bolusDose` survives. Once the 30 s grace passes, `fetchBolusStatus(fromSync:)` either clears `bolusDose` without emitting anything (status 0) or returns early (status delivering/requesting). The bolus that was actually delivered is never finalized: the next basal/temp-basal/suspend emission (all `replacePendingEvents: true`) purges the mutable row from DoseStore and InsulinDeliveryStore, so the delivered insulin vanishes from IOB. No code path rebuilds a reporter or re-reports the persisted dose on relaunch.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:70` internal var bolusProgressReport: TandemDoseProgressReporter? — in-memory only, nil after relaunch
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:244` bolusDose = UnfinalizedDose(rawValue: bolusDoseRaw) — the in-progress bolus IS persisted
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:217` if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil { state.bolusDose = nil ... return } — cleared with no emit
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:226` guard let progressReport = bolusProgressReport else { return } — any other status returns silently
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:598` initial mutable bolus was emitted with replacePendingEvents: false and is never re-sent

- Recommendation: On init, if `state.bolusDose` is non-nil, recreate the progress reporter (or a lightweight finalizer) from the persisted dose; in `fetchBolusStatus`, when `bolusProgressReport == nil` but `state.bolusDose != nil`, query LastBolusStatus and finalize with the pump's delivered volume instead of clearing state silently.

**P23-6 Temp basal: never-happened and immediate-cancel paths** (Conforms, impact none, unverified)

A temp basal the pump refuses (no CurrentBasalStatus response, StopTempRate failure, SetTempRate no-response or non-OK status) is never reported: `state.basalDose` and the mutable `.tempBasal` event are written only after the pump confirms, on every path traced (steady state, reconnect, relaunch — the body is synchronous). A TBR canceled by a zero-duration/100% enact, suspend, Control-IQ enable or a basal-status change is finalized via `getActivePumpEvents(endDate:)` with delivered units for the elapsed window rather than silently dropped. Only a cancel within the same instant would yield a ~0 U immutable temp basal instead of a retraction; its netBasalUnits is 0, so accounting is unaffected.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:756` guard response.isStatusOK else { ... completion(...); return } — returns before any dose/event is written
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:774` self.state.basalDose = dose — set only after SetTempRateResponse OK
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:736` var events = self.getActivePumpEvents(endDate: dose.startDate) — cancel path finalizes the running TBR, does not drop it
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` state.basalDose.toDoseEntry(isMutable: endDate == nil, endDate: endDate ?? Date.now)
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` deliveredUnits: isMutable ? nil : value * (duration / .hours(1)) — actual elapsed delivery, not 0

- Recommendation: No change needed for this point. Optionally retract (omit) a TBR finalized with an elapsed duration below one basal increment instead of emitting a ~0 U immutable entry.

Open questions raised by this point:

- Whether LoopKit's HKQuantitySample(type:unit:dose:...) initializer (LoopKit/Extensions/HKQuantitySample+InsulinKit.swift) returns nil for a 0 U dose is not determinable from the reference files provided; if it does not, the 0 U immutable boluses from P23-1/P23-4 become HealthKit samples.
- Adjacent to P23 but a finalization-accuracy issue: `enactTempBasal` (TandemPumpManager.swift:706-718) and `suspendDelivery` (:802-811) stop the running temp rate on the pump before a later step can fail; on failure `state.basalDose` still holds the TBR and it keeps being re-reported as running until its estimated end (over-count).
- `cancelBolus` completes with `.success(nil)` (TandemPumpManager.swift:659) rather than the canceled DoseEntry LoopKit's `PumpManagerResult<DoseEntry?>` contract expects; outside this point.
- Hardware behavior not verifiable from code: whether LastBolusStatus returns the canceled bolus's id with deliveredVolume 0 after a pump-side cancel, and whether the Mobi's 2 s write delay (line 636) is always sufficient — both decide which P23 branch a real cancel takes.
- No test exercises `cancelBolus` or the `fetchBolusStatus` bolusId==0 finalization emission (grep of Tests/TandemKitTests found no references to queryLastBolusDeliveredVolume, getPumpEvent or CurrentBolusStatusResponse).
- `handleHomeScreenMirrorResponse` (TandemPumpManager+StateSync.swift:473) emits basal/suspend events but has no caller in Sources/; dead code today.
- The history-backed emission layer (`HistoryToDoseMapper`, `historyDoseReporting` flag, default off) is not wired to any delegate call, so it cannot currently recover or retract any of the doses discussed here.
### P24. Event dates and ordering are chosen so DoseStore behaves predictably: pumpEventQueryAfterDate only advances on immutable events, the cache window purge does not eat backfilled history, and dedup by raw does not collide between the live path and the history path

Guide section: §8 DoseStore consequences.

Overall: **Partial** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 0 of 2 verifier passes completed

The live path alone behaves predictably in DoseStore: suspend/resume/basal are immutable and dated at emission, the only mutable rows are the in-flight bolus and the running temp basal, and a finalized batch always carries the still-running TBR so the cursor is only pulled back to a TBR start. The history path is not wired to any emission today (mapToEvents has no caller; historyBackfill/historyDoseReporting default off), so nothing collides yet, but the design is not collision-safe: live raws are type/units/ISO strings while history raws are HistoryLogSyncIdentifier bytes, and live bolus/TBR raws change on finalization. The planner's emitFloor and DoseStore's basal-sync window would both drop late-discovered pump-UI doses once emission exists.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P24-1 | Partial | high | unverified | Live-path vs history-path raw for the same bolus |
| P24-2 | Partial | medium | unverified | Live raw changes on finalization; update-vs-insert relies on mutable purge |
| P24-3 | Conforms | none | unverified | pumpEventQueryAfterDate cursor behaviour on the live path |
| P24-4 | Partial | high | unverified | emitFloor derived from host floor would drop late-discovered pump-UI doses |
| P24-5 | Partial | medium | unverified | Cache window purge vs backfill depth; IDS basal sync window |
| P24-6 | Conforms | low | unverified | Event date choice: completed bolus dated endDate, everything else startDate |

**P24-1 Live-path vs history-path raw for the same bolus** (Partial, impact high, unverified)

A Loop-commanded bolus reported live (raw = string) and later re-read from history (raw = 10-byte identifier) has two different raws, so DoseStore's unique-by-raw dedup would insert two PumpEvent rows and the InsulinDeliveryStore would hold two immutable doses: a double count. Nothing prevents this except that the history emission layer does not exist yet and both flags default off. HistoryLogSyncIdentifier's own doc (line 45) promises the live report will mint the same identity from bolusId at command time, but enactBolus/TandemDoseProgressReporter/cancelBolus still use the string raw, and the serial needed to mint it is only known after fetchPumpInformation.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:10` live bolus raw: "\(DoseType.bolus.rawValue) \(units) \(iso8601 date)"
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:183` history bolus raw = HistoryLogSyncIdentifier.bolus(pumpSerial:, bolusId:)
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:194` isCommandedBolus only sets wasProgrammedByPumpUI; it does not suppress or re-key the event
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:9` "Nothing is mapped to doses or emitted here" — no caller of mapToEvents exists in Sources/
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:173` historyDoseReporting = historyBackfill && historyDoseReporting; both default false, no consumer

- Recommendation: Before enabling historyDoseReporting, make the live bolus/TBR raw equal HistoryLogSyncIdentifier.bolus/.tempRate (serial + pump id) once the serial is known, or have the emission layer skip/re-key history events whose bolusId matches a live-reported dose. Add a test asserting live raw == history raw for the same bolusId.

**P24-2 Live raw changes on finalization; update-vs-insert relies on mutable purge** (Partial, impact medium, unverified)

For an interrupted/cancelled bolus and for every early-ended temp basal, the finalized event's raw differs from the mutable one. At the PumpEvent tier the old row disappears only because every finalizing emission uses replacePendingEvents: true (default); at the InsulinDeliveryStore tier the mutable dose is soft-deleted and a fresh immutable row inserted rather than updated. The end state is correct today (Medtrum-style safety net), but dedup by raw is not what keeps it correct, and any future finalizing emission with replacePendingEvents: false, or a history-path re-report, would duplicate. Only the initial enactBolus emission uses false (line 600), which is fine.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:44` finalized bolus: units: delivered (not programmed) feeds the raw string
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:652` cancelBolus: .bolus(dose:, units: canceledDose.deliveredUnits ?? 0, ...)
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:20` tempBasal raw uses dose.programmedUnits, i.e. rate x duration
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:177` finalized TBR endDate is the actual (earlier) end, so programmedUnits and raw change
  - `reference: loopkit-trio/DoseStore.swift:706` replacePendingEvents purges mutable == YES rows before inserting

- Recommendation: Key live bolus events on programmed units (or the pump bolusId) and TBR events on start date/rate rather than programmedUnits, so raw is byte-identical across mutable and finalized reports; keep replacePendingEvents: true on finalization.

**P24-3 pumpEventQueryAfterDate cursor behaviour on the live path** (Conforms, impact none, unverified)

The only long-lived mutable rows TandemKit creates are the running TBR and the in-flight bolus. A suspend is emitted immutable at its start, so an open suspend never holds the cursor back. When a finalized bolus is emitted while a TBR runs, the batch includes the mutable TBR and DoseStore pulls the cursor to the TBR start (at most the TBR duration ago) — LoopKit's intended behaviour. On relaunch, state.basalDose/bolusDose are persisted so the same rows are re-derived. Minor: DoseStore assigns (not maxes) the cursor, so a future backfill batch of older immutable events would move it backward; that only causes upstream re-query and is dedup-safe upstream.

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:196` suspend/resume/basal DoseEntries are built without isMutable (immutable)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` getActivePumpEvents: TBR is mutable only when endDate == nil
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:259` bolus completion batch = getActivePumpEvents() (mutable TBR) + finalized bolus
  - `reference: loopkit-trio/DoseStore.swift:747` cursor set to firstMutableDate if it precedes the newest final date, else to finalDate
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:141` fetchBasalStatus emits only on basal-type change (finalizes TBR with endDate: now)

- Recommendation: No change needed for the live path. When history emission is added, expect the cursor to move backward on backfill batches and confirm upstream consumers dedup by syncIdentifier.

**P24-4 emitFloor derived from host floor would drop late-discovered pump-UI doses** (Partial, impact high, unverified)

The planner's contract says history events dated before emitFloor will not be reported. The host floor marches to roughly now as live events are reported (Trio: lastEventDate-15min; in Loop, DeviceDataManager returns doseStore.pumpEventQueryAfterDate — from memory, verify). A quick-bolus or Control-IQ bolus on the pump discovered on the next 5-minute sync, after a live TBR/basal event was finalized, is older than that floor and would be filtered out — exactly the external dose the backfill exists to find, and under-counting IOB is the over-delivery direction. The premise that DoseStore discards such events is wrong for the Trio-fork DoseStore, which only purges older than 24h. Not yet exercised because no emission layer consumes TickOutcome.emitFloor.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillPlanner.swift:98` emitFloor = max(hostFloor, firstSeenFloor)
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillPlanner.swift:90` comment: "events below it are discarded on arrival" — DoseStore.addPumpEvents has no such filter
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:322` hostEventFloor = delegate.startDateToFilterNewPumpEvents(for:)
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:129` emitFloor computed each tick and handed out in TickOutcome for the emission layer
  - `CLAUDE.md:537` Trio returns lastEventDate - 15min as the host floor

- Recommendation: Do not use startDateToFilterNewPumpEvents as an emission floor for history-derived doses; floor only on firstSeenFloor (and DoseStore's 24h cache). Fix the planner doc comment and add a test that a pump-UI bolus older than hostFloor but within the lookback is still reported.

**P24-5 Cache window purge vs backfill depth; IDS basal sync window** (Partial, impact medium, unverified)

Backfilled events can be at most ~7h old, well inside DoseStore's 24h PumpEvent cache, so the cache purge cannot eat them; a re-paired same-serial pump keeps its old firstSeenFloor but the walk is still capped at 7h. However DoseStore only forwards non-bolus pump events to the InsulinDeliveryStore from the last immutable basal end date onward. Because TandemKit's live path continually emits immutable .basal/.suspend/.resume events dated now, any history-derived temp basal, suspend or resume that predates the newest live basal event would be stored as a PumpEvent but never reach the InsulinDeliveryStore/IOB. Only backfilled boluses are safe under this ordering. Not exercised today (no emission layer).

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillPlanner.swift:72` deepFetchLookback = 7 hours
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillPlanner.swift:76` deepFetchTarget = max(now - lookback, firstSeenFloor); never deeper than 7h
  - `reference: loopkit-trio/DoseStore.swift:196` cacheLength default 24 hours
  - `reference: loopkit-trio/DoseStore.swift:916` IDS sync starts at max(lastImmutableBasalEndDate, now-24h)
  - `reference: loopkit-trio/DoseStore.swift:1140` only boluses are saved when startDate < basalStart; non-bolus doses need startDate >= basalStart

- Recommendation: When wiring history emission, either restrict backfilled doses to boluses, or stop emitting synthetic live .basal events so history owns the basal timeline (MinimedKit pattern). Document the constraint in HistoryBackfillPlanner.

**P24-6 Event date choice: completed bolus dated endDate, everything else startDate** (Conforms, impact low, unverified)

At the DoseStore tier the date shift between the mutable and finalized report of the same raw is harmless: the mutable row is purged by replacePendingEvents before insert, the IDS match is by syncIdentifier, and dating a completed bolus at its end only advances the cursor to completion time. The inconsistency with the live path (startDate) is cosmetic in DoseStore. It becomes a hazard only if the emission layer applies emitFloor to event.date: a bolus could pass the floor as mutable and be dropped when finalized, leaving the mutable row purged and the dose lost — see P24-4.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:196` completed bolus: NewPumpEvent(date: dose.endDate, ...)
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:219` in-flight bolus (same raw): NewPumpEvent(date: dose.startDate, ...)
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:45` live finalized bolus dated dose.startDate
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:54` test pins event.date == completion time, so the choice is deliberate
  - `reference: loopkit-trio/DoseStore.swift:720` "There is no guarantee of event ordering" — DoseStore does not depend on batch order

- Recommendation: Prefer one convention (date = startDate) for all dose events, matching the live path and OmnipodKit/MinimedKit, and never filter finalizing events by a floor that the mutable report already passed.

Open questions raised by this point:

- HistoryLogStore.swift:39 states DoseStore "under Trio isn't used at all"; if Trio persists pump events in its own PumpHistoryStorage keyed by syncIdentifier, the §8 DoseStore consequences apply to Loop only and Trio's dedup/purge rules need a separate audit.
- Loop's DeviceDataManager.startDateToFilterNewPumpEvents is believed (from memory) to return doseStore.pumpEventQueryAfterDate; not on disk in the scratchpad — verify before acting on P24-4.
- The Core Data model (unique constraint on PumpEvent.raw and CachedInsulinDeliveryObject.syncIdentifier, merge policy) is not in the scratchpad; the guide's "unique constraint on raw" is taken on trust.
- HistoryLogSyncIdentifier.swift:45 says "Nothing emits these identifiers yet" while HistoryToDoseMapper does mint them (unwired); the comment is stale relative to the mapper but accurate for what reaches the delegate.
- docs/tandemkit-history-integration-plan.md describes a HistoryReconciler/PendingDose matching layer (±5 min, ±0.05 U) marked as completed; no such code exists at HEAD — the doc is stale.
## Method and limitations

Each of the 24 points was audited by a separate agent that read the guide, the relevant TandemKit sources, the two LoopKit
variants and the tests, and returned findings with file and line evidence. Every finding was then scheduled for review by two
independent reviewers with different briefs: one re-read the cited code and traced control flow, persistence and reconnect
behaviour; the other checked the claimed consequence against the LoopKit and Trio sources and against the pump message
definitions. Findings the reviewers judged wrong were to be dropped into a "refuted" list; findings they judged mis-rated were to
be amended. A completeness pass then looked for behaviour none of the 24 points had covered, and the Trio consumer was audited as
its own point.

The review stage did not complete as designed. An organisation usage cap interrupted the agent fleet twice. All 24 point audits
finished, but only a fraction of the independent review passes ran before the cap. The verification column in each findings
table records exactly which findings were independently reviewed. The high-impact findings were then re-verified in themed
batches with one reviewer per batch; their outcomes are reflected in the verification column and in the verifier notes. Findings
still marked unverified were produced by a single auditor and should be read as credible leads with file and line evidence, not
as confirmed defects. Several of them are corroborated by more than one point reaching the same conclusion from a different
direction, which the cross-cutting section calls out.

Other limits:

- Source-only. No pump hardware was used. Firmware behaviour that decides a verdict is listed under open questions.
- Line numbers refer to the audited commit and will drift.
- Loop's `DeviceDataManager` was not on disk; statements about Loop's host behaviour rely on the LoopKit sources and the guide.
  Trio's host code was on disk and was read directly.
- The guide itself describes `decisionId`, which exists only in `loopkitdev/LoopKit` `next-dev`; the LoopKit fork Trio pins does
  not have it, so P09 is scored as not applicable today with a forward-looking note.

Reference material used: the guide; `LoopKit/DeviceManager/PumpManager.swift`, `InsulinKit/DoseEntry.swift`,
`InsulinKit/NewPumpEvent.swift`, `InsulinKit/PumpEventType.swift`, `InsulinKit/DoseStore.swift`,
`InsulinKit/InsulinDeliveryStore.swift`, `InsulinKit/InsulinMath.swift` from both LoopKit variants; Trio's
`Trio/Sources/APS/DeviceDataManager.swift`, `Trio/Sources/APS/Storage/PumpHistoryStorage.swift` and
`Trio/Sources/APS/APSManager.swift`; and the TandemKit sources and tests under `Sources/` and `Tests/`.

