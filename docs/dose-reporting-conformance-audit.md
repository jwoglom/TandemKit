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

### Premise: a pump manager for a screenless pump

For this analysis TandemKit is treated as a pump manager used exclusively with a pump that has no screen, the Tandem Mobi, driven
from the Loop or Trio app on the phone. That places it in the guide's **Loop-only pump** archetype (the one OmnipodKit and
MedtrumKit follow) rather than the **UI-capable pump** archetype (MinimedKit). There is no pump screen on which the user can
bolus, set a temp rate, or suspend and resume, and Tandem's own phone app is assumed not to be in use because the pump is paired
to TandemKit. The consequences for the guide's rules are:

- `lastReconciliation` may legitimately be the last time TandemKit received status from the pump (§6, Loop-only archetype).
- `wasProgrammedByPumpUI` may be left false, and the guide's UI-capable items (§7, and the external-dose test in §11) are not
  applicable in the default configuration.
- Two residual pump-side dose sources remain and are treated as **conditional**, not as the default case: the Mobi's quick-bolus
  button, which TandemKit turns off on the pump on every sync unless the `quickBolusButtonSupport` feature flag (default off) is
  enabled; and Control-IQ automatic dosing, which applies only when Control-IQ is enabled on the pump, at which point TandemKit
  blocks its own dosing and the host disables closed loop. Findings whose impact rises under one of these sources say so.
- Pump-initiated delivery stops that need no screen remain fully in scope: occlusion, empty-cartridge and auto-off alarms,
  malfunctions, cartridge-change mode, resume-pump alarms, and a bolus the pump aborts for those reasons.
- Findings whose trigger is the app itself (relaunch, BLE loss, timeouts, cancellation, batch composition, identity keys) are
  unaffected by the premise.

The three points whose verdict is driven by the archetype (P02, P08, P20) were re-audited under this premise, and every other
finding that mentioned pump-screen doses was re-rated. The earlier UI-capable readings are kept for reference in the method
section, since the same code would face them if TandemKit were ever paired to a t:slim X2.

Points P01 to P10 are the guide's conformance checklist (§9). P11 to P14 are the four pitfalls in §10. P15 to P21 are the seven
testing recommendations in §11. P22 to P24 cover the data model (§2), the zero-delivery transition in §3, and the `DoseStore`
consequences in §8. G-points are gaps found outside that structure.

Verdict legend: **Conforms** means the requirement holds on every path traced. **Partial** means it holds on some paths, or only
behind a non-default feature flag, or with a concrete gap. **Non-conforming** means it is violated or not implemented. **Unsure**
means the code alone could not settle it. **Not applicable** means the requirement does not apply under the premise. A point's
overall verdict is the most conservative verdict among its findings, so one non-conforming finding makes the point
non-conforming even when most of its findings conform.

Verification legend: **verified** means a reviewer other than the point's auditor (a second agent, or the lead reviewer's
re-check described in the method section) re-read the cited code and confirmed the finding. **amended** means the reviewer
changed the verdict or impact; the auditor's original is shown next to it. Every finding in this report was reviewed one of these
two ways. Findings marked "added by a verifier" were raised during review rather than by the point's auditor.

Safety impact is about insulin accounting. **high** means Loop or Trio could count IOB wrong by a clinically meaningful amount, or
lose or duplicate a dose. **medium** means wrong metadata or timing that degrades accounting. **low** means cosmetic or upstream
only. Nothing in this report is medical advice; it is engineering review material for the maintainers.

## Summary table

| Point | Guide section | Requirement | Overall | Highest impact | Findings |
| --- | --- | --- | --- | --- | --- |
| P01 | §9 item 1 (with §1, §6, §8) | hasNewPumpEvents is called on every sync with the pump, even when there are no new doses, so... | Non-conforming | medium | 8 |
| P02 | §9 item 2 (with §6) | A current, correct lastReconciliation is always passed: for a Loop-only pump this is the last time... | Partial | medium | 7 |
| P03 | §9 item 3 (with §4) | Each dose has a raw/syncIdentifier that is byte-for-byte constant for the entire life of that dose,... | Non-conforming | medium | 7 |
| P04 | §9 item 4 (with §3 report-or-delete rule) | In-progress doses are reported with isMutable: true and re-reported on EVERY sync until they finalize;... | Non-conforming | high | 7 |
| P05 | §9 item 5 (with §3 finalization) | Finalized doses are reported with isMutable: false, a real endDate, and the actual deliveredUnits | Non-conforming | high | 7 |
| P06 | §9 item 6 (with §5) | replacePendingEvents is true when a batch is the complete current set of pending delivery and false only... | Non-conforming | high | 6 |
| P07 | §9 item 7 | value carries the programmed amount and deliveredUnits the actual amount, both rounded to the pump's... | Non-conforming | high | 8 |
| P08 | §9 item 8 (with §7) | wasProgrammedByPumpUI is set for user-initiated doses and they are reconciled from pump history... | Not applicable today (residual findings: Partial) | low | 6 |
| P09 | §9 item 9 | decisionId is threaded from enactBolus/enactTempBasal through to the DoseEntry | Not applicable today (residual findings: Partial) | medium | 4 |
| P10 | §9 item 10 | Suspend/resume, prime, alarm, and pump-replacement events are emitted with appropriate PumpEventType values | Non-conforming | medium | 8 |
| P11 | §10 pitfall: temp basal finalization and overwrite | A running temp basal keeps a stable syncIdentifier across every update, is finalized (not dropped) on... | Non-conforming | medium | 6 |
| P12 | §10 pitfall: bolus during BLE loss | A bolus is registered up front as a mutable dose before contact can be lost, its in-progress state is... | Non-conforming | high | 7 |
| P13 | §10 pitfall: suspend / resume events | Suspend and resume are modeled as real dose events with correct timing: a suspend is emitted whenever... | Non-conforming | medium | 7 |
| P14 | §10 pitfall: faults, alarms, pump replacement | Pump faults are surfaced as NewPumpEvent with type .alarm / alarmType, and .replaceComponent is emitted on... | Non-conforming | low | 6 |
| P15 | §11 testing: interrupt everything | Tests cover BLE loss mid-bolus and mid-temp-basal, verifying the dose is recovered and finalized with the... | Non-conforming | high | 6 |
| P16 | §11 testing: cancel everything | Tests cancel a bolus and a temp basal at various points and verify the finalized dose shows the partial... | Non-conforming | medium | 5 |
| P17 | §11 testing: idempotency | Tests re-report the same in-progress dose many times and confirm it stays a single dose with identical raw... | Non-conforming | medium | 6 |
| P18 | §11 testing: empty syncs | Tests confirm a sync with no new doses still calls hasNewPumpEvents and advances lastReconciliation | Non-conforming | medium | 9 |
| P19 | §11 testing: rounding | Tests verify value and deliveredUnits are rounded to the pump's supported increment | Non-conforming | low | 7 |
| P20 | §11 testing: external doses (UI pumps) | Tests bolus on the pump directly and confirm Loop picks it up from history with wasProgrammedByPumpUI =... | Not applicable today (residual findings: Partial) | low | 7 |
| P21 | §11 testing: timeline diff vs pump history | Reported dose timeline is diffed against the pump's own delivery history and expected IOB, so small... | Non-conforming | high | 6 |
| P22 | §2 data model | NewPumpEvent/DoseEntry fields are populated with the documented semantics: type, startDate/endDate (TBR... | Non-conforming | high | 8 |
| P23 | §3 transitions: never happened / zero-delivery cancel | A dose that never happened or was canceled with zero delivery stops being sent (with... | Non-conforming | high | 6 |
| P24 | §8 DoseStore consequences | Event dates and ordering are chosen so DoseStore behaves predictably: pumpEventQueryAfterDate only... | Partial | low | 6 |
| G01 | host consumer (outside the guide) | How Trio actually consumes TandemKit's events: with lastReconciliation and replacePendingEvents ignored... | Non-conforming | high | 8 |
| G02 | §3 mutable lifecycle, §10 'bolus during BLE loss' analog (register before you can lose contact; pump is source of truth), §9 item 4/5 | Temp-basal command ordering: the running rate is stopped on the pump before the new one is confirmed; a... | Non-conforming | medium | 1 |
| G03 | §2 value = programmed amount, §9 item 7, §6 trust boundary | Pump clock vs phone clock and percent-of-profile semantics: the reported TBR value/deliveredUnits and... | Partial | medium | 1 |
| G04 | §6 trust boundary, §10 suspend/resume ('emit a suspend whenever delivery actually stops') | A basal-state transition observed while no delegate is attached (the pairing sync, or notifications... | Non-conforming | medium | 1 |
| G05 | §3 finalization with actual deliveredUnits, §10 'pump is the source of truth' | Mobi message selection for the delivered-volume read: queryLastBolusDeliveredVolume always sends... | Unsure | medium | 1 |
| G06 | §3 report-or-delete, §10 suspend on teardown, §9 item 10 | Deleting the pump manager (prepareForDeactivation) leaves a running mutable temp basal and any in-progress... | Partial | low | 1 |
| G07 | §3 finalization, §7 pump-initiated delivery changes | Control-IQ when enabled (conditional): a pump-reported Control-IQ flip in fetchControlIQStatus sets... | Not applicable | none | 1 |

## Findings that need action first

Many points reached the same defect from different directions. This list names each underlying defect once, with the finding ids
that describe it, the single most important code location, the host it affects (Loop's `DoseStore`, Trio's `PumpHistoryStorage`,
or both), and the fix the findings recommend. Ratings are for the screenless-pump premise in the default configuration. Details and
full evidence are in the per-point sections.

### High impact

1. **A bolus in flight across an app relaunch is never finalized.** (P04-2, P05-4, P12-3, P23-5, G01-6; also P15-5) Both hosts.
   `state.bolusDose` is persisted but the object that builds the finalizing event, `bolusProgressReport`, lives only in memory
   (`Sources/TandemKit/PumpManager/TandemPumpManager.swift:70`) and is never rebuilt from the persisted dose. After relaunch,
   `fetchBolusStatus` either clears the persisted dose silently or returns early (`TandemPumpManager+StateSync.swift:217-226`),
   so no finalized event is emitted. In Loop the mutable bolus emitted at enact time is purged by the next
   `replacePendingEvents: true` batch and the insulin vanishes from IOB. In Trio the bolus stays frozen at its programmed amount,
   which over-counts IOB whenever the pump aborted it (occlusion, empty cartridge, auto-off). The reviewers confirmed the code
   facts and corrected the per-host consequence. Fix: rebuild the finalizer from the persisted dose on init; when a persisted
   `bolusDose` exists without a reporter, query `LastBolusStatus` for that bolus id and finalize with the pump's delivered
   volume, at the original start date, before clearing state.

2. **A lost InitiateBolus acknowledgement leaves a possibly-running bolus untracked in both hosts.** (P12-1) Verified.
   The write helper returns nil both when the request never left the phone and when the pump received it and the response was
   lost after the 30 s timeout (`TandemPumpManager.swift:564`, `TandemPeripheralManager.swift:215`). `enactBolus` then releases
   permission, returns a communication error and records nothing; `deliveryIsUncertain` is hard-coded false. If the pump did
   start the bolus, neither host has any IOB for it and the loop may retry. Fix: on a nil response keep the bolus id and units in
   `state.bolusDose`, emit the mutable dose, flag delivery as uncertain, and confirm or retract from `CurrentBolusStatus` /
   `LastBolusStatus` on the next contact.

3. **Unknown delivery is finalized as a guess: cancel assumes zero, completion assumes everything.**
   (P05-2, P07-1, P22-3, P23-2, G01-2 high; P23-4, P05-1, P07-3, P21-2, P23-1 medium) Both hosts. Verified.
   `cancelBolus` coerces a failed or mismatched `LastBolusStatus` read to `deliveredUnits = 0` and finalizes immutably
   (`TandemPumpManager.swift:639-641`); the completion path falls back to the full programmed amount
   (`TandemDoseProgressReporter.swift:33`). Under the premise a mismatch no longer comes from a touchscreen bolus, but a BLE
   timeout and the Mobi's storage lag after a cancel (the code sleeps 2 s and hopes) still produce nil reads. In Trio the effect
   is worse than in Loop: Trio updates a stored bolus only downward, so the 0 U report overwrites the programmed amount and the
   insulin the pump did push before the cancel disappears from oref's IOB. Fix: never finalize on a guess. Keep the dose mutable
   with the same `raw` and retry the read on the next sync, or finalize from `BolusCompletedHistoryLog` for that bolus id. Retract
   rather than finalize at 0 U when the pump confirms nothing was delivered.

4. **Ending a temp basal without a replacement never truncates Trio's stored temp basal, and this happens on every neutral
   temp.** (G01-4; related P11-2, P23-6) Trio only. Amended upward by the reviewer.
   `enactTempBasal` treats `percent == 100` the same as a cancel (`TandemPumpManager.swift:725`): it stops the running temp rate
   and emits the old temp basal finalized with `deliveredUnits` set plus a `.basal` dose, and no new temp basal. That is correct
   for Loop, but Trio skips any temp basal event that carries `deliveredUnits` and ignores `.basal`, so its stored temp basal keeps
   its full programmed duration and oref counts the old rate for the remaining minutes. Because oref returns a neutral temp at the
   profile rate every few cycles by default, this is routine, not exceptional. The same happens on a pump-side stop and on
   Control-IQ enable. Fix: when ending a temp basal without a replacement, also emit a truncating `.tempBasal` event at the cancel
   time with `deliveredUnits == nil` (zero duration or the scheduled rate), which is the shape Trio stores for other drivers; or
   agree a Trio-side change to honour `deliveredUnits`-bearing temp basal events as truncations.

5. **The running bolus is never re-reported and is purged by any complete batch emitted while it runs.** (P04-1, P06-1, P13-7, P04-4, P12-6) Loop only. Verified.
   `getActivePumpEvents` (`TandemPumpManager.swift:1703`) returns only the temp basal, so every `replacePendingEvents: true`
   batch built while a bolus is delivering (a temp basal expiring during `fetchBasalStatus`, a suspend, a Control-IQ toggle, a
   temp basal once the time-based guard releases, a resume) omits the bolus and Loop's `DoseStore` deletes it. In steady state
   it reappears when the bolus completes, so IOB dips for minutes; combined with item 1 it disappears for good. Trio ignores
   `replacePendingEvents`, so it is unaffected. Fix: make the complete-batch builder return the mutable bolus with the same `raw`
   and any live temp basal, and use it in every `true` batch including resume.

### Medium impact

6. **A resume the app did not record is reported as a `.basal` dose, never as `.resume`.** (P10-2, P13-3, G01-3) Both hosts.
   Amended from high to medium: on a screenless pump every normal resume goes through `sendResumePumping`, which emits `.resume`
   correctly. The residual trigger is app-side: a `ResumePumpingRequest` whose response is lost after the pump resumed
   (`TandemPumpManager.swift:895`) leaves state at suspend, and the next `fetchBasalStatus` emits a scheduled-basal dose
   (`TandemPumpManager+StateSync.swift:166-173`). When it fires the consequence is large: LoopKit's `InsulinMath.reconciled()`
   closes an open suspend only on a `.resume` or `.tempBasal`, and Trio ignores `.basal` and treats a trailing `PumpSuspend` as
   suspended until now, zeroing basal IOB while it keeps dosing. Fix: emit a `.resume` event whenever the recorded state is suspend
   and the pump reports basal or temp basal, and handle the lost-response case in `sendResumePumping`.

7. **`hasNewPumpEvents` is not called on a quiet sync, and events emitted before the delegate attaches are dropped.**
   (P01-1, P18-2, P18-A1, P01-A1; P01-3, P18-5) Loop only. Verified.
   `syncPumpData` stamps the driver's own boundary but never calls the delegate unless a basal type changed or a bolus finished
   (`TandemPumpManager.swift:445-457`). Loop's `DoseStore` boundary therefore lags to the last dose transition, a freshly paired
   pump never seeds it, and reservoir arbitration flip-flops between syncs (P02-3). Events emitted during the pairing-time sync,
   before the host adopts the manager, are logged and discarded. Under the Loop-only premise the stamp itself is the right value
   (P02-1, P02-2, P02-4, P02-6 conform); the gap is that it never reaches the host. Fix: emit the complete pending set, or an
   empty batch, at the end of every successful sync, and queue pre-delegate events for replay alongside the existing reservoir
   flush.

8. **Pump-initiated stops are dated at detection, not at the stop.** (P02-5, P13-4, P11-4) Both hosts. Verified.
   Occlusion, empty-cartridge, auto-off and malfunction stops are learned only when `CurrentBasalStatus` reports suspend on the
   next sync (up to about five minutes, longer after a BLE outage) or on a `.pumpSuspend` qualifying event; an `.alarm` or
   `.malfunction` event alone triggers no basal read. The suspend dose is dated `now` (`TandemPumpManager+StateSync.swift:152`),
   so basal between the real stop and detection is credited as delivered. The pump-timestamped `PumpingSuspendedHistoryLog` is
   mapped by the history code but never emitted. Fix: fetch basal status on alarm and malfunction events, and date the suspend
   from the alarm or the history entry rather than the poll.

9. **Delivered volume is floored to a 0.05 U grid.** (P07-2, P22-3, P05-5, P19-2) Both hosts. Verified.
   The pump reports milliunits and delivers partial boluses; `roundToSupportedBolusVolume` floors, while the history mapper rounds
   to 0.001 U, so the two paths disagree and partial deliveries are systematically understated.

10. **Temp basal `value` and `deliveredUnits` come from the app's schedule, not from the pump.** (P07-4, P11-6, P05-6, P22-8) Both hosts.
    The reported rate is the app's scheduled basal times the percent it requested; `CurrentBasalStatusResponse.profileBasalRate`
    fetched in the same command is not used, and `deliveredUnits` is programmed rate times elapsed time. The premise shrinks the
    profile-divergence risk (only TandemKit writes the pump profile), leaving segment-boundary drift within a temp basal.

11. **Percent rounding can push the reported rate above Trio's `maxBasal` filter.** (G01-5) Trio only. Verified.
    `percentForTempBasal` rounds to the nearest percent (`TandemPumpManager.swift:284`) and the dose is built from the resulting
    absolute rate; when oref requests exactly `maxBasal` on a profile basal of 2 U/h or more the reported rate can exceed it by
    0.01 U/h and Trio silently drops the temp basal record. Fix: clamp the reported rate to the requested rate.

12. **`manuallyEntered` is set for a normal pump-delivered bolus.** (P22-2, P09-3) Both hosts. Verified.
    `DoseEntry.bolus` sets it when the activation type is `manualNoRecommendation`
    (`Sources/TandemCore/Common/Extensions/DoseEntry.swift:24`). LoopKit and Trio use that flag for insulin the pump did not
    deliver, and it flips between the mutable and finalized report of the same dose.

13. **The resume batch omits a live temp basal and overwrites it without finalizing.** (P04-4, P06-4) Loop only.
    `sendResumePumping` emits only the resume event (`TandemPumpManager.swift:904-906`). The trigger under the premise is a
    pump-initiated stop during a BLE outage followed by a resume from the fill-tubing flow, which checks the pump rather than state.

14. **Bolus `endDate` is detection time, not the pump's completion time.** (P05-3) Both hosts. Verified. Affects the shape of the
    insulin curve for boluses whose completion is noticed a sync late.

15. **The temp basal command is a two-step write whose first step is irreversible, with no self-healing.** (G02) Both hosts.
    Raised by the completeness pass. `enactTempBasal` stops the running temp rate on the pump (`TandemPumpManager.swift:706`)
    before the new one is confirmed. If `SetTempRate` then fails or its response is lost, the driver's record is not updated
    (`TandemPumpManager.swift:750-774`): either the pump is on profile basal while the old temp basal stays mutable in Loop until
    its scheduled end, or the pump runs the new rate while the driver still reports the old one, and `fetchBasalStatus` has no
    `.tempBasal` branch to notice. `suspendDelivery` has the same shape. Exposure is bounded by the next loop cycle unless BLE
    is lost right after the failure. Fix: on a failed or unanswered second step, re-read `CurrentBasalStatus` and `TempRate`
    and reconcile the record to what the pump reports before returning.

16. **The delivered-volume read may be sending the wrong message on the Mobi.** (G05) Both hosts. Unsure, raised by the
    completeness pass. `queryLastBolusDeliveredVolume` always sends `LastBolusStatusV2Request`; the Mobi-only
    `LastBolusStatusV3Request` exists in the message catalog but has no sender, and its response type does not conform to the
    abstract response the finalization path casts to (`LastBolusRequestBuilder.swift:5`, `LastBolusStatusV3.swift:12,58`). Under
    the premise the Mobi is the only target, so if Mobi firmware 3.5 and later does not answer the V2 request, every bolus
    completion finalizes at the programmed amount and every cancel at 0 U, turning item 3 from a failure path into the normal
    path. This needs a hardware capture before anything else on this list is prioritized.

17. **A basal transition observed while no delegate is attached is consumed into state and never re-emitted.** (G04, with P01-3, P18-5) Both hosts.
    `fetchBasalStatus` emits only on a type change and updates `state.basalDose` in the same step
    (`TandemPumpManager+StateSync.swift:141-158`), while `emitPumpEvents` drops the batch when no delegate is attached
    (`TandemPumpManager.swift:1736`). A pump that is suspended when TandemKit first syncs it, before the host adopts the manager,
    is therefore recorded as suspended by the driver but never reported, and every later sync stays silent. The reservoir path
    has a pending-flag replay; pump events do not. Fix: queue events emitted without a delegate and flush them from
    `deliverStateMissedByTheDelegate`.

18. **Temp basal amounts assume the phone's clock and schedule segment.** (G03, with P07-4, P11-6) Both hosts.
    Tandem applies the requested percent to the pump's own current profile segment on the pump's clock, while the reported
    `value` and `deliveredUnits` use the phone's schedule at phone time (`TandemPumpManager.swift:685,1756`). A segment boundary
    inside a 30-minute temp basal, or a pump clock that differs from the phone after a time-zone or DST change, makes the
    delivered amount differ from the reported one. Clock drift is surfaced in settings but never corrected automatically or
    reported through `didAdjustPumpClockBy`, and pairing does not set the pump time.

### Latent today, high once the history emission layer exists

19. **Dose identity changes over a dose's life, and the live and history identities for the same bolus differ.**
    (P03-1, P03-2, P03-3, P11-1, P16-4, P17-2, P24-2 low; P24-1, P03-6, P08-6 low today) Both hosts.
    The bolus `raw` embeds `units` (programmed at enact, delivered at completion or cancel) and the temp basal `raw` embeds
    `programmedUnits`, which shrinks whenever a temp basal ends early (`Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:10,20`).
    Reviewers lowered these to low because every finalizing batch uses `replacePendingEvents: true`, so Loop's purge produces the
    right end state and Trio never reads `raw`. The history mapper mints a different identity (`HistoryLogSyncIdentifier`) for the
    same bolus and dates completed boluses at `endDate` rather than `startDate`, so switching on history emission today would
    double-count every app-commanded bolus in both hosts (P24-1). Fix before wiring emission: key live doses on the pump's bolus id
    or temp rate id via `HistoryLogSyncIdentifier`, and never change the key on cancel or completion.

20. **The planned emission floor would drop late-discovered doses.** (P24-4) Low today. `HistoryBackfillPlanner.emitFloor` uses
    the host's `startDateToFilterNewPumpEvents`, and its comment that older events "are discarded on arrival" describes neither
    host. It matters only under the conditional sources.

### Conditional: quick-bolus flag on, or Control-IQ on

Under either conditional source TandemKit reverts to the UI-capable archetype and the following become high-impact non-conformances
(P02-7, P08-2, P08-3, P20-3, P20-4, P22-4, P22-5): a bolus the app did not start is ignored by `fetchBolusStatus`
(`TandemPumpManager+StateSync.swift:226`), a pump-set or Control-IQ temp rate produces no dose, `bolusSource` on the status and
history messages is never read (P20-5), `wasProgrammedByPumpUI` cannot be expressed by `UnfinalizedDose`, and `lastReconciliation`
keeps advancing past doses that were never seen. The history path that would recover them has no production caller and both
history flags default off (P08-1, P20-2). Keep both flags off until the emission layer, a stable identity, and a foreign-bolus
handler in `fetchBolusStatus` exist. One narrow default-configuration residual remains: the quick-bolus lockout needs a
successful `PumpGlobals` read in the same sync and does not cover the window between pairing and the first sync (P20-1). The
completeness pass added one more conditional gap: when the pump itself reports Control-IQ enabled, `fetchControlIQStatus` flips
the dosing guard but does not finalize the running Loop temp basal, unlike the app-side enable path, which does (G07).

### Low impact, listed for completeness

Deleting the pump manager tears down the transport without finalizing a running temp basal or an in-flight bolus, so in Loop
those mutable rows can never be finalized or persisted (G06). No `.prime` event is emitted for tubing or cannula fills (P10-5, P14-4). Alarms are never emitted as pump events on a live path
and `alarmType` is never populated (P14-1, P14-2, P10-6). No `.replaceComponent(.pump)` is emitted when a different pump is
paired (P14-5). The basal, suspend and resume `raw` strings have one-second resolution and no discriminator (P03-5). The Linux
shim cannot express `alarmType` and does not couple `raw` to `syncIdentifier` (P14-6, P03-7, P22-6). No IOB comparison against
the pump exists (P21-3). The cartridge-change `.rewind` and site-change `.replaceComponent(.infusionSet)` events were re-rated as
conforming under the premise, since the wizards are the only change paths and Trio consumes both types (P10-3, P10-4, P14-3, G01-7).

## Cross-cutting observations

**What conforms.** The shapes are right where the code is reached. App-commanded boluses are emitted mutable at enact time with
`replacePendingEvents: false` and finalized immutable with a pump-reported delivered volume on the normal completion path
(P05-1, P07-8, P22-1). App-commanded suspend and resume carry the right types (P10-1, P13-1, P13-2). Replacing or cancelling a
running temp basal finalizes the old one rather than overwriting it (P11-2), the temp basal record survives BLE reconnect and
app relaunch (P11-3), and a mutable temp basal re-report has a stable identity when it runs to its scheduled end (P03-4). Site
and cartridge changes are emitted with `replacePendingEvents: false` and with types Trio consumes (P06-3, P10-3, P10-4, P14-3,
G01-7). Failed, unanswered and throttled syncs correctly leave `lastReconciliation` alone (P01-2, P02-4), and under the Loop-only
premise the status-poll and command-acknowledgement stamps are the guide's recommended value (P02-1, P02-2, P02-6). The
quick-bolus lockout that makes the premise hold is itself unit-tested (P20-1). In Trio, the three bolus emissions collapse onto one
stored row and the downward correction on partial delivery works (G01-1). The history-log path is designed to the guide's rules,
with pump-assigned identifiers and pump timestamps (P03-6, P05-7), but none of it is reachable.

**What the premise changed.** Fixing the analysis to a screenless pump moved P02 from non-conforming to partial, P08 and P20 to
not applicable by default, and lowered the impact of every finding whose trigger was a user acting on a pump screen: the
pump-side resume (P10-2, P13-3, G01-3) from high to medium, identity instability (P03-1, P03-3, P16-4, P17-2) from medium to
low, the wasProgrammedByPumpUI and automatic-flag findings (P22-4, P22-5) to not applicable, and the history-reconciliation
diagnostics (P21-1, P21-3, P24-1, P24-4, P24-5) to low. It did not change anything whose trigger is the app itself: the
relaunch loss, the lost acknowledgement, the purge of the running bolus, the guessed finalization values, the quiet-sync gap and
the pump-initiated stop timing keep their ratings. One rating went up: the reviewer of G01-4 found that Trio's stored temp basal is
never truncated on every neutral temp, not only on explicit cancels.

**Two consumers, two sets of semantics.** The guide describes Loop's `DoseStore`. TandemKit ships in Trio, whose
`DeviceDataManager` ignores both `lastReconciliation` and `replacePendingEvents`, and whose `PumpHistoryStorage` keys events by
`(event.date, type)` rather than by `raw`, updates a duplicate bolus only if the new amount is smaller, skips any temp basal event
that carries `deliveredUnits`, and ignores `.basal` events. Several findings therefore have different consequences per host. The
relaunch loss (item 1) is a lost dose in Loop but a frozen programmed amount in Trio. The quiet-sync and `lastReconciliation`
findings (item 7, P02-3) affect Loop only. The purge of the running bolus (item 5) affects Loop only. The cancel-to-zero fallback
(item 3) is worse in Trio, where the 0 U overwrites the stored amount. The temp basal truncation gap (item 4) and the `maxBasal`
filter drop (item 11) exist only in Trio. G01 audits the Trio side directly and its findings were independently reviewed.

**Feature flags.** Everything history-related sits behind `historyBackfill` and `historyDoseReporting`, both default off
(`Sources/TandemKit/State/TandemFeatureFlags.swift`). Even with both on, the coordinator only fills the session store and
persists a watermark; there is no emission layer, so the flags change nothing about what Loop or Trio receive today. The
`quickBolusButtonSupport` and `controlIQSupport` flags, also default off, are what keep the premise true; enabling either
reintroduces pump-originated doses that no live path reports. `CLAUDE.md` describes the history layer accurately.
`docs/tandemkit-history-integration-plan.md` sketches the emission layer with a `replacePendingEvents: true` batch; as drawn it
would need to include the live bolus and temp basal or it would purge them (P06 open question), and its progress notes claim a
delegate-delivery path that does not exist at this commit (P20-7).

**Dependence on the LoopKit variant.** `decisionId` exists only in `loopkitdev/LoopKit` `next-dev`. The fork Trio pins has no
such field and neither does the Linux shim, so P09 is not applicable today. When TandemKit adopts a LoopKit with `decisionId`, the
enact signatures change and the id needs to be carried on `UnfinalizedDose` and persisted, alongside the bolus id that already is
(P09-2). The shim also lacks `alarmType` on `NewPumpEvent` and does not derive `syncIdentifier` from `raw`, so Linux tests cannot
observe two of the behaviours the guide depends on (P03-7, P14-6, P22-6).

**What the completeness pass added.** The critic confirmed that every `emitPumpEvents` call site (nine in
`TandemPumpManager.swift`, four in `TandemPumpManager+StateSync.swift`) is cited by at least one point, so no emission path went
unexamined. It found six behaviours no point had settled, recorded as G02 to G07: the two-step temp basal command with no
self-healing (G02), pump clock and segment-boundary effects on temp basal amounts (G03), basal transitions consumed while no
delegate is attached (G04), the unresolved question of whether the Mobi answers the V2 last-bolus message the finalization path
depends on (G05), deactivation without finalization (G06), and the pump-reported Control-IQ flip (G07). It also independently
re-derived two of the Trio-consumer findings, which corroborates G01-2 and G01-4 (it rated the truncation gap lower because the
root cause is Trio's dedup design; the G01 reviewer rated it high because the driver's percent-100-as-cancel choice makes it recur
on every neutral temp). Two scenarios it checked and found not applicable: Basal-IQ is not a Mobi feature, and extended boluses
cannot be requested through `enactBolus`, which always sends a standard bolus.

**Contradictions and near-contradictions between points.** The auditors did not contradict each other on facts, but they
weighted the same facts differently, and the premise resolved most of it. The critic listed five rating disagreements. Pump-side
stops dated at detection time (P02-5, P13-4, P11-4) now agree at partial and medium after a mis-applied review decision on P02-5
was reverted. Aborted boluses are "accounted for" in P08-4 and "finalized on a guess when the read fails" in P23-4; both are true,
of the normal path and the failure path respectively. The running temp basal not being re-reported is rated medium by P04-3, not
applicable by P17-3 and passed over by P11-3; P04's reading is the one that matters for Loop. Command-path `lastReconciliation`
stamps are partial and low in P01-A2 but conform under the premise in P02-2, which was re-audited; read P01-A2 as superseded. The
bolus `raw` changing on cancel was low in the reviewed findings (P03-1, P16-4) and medium in the then-unreviewed ones (P12-6,
P24-2, P03-6, P06-2); the lead re-check lowered P24-2, P03-6 and P06-2 to low to match, and kept P12-6 at medium because it also
covers the running-bolus purge. P23-1 rates finalizing a truly zero-delivery cancel as
0 U immutable at medium because IOB is unaffected, while P23-2 rates the same line high because the 0 U also swallows a failed
read; both are right about different inputs to the same line, and in Trio the 0 U is the only downward update that ever reaches
the stored bolus (G01-1, P23-4). P17-3 scores "the driver never re-reports an in-progress dose" as not applicable to a test point,
while P04-1 scores the same fact as a high non-conformance; P04's reading is the one that matters for Loop. P09 scored
`decisionId` as not applicable while also flagging the `activationType` surrogate as lossy (P09-3), and P22-2 treats the same
`manuallyEntered` mapping as a defect; the two are consistent once P09-3 is read as forward-looking.

**Dead and unreachable code that would matter if reached.** `handleHomeScreenMirrorResponse` emits the correct suspend to
resume transition but has no callers; the reviewer noted that its `NewPumpEvent.basal` wrapper is cosmetic, since LoopKit derives
the event type from the dose (P10-2, P06-4). `HistoryToDoseMapper` is correct in shape and untested in situ, and its
`isCommandedBolus` predicate has no production source (P08-5, P20-5). Deciding whether these are to be wired or removed changes
where several fixes belong.

**Open questions that need hardware or firmware knowledge.** Whether the pump raises a `.pumpSuspend` qualifying event, not only
`.alarm` or `.malfunction`, when an occlusion, empty cartridge or auto-off stops delivery; how often `LastBolusStatus` returns a
mismatched bolus id or nothing right after a cancel on Mobi firmware; whether `SuspendPumping` cancels a running bolus and how
`CurrentBolusStatus` then reports it; whether `LastBolusStatus.timestamp` is start or completion time; whether a quick bolus or
Control-IQ bolus appears in `CurrentBolusStatus` with its `bolusSource`; whether `SetTempRateRequest`, marked Mobi-only in the
message registry, is the right message for every target; whether `LastBolusStatusV3` is required on newer Mobi firmware; and
whether the Mobi permits Tandem's own app to stay paired alongside TandemKit, which the premise assumes it does not. Each is
listed under the point that raised it.

## Suggested test additions

Six of the seven testing recommendations in §11 of the guide are unmet (P15 to P19, P21); the seventh, the external-dose test
(P20), is not applicable by default under the premise and becomes required only if the quick-bolus flag or Control-IQ is enabled.
The common blocker is the test double: `Tests/TandemKitTests/MockPumpManagerDelegate.swift` records the events passed to
`hasNewPumpEvents` but discards `lastReconciliation` and `replacePendingEvents`, does not count calls, and no test reads the
events it records (P06-6, P15-4, P16-3, P17-1, P18-4, P20-6). The existing `StubPumpBluetooth` can drop or substitute responses
but cannot model a disconnect and reconnect (P15-3). In order:

1. **Extend the mock delegate** to record, per call, the events, `lastReconciliation` and `replacePendingEvents`, and to expose
   a call count. Every item below depends on this.
2. **Empty sync.** Drive `syncPumpData` with a stub that answers every status request with unchanged values and assert that
   `hasNewPumpEvents` is called with an empty (or complete-pending) batch and a `lastReconciliation` later than before; assert it
   is not called when the pump answers nothing (P18, P01).
3. **Relaunch mid-bolus.** Construct a manager from the `rawValue` of a state that holds an in-progress `bolusDose`, run a
   sync with a stubbed `LastBolusStatus`, and assert a finalized event with the same `raw` and start date reaches the delegate
   (P12, P15, P23, G01-6).
4. **Lost InitiateBolus acknowledgement.** Swallow the `InitiateBolusResponse` and assert the bolus is registered as mutable
   and marked uncertain, then confirmed or retracted on the next status read (P12).
5. **Failed delivery read.** Cancel and complete a bolus with the `LastBolusStatus` response omitted, and with a response
   carrying a different bolus id, and assert the dose stays mutable rather than finalizing at 0 U or at the programmed total
   (P05, P07, P23, G01-2).
6. **Complete batches.** With a bolus in progress, trigger a temp basal expiry, a suspend and a resume, and assert every
   `replacePendingEvents: true` batch contains the mutable bolus and any live temp basal (P04, P06, P13).
7. **Bolus lifecycle identity.** Enact a bolus, complete it with a stubbed `LastBolusStatus` that reports less than the
   programmed amount, and assert the `raw` bytes of the mutable and finalized events are identical, `isMutable` flips, and
   `deliveredUnits` equals the stubbed pump volume rounded to 0.001 U. Repeat for cancel at several delivered amounts (P16, P17,
   P03, P07).
8. **Temp basal lifecycle, including neutral temps.** Enact, then replace early, cancel with duration 0, request the profile
   rate (percent 100), and let one expire; assert stable `raw`, correct `endDate`, `deliveredUnits`, and that every early end emits
   a record Trio would store as a truncation (P11, P16, P19, G01-4).
9. **Rate clamp.** Request exactly `maxBasal` on profile rates of 2 U/h and above and assert the reported `unitsPerHour` never
   exceeds the request (G01-5).
10. **Pump-side transitions.** Stub `CurrentBasalStatus` through basal to suspend to basal and assert a `.suspend` then a
    `.resume` event; stub an `.alarm` qualifying event and assert a basal status read follows; stub a lost `ResumePumpingResponse`
    and assert the next sync emits `.resume` (P10, P13, P02-5).
11. **Conditional sources.** Stub an unanswered `PumpGlobalsRequest` and assert no quick-bolus disable is sent and that the next
    good read does send it (P20-1). Stub `ControlIQInfo` with `closedLoopEnabled: true` and assert `useControlIQ` flips and a
    subsequent automatic bolus is refused (P20-4). Stub `CurrentBolusStatus` as delivering a bolus id the app never issued and
    assert the current behaviour explicitly as a guard; when the flags are offered to users, change the assertion to a reported
    dose with `wasProgrammedByPumpUI` true (P20-3, P08-2).
12. **Rounding.** Unit-test `roundToSupportedBolusVolume`, `roundToSupportedBasalRate`, `TandemPumpCapabilities.supportedBasalRates`
    and `TandemDoseProgressReporter` against the pump's increments, and the milliunit conversions in the bolus and temp rate
    messages (P19).
13. **Timeline diff.** Once history emission exists, add an integration test that replays a recorded history log against the
    live-path events for the same period and asserts no dose is missing or duplicated (P21).

## Per-point detail

Points P01 to P24 follow the guide. G-points are gaps found by the completeness pass and by reading the host app.

### P01. hasNewPumpEvents is called on every sync with the pump, even when there are no new doses, so lastReconciliation advances

Guide section: §9 item 1 (with §1, §6, §8).

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 8 of 8 findings independently reviewed

TandemKit does not call hasNewPumpEvents on every sync. syncPumpData (the body behind ensureCurrentPumpData) stamps state.lastReconciliation = Date.now after a responsive pump and returns it via lastSync/completion, but never calls emitPumpEvents itself and there is no hasNewPumpEvents(events: []) anywhere in Sources. The delegate is reached only when fetchBasalStatus sees a basal-type transition or fetchBolusStatus sees a bolus finish, so in steady state the host's DoseStore lastPumpEventsReconciliation lags to the last dose transition while the driver's own lastSync advances. After fresh pairing the first sync typically emits nothing (nil stays nil), pre-delegate emissions are dropped without replay, and a BLE reconnect triggers no sync. Failed/unanswered syncs correctly leave the boundary alone.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P01-1 | Non-conforming | medium | verified | syncPumpData never reports to DoseStore on a no-change sync |
| P01-2 | Conforms | none | verified | Failed, unanswered, throttled or stood-down syncs |
| P01-3 | Non-conforming | medium | verified | First sync after pairing: nil boundary and pre-delegate drops |
| P01-4 | Partial | low | verified | BLE auto-reconnect does not sync or report |
| P01-5 | Partial | low | verified | Throttle keyed on a timestamp that command paths also stamp |
| P01-6 | Non-conforming | none | verified | No test covers delegate calls during a sync |
| P01-A1 | Partial | low | verified | Qualifying-event fetches stamp lastReconciliation with no delegate call |
| P01-A2 | Partial | low | amended | Host boundary advances via enact path only while Loop is enacting; not under Control-IQ |

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
  - [review:confirm] Literally verified: syncPumpData stamps at 445 and produces only pumpManagerDidUpdateState/didUpdate plus completion; hasNewPumpEvents is reachable only via emitPumpEvents (1742), and both sync-path emitters are gated on a transition (StateSync 141, 268). Trigger is the app's own sync, so the premise does not change it. Trio discards lastReconciliation and has no DoseStore, so the effect is Loop-only: DoseStore's boundary lags at the last emit, the save range is cut there (968), and the reservoir branch (1217) then replaces post-boundary pump events with whole-unit reservoir doses in the lag window. Medium holds.

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
  - [review:confirm] Verified: rawValue init leaves lastReconciliation nil (199); the default basalDose is a basalRate dose (UnfinalizedDose 221-223) so a pump in normal basal at pairing yields no transition at 141; onPairSuccess runs syncPumpData before the host adopts the manager (ScanViewModel 91); emitPumpEvents drops with a warning when the delegate is nil (1735-1737); deliverStateMissedByTheDelegate replays state and reservoir only (303-308). A fresh Mobi stopped at pairing is a pump-side state, not a screen action, so a suspend emitted in that window is lost. Loop-only effect (DoseStore 968 returns [] while nil); Trio unaffected. Medium holds.

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
  - [review:confirm] Code fact holds: both auto-reconnect closures only log, peripheral setup ends with isConnected=true and finishSetup(nil), no syncPumpData or trigger(kind:.history) exists, docs line 38 is stale. Trigger is app-side (BLE loss), which the premise leaves unaffected. The pump-side temp-rate sub-point is not_applicable under the premise, but pump-initiated stops during an outage (occlusion, cartridge change) still surface only at the next throttled poll. partial/low stands.

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

**P01-A1 Qualifying-event fetches stamp lastReconciliation with no delegate call** (Partial, impact low, verified, added by a verifier)

Beyond the command paths in P01-5, unsolicited qualifying events also move the driver boundary without telling the host. `.remainingInsulin`, `.pumpSuspend` and `.pumpResume` all map to `.reservoirStatus`, so `fetchReservoirStatus` stamps `lastReconciliation` on the pump's schedule (e.g. a low-cartridge event) with no `hasNewPumpEvents` call, and the stamp then arms the 4.5-minute short-circuit in `ensureCurrentPumpData`. `handleQualifyingEvents` itself never emits or stamps; it relies on the individual fetches, of which only `fetchBasalStatus` (on a type change) and `fetchBolusStatus` (on completion) emit. The pumpSuspend/pumpResume addition of `.basalStatus` matches CLAUDE.md and does emit the suspend/resume when the type actually changed.

- Evidence:
  - `Sources/TandemCore/Messages/QualifyingEvent/QualifyingEvent.swift:178` case .remainingInsulin: return [InsulinStatusRequest()]
  - `Sources/TandemKit/PumpManager/QualifyingEventFetch.swift:50` case is InsulinStatusRequest: -> .reservoirStatus
  - `Sources/TandemKit/PumpManager/QualifyingEventFetch.swift:78` if !events.isDisjoint(with: [.pumpSuspend, .pumpResume]) { needed.insert(.basalStatus) }
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1659` for fetch in fetches { self.runFetch(fetch) }; completion() — no stamp, no emit of its own
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:410` fetchReservoirStatus stamps lastReconciliation

- Recommendation: Treat qualifying-event handling like a sync: after the fetches run successfully, emit with the current lastReconciliation (or stop stamping from fetchReservoirStatus), so pump-initiated reads cannot advance the driver boundary silently or suppress the next poll.

- Verifier notes:
  - [review:confirm] Code fact holds: .remainingInsulin maps to InsulinStatusRequest -> .reservoirStatus, fetchReservoirStatus stamps lastReconciliation, handleQualifyingEvents neither stamps nor emits. Trigger is pump-initiated (e.g. low-cartridge event), not a screen action, so it is in scope. Under the Loop-only clause the stamp itself is a legitimate status-receipt boundary; the residual defect is only the missing delegate call plus arming the 4.5-min short-circuit, so partial/low is right.

**P01-A2 Host boundary advances via enact path only while Loop is enacting; not under Control-IQ** (Partial, impact low, amended, added by a verifier)

Both branches of `enactTempBasal` stamp and emit, so in ordinary closed-loop operation the host's `lastPumpEventsReconciliation` does advance roughly once per cycle as a side effect of Loop's own dosing, which bounds the practical exposure of P01-1. That bound disappears exactly where it matters most: with `useControlIQ` true, `enactTempBasal` is refused outright and automatic boluses are refused, so no enact path runs and the pump is delivering autonomous corrections and basal modulation on its own. In that mode the host boundary moves only on suspend/resume, bolus completion or a Control-IQ toggle, while the driver's own `lastSync` advances every ~5 minutes. The same holds in open loop and on cycles where Loop decides no new temp basal is needed.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:673` guard !state.useControlIQ else { — enactTempBasal refused under Control-IQ
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:517` if state.useControlIQ, activationType.isAutomatic { — automatic boluses refused
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:740` lastReconciliation = Date.now then emitPumpEvents on the cancel/100% branch
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:775` lastReconciliation = dose.startDate then emitPumpEvents on the set-temp branch

- Recommendation: When implementing the every-sync emission, verify it specifically in a Control-IQ configuration (useControlIQ true) where no enact path runs, since that is the operating mode with no incidental boundary advance today.

- Verifier notes:
  - [review:amend] Code fact holds (Control-IQ guards at 517/673; both enactTempBasal branches stamp and emit). The medium rating rested entirely on Control-IQ mode, which the premise makes a conditional source, not the default. In the default configuration (Control-IQ off) the pump is Loop-only: no external doses can hide behind a lagging host boundary, the driver's own doses are emitted on enact, and Trio's consumer ignores lastReconciliation anyway. Remaining exposure is the open-loop/no-change-cycle lag from P01-1, so low. Under the Control-IQ conditional source the original medium would apply.

Open questions raised by this point:

- How Trio's DeviceDataManager consumes lastReconciliation is not on disk: Trio stores pump events in its own PumpHistoryStorage rather than LoopKit's DoseStore, so the practical effect of the missing per-sync call in Trio (versus Loop) needs confirmation from Trio's source before the safety impact of P01-1 is finalized.
- Loop is believed to seed DoseStore.lastPumpEventsReconciliation from pumpManager.lastSync at startup (DoseStore.init takes it as a parameter at loopkit-trio/DoseStore.swift:203); if so, a relaunch would import the driver's status-ping timestamp as the trust boundary. Verify against the host app.
- §6 archetype: lastReconciliation is stamped after status reads only. History reading exists behind the historyBackfill flag (default false, TandemFeatureFlags.swift:32-39) and even when on emits nothing (HistoryBackfillCoordinator.swift:9-10; CLAUDE.md:541). Whether the status-sync timestamp is an acceptable lastReconciliation for a UI-capable pump belongs to P02.
- fetchBasalStatus (StateSync.swift:151-186) handles only .suspend and .basal transitions; a pump-side temp rate (.tempBasal from the t:slim X2 UI) is neither emitted nor stamped. That is an external-dose gap for P07/P08 rather than this point.
- handleHomeScreenMirrorResponse (StateSync.swift:473-514) emits without stamping lastReconciliation, but QualifyingEventFetch never issues HomeScreenMirrorRequest, so this path appears dead; confirm no other caller exists.
### P02. A current, correct lastReconciliation is always passed: for a Loop-only pump this is the last time telemetry/status was received from the pump; it must never be advanced past delivery that has not actually been accounted for

Guide section: §9 item 2 (with §6).

Overall: **Partial** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 7 of 7 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

Re-audited under the screenless-pump premise; the UI-capable reading is summarised in the method section.

Under the screenless-Mobi (Loop-only) premise, TandemKit's lastReconciliation is a "last time the pump answered" stamp: it is set after every status sync that received at least one response, after every accepted command, and after every reservoir read, is guarded against no-response syncs and failed connects, and is persisted across relaunch — which is exactly the OmnipodKit/MedtrumKit rule, so the archetype mismatch, the unseen-external-dose pitfall and the command-path stamps that made the UI-capable reading nonconforming/high become not_applicable or conform here (they revert to nonconforming only if the quickBolusButtonSupport flag is turned on or Control-IQ is enabled, because nothing derives the boundary from pump history). Two residual issues keep the point at partial: the value only reaches DoseStore alongside a dose emit, so on Loop the reservoir-vs-events arbitration flip-flops between syncs with a whole-unit reservoir reading, and pump-initiated stops (occlusion/auto-off/cartridge alarms) are stamped at detection time with the suspend dose dated to detection, so the boundary is advanced across a window in which basal was counted but not delivered.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P02-1 | Conforms | none | verified | Archetype: status-poll timestamp under the Loop-only premise |
| P02-2 | Conforms | none | verified | Command-path stamps after a single accepted command |
| P02-3 | Partial | medium | verified | Reservoir stamp and DoseStore reservoir arbitration |
| P02-4 | Conforms | none | verified | No-response guard, failed sync, relaunch persistence |
| P02-5 | Partial | medium | verified | Pump-initiated stops stamped at detection time |
| P02-6 | Conforms | none | verified | lastReconciliation doubles as lastSync, poll gate and staleness gate |
| P02-7 | Not applicable | none | verified | Conditional sources: quick-bolus flag on or Control-IQ on |

**P02-1 Archetype: status-poll timestamp under the Loop-only premise** (Conforms, impact none, verified)

The guide's §6 Loop-only rule is 'the last time you received telemetry/status from the pump' (OmnipodKit validTime, MedtrumKit lastSync). Line 445 stamps Date.now only after a sync in which the pump answered at least one status request, and that value is what every hasNewPumpEvents call carries. With the quick-bolus button forced off on every sync (line 362, flag default off) and Control-IQ off, there is no pump-side dose source the status poll could miss, so advancing the boundary to the poll time does not out-run unaccounted delivery. The previous audit's P02-1 (archetype mismatch) is therefore not_applicable under the premise; it re-applies only under the conditional sources (see P02-7).

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:445` syncPumpData: `self.state.lastReconciliation = Date.now` after the status reads answered
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:444` `if self.bluetooth.responseCount > responsesBefore` gates the stamp
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1743` emitPumpEvents passes `lastReconciliation: self.state.lastReconciliation`
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:362` enforceQuickBolusDisabled: `guard !state.featureFlags.quickBolusButtonSupport, state.quickBolusEnabled == true`
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:38` controlIQSupport/quickBolusButtonSupport/historyBackfill/historyDoseReporting all `return false`

- Recommendation: Keep the stamp semantics as-is for the default configuration; document in code that lastReconciliation is a Loop-only 'last contact' value and is only valid while quick bolus is disabled and Control-IQ is off.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P02-2 Command-path stamps after a single accepted command** (Conforms, impact none, verified)

Each of these stamps follows a pump response (a command acknowledgement or a status read), so under the Loop-only rule it is a genuine 'status received' instant, not a fabricated one. The only delivery in flight at these moments is the app's own dose, which the same code path registers as a mutable NewPumpEvent (596 with replacePendingEvents:false; 655/775/825/907 with the active set), so the boundary never moves past delivery the driver has not registered. The previous P02-5 (command paths are not history reconciles) is not_applicable under the premise. The cancelBolus path reads the pump's actual delivered volume before stamping, which is the right order.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:596` enactBolus: `self.state.lastReconciliation = Date.now` after InitiateBolus accepted, before delivery
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:775` enactTempBasal: `self.state.lastReconciliation = dose.startDate` (= Date.now captured moments earlier)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:655` cancelBolus stamps Date.now after LastBolusStatus read; likewise 740, 825, 907, 1328
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:265` fetchBolusStatus finished: stamps Date.now after CurrentBolusStatus/LastBolusStatus

- Recommendation: No change required for the default configuration. If lastReconciliation is later split from lastSync (P02-6), keep command paths updating the contact time.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P02-3 Reservoir stamp and DoseStore reservoir arbitration** (Partial, impact medium, verified)

Stamping after a reservoir-only qualifying fetch is acceptable under the Loop-only rule (a status was received), and the previous P02-4 concern that it silences a reservoir fallback needed to reveal pump-UI doses is not_applicable. The residual problem is that the stamp only reaches DoseStore when a dose is emitted (1733), while didReadReservoirValue reaches it on every sync. On quiet syncs DoseStore therefore sees a reservoir reading newer than lastPumpEventsReconciliation and switches to reservoir-derived doses (1217) at 1 U resolution; the next emit carries a later Date.now and switches back. On Loop, IOB between emits alternates between event-based and coarse reservoir-based estimates. On Trio, which ignores the value, there is no effect.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:410` fetchReservoirStatus: `state.lastReconciliation = timestamp` equals the reservoir value's startDate
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1688` runFetch `.reservoirStatus: fetchReservoirStatus()` — a qualifying-event read with no delivery read
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:434` quiet sync: fetchReservoirStatus() runs, but no emitPumpEvents follows unless basal/bolus state changed
  - `reference: loopkit-trio/DoseStore.swift:1217` reservoir doses used only if `reservoirEndDate > self.lastPumpEventsReconciliation`
  - `Sources/TandemCore/Messages/CurrentStatus/InsulinStatus.swift:39` `public var currentInsulinAmount: Int` — whole-unit reservoir resolution

- Recommendation: Call hasNewPumpEvents (with the current active events and the fresh stamp) on every sync, as P01 requires, so lastPumpEventsReconciliation always postdates the reservoir reading; alternatively record the reservoir reading with a timestamp not later than the reported reconciliation.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: 410 stamps the reservoir timestamp; DoseStore learns lastPumpEventsReconciliation only through addPumpEvents (fork DoseStore.swift:680) and TandemKit calls it only on dose transitions, so the reservoir reading is newer than the stored boundary between transitions and the 1217 branch can fire. Loop-only.

**P02-4 No-response guard, failed sync, relaunch persistence** (Conforms, impact none, verified)

The driver never fabricates contact: a sync on a link that answers nothing leaves the value alone, a failed connect and the 180 s watchdog (401) both hand back the previous value rather than nil or now, and the value survives relaunch so the first post-relaunch emit carries the genuinely old date. A single answered request is enough to advance the stamp (test at 170), which is the correct Loop-only semantics since any pump response is telemetry. The previous P02-7 survives the premise unchanged.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:444` stamp gated on `responseCount > responsesBefore`; else 'leaving lastSync where it was'
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:409` connect failure: `completion(self.state.lastReconciliation)` returns the previous value
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:196` lastReconciliation decoded from rawValue (encoded at 365)
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:78` asserts 'A failed sync must not advance lastReconciliation'
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:170` testSyncAdvancesLastSyncOnASingleResponse: one answered request advances the stamp

- Recommendation: Retain the responseCount guard, previous-value-on-failure and persistence; add a test that a sync during which the pump reports an unexpected bolusId does not advance the boundary if the conditional sources are ever enabled.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P02-5 Pump-initiated stops stamped at detection time** (Partial, impact medium, verified)

Occlusion, empty-cartridge, auto-off and malfunction stops need no screen and are in scope. TandemKit learns of them only when CurrentBasalStatus reports `.suspend`, which happens on the next sync (up to ~5 min) or on a `.pumpSuspend` qualifying event; an `.alarm`/`.malfunction` event alone triggers no basal read. The suspend dose is then dated `now` and lastReconciliation stamped, so basal between the actual stop and detection is trusted as delivered. Whether the pump raises `.pumpSuspend` for alarm-driven stops is unverified. Impact is bounded to one sync interval of basal (IOB over-counted, so Loop under-delivers); the previous audit did not cover this.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:152` fetchBasalStatus: `UnfinalizedDose(suspendStartTime: now)` — suspend dated at the poll, not the stop
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:159` then `state.lastReconciliation = Date.now`
  - `Sources/TandemKit/PumpManager/QualifyingEventFetch.swift:36` alarm/malfunction requests map only to `.notifications`, not `.basalStatus`
  - `Sources/TandemKit/PumpManager/QualifyingEventFetch.swift:80` basalStatus added only for `.pumpSuspend`/`.pumpResume` events
  - `Sources/TandemCore/Messages/QualifyingEvent/QualifyingEvent.swift:125` `.alarm` handlers: AlarmStatus, HighestAam, ActiveAamBits — no basal read

- Recommendation: Add `.basalStatus` to the fetches for `.alarm` and `.malfunction` events, and when a stop is detected without a matching `.pumpSuspend`, take the suspend start from the alarm's timestamp (or the PumpingSuspended history entry) rather than the poll time; verify on hardware which events accompany an occlusion.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: suspend dated at the poll (152) and stamped (159); QualifyingEventFetch maps AlarmStatus/MalfunctionStatus requests to .notifications only (36-43) while pumpSuspend/pumpResume add .basalStatus (80-81).

**P02-6 lastReconciliation doubles as lastSync, poll gate and staleness gate** (Conforms, impact none, verified)

Under the UI-capable reading this coupling was a design obstacle (prior P02-6, partial). Under the Loop-only premise all four consumers want the same quantity — last successful contact — so the coupling is coherent and the prior finding downgrades to conforms. The stamp while a bolus is running or a temp basal is live but not re-reported is likewise legitimate here: status was received, the app's own mutable doses remain registered in Loop because quiet syncs do not call the delegate with replacePendingEvents:true, and their re-reporting cadence is P04's concern, not the boundary's meaning.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:234` `public var lastSync: Date? { state.lastReconciliation }`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:360` ensureCurrentPumpData short-circuits when `timeIntervalSince(lastSync) < .minutes(4.5)`
  - `Sources/TandemKit/PumpManager/PumpConnectionIssue.swift:46` `return .noRecentSync` when lastReconciliation is older than the stale threshold
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:202` sync skips the bolus read while a bolus runs (`shouldDeferBolusSync`) yet still stamps at 445

- Recommendation: If the conditional sources are ever supported, split a history-derived lastReconciliation from lastSync so the 4.5-minute and 15-minute gates keep working; until then no change.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P02-7 Conditional sources: quick-bolus flag on or Control-IQ on** (Not applicable, impact none, verified)

Not applicable in the default configuration. If quickBolusButtonSupport is enabled (the button is then not forced off) or Control-IQ is on, the pump delivers doses the status poll cannot see (226, 141) while every sync still stamps Date.now, and no code path ties the boundary to a history read (367, 455; both history flags default off, CLAUDE.md 541). The previous P02-1, P02-2 and P02-3 then all survive verbatim as nonconforming/high: Loop would trust delivery it never saw and under-count IOB by the whole external dose. The verdict for this point flips from partial to nonconforming under either conditional source.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:226` fetchBolusStatus: `guard let progressReport = bolusProgressReport else { return }` — a pump-started bolus is never emitted
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:141` fetchBasalStatus emits only when `activeBasalType != state.basalDose.type`; Control-IQ rate changes are invisible
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:517` enactBolus under Control-IQ blocks only `activationType.isAutomatic`
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:367` persist() writes only `pumpManager.state.historyBackfill`, never lastReconciliation
  - `CLAUDE.md:541` 'gap-aware `lastReconciliation` advancement all remain to be done'

- Recommendation: Before either flag or Control-IQ pairing is considered supported, gate lastReconciliation on a completed history read through the pump's current sequence number, or refuse to advance it while `state.quickBolusEnabled == true` or `state.useControlIQ` is set.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

Open questions raised by this point:

- Does the pump emit a `.pumpSuspend` qualifying event (not only `.alarm`/`.malfunction`) when an occlusion, empty-cartridge or auto-off alarm stops delivery? If not, the suspend is only detected on the next sync and P02-5's timing gap is a full poll interval.
- P01 overlap: syncPumpData never calls hasNewPumpEvents on a quiet sync, so the fresh stamp reaches TandemKit state but not DoseStore; P02-3's reservoir flip-flop is the P02-visible consequence and is resolved by fixing P01.
- Under the premise Trio ignores lastReconciliation entirely (DeviceDataManager.swift:608), so every finding here affects Loop only; the Trio impact of this point is nil regardless of verdict.
- Working tree HEAD is f008ec40 (adds only docs/dose-reporting-conformance-audit.md on top of the stated 7d20b2dc); all cited source lines are identical in both commits.
### P03. Each dose has a raw/syncIdentifier that is byte-for-byte constant for the entire life of that dose, including in-progress re-reports and cancellation

Guide section: §9 item 3 (with §4).

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 7 of 7 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

TandemKit's optimistic (Loop-commanded) doses key `raw` as "<type> <units> <ISO8601 start, second precision>". The start component is stable on every path (all call sites pass dose.startDate; no Date.now default is used; persisted UnfinalizedDose round-trips the Date). The units component is not: cancelBolus keys on deliveredUnits, bolus completion keys on the pump-reported delivered amount, and temp basals key on programmedUnits = rate x duration, which shrinks whenever a temp basal is cut short (the normal case when Loop re-issues every ~5 min). Correct end state currently depends on the replacePendingEvents:true mutable purge, not on identity. The history mapper mints stable pump-assigned ids but is not wired, and uses a different identity scheme than the optimistic path. No test asserts raw stability for the manager path.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P03-1 | Non-conforming | low | amended | Bolus cancellation changes raw (deliveredUnits in key) |
| P03-2 | Partial | medium | verified | Bolus completion re-keys on pump-reported delivered volume |
| P03-3 | Non-conforming | low | amended | Temp basal raw derived from programmedUnits (rate x duration) |
| P03-4 | Conforms | none | verified | Mutable temp-basal re-reports and start-date component are stable |
| P03-5 | Partial | low | amended | Basal/suspend/resume raw has 1-second resolution and no discriminator |
| P03-6 | Partial | low | amended | History identity scheme differs from optimistic scheme; not yet wired |
| P03-7 | Partial | low | verified | Linux shim omits raw-to-syncIdentifier coupling; no lifecycle test |

**P03-1 Bolus cancellation changes raw (deliveredUnits in key)** (Non-conforming, impact low, amended)

The initial mutable bolus is keyed on the programmed amount, but cancelBolus re-keys the same dose on the partially delivered amount (or 0 if the LastBolusStatus query fails), so the raw and therefore syncIdentifier change mid-life. This is exactly the MedtrumKit pattern the guide flags in section 4. Because the cancel batch is emitted with replacePendingEvents:true, DoseStore purges the stale mutable row by its mutable flag and InsulinDeliveryStore soft-deletes the unmatched mutable dose, so the end state is a single finalized dose. Correctness rests on that safety net rather than on identity matching: the in-progress row is deleted and a new one inserted, never updated in place.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:10` raw: "\(DoseType.bolus.rawValue) \(units) \(dateFormatter.string(from: date))"
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:599` initial report: NewPumpEvent.bolus(dose: doseEntry, units: units, date: dose.startDate) -- programmed units
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:653` cancel: .bolus(dose: canceledDose, units: canceledDose.deliveredUnits ?? 0, date: canceledDose.startDate)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:657` self.emitPumpEvents(events) -- replacePendingEvents defaults to true

- Recommendation: Key the bolus raw on the programmed amount only (pass `units: canceledDose.programmedUnits`, or better a bolusId-based HistoryLogSyncIdentifier.bolus minted at enactBolus), and finalize by flipping isMutable and setting deliveredUnits. Add a manager test asserting raw equality across enact/cancel.

- Verifier notes:
  - [review:amend] Facts verified: initial raw keys on programmed units (599), cancel re-keys on deliveredUnits ?? 0 (653), so syncIdentifier changes mid-life. But the cancel batch is replace:true (657 default at 1733), so in both LoopKit variants the stale mutable row is purged (DoseStore trio:704-706, nextdev:624-625) and IDS soft-deletes the unmatched mutable dose (trio IDS:434); one finalized dose results, no IOB error. Trio ignores raw entirely and updates the same-date bolus only if smaller. No accounting degradation in any host; latent only. Premise irrelevant (app trigger).

**P03-2 Bolus completion re-keys on pump-reported delivered volume** (Partial, impact medium, verified)

On natural completion the finalized event is built from getPumpEvent(actualDeliveredUnits:), whose raw units component is the pump-reported delivered volume. When the pump delivered exactly the programmed amount the string usually matches the initial report (both are Double(n)/1000 grid values), so identity holds on the happy path. It diverges whenever delivery was interrupted on the pump (occlusion, pump-UI cancel, reconciliation after BLE loss) or if the host passes an unrounded `units` value, since enactBolus does not round before keying. The mismatch is again masked only by the replacePendingEvents:true purge. Note also that after app relaunch bolusProgressReport is nil, so this completion path never runs (StateSync 217-224 clears state without emitting), which is a P04/P05 concern.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:33` let delivered = actualDeliveredUnits ?? total
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:44` units: delivered, -- raw component is the delivered, not programmed, amount
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:256` actualDelivered = queryLastBolusDeliveredVolume(bolusId: bolusId)
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:268` emitPumpEvents(events) -- replacePendingEvents true
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1881` stride(...).map { Double($0) / multiplier } -- grid values equal decimal literals, so full delivery usually matches

- Recommendation: Have getPumpEvent pass `units: total` (programmed) into the raw while still setting deliveredUnits to the pump-reported value. Round `units` with roundToSupportedBolusVolume before building the UnfinalizedDose so the key is grid-exact.

- Verifier notes:
  - [review:confirm] Code fact holds: getPumpEvent keys raw on `delivered = actualDeliveredUnits ?? total`, enactBolus builds UnfinalizedDose with unrounded `units`, completion emits with replacePendingEvents true. Only the pump-UI-cancel trigger drops out under the premise; occlusion/alarm-aborted boluses, BLE-loss reconciliation and unrounded host units are premise-independent. End state remains correct only via the mutable purge, so partial/medium stands.

**P03-3 Temp basal raw derived from programmedUnits (rate x duration)** (Non-conforming, impact low, amended)

The mutable temp-basal report has endDate = estimatedEndDate, so programmedUnits = rate x full duration. Finalization via getActivePumpEvents(endDate:) uses min(endDate, estimatedEndDate), so whenever the temp basal is replaced or stopped before its programmed end (every Loop re-issue in enactTempBasal, suspendDelivery, configureControlIQMode, fetchBasalStatus, handleHomeScreenMirrorResponse) programmedUnits shrinks and the raw changes. Only a temp basal that runs to its programmed end keeps its identity. All these finalizations use replacePendingEvents:true, so the stale mutable row is purged and a new immutable row inserted; the end state is correct but each finalized TBR is a delete-plus-insert, not an update. This is the section 10 'TBR overwritten' shape the guide warns about.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:20` raw: "\(DoseType.tempBasal.rawValue) \(dose.programmedUnits) \(...date)"
  - `reference: loopkit-trio/DoseEntry.swift:73` case .unitsPerHour: return value * hours -- programmedUnits scales with endDate
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:177` var actualEndDate = isMutable ? estimatedEndDate : endDate
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` state.basalDose.toDoseEntry(isMutable: endDate == nil, endDate: endDate ?? Date.now)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:765` var events = self.getActivePumpEvents(endDate: dose.startDate) -- finalizes previous TBR early on every re-issue

- Recommendation: Key temp basals on values fixed at enact time: the rate (`dose.unitsPerHour` or UnfinalizedDose.value) plus start, or a per-dose UUID/tempRateId stored in UnfinalizedDose and persisted. Add a test that enacts, then replaces, a temp basal and asserts identical raw bytes.

- Verifier notes:
  - [review:amend] Verified: mutable TBR uses estimatedEndDate (UnfinalizedDose:177), finalized uses min(endDate, estimatedEndDate) (178-181), and raw embeds programmedUnits = value*hours (trio DoseEntry:73), so raw shrinks on every early finalization via getActivePumpEvents(endDate:) (1707; callers 736/765/824/1324, StateSync:149/481). Identity survives only when the TBR runs to its programmed end (1716 compares endDate to estimatedEndDate). Every finalizing batch is replace:true, so both LoopKit variants purge-and-reinsert with correct totals; Trio skips finalized TBRs (deliveredUnits != nil) so raw never matters there. No accounting error today; latent identity flaw.

**P03-4 Mutable temp-basal re-reports and start-date component are stable** (Conforms, impact none, verified)

When a temp basal is re-reported while still running (from cancelBolus and from bolus completion), toDoseEntry(isMutable:true) uses estimatedEndDate exactly as the initial report did, so programmedUnits and the ISO8601 start string are byte-identical to the enact-time raw. Every NewPumpEvent factory call in the driver passes `date:` explicitly from the dose's own startDate; none rely on the Date.now default. ISO8601DateFormatter truncates to whole seconds, and UnfinalizedDose persists startDate as a Date, so the string is unchanged across BLE reconnect and app relaunch. The instability in P03-1/2/3 is entirely in the units component, not the timestamp.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:647` var events = self.getActivePumpEvents() -- endDate nil => isMutable true re-report
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:259` var events = getActivePumpEvents() -- same re-report at bolus completion
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1711` date: basalEntry.startDate -- explicit start, not Date.now
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:136` raw["startDate"] = startDate -- persisted as Date, restored at line 88-93
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:272` basalDose = UnfinalizedDose(rawValue: rawDoseEntry) ?? ... -- survives relaunch

- Recommendation: Keep the explicit `date: dose.startDate` discipline; if the key is redesigned, retain a start-anchored or id-anchored component and drop the mutable units component.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P03-5 Basal/suspend/resume raw has 1-second resolution and no discriminator** (Partial, impact low, amended)

Scheduled-basal, suspend and resume events are immutable and reported once, so per-dose constancy is trivially met. However their raw is only the type plus a whole-second timestamp. Two events of the same type inside one second collide on DoseStore's unique raw constraint and the second is silently deduplicated. The enactTempBasal 100%-percent path and suspend/configureControlIQ paths can append a scheduled-basal marker from getActivePumpEvents(endDate:) and another from their own code in one batch; only fetchBasalStatus guards against this. Basal markers carry no insulin beyond the schedule, so accounting impact is small, but a lost suspend marker in a rapid suspend/resume/suspend sequence would be more serious.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:31` raw: "\(DoseType.basal.rawValue) \(dateFormatter.string(from: date))"
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1721` events.append(NewPumpEvent.basal(... date: basalEntry.endDate)) -- appended by getActivePumpEvents
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:737` events.append(NewPumpEvent.basal(dose: dose.toDoseEntry(isMutable: false), date: dose.startDate)) -- second basal in same batch, no dedupe guard
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:167` if !events.contains(where: { $0.type == .basal }) -- guard exists only here
  - `reference: loopkit-trio/DoseEntry.swift:31` init(suspendDate: ..., isMutable: Bool = false ...) -- these are single-shot immutable events

- Recommendation: Include a discriminator (sequence counter, UUID, or sub-second component) in basal/suspend/resume raws, and reuse the fetchBasalStatus duplicate-basal guard in the other paths that append a scheduled-basal marker.

- Verifier notes:
  - [review:amend] Lead reviewer re-check: raw format and second resolution confirmed (31). The same-batch double basal marker needs getActivePumpEvents to append one, which requires exact Date equality between the finalization endDate and estimatedEndDate (1716), so the collision inside enactTempBasal is theoretical; the finding stays partial/low as a design note.

**P03-6 History identity scheme differs from optimistic scheme; not yet wired** (Partial, impact low, amended)

The history path is designed correctly for this point: bolus activation and completion, and temp-rate activation and completion, share a pump-assigned id in a frozen 10-byte encoding, and tests pin the golden values. But mapToEvents has no caller in Sources, nothing under History/ reaches emitPumpEvents, and historyDoseReporting has no consumer, so none of this is live. Meanwhile the optimistic path keys the same bolus as a text string despite already holding bolusId. If history reporting is wired without first migrating enactBolus to the same identity (or reconciling by bolusId before emit), a Loop-commanded bolus will appear under two identities and be double-counted. Today the impact is nil; the design gap is acknowledged in the code comment.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryLogSyncIdentifier.swift:45` Nothing emits these identifiers yet -- `NewPumpEvent`'s raw values are still built from the dose type, volume and timestamp.
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:183` let raw = HistoryLogSyncIdentifier.bolus(pumpSerial: pumpSerial, bolusId: completion.bolusId)
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:207` in-flight bolus uses the same bolusId key as its completion
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:584` bolusId: permissionResponse.bolusId -- id known at enact time but not used in raw
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:173` self[.historyBackfill] && self[.historyDoseReporting] -- both default false

- Recommendation: Before wiring history dose reporting, switch enactBolus/cancel/completion to HistoryLogSyncIdentifier.bolus(pumpSerial, bolusId) when the serial is known (fall back to the text key otherwise), and add a test that an optimistic bolus and its history confirmation share raw bytes.

- Verifier notes:
  - [review:amend] Lead reviewer re-check: facts confirmed (HistoryLogSyncIdentifier.swift:45, HistoryToDoseMapper.swift:183/207, no production caller). The same latent defect is rated low in the reviewed P24-1 and P08-6; lowered from medium to low for consistency. It becomes high once history emission is wired without re-keying the live path.

**P03-7 Linux shim omits raw-to-syncIdentifier coupling; no lifecycle test** (Partial, impact low, verified)

On Linux the shim's NewPumpEvent does not derive dose.syncIdentifier from raw the way the pinned LoopKit does, so Linux CI cannot observe the identity coupling that section 2 describes; the history mapper works around this by stamping syncIdentifier itself, but the optimistic factories in NewPumpEvent.swift do not. Separately, the mock delegate records every hasNewPumpEvents batch, yet no test inspects those events, so the raw drift in P03-1/2/3 is unguarded by any test on either platform. This is test-infrastructure quality rather than a runtime accounting defect on Apple builds.

- Evidence:
  - `LinuxShims/LoopKit/LoopKit.swift:552` self.date = date ... self.raw = raw -- dose.syncIdentifier is never set from raw
  - `reference: loopkit-trio/NewPumpEvent.swift:33` dose?.syncIdentifier = raw.hexadecimalString
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:36` var pumpEvents: [NewPumpEvent] -- recorded, but no test reads .pumpEvents or compares raw
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:192` syncIdentifier: raw.hexadecimalString -- mapper sets it explicitly to compensate

- Recommendation: Make the shim init mirror LoopKit (set dose.syncIdentifier = raw.hexadecimalString). Add lifecycle tests using MockPumpManagerDelegate that assert byte-equal raw across enact/re-report/cancel/complete for one bolus and one temp basal.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

Open questions raised by this point:

- Does the host (Trio/Loop) always pass `units` to enactBolus already rounded via roundToSupportedBolusVolume? enactBolus (TandemPumpManager.swift:578-599) keys the raw on the unrounded argument while completion keys on the grid-rounded pump value; an unrounded input would break identity even on full delivery. Checking the host call site would settle it.
- Is a tempRateId available at command time (e.g. in SetTempRateResponse or TempRateResponse cargo)? If so the optimistic temp basal could use HistoryLogSyncIdentifier.tempRate; if not, a persisted per-dose UUID in UnfinalizedDose is the fallback.
- After app relaunch, bolusProgressReport is in-memory only (TandemPumpManager.swift:70) and fetchBolusStatus clears a completed bolus without emitting a finalization (StateSync.swift:217-224); the persisted mutable bolus is then purged on the next replacePendingEvents:true batch. This is a P04/P05 (re-report/finalize) concern rather than an identity one, but it means identity constancy can never be exercised across relaunch today.
- The guide (written against loopkitdev next-dev) expects decisionId threading; the pinned loopandlearn LoopKit DoseEntry has no decisionId, so that checklist item is not applicable to what TandemKit builds against today (outside P03).
- docs/tandemkit-history-integration-plan.md:295 and :596 plan 'syncIdentifier preservation' between pending doses and history; that plan is not reflected in code yet and should be reconciled with the HistoryLogSyncIdentifier design once history reporting is wired.
### P04. In-progress doses are reported with isMutable: true and re-reported on EVERY sync until they finalize; nothing mutable is silently omitted from a replacePendingEvents:true batch

Guide section: §9 item 4 (with §3 report-or-delete rule).

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 7 of 7 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

TandemKit reports only two kinds of mutable dose: the Loop-commanded bolus and the Loop-commanded temp basal. The bolus is emitted mutable exactly once (enactBolus, replacePendingEvents:false) and is never re-sent; the `.inProgress` bolusState only feeds PumpManagerStatus. Every later replacePendingEvents:true batch (basal-type change on sync, suspend, resume, Control-IQ enable, next enactTempBasal) omits it, so the Trio-pinned DoseStore purges it until finalization is detected; after an app relaunch it is cleared silently and never finalized. The TBR is not re-reported on routine syncs either, but it is finalized inside most replace:true batches, so it is only lost on the resume path. No test observes replacePendingEvents.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P04-1 | Non-conforming | high | verified | Running bolus never re-reported; purged by any replace:true batch |
| P04-2 | Non-conforming | high | amended | After app relaunch a persisted in-progress bolus is cleared without finalization |
| P04-3 | Partial | low | amended | Running temp basal not re-reported on routine syncs, but finalized in most replace:true batches |
| P04-4 | Non-conforming | medium | amended | Resume path omits live TBR and bolus from a replace:true batch |
| P04-5 | Conforms | none | verified | Suspend/resume/basal reported immutable; only bolus and TBR are ever mutable |
| P04-6 | Partial | medium | verified | Estimate-based bolus guard opens the omission window before pump confirms |
| P04-7 | Non-conforming | low | verified | No test observes replacePendingEvents or mutable re-reporting |

**P04-1 Running bolus never re-reported; purged by any replace:true batch** (Non-conforming, impact high, verified)

The in-progress bolus is a mutable DoseEntry (deliveredUnits nil, UnfinalizedDose.swift:161) sent once with replacePendingEvents:false. Nothing re-sends it: syncs update bolusState/progress observers only, and getActivePumpEvents (1702) covers only the temp basal. While the bolus runs, realistic replace:true batches fire: a routine sync whose fetchBasalStatus sees the 30-min TBR expire (149-183), a user suspend (828), Control-IQ enable (1330), or the next enactTempBasal once the estimate-based guard releases (679). Each purges the bolus from DoseStore and the InsulinDeliveryStore. It reappears only when fetchBolusStatus sees bolusId==0 (StateSync:249-268), under a different raw (NewPumpEvent.swift:10 keys on delivered units). In between, Loop/Trio compute IOB without the bolus.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:598` only mutable bolus emission: `self.emitPumpEvents(` ... `replacePendingEvents: false`
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:236` `state.bolusState = .inProgress(dose.toDoseEntry(isMutable: true))` — status only, no NewPumpEvent
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:149` fetchBasalStatus batch `var events = getActivePumpEvents(endDate: now)` has no bolus; emitted at 161/183 with default replace:true
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:828` suspendDelivery emits [finalized TBR, suspend] with default replace:true; bolus omitted (also 910, 1330)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1733` `func emitPumpEvents(_ events: [NewPumpEvent], replacePendingEvents: Bool = true)`

- Recommendation: Include the running bolus (same raw, isMutable:true) in every batch built by getActivePumpEvents and re-emit it on every sync; or emit all intra-bolus batches with replacePendingEvents:false until the bolus is finalized.

- Verifier notes:
  - [review:confirm] Verified literally: the only mutable bolus emission is enactBolus with replace:false (598-601); fetchBolusStatus while delivering only sets bolusState (StateSync:236); getActivePumpEvents never returns the bolus (1703). syncPumpData defers bolus sync (436) but runs fetchBasalStatus unconditionally (437), which emits replace:true when a TBR expires mid-bolus (149-161/183); suspend (828), Control-IQ enable (1330) and enactTempBasal after the timer estimate flips (679) do the same. In both LoopKit variants the mutable bolus row is purged and IDS soft-deletes it; after relaunch bolusProgressReport is in-memory only (70), so 217-224 clears bolusDose without emitting: lost dose. Minor: raw is identical on full delivery. Trio is immune (ignores replacePendingEvents). App-triggered, premise unaffected.

**P04-2 After app relaunch a persisted in-progress bolus is cleared without finalization** (Non-conforming, impact high, amended)

The manager persists bolusDose but not the progress reporter. On relaunch mid-bolus (or after a bolus whose completion event was missed), fetchBolusStatus takes the reporter-nil branch: if the pump says already-delivered it silently drops bolusDose (217-224); if still delivering it returns at 226 without re-reporting. No finalized event is ever emitted for that bolus. Its mutable row survives in DoseStore only until the first replacePendingEvents:true batch — typically the next loop cycle's enactTempBasal — and is then deleted permanently. BLE reconnect within the same process is different: performInitialSetup (TandemPeripheralManager.swift:493) runs no sync and the reporter survives, so only relaunch hits this. History backfill/emission that could recover the dose does not exist.

- Evidence:
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:60` `public var bolusDose: UnfinalizedDose?` persisted (restored at 244-247)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:70` `internal var bolusProgressReport: TandemDoseProgressReporter?` — in-memory only, nil after relaunch
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:217` `if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil` → clears bolusDose, emits nothing
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:226` `guard let progressReport = bolusProgressReport else { return }` — .delivering and finish paths unreachable without the reporter
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:778` next enactTempBasal emits with replace:true; the stale mutable bolus row is purged

- Recommendation: On init, if state.bolusDose exists, rebuild the reporter (or make finalization independent of it) and re-report the bolus mutable; on the first status read, finalize via LastBolusStatus deliveredVolume (queryLastBolusDeliveredVolume) rather than clearing silently.

- Verifier notes:
  - [review:amend] Code facts confirmed: init rebuilds no reporter, the reporter-nil branch clears bolusDose silently, and the delivering path returns without re-reporting; the trigger (relaunch) is unaffected by the premise. One key fact needs correcting: the mutable row is deleted only in LoopKit DoseStore hosts (both variants purge mutable==YES). Trio ignores replacePendingEvents and stores the enact-time bolus permanently at programmedUnits, so in Trio the dose is not lost; it is over-counted at the full programmed amount if the pump aborted it (occlusion/alarm), and correct if it completed. High holds under either host.

**P04-3 Running temp basal not re-reported on routine syncs, but finalized in most replace:true batches** (Partial, impact low, amended)

The TBR is emitted mutable when enacted (772) and again only in cancelBolus and bolus-finish batches. A quiet 5-minute sync sends no hasNewPumpEvents at all, so the guide's "re-reported on every sync" is not met. However, TandemKit does not silently omit the TBR from the replace:true batches it does send: fetchBasalStatus, enactTempBasal, suspendDelivery and configureControlIQMode all call getActivePumpEvents(endDate:) first, which converts the live TBR into a finalized entry in the same batch. Under the Trio-pinned DoseStore the mutable row therefore persists between syncs and is replaced, not dropped — the exception is the resume path (P04-4). Steady-state IOB from the TBR is preserved; the gap is contractual rather than an observed loss.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` `toDoseEntry(isMutable: endDate == nil, endDate: endDate ?? Date.now)` — mutable only when endDate nil
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:648` cancelBolus `var events = self.getActivePumpEvents()` — one of two mutable re-reports (other: StateSync:259)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:437` syncPumpData calls fetchBasalStatus; nothing emits when basal type is unchanged (StateSync:141)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:736` enactTempBasal includes finalized old TBR `getActivePumpEvents(endDate: dose.startDate)` (also 771, 821, 1324)
  - `reference: loopkit-trio/DoseStore.swift:682` `guard events.count > 0 else { completion(nil); return }` — empty batches neither purge nor re-resolve

- Recommendation: Re-emit the live TBR (same raw, isMutable:true) from every syncPumpData pass, alongside the empty-batch lastReconciliation update, so the batch is always the complete pending set.

- Verifier notes:
  - [review:amend] Lead reviewer re-check: facts confirmed. The finding's own analysis is that the temp basal is finalized in every complete batch except the resume path (P04-4, rated separately), so steady-state IOB is preserved; the unmet requirement is the re-report cadence with no accounting consequence. Lowered from medium to low.

**P04-4 Resume path omits live TBR and bolus from a replace:true batch** (Non-conforming, impact medium, amended)

sendResumePumping builds a batch of only the resume event. If state.basalDose is still .tempBasal (pump was suspended on its own UI and no sync has run since; the fill-tubing flow checks suspension against the pump rather than state), the live TBR's mutable row is purged by replacePendingEvents:true and the TBR is never finalized because state.basalDose is overwritten — insulin delivered under that TBR before the suspend disappears from Loop's history. The settings-screen resume is gated on state, so only the fill-tubing resume (and any host-app resume issued from a stale status) reaches this. Any running bolus (P04-1) is omitted here too.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:904` `let events = [NewPumpEvent.resume(dose: dose.toDoseEntry(), date: dose.startDate)]` — no getActivePumpEvents
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:906` `state.basalDose = dose` overwrites a possibly still-tempBasal basalDose, so it can never be finalized later
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:910` `emitPumpEvents(events)` — default replacePendingEvents:true
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitFillTubingViewModel.swift:128` `pumpManager?.fetchSuspendStatus` reads the pump directly, not state.basalDose
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:130` fetchSuspendStatus `completion(response.basalType == .suspend)` does not update state.basalDose

- Recommendation: Build the resume batch with getActivePumpEvents(endDate: resumeStart) like suspendDelivery does, or refresh basal state from the pump before emitting; never overwrite a .tempBasal basalDose without finalizing it.

- Verifier notes:
  - [review:amend] Code facts hold: sendResumePumping emits only [resume] with default replace:true (904-910) and overwrites state.basalDose (906), so a still-.tempBasal basalDose is purged in Loop and never finalized; settings resume is gated on state (SettingsVM:191) but cartridge/tubing/cannula flows check the pump directly (fetchSuspendStatus, StateSync:130 does not update basalDose) and call resumeDelivery (FillTubingVM:244). Key fact corrected for the premise: the trigger is not a pump-UI suspend (N/A on Mobi) but a pump-initiated stop (occlusion/empty-cartridge/auto-off) during BLE loss so no basalStatus fetch ran; qualifying events normally map pumpSuspend to fetchBasalStatus, narrowing it. Trio immune. Loop loses TBR delivered before the stop: medium.

**P04-5 Suspend/resume/basal reported immutable; only bolus and TBR are ever mutable** (Conforms, impact none, verified)

An open suspend is reported as an immutable point event, as are resume and scheduled-basal markers. That matches the in-tree reference drivers (Omnipod/Medtrum also report suspend without a duration), so these are never at risk of the report-or-delete purge and nothing mutable of these types can be silently omitted. The guide's §3 wording ("an open suspend — all are mutable") is stricter than LoopKit's own suspend model; noted for completeness, not as a defect. The mutable surface to keep re-reporting is therefore exactly the Loop bolus and Loop TBR examined in P04-1..4.

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:197` `.suspend` → `DoseEntry(suspendDate: startDate, automatic: automatic)` — isMutable defaults false
  - `reference: loopkit-trio/DoseEntry.swift:31` `init(suspendDate:..., isMutable: Bool = false, ...)`
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:168` `.basal` DoseEntry has no isMutable argument — always immutable
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:519` `.tempBasal(basalDose.toDoseEntry(isMutable: true))` — status surface, not DoseStore

- Recommendation: No change required; keep suspend/resume immutable, consistent with reference drivers.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P04-6 Estimate-based bolus guard opens the omission window before pump confirms** (Partial, impact medium, verified)

enactTempBasal is blocked only while the reporter's elapsed-time estimate says the bolus is unfinished. Once the estimate completes — before the pump has confirmed via qualifying event or the deferred sync — Loop's next enactTempBasal is accepted and its replace:true batch omits the still-mutable bolus, deleting it (P04-1 mechanism) deterministically rather than only on rarer paths. If the bolusChange event was lost, the deletion persists until the next sync past the 30s grace finalizes it. With the reporter nil (P04-2) the guard is absent entirely.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:679` `if let bolusProgressReport, bolusProgressReport.isUnfinalized()` — only guard against enactTempBasal mid-bolus
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:58` `deliveredUnits < total` where deliveredUnits is elapsed-time estimate (line 77)
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:198` sync finalization deferred until `estimatedEndDate + 30s`; a lost bolusChange event is never replayed (comment 192-193)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:771` enactTempBasal batch `getActivePumpEvents(endDate:)` + new TBR, replace:true, no bolus

- Recommendation: Gate on pump-confirmed completion (state.bolusDose == nil) rather than the estimate, and have enactTempBasal carry the mutable bolus in its batch until it is finalized.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: the enactTempBasal guard is bolusProgressReport.isUnfinalized() (679), which is the time-based estimate deliveredUnits < total (58, 77), and is absent when the reporter is nil.

**P04-7 No test observes replacePendingEvents or mutable re-reporting** (Non-conforming, impact low, verified)

The mock delegate appends events but drops replacePendingEvents, so no test can assert that a batch marked as the complete pending set actually contains every live mutable dose, nor that a running bolus/TBR is re-sent across syncs. The bolus finish path (StateSync:249-268), cancelBolus (648-657) and enactTempBasal (736-778) have no event-level tests. This is why P04-1/P04-2 have gone unnoticed.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:130` `replacePendingEvents _: Bool,` — flag discarded by the test delegate
  - `Tests/TandemKitTests/TandemPumpManagerBolusSyncTests.swift:24` bolus tests cover only shouldDeferBolusSync; no event assertions
  - `Tests/TandemKitTests/TandemPumpManagerSuspendDeliveryTests.swift:98` testSuspendRecordsASuspendDose asserts state only, not the emitted batch contents

- Recommendation: Record replacePendingEvents in the mock and add tests: mid-bolus sync with TBR expiry, suspend mid-bolus, relaunch mid-bolus, and TBR re-report, asserting each replace:true batch contains all live mutable doses.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

Open questions raised by this point:

- The Trio-pinned DoseStore.addPumpEvents returns early on empty events (line 682) before the mutable purge and before syncPumpEventsToInsulinDeliveryStore, so the guide's §8 claim that an empty call re-resolves the InsulinDeliveryStore does not hold for the LoopKit TandemKit builds against (lastReconciliation is still set at line 680).
- Does Trio's DeviceDataManager/pump delegate use PumpManagerStatus.bolusState (.inProgress) for anything IOB-related? If so, the status surface partially masks P04-1 in Trio; settle by reading Trio's PumpManagerDelegate implementation.
- Bolus raw changes between the mutable report (units: programmed, TandemPumpManager.swift:599) and the finalized report (units: delivered, TandemDoseProgressReporter.swift:44 / cancelBolus:652) — a §4/P03 identity issue that compounds P04-1 (finalized bolus is inserted as a new row rather than matched).
- handleHomeScreenMirrorResponse (StateSync.swift:473-514) emits a replace:true batch but has no callers in Sources/; dead code or pending wiring?
- Domain fact to verify on hardware: does SuspendPumpingRequest cancel a running bolus on t:slim X2/Mobi? It determines whether the suspend-path omission in P04-1 is followed by a finalization with the partial volume.
- docs/tandemkit-history-integration-plan.md:468 describes a history-driven hasNewPumpEvents(replacePendingEvents: true) emission that does not exist in the current code (HistoryBackfillCoordinator.swift:9); the doc is stale relative to HEAD.
### P05. Finalized doses are reported with isMutable: false, a real endDate, and the actual deliveredUnits

Guide section: §9 item 5 (with §3 finalization).

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 7 of 7 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

App-commanded boluses that complete or are cancelled while the app process is alive are finalized with isMutable:false and a pump-reported deliveredUnits (LastBolusStatus, milliunits/1000), which is the right shape. But endDate is always Date.now at detection rather than the pump's completion time; the cancel path substitutes 0 U and the completion path substitutes the full programmed amount when the pump query fails; delivered volume is floored to a 0.05 U grid; and after an app relaunch a persisted in-flight bolus is never finalized because the progress reporter is in-memory only, so Loop purges the mutable dose and the insulin is lost. Temp basals finalize with programmed-rate x elapsed and detection-time endDate. The history mapper finalizes correctly but has no production caller and sits behind two default-off flags.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P05-1 | Partial | medium | verified | Bolus natural completion via CurrentBolusStatus (steady state) |
| P05-2 | Partial | high | verified | cancelBolus finalization falls back to zero delivered |
| P05-3 | Partial | medium | verified | Bolus endDate is detection time, not pump completion time |
| P05-4 | Non-conforming | high | amended | Persisted in-flight bolus is never finalized after app relaunch |
| P05-5 | Partial | low | verified | Delivered volume floored to 0.05 U grid |
| P05-6 | Partial | medium | verified | Temp basal finalization: programmed x elapsed, detection-time end |
| P05-7 | Partial | low | verified | History-log finalization: correct shape, unreachable; extended boluses ignored |

**P05-1 Bolus natural completion via CurrentBolusStatus (steady state)** (Partial, impact medium, verified)

In the common path the finalized event has isMutable:false, an endDate and deliveredUnits taken from the pump (LastBolusStatus.deliveredVolume / 1000). That satisfies the guide's shape. The gap is the fallback: when LastBolusStatus fails or its bolusId does not match (e.g. the user delivered a quick bolus on the pump after Loop's bolus), the dose is finalized as fully delivered. A bolus stopped early by occlusion, alarm or a pump-side cancel would then be permanently over-counted, since a finalized row is never revised. There is no unit test of this path; the mock delegate records events but nothing asserts on finalization.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:249` `if response.bolusId == 0 {` is the completion trigger, requires bolusProgressReport non-nil (guard at 226)
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:256` `actualDelivered = queryLastBolusDeliveredVolume(bolusId: bolusId)` reads LastBolusStatus deliveredVolume
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:33` `let delivered = actualDeliveredUnits ?? total` falls back to programmed amount
  - `Sources/TandemCore/Common/Extensions/DoseEntry.swift:25` `isMutable: false` when endDate supplied
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:527` `guard response.bolusId == bolusId else {` mismatch returns nil, so a pump-UI bolus after ours forces the programmed-total fallback

- Recommendation: Do not finalize on a guessed amount. If LastBolusStatus fails or mismatches, keep the dose mutable and retry (or read BolusCompletedHistoryLog for that bolusId). Add a StubPumpBluetooth test that drives enact -> completion and asserts isMutable:false and deliveredUnits equal the stubbed pump volume.

- Verifier notes:
  - [review:confirm] Code fact holds: bolusId==0 triggers completion, queryLastBolusDeliveredVolume returns nil on comm failure or bolusId mismatch, and getPumpEvent then finalizes at the programmed total. Under the premise the bolusId-mismatch trigger (quick bolus after ours) is not applicable in the default configuration and only returns under the quick-bolus or Control-IQ conditional sources. The comm-failure fallback still combines with a pump-aborted bolus (occlusion, empty cartridge, auto-off) to permanently over-count a partial bolus, so partial/medium stands.

**P05-2 cancelBolus finalization falls back to zero delivered** (Partial, impact high, verified)

Cancellation correctly waits 2 s, queries LastBolusStatus and finalizes with isMutable:false. But when that query returns nil (no response, or bolusId mismatch) the dose is finalized with deliveredUnits = 0. A bolus that had already delivered several units before the cancel is then recorded as zero, and because the row is immutable it is never corrected. This is the unsafe direction (IOB under-count -> Loop over-delivers), and it is the opposite fallback from the completion path (P05-1), so the two paths disagree on what an unknown delivery means. The completion callback also returns nil instead of the canceled DoseEntry, so the host cannot display or reconcile it.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` `bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:641` `let canceledDose = bolusDose.toDoseEntry(endDate: Date.now)` -> immutable
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:161` `deliveredUnits: isMutable ? nil : deliveredUnits` carries the 0 into the finalized entry
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:659` `completion(.success(nil))` — the finalized DoseEntry is not returned to the host

- Recommendation: On a failed/mismatched LastBolusStatus query, leave the dose mutable (re-report it) and re-query on the next sync or via BolusCompletedHistoryLog; never finalize at 0. Return the canceled DoseEntry in the completion. Cover with a test where the stub omits LastBolusStatusResponse.

- Verifier notes:
  - [review:confirm] Claim literal and accurate: cancel coerces a nil LastBolusStatus read to 0 and finalizes immutable; completion returns nil. Under the premise the triggers survive: BLE timeout (app-side) and a bolusId mismatch from the Mobi storage lag the 2 s sleep only guesses at; Control-IQ/quick-bolus mismatches are conditional extras. Consequence holds in both hosts: LoopKit netBasalUnits honours deliveredUnits 0; Trio's smaller-amount update rewrites the stored bolus to 0. A partially delivered bolus vanishes from IOB, so high stands. Note Trio discards the returned DoseEntry anyway, so the nil return is minor.

**P05-3 Bolus endDate is detection time, not pump completion time** (Partial, impact medium, verified)

The finalized bolus gets endDate = the moment the app noticed completion. Steady state that is the completion poll or the next ~5-minute sync; after a BLE drop mid-bolus it is whenever the link comes back, possibly much later. The pump exposes its own timestamp on LastBolusStatus (and BolusCompletedHistoryLog carries pumpTimeSec) but neither is used. LoopKit treats a bolus whose window exceeds roughly one 5-minute delta as continuous delivery across startDate..endDate, so an inflated endDate smears IOB later than it was actually delivered. The wider the reconnect gap, the larger the distortion. The 'real endDate' requirement is only approximately met.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:42` `endDate: Date.now` on the finalized completion event
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:641` `bolusDose.toDoseEntry(endDate: Date.now)` on cancel
  - `Sources/TandemCore/Messages/CurrentStatus/LastBolusStatus.swift:54` `timestamp = Bytes.readUint32(cargo, 5)` — pump-side bolus timestamp is parsed but unused
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:198` sync defers until `estimatedEndDate + 30s`, so completion is detected at earliest ~30 s late and at most one sync (~5 min) late

- Recommendation: Compute the finalized endDate from pump data: LastBolusStatus.timestampDate (or startDate + deliveredUnits / bolus speed, clamped to now) rather than Date.now. Validate on hardware whether LastBolusStatus.timestamp is the start or completion time before relying on it.

- Verifier notes:
  - [review:confirm] Code fact holds: finalized bolus endDate is Date.now in getPumpEvent and in cancelBolus; LastBolusStatus.timestamp is parsed but unused; sync defers until estimatedEndDate + 30 s. All triggers are app-side (poll cadence, BLE loss, cancel), which the premise leaves unaffected. partial/medium stands.

**P05-4 Persisted in-flight bolus is never finalized after app relaunch** (Non-conforming, impact high, amended)

enactBolus emits the mutable bolus and persists state.bolusDose, but the object that builds the finalized event lives only in memory. If the app is killed mid-bolus (or before the completion sync), on relaunch fetchBolusStatus either clears bolusDose silently (status alreadyDelivered, reporter nil) or returns early (status delivering, reporter nil). No isMutable:false event is ever sent for that bolusId, and the mutable dose is not re-reported either. The next emitPumpEvents with replacePendingEvents:true — any basal-type change, temp basal, suspend — purges it from DoseStore, so the insulin vanishes from IOB. The history path that could recover it (HistoryToDoseMapper) has no production caller and its flags default off. This is exactly the MedtrumKit #92 failure the guide warns about.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:70` `internal var bolusProgressReport: TandemDoseProgressReporter?` — in-memory only, nil after relaunch
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:244` `if let bolusDoseRaw = rawValue["bolusDose"]` — the UnfinalizedDose itself is restored
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:217` `if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil {` clears bolusDose without emitting any event
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:226` `guard let progressReport = bolusProgressReport else { return }` — every finalize path needs the reporter
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:600` initial mutable bolus emitted with `replacePendingEvents: false`; the next `true` batch (e.g. StateSync:161/183) purges it

- Recommendation: Make finalization depend only on persisted state: rebuild the progress reporter from state.bolusDose on init, or move getPumpEvent onto UnfinalizedDose. On relaunch with a persisted bolusDose, re-report it mutable, then finalize from LastBolusStatus/BolusCompletedHistoryLog by bolusId. Add a relaunch test (init from rawValue, then sync).

- Verifier notes:
  - [review:amend] Same defect as P04-2 and the code claims check out: bolusDose round-trips (state 244-247, tested in TandemPumpManagerStateTests) but the finalizer lives only on the in-memory reporter, so no isMutable:false event is ever sent after a relaunch. The cited StateSync:161/183 emits are the fetchBasalStatus replace:true batches. Correct the consequence per host: LoopKit DoseStore purges the mutable row (lost dose); Trio never purges and keeps the enact-time row at programmedUnits, so the dose is retained and over-counted only if the pump aborted it. Relaunch is an app-side trigger, unaffected by the premise.

**P05-5 Delivered volume floored to 0.05 U grid** (Partial, impact low, verified)

The pump reports delivered volume in milliunits, i.e. 0.001 U resolution. The status path floors that to the 0.05 U command grid, so a cancelled bolus that delivered 1.049 U is finalized as 1.00 U. The error is bounded (< 0.05 U per bolus) but always understates delivery, which is the direction that lets Loop over-deliver. The repository already recognises this: HistoryToDoseMapper.roundToReportingResolution rounds to nearest 0.001 U precisely to avoid it, so the two finalization surfaces disagree. The guide asks for deliveredUnits rounded to the pump's supported increment; Tandem's reported increment is the milliunit, not 0.05 U.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:532` `return roundToSupportedBolusVolume(units: Double(response.deliveredVolume) / 1000.0)`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:226` `supportedBolusVolumes.last(where: { $0 <= units }) ?? 0` — floor, not nearest
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:27` `strideRange(from: 0.05, through: 25.0, by: 0.05)` is the grid
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:161` mapper instead rounds to nearest milliunit and documents why floor-to-grid is the unsafe direction

- Recommendation: Use HistoryToDoseMapper.roundToReportingResolution (nearest 0.001 U) for deliveredUnits in queryLastBolusDeliveredVolume; keep roundToSupportedBolusVolume for programming only. Add a test with deliveredVolume = 1049.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P05-6 Temp basal finalization: programmed x elapsed, detection-time end** (Partial, impact medium, verified)

Every path that ends a temp basal (enactTempBasal, suspendDelivery, configureControlIQMode, fetchBasalStatus, handleHomeScreenMirrorResponse) finalizes it through getActivePumpEvents(endDate:), producing isMutable:false, an endDate and deliveredUnits. Natural expiry is handled well: the end is clamped to the programmed end. Two gaps remain. First, deliveredUnits is programmed rate x elapsed time, not a measured amount, and is not rounded to any pump increment; Tandem gives no direct measured TBR volume, so this is the reasonable estimate but should be documented as such. Second, when the pump itself stops the TBR (user suspend on the t:slim screen, Control-IQ enable) and TandemKit only learns at the next sync, endDate is the sync time, over-reporting delivery by up to one sync interval at the temp rate.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` `state.basalDose.toDoseEntry(isMutable: endDate == nil, endDate: endDate ?? Date.now)`
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` `deliveredUnits: isMutable ? nil : value * (duration / .hours(1))` — programmed rate, unrounded
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:178` `if !isMutable, actualEndDate > estimatedEndDate {` clamps natural expiry to the programmed end
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:149` `var events = getActivePumpEvents(endDate: now)` — pump-side suspend/stop detected at sync gets the sync time as endDate
  - `Sources/TandemCore/Messages/HistoryLog/TempRateCompletedHistoryLog.swift:16` `timeLeft` plus pumpTimeSec give the true stop time but are unused by the status path

- Recommendation: For pump-initiated stops detected at sync, derive endDate from the pump (PumpingSuspendedHistoryLog / TempRateCompletedHistoryLog pumpTimeSec, or CurrentBasalStatus if it carries a change time) rather than Date.now. Round deliveredUnits to 0.001 U. Document that TBR deliveredUnits is computed, not measured.

- Verifier notes:
  - [review:confirm] Code fact holds: TBR finalization uses programmed rate x elapsed, unrounded, clamped to programmed end, and pump-side stops seen at sync get the sync time as endDate. The 'user suspend on the t:slim screen' example is not applicable under the premise and Control-IQ enable is conditional, but the premise keeps pump-initiated stops (occlusion, empty cartridge, auto-off, cartridge-change mode) fully in scope, and those hit exactly this path via fetchBasalStatus. The computed-not-measured deliveredUnits is premise-independent. partial/medium stands.

**P05-7 History-log finalization: correct shape, unreachable; extended boluses ignored** (Partial, impact low, verified)

The history mapper is the one place that finalizes exactly as the guide describes: pump completion timestamp as endDate, insulinDelivered rounded to nearest milliunit, isMutable:false, stable bolusId-based raw, and in-flight activations reported mutable under the same identity. HistoryToDoseMapperTests asserts these fields. However, nothing in Sources calls mapToEvents, and both governing flags default to false, so on every real path (steady state, first sync, reconnect, relaunch) this finalization never reaches the delegate. Within the mapper, finalized temp basals omit deliveredUnits (LoopKit then rounds programmedUnits to Minimed's 1/20 U increments via unitsInDeliverableIncrements), and extended-bolus records are dropped, so a t:slim extended bolus would be finalized with only its immediate portion once the layer is wired.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:175` `let endDate = reconciler.utcDate(pumpTimeSec: completion.pumpTimeSec, ...)` — real pump completion time
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:190` `deliveredUnits: Self.roundToReportingResolution(Double(completion.insulinDelivered))`, isMutable defaults false
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:261` TBR `isMutable: completion == nil` but no deliveredUnits, so LoopKit falls back to programmedUnits
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:118` `default: continue` — BolexActivated/BolexCompletedHistoryLog (extended bolus) are never mapped
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:9` "Nothing is mapped to doses or emitted here" — mapToEvents has no caller outside tests

- Recommendation: When wiring the emission layer, set deliveredUnits on finalized TBRs (rate x min(programmed, actual) duration) and add BolexActivated/BolexCompleted handling so the extended portion is counted. Until then, document clearly that history-based finalization is not active in shipped builds.

- Verifier notes:
  - [review:confirm] Code fact holds: mapToEvents has no caller in Sources, both governing flags default false, TBR mapping omits deliveredUnits, Bolex records fall to `default: continue`. Under the premise the extended-bolus gap is not applicable by default (TandemKit issues no extended boluses and Control-IQ does not either), which only reinforces the existing low rating; the rest is dormant code. partial/low stands.

Open questions raised by this point:

- Identity vs finalization (P03/P04 territory): the finalized bolus raw embeds deliveredUnits (`NewPumpEvent.bolus(... units: delivered ...)`, TandemDoseProgressReporter.swift:44, TandemPumpManager.swift:652) and the TBR raw embeds programmedUnits = rate x (endDate - startDate) (NewPumpEvent.swift:20), so any finalization with a shorter duration or partial delivery changes the syncIdentifier. Finalization therefore works only through the replacePendingEvents:true purge, not in-place matching — and the relaunch case in P05-4 is where that safety net fails.
- LastBolusStatusResponse.timestamp semantics: is it the bolus start or completion time on Tandem firmware? Confirming on hardware decides whether it can be used as the finalized endDate (P05-3).
- Does BolusCompletedHistoryLog.insulinDelivered for an extended bolus cover only the immediate portion, with the remainder in BolexCompletedHistoryLog? pumpX2 field semantics should be checked before the emission layer is built.
- Pump-UI boluses (Mobi quick bolus, t:slim touchscreen boluses, Control-IQ automatic corrections) are never reported by the status path at all — fetchBolusStatus only finalizes a dose TandemKit itself enacted. That belongs to the wasProgrammedByPumpUI point but compounds P05-4: today no path finalizes them.
- LastBolusRequestBuilder never selects LastBolusStatusV3Request on Mobi API >= 3.5; if the V2 message is deprecated on that firmware, queryLastBolusDeliveredVolume would fail on every bolus and the fallbacks in P05-1/P05-2 would become the normal path.
- CLAUDE.md states `historyDoseReporting` has no consumer and that HistoryToDoseMapper is not wired to emission; the code confirms this at HEAD 7d20b2d, so the docs are accurate on this point.
### P06. replacePendingEvents is true when a batch is the complete current set of pending delivery and false only when appending an event that must not disturb a live mutable dose

Guide section: §9 item 6 (with §5).

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 6 of 6 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

The flag is used with the right intent: `false` only for the initial mutable bolus (MedtrumKit pattern) and for dose-less site/cartridge events (OmnipodKit pattern); every other batch is `true`. But `true` batches are not the "complete current set": they are assembled from `getActivePumpEvents`, which only ever contributes the temp basal in `state.basalDose` and never the live bolus in `state.bolusDose`. Any `true` batch emitted while a bolus is running purges that mutable bolus. In steady state it is re-inserted immutable at finalization; after an app relaunch (`bolusProgressReport` is nil) it is never finalized and the next temp basal enact deletes it from IOB. `sendResumePumping` also emits `true` without the temp basal. No test asserts the flag.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P06-1 | Partial | high | verified | true batches omit the live mutable bolus |
| P06-2 | Partial | low | amended | initial bolus emitted with false |
| P06-3 | Conforms | none | verified | siteChange / cartridgeChange emitted with false |
| P06-4 | Partial | medium | verified | resume emits true without the active TBR; dead HSM path |
| P06-5 | Conforms | none | verified | flag semantics across LoopKit variants and Linux shim |
| P06-6 | Non-conforming | low | verified | no test observes replacePendingEvents |

**P06-1 true batches omit the live mutable bolus** (Partial, impact high, verified)

The initial bolus is appended with `false` (correct), but every later `true` batch is assembled from `getActivePumpEvents`, which only includes the temp basal. While a bolus is live, `fetchBasalStatus` (every sync and on qualifying events), `suspendDelivery`, `configureControlIQMode`, and `enactTempBasal` once the time-based `isUnfinalized()` flips false all emit `true` and purge the mutable bolus. Steady state: `fetchBolusStatus` later re-inserts it immutable (StateSync:268), so IOB only dips temporarily. After relaunch `bolusProgressReport` is nil: the guard at 679 no longer blocks, `fetchBolusStatus` clears `bolusDose` without emitting (217-224, 226), and the next Loop temp basal enact purges the persisted mutable bolus permanently — a lost dose. Same on BLE reconnect if the bolusChange event was missed and the bolus finished during the outage.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1703` getActivePumpEvents: `guard state.basalDose.type == .tempBasal else { return [] }` — never consults state.bolusDose
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:161` fetchBasalStatus emits `true` batch (TBR finalize + suspend) with no bolus event; also 183
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:828` suspendDelivery emits `true` batch built only from getActivePumpEvents + suspend
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:679` enactTempBasal bolus guard: `if let bolusProgressReport, bolusProgressReport.isUnfinalized()` — nil after relaunch
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:58` isUnfinalized is a timer estimate `deliveredUnits < total`, not pump state

- Recommendation: Make `getActivePumpEvents` (or a new `pendingEvents()`) also return `state.bolusDose` as a mutable bolus event whenever it is non-nil, so every `true` batch is genuinely complete. On relaunch, rebuild the bolus tracker from persisted `bolusDose` or finalize it from `LastBolusStatus` before any `true` emit.

- Verifier notes:
  - [review:confirm] Same defect as P04-1 viewed through the flag semantics; all cited facts check out: getActivePumpEvents guards on basalDose only (1703), the enactTempBasal guard is a timer estimate (679; DoseProgressReporter:58 deliveredUnits < total) and is nil after relaunch since bolusProgressReport is a plain in-memory var (70) with no restore from the persisted bolusDose (State:244), and fetchBolusStatus returns without emitting when the report is nil (217-227). The intent of false/true usage is right (initial bolus, site/cartridge events at 1062/1071), so 'partial' is fair for this point. High in Loop (lost dose after relaunch); Trio ignores the flag. App-triggered; premise unaffected.

**P06-2 initial bolus emitted with false** (Partial, impact low, amended)

Using `false` here is correct and matches MedtrumKit: it appends the mutable bolus without wiping a running temp basal, and because the TBR row survives at the PumpEvent tier it is re-resolved (not deleted) at the InsulinDeliveryStore tier. The §5 compound pitfall (changed identity + `false`) does not fire, because every finalizing emit (`fetchBolusStatus` StateSync:268, `cancelBolus` 657) uses `true`. However the identity is not stable: initial raw uses programmed units, finalization and cancel use delivered units, so on partial delivery the driver relies on the mutable-purge safety net exactly as the guide warns for MedtrumKit. Correct end state today, latent duplicate if any finalizing path ever switches to `false`.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:600` `replacePendingEvents: false` on the initial mutable bolus event
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:10` raw = `"\(DoseType.bolus.rawValue) \(units) \(ISO date)"` — units is programmed here
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:44` finalizer passes `units: delivered`, so raw differs from the initial when delivery is partial
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:652` cancelBolus: `units: canceledDose.deliveredUnits ?? 0` — raw changes on cancel
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:657` cancel finalization uses default `true`, so the stale mutable row is purged by flag, not identity

- Recommendation: Keep `false` on the initial emit, but build the bolus raw from programmed units and bolusId/startDate in all three sites (initial, finalize, cancel) so identity never changes; finalize by flipping isMutable and setting deliveredUnits only.

- Verifier notes:
  - [review:amend] Lead reviewer re-check: the finding itself concludes the use of replacePendingEvents:false is correct and the end state is right; the residual is the latent identity change rated low in the reviewed P03-1/P16-4. Lowered from medium to low.

**P06-3 siteChange / cartridgeChange emitted with false** (Conforms, impact none, verified)

Both events carry no dose, are immutable, and have a raw fixed at creation from a single date, so they are emitted once and never re-reported. Passing `false` is exactly the OmnipodKit pod-change pattern the guide endorses: a running bolus or temp basal is left untouched. `lastReconciliation` is forwarded unchanged from state, so these emits do not move the trust boundary. No feature flag gates them.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1062` `emitPumpEvents([NewPumpEvent.siteChange(date: date)], replacePendingEvents: false)`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1071` `emitPumpEvents([NewPumpEvent.cartridgeChange(date: date)], replacePendingEvents: false)`
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:62` siteChange: `dose: nil`, raw `"siteChange <ISO date>"`, type .replaceComponent
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:75` cartridgeChange: `dose: nil`, raw `"cartridgeChange <ISO date>"`, type .rewind
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitFillCannulaViewModel.swift:172` UI calls recordSiteChange after a successful cannula fill

- Recommendation: No change needed for the flag. (Whether cartridge change should be `.replaceComponent(.reservoir)` rather than `.rewind` belongs to the event-type checklist item, not this one.)

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P06-4 resume emits true without the active TBR; dead HSM path** (Partial, impact medium, verified)

`sendResumePumping` is the one `true` batch that does not fold in `getActivePumpEvents`. When `state.basalDose` is `.suspend` (the normal case after `suspendDelivery` or a sync that saw the pump suspended) nothing mutable is outstanding and `true` is correct. But if the user suspended on the pump and pressed the app's resume button before the next sync/qualifying-event fetch, `state.basalDose` is still the temp basal: the `true` emit purges that mutable TBR with no finalized replacement, losing its delivered insulin. Window is bounded (~5 min or the pumpSuspend qualifying event). Suspend, resume and basal entries are immutable in the pinned LoopKit, so omitting them from later `true` batches is harmless. `handleHomeScreenMirrorResponse` is unreachable code.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:904` `let events = [NewPumpEvent.resume(...)]` — getActivePumpEvents not called
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:910` `emitPumpEvents(events)` with default `true`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:854` resumeDeliveryAcknowledgingResumeAlarms is a user button path, callable whatever state.basalDose holds
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:473` handleHomeScreenMirrorResponse builds and emits a `true` batch but has no callers in Sources/ or Tests/
  - `reference: loopkit-trio/DoseEntry.swift:31` `init(suspendDate:..., isMutable: Bool = false)` — suspend/resume/basal entries are immutable, so only TBR and bolus are at risk

- Recommendation: In `sendResumePumping`, prepend `getActivePumpEvents(endDate: dose.startDate)` (finalizing any lingering TBR) before the resume event, mirroring suspendDelivery. Delete or wire `handleHomeScreenMirrorResponse`.

- Verifier notes:
  - [review:confirm] Code fact holds: sendResumePumping emits only the resume event with default replacePendingEvents true, without getActivePumpEvents; handleHomeScreenMirrorResponse has no callers. The original trigger (user suspends on the pump screen) is not applicable under the premise, but the same window exists for pump-initiated suspends the premise keeps in scope: an occlusion/auto-off/resume-pump alarm suspends the pump while state.basalDose is still the TBR, and resumeDeliveryAcknowledgingResumeAlarms is precisely the button for that case; if no sync or pumpSuspend fetch ran first, the true emit purges the mutable TBR with no finalized replacement. partial/medium stands.

**P06-5 flag semantics across LoopKit variants and Linux shim** (Conforms, impact none, verified)

The purge semantics TandemKit relies on are identical in the LoopKit fork it builds against and in next-dev, and both default the flag to `true`, matching `emitPumpEvents`' default. The driver therefore does not need variant-specific handling. On Linux the shim only type-checks the call: nothing purges, and the shim's `NewPumpEvent` differs structurally from real LoopKit (event-level `isMutable`, no raw-derived syncIdentifier), so a Linux test run cannot observe misuse of the flag. `notify` dispatches FIFO on the delegate queue, so the `false` initial bolus emit is never reordered after a later `true` batch.

- Evidence:
  - `reference: loopkit-trio/DoseStore.swift:679` `addPumpEvents(..., replacePendingEvents: Bool = true, ...)` — Trio-pinned default true, purge at 704-706
  - `reference: loopkit-nextdev/DoseStore.swift:624` next-dev: identical `if replacePendingEvents { purge mutable == YES }`
  - `LinuxShims/LoopKit/LoopKit.swift:183` shim delegate protocol carries `replacePendingEvents: Bool` but has no DoseStore behind it
  - `LinuxShims/LoopKit/LoopKit.swift:539` shim NewPumpEvent has its own `isMutable` and does not derive syncIdentifier from raw
  - `LinuxShims/LoopKit/LoopKit.swift:844` `notify` is `queue.async` — emits are serialized in call order, so the false-then-true sequence is preserved

- Recommendation: None for conformance. If Linux CI is meant to catch dose-reporting regressions, add a tiny in-test DoseStore stand-in that applies the mutable purge and raw-based matching.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P06-6 no test observes replacePendingEvents** (Non-conforming, impact low, verified)

The mock delegate is the only place the flag can be observed in tests, and it drops it; no test inspects the accumulated events either. The P06-1 and P06-4 gaps (a `true` batch missing a live mutable dose) are exactly the kind of regression a batch-content assertion would catch, and the guide's §11 explicitly recommends idempotency and cancel tests. Given CLAUDE.md notes that earlier dose-path coverage was dropped and not re-created, this is a real, current gap rather than a stale note.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:130` `replacePendingEvents _: Bool,` — the mock discards the flag
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:133` `_pumpEvents += events` accumulates, but no test file reads `pumpEvents`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1733` `func emitPumpEvents(_ events:, replacePendingEvents: Bool = true)` — the only chokepoint, untested

- Recommendation: Record `(events, replacePendingEvents)` pairs in the mock and add StubPumpBluetooth-driven tests: bolus start (`false`, one mutable bolus), TBR enact during bolus (`true` must contain the bolus), cancel (`true`, same raw), relaunch-then-enactTempBasal (bolus still present).

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

Open questions raised by this point:

- Does the host (Loop/Trio) ever call enactTempBasal while a bolus is in progress? If not, the steady-state purge in P06-1 is limited to fetchBasalStatus/suspend paths; the relaunch case stands regardless.
- Does SuspendPumpingRequest cancel an in-progress bolus on Tandem firmware? If so, suspendDelivery's `true` batch purge is always followed by a fetchBolusStatus finalization; if not, the bolus resumes and the purge/reinsert gap is longer.
- The scratchpad LoopKit copies do not include WeakSynchronizedDelegate; the FIFO-ordering claim in P06-5 is verified against the Linux shim and LoopKit's known implementation, not the pinned source.
- docs/tandemkit-history-integration-plan.md:468 shows a planned history-reconciliation emit with `replacePendingEvents: true`; if built as drawn, that batch would also need to include the live bolus/TBR or it will purge them (same class as P06-1).
- fetchBasalStatus emits a `true` batch that does not update lastReconciliation in one branch order (StateSync:159-162 sets it before emit, but handleHomeScreenMirrorResponse never sets it) — relevant to P02, not this point.
### P07. value carries the programmed amount and deliveredUnits the actual amount, both rounded to the pump's supported increment

Guide section: §9 item 7.

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 8 of 8 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

The bolus shape is right: mutable doses carry deliveredUnits nil, and finalized doses carry value=programmed and deliveredUnits from the pump's LastBolusStatus. But the actual amount is floored to the driver's declared 0.05 U grid, coarser than the milliunit wire resolution (and Tandem's 0.01 U bolus increment), systematically under-counting partial deliveries; cancelBolus reports deliveredUnits=0 when the LastBolusStatus read fails or its bolusId mismatches, while the completion path assumes full delivery in the same situation. Temp basal value is derived from the app-side schedule times an integer percent and never reconciled with the pump-reported profile/current rate fetched in the same command; temp basal deliveredUnits is an unrounded value x hours. The history mapper rounds differently (0.001 nearest) but is unwired and behind default-off flags.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P07-1 | Non-conforming | high | verified | cancelBolus deliveredUnits fallback to zero |
| P07-2 | Partial | medium | verified | deliveredUnits floored to 0.05 U grid, coarser than pump |
| P07-3 | Partial | medium | verified | Completion path assumes full delivery when pump read fails |
| P07-4 | Partial | medium | verified | Temp basal value derived from app schedule, pump rate ignored |
| P07-5 | Partial | low | verified | Temp basal deliveredUnits computed, unrounded, not pump-sourced |
| P07-6 | Partial | low | verified | Declared increments coarser than protocol; value not re-rounded |
| P07-7 | Unsure | none | verified | History mapper rounding vs live path; unwired |
| P07-8 | Conforms | none | verified | Mutable/finalized bolus shape (value vs deliveredUnits) |

**P07-1 cancelBolus deliveredUnits fallback to zero** (Non-conforming, impact high, verified)

On cancel, the finalized dose's deliveredUnits is taken from LastBolusStatus; when that read times out, returns a different bolusId (e.g. the pump has not yet stored the cancelled bolus after the 2 s sleep, or a pump-UI bolus intervened), the code substitutes 0. The dose is then emitted immutable with deliveredUnits = 0, so a bolus that delivered several units before cancellation is recorded as delivering nothing. Because the dose is immutable, nothing later corrects it (history emission is not wired). This is the under-count direction: Loop/Trio IOB drops by the full partially-delivered amount.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:641` canceledDose = bolusDose.toDoseEntry(endDate: Date.now) -> immutable, deliveredUnits carried as-is
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:527` guard response.bolusId == bolusId else { ... return nil } — mismatch also yields nil
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:522` write(request) as? LastBolusStatusAbstractResponse else { ... return nil } — no response yields nil
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:636` Thread.sleep(2s) 'Allow the Mobi to store the bolus' — timing-dependent read

- Recommendation: On a failed/mismatched LastBolusStatus read, do not finalize with 0: keep the dose mutable and retry the read (or fall back to the progress-reporter estimate, clearly bounded), and only finalize once the pump reports the delivered volume for the matching bolusId.

- Verifier notes:
  - [review:confirm] All five evidence lines check out. The 'pump-UI bolus intervened' cause is not applicable under the premise, but the finding also names timeout and the post-cancel storage race, which are default-configuration triggers; Control-IQ auto-bolus and the quick-bolus button remain conditional causes of a bolusId mismatch. Both LoopKit variants compute bolus IOB as deliveredUnits ?? programmedUnits, so 0 removes the partial delivery; Trio's store does the same via unitsInDeliverableIncrements. Nonconforming/high is right for the cancel path; no test exercises it (no Tests reference cancelBolus or LastBolusStatus).

**P07-2 deliveredUnits floored to 0.05 U grid, coarser than pump** (Partial, impact medium, verified)

The pump reports the actual delivered volume in milliunits, and Tandem's bolus delivery increment is finer than 0.05 U (0.01 U per the t:slim X2 / Mobi specifications, to be verified). Both finalization paths (natural completion via fetchBolusStatus and cancel) pass that value through roundToSupportedBolusVolume, which is the LoopKit *command* rounding (floor to the driver's 0.05 grid). A cancelled bolus that delivered 1.041 U is reported as 1.00 U; 1.049 U becomes 1.00 U. The error is always downward (up to 0.049 U per bolus) and accumulates across boluses. The repo's own history mapper documents this as the unsafe direction and uses round-to-nearest 0.001 instead, but that path is not wired.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:532` return roundToSupportedBolusVolume(units: Double(response.deliveredVolume) / 1000.0)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:226` supportedBolusVolumes.last(where: { $0 <= units }) ?? 0 — floor, not nearest
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:27` onboardingSupportedBolusVolumes = strideRange(from: 0.05, through: 25.0, by: 0.05)
  - `Sources/TandemCore/Messages/CurrentStatus/LastBolusStatus.swift:46` deliveredVolume = Bytes.readUint32(cargo, 9) — milliunit resolution on the wire
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:158` comment: floor-to-command-grid 'could drop a whole increment and understate delivered IOB (the unsafe direction)'

- Recommendation: Report deliveredUnits at the pump's native reporting resolution using round-to-nearest (reuse HistoryToDoseMapper.roundToReportingResolution) rather than the floor-to-command-grid helper; reserve roundToSupportedBolusVolume for outgoing commands. Confirm the hardware bolus increment (0.01 U) and consider aligning supportedBolusVolumes with it.

- Verifier notes:
  - [review:confirm] Code fact holds: both finalization paths pass the milliunit deliveredVolume through the floor-to-0.05 command grid. Trigger is app-side (cancelBolus, completion via fetchBolusStatus) or a pump abort for alarm reasons, which the premise keeps in scope. Systematic downward error on partial deliveries degrades IOB accounting; medium stands under the default configuration.

**P07-3 Completion path assumes full delivery when pump read fails** (Partial, impact medium, verified)

When CurrentBolusStatus reports bolusId 0 (finished), the driver queries LastBolusStatus for the real delivered volume — the right source. If that read fails or the bolusId mismatches, it finalizes with deliveredUnits = programmed total, i.e. assumes full delivery. A bolus stopped by an occlusion/alarm or a BLE-initiated stop (bolusStatus .stoppedAlarm/.stoppedWireless) that then fails the follow-up read is over-counted. This is the opposite fallback direction from cancelBolus (P07-1), so the two paths disagree about what an unknown delivered amount means. The bolusStatus field, which would at least flag an incomplete delivery, is never read.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:255` if let bolusId = state.bolusDose?.bolusId { actualDelivered = queryLastBolusDeliveredVolume(bolusId: bolusId) }
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:260` events.append(progressReport.getPumpEvent(actualDeliveredUnits: actualDelivered))
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:33` let delivered = actualDeliveredUnits ?? total — falls back to programmed
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:36` units: total, deliveredUnits: delivered — value/deliveredUnits split is correct when the read succeeds
  - `Sources/TandemCore/Messages/CurrentStatus/LastBolusStatusAbstractResponse.swift:15` BolusStatus stopped/stoppedAlarm/stoppedMalfunction/stoppedWireless exist but are never consulted

- Recommendation: Treat a failed LastBolusStatus read as 'delivered amount unknown': keep the dose mutable and retry on the next sync rather than finalizing with a guess. When the read succeeds, also log/assert bolusStatus == .complete when deliveredVolume equals requested.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: 255-256 read LastBolusStatus, 260 finalizes through getPumpEvent, whose fallback is actualDeliveredUnits ?? total (33). The bolusStatus field of the response is not read.

**P07-4 Temp basal value derived from app schedule, pump rate ignored** (Partial, impact medium, verified)

The reported value is baseline x integer percent, floored to the 0.01 grid, which correctly reflects the percent actually programmed (not Loop's raw request) — good. But the baseline is the app's cached schedule via Calendar.current, not the pump's own profileBasalRate returned by the CurrentBasalStatusRequest sent two lines earlier. If the pump profile differs (partial syncBasalRateSchedule failure, segment edited on the pump, segment-boundary off-by-one with strict '<'), or a profile segment changes mid-temp-rate, the pump runs percent x its own rate while the reported value stays fixed; deliveredUnits then inherits the error (P07-5). The finalized dose is never checked against currentBasalRate on later syncs either.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:685` let baselineRate = getScheduledBasalRate() — app-side state.basalRateSchedule, not the pump
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:699` guard let currentBasal = self.bluetooth.write(CurrentBasalStatusRequest()) — fetched but only basalType is used
  - `Sources/TandemCore/Messages/CurrentStatus/CurrentBasalStatus.swift:45` profileBasalRate / currentBasalRate available at 0.001 U/h resolution
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:721` percent = percentForTempBasal(...); absoluteRate = roundToSupportedBasalRate(baselineRate * percent/100)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:284` Int((requestedRate / baseline * 100.0).rounded()) clamped 0...250 — 1% resolution

- Recommendation: Compute the baseline from currentBasal.profileBasalRate (pump truth) and report value from it; on each sync, compare state.basalDose.value with CurrentBasalStatusResponse.currentBasalRate and correct/split the mutable temp basal when a profile segment change alters the running rate.

- Verifier notes:
  - [review:confirm] Code fact holds: baseline is getScheduledBasalRate() from app state while the CurrentBasalStatusResponse fetched at line 699 exposes profileBasalRate that is never read in TandemPumpManager. The premise removes only the 'segment edited on the pump' trigger; partial syncBasalRateSchedule failure, segment-boundary mismatch and a profile segment change mid-temp-rate are driver-internal and remain. Partial/medium unchanged.

**P07-5 Temp basal deliveredUnits computed, unrounded, not pump-sourced** (Partial, impact low, verified)

A finalized temp basal's deliveredUnits is value x elapsed hours with full double precision (e.g. 1.13 U/h x 27.5 min = 0.51792 U), not rounded to any pump increment, and not read back from the pump. Trio's LoopKit consumes it verbatim. The guide asks for deliveredUnits rounded to the pump's increment; Medtrum's plotting/IOB bug was exactly this. Magnitude here is sub-milliunit per dose so the accounting impact is cosmetic, but the value is only as accurate as `value` (see P07-4), and there is no pump-side confirmation (BasalDeliveryHistoryLog / BasalRateChangeHistoryLog are parsed but unused for reconciliation).

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` deliveredUnits: isMutable ? nil : value * (duration / .hours(1))
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:177` actualEndDate = isMutable ? estimatedEndDate : endDate, capped at estimatedEndDate
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` getActivePumpEvents finalizes the running temp basal with endDate ?? Date.now
  - `reference: loopkit-trio/DoseEntry.swift:152` unitsInDeliverableIncrements uses deliveredUnits verbatim when present

- Recommendation: Round temp basal deliveredUnits to the milliunit (0.001 U) reporting resolution, and when the history backfill is enabled use BasalRateChangeHistoryLog/TempRateCompletedHistoryLog to confirm start/end and rate.

- Verifier notes:
  - [review:confirm] Code fact holds: finalized temp basal deliveredUnits is value * (duration / .hours(1)) with no rounding and no pump readback. Trigger is the driver's own finalization path, unaffected by the premise. Sub-milliunit magnitude; low stands.

**P07-6 Declared increments coarser than protocol; value not re-rounded** (Partial, impact low, verified)

The wire carries milliunits for boluses, profile rates and current rate (Tandem specs: 0.001 U/h basal at >=0.1 U/h, 0.01 U bolus — verify), but the driver declares 0.01 U/h and 0.05 U grids and floors to them when reporting. enactBolus does not itself round: value is whatever the host passed, while the wire gets round(units*1000); Loop and Trio round to supportedBolusVolumes first, so in practice value sits on the 0.05 grid, but the driver relies on the host for that. Reported `value` for temp/scheduled basal is floored to 0.01, up to 0.00999 U/h below the pump's 0.001-resolution rate. Small, but it means 'rounded to the pump's supported increment' is only approximately true.

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:238` step = Int(round(0.01 * multiplier)) — supportedBasalRates in 0.01 U/h steps
  - `Sources/TandemCore/Messages/CurrentStatus/IDPSegment.swift:62` profileBasalRate = Bytes.readShort(cargo, 4) — milliunit profile rates on the wire
  - `Sources/TandemKit/PumpManager/TandemPumpManager+SyncBasal.swift:222` basalMilliunits = Int((scheduleItem.value * 1000.0).rounded())
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:551` milliUnits = max(0, Int((units * 1000).rounded())) — bolus sent at 0.001 U resolution
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:578` UnfinalizedDose(units: units, ...) — value is the host's unrounded request

- Recommendation: Round `value` inside the driver (roundToSupportedBolusVolume in enactBolus) so the reported amount equals the wire amount regardless of host; document that the declared grids are UI-selection grids and use milliunit round-to-nearest for anything read back from the pump.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P07-7 History mapper rounding vs live path; unwired** (Unsure, impact none, verified)

The history-derived path correctly keeps value=bolusSize (programmed) and deliveredUnits=insulinDelivered (actual), rounded to nearest 0.001 U with Float32 noise stripped, and leaves temp basal deliveredUnits nil so LoopKit derives it. This is the better-conforming implementation, but it has no production caller (only tests reference HistoryToDoseMapper) and is gated by two default-off flags. Because it rounds differently from the live path (0.05 floor) and mints different raw identifiers, once wired the same bolus could be reported twice with different deliveredUnits. BasalRateChange value is a raw Float (0.8999999 style noise) and unrounded. Cannot judge steady-state behaviour of an emission layer that does not exist yet.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:162` (units * 1000).rounded() / 1000 — round-to-nearest milliunit
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:188` value from activation.bolusSize (Float), deliveredUnits from completion.insulinDelivered (Float)
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:277` value: Double(basalChange.commandBasalRate) — Float noise not rounded
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:36` historyBackfill / historyDoseReporting default false
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:173` historyDoseReporting is self[.historyBackfill] && self[.historyDoseReporting]

- Recommendation: When wiring the emission layer, make the live paths adopt roundToReportingResolution so both report identical deliveredUnits, apply it to BasalRateChangeHistoryLog.commandBasalRate too, and add tests asserting live-path bolus/temp-basal value and deliveredUnits rounding (none exist today).

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P07-8 Mutable/finalized bolus shape (value vs deliveredUnits)** (Conforms, impact none, verified)

Across enact, natural completion and cancel, the DoseEntry keeps value = the programmed units and puts the pump-reported amount in deliveredUnits; in-progress doses carry deliveredUnits nil, the MedtrumKit shape the guide endorses. The 1 s progress estimate (floored to 0.05) is confined to the DoseProgressReporter and never reaches hasNewPumpEvents. Persisted UnfinalizedDose round-trips value and deliveredUnits unchanged, so an app relaunch does not alter amounts. The remaining P07 defects (P07-1..P07-6) are about *which* number lands in deliveredUnits and how it is rounded, not about the field split itself.

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:161` deliveredUnits: isMutable ? nil : deliveredUnits — no delivered amount while in progress
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:587` dose.toDoseEntry(isMutable: true) emitted at enact time with value = programmed units
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:37` finalized: units: total (programmed), deliveredUnits: delivered (pump-reported)
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:77` progress estimate floored to 0.05 only feeds DoseProgress UI, not the DoseStore
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:244` bolusDose value/deliveredUnits persisted as Doubles, not re-rounded on relaunch

- Recommendation: Keep this shape; add a unit test pinning value=programmed and deliveredUnits=pump-reported for completion and cancel so the rounding fixes above cannot regress the split.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

Open questions raised by this point:

- Hardware increments should be confirmed against the current t:slim X2 and Mobi user guides: this audit assumes 0.001 U/h basal (at >=0.1 U/h) and 0.01 U bolus delivery increments; if the bolus increment is actually 0.05 U the severity of P07-2 drops to low.
- After an app relaunch, bolusProgressReport is nil (not persisted); fetchBolusStatus then clears state.bolusDose on .alreadyDeliveredOrInvalid (StateSync 217-224) without emitting a finalized dose, so the deliveredUnits for that bolus is never reported at all. This is a P04/P05 (finalization/re-report) issue rather than P07 but directly affects whether any 'actual amount' reaches Loop.
- cancelBolus mints the finalized bolus raw as 'bolus <deliveredUnits> <startDate>' (TandemPumpManager.swift 652) while enactBolus used the programmed units, so the identity changes at cancel; covered under P03, but it interacts with P07-1 because the zero-delivered dose is inserted under a new identity while the mutable original is purged only via replacePendingEvents.
- SetTempRateRequest is declared mobiOnly / minApi mobiApiV3_5 (SetTempRate.swift 12-13); whether t:slim X2 has any temp-rate path in this driver was not verified and affects which pump the temp basal findings apply to.
- fetchBasalStatus never emits anything when the pump reports .tempBasal while the driver thinks it is on scheduled basal (StateSync 141-187), so a temp rate set on the pump UI has no reported value/deliveredUnits at all (P08 territory).
- handleHomeScreenMirrorResponse (StateSync 473) emits basal doses but has no caller; if it is revived it should use the same rounding rules.
- The guide's decisionId and the historyDoseReporting emission layer do not exist in the Trio-pinned LoopKit / this codebase; the CLAUDE.md claim that HistoryToDoseMapper is 'not wired to any emission path' matches the code at HEAD.
### P08. wasProgrammedByPumpUI is set for user-initiated doses and they are reconciled from pump history (UI-capable pumps only)

Guide section: §9 item 8 (with §7).

Overall: **Not applicable today (residual findings: Partial)** (auditor's own overall: Not applicable; computed as the most conservative verdict among the surviving findings). 6 of 6 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

Re-audited under the screenless-pump premise; the UI-capable reading is summarised in the method section.

Under the screenless-Mobi premise, §9 item 8 does not apply in the default configuration: the only pump-side dose sources are the quick-bolus button, which TandemKit turns off on every sync unless quickBolusButtonSupport (default off) is enabled, and Control-IQ, which is reachable only through the controlIQSupport flag (default off) and then blocks TandemKit's own dosing. The UI-capable reading rated this point nonconforming/high; under the premise it is not_applicable/none by default, with the "boluses TandemKit never sees" finding surviving only conditionally (nonconforming/high if either flag is turned on, plus a narrow default-config residual when the pump rejects the quick-bolus disable). Pump-initiated stops (alarm suspends, aborted boluses) are accounted for without needing the flag, which is correct for a Loop-only pump. The dormant history path (HistoryToDoseMapper, historyDoseReporting) carries latent app-side metadata and identity gaps that should be fixed before it is ever switched on, but has no effect today. Code audited at HEAD f008ec40, which differs from 7d20b2dc only by an added docs file.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P08-1 | Not applicable | none | verified | Applicability: default configuration has no user-programmable pump-side dose source |
| P08-2 | Partial | low | verified | Conditional: quick-bolus and Control-IQ boluses are invisible to the live status path |
| P08-3 | Not applicable | none | verified | Conditional: Control-IQ basal modulation and pump-set temp rates produce no dose |
| P08-4 | Conforms | none | verified | Pump-initiated stops (alarm suspends, aborted boluses) are accounted for without the flag |
| P08-5 | Partial | low | verified | Latent: dormant history mapper would misflag Loop's own boluses and omit `automatic` |
| P08-6 | Partial | low | verified | Latent: no identity bridge between optimistic raw and history identifiers (app-triggered once history emission is enabled) |

**P08-1 Applicability: default configuration has no user-programmable pump-side dose source** (Not applicable, impact none, verified)

With no screen, the Mobi's only user-initiated dose sources are the quick-bolus button and Control-IQ. TandemKit re-reads PumpGlobals and issues SetQuickBolusSettingsRequest(enabled: false) on every sync while quickBolusButtonSupport is off, and Control-IQ can only be turned on from TandemKit's own settings screen when controlIQSupport is on (or by Tandem's phone app, excluded by the premise). Both flags default to false. So in the default configuration every dose is Loop-commanded and the guide's §7/§9-8 requirement (flag user-initiated doses, reconcile them from history) has nothing to apply to; leaving wasProgrammedByPumpUI false is what the guide prescribes for Loop-only pumps. This is the premise's archetype, matched by code.

- Evidence:
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:38` controlIQSupport, quickBolusButtonSupport, historyBackfill, historyDoseReporting all `return false` by default
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:362` guard !state.featureFlags.quickBolusButtonSupport, state.quickBolusEnabled == true else { return }
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:432` self.enforceQuickBolusDisabled() — runs on every syncPumpData after a fresh PumpGlobals read (line 427-429)
  - `Sources/TandemKitUI/ViewModels/Settings/TandemKitSettingsViewModel.swift:237` guard pumpManager.state.featureFlags.controlIQSupport else { — switching Control-IQ on is flag-gated
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:517` if state.useControlIQ, activationType.isAutomatic { — automatic Loop boluses blocked under Control-IQ

- Recommendation: Document in the driver's user-facing notes that the quick-bolus button is disabled by TandemKit and that enabling quickBolusButtonSupport or Control-IQ changes the dose-accounting contract (see P08-2). Keep both flags default-off until P08-2 is addressed.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P08-2 Conditional: quick-bolus and Control-IQ boluses are invisible to the live status path** (Partial, impact low, verified)

fetchBolusStatus (from sync and from the .bolusChange qualifying event) emits a dose only when a TandemDoseProgressReporter exists, i.e. enactBolus ran in this process. A bolus from the quick-bolus button or a Control-IQ auto-correction arrives as .delivering with a foreign bolusId and returns silently; on completion state is cleared with no event, so it never reaches IOB. The response's bolusSource, which would let the driver set wasProgrammedByPumpUI/automatic, is unused. In the default configuration this is reachable only in a narrow residual: between pairing and the first successful sync, or when the pump rejects the disable (tested at line 109). With quickBolusButtonSupport on, or with Control-IQ enabled, this becomes nonconforming with high impact (lost boluses).

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:226` guard let progressReport = bolusProgressReport else { return } — a .delivering bolus Loop did not start is ignored
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:216` if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil { …clear state, no event }
  - `Sources/TandemKit/PumpManager/QualifyingEventFetch.swift:49` case is CurrentBolusStatusRequest: return .bolusStatus — .bolusChange routes into the same guarded fetch
  - `Sources/TandemCore/Messages/CurrentStatus/CurrentBolusStatus.swift:85` public var bolusSource: BolusSource? — never read anywhere under Sources/TandemKit
  - `Sources/TandemCore/Messages/Models/BolusDelivery.swift:4` case quickBolus = 0 … controlIQAutoBolus = 7, bluetoothRemoteBolus = 8

- Recommendation: In fetchBolusStatus, when status is .delivering or the id is foreign, emit a dose keyed by HistoryLogSyncIdentifier.bolus with wasProgrammedByPumpUI = (bolusSource != .bluetoothRemoteBolus) and automatic = (bolusSource == .controlIQAutoBolus), finalizing from LastBolusStatus. Until then, make enabling quickBolusButtonSupport or Control-IQ surface a warning that pump-side boluses are not counted in IOB, and consider retrying the quick-bolus disable when the pump rejects it.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: the reporter guard (226) and the clear-without-emit branch (217) are as described; bolusSource is never read anywhere under Sources/TandemKit. Conditional under the premise; low by default.

**P08-3 Conditional: Control-IQ basal modulation and pump-set temp rates produce no dose** (Not applicable, impact none, verified)

A temp rate the app did not set, or Control-IQ raising/attenuating basal, would either fall through fetchBasalStatus's change block with no emission (.tempBasal) or be reported as the app's scheduled rate (.basal). On a screenless Mobi with Tandem's app not in use, the only way to reach this is Control-IQ, which is off by default and gated behind controlIQSupport; when it is on, TandemKit already refuses its own temp basals and automatic boluses, so the app is no longer the dosing authority. Under the default configuration there is no trigger. Under Control-IQ the impact would be high (the pump's actual basal delivery is unaccounted for), but the premise treats that as a conditional mode, not the default.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:141` if activeBasalType != state.basalDose.type { — only .suspend and .basal branches follow; .tempBasal falls through
  - `Sources/TandemCore/Messages/CurrentStatus/CurrentBasalStatus.swift:44` basalType: 0x01 → .suspend, 0x02 → .tempBasal, default → .basal
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:170` basalRate: getScheduledBasalRate() — emitted basal is the app's schedule, not the pump's currentBasalRate
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:473` func handleHomeScreenMirrorResponse — zero call sites under Sources/
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:673` guard !state.useControlIQ else { — TandemKit stops setting temp basals when Control-IQ is on

- Recommendation: Before making controlIQSupport generally available, report CurrentBasalStatusResponse.currentBasalRate (and TempRateRequest percent/remaining for 0x02) as a mutable .tempBasal/.basal dose with automatic = true and a stable tempRateId-based raw, so Control-IQ modulation reaches IOB when the user opts into it.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P08-4 Pump-initiated stops (alarm suspends, aborted boluses) are accounted for without the flag** (Conforms, impact none, verified)

The in-scope pump-side events under the premise are stops the pump initiates on its own: occlusion, empty cartridge, auto-off, malfunction, cartridge-change mode, and a bolus it aborts for those reasons. These are detected (sync or pumpSuspend/pumpResume qualifying event) and emitted as suspend doses, and an aborted Loop bolus is finalized from LastBolusStatus.deliveredVolume rather than assumed complete. None of these is a user-programmed dose, so leaving wasProgrammedByPumpUI false is the correct value per §7 for a Loop-only pump; no flag is missing. Detection-time (not pump-time) start stamps for suspends are a timing matter covered by other points, not a flag matter.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:153` let dose = UnfinalizedDose(suspendStartTime: now) — pump-detected suspend emitted as a suspend dose
  - `Sources/TandemKit/PumpManager/QualifyingEventFetch.swift:80` if !events.isDisjoint(with: [.pumpSuspend, .pumpResume]) { needed.insert(.basalStatus) }
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:257` actualDelivered = queryLastBolusDeliveredVolume(bolusId: bolusId) — aborted bolus finalized with the pump's delivered volume
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:197` DoseEntry(suspendDate: startDate, automatic: automatic) — wasProgrammedByPumpUI left at default false

- Recommendation: No change for this item. Keep the suspend/resume and aborted-bolus paths as they are; timing accuracy of the suspend start belongs to the suspend/resume audit point.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P08-5 Latent: dormant history mapper would misflag Loop's own boluses and omit `automatic`** (Partial, impact low, verified)

The mapper's derivation is the right shape, but under the premise every bolus is Loop's own, and nothing in the driver can supply isCommandedBolus: only the in-flight bolusDose.bolusId is kept and it is cleared on completion, so once an emission layer exists every completed Loop bolus found in history would be flagged wasProgrammedByPumpUI = true. Trio ignores that flag (no reference in its consumer), but it does read `automatic`, which the mapper never sets, so history-derived boluses would be recorded as SMBs. Today none of this fires: mapToEvents has no production caller and historyDoseReporting has no consumer. Under Control-IQ the gap would matter more, since auto-boluses would be indistinguishable from user boluses.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:194` wasProgrammedByPumpUI: !isCommandedBolus(completion.bolusId) — only place the flag is set
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:42` isCommandedBolus: (Int) -> Bool — caller-supplied; no production caller of mapToEvents exists
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:263` state.bolusDose = nil — the only commanded bolusId is forgotten at completion
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:184` let dose = DoseEntry(type: .bolus, … — no `automatic:` argument
  - `Trio/Sources/APS/Storage/PumpHistoryStorage.swift:137` newBolusEntry.isSMB = dose.automatic ?? true — Trio treats a nil `automatic` as an SMB

- Recommendation: Before wiring the emission layer: persist a bounded set of commanded bolusIds in TandemPumpManagerState for the predicate, and set `automatic` from BolusDeliveryHistoryLog.bolusSourceEnum (controlIQAutoBolus → true, bluetoothRemoteBolus → the activationType Loop recorded).

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P08-6 Latent: no identity bridge between optimistic raw and history identifiers (app-triggered once history emission is enabled)** (Partial, impact low, verified)

§7's history reconciliation is a UI-capable requirement and does not apply under the premise, and TandemKit indeed finalizes Loop's boluses from LastBolusStatus rather than history. This finding survives only as an app-side latent risk: the driver has built flags and a mapper for history-derived doses, but the optimistic raw minted by enactBolus/cancelBolus and the HistoryLogSyncIdentifier raw minted by the mapper are different bytes for the same bolus. If an emission layer were added and historyDoseReporting switched on without first unifying identities, every Loop bolus would appear twice (Trio dedups by date+type, which would only partially mask it). Nothing fires today: both flags default off and no emitter exists.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:10` raw: "\(DoseType.bolus.rawValue) \(units) \(dateFormatter.string(from: date))" — optimistic identity
  - `Sources/TandemKit/PumpManager/History/HistoryLogSyncIdentifier.swift:45` Nothing emits these identifiers yet — NewPumpEvent's raw values are still built from the dose type, volume and timestamp
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:183` let raw = HistoryLogSyncIdentifier.bolus(pumpSerial: pumpSerial, bolusId: completion.bolusId)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:584` bolusId: permissionResponse.bolusId — pump id is known at command time but not used in raw
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:59` guard pumpManager?.state.featureFlags.historyBackfill == true else { return } — default off, history never read

- Recommendation: Make enactBolus/cancelBolus/getPumpEvent use HistoryLogSyncIdentifier.bolus(pumpSerial:bolusId:) as raw once the serial is known (and tempRateId for temp basals) before any history emission is wired, so history confirmations update in place. Note in the flag's description that it must not be enabled before that change lands.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

Open questions raised by this point:

- The premise states the host disables closed loop when Control-IQ is on, but the Trio checkout has no reference to Control-IQ or to TandemKit's useControlIQ/controlIQEnabled state; the only enforcement found is TandemKit refusing automatic boluses and temp basals (TandemPumpManager.swift:517, 673). How Trio actually learns to open-loop needs confirming.
- Whether a quick bolus or Control-IQ auto-bolus appears in CurrentBolusStatusResponse with bolusSource .quickBolus/.controlIQAutoBolus (vs only in history) needs a hardware capture before the P08-2 recommendation is implemented.
- How long the default-config residual window is in practice: the quick-bolus lockout requires a successful PumpGlobals read and SetQuickBolusSettings in the same sync; a Mobi paired with the button already on could accept a quick bolus before the first sync, and the disable is not retried within a sync when the pump rejects it.
- Whether the Mobi permits Tandem's own phone app to remain paired alongside TandemKit; the premise assumes not, and a concurrently paired Tandem app would reintroduce GUI-source boluses (bolusSource .gui) that P08-2 would also miss.
### P09. decisionId is threaded from enactBolus/enactTempBasal through to the DoseEntry

Guide section: §9 item 9.

Overall: **Not applicable today (residual findings: Partial)** (auditor's own overall: Not applicable; computed as the most conservative verdict among the surviving findings). 4 of 4 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

decisionId does not exist in the LoopKit TandemKit builds against. Trio's pinned loopandlearn fork (rev 0229bb18, unit-tests.yml:46) declares enactBolus(units:activationType:) and enactTempBasal(unitsPerHour:for:) with no decisionId, and its DoseEntry has no such field; the Linux shim matches. TandemKit's signatures mirror the fork exactly and the repo has zero references to decisionId, so the item is not applicable today. Forward-looking: next-dev makes decisionId a required DoseEntry init parameter, and TandemKit has no slot for a host-side id — UnfinalizedDose carries only a pump-assigned bolusId (persisted) and reduces activationType to a Bool. The surrogate metadata actually used (automatic/manuallyEntered) is lossy and inconsistent between the mutable and finalized bolus, with manuallyEntered=true applied to pump-delivered boluses.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P09-1 | Not applicable | none | verified | decisionId absent from the pinned LoopKit API |
| P09-2 | Partial | none | verified | Readiness: correlation id slot for a future decisionId |
| P09-3 | Partial | medium | verified | activationType surrogate is lossy and inconsistent across bolus lifecycle |
| P09-4 | Partial | low | verified | Temp basal and history-derived doses: automatic flag conventions |

**P09-1 decisionId absent from the pinned LoopKit API** (Not applicable, impact none, verified)

The guide's §9 item 9 presupposes the next-dev API where enactBolus/enactTempBasal receive `decisionId: UUID?` and DoseEntry stores it. TandemKit is built (per Package.swift and CI) against Trio's loopandlearn fork, whose PumpManager protocol and DoseEntry have no decisionId at all, and the Linux shim matches. TandemKit's method signatures are the fork's verbatim; a repo-wide grep for `decisionId` returns nothing. There is therefore nothing to thread and nothing to violate on the current target, on any path (steady state, first sync, reconnect, relaunch).

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:510` enactBolus takes `activationType: BolusActivationType,` and no decisionId
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:663` enactTempBasal(unitsPerHour:for:completion:) — no decisionId parameter
  - `reference: loopkit-trio/PumpManager.swift:199` fork protocol: `func enactBolus(units: Double, activationType: BolusActivationType, completion:`
  - `reference: loopkit-trio/DoseEntry.swift:40` fork DoseEntry init has no decisionId parameter
  - `LinuxShims/LoopKit/LoopKit.swift:272` Linux shim enactBolus likewise has no decisionId

- Recommendation: No action for the current Trio target. Track the requirement against the LoopKit bump that introduces decisionId (see P09-2).

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P09-2 Readiness: correlation id slot for a future decisionId** (Partial, impact none, verified)

For boluses a durable correlation key exists: the pump-assigned bolusId is stored on UnfinalizedDose, persisted in manager state, and used by HistoryLogSyncIdentifier so a history confirmation can match the optimistic report. A future decisionId could be stored alongside it. But nothing in UnfinalizedDose, its rawValue, or toDoseEntry has a slot for a host-supplied UUID, and temp basals carry no id of any kind. On next-dev, DoseEntry's initializer makes decisionId a required argument, so every construction site (UnfinalizedDose.toDoseEntry, the DoseEntry extension, HistoryToDoseMapper) would need changes, and the value would have to be persisted in rawValue — not in the in-memory TandemDoseProgressReporter — to survive relaunch.

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:9` `public var bolusId: Int?` — the only correlation id on a tracked dose
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:585` `bolusId: permissionResponse.bolusId` — id is pump-assigned, not host-assigned
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:141` `raw["bolusId"] = bolusId` — bolusId survives relaunch via rawValue
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:444` `raw["bolusDose"] = bolusDose.rawValue` persists the in-flight bolus
  - `Sources/TandemKit/PumpManager/History/HistoryLogSyncIdentifier.swift:102` `static func bolus(pumpSerial:bolusId:)` mints a stable identity from the pump bolusId

- Recommendation: When adopting a decisionId-bearing LoopKit: add `decisionId: UUID?` to UnfinalizedDose (bolus and tempBasal inits, rawValue round-trip) and pass it through toDoseEntry; give temp basals a stable identity (pump tempRateId if the set response exposes it).

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P09-3 activationType surrogate is lossy and inconsistent across bolus lifecycle** (Partial, impact medium, verified)

Because the fork has no decisionId, the only Loop-side provenance TandemKit records is `automatic`/`manuallyEntered`. The in-progress and cancel representations (UnfinalizedDose.toDoseEntry) carry `automatic` only, while the normal-completion representation (TandemDoseProgressReporter → DoseEntry.bolus) also sets `manuallyEntered = true` for `.manualNoRecommendation`. So the same bolus flips metadata between mutable and finalized, and differs depending on whether it completed or was cancelled. In LoopKit, `manuallyEntered` denotes insulin the user logged that the pump did not deliver; `getManuallyEnteredDoses`/`deleteAllManuallyEnteredDoses` select on it. Flagging a pump-delivered bolus this way misdescribes it and exposes it to host flows that manage external insulin. The fork's getNormalizedDoseEntries does not filter on the flag, so IOB inside LoopKit is unaffected.

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:33` `automatic = activationType.isAutomatic` — five-case enum collapsed to a Bool
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:163` mutable/cancel bolus DoseEntry sets `automatic:` only; manuallyEntered left false
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:17` `private let activationType: BolusActivationType` kept only in memory
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:35` finalized event built via DoseEntry.bolus(... activationType:)
  - `Sources/TandemCore/Common/Extensions/DoseEntry.swift:24` `manuallyEntered: activationType == .manualNoRecommendation` on a pump-delivered bolus

- Recommendation: Never set manuallyEntered on pump-delivered doses; derive `automatic` from activationType in one place (UnfinalizedDose) and use it for mutable, cancelled and finalized entries alike. Persist activationType (or automatic) in rawValue rather than the reporter.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: UnfinalizedDose keeps only automatic (33, 163); the reporter's activationType (17) is memory-only and feeds DoseEntry.bolus, which sets manuallyEntered for .manualNoRecommendation (Extensions/DoseEntry.swift:24). Same defect as P22-2.

**P09-4 Temp basal and history-derived doses: automatic flag conventions** (Partial, impact low, verified)

With no decisionId or activation type available for temp basals in the fork API, TandemKit assumes every enacted temp basal is automatic, matching the common Loop-only-driver convention; this is acceptable but is duplicated in an unused DoseEntry.tempBasal helper that can drift. History-derived boluses (the path that would surface Control-IQ automatic corrections and pump-UI quick boluses on this UI-capable pump) leave `automatic` nil and rely solely on wasProgrammedByPumpUI. That mapper is not connected to any emission path today (only tests call it), so this is a design note rather than a live defect.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:768` `automatic: true,` hard-coded for every Loop-commanded temp basal
  - `reference: loopkit-trio/PumpManager.swift:215` fork enactTempBasal passes no automatic/activation info to the driver
  - `Sources/TandemCore/Common/Extensions/DoseEntry.swift:60` unused DoseEntry.tempBasal helper also hard-codes `automatic: true`
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:194` history bolus sets `wasProgrammedByPumpUI: !isCommandedBolus(...)` but never `automatic`
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:19` only caller of HistoryToDoseMapper().mapToEvents is a test — mapper not wired into emission

- Recommendation: Remove or route through the unused DoseEntry.tempBasal helper. When the history mapper is wired, set `automatic` for Control-IQ-originated boluses (distinguishable from user quick boluses via bolus type/source fields) so host UIs classify them correctly.

- Verifier notes:
  - [review:confirm] Code fact holds: automatic: true is hard-coded for enacted temp basals and duplicated in the unused DoseEntry.tempBasal helper; the history mapper sets wasProgrammedByPumpUI but not automatic and has no caller outside tests. Under the premise the Loop-only convention (automatic temp basals) is the correct default, and the Control-IQ/quick-bolus classification only matters under the conditional sources. The live residue is the unwired mapper and the drift-prone helper, so partial/low stands as a design note.

Open questions raised by this point:

- Does Trio ever call DoseStore.deleteAllManuallyEnteredDoses or present manuallyEntered==YES doses as 'external insulin' in its UI? If so, a finalized .manualNoRecommendation bolus (P09-3) could be deleted or misclassified by the host; this cannot be verified from the TandemKit repo.
- Does SetTempRateResponse (or TempRateResponse) expose the pump's tempRateId at command time? If it does, temp basals could get a stable pump-side identity analogous to bolusId, which any future decisionId mapping could ride on. Not verified in this audit.
- After an app relaunch mid-bolus, bolusProgressReport is nil (TandemPumpManager.swift:70, in-memory) and fetchBolusStatus returns before emitting the finalized bolus event (TandemPumpManager+StateSync.swift:226 `guard let progressReport = bolusProgressReport else { return }`). This concerns finalization (other checklist items), not decisionId, but it also means any provenance kept on the reporter is lost across relaunch.
- The guide (§2) describes DoseEntry.decisionId as an existing field; that is true only for loopkitdev/LoopKit next-dev. Trio's pinned loopandlearn fork and the Linux shim have no such field, so guide and target API disagree on this point.
### P10. Suspend/resume, prime, alarm, and pump-replacement events are emitted with appropriate PumpEventType values

Guide section: §9 item 10.

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 8 of 8 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

App-commanded suspend/resume are emitted as proper .suspend/.resume dose events, and the UI cartridge/cannula wizards emit .rewind and .replaceComponent(.infusionSet). Gaps: a resume performed on the pump itself is detected by CurrentBasalStatus polling and emitted as a .basal dose with no .resume, which can leave an open suspend in Loop/Trio (the only correct handler, handleHomeScreenMirrorResponse, has no callers). No .prime event is ever emitted despite tubing/cannula fill volumes being known. No live path emits NewPumpEvent(type: .alarm); the history mapper does (without alarmType) but is unwired and behind two default-off flags. Site/cartridge changes made on the pump UI are never detected (CannulaFilled/CartridgeFilled logs ignored). No tests assert emitted PumpEventType on manager paths.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P10-1 | Conforms | none | verified | App-commanded suspend/resume event types |
| P10-2 | Non-conforming | medium | amended | Pump-UI resume emitted as .basal, never .resume |
| P10-3 | Conforms | none | amended | Cartridge change as .rewind, wizard-only |
| P10-4 | Conforms | none | amended | Site change as .replaceComponent(.infusionSet), wizard-only |
| P10-5 | Non-conforming | low | amended | No .prime event for tubing or cannula fills |
| P10-6 | Non-conforming | low | verified | Alarms not emitted as pump events on any live path |
| P10-7 | Not applicable | none | verified | Pump replacement / deactivation events |
| P10-8 | Partial | none | verified | Test coverage of emitted PumpEventType |

**P10-1 App-commanded suspend/resume event types** (Conforms, impact none, verified)

suspendDelivery and sendResumePumping build DoseEntry(suspendDate:)/DoseEntry(resumeDate:) and wrap them with NewPumpEvent.suspend/.resume. The factories pass no explicit PumpEventType, so the type comes from LoopKit's `type ?? dose?.type.pumpEventType` inference, which yields .suspend/.resume on Apple builds (Trio-pinned and next-dev LoopKit behave identically here). A suspend performed on the pump and seen by CurrentBasalStatus polling (fetchBasalStatus) is also emitted as .suspend. Holds in steady state, after reconnect (qualifying .pumpSuspend/.pumpResume force a basalStatus fetch) and after relaunch (basalDose persisted). Only the Linux shim leaves `type` nil, which affects Linux tests, not production.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:822` events.append(NewPumpEvent.suspend(dose: suspendDose.toDoseEntry(), date: suspendDose.startDate))
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:904` let events = [NewPumpEvent.resume(dose: dose.toDoseEntry(), date: dose.startDate)]
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:197` case .suspend: return DoseEntry(suspendDate: startDate, automatic: automatic)
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:46` static func suspend(...) passes no explicit `type:`; relies on LoopKit inference
  - `reference: loopkit-trio/NewPumpEvent.swift:37` self.type = type ?? dose?.type.pumpEventType

- Recommendation: Pass `type: .suspend` / `type: .resume` explicitly in the NewPumpEvent factories so the type does not depend on LoopKit inference and is identical on the Linux shim. Confirm `DoseType.pumpEventType` in the pinned LoopKit maps suspend/resume as expected (file not in the reference set).

- Verifier notes:
  - [review:confirm] Code fact holds: suspend/resume events wrap DoseEntry(suspendDate:)/(resumeDate:) and rely on LoopKit type inference, with pump-side suspends detected by fetchBasalStatus also emitted as .suspend. Pump-initiated stops (occlusion, auto-off, cartridge change) remain in scope under the premise and take the same path. Conforms/none unchanged.

**P10-2 Pump-UI resume emitted as .basal, never .resume** (Non-conforming, impact medium, amended)

When the user resumes on the pump (t:slim X2 touchscreen, Tandem app, or after clearing an alarm), the only live detection path is fetchBasalStatus, which sees basalType .basal while state.basalDose is .suspend and emits a .basal dose only — no .resume. The trio-pinned DoseStore extends an unclosed suspend to `end`, and InsulinMath.reconciled() (not in the reference set, so unverified on disk) closes a suspend only at a .resume, so Loop can keep treating delivery as suspended after the pump has resumed, under-counting basal IOB. The correct suspend->resume transition exists in handleHomeScreenMirrorResponse, but grep finds no caller (dead code) and it mislabels the resume as NewPumpEvent.basal. The history mapper emits .resume correctly but is unwired and behind default-off flags.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:166` if activeBasalType == .basal { ... } — branch reached when state.basalDose.type == .suspend
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:173` events.append(NewPumpEvent.basal(dose: dose.toDoseEntry(), ...)) — no resume event
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:492` handleHomeScreenMirrorResponse: if state.basalDose.type == .suspend { dose = UnfinalizedDose(resumeStartTime: ...) }
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:504` ...but wraps it as NewPumpEvent.basal (title "Basal", raw "basal ...")
  - `Sources/TandemKit/PumpManager/QualifyingEventFetch.swift:80` pumpSuspend/pumpResume -> .basalStatus -> fetchBasalStatus (the only live detection path)

- Recommendation: In fetchBasalStatus, when the previous basalDose is .suspend and the pump reports .basal (or .tempBasal), emit NewPumpEvent.resume first, then the basal dose. Fix or delete handleHomeScreenMirrorResponse's NewPumpEvent.basal wrapping of a resume dose. Add a test asserting the delegate receives a .resume event.

- Verifier notes:
  - [review:amend] Code facts hold: with state.basalDose == .suspend and the pump reporting .basal, fetchBasalStatus emits only a .basal event; the trio-pinned reconciled() closes an open suspend only on .resume/.tempBasal, and Trio ignores .basal and treats a trailing PumpSuspend as suspended to now (unbounded). Two corrections: (1) the 'mislabel' point is cosmetic — NewPumpEvent derives type from dose.type, so the dead HSM path would still be a .resume; (2) under the premise the stated trigger (resume on pump screen) is not applicable. Every default-config Mobi resume goes through sendResumePumping, which emits .resume and sets state to .resume so the line-143 guard short-circuits. The only default-config trigger left is a ResumePumpingRequest whose response is lost (write returns nil on timeout) after the pump resumed; Basal-IQ auto-resume is a t:slim X2 feature. Consequence when triggered is severe in Trio (unbounded open suspend); likelihood is a rare BLE race, so medium; would be high for a UI-capable pump or Basal-IQ.

**P10-3 Cartridge change as .rewind, wizard-only** (Conforms, impact none, amended (auditor said Partial))

A cartridge change performed through TandemKit's wizard is reported as a dose-less .rewind event with replacePendingEvents:false (correct per guide §5) and a date-stamped raw. .rewind is the legacy Medtronic-era reservoir-change type that Loop/Trio have historically consumed (e.g. Nightscout 'Insulin Change'); .replaceComponent(.reservoir) is the newer semantic type the guide's §10 points to. DoseStore itself does not act on either (it only inspects .prime), so this is metadata only. The gap is coverage: a cartridge change done on the pump's own UI (t:slim X2) is never detected — CartridgeFilledHistoryLog is parsed by TandemCore but HistoryToDoseMapper drops it, and the mapper is unwired anyway.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:78` type: .rewind
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1071` emitPumpEvents([NewPumpEvent.cartridgeChange(date: date)], replacePendingEvents: false)
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitChangeCartridgeViewModel.swift:319` pumpManager?.recordCartridgeChange() — only caller, inside the app's wizard
  - `Sources/TandemCore/Messages/HistoryLog/CartridgeFilledHistoryLog.swift:4` public static let typeId = 33 — parsed but never mapped
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:118` default: continue — CartridgeFilled/CannulaFilled/TubingFilled logs dropped

- Recommendation: Keep .rewind unless Trio/Loop consumers are confirmed to handle .replaceComponent(.reservoir); document the choice. Add CartridgeFilledHistoryLog -> cartridgeChange mapping (raw = HistoryLogSyncIdentifier) so pump-UI cartridge changes are captured once history emission is wired.

- Verifier notes:
  - [review:amend] Code fact holds: .rewind is emitted with replacePendingEvents:false from recordCartridgeChange, whose only caller is the TandemKit change-cartridge wizard; CartridgeFilledHistoryLog is dropped by the mapper. The premise (no pump screen, Tandem app not in use) makes the wizard the sole cartridge-change path, so the 'pump-UI cartridge change never detected' gap does not arise. Trio consumes .rewind and does not consume .replaceComponent(.reservoir), so the type choice is right for the host. Under the conditional sources nothing changes either, since neither quick bolus nor Control-IQ changes cartridges.

**P10-4 Site change as .replaceComponent(.infusionSet), wizard-only** (Conforms, impact none, amended (auditor said Partial))

The fill-cannula wizard emits .replaceComponent(.infusionSet) only after the pump's FillCannulaStateStream reports .cannulaFilled, with a stable date-stamped raw and replacePendingEvents:false so an in-flight mutable dose is not purged. That is the appropriate type. As with the cartridge event, a cannula fill done on the pump itself is never surfaced: CannulaFilledHistoryLog (typeId 61) is parsed by TandemCore but ignored by the mapper's switch, and the mapper is unwired. The event carries no dose, so accounting impact is limited to upstream site-age tracking.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:65` type: .replaceComponent(componentType: .infusionSet)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1062` emitPumpEvents([NewPumpEvent.siteChange(date: date)], replacePendingEvents: false)
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitFillCannulaViewModel.swift:172` pumpManager?.recordSiteChange(primeAmount: primeAmount) — after .cannulaFilled stream
  - `Sources/TandemCore/Messages/HistoryLog/CannulaFilledHistoryLog.swift:7` public let primeSize: Float — available but never mapped

- Recommendation: Map CannulaFilledHistoryLog (completionStatus == .completed) to the same siteChange event, keyed by HistoryLogSyncIdentifier, so pump-UI site changes are reported once history emission exists.

- Verifier notes:
  - [review:amend] Code fact holds: .replaceComponent(.infusionSet) is emitted with replacePendingEvents:false only from the fill-cannula wizard after the pump reports .cannulaFilled; CannulaFilledHistoryLog is not mapped. The premise makes the wizard the only cannula-fill path on a screenless Mobi without Tandem's app, so the 'pump-UI site change never surfaced' gap is not applicable. Trio maps .replaceComponent(.infusionSet) to siteChange, so the type is consumed correctly.

**P10-5 No .prime event for tubing or cannula fills** (Non-conforming, impact low, amended)

grep over Sources finds no NewPumpEvent with type .prime; the only mentions are the shim enum and UI strings. Both fill flows know the volume (cannula prime in units from the wizard; TubingFilled/CannulaFilled history logs carry primeSize) but nothing reports it. TandemKit correctly does not report fills as insulin doses. However .prime is the one non-dose type DoseStore acts on: it marks reservoir data non-continuous so a tubing fill (a large reservoir drop) is not mistaken for delivery when reservoir-derived doses are in use. Exposure therefore depends on whether TandemKit ever leaves reservoir data newer than lastReconciliation (another point). Trio's Nightscout uploads also derive site-change markers from prime events (not verifiable from the reference set).

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1045` FillCannulaRequest(primeSizeMilliUnits: Int(amount * 1000)) — prime volume known, no event
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1029` ExitFillTubingModeRequest — tubing fill completes with no pump event
  - `Sources/TandemCore/Messages/HistoryLog/TubingFilledHistoryLog.swift:15` public let primeSize: Float — parsed, never mapped
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:118` default: continue — TubingFilled/CannulaFilled dropped
  - `reference: loopkit-trio/DoseStore.swift:723` if case .prime? = event.type { primeValueAdded = true }

- Recommendation: Emit NewPumpEvent(type: .prime, dose: nil, title: "Prime N U") with replacePendingEvents:false when the tubing fill exits successfully and alongside recordSiteChange (cannula prime). Later, map TubingFilled/CannulaFilledHistoryLog(completed) to .prime via HistoryLogSyncIdentifier.

- Verifier notes:
  - [review:amend] Facts confirmed: no NewPumpEvent of type .prime anywhere in Sources; FillCannulaRequest carries the prime volume and ExitFillTubingModeRequest completes with no event; TubingFilled/CannulaFilled logs fall to the mapper's default: continue. The trigger is the app's own fill wizards, so the premise does not remove it and the guide's checklist item is unmet. The accounting consequence is smaller than rated: Trio never derives doses from reservoir readings and only stores .prime as a marker; Loop uses reservoir doses only when the last reading is newer than lastReconciliation, and syncPumpData stamps lastReconciliation after fetchReservoirStatus, so exposure is confined to qualifying-event reservoir reads (pumpSuspend/pumpResume -> InsulinStatusRequest) until the next sync (<= ~5 min), and a cartridge refill raises the level, masking the tubing-fill drop. Transient, bounded, Loop-only: low.

**P10-6 Alarms not emitted as pump events on any live path** (Non-conforming, impact low, verified)

Pump alarms/malfunctions reach the host only as LoopKit Alerts (reconcileLoopKitAlerts), never as NewPumpEvent(type: .alarm, alarmType:). The only code that builds a .alarm event is HistoryToDoseMapper.alarmEvent, which (a) has no production caller — mapToEvents is invoked only from tests and HistoryBackfillCoordinator explicitly emits nothing, (b) is gated by two default-off flags, (c) leaves alarmType nil although AlarmActivatedHistoryLog.alarmResponseType could map occlusion/no-delivery/low-power, and (d) also maps AlertActivatedHistoryLog (e.g. reminders/low reservoir) as .alarm and never emits .alarmClear. Alarm events do not change IOB, but an alarm-induced auto-suspend is only picked up via the basalStatus fetch (P10-2), not via the alarm.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+Alerts.swift:114` delegate.issueAlert(item.loopKitAlert(managerIdentifier:)) — Alert issuance only
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:296` type: .alarm — but no alarmType, dose nil; alerts also mapped as .alarm (line 90)
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:9` Nothing is mapped to doses or emitted here — that is the emission layer's job
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:37` historyBackfill / historyDoseReporting default false
  - `Sources/TandemCore/Messages/HistoryLog/AlarmActivatedHistoryLog.swift:76` alarmResponseType available for a PumpAlarmType mapping

- Recommendation: When fetchNotifications first sees an active alarm/malfunction, emit NewPumpEvent(type: .alarm, alarmType:) keyed by notification id+timestamp with replacePendingEvents:false, and .alarmClear on retraction. In the mapper, map AlarmActivated to PumpAlarmType, and reconsider emitting alerts as .alarm.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: the only NewPumpEvent with type .alarm is built in HistoryToDoseMapper (296), which has no production caller; the live path issues LoopKit Alerts only (+Alerts.swift:114).

**P10-7 Pump replacement / deactivation events** (Not applicable, impact none, verified)

Tandem t:slim X2 and Mobi are durable pumps, not pods/patches: removing the driver does not stop insulin (the pump continues its own basal), so the MedtrumKit lesson of emitting a suspend on force-remove does not transfer, and emitting one would falsely zero basal in Loop. Replacing the physical pump requires re-pairing and a new manager instance, at which point .replaceComponent(.pump) has no continuous dose timeline to annotate. The two replaceable Tandem components (cartridge, infusion set) are covered by P10-3/P10-4.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1117` prepareForDeactivation: tears down transport, emits no suspend or replaceComponent(.pump)
  - `reference: loopkit-trio/PumpEventType.swift:89` case pump // Base, pod or patch full replacement

- Recommendation: No change. Optionally document in the driver README why no suspend/pump-replacement event is emitted on deactivation, so a future contributor does not add one by analogy with patch pumps.

- Verifier notes:
  - [review:confirm] Code fact holds: prepareForDeactivation tears down the transport and emits no suspend or replaceComponent(.pump). The reasoning rests on the Mobi being a durable pump that keeps delivering basal after driver removal, which the premise does not alter. not_applicable/none unchanged.

**P10-8 Test coverage of emitted PumpEventType** (Partial, impact none, verified)

The mapper's suspend/resume/alarm types are unit-tested, but no test inspects the NewPumpEvent.type or replacePendingEvents flag actually delivered to the delegate by suspendDelivery, resumeDelivery, fetchBasalStatus, recordSiteChange or recordCartridgeChange, which is exactly where P10-2 hides. On Linux, the shim's NewPumpEvent does not infer type from the dose, so such a test would need the explicit `type:` recommended in P10-1 to pass on both platforms.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:36` var pumpEvents: [NewPumpEvent] — captured but no test asserts .type on manager paths
  - `Tests/TandemKitTests/TandemPumpManagerSuspendDeliveryTests.swift:104` XCTAssertEqual(manager.state.basalDose.type, .suspend) — checks state, not the emitted event
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:273` XCTAssertEqual(suspend.type, .suspend) — mapper-only coverage
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:293` XCTAssertEqual(event.type, .alarm)

- Recommendation: Add delegate-level tests via StubPumpBluetooth asserting: suspend emits .suspend; pump-side resume emits .resume then .basal; site/cartridge emit their types with replacePendingEvents:false; fill flows emit .prime.

- Verifier notes:
  - [review:confirm] Code fact holds: MockPumpManagerDelegate captures pumpEvents but no test outside HistoryToDoseMapperTests asserts the emitted NewPumpEvent.type or replacePendingEvents on manager paths. Test coverage is app-side and unaffected by the premise. Partial/none unchanged.

Open questions raised by this point:

- InsulinMath.reconciled() (LoopKit/InsulinKit/InsulinMath.swift) and DoseType.pumpEventType (DoseType.swift) are not in the reference set; P10-2's severity and P10-1's inference claim rest on their well-known behaviour and should be confirmed against the Trio-pinned LoopKit checkout.
- How Trio (nightscout/Trio PumpHistoryStorage / NightscoutManager) consumes .rewind vs .replaceComponent(.reservoir) and .prime for its cannula/insulin-age display and Nightscout Site Change / Insulin Change uploads was not verifiable from disk; it decides whether .rewind should be replaced.
- After sendResumePumping the driver stores a .resume basalDose and fetchBasalStatus deliberately returns early for basalType .basal, so no scheduled .basal dose follows the resume; whether LoopKit's basal overlay covers this is a basal-reporting question outside P10.
- handleHomeScreenMirrorResponse (StateSync.swift:473) has no callers; the pump's HomeScreenMirror is also not in QualifyingEventFetch. Whether it is intended to be wired or removed affects where the P10-2 fix belongs.
- The Linux shim's NewPumpEvent lacks `alarmType` and type inference (LinuxShims/LoopKit/LoopKit.swift:537-557); any future alarmType-carrying event will need a shim update to compile on Linux.
### P11. A running temp basal keeps a stable syncIdentifier across every update, is finalized (not dropped) on reconnect, and its deliveredUnits are rounded to the pump increment

Guide section: §10 pitfall: temp basal finalization and overwrite.

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 6 of 6 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

A running TBR is finalized, not overwritten, when Loop replaces or cancels it, and it survives BLE reconnect and app relaunch because state.basalDose is persisted and the next sync's fetchBasalStatus finalizes it (clamped to the programmed end on natural expiry). However the raw key is "tempBasal <programmedUnits> <start>", and LoopKit computes programmedUnits from the entry's endDate, so every early finalization (Loop's 5-minute re-issue, suspend, Control-IQ enable, pump-side cancel) changes the syncIdentifier; the correct end state depends on the replacePendingEvents purge, the §4 anti-pattern. Pump-side cancellation is stamped at sync time rather than the pump's stop time, deliveredUnits is an unrounded rate×duration product, and the reported rate is derived from the app's schedule rather than the pump's profileBasalRate just fetched.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P11-1 | Partial | medium | verified | Temp basal syncIdentifier stability through finalization |
| P11-2 | Conforms | none | verified | Replacing/cancelling a running TBR finalizes instead of overwriting |
| P11-3 | Conforms | none | verified | TBR survives BLE reconnect and app relaunch |
| P11-4 | Partial | medium | verified | Pump-side TBR stop stamped at sync time, not pump time |
| P11-5 | Non-conforming | low | verified | deliveredUnits rounding to pump increment |
| P11-6 | Partial | medium | verified | Reported rate derived from app schedule, not pump's profile rate |

**P11-1 Temp basal syncIdentifier stability through finalization** (Partial, impact medium, verified)

The mutable TBR re-reports (endDate = estimatedEndDate) and the natural-expiry finalization (clamped to estimatedEndDate) produce byte-identical raw, so identity is stable on those paths. But when a TBR is ended early — Loop re-issuing a TBR via enactTempBasal, suspendDelivery, configureControlIQMode, or fetchBasalStatus detecting a pump-side stop — the finalized entry's endDate is now, programmedUnits shrinks, and the raw/syncIdentifier changes. DoseStore still reaches the right end state because replacePendingEvents:true purges every mutable row regardless of identity, and InsulinDeliveryStore soft-deletes unmatched mutables. This is exactly the MedtrumKit pattern §4 warns against: correctness rests on the purge safety net, not identity matching, and no test asserts key stability across cancellation.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:20` raw: "\(DoseType.tempBasal.rawValue) \(dose.programmedUnits) \(date)" — key embeds programmedUnits
  - `reference: loopkit-trio/DoseEntry.swift:72` case .unitsPerHour: return value * hours — hours = endDate - startDate
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:177` var actualEndDate = isMutable ? estimatedEndDate : endDate — finalized entry gets a different endDate
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:178` clamp to estimatedEndDate only when endDate exceeds it (natural expiry keeps key stable)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` toDoseEntry(isMutable: endDate == nil, endDate: endDate ?? Date.now) — early finalization uses now

- Recommendation: Build the raw key from the UnfinalizedDose's own stable fields (value × programmed duration, or startDate alone) rather than DoseEntry.programmedUnits, so cancellation never changes it. Add a test asserting the mutable and finalized raw are equal for early cancel.

- Verifier notes:
  - [review:confirm] Code fact holds: temp basal raw embeds dose.programmedUnits, which shrinks when toDoseEntry finalizes with an early endDate (Date.now) in getActivePumpEvents. Every early-end trigger is app-side (Loop re-issuing a TBR, suspendDelivery, configureControlIQMode) or a pump alarm stop noticed by fetchBasalStatus, all in scope under the premise. Correctness relies on the replacePendingEvents purge, the pattern §4 warns against. Partial/medium unchanged.

**P11-2 Replacing/cancelling a running TBR finalizes instead of overwriting** (Conforms, impact none, verified)

On enactTempBasal with a TBR already running the driver stops the pump's temp rate, then emits in one batch: the old TBR as an immutable DoseEntry with endDate = the new dose's startDate and computed deliveredUnits, plus the new TBR as mutable. The zero-duration/100% path likewise finalizes the old TBR and emits the scheduled basal. suspendDelivery and configureControlIQMode follow the same finalize-then-replace shape. The old TBR's end is stamped a few seconds after the actual StopTempRate (at the new dose's Date.now), which is negligible. There is no code path that re-emits a different TBR under the old dose's slot without first finalizing it.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:705` if currentBasal.basalType == .tempBasal { StopTempRateRequest ... }
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:771` var events = self.getActivePumpEvents(endDate: dose.startDate) — old TBR finalized at new start
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:772` events.append(NewPumpEvent.tempBasal(dose: dose.toDoseEntry(isMutable: true) ...)) — new TBR mutable
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:738` cancel-only path (duration 0 / 100%) finalizes via getActivePumpEvents(endDate:) and emits a basal
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1715` if endDate != nil, basalEntry.endDate == estimatedEndDate — scheduled basal appended on natural expiry

- Recommendation: Keep the finalize-then-start ordering; consider stamping the old TBR's end at the StopTempRate response time rather than the new dose's start to remove the small overlap gap.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P11-3 TBR survives BLE reconnect and app relaunch** (Conforms, impact none, verified)

Neither the disconnect callback nor the Bluetooth-off path modifies basalDose or emits events, and auto-reconnect only re-establishes the link. Because UnfinalizedDose is persisted inside TandemPumpManagerState, the same startDate/estimatedEndDate/value regenerate an identical raw after relaunch (ISO8601 formatting drops sub-seconds, so precision is not a factor). At the next ensureCurrentPumpData (≈5 min) or .basalChange qualifying event, fetchBasalStatus sees the pump back on profile basal and finalizes the TBR with endDate clamped to estimatedEndDate on natural expiry. No path emits replacePendingEvents:true while omitting the running TBR except sendResumePumping, which is only reachable when state already says suspended (so no TBR is pending).

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemBluetoothManager.swift:473` didDisconnectPeripheral cancels in-flight ops, marks link down, auto-reconnects — no dose state touched
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:386` raw["basalDose"] = basalDose.rawValue — TBR persisted with start/estimatedEnd/value
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:272` basalDose restored from rawValue on relaunch
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:141` if activeBasalType != state.basalDose.type — next sync finalizes the TBR when pump reports basal
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:149` var events = getActivePumpEvents(endDate: now) — finalized, not dropped

- Recommendation: Add a test that drives disconnect → reconnect → fetchBasalStatus with a stubbed CurrentBasalStatusResponse(basal) and asserts the TBR is emitted immutable with the original raw and deliveredUnits.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: didDisconnectPeripheral touches no dose state (TandemBluetoothManager.swift:473); basalDose round-trips through rawValue (272, 386).

**P11-4 Pump-side TBR stop stamped at sync time, not pump time** (Partial, impact medium, verified)

Natural expiry is handled correctly because toDoseEntry clamps to estimatedEndDate. But if the temp rate stops early on the pump (user cancels on the t:slim X2 screen, pump alarm, cartridge change), fetchBasalStatus finalizes the TBR at the time of the poll that noticed it. Unless the pump also emits a .basalChange qualifying event (hardware behavior, not verifiable here), that can be up to ≈5 minutes after the real stop, and deliveredUnits = rate × (poll − start) over-counts by rate × delay. The pump exposes the truth twice — TempRateResponse (start, duration) and TempRateCompletedHistoryLog — and HistoryToDoseMapper already computes min(programmedEnd, completion), but nothing consumes it.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:148` let now = Date.now; var events = getActivePumpEvents(endDate: now) — end = time of the poll
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:360` lastSync < 4.5 min short-circuits — polls are ≈5 min apart
  - `Sources/TandemCore/Messages/CurrentStatus/TempRate.swift:41` TempRateResponse carries startTimeRaw and duration but is only read in suspendDelivery
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:240` endDate = min(programmedEndDate, completionDate) — correct logic exists here
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:35` mapToEvents has no caller anywhere in Sources (grep) — mapper is not wired

- Recommendation: When fetchBasalStatus sees the TBR gone, read TempRateResponse (or the TempRateCompleted history record) and finalize at the pump's reported stop time; wire HistoryToDoseMapper's temp-rate output to reconcile the optimistic entry in place.

- Verifier notes:
  - [review:confirm] Code fact holds: fetchBasalStatus finalizes a vanished TBR at the poll time (Date.now), polls are ~5 min apart, and TempRateResponse startTimeRaw/duration are only read in suspendDelivery. The premise drops the 'user cancels on the screen' trigger, but pump alarm stops (occlusion, empty cartridge, auto-off) and cartridge-change mode remain in scope and produce the same rate x delay over-count. Partial/medium stands.

**P11-5 deliveredUnits rounding to pump increment** (Non-conforming, impact low, verified)

The finalized TBR's deliveredUnits is value × elapsed hours with arbitrary double precision (e.g. 0.85 U/h × 17m23s = 0.24626… U). Tandem reports insulin in milliunits, so the guide's expectation is a value rounded to 0.001 U (or the pump's delivery increment). Only the programmed rate is snapped to the 0.01 U/h grid. This is an estimate anyway — the pump is never asked what it actually delivered for the temp rate — so the unrounded figure also misrepresents precision. Impact on IOB is sub-milliunit, but it feeds HealthKit and plotting.

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` deliveredUnits: isMutable ? nil : value * (duration / .hours(1)) — raw product, no rounding
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:229` roundToSupportedBasalRate floors the rate to the 0.01 U/h grid — value is rounded, delivered is not
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:161` roundToReportingResolution (0.001 U) exists but tempBasalEvent leaves deliveredUnits nil
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:252` history temp basal DoseEntry has no deliveredUnits argument

- Recommendation: Round the finalized temp basal deliveredUnits with HistoryToDoseMapper.roundToReportingResolution (or a shared TandemCore helper) before building the DoseEntry; do the same in the mapper's tempBasalEvent once wired.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P11-6 Reported rate derived from app schedule, not pump's profile rate** (Partial, impact medium, verified)

Tandem temp rates are a percent of the active profile segment. The driver converts Loop's absolute U/h to an integer percent (clamped to 250 %), then reports value = round(baseline × percent/100), which correctly reflects the quantized/clamped rate the pump will deliver rather than Loop's request. But baseline comes from the app's cached basalRateSchedule, while the pump's own profileBasalRate is in the CurrentBasalStatusResponse just fetched and ignored. If the pump's profile differs (edited on the X2 screen, a segment boundary crossed, or a failed syncBasalRateSchedule), both the percent sent and the value reported are wrong, and the finalized deliveredUnits inherits the error. Duration is truncated to whole minutes with no handling of Tandem's 15-minute minimum.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:690` let baselineRate = getScheduledBasalRate() — from state.basalRateSchedule
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:702` CurrentBasalStatusResponse fetched here exposes profileBasalRate, which is not used
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:284` percent = Int((requestedRate / baseline * 100).rounded()); clamped 0…250
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:722` absoluteRate = roundToSupportedBasalRate(baselineRate * percent/100) — reported value is the quantized rate
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:749` SetTempRateRequest(minutes: Int(duration.minutes), percent:) — no 15-minute minimum handling

- Recommendation: Use currentBasal.profileBasalRate from the fetched CurrentBasalStatusResponse as the percent baseline and reported value; after SetTempRate, read TempRateResponse to confirm percent/duration and set estimatedEndDate from it; reject or clamp durations below the pump minimum explicitly.

- Verifier notes:
  - [review:confirm] Code fact holds: percent and reported value derive from the app schedule baseline; profileBasalRate from the fetched CurrentBasalStatusResponse is unused, duration is truncated to whole minutes with no 15-minute-minimum handling. The premise removes the 'edited on the X2 screen' trigger only; failed syncBasalRateSchedule and segment-boundary drift are driver-internal and remain. Partial/medium unchanged. Same underlying defect as P07-4.

Open questions raised by this point:

- Does the pump emit a .basalChange qualifying event when a temp rate expires or is cancelled on the pump? That determines whether P11-4's detection latency is seconds or the ~5-minute sync interval; it is hardware behavior not determinable from the code.
- SetTempRateRequest.props is marked supportedDevices: .mobiOnly / minApi: .mobiApiV3_5, yet enactTempBasal does not check supports(). What happens on a t:slim X2 (rejected, or works) affects whether any TBR record exists to finalize on that model.
- Does Trio's implementation of pumpManager(_:hasNewPumpEvents:...) honor replacePendingEvents exactly as LoopKit's DoseStore does? P11-1's correct end state relies on that purge.
- fetchBasalStatus silently does nothing when the pump reports .tempBasal while state.basalDose is .basal (StateSync 141-187 has no branch for that case), so a TBR set on the pump UI, or one whose local record was lost, is never reported. This is a §7 (wasProgrammedByPumpUI) matter rather than P11 but interacts with it.
- Ordinary syncs with a running TBR do not call hasNewPumpEvents at all (fetchBasalStatus emits only on type change; fetchReservoirStatus only sets lastReconciliation), so the guide's 'the mutable dose is re-reported every sync' expectation is not met even though nothing purges it; this belongs to the every-sync/lastReconciliation point.
- sendResumePumping emits [resume] with replacePendingEvents:true and no getActivePumpEvents(); it is only reachable when the driver already believes delivery is suspended, but a direct resumeDelivery call while state.basalDose is .tempBasal would drop the mutable TBR unfinalized.
### P12. A bolus is registered up front as a mutable dose before contact can be lost, its in-progress state is persisted, and on reconnect the pump's own history/status supplies the delivered amount before finalizing

Guide section: §10 pitfall: bolus during BLE loss.

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 7 of 7 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

TandemKit persists the in-progress bolus (UnfinalizedDose with pump bolusId) and, when the app stays alive across a BLE drop, finalizes it from the pump's own LastBolusStatus delivered volume after the estimated end plus a 30 s grace. Two gaps break the pitfall's intent. First, the mutable dose is only registered after the pump acknowledges InitiateBolusRequest; a response timeout on a request the pump did receive yields a clean failure, no dose, and deliveryIsUncertain stays false. Second, finalization is gated on the memory-only TandemDoseProgressReporter, so after an app relaunch mid-bolus the persisted dose is cleared silently and the earlier mutable event is never finalized (later purged). Additionally the mutable bolus is not re-reported during delivery and its raw changes on partial delivery.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P12-1 | Partial | high | verified | enactBolus registration vs InitiateBolus ack timeout |
| P12-2 | Conforms | none | verified | In-progress bolus state persistence |
| P12-3 | Non-conforming | high | amended | Recovery after app relaunch mid-bolus |
| P12-4 | Conforms | none | verified | Reconnect with app alive: pump supplies delivered amount |
| P12-5 | Partial | medium | verified | Fallbacks when the pump query fails; rounding of delivered amount |
| P12-6 | Partial | medium | verified | Mutable bolus not re-reported during delivery; raw changes on partial delivery |
| P12-7 | Partial | low | verified | History-log path as recovery source |

**P12-1 enactBolus registration vs InitiateBolus ack timeout** (Partial, impact high, verified)

In steady state the mutable dose, bolusId, and lastReconciliation are recorded and emitted as soon as the pump acks InitiateBolusRequest, which is the earliest point the app knows a bolus exists — acceptable. But the write helper returns nil both when the request never left the phone and when the pump received it and the response was lost (30 s responseTimeout, or the 180 s CommandWatchdog). On that path enactBolus releases permission, reports a clean communication error and registers nothing; PumpManagerStatus never flags deliveryIsUncertain. If the pump did start the bolus, Loop/Trio has zero IOB for it and may retry, which the code's own comment identifies as a double-dose risk.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:564` guard let initiateResponse = self.bluetooth.write(bolusRequest) else { ... completion(.communication(PumpCommError.noResponse)) } — no dose registered
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:598` self.emitPumpEvents([NewPumpEvent.bolus(...)], replacePendingEvents: false) — mutable dose emitted only after wasBolusInitiated
  - `Sources/TandemKit/PumpManager/TandemPeripheralManager.swift:207` writeQ.waitForOutcome(timeout: .now() + Self.responseTimeout) ... return nil — request already written at line 200
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:131` deliveryIsUncertain: false — hard-coded in makeStatus
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:84` comment: on a bolus timeout, surfacing uncertain delivery would be safer than a clean failure. Tracked separately.

- Recommendation: On a nil/timed-out InitiateBolus response, keep bolusId and units in state.bolusDose, emit the mutable dose, and set deliveryIsUncertain until CurrentBolusStatus/LastBolusStatus confirms or denies the bolus; only then finalize or retract. Add a test with a stub that swallows the InitiateBolus response.

- Verifier notes:
  - [review:confirm] Verified literally: the packets are written at TandemPeripheralManager:200 and nil is returned at 215 after the 30 s responseTimeout or a cancel, so nil covers both never-sent and ack-lost. enactBolus (564-568) then releases permission, reports .noResponse and registers no dose; makeStatus hard-codes deliveryIsUncertain:false. Trio has no consumer of deliveryIsUncertain, and neither host receives any event, so a started bolus has zero IOB in both. The 180 s watchdog is a different case: CommandWatchdog is once-only, so the late state.bolusDose/emit still lands but Loop already saw a failure. BLE loss is app-side; premise does not lower it.

**P12-2 In-progress bolus state persistence** (Conforms, impact none, verified)

The guide asks that UnfinalizedDose state not live only in memory. TandemKit persists state.bolusDose (type, value, startDate, estimatedEndDate, deliveredUnits, bolusId) and the LoopKit bolusState into rawState on every notifyDelegateStateUpdated, and decodes both on init. BLE disconnects (markLinkDown / didDisconnectPeripheral) do not touch bolusDose or bolusState, so the record survives both link loss and app termination. Whether that persisted record is actually used to recover is a separate matter (P12-3).

- Evidence:
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:443` if let bolusDose { raw["bolusDose"] = bolusDose.rawValue }
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:244` if let bolusDoseRaw = rawValue["bolusDose"] as? UnfinalizedDose.RawValue { bolusDose = UnfinalizedDose(rawValue:) }
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:141` raw["bolusId"] = bolusId — pump-assigned id survives relaunch
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:652` case let .inProgress(dose): raw["dose"] = PropertyListEncoder().encode(dose)
  - `Tests/TandemKitTests/TandemPumpManagerStateTests.swift:115` testInProgressBolusRoundTrips asserts bolusId 2004, startDate, estimatedEndDate survive

- Recommendation: No change needed for persistence itself. Consider also persisting the dose's original raw/syncIdentifier so any relaunch recovery re-reports the identical identity (see P12-3, P12-6).

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P12-3 Recovery after app relaunch mid-bolus** (Non-conforming, impact high, amended)

The mutable bolus was reported to Loop with replacePendingEvents:false at enact time. If the app is killed and relaunched mid-bolus, state.bolusDose and bolusId are restored but bolusProgressReport is nil. On the next sync (after the grace window) fetchBolusStatus takes the `alreadyDeliveredOrInvalid && bolusProgressReport == nil` branch: it clears bolusDose/bolusState and returns without querying LastBolusStatus or emitting anything. While still delivering it hits the guard and returns. The earlier mutable event is therefore never finalized; the next replacePendingEvents:true batch (fetchBasalStatus, enactTempBasal, suspend/resume) deletes it, so the bolus vanishes from IOB. No test covers this path.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:70` internal var bolusProgressReport: TandemDoseProgressReporter? — memory-only, assigned only in enactBolus (line 588)
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:217` if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil { state.bolusDose = nil ... return } — no emitPumpEvents
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:226` guard let progressReport = bolusProgressReport else { return } — delivering branch also emits nothing
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:255` if let bolusId = state.bolusDose?.bolusId { actualDelivered = queryLastBolusDeliveredVolume(bolusId:) } — reachable only with a progressReport
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1733` func emitPumpEvents(_ events:, replacePendingEvents: Bool = true) — later batches purge the still-mutable bolus

- Recommendation: Rebuild finalization from persisted state: when state.bolusDose has a bolusId and no progress reporter exists, query LastBolusStatus for that id and emit the finalized dose (isMutable:false, deliveredUnits from the pump, same raw) before clearing state. Add a relaunch test using StubPumpBluetooth.

- Verifier notes:
  - [review:amend] Code claims verified, including that StateSync:255 (queryLastBolusDeliveredVolume) sits behind the reporter guard and emitPumpEvents defaults replacePendingEvents to true (1733). The qualifying-event path (.bolusChange → fetchBolusStatus(fromSync:false)) runs the same reporter-gated code, so no path recovers. Correct the downstream fact: the purge that makes the bolus vanish exists in LoopKit DoseStore (both variants); Trio ignores replacePendingEvents and retains the enact-time row at programmedUnits, so under Trio the failure mode is over-count after a pump-side abort rather than loss. Relaunch is app-side; high retained.

**P12-4 Reconnect with app alive: pump supplies delivered amount** (Conforms, impact none, verified)

When BLE drops but the process survives, nothing resets bolusDose or bolusProgressReport (TandemBluetoothManager only flips isConnected). The pump does not replay the missed bolusChange qualifying event, so the driver relies on the periodic sync: it defers CurrentBolusStatus until estimatedEndDate + 30 s, then, once the pump reports no active bolus, reads LastBolusStatus for the tracked bolusId and finalizes with the pump's deliveredVolume rather than the time-based TandemDoseProgressReporter estimate. This matches the guide's 'pump is the source of truth' rule. ensureCurrentPumpData's 4.5-minute freshness check delays this to the next Loop poll, which is acceptable.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:194` shouldDeferBolusSync: date < bolusDose.estimatedEndDate.addingTimeInterval(bolusSyncReconcileGrace) — 30 s grace, then reconcile
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:249` if response.bolusId == 0 { ... actualDelivered = queryLastBolusDeliveredVolume(bolusId: bolusId) }
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:527` guard response.bolusId == bolusId else { return nil } — LastBolusStatus matched to the tracked bolus
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:260` events.append(progressReport.getPumpEvent(actualDeliveredUnits: actualDelivered)) — finalized with pump value
  - `Tests/TandemKitTests/TandemPumpManagerBolusSyncTests.swift:44` testSyncReconcilesAfterGraceExpires — regression for bolusChange lost to a disconnect

- Recommendation: Keep this path; consider triggering fetchBolusStatus(fromSync:true) directly from the auto-reconnect completion so a bolus interrupted by link loss is reconciled within seconds of reconnect rather than at the next poll.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P12-5 Fallbacks when the pump query fails; rounding of delivered amount** (Partial, impact medium, verified)

The recovery path finalizes from the pump only when LastBolusStatus answers and its bolusId matches. If that single read times out (plausible right after a reconnect) the completion path finalizes with the full programmed amount, while the cancel path finalizes with zero. Both silently commit a guess as an immutable dose that Loop will never revise, in opposite directions. Separately, the pump's milliunit deliveredVolume is floored to the 0.05 U command grid, so an interrupted bolus of e.g. 1.041 U is recorded as 1.00 U; the history mapper explicitly rounds to nearest to avoid this.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:33` let delivered = actualDeliveredUnits ?? total — assumes full delivery when LastBolusStatus fails or bolusId mismatches
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0 — cancel path assumes zero
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:532` return roundToSupportedBolusVolume(units: Double(response.deliveredVolume) / 1000.0) — floors to 0.05 U grid
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:161` roundToReportingResolution: round-to-nearest mU; comment warns flooring understates delivered IOB

- Recommendation: If LastBolusStatus fails or mismatches, keep the dose mutable and retry on the next sync instead of committing programmed or zero. Round delivered volume with round-to-nearest milliunits (as HistoryToDoseMapper does) rather than flooring to the command grid.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: completion fallback ?? total (reporter:33), cancel fallback ?? 0 (639), floor to the 0.05 U grid (532, 226). Duplicates P05-2/P07-1/P07-2/P07-3.

**P12-6 Mutable bolus not re-reported during delivery; raw changes on partial delivery** (Partial, impact medium, verified)

After the single replacePendingEvents:false emission at enact time, the in-progress bolus is never re-sent. Any replacePendingEvents:true batch during delivery — most plausibly fetchBasalStatus detecting a temp basal that expired during a BLE outage, since enactTempBasal is blocked while the bolus runs — purges the mutable bolus from Loop, leaving IOB short until finalization re-inserts it. Finalization also mints raw from delivered units, so an interrupted bolus (delivered < programmed) gets a different syncIdentifier than the mutable one; the end state is correct only because the purge removes the stale row, the MedtrumKit safety-net pattern the guide advises against.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:230` if response.status == .delivering { ... state.bolusState = .inProgress(...) ... return } — no emitPumpEvents
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1702` getActivePumpEvents: guard state.basalDose.type == .tempBasal else { return [] } — bolus never included
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:183` fetchBasalStatus: emitPumpEvents(events) — default replacePendingEvents:true, runs even while bolus sync is deferred
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:95` raw: "\(DoseType.bolus.rawValue) \(units) \(date)" — units is part of the identity
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:44` units: delivered — final event's raw uses delivered, not programmed, units

- Recommendation: Include the in-progress bolus (same raw, isMutable:true) in getActivePumpEvents so every batch re-reports it, and build the bolus raw from programmed units (or the pump bolusId) so cancellation and partial delivery keep the identity constant.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: .delivering branch updates bolusState only (230-236); getActivePumpEvents never returns the bolus (1703); fetchBasalStatus emits replace:true (183) while the sync-path bolus read is deferred (202). The purge is P04-1 (high, Loop-only); the identity part is rated low elsewhere; medium kept as the blend.

**P12-7 History-log path as recovery source** (Partial, impact low, verified)

The guide's reconnect recovery names the pump's history. TandemKit's recovery uses LastBolusStatus (P12-4), which is a valid pump-side source, but the richer history-log path cannot yet serve as a backstop: HistoryToDoseMapper is referenced nowhere outside its own file, HistoryBackfillCoordinator explicitly emits nothing, and both flags default to off. The mapper also keys boluses by pumpSerial+bolusId while the live path keys by units+date, so if history emission is wired on later without aligning identities, an interrupted bolus would be double-counted rather than finalized in place.

- Evidence:
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:176` historyBackfill / historyDoseReporting defaultValue: false
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:9` Nothing is mapped to doses or emitted here — that is the emission layer's job
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:207` raw = HistoryLogSyncIdentifier.bolus(pumpSerial:, bolusId:) — identity differs from the optimistic "bolus units date" raw
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1634` if events.contains(.bolusChange) { historyBackfillCoordinator.runTick() } — gated by the off-by-default flag

- Recommendation: When the history emission layer lands, mint the optimistic bolus raw from HistoryLogSyncIdentifier.bolus(pumpSerial, bolusId) so the history completion finalizes the same dose; until then document that LastBolusStatus is the sole recovery source.

- Verifier notes:
  - [review:confirm] Code fact holds: both history flags default false, HistoryBackfillCoordinator emits nothing, HistoryToDoseMapper/mapToEvents has no caller outside its own file, and the mapper keys boluses by pumpSerial+bolusId while the live path uses units+date. Trigger is app-side (BLE loss recovery), so the premise does not change it; on a screenless Mobi the history log is still only a would-be backstop and LastBolusStatus remains the sole working recovery source. partial/low stands.

Open questions raised by this point:

- What does CurrentBolusStatusResponse carry after a bolus completes: bolusId 0, or the finished bolus's id with status 0? fetchBolusStatus finalizes only on `response.bolusId == 0` (StateSync.swift:249); if the pump echoes the last id, an interrupted bolus would never finalize via this path. No TandemCoreTests fixture settles it; a captured response from hardware would.
- If the pump did start a bolus whose InitiateBolusResponse was lost, does BolusPermissionReleaseRequest for that bolusId succeed, fail, or cancel the bolus? This determines whether the P12-1 timeout path is merely unrecorded or actively harmful.
- CLAUDE.md states the history mapper's bolus identity is one 'an optimistic report can mint from the pump-assigned id at command time', but the live path (NewPumpEvent.bolus, Extensions/NewPumpEvent.swift:95) uses units+date instead; the doc appears ahead of the code.
- Does a Tandem pump continue a Loop-initiated bolus across a BLE drop, or stop it with LastBolusStatus bolusStatus .stoppedWireless (LastBolusStatusAbstractResponse.swift:130)? The driver reads deliveredVolume but ignores bolusStatus, so it cannot distinguish the two for logging or uncertainty flags.
### P13. Suspend and resume are modeled as real dose events with correct timing: a suspend is emitted whenever delivery actually stops (including pump-initiated stops and teardown) and a resume restores the basal picture

Guide section: §10 pitfall: suspend / resume events.

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 7 of 7 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

Loop-initiated suspend and resume are modeled correctly: suspendDelivery finalizes any running temp basal at the suspend instant and emits an immutable .suspend point event; sendResumePumping emits a .resume carrying insulinType, and with pumpRecordsBasalProfileStartEvents=false LoopKit re-inserts scheduled basal itself. Pump-initiated stops are only partly handled. The live detection path (fetchBasalStatus) stamps a pump-side suspend at detection time, not the pump's time, and—critically—reports a pump-side resume as a .basal dose, which LoopKit's reconciled() does not accept as closing a suspend, so the suspend stays open. The pump-timestamped PumpingSuspended/Resumed history mapping exists but is unwired and behind default-off flags. Teardown correctly emits no suspend because a Tandem pump keeps delivering after the driver is removed.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P13-1 | Conforms | none | verified | Loop-initiated suspend (suspendDelivery) |
| P13-2 | Conforms | none | verified | Loop-initiated resume (sendResumePumping) |
| P13-3 | Non-conforming | medium | amended | Pump-initiated resume reported as .basal, not .resume |
| P13-4 | Partial | medium | verified | Pump-initiated suspend timing and coverage |
| P13-5 | Not applicable | none | verified | Teardown / prepareForDeactivation |
| P13-6 | Partial | medium | verified | Cartridge/cannula/tubing flows with pump already suspended |
| P13-7 | Partial | medium | verified | Suspend batch drops an in-flight mutable bolus |

**P13-1 Loop-initiated suspend (suspendDelivery)** (Conforms, impact none, verified)

A Loop-commanded suspend is a real dose event with correct timing: it is stamped when the pump acknowledges SuspendPumpingRequest, the in-flight temp basal is finalized at that same instant, and the batch is sent with replacePendingEvents: true. The suspend is an immutable zero-duration entry, which is what LoopKit's reconciled() and DoseStore ('extend an unfinished suspend out to end time') expect; the in-tree Omnipod driver uses the identical DoseEntry(suspendDate:) shape, so not re-reporting it as mutable is the established convention rather than a gap. After app relaunch the persisted basalDose keeps basalDeliveryState at .suspended. Tests exercise the wire sequence and state but not the emitted NewPumpEvent contents.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:820` let suspendDose = UnfinalizedDose(suspendStartTime: Date.now) after SuspendPumpingResponse status 0
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:821` getActivePumpEvents(endDate: suspendDose.startDate) finalizes a running temp basal at the suspend instant
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:828` emitPumpEvents(events) with default replacePendingEvents: true
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:197` case .suspend returns DoseEntry(suspendDate: startDate, automatic: automatic)
  - `reference: loopkit-trio/DoseEntry.swift:31` init(suspendDate:...) defaults isMutable: false — immutable point event, same shape as OmnipodKit

- Recommendation: Add a test asserting the emitted batch (finalized temp basal + .suspend, replacePendingEvents true) via StubPumpBluetooth and a recording delegate.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P13-2 Loop-initiated resume (sendResumePumping)** (Conforms, impact none, verified)

The resume emitted after a successful ResumePumpingRequest is a real .resume DoseEntry stamped at the acknowledgement time and carries insulinType. It does not carry scheduledBasalRate, but in the LoopKit fork TandemKit builds against that property is internal(set) and is filled in by DoseStore's annotated(with: basalProfile), so the MedtrumKit 'resume missing basal rate' failure cannot be reproduced from the driver side. No explicit .basal dose follows the resume; that is correct because pumpRecordsBasalProfileStartEvents is false and LoopKit's overlayBasalSchedule inserts scheduled basal. LoopKit's reconciled() pairs this .resume with the prior .suspend, restoring the basal picture. Status also flips to .active. (next-dev makes scheduledBasalRate public var; still optional there.)

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:900` let dose = UnfinalizedDose(resumeStartTime: Date.now, insulinType: state.insulinType)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:904` let events = [NewPumpEvent.resume(dose: dose.toDoseEntry(), date: dose.startDate)]
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:203` case .resume returns DoseEntry(resumeDate:insulinType:automatic:)
  - `reference: loopkit-trio/DoseEntry.swift:29` public internal(set) var scheduledBasalRate — a driver cannot set it in the pinned LoopKit; DoseStore.annotated(with:) supplies it
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:216` pumpRecordsBasalProfileStartEvents returns false, so LoopKit inserts scheduled basal after the resume

- Recommendation: No change required. If TandemKit later builds against next-dev LoopKit, consider populating scheduledBasalRate on the resume from getScheduledBasalRate().

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: the fork's DoseEntry.scheduledBasalRate is `public internal(set)` (loopkit-trio DoseEntry.swift:29), so the driver cannot set it and DoseStore fills it in; the resume event is built with insulinType at 900-904.

**P13-3 Pump-initiated resume reported as .basal, not .resume** (Non-conforming, impact medium, amended)

When the user resumes on the pump (or the pump resumes after an alarm/Basal-IQ suspend), fetchBasalStatus sees basalType .basal while state.basalDose is .suspend and emits a zero-length .basal dose instead of a .resume. LoopKit's reconciled() closes an open suspend only on a .resume or a .tempBasal; a .basal leaves lastSuspend set, so the suspend is appended with endDate nil and DoseStore extends it to the query end. Loop/Trio therefore keeps treating basal as suspended after the pump has actually resumed, until a later temp basal or Loop-issued resume arrives. That under-counts delivered basal for an unbounded period and can drive over-delivery. The only code that emits a .resume for a pump-side resume (handleHomeScreenMirrorResponse) is unreachable. No test covers fetchBasalStatus transitions.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:166` if activeBasalType == .basal { ... } — branch taken when the pump resumes on its own after state.basalDose.type == .suspend
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:168` let dose = UnfinalizedDose(basalRate: getScheduledBasalRate(), ...) — a .basal dose, no .resume is created
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:168` case .basal returns DoseEntry(type: .basal, ...) with no endDate
  - `reference: InsulinMath_loopandlearn.swift:415` } else if let suspend = lastSuspend, dose.type == .tempBasal { // Handle missing resume — only a temp basal (not .basal) closes an open suspend
  - `reference: InsulinMath_loopandlearn.swift:501` if let suspend = lastSuspend { reconciled.append(... endDate: nil ...) } — the suspend is emitted still open

- Recommendation: In fetchBasalStatus, when state.basalDose.type == .suspend and the pump reports .basal, emit UnfinalizedDose(resumeStartTime:insulinType:) with wasProgrammedByPumpUI where LoopKit allows, mirroring handleHomeScreenMirrorResponse; add a StubPumpBluetooth test for suspend→basal and basal→suspend transitions.

- Verifier notes:
  - [review:amend] All cited lines verified (InsulinMath_loopandlearn.swift is byte-identical to loopkit-trio/InsulinMath.swift; UnfinalizedDose .basal DoseEntry has no endDate; QualifyingEventFetch routes pumpResume to .basalStatus; handleHomeScreenMirrorResponse has no caller; no test covers fetchBasalStatus transitions). Same defect as P10-2. Under the premise the primary trigger (user or Basal-IQ resume on the pump) is not applicable: all default-config Mobi resumes run through sendResumePumping, which emits .resume and sets state .resume so fetchBasalStatus's guard returns. The residual default-config trigger is an app-side one — a ResumePumpingRequest whose response times out after the pump acted — so the defect stays nonconforming but its rating drops to medium. When it fires, Trio's IobHistory keeps the pump 'suspended' until a later PumpResume (unbounded), Loop until the next .tempBasal; would be high for a UI-capable pump or with Basal-IQ enabled.

**P13-4 Pump-initiated suspend timing and coverage** (Partial, impact medium, verified)

Pump-initiated stops (user 'Stop Insulin', occlusion/empty-cartridge alarms, malfunction, Basal-IQ auto-suspend — all reasons carried by PumpingSuspendedHistoryLog) are detected only by polling CurrentBasalStatus: on a pumpSuspend qualifying event while connected, or on the next Loop sync (up to ~5 min, or after a BLE outage arbitrarily longer, since reconnect does not sync). The suspend is then stamped Date.now, so Loop credits basal delivered between the real stop and detection. The pump's own ledger (PumpingSuspended/ResumedHistoryLog, pump-timestamped) is mapped by HistoryToDoseMapper but never emitted, and the whole history path is behind two default-off flags. HypoMinimizerSuspend/Resume logs are not mapped at all. Whether Basal-IQ or Control-IQ zero-basal sets bitmask exactly 0x01 is not verifiable from code.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:148` let now = Date.now — pump-side suspend is stamped at detection time, not the pump's suspend time
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:152` let dose = UnfinalizedDose(suspendStartTime: now) emitted only when basalType flips to .suspend
  - `Sources/TandemCore/Messages/CurrentStatus/CurrentBasalStatus.swift:45` case 0x01: return .suspend — exact-match switch on basalModifiedBitmask
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:360` ensureCurrentPumpData skips a sync if lastReconciliation is < 4.5 min old; reconnect itself triggers no sync
  - `Sources/TandemKit/PumpManager/TandemBluetoothManager.swift:427` auto-reconnect calls ensureConnected only; no fetchBasalStatus/syncPumpData follows

- Recommendation: Wire pump-timestamped PumpingSuspended/Resumed history events into emission (dedup against the polled suspend by replacing its raw), trigger fetchBasalStatus on reconnect, map HypoMinimizer logs, and confirm bitmask values for Basal-IQ/Control-IQ on hardware.

- Verifier notes:
  - [review:confirm] Code fact holds: fetchBasalStatus stamps a pump-side suspend at Date.now, only when basalType flips to .suspend; reconnect calls ensureConnected without a sync; ensureCurrentPumpData short-circuits under 4.5 min; pump-timestamped PumpingSuspended mapping is unwired behind default-off flags. Under the premise the user-Stop-Insulin trigger drops out, but occlusion, empty-cartridge, auto-off and malfunction stops are explicitly in scope and hit the same late, wrongly-timed suspend, so Loop credits basal that was not delivered. partial/medium stands.

**P13-5 Teardown / prepareForDeactivation** (Not applicable, impact none, verified)

The guide's 'emit a suspend on teardown' lesson comes from patch pumps whose removal ends delivery. A t:slim X2 or Mobi keeps running its own basal profile (and Control-IQ, if enabled) after the driver is deleted, so emitting a .suspend at deactivation would tell Loop insulin stopped when it did not. Not emitting one is therefore correct for this hardware; TandemKit does nothing but tear down BLE and notify the host. A remaining, separate concern is that a mutable temp basal in flight at deactivation is not finalized (outside this point).

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1119` bluetooth.deactivate() then notifyDelegateOfDeactivation — no SuspendPumpingRequest, no suspend event
  - `Sources/TandemKit/PumpManager/TandemBluetoothManager.swift:386` deactivate(): sets isDeactivated, disconnect(), drops pumpManager — transport only
  - `reference: loopkit-trio/PumpManager.swift:281` notifyDelegateOfDeactivation only calls pumpManagerWillDeactivate

- Recommendation: Keep as is. Document in contributor docs why no suspend is emitted at deactivation, and consider finalizing any running temp basal there.

- Verifier notes:
  - [review:confirm] Code fact holds: prepareForDeactivation only calls bluetooth.deactivate() and notifyDelegateOfDeactivation; no SuspendPumpingRequest or .suspend event. The reasoning is a hardware fact independent of the premise: a Mobi keeps running its own basal profile after the driver is deleted, so emitting a suspend at teardown would be wrong. not_applicable/none stands.

**P13-6 Cartridge/cannula/tubing flows with pump already suspended** (Partial, impact medium, verified)

The change-cartridge, fill-cannula and fill-tubing wizards normally suspend via suspendDelivery (emits the suspend dose) and resume via resumeDelivery (emits the resume, then syncs), which is correct. However each wizard first calls fetchSuspendStatus and, if the pump is already suspended (user pressed Stop Insulin on the pump), skips the suspend step. fetchSuspendStatus only returns a Bool; it does not update state.basalDose or emit a suspend, so the whole cartridge change can proceed with Loop still believing basal is running until the next sync's fetchBasalStatus notices. Combined with P13-3, the later resume from the wizard is fine (Loop-initiated), but the pre-existing pump-side suspend is late.

- Evidence:
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitChangeCartridgeViewModel.swift:127` pumpManager?.fetchSuspendStatus { isSuspended in ... currentStep = .enterMode } — skips the suspend step if pump is already suspended
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:130` completion(response.basalType == .suspend) — fetchSuspendStatus returns a Bool and neither updates state.basalDose nor emits a suspend
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitChangeCartridgeViewModel.swift:142` pumpManager?.suspendDelivery — the normal path does go through the event-emitting suspend
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitFillCannulaViewModel.swift:183` pumpManager?.resumeDelivery then syncPumpData — resume path emits .resume and re-syncs

- Recommendation: Have fetchSuspendStatus delegate to fetchBasalStatus (which emits the suspend and updates basalDose) and return state.basalDose.type == .suspend, so a pump-side suspend seen by the wizards is recorded immediately.

- Verifier notes:
  - [review:confirm] Code fact holds: all three wizards call fetchSuspendStatus, which returns only a Bool from CurrentBasalStatus and neither updates state.basalDose nor emits a suspend; ChangeCartridge skips to .enterMode when already suspended. Under the premise the named trigger (user pressed Stop Insulin on the pump) is out of scope, but the pump-initiated no-screen stops remain: an empty-cartridge or occlusion alarm suspends the pump and is precisely what precedes a cartridge change on a Mobi, so the wizard proceeds with the suspend unrecorded until the next fetchBasalStatus. partial/medium stands with the trigger re-scoped to alarm-induced suspends.

**P13-7 Suspend batch drops an in-flight mutable bolus** (Partial, impact medium, verified)

A Tandem 'stop insulin' halts a running bolus as well as basal. suspendDelivery does not include the in-progress mutable bolus in its replacePendingEvents:true batch, so LoopKit soft-deletes it at the moment of suspend and the partially delivered bolus disappears from IOB. state.bolusDose is retained, so the next fetchBolusStatus (deferred until estimated end + 30 s) may finalize it with the pump's LastBolusStatus delivered volume if CurrentBolusStatus reports bolusId 0. Recovery is plausible but time-delayed and not tested; whether the pump reports the interrupted bolus that way is unverified. This is bolus accounting, but the trigger is the suspend batch's contents.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:598` bolus emitted with replacePendingEvents: false as a mutable dose
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1706` getActivePumpEvents: guard state.basalDose.type == .tempBasal else { return [] } — never re-reports the bolus
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:828` suspendDelivery emits [tempBasal?, suspend] with replacePendingEvents true, purging the mutable bolus
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:249` if response.bolusId == 0 { ... queryLastBolusDeliveredVolume ... emitPumpEvents } — later sync can re-add the finalized bolus

- Recommendation: In suspendDelivery, finalize the active bolus in the same batch (query LastBolusStatus for delivered volume) or include the mutable bolus in getActivePumpEvents; add a test for suspend-during-bolus.

- Verifier notes:
  - [review:confirm] Code fact holds: the bolus is emitted mutable with replacePendingEvents:false, getActivePumpEvents returns only a temp basal, and suspendDelivery emits [tempBasal?, suspend] with the default replacePendingEvents:true, purging the mutable bolus; recovery depends on a later fetchBolusStatus seeing bolusId == 0. Trigger is the app's own suspend batch composition during an app-initiated bolus, which the premise leaves unaffected. partial/medium stands.

Open questions raised by this point:

- Does CurrentBasalStatusResponse.basalModifiedBitmask read exactly 0x01 during a Basal-IQ hypo-suspend and during Control-IQ zero-basal, and can bits combine (e.g. 0x03)? The switch at CurrentBasalStatus.swift:44-52 matches exact values only; a hardware capture would settle it.
- After SuspendPumping interrupts a running bolus, does CurrentBolusStatusResponse report bolusId 0 with .alreadyDeliveredOrInvalid so fetchBolusStatus finalizes it (P13-7 recovery)? Not determinable from code.
- For P13-3 the sign of the error depends on which DoseStore pipeline Trio uses for IOB (live getNormalizedDoseEntries extends the open suspend to now; the InsulinDeliveryStore save path overlays schedule after a zero-length suspend). Both are wrong; the direction should be confirmed against Trio.
- The guide describes an 'open suspend' as a mutable dose, but LoopKit-trio's reconciled() and the in-tree OmnipodKit treat suspend as an immutable point event closed by the resume; TandemKit follows the in-tree convention.
- prepareForDeactivation leaves a running mutable temp basal un-finalized (outside P13 scope).
- docs/tandemkit-history-integration-plan.md:214 states suspend/resume are injected by UI flows rather than synthesized from history; that matches the code today, but the mapper's suspend/resume support (and its test) is otherwise unused.
### P14. Pump faults are surfaced as NewPumpEvent with type .alarm / alarmType, and .replaceComponent is emitted on component replacement

Guide section: §10 pitfall: faults, alarms, pump replacement.

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 6 of 6 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

TandemKit emits .replaceComponent(.infusionSet) on cannula fill and .rewind on cartridge change, both from the TandemKitUI wizards only, with replacePendingEvents:false. Pump faults never reach the pump-event log: HistoryToDoseMapper does map Alarm/AlertActivated logs to type .alarm (alarmType nil, alerts conflated with alarms), but mapToEvents has no caller in Sources, historyBackfill defaults off, and every traced emitPumpEvents call site carries only dose/suspend/resume/basal or the two component events. Alarms and malfunctions reach the host solely through LoopKit Alert issuance (a different channel). Nothing emits .replaceComponent(.pump) when a different pump is paired; only the history-backfill bookkeeping notices a serial change. Faults/alarms done on the pump UI (cartridge/tubing/cannula history logs) are ignored.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P14-1 | Non-conforming | low | verified | Alarm events never reach hasNewPumpEvents |
| P14-2 | Partial | low | verified | alarmType not populated; alerts conflated with alarms |
| P14-3 | Conforms | none | amended | Cannula fill emits .replaceComponent(.infusionSet) |
| P14-4 | Partial | low | verified | Cartridge change reported as .rewind, no prime event |
| P14-5 | Non-conforming | low | verified | No .replaceComponent(.pump) on pairing a different pump |
| P14-6 | Partial | none | verified | Linux shim cannot express alarmType |

**P14-1 Alarm events never reach hasNewPumpEvents** (Non-conforming, impact low, verified)

grep over Sources shows `mapToEvents`/`HistoryToDoseMapper` referenced only inside its own file, so the mapper's .alarm events are dead code today. Traced emission sites: TandemPumpManager.swift 598 (bolus), 657 (cancel), 743/778 (temp basal), 828/910 (suspend/resume), 1062/1071 (site/cartridge), 1330 (Control-IQ basal); +StateSync 161/183 (basal status), 268 (bolus done), 512 (home-screen mirror). Pump alarms (occlusion, empty cartridge, auto-off, cartridge removed — AlarmStatus.swift:62-85) and malfunctions are surfaced only as LoopKit Alerts via reconcileLoopKitAlerts. That satisfies user notification but not §10's 'NewPumpEvent with type .alarm'. Same on steady state, first sync, reconnect and relaunch; the historyBackfill flag does not change it because the store is never mapped.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:296` alarmEvent builds NewPumpEvent(type: .alarm) — the only .alarm construction in Sources
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:318` fetchNotifications() ends in reconcileLoopKitAlerts(), not emitPumpEvents
  - `Sources/TandemKit/PumpManager/TandemPumpManager+Alerts.swift:114` delegate.issueAlert(item.loopKitAlert(...)) — LoopKit Alert channel, not the pump-event log
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1733` func emitPumpEvents(_ events:, replacePendingEvents:) — all 13 call sites traced; none passes an .alarm event
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:36` historyBackfill / historyDoseReporting default false

- Recommendation: When the history emission layer is wired (historyDoseReporting), include the mapper's .alarm events; until then, consider emitting an .alarm NewPumpEvent from fetchNotifications for newly active alarms/malfunctions, keyed by a stable raw (serial + alarm id + activation time), with replacePendingEvents:false.

- Verifier notes:
  - [review:confirm] Code fact holds: the only NewPumpEvent(type: .alarm) construction is in the unwired HistoryToDoseMapper; fetchNotifications ends in reconcileLoopKitAlerts, which issues LoopKit Alerts, and no emitPumpEvents call site passes an alarm. Pump alarms and malfunctions (occlusion, empty cartridge, auto-off) are in scope under the premise and are surfaced only via the Alert channel, not the pump-event log Trio maps to pumpAlarm. Dose accounting is unaffected, so nonconforming/low stands.

**P14-2 alarmType not populated; alerts conflated with alarms** (Partial, impact low, verified)

The (currently unused) mapper populates type .alarm but leaves alarmType nil and uses the generic title "Alarm" for both AlarmActivated and AlertActivated logs. Tandem alerts (low insulin, high BG, reminders) are not faults; reporting them as .alarm would overstate fault history once the mapper is wired. The alarm id is available (alarmId, alarmResponseType) and several Tandem alarms map cleanly onto LoopKit's PumpAlarmType (OCCLUSION_ALARM→occlusion, EMPTY_CARTRIDGE_ALARM→noInsulin, AUTO_OFF_ALARM→autoOff, BATTERY_SHUTDOWN_ALARM→noPower). Test HistoryToDoseMapperTests.swift:285-299 asserts type and raw only. Identity is good: raw is HistoryLogSyncIdentifier.logSequence(pumpSerial, sequenceNum), stable across re-reads.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:87` case let alarm as AlarmActivatedHistoryLog: events.append(alarmEvent(...))
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:89` case let alert as AlertActivatedHistoryLog: also emitted as .alarm
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:291` NewPumpEvent(date:, dose: nil, raw:, title: "Alarm", type: .alarm) — no alarmType argument
  - `Sources/TandemCore/Messages/HistoryLog/AlarmActivatedHistoryLog.swift:76` alarmResponseType exposes the typed alarm id the mapper could translate
  - `reference: loopkit-trio/NewPumpEvent.swift:26` init(..., type: PumpEventType? = nil, alarmType: PumpAlarmType? = nil) — defaults nil

- Recommendation: Restrict .alarm to AlarmActivatedHistoryLog (and malfunctions); map alarmResponseType to PumpAlarmType (.occlusion, .noInsulin, .autoOff, .noPower, else .other(name)) and pass it as alarmType; use a descriptive title. Add a test asserting alarmType.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P14-3 Cannula fill emits .replaceComponent(.infusionSet)** (Conforms, impact none, amended (auditor said Partial))

The app-driven fill-cannula wizard reports a site change with the correct LoopKit type and, per §5, replacePendingEvents:false so a live mutable bolus/temp basal is not purged. raw is "siteChange <ISO8601>" — unique per event and not re-reported, so no identity churn. Gap: on a t:slim X2 the user can fill the cannula on the pump's own screen; CannulaFilledHistoryLog exists in the catalog but is ignored by the mapper (and the mapper is not wired anyway), so pump-UI site changes are never reported. No test asserts the emitted event.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:65` type: .replaceComponent(componentType: .infusionSet)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1062` emitPumpEvents([NewPumpEvent.siteChange(date: date)], replacePendingEvents: false)
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitFillCannulaViewModel.swift:172` pumpManager?.recordSiteChange(primeAmount: primeAmount) on successful fill only
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:118` default: continue — CannulaFilledHistoryLog is dropped

- Recommendation: Keep the UI path; additionally map CannulaFilledHistoryLog to .replaceComponent(.infusionSet) with a logSequence raw so pump-UI site changes are captured once history emission is wired. Add a MockPumpManagerDelegate assertion for the emitted event.

- Verifier notes:
  - [review:amend] Code fact holds: recordSiteChange emits .replaceComponent(.infusionSet) with replacePendingEvents:false and a unique date-based raw, and Trio maps it to siteChange. The only conformance gap the finding named was a cannula fill done on the pump's own screen (CannulaFilledHistoryLog dropped by the mapper). Under the premise (no pump screen, Tandem app not in use) a cannula fill can only happen through TandemKit's wizard, so that trigger is not_applicable per the pump-screen clause. The missing test is a section 11 testing note, not a conformance defect. Amend to conforms/none.

**P14-4 Cartridge change reported as .rewind, no prime event** (Partial, impact low, verified)

Cartridge replacement is emitted as .rewind (Medtronic idiom) rather than the guide's .replaceComponent(componentType: .reservoir), which the pinned LoopKit supports. LoopKit accepts either; the difference is only how the consumer app renders/handles it. The fill-tubing wizard (TandemKitFillTubingViewModel) records no event at all, so no .prime event exists. Both flows fire only from the TandemKitUI wizards; CartridgeFilledHistoryLog and TubingFilledHistoryLog are ignored by the mapper, so cartridge/tubing changes done on the pump screen are not reported. Timing: the event date is app-side Date.now at detection completion, not the pump's timestamp.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:78` type: .rewind for cartridgeChange (not .replaceComponent(.reservoir))
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1071` emitPumpEvents([NewPumpEvent.cartridgeChange(date: date)], replacePendingEvents: false)
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitChangeCartridgeViewModel.swift:319` pumpManager?.recordCartridgeChange() in finishDetecting()
  - `Tests/TandemKitTests/TandemKitChangeCartridgeViewModelTests.swift:214` asserts lastCartridgeChangeDate only, not the emitted NewPumpEvent
  - `reference: loopkit-trio/PumpEventType.swift:89` ReplaceableComponent has case reservoir

- Recommendation: Consider emitting .replaceComponent(.reservoir) (optionally alongside .rewind) for cartridge change and a .prime event after fill tubing; map CartridgeFilled/TubingFilled history logs for pump-UI changes. Confirm which type the host app (Trio) handles.

- Verifier notes:
  - [review:confirm] Code fact holds: cartridge change is emitted as .rewind from the wizard only, and TandemKitFillTubingViewModel records no event, so no .prime exists. Under the premise the pump-screen sub-part (CartridgeFilled/TubingFilled logs) is not_applicable, and the .rewind-vs-.replaceComponent(.reservoir) point is moot in practice since Trio handles .rewind but not .replaceComponent(.reservoir). The remaining defect, no .prime after the app-driven fill-tubing wizard, is app-side and still violates the section 9 checklist item. partial/low stands on that narrower basis.

**P14-5 No .replaceComponent(.pump) on pairing a different pump** (Non-conforming, impact low, verified)

A grep for replaceComponent across Sources finds only the .infusionSet case. When a user pairs a replacement t:slim X2/Mobi (new serial), fetchPumpInformation silently overwrites pumpSerial; the only serial-change logic is HistoryBackfillState.matching, which restarts backfill bookkeeping and does not emit anything. So the host never receives .replaceComponent(.pump), unlike OmnipodKit's pod-change event that §5/§10 reference. This holds on first sync after pairing and after relaunch. Dose accounting is unaffected (Loop's IOB is app-side), but the pump-event log lacks the marker that lets the consumer reset pump-specific state or display the change.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1112` pairPump stores pincode and connects; no event emitted
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:103` state.pumpState.pumpSerial = pumpVersionResponse.serialNumber — overwritten without comparing to the prior serial
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1137` deleteSavedPumpState resets PumpState() before re-setup; nothing reported
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillState.swift:67` guard self.pumpSerial == pumpSerial — only the backfill bookkeeping reacts to a replacement pump

- Recommendation: In fetchPumpInformation, compare the new serialNumber with the persisted pumpSerial; when it differs (or on first successful pairing), emit NewPumpEvent(type: .replaceComponent(componentType: .pump)) with raw derived from the new serial, replacePendingEvents:false. Test via StubPumpBluetooth.

- Verifier notes:
  - [review:confirm] Code fact holds: the only .replaceComponent in Sources is the .infusionSet case; fetchPumpInformation overwrites pumpSerial without comparison; pairPump and deleteSavedPumpState emit nothing; only HistoryBackfillState.matching reacts to a serial change. Pairing a replacement pump is an app-side action unaffected by the premise. Dose accounting is unaffected, so nonconforming/low stands.

**P14-6 Linux shim cannot express alarmType** (Partial, impact none, verified)

Any fix for P14-2 (passing alarmType) would not compile on Linux until the shim gains PumpAlarmType and the alarmType initializer parameter, since CI runs the Linux build. The shim's PumpComponent name differs from LoopKit's ReplaceableComponent, but TandemKit only uses the associated-value shorthand so no drift is exposed today. Purely a build-surface issue, no accounting impact.

- Evidence:
  - `LinuxShims/LoopKit/LoopKit.swift:538` NewPumpEvent has no alarmType field; PumpAlarmType is not defined in the shim
  - `LinuxShims/LoopKit/LoopKit.swift:517` public enum PumpComponent — real LoopKit names this ReplaceableComponent
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:65` uses inferred .replaceComponent(componentType: .infusionSet), so it compiles against both

- Recommendation: Extend LinuxShims/LoopKit/LoopKit.swift with PumpAlarmType (autoOff, lowInsulin, lowPower, noDelivery, noInsulin, noPower, occlusion, other(String)) and an alarmType parameter on NewPumpEvent.init before populating alarmType in the mapper.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

Open questions raised by this point:

- The real LoopKit PumpAlarmType.swift is not among the reference files on disk; the case list assumed above (autoOff, lowInsulin, lowPower, noDelivery, noInsulin, noPower, occlusion, other) should be verified against the loopandlearn fork Trio pins.
- Whether Trio (the consumer) handles .replaceComponent and .rewind pump events (guide §10 notes MedtrumKit #114 was a Trio-side gap) is outside this repo and was not verified.
- When an occlusion/empty-cartridge alarm stops delivery, does CurrentBasalStatusResponse.basalType report .suspend so fetchBasalStatus (+StateSync.swift:150-165) emits a suspend dose? If not, delivery stops caused by faults are not captured as doses either; needs hardware confirmation.
- docs/tandemkit-history-integration-plan.md:211 presents the AlarmActivated/AlertActivated -> NewPumpEvent(.alarm) mapping as part of the plan; CLAUDE.md states the mapper is not wired to any emission path. The code matches CLAUDE.md.
- LoopKit also defines .alarmClear; TandemKit never emits it. The guide does not require it, so it is not scored here.
### P15. Tests cover BLE loss mid-bolus and mid-temp-basal, verifying the dose is recovered and finalized with the pump's delivered amount, not dropped or duplicated

Guide section: §11 testing: interrupt everything.

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 6 of 6 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

No test interrupts a bolus or a temp basal and asserts on the NewPumpEvents Loop receives. The only "BLE dropped mid-bolus" test (TandemPumpManagerBolusSyncTests.testSyncReconcilesAfterGraceExpires) checks a boolean gate, not that the dose is finalized with the pump's delivered volume. Nothing exercises a temp basal across a drop at all. State-persistence round-trips are tested, but no test rebuilds a manager from persisted in-progress state and syncs. The harness can model unanswered requests and connect failures, but has no link-drop/reconnect event, and MockPumpManagerDelegate discards lastReconciliation/replacePendingEvents and flattens batches, so "not dropped, not duplicated" cannot be asserted today. Reading the code, the relaunch path clears an in-progress bolus without a finalizing event, which such a test would have caught.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P15-1 | Non-conforming | high | verified | Mid-bolus BLE loss: recovery/finalization untested |
| P15-2 | Non-conforming | medium | amended | Mid-temp-basal BLE loss: no coverage at all |
| P15-3 | Partial | low | verified | Harness can model drops, not disconnect/reconnect events |
| P15-4 | Non-conforming | low | verified | MockPumpManagerDelegate cannot verify drop/duplicate semantics |
| P15-5 | Partial | medium | verified | App relaunch: persistence tested, recovery-after-restore not |
| P15-6 | Partial | low | verified | History-based recovery tested in isolation, not end to end |

**P15-1 Mid-bolus BLE loss: recovery/finalization untested** (Non-conforming, impact high, verified)

The single test that mentions BLE loss mid-bolus verifies only that the sync gate reopens after the 30 s grace; it never drives enactBolus, drops the link, reconnects, and inspects hasNewPumpEvents. Nothing asserts that the finalized bolus carries the LastBolusStatus deliveredVolume rather than the programmed total. An interruption test would also expose that when bolusProgressReport is nil (app relaunch, or any path that recreated the manager) fetchBolusStatus clears state.bolusDose without emitting a finalized event, so the mutable bolus emitted at enactBolus is left for DoseStore's next replacePendingEvents:true purge.

- Evidence:
  - `Tests/TandemKitTests/TandemPumpManagerBolusSyncTests.swift:41` Doc comment names the scenario: 'BLE dropped mid-bolus; the pump does not replay missed qualifying events'
  - `Tests/TandemKitTests/TandemPumpManagerBolusSyncTests.swift:48` Only assertion: XCTAssertFalse(manager.shouldDeferBolusSync(at: now)) — no delegate, no events
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:256` Finalize path queries pump: actualDelivered = queryLastBolusDeliveredVolume(bolusId:) — never asserted by any test
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:217` if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil { state.bolusDose = nil } — no event emitted
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:70` internal var bolusProgressReport — in-memory only, not part of persisted state

- Recommendation: Add a StubPumpBluetooth test: enactBolus succeeds, CurrentBolusStatusRequest is unanswered (enqueue nil), then answered with bolusId 0 and a LastBolusStatus deliveredVolume; assert exactly one bolus NewPumpEvent with isMutable false and deliveredUnits == pump value. Repeat with a manager rebuilt from persisted state.

- Verifier notes:
  - [review:confirm] Absence verified: the only BLE-drop bolus test asserts a boolean gate; no test drives enactBolus, reconnects and reads delegate events (no test reads MockPumpManagerDelegate.pumpEvents; mock discards lastReconciliation/replacePendingEvents). The relaunch defect it would catch is real: bolusProgressReport is in-memory, and fetchBolusStatus clears a persisted bolusDose without emitting. Trigger is app relaunch/BLE loss, unaffected by the premise. In Loop the mutable row is later purged by any replace:true batch (lost dose); Trio keeps the enact-time bolus at programmed units. High stands.

**P15-2 Mid-temp-basal BLE loss: no coverage at all** (Non-conforming, impact medium, amended)

No test enacts a temp basal, loses the pump (connect failure or unanswered CurrentBasalStatusRequest), reconnects, and checks that the temp basal is re-reported as mutable while running and later finalized with deliveredUnits derived from actual elapsed time — the MedtrumKit failure the guide calls out ('TBR discarded after a BLE reconnect'). The only test with a temp rate and a lost response is in the suspend flow and asserts on the command sequence, not on NewPumpEvents.

- Evidence:
  - `Tests/TandemKitTests/TandemPumpManagerSyncBasalTests.swift:5` File covers syncBasalRateSchedule (IDP segments), not temp basals
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1702` getActivePumpEvents is the only path that re-reports/finalizes a running temp basal; no test calls a caller of it after a drop
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` basalEntry = state.basalDose.toDoseEntry(isMutable: endDate == nil, ...) — finalization semantics untested
  - `Tests/TandemKitTests/TandemPumpManagerSuspendDeliveryTests.swift:51` Only temp-rate test with a lost response: StopTempRateRequest unanswered, asserts SuspendPumpingRequest still sent, not events
  - `Tests/TandemKitTests/TandemPumpManagerControlIQTests.swift:119` Temp basal seeded into state only to assert it is not cancelled; no event assertions

- Recommendation: Add tests: enactTempBasal → syncPumpData with connectError set (assert no event change, lastReconciliation unchanged) → sync succeeds with CurrentBasalStatus reporting .basal after estimatedEndDate; assert the temp basal event is finalized once, with stable raw, and a basal event follows.

- Verifier notes:
  - [review:amend] Coverage absence confirmed: enactTempBasal appears only in ValidationTests:99 (Control-IQ block); ControlIQTests:119 asserts non-cancel; the unanswered StopTempRate case is at SuspendDeliveryTests:81-89 (not :51) and checks command sequence only. But tracing the drop/reconnect path finds no lost or duplicated dose in the default case: basalDose is persisted, a failed sync emits nothing, and finalization caps endDate at estimatedEndDate so a TBR that ran out offline is finalized correctly. The gap hides no identified defect, so medium rather than high. Pump-stopped-early timing is a separate finding (P11-4/P13-4).

**P15-3 Harness can model drops, not disconnect/reconnect events** (Partial, impact low, verified)

The stub can express the two observable consequences of a BLE loss (connect failure, unanswered request) and can vary answers across successive syncs, so P15-1/P15-2 scenarios are expressible today. What cannot be expressed is the disconnect notification itself: the reconnect path in TandemBluetoothManager (cancel in-flight operations, mark link down, auto-reconnect) runs only against CoreBluetooth and is never reached through StubPumpBluetooth, so any dose-state side effects of that path are untestable without a hook on the protocol.

- Evidence:
  - `Tests/TandemKitTests/StubPumpBluetooth.swift:16` var connectError: Error? — makes ensureConnected fail
  - `Tests/TandemKitTests/StubPumpBluetooth.swift:44` 'Returning nil simulates a request the pump never answered'
  - `Tests/TandemKitTests/StubPumpBluetooth.swift:53` enqueue(_:responses:) answers successive writes differently — enough to sequence 'answered, then silent, then answered'
  - `Sources/TandemKit/PumpManager/PumpBluetoothConnection.swift:9` protocol PumpBluetoothConnection has no link-dropped/reconnected callback
  - `Sources/TandemKit/PumpManager/TandemBluetoothManager.swift:473` didDisconnectPeripheral → cancelPendingOperations/markLinkDown/auto-reconnect lives outside the stubbed surface

- Recommendation: Either add a test-visible 'linkDidDrop' entry point on TandemPumpManager driven from markLinkDown, or document that unit tests cover only the command-level consequences and hardware tests cover reconnect itself.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P15-4 MockPumpManagerDelegate cannot verify drop/duplicate semantics** (Non-conforming, impact low, verified)

Whether a mutable dose survives DoseStore depends on which call re-sent it and with what replacePendingEvents value (§3/§5 of the guide). The mock records neither the flag nor the per-call batch, and no test reads delegate.pumpEvents at all. So even if an interruption test were written today, it could not distinguish 'dose dropped' (omitted from a replacePendingEvents:true batch) from 'dose re-reported', nor detect a duplicate created by a changed raw.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:129` lastReconciliation _: Date? — discarded
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:130` replacePendingEvents _: Bool — discarded
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:133` _pumpEvents += events — batches flattened, call boundaries lost
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:45` didReceivePumpEventsExpectation exists but no test sets it (grep: no callers outside the mock)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:600` enactBolus emits with replacePendingEvents: false — the flag the mock cannot observe

- Recommendation: Record each hasNewPumpEvents call as (events, lastReconciliation, replacePendingEvents) and add a helper that folds the calls the way DoseStore.addPumpEvents would, keyed by raw, so tests can assert the surviving dose set.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P15-5 App relaunch: persistence tested, recovery-after-restore not** (Partial, impact medium, verified)

The guide's 'persist the UnfinalizedDose' advice is honoured and its serialization is tested. But no test constructs a TandemPumpManager from a state carrying an in-progress bolus or temp basal and runs syncPumpData/fetchBolusStatus to check what Loop is told. That is the exact scenario where bolusProgressReport (memory only) is nil, so the code path differs from steady state; the missing test hides that the restored bolus is either cleared silently (status .alreadyDeliveredOrInvalid) or never finalized.

- Evidence:
  - `Tests/TandemKitTests/TandemPumpManagerStateTests.swift:115` testInProgressBolusRoundTrips: bolusDose incl. deliveredUnits/bolusId survives rawValue round-trip
  - `Tests/TandemKitTests/TandemPumpManagerStateTests.swift:145` testTempBasalRoundTripsThroughBasalDose: basalDose tempBasal survives round-trip
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:226` guard let progressReport = bolusProgressReport else { return } — restored bolus can never reach the finalize branch
  - `Tests/TandemKitTests/TandemPumpManagerBolusSyncTests.swift:6` makeManager seeds state.bolusDose directly but only queries shouldDeferBolusSync

- Recommendation: Add a relaunch test: build state with bolusDose past estimatedEndDate, construct manager, stub CurrentBolusStatus (bolusId 0 or alreadyDelivered) and LastBolusStatus; assert a finalized bolus event with the pump's deliveredVolume and same raw as the original.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: testInProgressBolusRoundTrips and testTempBasalRoundTripsThroughBasalDose exist (115, 145); no test constructs a manager from such a state and syncs; the reporter guard at 226 makes that path differ from steady state.

**P15-6 History-based recovery tested in isolation, not end to end** (Partial, impact low, verified)

The component that would recover a dose from the pump's own log after a drop (HistoryToDoseMapper) has good unit coverage for interrupted and completed records and stable raw identity, and the fetcher is tested for duplicate suppression. However grep finds no production caller of HistoryToDoseMapper and both history flags default off, so these tests verify a component that has no emission path; nothing tests that a bolus interrupted by BLE loss is finalized from history at the manager level. The project's own plan still lists disconnect/reconnect dedup as an unchecked hardware item.

- Evidence:
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:124` testActivationWithoutCompletionIsMutable — interrupted-bolus record maps to isMutable true, deliveredUnits nil
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:33` testMatchedBolusProducesFinalizedDose — completion record yields deliveredUnits from insulinDelivered
  - `Tests/TandemKitTests/TandemPumpManagerHistoryIntegrationTests.swift:194` testDuplicateStreamEntriesAreReportedOnce — re-streamed chunks reach onLog once
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:32` historyBackfill and historyDoseReporting defaultValue false
  - `docs/tandemkit-history-integration-plan.md:625` '[ ] Disconnect/reconnect, verify deduplication' — listed as unchecked manual hardware step

- Recommendation: When the emission layer is wired, add a manager-level test under historyBackfill+historyDoseReporting: mutable bolus from enactBolus, drop, then history stream returns BolusCompleted; assert one finalized event and no duplicate of the command-path event.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

Open questions raised by this point:

- Outside P15's scope but observed while tracing: TandemPumpManager+StateSync.swift:217-224 clears state.bolusDose on .alreadyDeliveredOrInvalid when bolusProgressReport is nil without emitting a finalized bolus event; whether DoseStore then purges the mutable bolus emitted at enactBolus (TandemPumpManager.swift:598-600) on the next replacePendingEvents:true call should be confirmed by whichever point owns the mutable-dose lifecycle (P3/P4).
- The command-path raw for a bolus is built from units and the ISO8601 date (NewPumpEvent.swift:10) while the finalize path passes deliveredUnits as `units` (StateSync:260 via TandemDoseProgressReporter.getPumpEvent:44); whether that changes the raw between the mutable and final report is a P4 (stable syncIdentifier) question, not settled here.
- Whether the auto-reconnect path in TandemBluetoothManager (didDisconnectPeripheral → ensureConnected) triggers any dose-state reconciliation on reconnect could not be determined from the stubbed test surface; hardware or an added hook would settle it.
### P16. Tests cancel a bolus and a temp basal at various points and verify the finalized dose shows the partial delivered amount and an unchanged syncIdentifier

Guide section: §11 testing: cancel everything.

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 5 of 5 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

TandemKit has no test that cancels an app-initiated bolus or temp basal and inspects the finalized dose. `cancelBolus` (TandemPumpManager.swift:607) and the zero-duration/percent-100 temp-basal cancel branch (663-747) are never exercised by TandemKitTests; the only cancel-named coverage is CancelBolusRequest serialization and HistoryToDoseMapper tests for a layer with no emission consumer. No test reads the mock delegate's `pumpEvents`, and the mock drops `lastReconciliation`/`replacePendingEvents`, so the §11 assertions (partial deliveredUnits, isMutable false, real endDate, unchanged syncIdentifier) cannot be made today. Had they existed, the bolus assertion would fail: enact keys the event on programmed units, cancel re-keys it on delivered units. Temp-basal identity is stable but equally untested.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P16-1 | Non-conforming | medium | verified | App-side bolus cancel has no test |
| P16-2 | Non-conforming | medium | verified | Temp basal cancel has no dose-level test |
| P16-3 | Non-conforming | low | verified | Test harness cannot observe hasNewPumpEvents arguments |
| P16-4 | Non-conforming | low | amended | Bolus cancel changes syncIdentifier; test would fail |
| P16-5 | Partial | low | verified | Only history-mapper layer has cancel coverage |

**P16-1 App-side bolus cancel has no test** (Non-conforming, impact medium, verified)

A repo-wide search of Tests/ finds no call to `manager.cancelBolus`. The path that §11 asks to exercise — cancel after N units, query LastBolusStatus, finalize with partial `deliveredUnits`, `isMutable:false`, `endDate: Date.now` (line 641) — is untested on every route (steady state, first sync, reconnect, relaunch). The `?? 0` fallback on line 639 (a failed or mismatched LastBolusStatus reply finalizes the cancelled bolus as 0 U delivered) is exactly the kind of behaviour such tests would pin down; it is currently unverified. `StubPumpBluetooth` can already stub `CancelBolusRequest` and `LastBolusStatus*Request`, so the harness is sufficient to write these.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:607` public func cancelBolus(completion:) exists and emits a finalized dose
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0
  - `Tests/TandemCoreTests/Messages/Control/CancelBolusRequestTests.swift:5` only cancel-named test: wire serialization of CancelBolusRequest
  - `Tests/TandemKitTests/TandemPumpManagerBolusSyncTests.swift:24` BolusSync tests cover shouldDeferBolusSync only, never cancelBolus

- Recommendation: Add TandemPumpManagerCancelBolusTests: stub BolusPermission/InitiateBolus, enact, stub CancelBolusResponse(wasCancelled) and LastBolusStatus with a partial volume, call cancelBolus, assert the finalized event's deliveredUnits, isMutable, endDate and raw. Include a case where LastBolusStatus fails to decide what 0-vs-nil should mean.

- Verifier notes:
  - [review:confirm] Repo-wide grep of Tests/ finds no call to cancelBolus; the only cancel-named test is CancelBolusRequest wire serialization. The untested path finalizes with deliveredUnits = queryLastBolusDeliveredVolume ?? 0 and endDate Date.now, emitted with replacePendingEvents default true. StubPumpBluetooth can stub CancelBolusRequest and LastBolus requests, so the test is writable. Cancel is app-initiated, unaffected by the premise. The ?? 0 defect itself is rated separately (P05-2/P07-1/P23-2).

**P16-2 Temp basal cancel has no dose-level test** (Non-conforming, impact medium, verified)

The cancel branch of `enactTempBasal` (zero duration or percent 100) and the StopTempRate sent by `suspendDelivery` (line 802) and by Control-IQ enable (line 1317) all finalize the running temp basal through `getActivePumpEvents(endDate:)`, computing partial `deliveredUnits` from the elapsed window. No test asserts on that finalized dose: SuspendDeliveryTests check only the command sequence and `state.basalDose.type`; ControlIQTests:129 checks StopTempRate was *not* sent; ValidationTests check only the block. Nothing verifies deliveredUnits, endDate, isMutable, or raw stability at early, mid, or near-end cancel points, nor the `endDate == estimatedEndDate` scheduled-basal append at line 1715.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:725` if duration < .ulpOfOne || percent == 100 { // We only needed to cancel
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:736` var events = self.getActivePumpEvents(endDate: dose.startDate) finalizes the running TBR
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` deliveredUnits: isMutable ? nil : value * (duration / .hours(1))
  - `Tests/TandemKitTests/TandemPumpManagerValidationTests.swift:99` only enactTempBasal test asserts the Control-IQ block, never a cancel
  - `Tests/TandemKitTests/TandemPumpManagerSuspendDeliveryTests.swift:58` XCTAssertEqual(sentTypes, ["TempRateRequest", "StopTempRateRequest", "SuspendPumpingRequest"])

- Recommendation: Add cancel-temp-basal tests: enact a TBR, advance the clock (inject a date provider or set basalDose.startDate), call enactTempBasal(rate, for: 0) and suspendDelivery; assert the finalized tempBasal event's deliveredUnits = rate * elapsed, endDate, isMutable false, and raw equal to the enact-time raw.

- Verifier notes:
  - [review:confirm] All three StopTempRate paths verified: enactTempBasal cancel branch (725-743), suspendDelivery (801-802, finalizing via getActivePumpEvents(endDate:) at 821), Control-IQ enable (1316-1317). Finalized deliveredUnits = value*(duration/1h) at UnfinalizedDose:190. No test asserts on those events: SuspendDeliveryTests checks sentTypes and basalDose.type, ControlIQTests:129 checks StopTempRate not sent, ValidationTests:99 checks the block. App-triggered; premise does not apply. Medium is right for a dose-level coverage gap.

**P16-3 Test harness cannot observe hasNewPumpEvents arguments** (Non-conforming, impact low, verified)

No test in the repo reads `delegate.pumpEvents` (search for `.pumpEvents` in Tests/ returns nothing); the mock is used only for reservoir readings and status updates. The mock also drops `replacePendingEvents` and `lastReconciliation` and merges all batches, so a test could not distinguish the enact-time `replacePendingEvents:false` (TandemPumpManager.swift:600) from the cancel-time `true` (657), which is what makes the current cancel end-state correct. Additionally, on Linux the shim's `NewPumpEvent` does not derive `syncIdentifier` from `raw`, so a §11 assertion on `dose.syncIdentifier` would pass vacuously there; TandemKitTests run on the simulator against real LoopKit (unit-tests.yml:258), where it would be meaningful.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:129` lastReconciliation _: Date?, replacePendingEvents _: Bool — both discarded
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:133` synchronized { _pumpEvents += events } flattens batches into one array
  - `LinuxShims/LoopKit/LoopKit.swift:544` shim NewPumpEvent.init never sets dose.syncIdentifier from raw
  - `reference: loopkit-trio/NewPumpEvent.swift:33` real LoopKit: dose?.syncIdentifier = raw.hexadecimalString

- Recommendation: Record each hasNewPumpEvents call as a struct (events, lastReconciliation, replacePendingEvents) in MockPumpManagerDelegate. In cancel tests assert on `event.raw` equality (as HistoryToDoseMapperTests:131 does) rather than only `dose.syncIdentifier`, so the check holds on both Linux and Xcode.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: grep over Tests/ finds no reader of the mock's pumpEvents; the mock discards lastReconciliation and replacePendingEvents (129-130) and flattens batches (133).

**P16-4 Bolus cancel changes syncIdentifier; test would fail** (Non-conforming, impact low, amended)

The §11 cancel test asserts the `syncIdentifier` never changed. TandemKit would fail it: the bolus `raw` embeds the units argument, which is the programmed amount at enact and the delivered amount at cancel (and at sync-side completion via `getPumpEvent`), so any partial delivery yields a different `raw`/`syncIdentifier`. This is the MedtrumKit anti-pattern the guide's §4 names. The end state is still correct only because cancel emits with `replacePendingEvents: true` (657 → 1733 default), purging the original mutable row by flag rather than by identity. The absence of the test is what lets this latent identity change persist unnoticed.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:599` enact: NewPumpEvent.bolus(dose: doseEntry, units: units, ...) — programmed units in key
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:652` cancel: .bolus(dose: canceledDose, units: canceledDose.deliveredUnits ?? 0, ...) — delivered units in key
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:251` raw: "\(DoseType.bolus.rawValue) \(units) \(date)"
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:44` natural completion also keys on `units: delivered`

- Recommendation: Key the bolus event on programmed units (or bolusId + startDate) in both enact and finalize paths so raw is byte-identical, then add the §11 assertion. Until fixed, the cancel test should at least assert the stale mutable row is purged (replacePendingEvents true) so the reliance is explicit.

- Verifier notes:
  - [review:amend] Claim correct: bolus raw embeds the units argument (programmed at enact 599, delivered at cancel 652 and completion). Evidence line is wrong: NewPumpEvent.swift is 81 lines; the raw is at line 10, not 251. Downstream, both finalize paths use replacePendingEvents true, so Loop purges the mutable PumpEvent row and soft-deletes the mutable InsulinDeliveryStore dose (excluded by deletedAt == NIL); Trio never reads raw and dedupes by (date,type), updating the smaller bolus amount. The mutable bolus is emitted only once, so no mid-life churn. Checklist §4 fails, but no accounting degradation: low.

**P16-5 Only history-mapper layer has cancel coverage** (Partial, impact low, verified)

The repo does contain cancel-shaped tests, but only for `HistoryToDoseMapper`, which maps pump history records to doses with a bolusId-keyed stable `raw` and partial `deliveredUnits`. That layer is not wired to any emission path (no reference to HistoryToDoseMapper outside Sources/TandemKit/PumpManager/History/), and the `historyBackfill`/`historyDoseReporting` flags default off. So the tests that do satisfy the §11 shape exercise code Loop/Trio never sees, while the live cancel paths (`cancelBolus`, `fetchBolusStatus` bolusId==0, `getActivePumpEvents(endDate:)`) have none. Coverage exists in the wrong place.

- Evidence:
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:105` testCancelledBolusKeepsProgrammedAndDeliveredDistinct: programmed 2.5, delivered 1.041
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:195` testEarlyCancelledTempBasalEndsAtCompletion: endDate = completion time
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:131` raw == HistoryLogSyncIdentifier.bolus(pumpSerial:bolusId:) — stable identity
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:217` live driver finalizes via CurrentBolusStatus/LastBolusStatus, not the mapper

- Recommendation: Keep the mapper tests, but add equivalent driver-level tests against the live paths. When the mapper is wired to emission, add a test that a history-finalized cancelled bolus and the live-path finalized one share one raw (today they cannot: bolusId-keyed vs units+date-keyed).

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

Open questions raised by this point:

- After an app relaunch `bolusProgressReport` is nil, so `fetchBolusStatus` (TandemPumpManager+StateSync.swift:217-223) clears a persisted in-progress `bolusDose` on `.alreadyDeliveredOrInvalid` without emitting a finalized dose; the mutable event from enact would then be purged on the next replacePendingEvents:true emission. This belongs to the interrupt/relaunch point but a relaunch-then-cancel test would expose it.
- `cancelBolus` finalizes with `deliveredUnits = 0` when `queryLastBolusDeliveredVolume` returns nil (line 639), while the sync-side completion path passes nil through to `getPumpEvent`, which falls back to the full programmed total (TandemDoseProgressReporter.swift:33). The two failure fallbacks under-count and over-count respectively; which is intended should be settled and tested.
- The bolus `raw` uses ISO8601 to seconds and `Date.now` at UnfinalizedDose init; a cancel test should confirm `dose.startDate` (not a new Date) is passed as the event date on both enact (line 599) and cancel (652), which the code appears to do.
### P17. Tests re-report the same in-progress dose many times and confirm it stays a single dose with identical raw and no IOB drift

Guide section: §11 testing: idempotency.

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 6 of 6 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

No test in the repository re-reports an in-progress dose and checks that it remains a single dose with identical raw. On the live path this is unexercised end to end: no test reads MockPumpManagerDelegate.pumpEvents (the mock even discards lastReconciliation/replacePendingEvents), no test drives enactBolus/enactTempBasal followed by repeated syncs, and no test touches DoseStore/InsulinDeliveryStore or IOB. The history path has identity-level tests (HistoryLogSyncIdentifierTests, HistoryToDoseMapperTests raw asserts) plus fetch/store-tier dedupe tests, but never maps the same log twice and the path is not wired to hasNewPumpEvents. The live raw scheme (bolus units, temp-basal programmedUnits) is phase-dependent, which is exactly the latent bug an idempotency test would catch.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P17-1 | Non-conforming | medium | verified | Live path: no repeated-report test against the delegate |
| P17-2 | Non-conforming | low | amended | Live raw is phase-dependent; nothing tests raw equality across phases |
| P17-3 | Not applicable | none | verified | Driver never re-reports an in-progress dose in steady state |
| P17-4 | Partial | low | verified | History path: identity tests exist but never re-map the same log |
| P17-5 | Partial | low | verified | Fetch/store-tier dedupe is tested, but not at the dose tier |
| P17-6 | Non-conforming | medium | verified | No IOB or DoseStore-backed assertion anywhere in the test target |

**P17-1 Live path: no repeated-report test against the delegate** (Non-conforming, impact medium, verified)

A grep of Tests/ for `.pumpEvents` and `didReceivePumpEventsExpectation` finds no consumer outside the mock itself; the recording is dead infrastructure. The only tests that run more than one sync (ConnectionTests 178-233) stub no active dose and assert connection counts. No test calls enactTempBasal/cancelBolus/handleBolusResponse to completion with a delegate attached and then compares the raw of the mutable and finalized reports. The guide's §11 idempotency check (re-report many times, one dose, identical raw) is therefore not represented for the live path in any of the four states: steady state, first sync after pairing, after BLE reconnect, or after relaunch.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:133` mock records events: `synchronized { _pumpEvents += events }`
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:129` `lastReconciliation _: Date?, replacePendingEvents _: Bool` are discarded, so neither can be asserted
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:219` only test running two syncs asserts `ensureConnectedCount`, not events
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:25` `stubSyncResponses` stubs ApiVersion/InsulinStatus/Battery only — no running bolus or temp basal
  - `Tests/TandemKitTests/TandemPumpManagerValidationTests.swift:50` enactBolus tests cover only pre-flight rejection, no emitted events

- Recommendation: Add a manager-level test: stub SetTempRate/CurrentBasalStatus, enact a temp basal, run syncPumpData N times, then assert exactly one tempBasal raw across all delegate calls and identical raw on finalize. Extend the mock to record lastReconciliation and replacePendingEvents per call.

- Verifier notes:
  - [review:confirm] Verified: MockPumpManagerDelegate records events into _pumpEvents (flattened) and discards lastReconciliation/replacePendingEvents; grep of Tests/ finds no reader of .pumpEvents or didReceivePumpEventsExpectation. The only multi-sync tests (ConnectionTests 178-233) stub ApiVersion/InsulinStatus/Battery and assert ensureConnectedCount. ValidationTests enactBolus cases assert pre-flight rejection only. No live-path idempotency test exists in any state. App-side harness gap, unaffected by premise.

**P17-2 Live raw is phase-dependent; nothing tests raw equality across phases** (Non-conforming, impact low, amended)

The live bolus raw is keyed on whichever units value the call site passes: programmed at enact, delivered at completion/cancel. Whenever delivered differs from programmed (any cancel, any pump-side rounding) the finalized event carries a different raw and syncIdentifier than the mutable one. Temp basal raw embeds programmedUnits, which for unitsPerHour is value*hours (loopkit-trio DoseEntry.swift:68-74); the mutable report uses estimatedEndDate, the finalized one the actual endDate, so an early stop changes raw. This is the MedtrumKit anti-pattern the guide flags in §4. The end state is rescued only by the `replacePendingEvents: true` purge. No test asserts raw equality between an enact-time event and its completion/cancel event, so this is invisible to CI.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:10` bolus raw: `"\(DoseType.bolus.rawValue) \(units) \(date)"` — units is a caller argument
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:599` enactBolus passes programmed `units: units`
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:44` completion passes `units: delivered` (pump-reported volume)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:651` cancelBolus passes `units: canceledDose.deliveredUnits ?? 0`
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:20` tempBasal raw embeds `dose.programmedUnits` (= value * hours, so it moves with endDate)

- Recommendation: Add tests asserting `raw` byte-equality between the enact-time mutable event and the completion and cancel events for bolus and temp basal; key raw on programmed units and a fixed start (or bolusId/tempRateId) so the tests pass.

- Verifier notes:
  - [review:amend] Facts verified: bolus raw keyed on the units argument (line 10), passed programmed at enact, delivered at completion (reporter :44) and cancel (:652); tempBasal raw embeds dose.programmedUnits = value*hours (loopkit-trio DoseEntry:68-74), with the finalized endDate differing from the mutable estimatedEndDate on early stop. No test asserts raw equality across phases. However mutable re-reports keep a stable raw (estimatedEndDate fixed), the key changes only at finalization, and every finalize path uses replacePendingEvents true, so Loop's end state is one dose; Trio ignores raw. Latent, not active: low.

**P17-3 Driver never re-reports an in-progress dose in steady state** (Not applicable, impact none, verified)

An idempotency test presupposes the driver re-sends the same mutable dose on each sync. TandemKit does not: emitPumpEvents is reached only on transitions (enact, cancel, completion, suspend/resume, basal-type change, site/cartridge change). A running temp basal or bolus is reported once at enact and then silent until it ends, and the periodic sync never sends an events batch (empty or otherwise). So there is currently no repeated-report behaviour to test — the §11 scenario is not applicable to the code as written. This is itself a §3 report-or-delete concern (a mutable dose reported once and then omitted from a later `replacePendingEvents: true` batch is deleted by DoseStore), but that belongs to the P-points covering §3/§6, not this one.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:430` syncPumpData runs fetchBolusStatus(fromSync:)/fetchBasalStatus, no unconditional emit
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:141` fetchBasalStatus emits only `if activeBasalType != state.basalDose.type`
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:202` `if fromSync, shouldDeferBolusSync() { ... return }` — bolus in progress is skipped entirely
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:238` delivering branch updates state.bolusState and progress observers, no emitPumpEvents
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:303` deliverStateMissedByTheDelegate re-pushes status/reservoir only, not doses

- Recommendation: Once re-reporting on every sync is implemented (see §3 findings), add the idempotency test from P17-1 at the same time; write it first so it fails until re-reporting lands.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: quiet syncs emit nothing (fetchBasalStatus 141, deferred bolus read 202). The accounting consequence of that silence is P04-1's finding, not this test point's.

**P17-4 History path: identity tests exist but never re-map the same log** (Partial, impact low, verified)

The history scheme is designed for idempotency — raw is derived from (pumpSerial, bolusId/tempRateId/sequenceNum), never from delivered units or end time — and the tests lock the wire format and check that the mutable activation and the finalized activation+completion each produce the scheme identifier. What is missing is the §11 shape: no test runs mapToEvents twice over the same logs (or over activation alone, then activation+completion) and asserts the raw is byte-identical across the two calls and that a consumer would see one dose. Also, per CLAUDE.md and the grep, HistoryToDoseMapper is not wired to any emission path and `historyBackfill`/`historyDoseReporting` default off, so even a perfect mapper test does not demonstrate delegate-level idempotency today.

- Evidence:
  - `Tests/TandemKitTests/HistoryLogSyncIdentifierTests.swift:39` testSameBolusIdFromDifferentPhasesMatches compares two constructions of the same id
  - `Tests/TandemKitTests/HistoryLogSyncIdentifierTests.swift:16` testWireFormatIsFrozen pins golden bytes so identity cannot silently drift
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:131` mutable activation asserts `event.raw == HistoryLogSyncIdentifier.bolus(..., bolusId: 9)`
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:49` finalized bolus asserts the same scheme with bolusId 7 — but a different test, different id
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:18` mapper class exists; grep finds no emitPumpEvents/hasNewPumpEvents in the History layer

- Recommendation: Add a mapper test that maps [activation] then [activation, completion] for the same bolusId and asserts equal raw and a single event per call; when the emission layer is wired, promote it to a delegate-level test behind the historyDoseReporting flag.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P17-5 Fetch/store-tier dedupe is tested, but not at the dose tier** (Partial, impact low, verified)

These tests establish that re-delivering the same history entries does not create duplicate rows in the session store and that a re-streamed chunk reaches the fetcher's callback once. That is a necessary precondition for dose-level idempotency and is well covered. It is not the §11 check, though: nothing here converts entries to NewPumpEvent or checks what a DoseStore would hold. Note testRepeatFetchIsServedFromStore shows that a repeat fetch does re-deliver every stored entry to onLog, so whatever emission layer is built on top will receive the same logs again on every window — making the raw-stability tests in P17-4 load-bearing rather than optional.

- Evidence:
  - `Tests/TandemKitTests/TandemPumpManagerHistoryIntegrationTests.swift:194` testDuplicateStreamEntriesAreReportedOnce — pump re-streams chunk, onLog fires once
  - `Tests/TandemKitTests/HistoryLogStoreTests.swift:88` testInsertIgnoresDuplicateSequenceNumbers — insert-ignore on (pumpSerial, sequenceNum)
  - `Sources/TandemKit/PumpManager/History/HistoryLogStore.swift:48` contract: `Idempotent by contract, matching ControlX2's onConflict = IGNORE`
  - `Tests/TandemKitTests/TandemPumpManagerHistoryIntegrationTests.swift:308` testRepeatFetchIsServedFromStoreWithoutChunkRequests — second fetch replays stored entries to onLog

- Recommendation: Keep these; add the dose-tier counterpart described in P17-4 so the store's idempotency is shown to carry through to identical raw on repeated emission.

- Verifier notes:
  - [review:confirm] Code facts hold: fetch/store-tier dedupe tests exist and HistoryLogStore documents insert-ignore, while no test maps the same log twice to NewPumpEvent. The trigger is batch composition and re-emission by the app, so the premise does not change it. Remains partial/low; the dose-tier idempotency gap is unexercised, and the history path is unwired regardless of pump archetype.

**P17-6 No IOB or DoseStore-backed assertion anywhere in the test target** (Non-conforming, impact medium, verified)

The guide's idempotency criterion is stated as 'stays a single dose in the InsulinDeliveryStore and IOB doesn't drift'. A grep for DoseStore, InsulinDeliveryStore and insulinOnBoard across Tests/TandemKitTests finds no code references — only comments and pump-message `iob` fields. The test target never feeds reported events into anything that computes IOB, and the Linux shim has no store types, so such a test would need a lightweight in-test model of DoseStore's purge/un-delete semantics (mutable==YES purge on replacePendingEvents, syncIdentifier matching) rather than real LoopKit. Absent that, IOB drift from duplicate or dropped mutable doses cannot be detected by CI on any path.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:9` the only delegate in tests is a recording mock; no DoseStore/InsulinDeliveryStore is instantiated
  - `Tests/TandemKitTests/HistoryBackfillCoordinatorTests.swift:210` IOB appears only in comments explaining why the walk depth matters
  - `LinuxShims/LoopKit/LoopKit.swift:1` Linux shim defines no DoseStore/InsulinDeliveryStore, so a store-backed test could not compile on Linux CI

- Recommendation: Add a small test double that mirrors DoseStore.addPumpEvents semantics (purge mutable when replacePendingEvents, dedupe by raw) and feed the mock's recorded calls through it; assert one dose and stable summed units after N re-reports.

- Verifier notes:
  - [review:confirm] Verified: grep of Tests/TandemKitTests for DoseStore/InsulinDeliveryStore finds nothing; IOB appears only in comments and pump-message iob fields; the Linux shim defines neither store type, so a real-store test cannot compile on Linux CI. Only a test double mirroring addPumpEvents/addDoseEntries semantics could assert 'single dose, no IOB drift'. Harness gap independent of the premise; medium consistent with the sibling §11 gaps.

Open questions raised by this point:

- The driver does not re-report a running bolus or temp basal on subsequent syncs (fetchBasalStatus emits only on basal-type change; fetchBolusStatus(fromSync:) defers while a bolus runs). Under the guide's §3 report-or-delete rule, a mutable dose omitted from a later replacePendingEvents: true batch is deleted by DoseStore. This affects §3/§5/§6 points more than P17 and should be assessed there.
- MockPumpManagerDelegate discards lastReconciliation and replacePendingEvents, so §6 empty-sync and §5 flag-choice tests cannot currently be written either; the same mock extension would unblock P17 and those points.
- Whether Apple-platform test runs (real LoopKit linked) could instantiate a DoseStore in-process for a true InsulinDeliveryStore-level idempotency check was not determined from the code; the Linux shim clearly cannot.
### P18. Tests confirm a sync with no new doses still calls hasNewPumpEvents and advances lastReconciliation

Guide section: §11 testing: empty syncs.

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 9 of 9 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

No test confirms that an empty sync calls hasNewPumpEvents, and none could: MockPumpManagerDelegate discards the lastReconciliation and replacePendingEvents arguments and no test reads its recorded pumpEvents or arms the events expectation. The reason is structural: syncPumpData advances state.lastReconciliation but never calls emitPumpEvents; fetchBasalStatus and fetchBolusStatus emit only on a change, so a steady-state sync makes no delegate dose call and DoseStore.lastPumpEventsReconciliation is not advanced. Existing ConnectionTests do pin the state/completion-callback half well (advances on any response, not on connect failure or a silent pump, persisted across relaunch). The delegate half of the §6/§11 contract is untested and, in production, unimplemented.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P18-1 | Non-conforming | medium | verified | No test asserts hasNewPumpEvents on a sync |
| P18-2 | Non-conforming | medium | verified | Empty sync never calls hasNewPumpEvents in production |
| P18-3 | Partial | low | verified | State-level lastReconciliation advancement is well tested |
| P18-4 | Non-conforming | low | verified | Mock delegate cannot observe lastReconciliation or call count |
| P18-5 | Non-conforming | medium | verified | First sync after pairing: no delegate, events dropped, untested |
| P18-6 | Partial | low | verified | Relaunch: skip-if-fresh path returns persisted date without delegate call |
| P18-A1 | Partial | medium | verified | Reservoir read alone advances lastReconciliation without any delegate event call |
| P18-A2 | Conforms | none | amended | Test pins lastReconciliation advancing on any single response, not a delivery read |
| P18-A3 | Partial | low | verified | emitPumpEvents reads lastReconciliation lazily on the delegate queue |

**P18-1 No test asserts hasNewPumpEvents on a sync** (Non-conforming, impact medium, verified)

A repo-wide search of Tests/ finds no reference to delegate.pumpEvents, didReceivePumpEventsExpectation, hasNewPumpEvents or replacePendingEvents outside the mock itself. The only tests that attach MockPumpManagerDelegate (telemetry reservoir, PumpConnectionIssue, ReservoirReportDelivery, HistoryBackfillCoordinator) assert on reservoir readings, status updates or the emit floor. The sync tests in ConnectionTests run syncPumpData without any delegate. Git history (9e551d0, 33d2445) shows earlier inline test delegates also discarded hasNewPumpEvents, so this coverage never existed. The §11 'Empty syncs' recommendation is therefore not represented in the suite.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:133` synchronized { _pumpEvents += events } -- events recorded, but no test reads pumpEvents
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:45` var didReceivePumpEventsExpectation: XCTestExpectation? -- never set by any test
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:104` testSuccessfulSyncAdvancesLastReconciliation attaches no delegate at all
  - `Tests/TandemKitTests/TandemPumpManagerTelemetryTests.swift:133` XCTAssertNotNil(manager.state.lastReconciliation) -- state-level only, delegate events unchecked

- Recommendation: Add a ConnectionTests case: attach MockPumpManagerDelegate, stub sync responses with basal type equal to state.basalDose.type and no bolus, run syncPumpData, and assert hasNewPumpEvents was invoked once with [] and lastReconciliation == state.lastReconciliation.

- Verifier notes:
  - [code:amend] Core claim verified: no current test references delegate.pumpEvents, didReceivePumpEventsExpectation, or asserts hasNewPumpEvents; ConnectionTests attach no delegate. One key fact is wrong: at 33d2445 TandemPumpManagerHistoryIntegrationTests had a CapturingPumpManagerDelegate that captured hasNewPumpEvents and asserted XCTAssertNotNil(lastReconciliation) (deleted in 9e551d0). So coverage of the delegate argument existed for history events, though never for an empty sync. Verdict and impact stand.
  - [review:confirm] Verified: no test reads delegate.pumpEvents or sets didReceivePumpEventsExpectation; ConnectionTests attach no delegate (setUp creates only StubPumpBluetooth and the manager); TelemetryTests:133 asserts state only. Git -S shows CapturingPumpManagerDelegate added in 35d1516 and removed in 9e551d0, matching the earlier amendment. Note the recommended test would fail today: syncPumpData (389-459) never calls emitPumpEvents; only fetchBasalStatus/fetchBolusStatus emit, and only on change — that production defect is P01-1/P18-2.

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
  - [review:confirm] Same defect as P01-1, re-verified from the P18 citations: 445 stamps, 450/253 send only state/status updates, 141 and 217 are the sync-path gates that return without emitting, and HistoryBackfillCoordinator has no emit path. Contradicts the pinned delegate doc comment (PumpManager.swift 57-58). Trigger is the app's sync, so the premise does not lower it. Trio ignores lastReconciliation (DeviceDataManager 608) so the accounting effect is Loop-only: lagging boundary, cut save range (968), and the reservoir branch (1217) substituting whole-unit reservoir doses for pump events in the lag window. Medium holds.

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
  - [review:confirm] Assertions at ConnectionTests 78/119/140/170 and the responseCount gate at TandemPumpManager 444-447 are unchanged. Under the Loop-only premise, state-level advancement on any status response is the correct value for lastReconciliation, so the tested half is right; what is still missing is any assertion that the same date reaches the host via hasNewPumpEvents. partial/low stands.

**P18-4 Mock delegate cannot observe lastReconciliation or call count** (Non-conforming, impact low, verified)

Even if a test were written, the current harness flattens all hasNewPumpEvents calls into one events array and drops lastReconciliation and replacePendingEvents. An invocation with events == [] is indistinguishable from no invocation, and the reconciliation date Loop would store is unobservable. The stub bluetooth (StubPumpBluetooth.responseCount) already provides what is needed on the pump side, so the gap is entirely in the delegate recorder.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:129` lastReconciliation _: Date?, -- argument discarded
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:130` replacePendingEvents _: Bool, -- argument discarded
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:36` var pumpEvents: [NewPumpEvent] -- flattened; an empty call leaves no trace

- Recommendation: Record each hasNewPumpEvents call as a struct {events, lastReconciliation, replacePendingEvents} in an ordered array, alongside the existing flattened pumpEvents, so tests can assert count, emptiness and the reported date.

- Verifier notes:
  - [code:confirm] Verified: the mock's hasNewPumpEvents signature discards lastReconciliation (129) and replacePendingEvents (130) with `_`, and appends events into one flattened array (133); the expectation at 45 is optional and unset by every test. An empty-events call is therefore unobservable except via the expectation, and the reported date is never observable. StubPumpBluetooth.responseCount exists (StubPumpBluetooth.swift:26).
  - [review:confirm] MockPumpManagerDelegate still discards lastReconciliation and replacePendingEvents with `_` (129-130) and flattens events into one array (133). This is a test-harness observability gap triggered by the app's own delegate calls, independent of pump archetype. nonconforming/low stands.

**P18-5 First sync after pairing: no delegate, events dropped, untested** (Non-conforming, impact medium, verified)

The pairing-time sync runs before the host adopts the manager (per the comment above reportReservoirReading). On that path emitPumpEvents discards anything it would have sent and no later flush replays it, so the first lastReconciliation is never delivered to DoseStore until a dose-changing event occurs. ReservoirReportDeliveryTests pin the analogous reservoir problem; no test covers the pump-event/lastReconciliation side of the same first-sync path.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1736` self.logger.warning("No pump delegate, not notifying...") -- pump events are dropped, not held
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:447` func flushPendingReservoirReading() -- reservoir has a replay path; pump events/lastReconciliation do not
  - `Tests/TandemKitTests/ReservoirReportDeliveryTests.swift:6` tests exist for the reservoir flush, none for pump events or lastReconciliation after the delegate attaches

- Recommendation: Mirror the reservoir flush: when a delegate attaches and state.lastReconciliation is set, emit hasNewPumpEvents with the current active events (or []) and that date; add a ReservoirReportDelivery-style test for it.

- Verifier notes:
  - [code:confirm] Verified: emitPumpEvents drops events when no delegate (1736) with no pending flag; deliverStateMissedByTheDelegate (called from the pumpManagerDelegate setter, 295) only calls notifyDelegateStateUpdated and flushPendingReservoirReading (306-307), so no pump event or lastReconciliation is replayed. The pairing path (TandemKitScanViewModel.onPairSuccess -> syncPumpData at :91) runs before the host adopts the manager, as the comment at StateSync 428-430 states. ReservoirReportDeliveryTests cover only the reservoir side.
  - [review:confirm] Verified: emitPumpEvents drops events with no delegate and sets no pending flag; deliverStateMissedByTheDelegate (from the delegate setter) only calls notifyDelegateStateUpdated and flushPendingReservoirReading; the pairing view model runs syncPumpData before adoption; ReservoirReportDeliveryTests cover the reservoir side only. Since syncPumpData itself never emits and fetchBasalStatus emits only on type change, the first lastReconciliation reaches DoseStore only with the next dose-changing event. Loop-only consequence (Trio discards lastReconciliation), pairing-path trigger, unaffected by premise.

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

**P18-A1 Reservoir read alone advances lastReconciliation without any delegate event call** (Partial, impact medium, verified, added by a verifier)

The auditor treated syncPumpData:445 as the place an empty sync advances lastReconciliation, but fetchReservoirStatus stamps it independently of the response-count gate, and is reachable on its own from the cartridge-change UI and from qualifying-event fetches (TandemPumpManager.swift:1688). Each of those advances state.lastReconciliation (feeding lastSync and the next emitPumpEvents date) with no hasNewPumpEvents call, so it is a second production path with the P18-2 gap. TelemetryTests:133 is actually pinning this reservoir-path behaviour, which the auditor attributed to sync.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:410` state.lastReconciliation = timestamp -- stamped by fetchReservoirStatus itself
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:392` completion(self.fetchReservoirStatus()) -- standalone command job callable outside syncPumpData
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitChangeCartridgeViewModel.swift:169` pumpManager?.fetchReservoirStatus { units in -- UI caller
  - `Tests/TandemKitTests/TandemPumpManagerTelemetryTests.swift:133` XCTAssertNotNil(manager.state.lastReconciliation) -- this asserts the reservoir-path stamp, not syncPumpData's

- Recommendation: Either drop the stamp from fetchReservoirStatus (let syncPumpData own it) or follow it with an empty hasNewPumpEvents; add a test that a standalone reservoir fetch does not advance lastReconciliation without informing the host.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: fetchReservoirStatus stamps lastReconciliation itself (410), is reachable standalone (392) and from the cartridge-change view model (169) and the .reservoirStatus qualifying fetch (1688), none of which calls hasNewPumpEvents. Loop-only.

**P18-A2 Test pins lastReconciliation advancing on any single response, not a delivery read** (Conforms, impact none, amended, added by a verifier (auditor said Partial))

The existing 'advances lastReconciliation' test enshrines that one answer of any kind (here a reservoir reading, with CurrentBasalStatusRequest and CurrentBolusStatusRequest unanswered) moves the trust boundary to now. For a UI-capable pump (guide §6) that claims delivery is accounted for when neither basal nor bolus status was read and no history was reconciled. The test suite therefore confirms advancement under conditions the guide says should not advance it; any P18 test added should not copy this fixture as the 'empty sync' case.

- Evidence:
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:158` only InsulinStatusRequest stubbed; basal/bolus reads return nil
  - `Tests/TandemKitTests/TandemPumpManagerConnectionTests.swift:170` XCTAssertNotEqual(manager.state.lastReconciliation, previousSync) -- asserted as desired behaviour
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:444` if self.bluetooth.responseCount > responsesBefore { -- any response, including alerts/time, counts

- Recommendation: Gate the stamp on the basal and bolus status reads (or a history reconcile) succeeding rather than responseCount, and change testSyncAdvancesLastSyncOnASingleResponse to assert non-advancement when only a non-delivery read answers.

- Verifier notes:
  - [review:amend] Code fact holds (any response advances lastReconciliation). The original concern was explicitly for a UI-capable pump. Under the premise's Loop-only clause, lastReconciliation is legitimately the last time TandemKit received status from the pump, which is exactly what the responseCount gate implements and the test pins; a reservoir reading is telemetry. Under conditional sources (Control-IQ on, quick bolus enabled) the original partial/medium rating would return, since pump-originated doses could then fall in the unread window.

**P18-A3 emitPumpEvents reads lastReconciliation lazily on the delegate queue** (Partial, impact low, verified, added by a verifier)

The date passed to hasNewPumpEvents is whatever state.lastReconciliation holds when the delegate queue runs the block, not when the event was produced. Ordering is preserved on a serial queue, but a test asserting the reported date equals the sync's completion value must run the delegate queue to completion first, and a later stamp (e.g. a reservoir read at StateSync:410 on another job) can be observed by an earlier event's delegate call. Relevant to how a P18 test should be written and to the accuracy of the reported boundary.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1743` lastReconciliation: self.state.lastReconciliation, -- read inside the async notify closure
  - `LinuxShims/LoopKit/LoopKit.swift:845` queue.async { block(delegate) } -- notify defers the block

- Recommendation: Capture lastReconciliation at the call site and pass it into the notify closure; in tests, drain the delegate queue (queue.sync {}) before asserting the recorded date.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

Open questions raised by this point:

- How does Trio's DeviceDataManager implement pumpManager(_:hasNewPumpEvents:lastReconciliation:...)? If Trio ignores lastReconciliation and only stores events into its own pump history, the accounting impact of P18-2 is Loop-specific; Trio source was not available to verify.
- The emitPumpEvents site at Sources/TandemKit/PumpManager/TandemPumpManager.swift:1318-1332 creates a scheduled-basal dose; its trigger (reconnect, qualifying event or Control-IQ transition) was not traced for this point and should be characterised when auditing the reconnect path.
- Guide vs. repo: the guide treats an empty hasNewPumpEvents call as required on every sync; CLAUDE.md line 541 lists 'gap-aware lastReconciliation advancement' as future work tied to history emission, suggesting the team plans to gate reconciliation advancement on a full history read (§6 UI-capable archetype) rather than on status polls. Which archetype TandemKit intends to follow should be settled before P18-2's fix is chosen.
- CI runs TandemKitTests only via xcodebuild on macOS; no Linux swift test job was found, so the LinuxShims delegate signature is not exercised by tests.
### P19. Tests verify value and deliveredUnits are rounded to the pump's supported increment

Guide section: §11 testing: rounding.

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 7 of 7 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

Rounding is unit-tested only in HistoryToDoseMapper (bolus value/deliveredUnits rounded to 0.001 U reporting resolution, deliberately not the 0.05 U command grid) and at the wire layer (InitiateBolusRequest milliunit encoding, Float32 noise in BolusCompletedHistoryLog). But the mapper has no production caller, so those tests cover nothing Loop receives today. The live paths that do reach Loop are untested for rounding: roundToSupportedBolusVolume/roundToSupportedBasalRate and the capability tables, LastBolusStatus -> deliveredUnits (which floors to 0.05 U, contradicting the mapper's own rationale), TandemDoseProgressReporter, and temp-basal value/deliveredUnits (deliveredUnits is never rounded). Verdict: partial.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P19-1 | Partial | none | verified | HistoryToDoseMapper bolus rounding tests |
| P19-2 | Non-conforming | low | verified | Live bolus finalization deliveredUnits floors to 0.05 U, untested |
| P19-3 | Non-conforming | low | verified | roundToSupported* helpers and capability tables have no tests |
| P19-4 | Non-conforming | low | verified | TandemDoseProgressReporter untested |
| P19-5 | Partial | low | verified | Temp basal value and deliveredUnits rounding untested |
| P19-6 | Partial | low | verified | Wire-level milliunit and Float32 tests |
| P19-7 | Partial | low | verified | Basal profile change value not rounded; test tolerates Float noise |

**P19-1 HistoryToDoseMapper bolus rounding tests** (Partial, impact none, verified)

The history mapper has explicit rounding tests for both value and deliveredUnits, and they pin a documented, defensible choice: round to nearest 0.001 U (the pump's milliunit reporting resolution), not the 0.05 U bolus command increment, because Tandem reports genuine partial deliveries (e.g. 1.041 U) and flooring would understate IOB. This deviates in letter from the guide's 'supported increment' wording but is the safer interpretation. However, grep shows no production caller of HistoryToDoseMapper.mapToEvents outside its own file, so these tests currently verify a path that never reaches the host app.

- Evidence:
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:84` testBolusUnitsRoundedToReportingResolution: Float 0.9 -> programmedUnits/deliveredUnits == 0.9
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:121` XCTAssertEqual(dose.deliveredUnits, 1.041) — partial delivery preserved at 0.001 U
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:161` roundToReportingResolution: (units * 1000).rounded() / 1000
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:160` comment: floor-to-command-grid rounding called the 'unsafe direction'

- Recommendation: Keep these tests; when the mapper is wired to emission, add an end-to-end test asserting the emitted NewPumpEvent dose values through the delegate. Document the 0.001 U choice in a docs file so reviewers do not 'fix' it to 0.05.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P19-2 Live bolus finalization deliveredUnits floors to 0.05 U, untested** (Non-conforming, impact low, verified)

The path that actually reaches Loop today (cancel and natural completion, steady state and after reconnect while bolusProgressReport is still in memory) converts LastBolusStatus.deliveredVolume (milliunits) to units and then floors to the 0.05 U command grid. A cancelled bolus that delivered 1.041 U is reported as 1.00 U — the exact 'unsafe direction' the mapper comment warns about. No test in Tests/ references LastBolusStatus or deliveredVolume (only QualifyingEventTests in TandemCoreTests), so neither the milliunit conversion nor the flooring is verified. Two rounding policies for the same quantity coexist without a test pinning either.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:532` return roundToSupportedBolusVolume(units: Double(response.deliveredVolume) / 1000.0)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:226` supportedBolusVolumes.last(where: { $0 <= units }) ?? 0 — floor, not nearest
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` cancelBolus: deliveredUnits = queryLastBolusDeliveredVolume(...) ?? 0
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:256` natural completion also uses queryLastBolusDeliveredVolume

- Recommendation: Add StubPumpBluetooth tests stubbing LastBolusStatus responses (e.g. 1041, 1049, 0 mU) and asserting emitted deliveredUnits; switch queryLastBolusDeliveredVolume to round-to-nearest 0.001 U to match the mapper, or document why flooring is intended.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P19-3 roundToSupported* helpers and capability tables have no tests** (Non-conforming, impact low, verified)

Grep of Tests/ for roundToSupportedBolusVolume, roundToSupportedBasalRate, strideRange, TandemPumpCapabilities, onboardingSupportedBolusVolumes and supportedBasalRates returns nothing. These are the functions LoopKit calls to round requested values before enactBolus/enactTempBasal and that the driver uses to round reported values. On reading, the integer-stride construction is correct (values are the nearest doubles to k*0.05 / k*0.01, so exact literals like 1.0 are found by the <= search), and rounding 0 U returns 0 as the comment intends, but none of this is pinned. A future edit to the tables (e.g. Mobi vs X2 ranges) could silently change rounding of every reported dose.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:224` public func roundToSupportedBolusVolume(units:) — no test references it
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:229` public func roundToSupportedBasalRate(unitsPerHour:)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1870` strideRange builds tables via integer stride / 1000 (avoids FP drift)
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:234` TandemPumpCapabilities.supportedBasalRates: [0.0] + 0.1...15.0 by 0.01

- Recommendation: Add unit tests: table endpoints and counts (0.05...25.0 step 0.05; 0.0 then 0.1...15.0 step 0.01), exact-literal membership (1.0, 0.15, 2.35), floor behaviour for off-grid inputs, and 0/negative inputs.

- Verifier notes:
  - [review:confirm] roundToSupportedBolusVolume/roundToSupportedBasalRate (224/229), strideRange (1870) and supportedBasalRates (UnfinalizedDose 234) exist and a grep of Tests/ for any of these symbols returns nothing. Rounding of app-commanded doses is unaffected by the premise. nonconforming/low stands.

**P19-4 TandemDoseProgressReporter untested** (Non-conforming, impact low, verified)

No test file references TandemDoseProgressReporter or DoseProgress. The reporter rounds its time-estimated progress to the 0.05 U grid (UI-only), and builds the finalized bolus NewPumpEvent with value = programmed total and deliveredUnits = pump-reported (already floored by P19-2) or the programmed total. Whether the finalized event's value and deliveredUnits land on a supported increment is therefore never asserted. Note also that `units: delivered` participates in the raw identity string, so a rounding change would change the bolus syncIdentifier (outside this point, see open questions).

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:77` deliveredUnits = pumpManager.roundToSupportedBolusVolume(units: min(runningFor * unitsDeliveredPerSec, total))
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:33` getPumpEvent: delivered = actualDeliveredUnits ?? total (no rounding applied here)
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:47` units: delivered feeds NewPumpEvent.bolus raw key

- Recommendation: Add tests for getPumpEvent with nil and explicit actualDeliveredUnits asserting value, deliveredUnits and isMutable == false; add a notify() test with an injected clock asserting progress is on the 0.05 U grid and capped at total.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: grep over Tests/ finds no reference to TandemDoseProgressReporter or DoseProgress.

**P19-5 Temp basal value and deliveredUnits rounding untested** (Partial, impact low, verified)

enactTempBasal does the right thing for `value`: it quantizes the request to an integer percent of the scheduled basal (what the pump actually delivers) and rounds the resulting absolute rate to the 0.01 U/hr grid. But no test drives enactTempBasal through StubPumpBluetooth (SyncBasalTests cover profile writes only), so the percent quantization and the reported rate are unverified — e.g. requesting 0.53 U/hr on a 0.8 U/hr baseline yields 66% -> 0.528 -> 0.52 U/hr, and the test suite would not notice a regression. The finalized deliveredUnits is value*hours with no rounding at all; mathematically correct, but not what the guide asks and untested.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:670` let unitsPerHour = roundToSupportedBasalRate(unitsPerHour: unitsPerHour)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:723` absoluteRate re-rounded from baseline * percent/100 (integer percent, capped 250)
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` deliveredUnits: isMutable ? nil : value * (duration / .hours(1)) — never rounded
  - `Tests/TandemKitTests/TandemPumpManagerStateTests.swift:166` only assertion on a temp basal rate: round-trip of 1.75, not rounding

- Recommendation: Add enactTempBasal tests asserting SetTempRateRequest.percent and the emitted mutable/finalized DoseEntry value; decide whether deliveredUnits should be rounded to 0.001 U and pin it in a UnfinalizedDose.toDoseEntry test.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P19-6 Wire-level milliunit and Float32 tests** (Partial, impact low, verified)

The TandemCore message tests verify the milliunit encoding of InitiateBolusRequest and the Float32 parsing of history bolus records, including a real capture showing Float noise (0.89000005). That covers the wire representation, and the manager's units->milliunits conversion uses rounded() so 0.13 U cannot become 129 mU. There are, however, no tests for LastBolusStatus/V2/V3 responses (the source of finalized deliveredUnits), for SetTempRateRequest, or for the manager-side conversion at line 551 itself — so the chain from wire bytes to the DoseEntry Loop receives is only tested at one end.

- Evidence:
  - `Tests/TandemCoreTests/Messages/Control/InitiateBolusRequestTests.swift:30` XCTAssertEqual(1000, Int(parsed.totalVolume)) — 1 U = 1000 mU round trip
  - `Tests/TandemCoreTests/Messages/Control/InitiateBolusRequestTests.swift:66` 0.13 U encoded as 130 mU
  - `Tests/TandemCoreTests/HistoryLog/BolusCompletedHistoryLogTests.swift:29` testBolusCompletedHistoryLog_mismatchingFloats: insulinDelivered 0.89000005 vs requested 0.89
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:551` let milliUnits = max(0, Int((units * 1000).rounded()))

- Recommendation: Add LastBolusStatus response parsing tests with milliunit deliveredVolume fixtures and a SetTempRateRequest test; add one manager test asserting InitiateBolusRequest.totalVolume for an off-grid Double like 0.13.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P19-7 Basal profile change value not rounded; test tolerates Float noise** (Partial, impact low, verified)

Within the same mapper, bolus amounts are cleaned of Float32 noise but the .basal rate is passed through unrounded, and the corresponding test is written with an accuracy tolerance rather than asserting the exact 1.15 the pump displays. The mapper's temp-basal test also supplies its own round-to-nearest closure, so the production floor (roundToSupportedBasalRate) is never exercised through the mapper. Impact is cosmetic today (scheduled-basal values with 1e-8 noise, and the mapper is unwired), but it is an inconsistency the tests currently enshrine rather than catch.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:277` value: Double(basalChange.commandBasalRate) — raw Float32 widened, no rounding
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:260` XCTAssertEqual(dose.unitsPerHour, 1.15, accuracy: 1e-6) — accepts 1.14999997
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:16` tests inject roundBasalRate = nearest 0.01, not the production floor helper

- Recommendation: Apply roundToReportingResolution (or the basal 0.01 grid) to commandBasalRate and tighten the test to an exact 1.15; add one mapper test that passes the production roundToSupportedBasalRate closure.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

Open questions raised by this point:

- The guide asks for rounding to the pump's 'supported increment'; Tandem reports delivered volume in 0.001 U and genuinely delivers partial boluses, so the mapper's 0.001 U policy (HistoryToDoseMapper.swift:161) is arguably more correct than the guide's wording. The live path floors to 0.05 U instead (StateSync:532). Which policy is intended should be decided once and tested.
- cancelBolus falls back to deliveredUnits = 0 when LastBolusStatus fails or returns a different bolusId (TandemPumpManager.swift:639), which would report a possibly-delivered bolus as zero delivery; this is a finalization/accounting concern for other points, not rounding.
- NewPumpEvent.bolus embeds `units` (programmed on enact, delivered on cancel/complete) in the raw identity string (Extensions/NewPumpEvent.swift:9), so any change in rounding of deliveredUnits also changes the bolus syncIdentifier between the mutable and final report — relevant to the §4 stable-identity points.
- After an app relaunch, bolusProgressReport is in-memory only, so fetchBolusStatus returns before finalizing a persisted bolusDose (StateSync:239); rounding of that dose is moot because it is never emitted — relevant to the persistence/reconnect points.
- HistoryToDoseMapper.mapToEvents has no production caller at HEAD, so CLAUDE.md's description of history-derived doses should be read as aspirational for all P19 findings about the mapper.
### P20. Tests bolus on the pump directly and confirm Loop picks it up from history with wasProgrammedByPumpUI = true (UI-capable pumps only)

Guide section: §11 testing: external doses (UI pumps).

Overall: **Not applicable today (residual findings: Partial)** (auditor's own overall: Not applicable; computed as the most conservative verdict among the surviving findings). 7 of 7 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

Re-audited under the screenless-pump premise; the UI-capable reading is summarised in the method section.

Under the screenless-Mobi premise the guide's external-dose test is not applicable in the default configuration, because TandemKit turns the quick-bolus button off on every sync (and that enforcement is unit-tested) and Control-IQ is off, so the only pump-side bolus sources are the two conditional ones; the UI-capable reading rated this point nonconforming (no end-to-end test, no history-to-delegate emission path), whereas here those gaps survive only as conditional, low-rated findings: no test covers a CurrentBolusStatus with an app-unknown bolusId (quick-bolus flag on or Control-IQ auto bolus), the pump-reported Control-IQ flip in fetchControlIQStatus is untested, the wire-level bolusSource origin field is unread, no test asserts any hasNewPumpEvents payload, and the manual test plan has no conditional-configuration step. HEAD is f008ec40, which differs from the audited 7d20b2d only by a docs-only commit, so all source line references are unchanged.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P20-1 | Conforms | none | verified | Quick-bolus enforcement tests remove the default-case external bolus source |
| P20-2 | Not applicable | none | verified | Guide's external-dose end-to-end test (bolus on pump → wasProgrammedByPumpUI at delegate) |
| P20-3 | Partial | low | verified | Conditional source (1): bolus status with an app-unknown bolusId is untested and silently dropped |
| P20-4 | Partial | low | verified | Conditional source (2): pump-reported Control-IQ flip and Control-IQ auto-boluses are untested |
| P20-5 | Partial | low | verified | Wire-level bolus origin (bolusSource) exists but is unread and untested |
| P20-6 | Partial | low | verified | No test asserts any hasNewPumpEvents payload |
| P20-7 | Partial | low | verified | Manual test plan lacks the conditional-configuration steps and overstates history emission |

**P20-1 Quick-bolus enforcement tests remove the default-case external bolus source** (Conforms, impact none, verified)

This is the mechanism that makes the guide's UI-pump test not applicable under the premise, and it is tested at the manager level with the stubbed BLE layer: flag off by default, globals re-read every sync, SetQuickBolusSettingsRequest(enabled: false) sent when the pump reports the button on, nothing sent when already off, and a rejected disable keeps state.quickBolusEnabled true so the next sync retries. Residual, untested: enforcement depends on a successful PumpGlobalsRequest read (guard on `state.quickBolusEnabled == true`), so an unanswered globals read leaves the button alone for that cycle, and the window between pairing and the first sync is not closed by the app.

- Evidence:
  - `Tests/TandemKitTests/QuickBolusEnforcementTests.swift:54` `func testSyncDisablesTheQuickBolusButtonWhenTheFlagIsOff() throws {`
  - `Tests/TandemKitTests/QuickBolusEnforcementTests.swift:87` `func testGlobalsAreReReadOnEverySyncWhileTheFlagIsOff()` — button re-enabled on pump is caught within one sync
  - `Tests/TandemKitTests/QuickBolusEnforcementTests.swift:109` `func testStateKeepsReportingEnabledWhenThePumpRejectsTheDisable()` — rejection path covered
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:362` `guard !state.featureFlags.quickBolusButtonSupport, state.quickBolusEnabled == true else {`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:432` `self.enforceQuickBolusDisabled()` runs on every syncPumpData pass

- Recommendation: Add one test for an unanswered PumpGlobalsRequest (quickBolusEnabled nil) asserting no disable is sent and that the next sync with a good read does send it; document the pairing-to-first-sync window in the hardware validation notes.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P20-2 Guide's external-dose end-to-end test (bolus on pump → wasProgrammedByPumpUI at delegate)** (Not applicable, impact none, verified)

The guide scopes this test to UI-capable pumps. With no screen, the quick-bolus button disabled every sync (P20-1) and Control-IQ off, there is no pump-originated bolus for the test to exercise, so the item does not apply in the default configuration. The prior audit's core findings (mapper-only flag assertions, no production caller of HistoryToDoseMapper, coordinator emits nothing, historyDoseReporting unconsumed) remain factually true at HEAD but are now conditional: they would become high-impact requirements only if quickBolusButtonSupport is turned on or Control-IQ is enabled, since either creates boluses the app never commanded and today nothing reports them.

- Evidence:
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:17` `isCommandedBolus: @escaping (Int) -> Bool = { _ in false }` — flag driven by a test stub
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:61` `XCTAssertTrue(dose.wasProgrammedByPumpUI)` — only positive assertion, on mapper output not delegate output
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:9` "Nothing is mapped to doses or emitted here — that is the emission layer's job"
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:455` `self.historyBackfillCoordinator.runTick()` — the only history hook in syncPumpData
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:173` `self[.historyBackfill] && self[.historyDoseReporting]` — reporting has no consumer in Sources (grep)

- Recommendation: Before either conditional source can be enabled for users, build the history emission layer and add the delegate-level test (Quick Bolus / Control-IQ auto-bolus activation+completion in history → `delegate.pumpEvents` contains a `.bolus` with `wasProgrammedByPumpUI == true`, `isMutable == false`). Until then, keep both flags off and Control-IQ support gated.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P20-3 Conditional source (1): bolus status with an app-unknown bolusId is untested and silently dropped** (Partial, impact low, verified)

With quickBolusButtonSupport on, a button press on the Mobi produces a bolusChange qualifying event and a CurrentBolusStatusResponse whose bolusId the app never issued. fetchBolusStatus returns before building any event when no progress reporter exists, and on completion merely resets bolusState, so the dose never reaches hasNewPumpEvents and lastReconciliation still advances past it (TandemPumpManager.swift:445). No test constructs a CurrentBolusStatusResponse at all, so this drop is unasserted. In the default configuration the path is unreachable because the button is disabled (P20-1), hence the low rating; with the flag on this is a lost dose and an IOB under-count, which would be high.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:226` `guard let progressReport = bolusProgressReport else {` — a `.delivering` bolus the app did not issue is ignored
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:217` `if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil {` — completed foreign bolus only clears state
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:588` `self.bolusProgressReport = TandemDoseProgressReporter(` — sole creation site, inside enactBolus
  - `Tests/TandemKitTests/TandemPumpManagerBolusSyncTests.swift:24` `func testSyncNotDeferredWithoutTrackedBolus()` — file only tests shouldDeferBolusSync, never a CurrentBolusStatusResponse
  - `Tests/TandemKitTests/QualifyingEventHandlingTests.swift:48` `XCTAssertEqual(handle([.bolusChange]), ["CurrentBolusStatusRequest"])` — asserts the request, not what is done with the reply

- Recommendation: Add a manager test: stub CurrentBolusStatusRequest with `.delivering`, bolusId 42, no app bolus, and assert current behaviour explicitly (no event emitted) as a guard; then, when the flag is offered to users, change the code to report such a bolus mutable with `wasProgrammedByPumpUI: true` and finalize from LastBolusStatus/history.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P20-4 Conditional source (2): pump-reported Control-IQ flip and Control-IQ auto-boluses are untested** (Partial, impact low, verified)

The premise's second conditional source is Control-IQ. The safety interlock that makes it tolerable — the pump reporting closedLoopEnabled during sync flips useControlIQ so automatic dosing is refused — has no test: the Control-IQ test helper always passes closedLoopEnabled false, and the guard tests preset the flag. Nothing tests a Control-IQ auto-bolus (BolusSource.controlIQAutoBolus) arriving in bolus status; per P20-3 it would be dropped. Manual app boluses still pass under Control-IQ, so the app's IOB would omit the pump's auto-corrections while the user boluses from the bolus calculator. Rated low because Control-IQ is off by default and controlIQSupport is a default-off flag; medium under Control-IQ.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:33` `if response.getClosedLoopEnabled(), !state.useControlIQ {` — pump-side enablement flips the dosing guard
  - `Tests/TandemKitTests/TandemPumpManagerControlIQTests.swift:62` `closedLoopEnabled: Bool = false,` — helper default; no test passes `closedLoopEnabled: true` (grep empty)
  - `Tests/TandemKitTests/TandemPumpManagerValidationTests.swift:71` `state.useControlIQ = true` — guard tests set the flag directly, bypassing fetchControlIQStatus
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:517` `if state.useControlIQ, activationType.isAutomatic {` — only automatic boluses are refused
  - `Sources/TandemKitUI/TandemPumpManager+UI.swift:146` `if state.useControlIQ {` — surfaced to the host only as a status highlight

- Recommendation: Add a sync test: stub ControlIQInfoV2Request with `closedLoopEnabled: true`, run syncPumpData, assert `state.useControlIQ` becomes true and a subsequent automatic enactBolus/enactTempBasal is refused. Add a test that a Control-IQ auto-bolus in CurrentBolusStatus is not silently discarded once emission exists.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: grep over Tests/ finds no `closedLoopEnabled: true`; the guard tests set state.useControlIQ directly (ValidationTests:71).

**P20-5 Wire-level bolus origin (bolusSource) exists but is unread and untested** (Partial, impact low, verified)

Both conditional sources are distinguishable on the wire: CurrentBolusStatusResponse and BolusDeliveryHistoryLog carry a bolusSource that names quick-bolus, Control-IQ auto-bolus and Bluetooth (app) boluses. Nothing under Sources/TandemKit reads bolusSource (grep empty), and the mapper's wasProgrammedByPumpUI depends on an isCommandedBolus closure that has no production implementer and could not survive a relaunch since only state.bolusDose is kept. No test exercises bolusSource decoding through the manager. This is the simplest correct basis for the guide's flag and would make the P20 test implementable without a commanded-id ring buffer. Default impact is low since no pump-side boluses occur.

- Evidence:
  - `Sources/TandemCore/Messages/CurrentStatus/CurrentBolusStatus.swift:90` `public var bolusSource: BolusSource? {` — origin field on the status response
  - `Sources/TandemCore/Messages/Models/BolusDelivery.swift:4` `case quickBolus = 0` (also `controlIQAutoBolus = 7`, `bluetoothRemoteBolus = 8`)
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:194` `wasProgrammedByPumpUI: !isCommandedBolus(completion.bolusId)` — relies on a caller-supplied predicate instead
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:594` `self.state.bolusDose = dose` — only the single in-flight bolus id is retained; no persisted commanded-id set

- Recommendation: Derive `wasProgrammedByPumpUI` from `bolusSource != .bluetoothRemoteBolus` (status and history paths) rather than a commanded-id lookup; add unit tests for all four BolusSource values through the manager once emission exists.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: grep over Sources/TandemKit finds no reader of bolusSource; the field is defined at CurrentBolusStatus.swift:85 (the cited line 90 has drifted by five lines) and BolusSource enumerates quickBolus, gui, controlIQAutoBolus and bluetoothRemoteBolus.

**P20-6 No test asserts any hasNewPumpEvents payload** (Partial, impact low, verified)

Independent of the premise (trigger is the test harness, not a pump screen): the mock delegate captures events but no test reads `pumpEvents` or sets `didReceivePumpEventsExpectation`, and the mock drops lastReconciliation/replacePendingEvents entirely. So even for app-commanded boluses and the pump-initiated stops that remain fully in scope, there is no assertion on what Loop actually receives, and a future conditional-source test (P20-2/3/4) has no exercised harness to build on. Test-only gap; it does not by itself change insulin accounting.

- Evidence:
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:36` `var pumpEvents: [NewPumpEvent] { synchronized { _pumpEvents } }` — recorded but no test file reads it (grep)
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:133` `synchronized { _pumpEvents += events }` — lastReconciliation and replacePendingEvents are discarded (`_`)
  - `Tests/TandemKitTests/TandemPumpManagerHistoryIntegrationTests.swift:6` Integration suite drives HistoryLogFetcher/store only; no delegate assertions

- Recommendation: Extend MockPumpManagerDelegate to record lastReconciliation and replacePendingEvents per call, and add at least one manager-level test per dose path (enactBolus start/finish, suspend, pump-aborted bolus) asserting the delegate payload; the conditional-source tests then slot in.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: grep over Tests/ finds no reader of the mock's pumpEvents and no setter of didReceivePumpEventsExpectation outside the mock.

**P20-7 Manual test plan lacks the conditional-configuration steps and overstates history emission** (Partial, impact low, verified)

Under the premise the Loop-issued-bolus manual step is the right default, so the missing bolus-on-pump step is not a defect by itself. What survives: the plan has no step for the two conditional configurations (quickBolusButtonSupport on: press the button, confirm the app sees it or refuses to enable the flag; Control-IQ on: confirm automatic dosing is refused and auto-boluses are visible), and its progress notes assert a delegate-delivery history path that does not exist at HEAD, which a QA reader would take as coverage. The qualifying-event test comment likewise implies IOB benefit from a store nothing consumes.

- Evidence:
  - `docs/tandemkit-history-integration-plan.md:622` `- [ ] Issue bolus from Loop, verify appears in history` — no quick-bolus or Control-IQ step
  - `docs/tandemkit-history-integration-plan.md:681` Claims `fetchPumpHistory` wired "with delegate delivery" — symbol absent from Sources (grep)
  - `Tests/TandemKitTests/QualifyingEventHandlingTests.swift:55` `func testBolusChangeAlsoReadsHistory()` — comment says a pump-UI bolus lands in the store "instead of leaving it out of IOB", yet nothing reads the store

- Recommendation: Correct the plan's Phase 6 status to "store only, no emission"; add conditional manual steps for quick-bolus-on and Control-IQ-on; reword the testBolusChangeAlsoReadsHistory comment to say the store is filled for a future emission layer.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

Open questions raised by this point:

- The premise says the host disables closed loop under Control-IQ, but the code only refuses automatic enactBolus/enactTempBasal (TandemPumpManager.swift:517, 673) and shows a status highlight (TandemPumpManager+UI.swift:146); Trio's sources have no Control-IQ awareness (grep empty). Does Trio actually turn closed loop off, or just fail each cycle, and does that change how Control-IQ auto-boluses should be reported?
- With quickBolusButtonSupport off, is there a firmware-side window between pairing and the first successful PumpGlobalsRequest read in which a Mobi quick-bolus press can deliver, and should pairing itself send SetQuickBolusSettingsRequest(enabled: false)?
- When the emission layer is built, should a Control-IQ auto-bolus be reported with wasProgrammedByPumpUI = true (MinimedKit precedent) or with automatic = true only? Trio's PumpHistoryStorage dedups by (date, type) and only lowers a duplicate bolus amount, so the flag choice affects how a pump-side bolus interacts with an app bolus at the same minute.
- HEAD f008ec40 differs from the audited 7d20b2d only by docs/dose-reporting-conformance-audit.md; confirm the audit should be pinned to 7d20b2d for source line references.
### P21. Reported dose timeline is diffed against the pump's own delivery history and expected IOB, so small persistent discrepancies surface

Guide section: §11 testing: timeline diff vs pump history.

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 6 of 6 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

TandemKit never diffs the doses it reports against the pump's own delivery history or against an expected IOB. History log entries are fetched into an in-memory store (only behind the default-off `historyBackfill` flag), but `HistoryToDoseMapper` has no caller, the coordinator explicitly emits nothing, and no code compares store contents with the live-path doses sent via `emitPumpEvents`. The pump's IOB is never read; `latestInsulinOnBoard` is never assigned. The only pump-side cross-check is a `LastBolusStatus` read at bolus end, whose failure is silently absorbed (full programmed units on completion, 0 U on cancel). Tests are component unit tests; the log viewer shows raw records only; docs describe a `HistoryReconciler` that does not exist.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P21-1 | Non-conforming | low | amended | Live-path vs history-path dose reconciliation |
| P21-2 | Partial | high | verified | Live-path cross-check against pump status at bolus end |
| P21-3 | Non-conforming | low | amended | Expected-IOB comparison |
| P21-4 | Non-conforming | low | verified | Test coverage for timeline diffing |
| P21-5 | Partial | low | verified | Diagnostic tooling for manual diffing |
| P21-6 | Non-conforming | low | verified | Documentation claims a reconciler that does not exist |

**P21-1 Live-path vs history-path dose reconciliation** (Non-conforming, impact low, amended)

Every path that reaches `emitPumpEvents` (enactBolus/cancelBolus/enactTempBasal/suspend/resume, fetchBasalStatus, handleBolusResponse, home-screen mirror) builds doses from app-side `UnfinalizedDose` state plus status polls. History records, when fetched at all (flag default off), land in the session store and are never mapped, never compared to what was emitted, and never surfaced as a discrepancy. This holds in steady state, on first sync after pairing, after BLE reconnect, and after relaunch (where the store is additionally empty). So a persistent gap such as a Control-IQ correction bolus or a pump-UI quick bolus missing from the reported timeline has no detector in the driver.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:8` "nothing is emitted to a delegate, reconciled against pending optimistic doses, or persisted"
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:9` "Nothing is mapped to doses or emitted here"
  - `CLAUDE.md:539` "nothing consumes the store's contents. `HistoryToDoseMapper` is not wired" — confirmed by grep: no caller outside its own file
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:36` historyBackfill and historyDoseReporting default to false
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:59` guard featureFlags.historyBackfill == true else return — no history read by default

- Recommendation: Add a reconciliation pass (the planned emission layer) that maps stored history for the window since last emission and compares by bolusId/tempRateId and amount against emitted doses; log and surface any dose present in one timeline and absent from the other.

- Verifier notes:
  - [review:amend] Facts verified: HistoryToDoseMapper has no caller in Sources; the coordinator maps nothing; historyBackfill/historyDoseReporting default false and runTick returns immediately; the store is in-memory. No emitted dose is ever compared to pump history. Under the premise (default config: quick bolus off, Control-IQ off) there are no pump-originated doses to miss, and the live path already reads LastBolusStatus for aborted boluses, so the missing diff is an absent diagnostic safety net rather than an accounting input: low. Under Control-IQ or quick-bolus it would be high, since those doses would be invisible.

**P21-2 Live-path cross-check against pump status at bolus end** (Partial, impact high, verified)

The driver does consult the pump once per Loop-commanded bolus (`LastBolusStatus.deliveredVolume`), which is a partial form of diffing against the pump's record. But a discrepancy is not surfaced: if the read fails or the pump's last bolus has a different bolusId (e.g. a Control-IQ bolus started after ours), natural completion is finalized at the full programmed amount and cancellation at 0 U delivered, both immutable, with only a log line. Temp basals and suspend/resume are finalized purely from elapsed time with no pump cross-check at all. No aggregate or persistent mismatch is tracked.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:254` "Query the pump for actual delivered volume rather than assuming full delivery"
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:528` bolusId mismatch only logs a warning and returns nil
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:33` let delivered = actualDeliveredUnits ?? total
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` temp basal deliveredUnits = value * elapsed; never checked against the pump

- Recommendation: When the status read fails or the bolusId mismatches, finalize from history (BolusCompletedHistoryLog for that bolusId) rather than 0/programmed; until then leave the dose mutable and record a visible discrepancy counter in state/debugDescription.

- Verifier notes:
  - [review:confirm] All evidence verified: the comment at 254, the warning-only mismatch at 528, the two opposite fallbacks (639 → 0, reporter:33 → programmed), and TBR deliveredUnits = value × elapsed at UnfinalizedDose:190 with no pump cross-check; bolusStatus is parsed but never read by the driver. The Control-IQ example is conditional under the premise; default triggers are timeout and the post-cancel storage race. High rides on the same fallback defect as P05-2/P07-1/P23-2 (see duplicates); what this finding uniquely adds (no discrepancy counter, TBR/suspend uncross-checked) is medium on its own.

**P21-3 Expected-IOB comparison** (Non-conforming, impact low, amended)

The pump exposes its own IOB (ControlIQIOBRequest / NonControlIQIOBRequest, and the `iob` field on BolusCompletedHistoryLog), which would be the natural 'expected IOB' to diff Loop's computed IOB against. Grep of Sources/TandemKit finds no read of any of these; `latestInsulinOnBoard` is persisted but never populated, so the debugDescription value is always nil. There is therefore no way, in code or diagnostics, to notice that Loop's IOB has drifted from what the pump believes it has delivered.

- Evidence:
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:47` public var latestInsulinOnBoard: Double? — only assigned from rawValue at line 167
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1641` "Nothing to fetch (e.g. iobChange only)" — iobChange qualifying event fetches nothing
  - `Sources/TandemCore/Messages/HistoryLog/BolusCompletedHistoryLog.swift:17` public let iob: Float — parsed but never read by the mapper
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:176` completedBolusEvent uses insulinRequested/insulinDelivered only; completion.iob ignored

- Recommendation: Poll the version-appropriate IOB request on sync (the suggested-handler table already names it for iobChange), store it in `latestInsulinOnBoard`, and log a warning when it differs from the host-reported IOB by more than the pump increment for several consecutive syncs.

- Verifier notes:
  - [review:amend] Facts verified: latestInsulinOnBoard is only read from and written to rawValue and never assigned from a pump response; no IOB request is sent anywhere in Sources/TandemKit (QualifyingEventFetch explicitly maps iobChange to nothing); BolusCompletedHistoryLog.iob is parsed but completedBolusEvent uses insulinRequested/insulinDelivered only. Under the premise the pump's IOB would be a diagnostic cross-check with no direct effect on accounting in the default configuration: low. Under Control-IQ it would matter more, since the pump's IOB would then be the only view of automatic dosing.

**P21-4 Test coverage for timeline diffing** (Non-conforming, impact low, verified)

HistoryTimestampReconcilerTests, HistoryLogStoreTests (missingRanges, prune), HistoryToDoseMapperTests and HistoryBackfillCoordinatorTests each test their component in isolation. No test drives `enactBolus`/`enactTempBasal` and a history fixture through the same manager and asserts the two timelines agree (grep finds no test file using both). No test computes IOB from emitted events or compares it to a pump-reported value. The word 'reconcile' in TandemPumpManagerBolusSyncTests refers to un-deferring the sync path, not to diffing against history.

- Evidence:
  - `Tests/TandemKitTests/HistoryBackfillCoordinatorTests.swift:507` "Nothing consumes the store yet, so this only fixes the contract"
  - `Tests/TandemKitTests/MockPumpManagerDelegate.swift:133` synchronized { _pumpEvents += events } — records events, no comparison helper
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:32` pure mapper unit tests; mapper referenced by no other test file
  - `Tests/TandemKitTests/HistoryTimestampReconcilerTests.swift:13` clock-delta arithmetic only
  - `Tests/TandemKitTests/TandemPumpManagerBolusSyncTests.swift:44` testSyncReconcilesAfterGraceExpires asserts only shouldDeferBolusSync == false

- Recommendation: Add an integration test with StubPumpBluetooth that enacts a bolus and temp basal, streams the matching Bolus/TempRate Activated+Completed history logs, maps them, and asserts identity (syncIdentifier), amounts and IOB match the events recorded by MockPumpManagerDelegate.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P21-5 Diagnostic tooling for manual diffing** (Partial, impact low, verified)

A developer can open the debug History Log Viewer to read raw pump records and the state dump to see the live-path bookkeeping, so a manual diff against Loop's insulin history is possible on-device. Nothing automates it: no view or log line juxtaposes reported doses with history, `scripts/` contains only an xcodeproj membership check and a web-setup script, Package.swift declares no executable/CLI target, and the store is in-memory so nothing survives a relaunch for offline analysis.

- Evidence:
  - `Sources/TandemKitUI/ViewModels/Settings/TandemKitHistoryLogViewerViewModel.swift:84` logsBySequence / logsByType / logsDescending — raw records only
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:459` debugDescription lists lastReconciliation, latestInsulinOnBoard (always nil), historyBackfill bookkeeping
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:182` manager debugDescription is just the state dump
  - `Sources/TandemKit/PumpManager/History/HistoryLogStore.swift:30` "Dose reconciliation only ever looks back hours" — describes intended, not implemented, use

- Recommendation: Add a debug screen or exportable dump that lists, side by side, the last N emitted NewPumpEvents (kept in state or a ring buffer) and the mapped history doses for the same window, highlighting unmatched entries and the pump's IOB.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P21-6 Documentation claims a reconciler that does not exist** (Non-conforming, impact low, verified)

The plan document marks Phase 4 (matching pending doses to history within ±0.05 U / ±0.01 U/hr, flagging unreconciled doses after 24 h) and Phase 6 (delegate delivery of reconciled events) as done, and KEY_FILES_REFERENCE describes `HistoryReconciler` and `HistoryDeduplicator` as present. Neither file exists in `Sources/TandemKit/PumpManager/History/`, and CLAUDE.md says the coverage was dropped with the code. A reviewer reading the docs would conclude the timeline diff this point asks for is implemented; it is not.

- Evidence:
  - `docs/tandemkit-history-integration-plan.md:680` "Implemented Phase 4 pending dose reconciliation primitives (`PendingDose`, `HistoryReconciler`)"
  - `docs/tandemkit-history-integration-plan.md:708` "- [x] Create `HistoryReconciler.swift`"
  - `docs/KEY_FILES_REFERENCE.md:189` lists /Sources/TandemKit/PumpManager/History/HistoryReconciler.swift — file absent from the directory
  - `CLAUDE.md:539` contradicts the above: "nothing consumes the store's contents"

- Recommendation: Update tandemkit-history-integration-plan.md and KEY_FILES_REFERENCE.md to mark Phases 4/6 as removed/not implemented and point to the current HistoryBackfillCoordinator/HistoryLogStore design; keep CLAUDE.md as the source of truth.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: no HistoryReconciler.swift or HistoryDeduplicator.swift exists under Sources/, while docs/KEY_FILES_REFERENCE.md:189 and the plan document list them as present.

Open questions raised by this point:

- Does the host app (Trio or Loop) provide its own pump-history-vs-DoseStore comparison tooling that the project intends to rely on instead of driver-side diffing? Nothing in the repo references one.
- What are the exact semantics of `BolusCompletedHistoryLog.iob` and of ControlIQIOBResponse/NonControlIQIOBResponse (IOB after the bolus? including basal?) — this determines whether either is a usable 'expected IOB' baseline for a diff.
- Is `LastBolusStatus.deliveredVolume` reliable immediately after CancelBolusRequest on Mobi? The 2 s `Thread.sleep` before the read (TandemPumpManager.swift ~636) suggests uncertainty; hardware confirmation would settle whether the live-path cross-check itself can be trusted.
- The guide (§11) frames this point as a testing recommendation; the project may consider hardware validation procedures (CLAUDE.md item 21, not yet written) the intended venue rather than driver code — the audit treated in-code/in-test tooling as the conformance bar.
### P22. NewPumpEvent/DoseEntry fields are populated with the documented semantics: type, startDate/endDate (TBR endDate = scheduled end while mutable), value+unit programmed, deliveredUnits actual, isMutable, wasProgrammedByPumpUI, automatic, manuallyEntered, insulinType, and syncIdentifier left to be derived from raw

Guide section: §2 data model.

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 8 of 8 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

The DoseEntry shape on TandemKit's live (optimistic) emission paths is mostly right: type, startDate, mutable TBR endDate = scheduled end, deliveredUnits nil while mutable, isMutable, insulinType and a raw-derived syncIdentifier all follow the guide. Four semantic gaps remain: (1) every finalized commanded bolus with activationType .manualNoRecommendation is stamped manuallyEntered = true, which LoopKit/Trio read as non-pump ("external") insulin; (2) cancelBolus finalizes with deliveredUnits = 0 when the LastBolusStatus read fails, and delivered volumes are floored to 0.05 U; (3) wasProgrammedByPumpUI is never true on any path that runs today (only the unwired, flag-gated HistoryToDoseMapper sets it, and only for boluses); (4) `automatic` is nil for all history-derived doses including Control-IQ auto-boluses, and TBR value/deliveredUnits derive from the host's schedule rather than the pump's profile.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P22-1 | Conforms | none | verified | type / startDate / endDate / isMutable shape on optimistic paths |
| P22-2 | Non-conforming | medium | verified | manuallyEntered mis-set on finalized commanded boluses |
| P22-3 | Partial | high | verified | deliveredUnits actual: cancel-path zeroing and floor rounding |
| P22-4 | Not applicable | none | amended | wasProgrammedByPumpUI never true on any live path |
| P22-5 | Not applicable | none | amended | automatic flag semantics across sources |
| P22-6 | Conforms | low | verified | syncIdentifier derivation, NewPumpEvent date/type, Linux shim divergence |
| P22-7 | Conforms | none | verified | insulinType propagation |
| P22-8 | Partial | low | amended | value (programmed) for temp basal and basal markers |

**P22-1 type / startDate / endDate / isMutable shape on optimistic paths** (Conforms, impact none, verified)

On every live path traced (enactBolus, cancelBolus, enactTempBasal, suspend, resume, fetchBasalStatus, handleHomeScreenMirrorResponse, configureControlIQMode, getActivePumpEvents) doses are built through UnfinalizedDose.toDoseEntry. Bolus and temp basal use the correct unit (.units / .unitsPerHour), mutable entries have deliveredUnits nil and endDate = programmed end, finalized entries flip isMutable and carry a real endDate. Suspend/resume use LoopKit's dedicated initializers; .basal markers have endDate == startDate and no deliveredUnits, which is how LoopKit models scheduled-basal boundaries. The DoseEntry.bolus helper's mutable branch (Date.now + duration) is dead code — its sole caller (TandemDoseProgressReporter.getPumpEvent) always passes endDate. State persists UnfinalizedDose (rawValue) so shape survives relaunch.

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:149` bolus: `endDate = isMutable || useEstimatedEndDate ? estimatedEndDate : endDate` — mutable bolus carries estimated end
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:161` `deliveredUnits: isMutable ? nil : deliveredUnits` — Medtrum-style shape the guide endorses
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:177` tempBasal: `actualEndDate = isMutable ? estimatedEndDate : endDate` — mutable TBR endDate is the scheduled end
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:178` finalized TBR endDate clipped to estimatedEndDate; deliveredUnits = rate x elapsed hours (line 190)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` `toDoseEntry(isMutable: endDate == nil, endDate: endDate ?? Date.now)` — running TBR re-emitted mutable, finalized at the next dose's start

- Recommendation: No change needed for shape. Consider deleting the unreachable mutable branch of DoseEntry.bolus and the unused DoseEntry.tempBasal/basal/resume/suspend helpers so the only DoseEntry factory is UnfinalizedDose.toDoseEntry.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P22-2 manuallyEntered mis-set on finalized commanded boluses** (Non-conforming, impact medium, verified)

In LoopKit, manuallyEntered marks insulin the user logged that the pump did not deliver (pen/manual entry); Trio maps it to `isExternal` ("delivered outside Trio, e.g. pen injection", per Trio's data model). BolusActivationType.manualNoRecommendation is a normal pump-delivered bolus the user requested when no recommendation existed. TandemKit therefore finalizes such boluses flagged as external/manual insulin, and the flag also changes between the mutable and finalized report of the same dose. Steady-state Loop UIs and Trio's Nightscout upload will classify these as external insulin; whether any consumer excludes them from pump-delivery reconciliation depends on the host, so accounting drift is possible but not proven here. Trio normally passes .manualRecommendationAccepted, so the path is hit mostly under Loop or custom hosts.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/DoseEntry.swift:24` `manuallyEntered: activationType == .manualNoRecommendation,`
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:35` getPumpEvent builds the finalized bolus via `DoseEntry.bolus(...)` with the stored activationType
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:260` `events.append(progressReport.getPumpEvent(actualDeliveredUnits: actualDelivered))` — the only finalize path for a completed bolus
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:155` initial mutable bolus (enactBolus) omits manuallyEntered -> false; the flag flips to true at finalization
  - `reference: loopkit-trio/InsulinDeliveryStore.swift:253` LoopKit queries `manuallyEntered == YES` as the 'manually entered doses' set (non-pump insulin)

- Recommendation: Always pass `manuallyEntered: false` for pump-delivered doses (it is never true for anything TandemKit reports). Use `automatic: activationType.isAutomatic` alone to distinguish SMB/automatic from user boluses. Add a test asserting manuallyEntered == false for every activationType.

- Verifier notes:
  - [review:confirm] Code facts verified: DoseEntry.bolus stamps manuallyEntered from .manualNoRecommendation (ext:24/38), the reporter uses it for the only completion finalize path, and UnfinalizedDose.toDoseEntry omits the flag so the mutable report is false. Trio does map it to isExternal, but only on first insert; its dedup update never touches isExternal, and APSManager passes only .automatic/.manualRecommendationAccepted, so Trio is unaffected. Under Loop the finalized row replaces the mutable one flagged as manual insulin, exposed to getManuallyEnteredDoses/deleteAllManuallyEnteredDoses. Trigger is the host app, unaffected by the premise. Medium stands (metadata, no IOB change).

**P22-3 deliveredUnits actual: cancel-path zeroing and floor rounding** (Partial, impact high, verified)

The guide requires deliveredUnits to be the pump's actual delivered amount at finalization. Natural completion does read LastBolusStatus (good) but falls back to the programmed total on read failure. cancelBolus is worse: if the LastBolusStatus read fails or returns a different bolusId (e.g. a Control-IQ or quick bolus started after the cancel on a UI-capable pump), the partially delivered bolus is finalized immutable with deliveredUnits = 0, so Loop drops all delivered insulin for it — IOB under-count, over-delivery risk. Separately, delivered volumes are floored to 0.05 U although the pump reports milliunits; HistoryToDoseMapper.swift:155-163 itself documents that flooring understates delivered IOB and uses round-to-nearest 0.001, so the two paths disagree.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` `bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:641` `let canceledDose = bolusDose.toDoseEntry(endDate: Date.now)` — immutable, so deliveredUnits 0 is final
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:527` `guard response.bolusId == bolusId else { ... return nil }` — mismatch or no response yields nil
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:532` `roundToSupportedBolusVolume(units: Double(response.deliveredVolume) / 1000.0)` — floors milliunit value to the 0.05 grid
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:226` `supportedBolusVolumes.last(where: { $0 <= units }) ?? 0` — floor, not nearest

- Recommendation: On cancel, if the LastBolusStatus read fails, keep the dose mutable (or fall back to the progress reporter's estimate) and retry on the next sync rather than finalizing at 0. Use round-to-nearest milliunit for deliveredUnits, matching HistoryToDoseMapper.roundToReportingResolution; reserve floor rounding for outgoing commands.

- Verifier notes:
  - [review:confirm] Every cited line verified: floor grid at 226, floor applied at 532, completion fallback to programmed at reporter:33, LoopKit honouring 0 at DoseEntry:95, and the mapper's own comment (lines 154-163) that flooring understates delivered IOB. The mismatch example (Control-IQ/quick bolus) is conditional under the premise; the default-configuration triggers are a BLE timeout and the Mobi storage race after cancel. High is carried by the cancel-zeroing component; the flooring alone is bounded (<0.05 U/bolus, always downward) and would be low on its own.

**P22-4 wasProgrammedByPumpUI never true on any live path** (Not applicable, impact none, amended (auditor said Non-conforming))

Tandem is UI-capable (t:slim X2 touchscreen, Mobi quick-bolus button, Control-IQ). The guide (§2, §7) requires wasProgrammedByPumpUI = true on doses that originated on the pump. Every path that emits today — including the two that exist specifically to pick up pump-side state changes (fetchBasalStatus, handleHomeScreenMirrorResponse) — leaves the flag false, because UnfinalizedDose.toDoseEntry cannot express it. The only code that sets it is HistoryToDoseMapper, which has no production caller and sits behind two default-off flags; even there, pump-set temp rates and pump-side suspend/resume are not flagged. Applies in steady state, after reconnect and after relaunch alike.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:152` suspend detected from CurrentBasalStatus: `UnfinalizedDose(suspendStartTime: now)` — default wasProgrammedByPumpUI false
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:486` home-screen-mirror suspend/basal doses likewise carry no wasProgrammedByPumpUI
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:146` toDoseEntry has no wasProgrammedByPumpUI parameter; every DoseEntry it builds uses the default false
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:194` `wasProgrammedByPumpUI: !isCommandedBolus(completion.bolusId)` — set for boluses only
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:252` temp-rate DoseEntry omits wasProgrammedByPumpUI (and suspend/resume at lines 98, 109)

- Recommendation: Add a `wasProgrammedByPumpUI` field to UnfinalizedDose (persisted in rawValue) and set it true for doses discovered from pump status rather than commanded. When HistoryToDoseMapper is wired, also flag temp rates (tempRateId not commanded) and suspend/resume records not matching an app-issued command.

- Verifier notes:
  - [review:amend] Code facts are accurate: UnfinalizedDose.toDoseEntry has no wasProgrammedByPumpUI parameter, so every live-path DoseEntry uses the default false; HistoryToDoseMapper sets it only for boluses and its mapToEvents has no production caller behind default-off flags. But the requirement is the guide's §7 UI-capable item, which the guide itself says Loop-only pumps may leave false; under the premise there is no pump UI, the quick-bolus button is turned off every sync (enforceQuickBolusDisabled, flag default off) and Control-IQ is off, so the finding's trigger is a user acting on a pump screen. Pump-initiated alarm stops remain in scope, but neither LoopKit variant nor Trio has any accounting logic keyed on the flag (LoopKit only persists it onto the PumpEvent row; Trio never reads it), so leaving it false has no insulin-accounting effect. Would be relevant (still metadata-only) under quickBolusButtonSupport or Control-IQ.

**P22-5 automatic flag semantics across sources** (Not applicable, impact none, amended (auditor said Partial))

For doses the host commands, `automatic` is right: boluses take it from activationType, and temp basals are always loop-issued (enactTempBasal is blocked under Control-IQ and only Loop/Trio call it), so `true` is defensible. The gap is doses the pump originates. Control-IQ correction boluses and basal modulation are the guide's canonical 'automatic' case, yet the history mapper emits `automatic: nil` for every dose type, and the records it reads (BolusActivated/Completed) do not carry the source; BolusDeliveryHistoryLog.BolusSource / CurrentBolusStatus.bolusSource do. Trio reads `automatic` as isSMB, so once history reporting is wired, Control-IQ auto-boluses would be classified as manual. Today the mapper is unwired, so the practical effect is that these doses are not reported at all (outside this point).

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:33` commanded bolus: `automatic = activationType.isAutomatic` — correct
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:768` enactTempBasal: `automatic: true,` hardcoded
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:60` `automatic = false // OSAID does not use suspend function` — also applied to pump-detected suspends
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:184` completed-bolus DoseEntry passes no `automatic:` — nil for Control-IQ auto-boluses and user boluses alike
  - `Sources/TandemCore/Messages/Models/BolusDelivery.swift:6` `case controlIQAutoBolus = 7` — the pump does expose bolus source

- Recommendation: When wiring HistoryToDoseMapper, join BolusDeliveryHistoryLog (or LastBolusStatus bolusSource) by bolusId and set `automatic: source == .controlIQAutoBolus`, `false` for .gui/.quickBolus, and activationType.isAutomatic for .bluetoothRemoteBolus matched to a commanded bolus. Set `automatic: true` on Control-IQ-driven TBRs if they are ever reported.

- Verifier notes:
  - [review:amend] Code facts hold. The identified gap is exclusively pump-originated boluses (Control-IQ auto-boluses, quick-bolus) emitted by the unwired HistoryToDoseMapper with automatic nil. Under the default premise (Control-IQ off, quick bolus disabled) no pump-originated bolus exists, and the live paths conform: bolus automatic from activationType, temp basal true (only the app issues TBRs). Under conditional source (2) with the mapper wired, the original partial/medium applies (Trio would treat CIQ auto-boluses as manual). Suspend automatic=false on pump-initiated suspends is cosmetic.

**P22-6 syncIdentifier derivation, NewPumpEvent date/type, Linux shim divergence** (Conforms, impact low, verified)

On Apple builds (the only production target) the guide's rule holds: the DoseEntry's syncIdentifier is whatever LoopKit derives from raw, because NewPumpEvent.init overwrites it. The mapper's explicit assignment is redundant but harmless — same bytes — and the file's header comment says so. Two low-grade caveats: the Linux shim's NewPumpEvent neither derives syncIdentifier nor falls back type to dose.type, so Linux-only tests cannot catch a raw/syncIdentifier divergence or a missing `type`; and the mapper stamps a completed bolus's event date with endDate while every other path uses startDate, so a dose's `date` moves when it finalizes (identity is unaffected since raw is stable). Titles and .replaceComponent/.rewind types for site/cartridge change are appropriate.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:7` optimistic events pass DoseEntry with syncIdentifier nil; LoopKit derives it from raw
  - `reference: loopkit-trio/NewPumpEvent.swift:33` `dose?.syncIdentifier = raw.hexadecimalString` — overwrites whatever the driver set
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:192` `syncIdentifier: raw.hexadecimalString,` — set manually but byte-identical to what LoopKit derives
  - `LinuxShims/LoopKit/LoopKit.swift:544` shim NewPumpEvent.init stores dose as-is: no syncIdentifier derivation, no type-from-dose fallback
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:196` completed bolus event `date: dose.endDate`, while in-flight (line 219) and optimistic events use startDate

- Recommendation: Drop the manual `syncIdentifier:` in HistoryToDoseMapper to match the guide, or keep it and add a test asserting it equals raw.hexadecimalString. Bring the shim's NewPumpEvent.init in line with LoopKit (derive syncIdentifier and type). Use startDate for the completed-bolus event date for consistency.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P22-7 insulinType propagation** (Conforms, impact none, verified)

state.insulinType is threaded into bolus, temp basal, basal and resume doses on every live path (enactBolus:583, enactTempBasal:769, basal fallbacks:732/1321/1718, resume:902), into the history mapper via its insulinType parameter, and into PumpManagerStatus so LoopKit's 'nil means pump insulin' fallback is consistent. Suspend doses carry nil, matching LoopKit's DoseEntry(suspendDate:) API. The type is captured on the UnfinalizedDose at command time and persisted, so a bolus finalized after relaunch keeps the type it was enacted with even if the user changes the setting meanwhile.

- Evidence:
  - `Sources/TandemKitUI/TandemUICoordinator.swift:172` `self.pumpManager.state.insulinType = type` — the only writer, from the settings UI
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:259` insulinType round-trips through rawValue, so it survives relaunch
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:139` `raw["insulinType"] = insulinType?.rawValue` — persisted per in-flight dose
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:130` `insulinType: state.insulinType,` on PumpManagerStatus, so nil-typed doses resolve to the pump's type
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:40` finalized bolus reuses `dose.insulinType` captured at enact time

- Recommendation: None required. Optionally warn in UI if state.insulinType is nil after onboarding, since a nil type falls back to the host's pump-level default.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: the only writer of state.insulinType outside decoding is the settings UI (TandemUICoordinator.swift:172); the type is captured on UnfinalizedDose (139) and persisted.

**P22-8 value (programmed) for temp basal and basal markers** (Partial, impact low, amended)

The guide wants `value` to be the programmed amount. For boluses it is (units requested, milliunits on the wire). For temp basals, Tandem programs a percent of the pump's active profile rate; TandemKit reports value = host-schedule-rate x percent, so `value` and the derived `deliveredUnits` are correct only while the pump's profile equals the host's schedule and the segment does not change during the TBR (the rate is also looked up at Date.now, not startDate, which matters for re-emission and history mapping). The `.basal` marker's rate is floored to the 0.1 U/hr grid, so a 0.05 U/hr segment reports 0. There is no evidence the driver verifies pump-profile equality before enacting, so this is partial rather than conforming.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:685` `let baselineRate = getScheduledBasalRate()` — host's schedule, not the pump's active profile segment
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:722` `absoluteRate = roundToSupportedBasalRate(baselineRate * percent/100)` — what is reported as `value`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:749` pump is sent only `SetTempRateRequest(minutes:, percent:)`; actual U/hr is pump-profile x percent
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1759` getScheduledBasalRate evaluates the schedule at `Date.now`, not at the dose's startDate
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` finalized TBR `deliveredUnits: value * (duration / .hours(1))` inherits any error in value

- Recommendation: Read the pump's current profile segment rate (CurrentBasalStatusResponse / IDPSegment) and report value = pumpRate x percent/100; or reject enactTempBasal when the pump profile differs from the host schedule. Evaluate the schedule at the dose's startDate. Use round-to-nearest for the basal marker's rate.

- Verifier notes:
  - [review:amend] Code facts hold: value = host schedule x percent, evaluated at Date.now, and the .basal marker floors to the 0.1 grid. Under the premise (no screen, Tandem app not in use) nothing but TandemKit writes the pump profile, and syncBasalRateSchedule pushes the host schedule down via SetIDPSegmentRequest, so host/pump profile divergence shrinks to a failed-sync window. Residual error is segment-boundary drift within a TBR and the Date.now lookup, both small; Trio also recomputes TBR delivery from rate/duration. Keep partial, lower to low.

Open questions raised by this point:

- §4 (identity), not P22: NewPumpEvent.bolus builds raw from the `units` argument, and the same bolus is emitted with programmed units at enact (TandemPumpManager.swift:599), delivered units at completion (TandemDoseProgressReporter.swift:44) and `deliveredUnits ?? 0` at cancel (TandemPumpManager.swift:652) — raw changes over the dose's life.
- §3, not P22: getActivePumpEvents (TandemPumpManager.swift:1702) returns only the running temp basal, so the mutable bolus emitted at enact is not re-reported on subsequent syncs; combined with enactBolus using replacePendingEvents: false and later syncs using true, its survival depends on DoseStore purge behaviour.
- §7, not P22: fetchBasalStatus (StateSync.swift:141-187) has no branch for activeBasalType == .tempBasal, so a temp rate set on the t:slim X2 screen is never turned into a dose on the optimistic path.
- fetchBolusStatus (StateSync.swift:233) recomputes estimatedEndDate as now + full duration on every poll; this reaches PumpManagerStatus.bolusState and shouldDeferBolusSync but not hasNewPumpEvents — worth confirming it is intentional.
- The claim that Trio maps DoseEntry.automatic -> isSMB and manuallyEntered -> isExternal is from Trio's PumpHistoryStorage as I know it and the Trio skill's data-model note; verify against the Trio revision the host builds.
- TandemFeatureFlags defaults were taken from CLAUDE.md ('both off by default') plus the grouping at TandemFeatureFlags.swift:36-37; confirm the default table if the flag state matters for the final report.
### P23. A dose that never happened or was canceled with zero delivery stops being sent (with replacePendingEvents:true) so LoopKit removes it, rather than being finalized as a 0 U immutable dose; and no live dose is dropped by silence

Guide section: §3 transitions: never happened / zero-delivery cancel.

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 6 of 6 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

TandemKit never retracts a dose. `cancelBolus` finalizes the bolus as an immutable 0 U dose (with a changed `raw`) when the pump reports zero or the LastBolusStatus query fails, conflating "unknown" with "nothing delivered". Natural completion (`fetchBolusStatus`, bolusId==0) does the opposite on query failure: it finalizes at the full programmed amount. After an app relaunch the persisted in-progress bolus is never re-reported, finalized or explicitly retracted — it is silently dropped by the next `replacePendingEvents:true` batch or lingers mutable. Only the pre-report rejection paths in `enactBolus`/`enactTempBasal` conform: state and events are written after the pump confirms, so a dose that never happened is never sent. No tests cover the cancel or finalization emissions.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P23-1 | Non-conforming | medium | verified | cancelBolus finalizes as immutable 0 U instead of retracting |
| P23-2 | Non-conforming | high | verified | cancelBolus treats a failed LastBolusStatus query as 0 U delivered |
| P23-3 | Conforms | none | verified | enactBolus: pump rejection precedes the mutable report |
| P23-4 | Non-conforming | medium | amended | Completion path finalizes a never-run/pump-canceled bolus at full or 0 U |
| P23-5 | Non-conforming | high | amended | App relaunch: persisted in-progress bolus dropped by silence |
| P23-6 | Conforms | none | verified | Temp basal: never-happened and immediate-cancel paths |

**P23-1 cancelBolus finalizes as immutable 0 U instead of retracting** (Non-conforming, impact medium, verified)

When a bolus is canceled with zero delivery, the guide says stop sending it so LoopKit removes it. TandemKit instead emits an immutable `.bolus` DoseEntry with `deliveredUnits = 0`, and because `units:` is the delivered amount the `raw` changes from "bolus <programmed> <start>" to "bolus 0.0 <start>". With `replacePendingEvents: true` the mutable row is purged and a new permanent 0 U bolus is inserted, advances `pumpEventQueryAfterDate`, and is offered to HealthKit. IOB is unaffected (Trio DoseEntry.netBasalUnits returns deliveredUnits = 0), so the impact is metadata/upstream noise plus the identity break, not miscounted insulin.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:641` let canceledDose = bolusDose.toDoseEntry(endDate: Date.now) — isMutable defaults to false
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:652` .bolus(dose: canceledDose, units: canceledDose.deliveredUnits ?? 0, ...) — raw built from delivered, not programmed, units
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:657` self.emitPumpEvents(events) — replacePendingEvents defaults to true (line 1733)
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:10` raw: "\(DoseType.bolus.rawValue) \(units) \(date)" — units are part of the identity

- Recommendation: In `cancelBolus`, when the pump reports 0 delivered, emit `getActivePumpEvents()` only (replacePendingEvents: true) so the mutable bolus is removed; when delivered > 0 finalize with the original programmed `units` in `raw` so the syncIdentifier stays constant.

- Verifier notes:
  - [review:confirm] Verified: raw is built from delivered units (652, NewPumpEvent ext:10), emitPumpEvents defaults replacePendingEvents true (1733), DoseStore advances pumpEventQueryAfterDate on final rows, and only immutable rows go to HealthKit. In LoopKit the 0 U row has no IOB effect, so medium is right; trigger is the app's cancel, unaffected by the premise. Caveat for the recommendation: Trio ignores replacePendingEvents and never purges mutable rows, so 'stop sending' would leave the full programmed bolus in Trio's history; Trio only corrects it because the 0 U re-report triggers its smaller-amount update.

**P23-2 cancelBolus treats a failed LastBolusStatus query as 0 U delivered** (Non-conforming, impact high, verified)

The zero-delivery retraction rule only applies when the driver knows nothing was delivered. `cancelBolus` cannot distinguish that from a BLE timeout or a LastBolusStatus answer for a different bolus: both return nil and are coerced to 0. A bolus that the pump had already partly delivered (the CancelBolusRequest succeeded only because delivery was in progress) is then finalized as a permanent 0 U dose. Loop/Trio drops that insulin from IOB entirely and may re-dose it. Line 636 sleeps 2 s for the Mobi to log the bolus, which suggests the author knows the query can miss.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` `?? 0` — nil (no response / bolusId mismatch) becomes zero delivered
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:522` guard let response = bluetooth.write(request) ... else { return nil } — no response yields nil
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:527` guard response.bolusId == bolusId else { ... return nil } — mismatch also yields nil
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:161` deliveredUnits: isMutable ? nil : deliveredUnits — the 0 is written into the immutable entry
  - `reference: loopkit-trio/DoseEntry.swift:95` netBasalUnits for .bolus: deliveredUnits ?? programmedUnits — a 0 here removes the bolus from IOB

- Recommendation: Never coerce nil to 0. On query failure keep the dose mutable (re-report with the same raw) or finalize with the estimated delivered amount from the progress reporter, and retry the LastBolusStatus read on the next sync before finalizing.

- Verifier notes:
  - [review:confirm] Same defect as P05-2/P07-1, all evidence lines verified literally. The finding's own triggers (BLE timeout, bolusId mismatch) survive the premise: the 2 s sleep at 636 exists because the Mobi may not yet have stored the cancelled bolus, so LastBolusStatus can still name the previous bolus and the guard at 527 returns nil. No screen is involved. Nonconforming/high stands; the recommendation to keep the dose mutable and re-query is consistent with the guide's report-or-delete rule.

**P23-3 enactBolus: pump rejection precedes the mutable report** (Conforms, impact none, verified)

The guide's "never happened" transition requires that a dose the pump refused is not left in LoopKit. In `enactBolus` every rejection (connect failure, no BolusPermission response, permission denied, no InitiateBolus response, initiation not successful) returns before `state.bolusDose` is set and before the mutable NewPumpEvent is emitted, so there is nothing to retract. This holds in steady state, on first sync after pairing and after reconnect alike, because the ordering is within one synchronous command body.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:545` guard permissionResponse.isPermissionGranted else { ... completion(...); return } — no state/event written
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:571` guard initiateResponse.wasBolusInitiated else { releaseBolusPermission; completion; return }
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:594` self.state.bolusDose = dose — only after wasBolusInitiated
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:598` emitPumpEvents([...bolus mutable...], replacePendingEvents: false) — first report, after acceptance
  - `Sources/TandemCore/Messages/Control/InitiateBolus.swift:164` wasBolusInitiated: status == 0 && statusType == .success

- Recommendation: Keep this ordering; add a unit test with StubPumpBluetooth asserting that a rejected InitiateBolusRequest produces zero `hasNewPumpEvents` calls, so a future refactor cannot move the report ahead of the pump's confirmation.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P23-4 Completion path finalizes a never-run/pump-canceled bolus at full or 0 U** (Non-conforming, impact medium, amended)

A bolus the user cancels on the t:slim X2 screen (or that the pump aborts after accepting InitiateBolus) reaches the same `bolusId == 0` branch as a normal completion. If LastBolusStatus reports 0 delivered, the dose is finalized as an immutable 0 U bolus instead of being retracted (same shape as P23-1). If the query fails or returns another bolus id, `getPumpEvent` assumes full delivery and finalizes at the programmed total — a dose that never happened is made permanent, over-counting IOB. In both cases `raw` changes, so identity matching is bypassed and only the `replacePendingEvents` purge prevents a duplicate.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:249` if response.bolusId == 0 { // Bolus is finished — reached for any non-delivering status incl. pump-side cancel
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:256` actualDelivered = queryLastBolusDeliveredVolume(bolusId: bolusId) — nil on failure/mismatch
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:260` events.append(progressReport.getPumpEvent(actualDeliveredUnits: actualDelivered))
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:33` let delivered = actualDeliveredUnits ?? total — nil becomes the full programmed amount
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:44` units: delivered — raw changes to the delivered amount, so identity differs from the mutable report

- Recommendation: In the bolusId==0 branch: if the pump reports 0 delivered, emit only `getActivePumpEvents()` to retract; if the query fails, keep the dose mutable (same raw) and retry next sync; never default to `total`. Build raw from programmed units in all reports.

- Verifier notes:
  - [review:amend] Mechanism confirmed: line 249 is reached for any non-delivering status with a live reporter, `?? total` (reporter:33) assumes full delivery when LastBolusStatus fails or mismatches, and raw is re-keyed on `delivered` (reporter:44). The pump-UI cancel trigger is gone under the premise; pump-side aborts remain. Impact is lower than rated for the default config: the 0 U branch carries the pump-reported value and is IOB-neutral (and in Trio it is the only update that shrinks the enact-time programmed row, since Trio never retracts), so it is a shape deviation. The full-delivery over-count needs an abort plus a failed read in one pass; a bolusId mismatch cannot occur without quick bolus/Control-IQ, where impact would be high.

**P23-5 App relaunch: persisted in-progress bolus dropped by silence** (Non-conforming, impact high, amended)

The guide's corollary is that silence must only remove doses that truly did not happen. If the app is killed mid-bolus and relaunched, `bolusProgressReport` is gone while `state.bolusDose` survives. Once the 30 s grace passes, `fetchBolusStatus(fromSync:)` either clears `bolusDose` without emitting anything (status 0) or returns early (status delivering/requesting). The bolus that was actually delivered is never finalized: the next basal/temp-basal/suspend emission (all `replacePendingEvents: true`) purges the mutable row from DoseStore and InsulinDeliveryStore, so the delivered insulin vanishes from IOB. No code path rebuilds a reporter or re-reports the persisted dose on relaunch.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:70` internal var bolusProgressReport: TandemDoseProgressReporter? — in-memory only, nil after relaunch
  - `Sources/TandemKit/State/TandemPumpManagerState.swift:244` bolusDose = UnfinalizedDose(rawValue: bolusDoseRaw) — the in-progress bolus IS persisted
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:217` if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil { state.bolusDose = nil ... return } — cleared with no emit
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:226` guard let progressReport = bolusProgressReport else { return } — any other status returns silently
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:598` initial mutable bolus was emitted with replacePendingEvents: false and is never re-sent

- Recommendation: On init, if `state.bolusDose` is non-nil, recreate the progress reporter (or a lightweight finalizer) from the persisted dose; in `fetchBolusStatus`, when `bolusProgressReport == nil` but `state.bolusDose != nil`, query LastBolusStatus and finalize with the pump's delivered volume instead of clearing state silently.

- Verifier notes:
  - [review:amend] Same defect as P04-2/P05-4/P12-3; all cited lines verified, including the DoseStore purge at trio-fork line 706 (next-dev 625). shouldDeferBolusSync only delays the sync-path read until estimatedEnd+30 s; the qualifying-event path hits the same reporter-nil branches immediately. Correct the consequence per host: in LoopKit DoseStore hosts the delivered bolus is purged and lost; in Trio (ignores replacePendingEvents, stores enact-time bolus at programmedUnits, never deletes) it is retained and over-counted only if the pump aborted it. Relaunch is an app-side trigger, so the premise does not lower the rating.

**P23-6 Temp basal: never-happened and immediate-cancel paths** (Conforms, impact none, verified)

A temp basal the pump refuses (no CurrentBasalStatus response, StopTempRate failure, SetTempRate no-response or non-OK status) is never reported: `state.basalDose` and the mutable `.tempBasal` event are written only after the pump confirms, on every path traced (steady state, reconnect, relaunch — the body is synchronous). A TBR canceled by a zero-duration/100% enact, suspend, Control-IQ enable or a basal-status change is finalized via `getActivePumpEvents(endDate:)` with delivered units for the elapsed window rather than silently dropped. Only a cancel within the same instant would yield a ~0 U immutable temp basal instead of a retraction; its netBasalUnits is 0, so accounting is unaffected.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:756` guard response.isStatusOK else { ... completion(...); return } — returns before any dose/event is written
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:774` self.state.basalDose = dose — set only after SetTempRateResponse OK
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:736` var events = self.getActivePumpEvents(endDate: dose.startDate) — cancel path finalizes the running TBR, does not drop it
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` state.basalDose.toDoseEntry(isMutable: endDate == nil, endDate: endDate ?? Date.now)
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` deliveredUnits: isMutable ? nil : value * (duration / .hours(1)) — actual elapsed delivery, not 0

- Recommendation: No change needed for this point. Optionally retract (omit) a TBR finalized with an elapsed duration below one basal increment instead of emitting a ~0 U immutable entry.

- Verifier notes:
  - [review:confirm] Code facts hold: state.basalDose and the TBR event are written only after SetTempRateResponse isStatusOK (756/774), and cancel/suspend/basal-status-change paths finalize the running TBR via getActivePumpEvents(endDate:) with elapsed delivery. Triggers are the app and pump-initiated stops (in scope under the premise), and both are handled. conforms/none stands.

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

Overall: **Partial** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 6 of 6 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

The live path alone behaves predictably in DoseStore: suspend/resume/basal are immutable and dated at emission, the only mutable rows are the in-flight bolus and the running temp basal, and a finalized batch always carries the still-running TBR so the cursor is only pulled back to a TBR start. The history path is not wired to any emission today (mapToEvents has no caller; historyBackfill/historyDoseReporting default off), so nothing collides yet, but the design is not collision-safe: live raws are type/units/ISO strings while history raws are HistoryLogSyncIdentifier bytes, and live bolus/TBR raws change on finalization. The planner's emitFloor and DoseStore's basal-sync window would both drop late-discovered pump-UI doses once emission exists.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| P24-1 | Partial | low | amended | Live-path vs history-path raw for the same bolus |
| P24-2 | Partial | low | amended | Live raw changes on finalization; update-vs-insert relies on mutable purge |
| P24-3 | Conforms | none | verified | pumpEventQueryAfterDate cursor behaviour on the live path |
| P24-4 | Partial | low | amended | emitFloor derived from host floor would drop late-discovered pump-UI doses |
| P24-5 | Partial | low | amended | Cache window purge vs backfill depth; IDS basal sync window |
| P24-6 | Conforms | low | verified | Event date choice: completed bolus dated endDate, everything else startDate |

**P24-1 Live-path vs history-path raw for the same bolus** (Partial, impact low, amended)

A Loop-commanded bolus reported live (raw = string) and later re-read from history (raw = 10-byte identifier) has two different raws, so DoseStore's unique-by-raw dedup would insert two PumpEvent rows and the InsulinDeliveryStore would hold two immutable doses: a double count. Nothing prevents this except that the history emission layer does not exist yet and both flags default off. HistoryLogSyncIdentifier's own doc (line 45) promises the live report will mint the same identity from bolusId at command time, but enactBolus/TandemDoseProgressReporter/cancelBolus still use the string raw, and the serial needed to mint it is only known after fetchPumpInformation.

- Evidence:
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:10` live bolus raw: "\(DoseType.bolus.rawValue) \(units) \(iso8601 date)"
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:183` history bolus raw = HistoryLogSyncIdentifier.bolus(pumpSerial:, bolusId:)
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:194` isCommandedBolus only sets wasProgrammedByPumpUI; it does not suppress or re-key the event
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:9` "Nothing is mapped to doses or emitted here" — no caller of mapToEvents exists in Sources/
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:173` historyDoseReporting = historyBackfill && historyDoseReporting; both default false, no consumer

- Recommendation: Before enabling historyDoseReporting, make the live bolus/TBR raw equal HistoryLogSyncIdentifier.bolus/.tempRate (serial + pump id) once the serial is known, or have the emission layer skip/re-key history events whose bolusId matches a live-reported dose. Add a test asserting live raw == history raw for the same bolusId.

- Verifier notes:
  - [review:amend] Facts confirmed: history bolus raw is HistoryLogSyncIdentifier.bolus (Mapper:183) while live raw is the type/units/ISO string (NewPumpEvent:10); the identifier's own doc says nothing emits it yet (SyncIdentifier:45-47); mapToEvents has no caller in Sources/; historyBackfill/historyDoseReporting default false (Flags:32-39). Would double count in Loop (unique by raw) and also in Trio, since the history event is dated dose.endDate (Mapper:197) while the live one uses startDate, defeating Trio's (date,type) dedup. But under the default configuration nothing can emit it, so current accounting impact is low; becomes high the moment an emission layer is wired without re-keying.

**P24-2 Live raw changes on finalization; update-vs-insert relies on mutable purge** (Partial, impact low, amended)

For an interrupted/cancelled bolus and for every early-ended temp basal, the finalized event's raw differs from the mutable one. At the PumpEvent tier the old row disappears only because every finalizing emission uses replacePendingEvents: true (default); at the InsulinDeliveryStore tier the mutable dose is soft-deleted and a fresh immutable row inserted rather than updated. The end state is correct today (Medtrum-style safety net), but dedup by raw is not what keeps it correct, and any future finalizing emission with replacePendingEvents: false, or a history-path re-report, would duplicate. Only the initial enactBolus emission uses false (line 600), which is fine.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:44` finalized bolus: units: delivered (not programmed) feeds the raw string
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:652` cancelBolus: .bolus(dose:, units: canceledDose.deliveredUnits ?? 0, ...)
  - `Sources/TandemCore/Common/Extensions/NewPumpEvent.swift:20` tempBasal raw uses dose.programmedUnits, i.e. rate x duration
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:177` finalized TBR endDate is the actual (earlier) end, so programmedUnits and raw change
  - `reference: loopkit-trio/DoseStore.swift:706` replacePendingEvents purges mutable == YES rows before inserting

- Recommendation: Key live bolus events on programmed units (or the pump bolusId) and TBR events on start date/rate rather than programmedUnits, so raw is byte-identical across mutable and finalized reports; keep replacePendingEvents: true on finalization.

- Verifier notes:
  - [review:amend] Lead reviewer re-check: facts confirmed (reporter:44, 652, NewPumpEvent.swift:20). Same latent identity defect as the reviewed P03-1/P03-3/P16-4/P17-2, all rated low because every finalizing batch uses replacePendingEvents:true and Trio ignores raw. Lowered from medium to low.

**P24-3 pumpEventQueryAfterDate cursor behaviour on the live path** (Conforms, impact none, verified)

The only long-lived mutable rows TandemKit creates are the running TBR and the in-flight bolus. A suspend is emitted immutable at its start, so an open suspend never holds the cursor back. When a finalized bolus is emitted while a TBR runs, the batch includes the mutable TBR and DoseStore pulls the cursor to the TBR start (at most the TBR duration ago) — LoopKit's intended behaviour. On relaunch, state.basalDose/bolusDose are persisted so the same rows are re-derived. Minor: DoseStore assigns (not maxes) the cursor, so a future backfill batch of older immutable events would move it backward; that only causes upstream re-query and is dedup-safe upstream.

- Evidence:
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:196` suspend/resume/basal DoseEntries are built without isMutable (immutable)
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1707` getActivePumpEvents: TBR is mutable only when endDate == nil
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:259` bolus completion batch = getActivePumpEvents() (mutable TBR) + finalized bolus
  - `reference: loopkit-trio/DoseStore.swift:747` cursor set to firstMutableDate if it precedes the newest final date, else to finalDate
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:141` fetchBasalStatus emits only on basal-type change (finalizes TBR with endDate: now)

- Recommendation: No change needed for the live path. When history emission is added, expect the cursor to move backward on backfill batches and confirm upstream consumers dedup by syncIdentifier.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

**P24-4 emitFloor derived from host floor would drop late-discovered pump-UI doses** (Partial, impact low, amended)

The planner's contract says history events dated before emitFloor will not be reported. The host floor marches to roughly now as live events are reported (Trio: lastEventDate-15min; in Loop, DeviceDataManager returns doseStore.pumpEventQueryAfterDate — from memory, verify). A quick-bolus or Control-IQ bolus on the pump discovered on the next 5-minute sync, after a live TBR/basal event was finalized, is older than that floor and would be filtered out — exactly the external dose the backfill exists to find, and under-counting IOB is the over-delivery direction. The premise that DoseStore discards such events is wrong for the Trio-fork DoseStore, which only purges older than 24h. Not yet exercised because no emission layer consumes TickOutcome.emitFloor.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillPlanner.swift:98` emitFloor = max(hostFloor, firstSeenFloor)
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillPlanner.swift:90` comment: "events below it are discarded on arrival" — DoseStore.addPumpEvents has no such filter
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:322` hostEventFloor = delegate.startDateToFilterNewPumpEvents(for:)
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillCoordinator.swift:129` emitFloor computed each tick and handed out in TickOutcome for the emission layer
  - `CLAUDE.md:537` Trio returns lastEventDate - 15min as the host floor

- Recommendation: Do not use startDateToFilterNewPumpEvents as an emission floor for history-derived doses; floor only on firstSeenFloor (and DoseStore's 24h cache). Fix the planner doc comment and add a test that a pump-UI bolus older than hostFloor but within the lookback is still reported.

- Verifier notes:
  - [review:amend] Code facts confirmed: emitFloor = max(hostFloor, firstSeenFloor) (Planner:98), the doc claims events below the host floor are discarded on arrival (Planner:90), hostEventFloor reads startDateToFilterNewPumpEvents (321-323), Trio returns lastEventDate-15min (DeviceDataManager:660). The discard premise is wrong for both hosts: DoseStore's only date drop is the cacheStartDate purge (trio:714) and Trio's storePumpEvents has no date filter. Under the premise, late-discovered pump-side doses exist only via quick bolus/Control-IQ (conditional, off), and no emission layer consumes emitFloor, so default impact is low; high once emission exists under those sources (or for a live-lost Loop bolus recovered from history). Loop DeviceDataManager behaviour unverified here.

**P24-5 Cache window purge vs backfill depth; IDS basal sync window** (Partial, impact low, amended)

Backfilled events can be at most ~7h old, well inside DoseStore's 24h PumpEvent cache, so the cache purge cannot eat them; a re-paired same-serial pump keeps its old firstSeenFloor but the walk is still capped at 7h. However DoseStore only forwards non-bolus pump events to the InsulinDeliveryStore from the last immutable basal end date onward. Because TandemKit's live path continually emits immutable .basal/.suspend/.resume events dated now, any history-derived temp basal, suspend or resume that predates the newest live basal event would be stored as a PumpEvent but never reach the InsulinDeliveryStore/IOB. Only backfilled boluses are safe under this ordering. Not exercised today (no emission layer).

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillPlanner.swift:72` deepFetchLookback = 7 hours
  - `Sources/TandemKit/PumpManager/History/HistoryBackfillPlanner.swift:76` deepFetchTarget = max(now - lookback, firstSeenFloor); never deeper than 7h
  - `reference: loopkit-trio/DoseStore.swift:196` cacheLength default 24 hours
  - `reference: loopkit-trio/DoseStore.swift:916` IDS sync starts at max(lastImmutableBasalEndDate, now-24h)
  - `reference: loopkit-trio/DoseStore.swift:1140` only boluses are saved when startDate < basalStart; non-bolus doses need startDate >= basalStart

- Recommendation: When wiring history emission, either restrict backfilled doses to boluses, or stop emitting synthetic live .basal events so history owns the basal timeline (MinimedKit pattern). Document the constraint in HistoryBackfillPlanner.

- Verifier notes:
  - [review:amend] Code facts hold: 7h deepFetchLookback, DoseStore forwards non-bolus events only from lastImmutableBasalEndDate, and the live path emits immutable .basal at TBR end. Under the default premise the only history-derived non-bolus doses not already known to the live path are pump-initiated stops during BLE loss, which the live path also reports (at detection time) from basal status on reconnect; Control-IQ TBRs are conditional source (2). mapToEvents still has no caller. Keep partial, lower to low; medium under Control-IQ once emission is wired.

**P24-6 Event date choice: completed bolus dated endDate, everything else startDate** (Conforms, impact low, verified)

At the DoseStore tier the date shift between the mutable and finalized report of the same raw is harmless: the mutable row is purged by replacePendingEvents before insert, the IDS match is by syncIdentifier, and dating a completed bolus at its end only advances the cursor to completion time. The inconsistency with the live path (startDate) is cosmetic in DoseStore. It becomes a hazard only if the emission layer applies emitFloor to event.date: a bolus could pass the floor as mutable and be dropped when finalized, leaving the mutable row purged and the dose lost — see P24-4.

- Evidence:
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:196` completed bolus: NewPumpEvent(date: dose.endDate, ...)
  - `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift:219` in-flight bolus (same raw): NewPumpEvent(date: dose.startDate, ...)
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:45` live finalized bolus dated dose.startDate
  - `Tests/TandemKitTests/HistoryToDoseMapperTests.swift:54` test pins event.date == completion time, so the choice is deliberate
  - `reference: loopkit-trio/DoseStore.swift:720` "There is no guarantee of event ordering" — DoseStore does not depend on batch order

- Recommendation: Prefer one convention (date = startDate) for all dose events, matching the live path and OmnipodKit/MinimedKit, and never filter finalizing events by a floor that the mutable report already passed.

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.

Open questions raised by this point:

- HistoryLogStore.swift:39 states DoseStore "under Trio isn't used at all"; if Trio persists pump events in its own PumpHistoryStorage keyed by syncIdentifier, the §8 DoseStore consequences apply to Loop only and Trio's dedup/purge rules need a separate audit.
- Loop's DeviceDataManager.startDateToFilterNewPumpEvents is believed (from memory) to return doseStore.pumpEventQueryAfterDate; not on disk in the scratchpad — verify before acting on P24-4.
- The Core Data model (unique constraint on PumpEvent.raw and CachedInsulinDeliveryObject.syncIdentifier, merge policy) is not in the scratchpad; the guide's "unique constraint on raw" is taken on trust.
- HistoryLogSyncIdentifier.swift:45 says "Nothing emits these identifiers yet" while HistoryToDoseMapper does mint them (unwired); the comment is stale relative to the mapper but accurate for what reaches the delegate.
- docs/tandemkit-history-integration-plan.md describes a HistoryReconciler/PendingDose matching layer (±5 min, ±0.05 U) marked as completed; no such code exists at HEAD — the doc is stale.
### G01. How Trio actually consumes TandemKit's events: with lastReconciliation and replacePendingEvents ignored and dedup by (event.date, type), does TandemKit's reporting produce correct bolus, temp basal, suspend/resume and site-change records in Trio, including cancellations and mutable-to-final transitions?

Guide section: host consumer (outside the guide).

Overall: **Non-conforming** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 8 of 8 findings independently reviewed

Trio ignores lastReconciliation/replacePendingEvents and stores events keyed by (date, type), so TandemKit's Loop-oriented finalization machinery is mostly inert in the shipped host. What survives works for the common paths: Trio-commanded boluses (programmed then delivered, updated downward), Trio-commanded temp basals (start record + oref truncation by the next TBR), app-side suspend/resume, and site/cartridge changes. Four paths break in Trio: (1) cancelBolus falls back to 0 U when the pump's LastBolusStatus read fails, which erases the delivered portion from IOB; (2) a pump-side resume is emitted as a `.basal` dose that Trio discards, leaving an orphan PumpSuspend that makes Trio's oref treat the pump as currently suspended and zero all later basal delivery while Trio keeps dosing; (3) every TBR cancellation or early end (skipNeutralTemps cancel, pump-side stop, Control-IQ enable) is reported only as a deliveredUnits-bearing TBR plus `.basal`, both of which Trio skips, so the stored TBR runs to its full programmed duration in IOB; (4) percent rounding can push the reported rate above maxBasal and Trio's filter then drops the TBR record entirely. A restart mid-bolus also loses the completion/cancel correction because the progress reporter is not persisted.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| G01-1 | Conforms | none | verified | Bolus initial/completion/cancel dedup in Trio |
| G01-2 | Non-conforming | high | verified | cancelBolus 0 U fallback erases delivered insulin in Trio |
| G01-3 | Non-conforming | medium | amended | Pump-side resume reported as .basal leaves an orphan PumpSuspend in Trio |
| G01-4 | Partial | high | amended | TBR cancel / early end never truncates Trio's stored TBR |
| G01-5 | Partial | medium | verified | Percent rounding can push reported rate over Trio's maxBasal filter |
| G01-6 | Partial | medium | verified | Restart mid-bolus loses the completion/cancel correction in Trio |
| G01-7 | Conforms | none | verified | Site change and cartridge change records |
| G01-8 | Not applicable | low | verified | Ignored lastReconciliation/replacePendingEvents and dedup-key collisions |

**G01-1 Bolus initial/completion/cancel dedup in Trio** (Conforms, impact none, verified)

All three bolus emissions share the same `date` (the UnfinalizedDose.startDate captured at initiation), so in Trio they collapse onto one BolusStored row keyed (date, bolus). The initial event stores the programmed amount; completion/cancel re-send with deliveredUnits, and Trio overwrites only when the new amount is smaller — exactly the downward correction a partial bolus needs. Delivered can never exceed programmed, so the 'smaller only' rule never blocks a legitimate update. Trio never reads `raw`, so TandemKit's changing raw (units embedded) has no effect here; that defect matters only against LoopKit's DoseStore (covered by earlier points).

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:599` initial mutable bolus: `[NewPumpEvent.bolus(dose: doseEntry, units: units, date: dose.startDate)]` (units = programmed)
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:33` completion: `let delivered = actualDeliveredUnits ?? total`, same dose.startDate
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:652` cancel: `.bolus(dose: canceledDose, units: canceledDose.deliveredUnits ?? 0, date: canceledDose.startDate)`
  - `Trio: Trio/Sources/APS/Storage/PumpHistoryStorage.swift:112` Trio updates a duplicate only if `amount < existingAmount as Decimal`
  - `Trio: Trio/Sources/APS/Storage/PumpHistoryStorage.swift:101` amount taken from `dose.unitsInDeliverableIncrements` (deliveredUnits ?? programmedUnits)

- Recommendation: No Trio-side change needed for the normal path; keep `date` pinned to the original startDate for all three emissions. Fix `raw` stability separately for LoopKit hosts.

- Verifier notes:
  - [review:confirm] Verified. Initial event uses dose.startDate (UnfinalizedDose captures Date.now once, UnfinalizedDose.swift:30) and units=programmed; completion reuses the same DoseEntry.startDate; cancel uses canceledDose.startDate. Trio keys (date,type) and updates only when smaller; unitsInDeliverableIncrements is deliveredUnits ?? programmedUnits in the pinned fork. Trio never reads raw. Delivered is pump-reported and floored to the bolus grid, so it cannot exceed programmed. Verdict and none impact stand; note the correction path itself is what G01-2 and G01-6 break.

**G01-2 cancelBolus 0 U fallback erases delivered insulin in Trio** (Non-conforming, impact high, verified)

When the post-cancel LastBolusStatus read fails (no response, or the pump returns a different bolusId — plausible right after a cancel despite the 2 s sleep), TandemKit reports the canceled bolus as 0 U delivered. Because Trio's dedup rule accepts any smaller amount, the BolusStored row that previously held the programmed units is overwritten to 0. Insulin that the pump actually pushed before the cancel (potentially several units) disappears from Trio's pump history and therefore from oref IOB, biasing subsequent SMB/TBR decisions toward over-delivery. In LoopKit the 0 U dose would at least be visible; in Trio it silently zeroes the record.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:639` `bolusDose.deliveredUnits = self.queryLastBolusDeliveredVolume(bolusId: bolusId) ?? 0`
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:527` query returns nil on bolusId mismatch: `guard response.bolusId == bolusId else`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:652` emitted with `units: canceledDose.deliveredUnits ?? 0`
  - `Trio: Trio/Sources/APS/Storage/PumpHistoryStorage.swift:112` Trio replaces the stored amount because 0 < existingAmount

- Recommendation: On a failed delivered-volume read, do not report 0. Either retry the read, fall back to the progress reporter's estimate (`bolusProgressReport.progress.deliveredUnits`) or the programmed amount, or leave the existing record untouched and reconcile from pump history later. Never emit an amount that is known to be a placeholder.

- Verifier notes:
  - [review:confirm] Verified literally. On a nil LastBolusStatus (no response, or bolusId mismatch at +StateSync:527) deliveredUnits becomes 0, the event is emitted at the original startDate with units 0, and Trio's smaller-only rule overwrites the stored programmed amount with 0. Insulin the pump delivered before the cancel vanishes from Trio pump history and oref IOB. Trigger is an app-side cancel plus a failed read (BLE), so the premise does not reduce it. UnfinalizedDose.deliveredUnits defaults to 0 anyway (line 14), so there is no distinguishing a placeholder from a genuine zero. High stands.

**G01-3 Pump-side resume reported as .basal leaves an orphan PumpSuspend in Trio** (Non-conforming, impact medium, amended)

If the user resumes on the t:slim X2 screen or the Tandem app after any suspend (app- or pump-initiated), `fetchBasalStatus` sees basal while state is `.suspend` and emits a `.basal` dose. Trio stores nothing for `.basal`, so its history holds a PumpSuspend with no PumpResume. Trio's oref then treats the pump as suspended from that moment to now: scheduled basal is zeroed and later TBRs overlapping the 'suspend' are removed, producing a large negative basal-IOB error. Meanwhile TandemKit's status reports not-suspended, so Trio keeps enacting TBRs and SMBs against the understated IOB. The condition persists until an app-side resume or the 24 h history window ages out. `handleHomeScreenMirrorResponse`, which would emit `.resume`, has no caller.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:142` only `.resume` state short-circuits: `if activeBasalType == .basal, state.basalDose.type == .resume`
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:173` suspend -> basal transition emits `events.append(NewPumpEvent.basal(` not `.resume`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:904` `.resume` is emitted only by sendResumePumping (app-initiated)
  - `Trio: Trio/Sources/APS/Storage/PumpHistoryStorage.swift:181` `.basal` falls to `default:` and is discarded
  - `Trio: Trio/Sources/APS/OpenAPSSwift/Iob/IobHistory.swift:159` `if let last = pumpSuspendResume.last, last.type == .pumpSuspend {` -> currently suspended until clock

- Recommendation: In fetchBasalStatus, when the previous state is `.suspend` and the pump reports basal, emit a `.resume` dose (as handleHomeScreenMirrorResponse already does) before or instead of the `.basal` dose. Add a test that a suspend->basal transition produces a `.resume` event.

- Verifier notes:
  - [review:amend] Code claims verified: suspend->basal in fetchBasalStatus emits .basal only (+StateSync:173), .resume comes solely from sendResumePumping, handleHomeScreenMirrorResponse has no caller, Trio drops .basal and treats a trailing PumpSuspend as suspended-until-now. But the finding's trigger (resume on the t:slim screen / Tandem app) is excluded by the premise. The residual in-scope trigger is app-initiated: ResumePumpingRequest whose response is lost after the pump resumed returns an error without recording state (TandemPumpManager.swift:895), so the next sync emits .basal and the orphan PumpSuspend results unless the user retries. Same consequence, much narrower trigger: medium for the default configuration.

**G01-4 TBR cancel / early end never truncates Trio's stored TBR** (Partial, impact high, amended)

Trio stores only the mutable TBR start (rate, programmed duration) and relies on the next TBR record to truncate it. That works for the steady-state loop where a new TBR arrives every cycle, and for suspend (oref truncates at PumpSuspend). It fails whenever TandemKit ends a TBR without a replacement TBR: the skipNeutralTemps cancel, a pump-side stop detected by fetchBasalStatus, and the Control-IQ-enable path (TandemPumpManager.swift:1324). All three emit a deliveredUnits-bearing TBR (skipped) plus `.basal` (ignored), so Trio's IOB counts the old rate for its full programmed duration — an error of (tempRate − scheduled) × remaining minutes, up to a full 30 min TBR. APSManager's current-temp readback is unaffected because basalDeliveryState becomes `.active`.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:725` cancel branch `if duration < .ulpOfOne || percent == 100 {` emits finalized TBR + `.basal`
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` finalized TBR carries `deliveredUnits: isMutable ? nil : value * (duration / .hours(1))`
  - `Trio: Trio/Sources/APS/Storage/PumpHistoryStorage.swift:146` `guard !isCancel else { continue }` skips any TBR with deliveredUnits set
  - `Trio: Trio/Sources/APS/OpenAPSSwift/Iob/IobHistory.swift:105` oref truncates a TBR only by the next stored TBR: `if currEnd > next.timestamp`
  - `Trio: Trio/Sources/APS/OpenAPSSwift/DetermineBasal/TempBasalFunctions.swift:93` skipNeutralTemps cancel sends `determination.duration = 0` -> reaches the TandemKit cancel branch

- Recommendation: When ending a TBR early without a replacement, additionally emit a zero-duration or scheduled-rate `.tempBasal` event with `deliveredUnits == nil` at the cancel time so Trio stores a truncating record (this is how Trio expects Minimed/Omnipod cancels to appear), or coordinate a Trio-side change to honor deliveredUnits-bearing TBRs as truncations.

- Verifier notes:
  - [review:amend] Claims verified, but the trigger is far broader than stated. The cancel branch fires on `percent == 100` as well as duration 0, so every oref neutral temp (rate == profile basal, 30 min, the default since skipNeutralTemps=false) lands there: TandemKit emits the old TBR finalized with deliveredUnits set (Trio skips it) plus .basal (Trio ignores it) and no new TBR. Trio's history therefore never truncates the prior TBR whenever oref returns to neutral, a routine every-few-cycles event, so oref's IOB carries the old temp for its full remaining programmed duration. Routine occurrence of up to (temp - scheduled) x 30 min error is a clinically meaningful IOB error: high.

**G01-5 Percent rounding can push reported rate over Trio's maxBasal filter** (Partial, impact medium, verified)

TandemKit reports the rate the pump will actually run (baseline × rounded percent), which can exceed the requested rate by up to baseline × 0.5 %; after flooring to 0.01 U/h this is ≥ 0.01 whenever the profile baseline is ≥ 2 U/h (e.g. baseline 4.0, request 3.02 → 76 % → 3.04). oref routinely requests exactly maxBasal, so in that case Trio's MDT-oriented filter silently discards the TBR event. No TBR record is stored, so oref continues to count the previous TBR (often 0 U/h) or scheduled basal for up to 30 min while the pump delivers at max — an IOB undercount of roughly (max − prior) × 0.5 h. Only high-baseline users at the max rate are affected.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:284` `let percent = Int((requestedRate / baseline * 100.0).rounded())` — rounds up to +0.5%
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:772` reported dose uses `absoluteRate` = baseline × percent/100, not the requested rate
  - `Trio: Trio/Sources/APS/DeviceDataManager.swift:620` Trio drops TBR events where `$0.dose?.unitsPerHour ?? 0 <= Double(settingsManager.pumpSettings.maxBasal)` is false

- Recommendation: Clamp the reported/actual rate to the requested rate (round percent down when the result would exceed the request, or reduce percent by one when absoluteRate > requestedRate), so the emitted unitsPerHour never exceeds what the host asked for.

- Verifier notes:
  - [review:confirm] Verified. percent uses .rounded() (half away from zero), absoluteRate = baseline x percent/100 floored to the 0.01 grid (roundToSupportedBasalRate uses last(where: <=)), and the TBR dose is built from absoluteRate. Trio drops any .tempBasal whose unitsPerHour exceeds pumpSettings.maxBasal. Because of the floor, the overshoot reaches 0.01 only when baseline >= 2 U/h and the request sits within baseline/200 of maxBasal (e.g. baseline 4.0, request 3.02 -> 76% -> 3.04), so it is a narrow high-baseline case; the dropped record leaves oref counting the prior TBR for up to 30 min. Trigger is app-side dosing, unaffected by premise. Partial/medium stands.

**G01-6 Restart mid-bolus loses the completion/cancel correction in Trio** (Partial, impact medium, verified)

The initial bolus record Trio stores carries the programmed amount. The only way it is corrected downward is a later completion or cancel event carrying deliveredUnits (G01-1). If Trio is relaunched or TandemPumpManager is recreated while a bolus runs (or was canceled on the pump), `bolusProgressReport` is nil; the sync path then clears `state.bolusDose` on `.alreadyDeliveredOrInvalid` without querying LastBolusStatus or emitting anything. Trio permanently keeps the programmed amount even if the pump delivered less, over-counting IOB. In LoopKit the mutable dose would be purged instead; in Trio it is frozen at the programmed value.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:70` `internal var bolusProgressReport: TandemDoseProgressReporter?` — in-memory only, not in state rawValue
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:217` `if response.status == .alreadyDeliveredOrInvalid, bolusProgressReport == nil {` clears state, emits nothing
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:226` `guard let progressReport = bolusProgressReport else { return }` — no completion event without reporter

- Recommendation: On reconciling stale bolus state without a reporter, call `queryLastBolusDeliveredVolume(bolusId:)` for the persisted `state.bolusDose.bolusId` and emit a finalized bolus event at the original startDate with the pump-reported delivered amount, so Trio's smaller-amount update fires.

- Verifier notes:
  - [review:confirm] Verified. bolusProgressReport is assigned only in enactBolus (line 588) and never rebuilt from the persisted state.bolusDose, so after a relaunch it is nil. fetchBolusStatus then clears state on .alreadyDeliveredOrInvalid without querying LastBolusStatus or emitting, and the guard at 226 blocks the completion path. Trio keeps the programmed amount; the error only materialises when the pump delivered less (occlusion/empty-cartridge/auto-off abort, in scope under the premise) during the relaunch window, otherwise programmed == delivered. Relaunch is an app trigger, so the premise does not reduce it. Partial/medium stands.

**G01-7 Site change and cartridge change records** (Conforms, impact none, verified)

The fill-cannula wizard emits `.replaceComponent(componentType: .infusionSet)`, which Trio maps to its siteChange event; the change-cartridge wizard emits `.rewind`, which Trio maps to rewind. Both carry `dose: nil`, so neither touches IOB, and `replacePendingEvents: false` is irrelevant to Trio. Each emission is a single event at a fresh `Date.now`, so no (date, type) collision arises. This matches the guide's expectation that component replacement and rewind are surfaced with appropriate types and matches what Trio consumes.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1062` `emitPumpEvents([NewPumpEvent.siteChange(date: date)], replacePendingEvents: false)`
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1071` `emitPumpEvents([NewPumpEvent.cartridgeChange(date: date)], replacePendingEvents: false)`
  - `Trio: Trio/Sources/APS/Storage/PumpHistoryStorage.swift:179` `.replaceComponent(.infusionSet)` -> `makeEventIfNew(timestamp: event.date, type: .siteChange)`
  - `Trio: Trio/Sources/APS/Storage/PumpHistoryStorage.swift:168` `.rewind` -> `makeEventIfNew(timestamp: event.date, type: .rewind)`
  - `Sources/TandemKitUI/ViewModels/Cartridge/TandemKitFillCannulaViewModel.swift:172` UI caller `pumpManager?.recordSiteChange(primeAmount: primeAmount)`

- Recommendation: None required. Optionally emit `.prime` with the cannula fill volume as well, since Trio also stores prime events.

- Verifier notes:
  - [review:confirm] Verified. recordSiteChange emits NewPumpEvent.siteChange (type .replaceComponent(.infusionSet), dose nil) and recordCartridgeChange emits .cartridgeChange (type .rewind, dose nil); Trio maps these to siteChange and rewind. Callers are the fill-cannula and change-cartridge view models. replacePendingEvents:false is irrelevant to Trio. No IOB effect. Conforms/none stands.

**G01-8 Ignored lastReconciliation/replacePendingEvents and dedup-key collisions** (Not applicable, impact low, verified)

Because Trio discards `lastReconciliation` and `replacePendingEvents`, none of TandemKit's reconciliation-timestamp or purge semantics reach the host; equally, TandemKit does not rely on re-reporting mutable doses each sync, so nothing is lost by Trio's append-only model. Trio's dedup key uses the exact `Date` TandemKit passes, and TandemKit stamps each dose with a distinct `Date.now`, so two boluses or TBRs cannot collide in Trio; the one-second ISO8601 truncation in `raw` affects only LoopKit's DoseStore. Trio's `startDateToFilterNewPumpEvents` is not applied to incoming events by either side, so no live emissions are filtered by date.

- Evidence:
  - `Trio: Trio/Sources/APS/DeviceDataManager.swift:608` `lastReconciliation _: Date?,` / `replacePendingEvents _: Bool` — both unused
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1743` `lastReconciliation: self.state.lastReconciliation,` has no host effect in Trio
  - `Trio: Trio/Sources/APS/Storage/PumpHistoryStorage.swift:70` dedup key is full-precision `timeIntervalSinceReferenceDate`, not ISO8601-truncated
  - `Trio: Trio/Sources/APS/DeviceDataManager.swift:666` `startDateToFilterNewPumpEvents` = lastEventDate − 15 min or now − 2 h
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:322` TandemKit reads it only as `hostEventFloor` for backfill, not to gate emissions

- Recommendation: No action for Trio. When a LoopKit-based host is targeted, the raw/syncIdentifier and lastReconciliation findings from earlier points apply instead.

- Verifier notes:
  - [review:confirm] Verified. Trio's delegate ignores lastReconciliation and replacePendingEvents (only a maxBasal filter runs before storePumpEvents), so TandemKit's values at emitPumpEvents:1743 have no host effect. Trio dedups on full-precision Date, and each TandemKit dose is stamped with a fresh Date.now, so distinct doses cannot collide; the finalized TBR re-uses the original startDate, which is the intended dedup. startDateToFilterNewPumpEvents is read only as hostEventFloor for backfill, and Trio does not apply it on ingest. Not-applicable/low stands.

Open questions raised by this point:

- How often does LastBolusStatus return a mismatched bolusId or no response immediately after CancelBolusRequest on real Mobi/t:slim X2 firmware (drives the practical frequency of G01-2)?
- Does Trio's remaining JavaScript oref path (if still selectable) treat an orphan PumpSuspend the same way as the Swift IobHistory port (G01-3)?
- Is skipNeutralTemps enabled by default in current Trio releases, which determines how often the zero-duration cancel path in G01-4 is exercised?
- Does Trio intend to keep skipping deliveredUnits-bearing tempBasal events, or would it accept a host-side change to treat them as truncating records?
- The completeness critic independently re-derived G01-2 (cancel 0 U overwrites Trio's stored bolus) and G01-4 (the percent-100/cancel path never truncates Trio's stored temp basal) from the Trio sources; it rated the truncation gap low on the grounds that the root cause is Trio's dedup design, whereas the G01 reviewer rated it high because the driver's percent-100-as-cancel choice makes it recur on every neutral temp. The driver-side mitigation (emit a truncating temp basal record) is available either way.
### G02. Temp-basal command ordering: the running rate is stopped on the pump before the new one is confirmed; a failed or unanswered SetTempRate/SuspendPumping leaves the driver's record (and DoseStore) describing delivery the pump is not doing, with no self-healing path

Guide section: §3 mutable lifecycle, §10 'bolus during BLE loss' analog (register before you can lose contact; pump is source of truth), §9 item 4/5.

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 1 of 1 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

The 24 audits cover a lost InitiateBolus ack (P12-1) and note the stop-then-fail ordering only as a P23 open question; none audits the temp-basal command as a two-step write whose first step is irreversible. Two app-triggered failure shapes, both unaffected by the premise: (a) StopTempRate succeeds, then SetTempRate gets no response or a bad status (lines 750-761) — the pump is on profile basal but state.basalDose still holds the old TBR, which stays mutable in DoseStore until its estimatedEndDate (up to 30 min) and is later finalized by getActivePumpEvents as if it ran until the next enact (over-count of old rate minus profile); (b) the SetTempRate write reached the pump but its response was lost — the pump runs the new rate while state says old TBR or .basal; fetchBasalStatus has no .tempBasal branch, so the unaccounted TBR is invisible until Loop's next enact stops it at line 705. suspendDelivery has the same shape at 802-816. Exposure is bounded by the next loop cycle when the loop keeps running, but a BLE loss right after the failure extends it to the full TBR duration. No test exercises either shape (StubPumpBluetooth can return nil per request but no test sequences StopTempRate-OK/SetTempRate-nil).

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| G02-1 | Non-conforming | medium | verified | Temp-basal command ordering: the running rate is stopped on the pump before the new one is |

**G02-1 Temp-basal command ordering: the running rate is stopped on the pump before the new one is** (Non-conforming, impact medium, verified)

The 24 audits cover a lost InitiateBolus ack (P12-1) and note the stop-then-fail ordering only as a P23 open question; none audits the temp-basal command as a two-step write whose first step is irreversible. Two app-triggered failure shapes, both unaffected by the premise: (a) StopTempRate succeeds, then SetTempRate gets no response or a bad status (lines 750-761) — the pump is on profile basal but state.basalDose still holds the old TBR, which stays mutable in DoseStore until its estimatedEndDate (up to 30 min) and is later finalized by getActivePumpEvents as if it ran until the next enact (over-count of old rate minus profile); (b) the SetTempRate write reached the pump but its response was lost — the pump runs the new rate while state says old TBR or .basal; fetchBasalStatus has no .tempBasal branch, so the unaccounted TBR is invisible until Loop's next enact stops it at line 705. suspendDelivery has the same shape at 802-816. Exposure is bounded by the next loop cycle when the loop keeps running, but a BLE loss right after the failure extends it to the full TBR duration. No test exercises either shape (StubPumpBluetooth can return nil per request but no test sequences StopTempRate-OK/SetTempRate-nil).

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:706` guard let stopCurrentRate = self.bluetooth.write(StopTempRateRequest()) else { — running TBR is stopped on the pump before anything else
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:750` guard let response = self.bluetooth.write(request) else { — lost SetTempRate response returns an error; state untouched
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:774` self.state.basalDose = dose — the driver's record changes only on a confirmed OK; on failure it still says the old TBR is running
  - `Sources/TandemKit/PumpManager/TandemPeripheralManager.swift:207` let outcome = writeQ.waitForOutcome(timeout: .now() + Self.responseTimeout) — the request was already written when nil comes back
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:141` if activeBasalType != state.basalDose.type { — only .suspend and .basal branches follow; a pump-reported .tempBasal never produces an event or state change

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: StopTempRate is written at 706 before SetTempRate at 750; state.basalDose changes only at 774 on an OK response, so both failure shapes are as described.
### G03. Pump clock vs phone clock and percent-of-profile semantics: the reported TBR value/deliveredUnits and .basal rates come from the phone's schedule at phone time, while the pump applies the percent to its own current segment on its own clock; drift is detected and surfaced but never corrected automatically, never reported via didAdjustPumpClockBy, and pairing does not set the pump time

Guide section: §2 value = programmed amount, §9 item 7, §6 trust boundary.

Overall: **Partial** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 1 of 1 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

P07-4/P11-6/P22-8 note that the TBR value is derived from the app schedule rather than the pump's profileBasalRate, but no audit considers the clock dimension or segment boundaries. Because Tandem temp rates are a percent of the pump's current profile segment, the units actually delivered differ from the reported value whenever (1) a segment boundary falls inside the 30-minute TBR (percent is fixed, profile changes), or (2) the pump's clock/time zone differs from the phone's — after a DST change or travel the pump runs a different segment than the one Loop assumes, for every TBR and for the scheduled-basal overlay itself, until the user acts on the settings warning. On a screenless Mobi the pump clock can only be corrected through this driver, so the misalignment persists for hours if the badge is missed. None of this is reconciled from the pump's own currentBasalRate (fetched at line 699 but unused) and the host is never given didAdjustPumpClockBy when the user does sync. The live dose dates themselves are phone-time (Date.now) so they are unaffected; the error is in the amount, not the timestamp.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| G03-1 | Partial | medium | verified | Pump clock vs phone clock and percent-of-profile semantics: the reported TBR value/deliver |

**G03-1 Pump clock vs phone clock and percent-of-profile semantics: the reported TBR value/deliver** (Partial, impact medium, verified)

P07-4/P11-6/P22-8 note that the TBR value is derived from the app schedule rather than the pump's profileBasalRate, but no audit considers the clock dimension or segment boundaries. Because Tandem temp rates are a percent of the pump's current profile segment, the units actually delivered differ from the reported value whenever (1) a segment boundary falls inside the 30-minute TBR (percent is fixed, profile changes), or (2) the pump's clock/time zone differs from the phone's — after a DST change or travel the pump runs a different segment than the one Loop assumes, for every TBR and for the scheduled-basal overlay itself, until the user acts on the settings warning. On a screenless Mobi the pump clock can only be corrected through this driver, so the misalignment persists for hours if the badge is missed. None of this is reconciled from the pump's own currentBasalRate (fetched at line 699 but unused) and the host is never given didAdjustPumpClockBy when the user does sync. The live dose dates themselves are phone-time (Date.now) so they are unaffected; the error is in the amount, not the timestamp.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:685` let baselineRate = getScheduledBasalRate() — app-side schedule, evaluated once at enact time
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1756` let startOfDay = Calendar.current.startOfDay(for: now) — phone clock and phone time zone
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:749` let request = SetTempRateRequest(minutes: Int(duration.minutes), percent: percent) — pump multiplies its own segment rate by percent
  - `Sources/TandemCore/Common/UnfinalizedDose.swift:190` deliveredUnits: isMutable ? nil : value * (duration / .hours(1)) — a single fixed value across any segment boundary inside the TBR
  - `Sources/TandemKit/PumpManager/TandemPumpManager+SyncBasal.swift:222` let startMinutes = Int((scheduleItem.startTime / 60.0).rounded()) — segments are keyed to pump-local minutes from midnight

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: baseline and percent come from the phone-side schedule at Date.now (685, 1756); SetTempRateRequest carries only minutes and percent (749). The pump's profileBasalRate from CurrentBasalStatusResponse (fetched at 699) is not used.
### G04. A basal-state transition observed while no delegate is attached (the pairing sync, or notifications arriving before the host adopts the manager) is consumed into state and never re-emitted, so a pump-side suspend seen then is permanently missing from the host

Guide section: §6 trust boundary, §10 suspend/resume ('emit a suspend whenever delivery actually stops').

Overall: **Non-conforming** (auditor's own overall: Non-conforming; computed as the most conservative verdict among the surviving findings). 1 of 1 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

P01-3 and P18-5 record that pre-delegate emissions are dropped, but rate it as a lastReconciliation/replay gap and do not follow the consequence through state. Because fetchBasalStatus emits only on a type change and updates state.basalDose in the same step, a dropped suspend is not delayed but lost: every later sync sees .suspend == .suspend and stays silent. The concrete default-configuration scenario is a Mobi that is suspended when TandemKit first syncs it (no cartridge on first setup, or an occlusion/empty-cartridge/auto-off alarm that fired before pairing): the host adopts the manager believing scheduled basal is flowing, overlays basal for the whole suspended window, and then receives a lone .resume from the cartridge wizard (which skipped suspendDelivery because the pump was already suspended). The same holds for a TBR expiry or alarm-suspend delivered as a qualifying event between connect and host adoption after a relaunch. The reservoir path has a pending-flag replay; pump events do not.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| G04-1 | Non-conforming | medium | verified | A basal-state transition observed while no delegate is attached (the pairing sync, or noti |

**G04-1 A basal-state transition observed while no delegate is attached (the pairing sync, or noti** (Non-conforming, impact medium, verified)

P01-3 and P18-5 record that pre-delegate emissions are dropped, but rate it as a lastReconciliation/replay gap and do not follow the consequence through state. Because fetchBasalStatus emits only on a type change and updates state.basalDose in the same step, a dropped suspend is not delayed but lost: every later sync sees .suspend == .suspend and stays silent. The concrete default-configuration scenario is a Mobi that is suspended when TandemKit first syncs it (no cartridge on first setup, or an occlusion/empty-cartridge/auto-off alarm that fired before pairing): the host adopts the manager believing scheduled basal is flowing, overlays basal for the whole suspended window, and then receives a lone .resume from the cartridge wizard (which skipped suspendDelivery because the pump was already suspended). The same holds for a TBR expiry or alarm-suspend delivered as a qualifying event between connect and host adoption after a relaunch. The reservoir path has a pending-flag replay; pump events do not.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1736` self.logger.warning("No pump delegate, not notifying...") — the batch is dropped, not queued
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:141` if activeBasalType != state.basalDose.type { — emission happens only on a transition
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:158` state.basalDose = dose — the transition is consumed even though the emit at 161 was dropped
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:307` flushPendingReservoirReading() — deliverStateMissedByTheDelegate replays state and reservoir only, never pump events
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:421` 'the pairing sync runs before the host adopts the manager' — the driver documents that this window exists

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: emitPumpEvents drops the batch with a warning when no delegate is attached (1736); deliverStateMissedByTheDelegate replays only notifyDelegateStateUpdated and flushPendingReservoirReading (303-308); fetchBasalStatus updates state.basalDose (158) in the same step as the dropped emit, so the transition is consumed.
### G05. Mobi message selection for the delivered-volume read: queryLastBolusDeliveredVolume always sends LastBolusStatusV2Request, never the Mobi-only LastBolusStatusV3Request, and V3Response does not conform to LastBolusStatusAbstractResponse; if Mobi firmware >= 3.5 does not answer V2, every completion finalizes at the programmed amount and every cancel at 0 U

Guide section: §3 finalization with actual deliveredUnits, §10 'pump is the source of truth'.

Overall: **Unsure** (auditor's own overall: Unsure; computed as the most conservative verdict among the surviving findings). 1 of 1 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

P05 lists this only as an open question and no audit examines the Mobi message matrix. Under the premise the Mobi is the only target, so the correctness of the single pump-truth read that every bolus finalization depends on rests on V2 being answered by Mobi firmware. The code cannot settle this (pumpX2 ships both messages and TandemCore has no fixture from Mobi hardware); the V3 response also carries a standard/extended split and an end-reason field that the finalization path would need. If V2 is answered, the point conforms; if not, P05-1/P05-2/P07-1/P23-2 fallbacks become the normal path on every bolus, which would be high. Needs a hardware capture; recorded as unsure with the medium rating the ambiguity warrants.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| G05-1 | Unsure | medium | verified | Mobi message selection for the delivered-volume read: queryLastBolusDeliveredVolume always |

**G05-1 Mobi message selection for the delivered-volume read: queryLastBolusDeliveredVolume always** (Unsure, impact medium, verified)

P05 lists this only as an open question and no audit examines the Mobi message matrix. Under the premise the Mobi is the only target, so the correctness of the single pump-truth read that every bolus finalization depends on rests on V2 being answered by Mobi firmware. The code cannot settle this (pumpX2 ships both messages and TandemCore has no fixture from Mobi hardware); the V3 response also carries a standard/extended split and an end-reason field that the finalization path would need. If V2 is answered, the point conforms; if not, P05-1/P05-2/P07-1/P23-2 fallbacks become the normal path on every bolus, which would be high. Needs a hardware capture; recorded as unsure with the medium rating the ambiguity warrants.

- Evidence:
  - `Sources/TandemCore/Builders/LastBolusRequestBuilder.swift:5` if let apiVersion, apiVersion.greaterThan(KnownApiVersion.apiV2_1.value) { — V2 for every API above 2.1, including Mobi 3.x
  - `Sources/TandemCore/Messages/CurrentStatus/LastBolusStatusV3.swift:12` minApi: .mobiApiV3_5, supportedDevices: .mobiOnly — the Mobi-specific message exists but has no sender
  - `Sources/TandemCore/Messages/CurrentStatus/LastBolusStatusV3.swift:58` public class LastBolusStatusV3Response: Message { — not LastBolusStatusAbstractResponse, so it could not be consumed even if sent
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:522` guard let response = bluetooth.write(request) as? LastBolusStatusAbstractResponse else { ... return nil }
  - `Sources/TandemKit/PumpManager/TandemDoseProgressReporter.swift:33` let delivered = actualDeliveredUnits ?? total — nil becomes full delivery

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: LastBolusRequestBuilder selects only LastBolusStatusRequest or LastBolusStatusV2Request; LastBolusStatusV3Response conforms to Message, not LastBolusStatusAbstractResponse, and queryLastBolusDeliveredVolume casts to the abstract type. Whether Mobi firmware answers V2 cannot be settled from code; unsure stands.
### G06. Deleting the pump manager (prepareForDeactivation) leaves a running mutable temp basal and any in-progress bolus unresolved in the host: no finalization batch, no lastReconciliation, no event

Guide section: §3 report-or-delete, §10 suspend on teardown, §9 item 10.

Overall: **Partial** (auditor's own overall: Partial; computed as the most conservative verdict among the surviving findings). 1 of 1 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

P13-5 and P10-7 correctly rate the absence of a suspend event not_applicable (a Tandem pump keeps delivering after the driver is removed), but P13 leaves the un-finalized TBR as an open question and no audit covers the bolus. The pump will run the TBR to its scheduled end and finish the bolus, so the mutable rows approximate reality, but in Loop they can never be finalized, persisted to HealthKit, or advanced past by pumpEventQueryAfterDate, and the last lastReconciliation stays at the last dose emit. An app-triggered path unaffected by the premise. A final replacePendingEvents:true batch that finalizes both doses at their estimated ends (with the pump-reported bolus volume where reachable) before deactivate() would close it.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| G06-1 | Partial | low | verified | Deleting the pump manager (prepareForDeactivation) leaves a running mutable temp basal and |

**G06-1 Deleting the pump manager (prepareForDeactivation) leaves a running mutable temp basal and** (Partial, impact low, verified)

P13-5 and P10-7 correctly rate the absence of a suspend event not_applicable (a Tandem pump keeps delivering after the driver is removed), but P13 leaves the un-finalized TBR as an open question and no audit covers the bolus. The pump will run the TBR to its scheduled end and finish the bolus, so the mutable rows approximate reality, but in Loop they can never be finalized, persisted to HealthKit, or advanced past by pumpEventQueryAfterDate, and the last lastReconciliation stays at the last dose emit. An app-triggered path unaffected by the premise. A final replacePendingEvents:true batch that finalizes both doses at their estimated ends (with the pump-reported bolus volume where reachable) before deactivate() would close it.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1117` public func prepareForDeactivation(_ completion: @escaping (Error?) -> Void) {
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1119` bluetooth.deactivate() — transport torn down; getActivePumpEvents/emitPumpEvents are not called
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1702` guard state.basalDose.type == .tempBasal else { — the only TBR finalization path, unreachable after deactivation
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:70` internal var bolusProgressReport: TandemDoseProgressReporter? — an in-flight bolus is likewise never finalized
  - `reference: loopkit-trio/DoseStore.swift:706` purgePumpEventObjects(matching: 'mutable == YES') — only a later addPumpEvents call resolves mutable rows; none will come

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: prepareForDeactivation calls bluetooth.deactivate() then notifyDelegateOfDeactivation with no getActivePumpEvents/emitPumpEvents call (1117-1123).
### G07. Control-IQ when enabled (conditional): a pump-reported Control-IQ flip in fetchControlIQStatus sets useControlIQ without finalizing the running Loop temp basal or emitting anything, unlike the app-side configureControlIQMode path which does

Guide section: §3 finalization, §7 pump-initiated delivery changes.

Overall: **Not applicable** (auditor's own overall: Not applicable; computed as the most conservative verdict among the surviving findings). 1 of 1 findings independently reviewed (first-pass reviewers and a lead re-check of every remaining finding)

P08-3 and P20-4 treat Control-IQ as not_applicable/untested and P02-7 notes the dosing guards, but none looks at what happens to the dose already in flight when the flip is observed. Under the default configuration the pump cannot have Control-IQ turned on by anything but TandemKit's flag-gated UI (which goes through configureControlIQMode), so the finding is not applicable by default. If the conditional source is active (Control-IQ enabled on the pump, e.g. carried over from prior Tandem-app use), a running Loop TBR that Control-IQ supersedes stays reported as mutable/running until a later fetchBasalStatus happens to see a basal-type change, and Control-IQ's own basal modulation is never reported (P08-3) — medium under that condition.

| Finding | Verdict | Impact | Verification | Area |
| --- | --- | --- | --- | --- |
| G07-1 | Not applicable | none | verified | Control-IQ when enabled (conditional): a pump-reported Control-IQ flip in fetchControlIQSt |

**G07-1 Control-IQ when enabled (conditional): a pump-reported Control-IQ flip in fetchControlIQSt** (Not applicable, impact none, verified)

P08-3 and P20-4 treat Control-IQ as not_applicable/untested and P02-7 notes the dosing guards, but none looks at what happens to the dose already in flight when the flip is observed. Under the default configuration the pump cannot have Control-IQ turned on by anything but TandemKit's flag-gated UI (which goes through configureControlIQMode), so the finding is not applicable by default. If the conditional source is active (Control-IQ enabled on the pump, e.g. carried over from prior Tandem-app use), a running Loop TBR that Control-IQ supersedes stays reported as mutable/running until a later fetchBasalStatus happens to see a basal-type change, and Control-IQ's own basal modulation is never reported (P08-3) — medium under that condition.

- Evidence:
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:33` if response.getClosedLoopEnabled(), !state.useControlIQ { — flips the dosing guard only
  - `Sources/TandemKit/PumpManager/TandemPumpManager+StateSync.swift:35` state.useControlIQ = true — state.basalDose (a mutable TBR) is untouched
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:1318` if request.enabled, self.state.basalDose.type == .tempBasal { — the app-side enable path stops and finalizes the TBR
  - `Sources/TandemKit/PumpManager/TandemPumpManager.swift:673` guard !state.useControlIQ else { — further enactTempBasal calls are refused, so nothing app-side will finalize the stale TBR
  - `Sources/TandemKit/State/TandemFeatureFlags.swift:38` controlIQSupport ... return false — default off

- Verifier notes:
  - [review:confirm] Lead reviewer re-check: every cited file:line was re-opened and says what the finding claims; the reasoning follows from the code as read.
## Method and limitations

Each of the 24 points was audited by a separate agent that read the guide, the relevant TandemKit sources, the two LoopKit
variants and the tests, and returned findings with file and line evidence. The Trio consumer was audited as its own point
(G01) and independently reviewed. A completeness pass then read all the point audits, the guide and the code looking for
behaviour none of the points had covered; each gap it found was audited by the critic itself and is recorded as a G-point (G02
to G07), single-finding and not independently reviewed. One of its gaps duplicated G01 and was folded into that point's notes.

The first pass was run with Tandem treated as a UI-capable pump, because the driver also lists the t:slim X2 among its targets.
The analysis was then fixed to the screenless-pump premise described in the scope section. Under that premise the three points
whose verdict is driven by the archetype (P02 `lastReconciliation`, P08 `wasProgrammedByPumpUI`, P20 external-dose tests) were
re-audited from scratch, and every other finding that mentioned pump-screen doses, Control-IQ, or the quick-bolus button was
re-rated by an independent reviewer. Re-rated findings show the auditor's original verdict next to the corrected one. The
superseded UI-capable audits of P02, P08 and P20 are summarised below rather than dropped, because the same code would face
those requirements if TandemKit were paired to a pump with a screen.

Verification: every high-impact finding, and every finding that could be affected by the premise, was independently reviewed by
a second agent with a different brief, which re-read the cited code, traced control flow, persistence and reconnect behaviour,
checked the claimed consequence against the LoopKit and Trio sources, and confirmed, refuted or amended the finding. The review
fleet was interrupted twice by an organisation usage cap, so the remaining findings (mostly low and none impact, plus the
re-audited P02, P08 and P20 and the completeness gaps) were re-checked by the lead reviewer rather than by a separate agent: every
cited file and line was re-opened, every claim of absence (no test, no caller, no reader of a field) was confirmed by search, and
four medium ratings on latent identity findings were lowered to low for consistency with the reviewed findings on the same defect.
The verification column in each findings table records the outcome; verifier notes prefixed "Lead reviewer re-check" mark the
findings reviewed this way. No finding was refuted by either stage. Several defects are corroborated by more than one point
reaching the same conclusion from a different direction, which the cross-cutting section calls out.

Other limits:

- Source-only. No pump hardware was used. Firmware behaviour that decides a verdict is listed under open questions.
- Line numbers refer to the audited commit and will drift.
- Loop's `DeviceDataManager` was not on disk; statements about Loop's host behaviour rely on the LoopKit sources and the guide.
  Trio's host code was on disk and was read directly.
- The guide describes `decisionId`, which exists only in `loopkitdev/LoopKit` `next-dev`; the LoopKit fork Trio pins does not
  have it, so P09 is scored as not applicable today with a forward-looking note.

### Superseded UI-capable readings of P02, P08 and P20

Kept for reference only. They do not apply under the premise.

- P02 read `lastReconciliation` as non-conforming because every assignment follows a status poll or a single accepted command and
  none follows a history read, which for a pump with its own dosing history would tell Loop to trust delivery it has not seen.
  Under the Loop-only archetype the status-poll timestamp is the guide's recommended value, so the point is re-scored above.
- P08 read `wasProgrammedByPumpUI` as non-conforming because the live status path cannot see a bolus the app did not start
  (`TandemPumpManager+StateSync.swift` returns early when there is no app-created progress reporter), the history mapper that
  sets the flag has no production caller, and both history flags default off. Under the premise there are no such boluses in
  the default configuration; the reading survives only as a conditional note for the quick-bolus flag and Control-IQ.
- P20 read the external-dose test as non-conforming for the same reason. Under the premise it is not applicable by default.

Reference material used: the guide; `LoopKit/DeviceManager/PumpManager.swift`, `InsulinKit/DoseEntry.swift`,
`InsulinKit/NewPumpEvent.swift`, `InsulinKit/PumpEventType.swift`, `InsulinKit/DoseStore.swift`,
`InsulinKit/InsulinDeliveryStore.swift`, `InsulinKit/InsulinMath.swift` from both LoopKit variants; Trio's
`Trio/Sources/APS/DeviceDataManager.swift`, `Trio/Sources/APS/Storage/PumpHistoryStorage.swift` and
`Trio/Sources/APS/APSManager.swift`; and the TandemKit sources and tests under `Sources/` and `Tests/`.

