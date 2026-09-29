# Dose-reporting conformance test plan

Scenario model for validating TandemKit against LoopKit's
[PumpManager dose reporting guide](https://github.com/loopkitdev/LoopKit/blob/next-dev/Documentation/PumpManagerDoseReporting.md),
using the faketandem integration harness (`docs/integration-harness.md`). Each scenario names the
guide rule it exercises (§n), the audit point it closes (P01–P24 / G01–G07, as quoted in the
`loopkit-conformance` issues) and the GitHub issue it reproduces where one exists.

The tests live in `Tests/TandemKitIntegrationTests/Conformance/` and run against a real
`TandemPumpManager` over the virtual GATT link, driving the emulator at its current `main`
(`FAKETANDEM_DIR=…`) — there is nothing to pin. Scenarios whose driver behaviour is a known open
issue are written with a **strict `XCTExpectFailure`** naming the issue, so the fix flips them to
"unexpected pass" and the marker is removed with the fix. Emulator gaps are wrapped the same way
and listed in `docs/integration-harness.md`; the temp-rate-completion gap that once kept B3, B4 and
B5 from closing their diffs is fixed, and those diffs now stand unwrapped.

## Oracles

Assertions are made against what a host would *store*, not just against the delegate call. Two
pure-Swift folds live in `Conformance/Oracles/`:

- **`LoopDoseStoreOracle`** — replays `hasNewPumpEvents` batches with LoopKit's `addPumpEvents`
  semantics (guide §3, §5, §8): `replacePendingEvents == true` purges every stored mutable dose,
  incoming entries match existing doses by `raw`, matched doses are updated and un-deleted,
  `isMutable == false` makes a dose permanent, `lastReconciliation` is set on every call including
  empty batches. Exposes `doses`, `deletedDoses`, `lastReconciliation`, and `iob(at:)` using a simple
  linear model good enough to detect drift.
- **`TrioDoseStoreOracle`** — replays the same batches the way Trio consumes them (audit G01):
  `lastReconciliation` and `replacePendingEvents` ignored, dedup by `(date, type)`; `raw`,
  `syncIdentifier` and `isMutable` are never read, a re-reported bolus only ever lowers the stored
  amount, and a temp basal carrying `deliveredUnits` is skipped. Used to catch reports that are
  correct for Loop and wrong for Trio.

Both oracles are unit-tested on their own (`Tests/TandemKitTests/DoseOracleTests.swift`), the Loop
oracle against the guide's three transitions (still delivering, finished, never happened).

## Fixtures and helpers

- The journal on `MockPumpManagerDelegate` (`journal`, `JournalEntry`): ordered record of every
  delegate call with a monotonic index and the driver clock's `now`, including `hasNewPumpEvents(events,
  lastReconciliation, replacePendingEvents)`, status updates, `didError`, `willDeactivate`.
- `PumpTimeline` from faketandem's history feed (`GET /api/history`, paged to the end rather than
  the 50-record tail in `/api/state`), the live snapshot and `/api/log`: the pump's own record of
  bolus start/stop and delivered units, temp-rate activation and completion, suspend and resume,
  and alarms with both ends (`alarms_history`). Every scenario ends by diffing the oracle's doses
  against the timeline (guide §11 "diff your reported timeline"; audit P21).

  Every instant in it is reconstructed from the record's wire seconds, which is the arithmetic a
  driver does: `unix = pump_seconds + 1_199_145_600 - pump_timezone_offset_seconds -
  pump_offset_seconds`. Record fields are read under their wire names (`bolusSize`,
  `insulinDelivered`/`insulinRequested`/`completionStatusId`, `durationMilliseconds`,
  `tempRateId`/`timeLeft`, `reasonId`, `alarmId`) and descriptive values — the bolus source, a temp
  rate's absolute rate, a suspend's reason string, an alarm's alert type — from the record's
  `extra`. `completionStatusId` is pumpX2's `BolusStatus`: 3 is the only completion.
- Time: driver on `ManualClock`, pump on `/api/clock` manual mode, in the test process's own time
  zone (`pump_timezone`), because a Tandem pump keeps local time and TandemKit decodes on that
  assumption. `pump_offset_seconds` is left at 0 and means a genuine clock skew when a scenario
  asks for one. `advanceBoth(seconds)` moves both clocks and ticks the simulator so delivery
  arithmetic and driver windows stay in lock-step.
- Delivery: `bolus_rate_units_per_second` is set per scenario: the pump's real speed, or a slower
  rate where a bolus has to keep running; `stall`/`resume`/`abort` stage pump-side interruptions.

## A. Interrupt everything (§10 "bolus during BLE loss", §11; P12, P15, P11; #326, #327, #340, #449, #451)

| ID | Scenario | Stage | Assert |
|---|---|---|---|
| A1 | BLE drop mid-bolus, pump keeps delivering | enact 2 U; after `InitiateBolus` ack, fault `disconnect` on next `CurrentBolusStatus`; pump completes; reconnect; sync | mutable dose registered before the drop; after reconnect exactly one dose with the same `raw`, `isMutable false`, `deliveredUnits` == pump's `last_bolus.delivered`, `endDate` == pump completion time; oracle has one dose; no 0 U guess |
| A2 | Lost `InitiateBolus` acknowledgement (#327) | fault `drop_response` scoped to `InitiateBolusRequest` (state applied, response lost); enact 1 U | enact reports a communication error; a mutable "uncertain" bolus is still reported (register up front); next sync sees the pump's running bolus and confirms it; never two doses, never dropped while the pump delivers |
| A3 | Relaunch mid-bolus (#326) | enact 2 U with slow rate; persist `rawValue`; discard manager; construct `TandemPumpManager(rawState:)` with new delegate; pump completes; sync | first batch after relaunch contains the bolus with the original `raw` and `startDate`; finalized from `LastBolusStatus`, not from the estimate |
| A4 | BLE drop mid-temp-basal (P11) | enact 45 min TBR; pump drops the link after the `SetTempRate` ack; advance 10 min; reconnect; sync | TBR reported mutable before the drop; after reconnect same `raw`, still mutable, `endDate` = scheduled end; when it expires on the pump it is finalized (not dropped) with `deliveredUnits` rounded to 0.001 U |
| A5 | Lost `SetTempRate` response after the irreversible stop step (#340, G02) | fault `drop_response` scoped to `SetTempRateRequest`; enact TBR | driver does not report a TBR the pump is not running; the pump's `CurrentBasalStatus` on the next sync wins; the previous TBR is finalized at its true end |
| A6 | Link drops inside a multi-fragment response | fault `disconnect` with `after: partial_response, fragments_sent: 1` on `PumpVersionBRequest` during sync | no dose is emitted or duplicated, `lastReconciliation` does not advance, next sync succeeds |
| A7 | Radio off during a running bolus, on again later | `radio_off` after enact; advance past pump completion; `radio_on`; sync | same as A1; additionally `connectionIssue` surfaced and cleared |

## B. Cancel everything (§3 transitions, §11; P16, P23, P03, P07; #329, #330, #339, #344, #451, #455)

| ID | Scenario | Stage | Assert |
|---|---|---|---|
| B1 | Cancel bolus at three points | enact 3 U; `cancelBolus` immediately / after 1 U / after 2.9 U (advance clock between) | finalized dose `deliveredUnits` == pump's `last_bolus.delivered` (0.0 / ~1.0 / ~2.9), `raw` identical to the mutable report, `value` == 3 U programmed |
| B2 | Cancel with zero delivery | cancel before any delivery (pump `delivered == 0`) | the dose disappears: next `replacePendingEvents: true` batch omits it; oracle shows it deleted; no 0 U immutable dose (P23). B1's first case expects the opposite; #455 decides |
| B3 | Cancel temp basal early | enact 60 min TBR; advance 12 min; `enactTempBasal(duration: 0)` | one dose, same `raw`, `isMutable false`, `endDate` == cancel time on the pump, `deliveredUnits` == rate × 12 min rounded; Trio oracle shows a truncation record (#329) |
| B4 | Replace temp basal early | enact TBR A; advance 7 min; enact TBR B | A finalized with real end and delivered units in the same batch that introduces mutable B; B has a new `raw`; no `replacePendingEvents: true` batch omits B while it runs |
| B5 | Neutral / profile-rate temp | enact a 100% temp basal (the profile rate) for 30 min, first with none running, then over a running TBR | no phantom dose; running TBR is finalized, not silently dropped |
| B6 | Cancel while disconnected | fault `disconnect` armed; `cancelBolus` | cancel returns a communication or connection error; bolus stays mutable; after reconnect the pump's state decides (still running → mutable; done → finalized) |
| B7 | Pump-side abort mid-bolus (occlusion) (#333) | enact 3 U; after 1 U `POST /api/state/suspend {reason: occlusion}` | bolus finalized at pump's partial amount with `endDate` at the pump's stop time (not detection time); `.suspend` event dated at the pump's stop time; `.alarm` event for the occlusion (P14) |

## C. Idempotency and complete batches (§3 report-or-delete, §5, §6, §11; P04, P06, P17, P18, P01; #330, #332, #342, #347, #352, #449, #450)

| ID | Scenario | Stage | Assert |
|---|---|---|---|
| C1 | Re-report a running bolus many times | enact 5 U at 0.02 U/s; sync 8× while running | every `replacePendingEvents: true` batch contains the bolus, byte-identical `raw`; oracle holds exactly one dose; `iob(at:)` at a fixed instant stays the same across syncs |
| C2 | Running TBR across many syncs | enact 60 min TBR; sync every 5 min ×6 | same `raw` in every batch; `endDate` stays the scheduled end while mutable; one dose in the oracle |
| C3 | Complete batches with several live doses | bolus running + TBR running; pump `suspend` then `resume` | every `replacePendingEvents: true` batch up to the resume includes both mutable doses; the suspend is appended without purging them; nothing live is dropped by silence |
| C4 | Empty sync advances the trust boundary | no doses; sync twice with the clock advanced 5 min | `hasNewPumpEvents` called each time with an empty batch that does not claim to be complete (`replacePendingEvents: false`), `lastReconciliation` strictly increases |
| C5 | Sync with no answer does not advance | fault `drop_response every` on `CurrentBasalStatusRequest` and friends; sync | `hasNewPumpEvents` not called, or called with unchanged `lastReconciliation` |
| C6 | Relaunch and re-sync | with a finalized bolus and a running TBR, relaunch from `rawValue`; sync | no duplicate of the finalized bolus; TBR continues with the same `raw` |
| C7 | Events before the delegate attaches (#342, #332) | pair and sync; set `delegate = nil`; pump `suspend`; sync; attach delegate; sync | the suspend transition is emitted after attach, not lost |
| C8 | A bolus that outlives the driver's estimate (#347, #330) | enact 1 U at 0.005 U/s; advance past the driver's model, inside the pump's; wait for the guard to release; enact a TBR | no replacing batch drops the running bolus (refusing the TBR also satisfies it); once the pump finishes, Loop holds the bolus at the pump's amount |
| C9 | Two markers in one second (#352) | enact TBR; step both clocks to 0.4 s short of its end, the driver's alone 0.5 s on; neutral temp | no batch carries two events under one `raw` |

## D. Pump-side failures and events (§7, §10 suspend/resume and faults; P10, P13, P14, G04, G06; #331, #333, #338, #348, #349, #350, #351, #424, #452)

| ID | Scenario | Stage | Assert |
|---|---|---|---|
| D1 | Pump-initiated suspend and resume | `suspend {reason: user}` (qualifying event fires); sync; advance 10 min; `resume`; sync | `.suspend` dose dated at the pump's suspend time; `.resume` dose; both immutable; suspend duration == 10 min (#331) |
| D2 | Occlusion alarm | `suspend {reason: occlusion}` | `.alarm` event with `alarmType`; `.suspend`; on `resume {clearAlarms: true}` an alarm-clear and `.resume` |
| D3 | `ErrorResponse` to a control command | fault `error_response` on `InitiateBolusRequest` | `enactBolus` reports an error promptly (not a 30 s timeout); no dose reported; pump has no bolus |
| D4 | Delivered-volume read fails | complete a bolus with `drop_response` on every `LastBolusStatus` request; then with a stale `last_bolus` id; then run past the driver's retry window | dose stays mutable while the driver retries the read, then is finalized under the same `raw` from the running estimate, never at 0 U (#448, G05) |
| D5 | Pump clock skew | `/api/clock pump_offset_seconds: 900`; enact and complete a bolus; TBR | dose dates come from the pump's timeline reconciled to phone time; TBR `value`/`deliveredUnits` use the pump's rate, not the phone's schedule segment (#343, #335); `didAdjustPumpClockBy` reported (G03) |
| D6 | Auto-reconnect after a pump-side drop syncs and reports (#351) | pump `disconnectPump` while idle; wait for driver auto-reconnect | a sync runs on reconnect and `hasNewPumpEvents` is called with a fresh `lastReconciliation` |
| D7 | Deleting the pump manager with live doses (#350, G06) | bolus running + TBR running; `prepareForDeactivation` / `notifyDelegateOfDeactivation` | a final batch finalizes the TBR (real end), resolves or marks the bolus, emits `.suspend` if delivery stops, and `pumpManagerWillDeactivate` fires |
| D8 | Cartridge change | `POST /api/state/history/append CartridgeFilled` + `reservoir_units` reset; sync | `.replaceComponent(.reservoir)` or `.prime` event as the guide requires (#349) |
| D9 | Basal transition observed while no delegate (G04) | covered by C7 | — |
| D10 | A wizard finds the pump already stopped (#348) | radio off; pump `suspend`; radio on (no sync, #351); `fetchSuspendStatus`; `resumeDelivery`; sync | a `.suspend` reaches the host no later than the check and is closed by the resume; dated at the pump's stop (#333) |
| D11 | Resume over a TBR the driver still holds (#338) | enact TBR; radio off; pump `suspend`; radio on; `resumeDelivery`; sync | the resume's replacing batch does not drop the TBR; Loop holds it finalized, ended no later than the resume |
| D12 | A bolus programmed on the pump (§7, §11 external doses; #452) | history flags on; pump-source bolus in flight; sync twice; enact TBR; pump completes; sync | reported from history, mutable, `wasProgrammedByPumpUI`, dated at the pump's start; re-reported while it runs; no replacing batch drops it; finalized under the same `raw` at the pump's amount |
| D13 | A 100% extended bolus programmed on the pump (#424) | history flags on; append `BolexActivated`, 30 min, `BolexCompleted`; sync until the backfill has read them | a dose for the extended bolus at `BolexCompleted`'s delivered amount, spanning the two records. faketandem encodes the two records' payloads from jwoglom/faketandem#39 on; before that they decode as zeros, and the marker fires either way |

## E. Rounding and field semantics (§2, §9 item 7; P07, P19, P22) — folded into A–D

Finalized doses in groups A, B and D are also checked for: `value` == programmed amount,
`deliveredUnits` on the pump's increment (0.001 U bolus, 0.001 U/h basal as the driver reports),
`isMutable` semantics, `manuallyEntered == false` for pump-delivered doses (#337),
`automatic` reflecting the activation type, `insulinType` set, and `syncIdentifier` derived from
`raw` (not set independently).

## Execution order

1. Oracles + the delegate journal + `PumpTimeline` + `advanceBoth` (shared infrastructure; the oracles
   and the journal replay have unit tests).
2. Group C (idempotency) — cheapest to stage, establishes the batch-shape assertions.
3. Group B (cancel), then A (interrupt), then D (pump-side).
4. Timeline diff on every scenario once 1–3 are green in their expected-failure shape.
