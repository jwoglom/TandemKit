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
and listed in `docs/integration-harness.md`.

## Oracles

Assertions are made against what a host would *store*, not just against the delegate call. Two
pure-Swift folds live in `Conformance/Oracles/`:

- **`LoopDoseStoreOracle`** — replays `hasNewPumpEvents` batches with LoopKit's `addPumpEvents`
  semantics (guide §3, §5, §8): `replacePendingEvents == true` purges every stored mutable dose,
  incoming entries match existing doses by `raw`, matched doses are updated and un-deleted,
  `isMutable == false` makes a dose permanent, a 0 U bolus is never stored (LoopKit makes no
  HealthKit sample for it), `lastReconciliation` is set on every call including empty batches.
  Exposes `doses`, `deletedDoses`, `lastReconciliation`, and `iob(at:)` using a simple linear model
  good enough to detect drift.
- **`TrioDoseStoreOracle`** — replays the same batches the way Trio consumes them since
  nightscout/Trio#1300: a temp basal above `maxBasal` dropped, `lastReconciliation` ignored, rows
  matched by `syncIdentifier` then `(timestamp, type, isScheduledBasal)`, a matched mutable row
  updated and a finalized one never changed, `.basal` stored as a zero-length scheduled temp basal
  row, and every mutable row a replacing batch leaves out deleted. `basalSegments(clock:)`,
  `netBasalUnits` and `iob(at:)` read the rows as oref's `IobHistory` does: each temp basal row cut
  at the next row's timestamp, suspends at zero. Used to catch reports that are correct for Loop and
  wrong for Trio.

Both oracles are unit-tested on their own (`Tests/TandemKitTests/DoseOracleTests.swift`), the Loop
oracle against the guide's three transitions (still delivering, finished, never happened), the Trio
oracle one rule at a time.

## Fixtures and helpers

- The journal on `MockPumpManagerDelegate` (`journal`, `JournalEntry`): ordered record of every
  delegate call with a monotonic index and the driver clock's `now`, including `hasNewPumpEvents(events,
  lastReconciliation, replacePendingEvents)`, status updates, `didError`, `willDeactivate`.
- `PumpTimeline` from faketandem's history feed (`GET /api/history`, paged to the end rather than
  the 50-record tail in `/api/state`), the live snapshot and `/api/log`: the pump's own record of
  bolus start/stop and delivered units, temp-rate activation and completion, suspend and resume,
  and alarms with both ends (`alarms_history`). Every scenario ends by diffing the oracle's doses
  against the timeline (guide §11 "diff your reported timeline"; audit P21).

  Its instants and record fields are the ones the harness doc describes under
  [Pump time is local time](integration-harness.md#pump-time-is-local-time) and
  [History records](integration-harness.md#history-records).
- Time: driver on `ManualClock`, pump on `/api/clock` manual mode (`ConformanceClock`).
  `advanceBoth(seconds)` moves both clocks and ticks the simulator so delivery arithmetic and driver
  windows stay in lock-step.
- Delivery: `bolus_rate_units_per_second` is set per scenario: the pump's real speed, or a slower
  rate where a bolus has to keep running; `stall`/`resume`/`abort` stage pump-side interruptions.

## A. Interrupt everything (§10 "bolus during BLE loss", §11; P12, P15, P11; #326, #327, #340, #346, #449, #451)

| ID | Scenario | Stage | Assert |
|---|---|---|---|
| A1 | BLE drop mid-bolus, pump keeps delivering | enact 2 U; after `InitiateBolus` ack, fault `disconnect` on next `CurrentBolusStatus`; pump completes; reconnect; sync | mutable dose registered before the drop; after reconnect exactly one dose with the same `raw`, `isMutable false`, `deliveredUnits` == pump's `last_bolus.delivered`, `endDate` == pump completion time; oracle has one dose; no 0 U guess |
| A2 | Lost `InitiateBolus` acknowledgement (#327) | fault `drop_response` scoped to `InitiateBolusRequest` (state applied, response lost); enact 1 U | the driver reads `CurrentBolusStatus`, finds its bolus id running and reports the enact as succeeded; a mutable bolus registered up front, `deliveryIsUncertain` false; finalized once at the pump's amount; never two doses, never dropped while the pump delivers |
| A2b | The link drops in place of the `InitiateBolus` acknowledgement (#327) | fault `disconnect` scoped to `InitiateBolusRequest` (state applied), and `error_response` on every `CurrentBolusStatusRequest`, so the driver's own reconnect cannot settle the bolus first; enact 1 U; lift the refusal; reconnect; sync | enact reports `.uncertainDelivery`; a mutable bolus at the programmed amount is reported and `deliveryIsUncertain` is true until the sync after the refusal is lifted sees the pump running the bolus id; finalized once at the pump's amount |
| A2c | `InitiateBolus` not applied, and the status read after it lost (#327) | fault `error_response` scoped to `InitiateBolusRequest`, `drop_response` on the next `CurrentBolusStatusRequest`; enact 1 U; sync | enact reports `.uncertainDelivery` and the bolus is counted mutable at its programmed amount; the sync finds nothing running and a last bolus older than its id, releases the permission and finalizes it at 0 U (as a zero-delivery cancel is, #455); `deliveryIsUncertain` clears |
| A3 | Relaunch mid-bolus (#326) | enact 2 U with slow rate; persist `rawValue`; discard manager; construct `TandemPumpManager(rawState:)` with new delegate; pump completes; sync | first batch after relaunch contains the bolus with the original `raw` and `startDate`; finalized from `LastBolusStatus`, not from the estimate |
| A3b | Relaunch mid-bolus with delayed delivered volume (#326) | history backfill off; relaunch while delivering; drop every `LastBolusStatus` response, armed before the pump completes (its `bolusChange` triggers the read); sync; persist and relaunch again; restore responses; sync | bolus remains mutable under its original `raw` while delivery is unknown; the pending finalization survives another relaunch and is finalized once from the pump's delivered volume |
| A3c | Relaunch mid-bolus, delivered volume never readable (#448) | history backfill off; relaunch while delivering; drop every `LastBolusStatus`; pump completes; sync; advance past `bolusFinalizationWindow`; sync | held mutable through the window, then finalized under the original `raw` at the programmed amount, never the persisted 0 U |
| A3d | Stopped bolus recovered from history after a relaunch (#448) | shut down after enact; drop every `LastBolusStatus`; the pump stops the bolus short; relaunch; sync | finalized before the window ends from the `BolusCompleted` record backfill reads: the pump's volume and end, not the programmed fallback |
| A4 | BLE drop mid-temp-basal (P11) | enact 45 min TBR; pump drops the link after the `SetTempRate` ack; advance 10 min; reconnect; sync | TBR reported mutable before the drop; after reconnect same `raw`, still mutable, `endDate` = scheduled end; when it expires on the pump it is finalized (not dropped) with `deliveredUnits` rounded to 0.001 U |
| A5 | Lost `SetTempRate` response after the irreversible stop step (#340, G02) | fault `drop_response` scoped to `SetTempRateRequest`; enact TBR | driver does not report a TBR the pump is not running; the pump's `CurrentBasalStatus` on the next sync wins; the previous TBR is finalized at its true end |
| A5b | The link drops in place of the `SetTempRate` response (#340) | fault `disconnect` scoped to `SetTempRateRequest`; enact TBR; sync | the next sync reads `TempRateRequest`, history ends the previous TBR at its completion and adopts the pump's from its activation: one live TBR at the pump's start, rate and duration |
| A5c | Lost `SuspendPumping` response after the temp stop (#340) | enact TBR; fault `drop_response` scoped to `SuspendPumpingRequest`; `suspendDelivery`; sync | the command reads `CurrentBasalStatus` back and succeeds; the `.suspend` is reported before it returns, at the stop, and not again from history; the TBR is finalized at the stop |
| A5d | `SuspendPumping` refused after the temp stop (#340) | enact TBR; fault `error_response` scoped to `SuspendPumpingRequest`; `suspendDelivery`; sync | the command fails after reading `CurrentBasalStatus` back; no `.suspend`; the TBR is finalized at the stop |
| A5e | Lost `ResumePumping` response (#346, P02-5) | `suspendDelivery`; 10 min; fault `drop_response` scoped to `ResumePumpingRequest`; `resumeDelivery`; sync | the command reads `CurrentBasalStatus` back and succeeds without sending the resume again; the `.resume` is reported before it returns, at the send, and not again from history; the suspend is closed after 10 minutes in Loop, and Trio holds one `PumpResume` |
| A5f | `ResumePumping` refused (#346) | `suspendDelivery`; 10 min; fault `error_response` scoped to `ResumePumpingRequest`; `resumeDelivery`; sync | the command fails after reading `CurrentBasalStatus` back; no `.resume`; the pump and both hosts hold the suspend |
| A6 | Link drops inside a multi-fragment response | fault `disconnect` with `after: partial_response, fragments_sent: 1` on `PumpVersionBRequest` during sync | no dose is emitted or duplicated, `lastReconciliation` does not advance, next sync succeeds |
| A7 | Radio off during a running bolus, on again later | `radio_off` after enact; advance past pump completion; `radio_on`; sync | same as A1; additionally `connectionIssue` surfaced and cleared |
| A8 | Link down across completion, then a pump-programmed bolus runs | `radio_off` after enact; pump completes ours; start a bolus on the pump (`source: pump`); advance past our estimate; `radio_on`; sync | the other bolus id delivering finishes ours: finalized from its own `LastBolusStatus` record under the original `raw`, with its own start and end, never the pump bolus's; `bolusDose` cleared; the pump's bolus is not reported as ours |
| A8b | As A8, delivered volume unreadable | as A8 with history backfill off and `drop_response` on every `LastBolusStatus`; sync; restore responses while the pump's bolus still runs; sync | held mutable with its own start while the record cannot be read; finalized once from its record on the retry |
| A9 | App killed mid-bolus, relaunched while a pump-programmed bolus runs | persist `rawValue` and shut down after enact; pump completes ours; start a bolus on the pump; advance; relaunch from the persisted state; sync | as A8, on the relaunch path with no progress reporter |
| A9b | As A9, delivered volume unreadable | as A9 with history backfill off and `drop_response` on every `LastBolusStatus`; sync; restore; sync | as A8b |

## B. Cancel everything (§3 transitions, §11; P16, P23, P03, P07; #329, #330, #339, #344, #451, #455)

| ID | Scenario | Stage | Assert |
|---|---|---|---|
| B1 | Cancel bolus at three points | enact 3 U; `cancelBolus` immediately / after 1 U / after 2.9 U (advance clock between); after 1 U again with `pump_offset_seconds: 900` | finalized dose `deliveredUnits` == pump's `last_bolus.delivered` (0.0 / ~1.0 / ~2.9), `raw` identical to the mutable report, `value` == 3 U programmed; `endDate` == the pump's stop in phone time, skewed or not (#339) |
| B2 | Cancel with zero delivery | cancel before any delivery (pump `delivered == 0`) | finalized at 0 U under its `raw` in a `replacePendingEvents: true` batch, not withdrawn as §3 has it (P23, #455): Loop stores no 0 U bolus, so its mutable copy stays deleted, the guide's end state; Trio keeps one finalized 0 U row; neither counts any insulin |
| B3 | Cancel temp basal early | enact 60 min TBR; advance 12 min; `enactTempBasal(duration: 0)` | one dose, same `raw`, `isMutable false`, `endDate` == cancel time on the pump, `deliveredUnits` == rate × 12 min rounded; Trio oracle shows a truncation record (#329) |
| B4 | Replace temp basal early | enact TBR A; advance 7 min; enact TBR B | A finalized with real end and delivered units in the same batch that introduces mutable B; B has a new `raw`; no `replacePendingEvents: true` batch omits B while it runs |
| B5 | Neutral / profile-rate temp | enact a 100% temp basal (the profile rate) for 30 min, first with none running, then over a running TBR | no phantom dose; running TBR is finalized, not silently dropped |
| B6 | Cancel while disconnected | fault `disconnect` armed; `cancelBolus` | cancel returns a communication or connection error; bolus stays mutable; after reconnect the pump's state decides (still running → mutable; done → finalized) |
| B7 | Pump-side abort mid-bolus (occlusion) (#333) | enact 3 U; after 1 U `POST /api/state/suspend {reason: occlusion}` | bolus finalized at pump's partial amount with `endDate` at the pump's stop time (not detection time); `.suspend` event dated at the pump's stop time; `.alarm` event for the occlusion (P14) |
| B8 | Cancel whose delivered volume is never readable (#448) | history backfill off; `drop_response` on every `CurrentBolusStatus` (no delivering status seen) and `LastBolusStatus`; enact 3 U; cancel after 1 U; sync; advance past the window; sync | held mutable through the window, then finalized with the time delivery ran at the pump's rate, never 0 U |
| B8b | As B8, volume in history | as B8 with history backfill on; sync until finalized | finalized before the window ends from the `BolusCompleted` record, at the pump's volume |

## C. Idempotency and complete batches (§3 report-or-delete, §5, §6, §11; P04, P06, P17, P18, P01; #330, #332, #342, #347, #352, #449, #450)

| ID | Scenario | Stage | Assert |
|---|---|---|---|
| C1 | Re-report a running bolus many times | enact 5 U at 0.02 U/s; sync 8× while running | each sync re-reports the bolus, mutable, in a `replacePendingEvents: true` batch; every such batch contains it, byte-identical `raw`; oracle holds exactly one dose; `iob(at:)` at a fixed instant stays the same across syncs |
| C2 | Running TBR across many syncs | enact 60 min TBR; sync every 5 min ×6 | each sync re-reports the TBR, mutable, in a `replacePendingEvents: true` batch; same `raw` in every batch; `endDate` stays the scheduled end while mutable; one dose in the oracle |
| C3 | Complete batches with several live doses | bolus running + TBR running; pump `suspend` then `resume` | every `replacePendingEvents: true` batch up to the resume includes both mutable doses; the suspend is appended without purging them; nothing live is dropped by silence |
| C4 | Empty sync advances the trust boundary | no doses; sync twice with the clock advanced 5 min | `hasNewPumpEvents` called each time with an empty batch that does not claim to be complete (`replacePendingEvents: false`), `lastReconciliation` strictly increases |
| C5 | Sync with no answer does not advance | fault `drop_response every` on `CurrentBasalStatusRequest` and friends; sync | `hasNewPumpEvents` not called, or called with unchanged `lastReconciliation` |
| C6 | Relaunch and re-sync | with a finalized bolus and a running TBR, relaunch from `rawValue`; sync | no duplicate of the finalized bolus; TBR continues with the same `raw` |
| C7 | Events before the delegate attaches (#342, #332) | pair and sync; set `delegate = nil`; pump `suspend`; sync; attach delegate; sync | the suspend transition is emitted after attach, not lost |
| C8 | A bolus that outlives the driver's estimate (#347, #330) | enact 1 U at 0.005 U/s; advance past the driver's model, inside the pump's; wait for the estimate to run out; enact a TBR | the TBR is refused (`bolusIsRunning`) and no replacing batch drops the running bolus; once the pump finishes, Loop holds the bolus at the pump's amount |
| C9 | Two markers in one second (#352) | enact TBR; step both clocks to 0.4 s short of its end, the driver's alone 0.5 s on; neutral temp | no batch carries two events under one `raw`; the neutral temp's marker is the only one, so Trio holds no two basal rows in one second |
| C10 | Two markers in one second, across batches (#352) | neutral temp; the driver's clock alone 0.2 s on, TBR; 0.3 s on, cancel | the two markers have their own `raw`, and Loop and Trio store both |
| C11 | Identical boluses in a row (#330) | 1 U at 0.02 U/s three times, a few minutes apart; sync while each runs; sync until each is finalized; again with history dose reporting on | each its own `raw`, re-sent while it runs and finalized once; no other bolus report (none from history); each one dose in Loop and one row in Trio, nothing deleted or purged; both hosts count the pump's total |
| C12 | The same temp basal every cycle (#450, #344) | 2 U/h for 30 min, enacted again every 5 minutes ×4 with a sync between | each enactment its own `raw`; the one it replaces finalized in the same batch and never reported again; only the latest mutable; Loop's temps back to back; both hosts count the pump's temp rates |
| C13 | A temp basal re-sent until it runs out (#450) | 2 U/h for 30 min; sync every 5 min ×5; let it run out; sync until finalized; sync again | one dose throughout, its scheduled end while mutable; finalized once at that end with rate × duration delivered; not reported after; both hosts count it once |
| C14 | A bolus re-sent through many syncs and a relaunch (#330) | 2 U at 0.01 U/s; sync every 15 s ×8, relaunching before the fourth; sync until finalized | one dose throughout, re-sent by every sync; finalized once at the pump's volume; both hosts count it once |
| C15 | Two identical boluses mutable at once (#330, #448) | history backfill off, every `LastBolusStatus` dropped, delivery at the driver's modelled speed; 2 U finishes and is held; a second 2 U runs; sync ×3; it finishes; faults cleared; sync until finalized | every sync re-sends both in one complete batch; the first finalized at its programmed amount when the second is held; each finalized once, one dose in Loop and one row in Trio; both hosts count the pump's total |
| C16 | The first poll after a relaunch (P18-6) | pair and sync; relaunch from `rawValue`; 1 min; `ensureCurrentPumpData`; again | the first poll, inside the 4.5-minute throttle, reaches the pump since the relaunched driver has no link, and hands the host a boundary later than the persisted one; the second, on a live link, is throttled and tells the host nothing |
| C17 | A reservoir read between syncs moves no boundary (#449) | pump raises `remainingInsulin`; the driver reads `InsulinStatus`; advance 3 min; sync | no batch and no reservoir reading reaches the host for the read, `lastReconciliation` stands; the sync's reading reaches the host after its boundary, dated no later |
| C18 | Delivery reads unanswered, reservoir answered (#449) | fault `drop_response every` on `CurrentBolusStatusRequest` and `CurrentBasalStatusRequest`; sync; clear; sync | the first sync returns the boundary it had and reports neither a boundary nor the reservoir reading it took; the next sync moves the boundary and reports its reading behind it |

## D. Pump-side failures and events (§7, §10 suspend/resume and faults; P10, P13, P14, P20, G04, G06; #331, #333, #338, #348, #349, #350, #351, #355, #424, #452, #556)

| ID | Scenario | Stage | Assert |
|---|---|---|---|
| D1 | Pump-initiated suspend and resume | `suspend {reason: user}` (qualifying event fires); sync; advance 10 min; `resume`; sync | `.suspend` dose dated at the pump's suspend time; `.resume` dose; both immutable; suspend duration == 10 min (#331) |
| D2 | Occlusion alarm (#349) | `suspend {reason: occlusion}` | one `.alarm` event with `alarmType` `.occlusion`, dated at the stop; `.suspend`; on `resume {clearAlarms: true}` one `.alarmClear` and `.resume`; Trio stores one `PumpAlarm` |
| D3 | `ErrorResponse` to a control command | fault `error_response` on `InitiateBolusRequest` | `enactBolus` reports an error promptly (not a 30 s timeout); no dose reported; pump has no bolus |
| D4 | Delivered-volume read fails | history backfill off; complete a bolus with `drop_response` on every `LastBolusStatus` request; then with a stale `last_bolus` id; then run past the driver's retry window | dose stays mutable while the driver retries the read, then is finalized under the same `raw` at the programmed amount, never at 0 U (#448, G05) |
| D4b | Delivered volume recovered from history | history backfill on; `drop_response` on every `LastBolusStatus`; the pump stops a bolus short; sync until finalized | finalized before the window ends from the `BolusCompleted` record: the pump's volume and end, below the programmed-amount fallback (#448) |
| D5 | Pump clock skew | `/api/clock pump_offset_seconds: 900`; enact and complete a bolus; TBR; `syncPumpTime` | dose dates come from the pump's timeline reconciled to phone time; the clock skew temp runs the phone's scheduled rate while the phone's segment lags; a TBR is worked out against the pump's own segment, so it runs and is reported at the rate asked (#343/#335); no `didAdjustPumpClockBy` until `syncPumpTime`, then one of −900 s (G03) |
| D6 | Auto-reconnect after a pump-side drop syncs and reports (#351) | pump `disconnectPump` while idle; wait for driver auto-reconnect | a sync runs on reconnect and `hasNewPumpEvents` is called with a fresh `lastReconciliation` |
| D7 | Deleting the pump manager with live doses (#350, G06) | bolus running + TBR running; `delete()` (`deactivateDriver`); the pump finishes both; the next pump manager's first report | one replacing batch before `pumpManagerWantsDeletion`: the TBR finalized at the deletion and its remainder a finalized dose of its own to the scheduled end, the bolus at its programmed amount; no `.suspend`, since the pump keeps delivering; nothing mutable in either host; Loop counts the remainder from its pump event and stores it behind the next manager's boundary |
| D8 | Cartridge change on the pump's screen | `POST /api/state/history/append CartridgeFilled` + `reservoir_units` reset; sync | `.replaceComponent(.reservoir)` or `.prime` event as the guide requires. #349 rated a pump-screen change not applicable, so it stays a strict expected failure; the wizard's `.rewind` is checked |
| D10 | A wizard finds the pump already stopped (#348) | radio off; pump `suspend`; radio on; `fetchSuspendStatus` (its own connect queues the reconnect's sync behind it); `resumeDelivery`; sync | a `.suspend` reaches the host no later than the check and is closed by the resume; dated at the pump's stop (#333) |
| D11 | Resume over a TBR the driver still holds (#338, #348) | enact TBR; radio off; pump `suspend`; radio on; `resumeDelivery`; sync | Loop holds the TBR finalized, ended at the pump's stop; the `.suspend`, dated at the stop, reaches the host before the resume; Loop's store matches the pump's timeline |
| D12 | A bolus programmed on the pump (§7, §11 external doses; #452) | history flags on; pump-source bolus in flight; sync until the backfill has read it; enact TBR; pump completes; sync | nothing reported while it runs (a deliberate departure from §9 item 4, #452); then reported once from history, finalized at the pump's amount, `wasProgrammedByPumpUI`, dated at the pump's start; Loop holds it permanent |
| D13 | A 100% extended bolus programmed on the pump (#424) | history flags on; append `BolexActivated`, 30 min, `BolexCompleted`; sync until the backfill has read them | one dose for the extended bolus under `HistoryLogSyncIdentifier.extendedBolus`, finalized at `BolexCompleted`'s delivered amount, spanning the two records, `wasProgrammedByPumpUI`; no up-front part; Loop holds it permanent and counts it in IOB, Trio stores one bolus row |
| D13b | An extended bolus running when history reads it, stopped part-way (#424, #452) | history flags on; append a `BolusDelivery` record with `extendedDurationRequested` 60, `BolexActivated`; sync until read; enact TBR; 20 min; append `BolexCompleted` with `completionStatus` 0 and a third delivered; sync until read | reported at once, mutable, over the 60 minutes the `BolusDelivery` record programs; the TBR's replacing batch carries it; finalized once, in a replacing batch, at the delivered amount and the stop, under its first report's date; nothing live dropped by a replacing batch; one row in each host |
| D13c | An extended bolus with an up-front part (#424) | history flags on; append `BolusDelivery`, `BolusActivated`; 30 s; `BolusCompleted`, `BolexActivated` in the same second; 30 min; `BolexCompleted`; sync until read | two doses under one `bolusId`: the up-front part under `HistoryLogSyncIdentifier.bolus` at `BolusCompleted`'s amount, the extended part under `extendedBolus` from `BolexActivated` to `BolexCompleted`; both permanent in Loop and two bolus rows in Trio |
| D14 | The fill wizards' primes (#349 P10-5) | `recordTubingFill`; 2 min; `recordSiteChange(primeAmount: 0.3)` | a dose-less `.prime` each, the cannula's with its `.replaceComponent(.infusionSet)`, non-replacing, dated when reported; no dose in Loop; Trio stores two `Prime` rows and one `SiteChange` |
| D15 | A pump with another serial (#349 P14-5) | pair; give `PumpVersionBRequest` another `serialNumber`; `deleteSavedPumpState`; re-pair; sync twice | one "Pump Added" `.replaceComponent(.pump)` for the first pump, then one "Pump Replaced" and one `pumpManagerPumpWasReplaced`; Trio stores each as a `SiteChange` |
| D16 | A bolus Control-IQ gives (§7, §11 external doses; #355 P20-7) | history flags on; Control-IQ on the pump; a bolus with Control-IQ's source, and its `BolusDelivery` (280) records at start and completion, which carry the source; pump completes; sync | reported once from history, finalized at the pump's amount and dated at its start, `automatic` and `wasProgrammedByPumpUI`; Loop holds it permanent and Trio stores it as an SMB |
| D17 | A stop seen only through its alarm (#333 P02-5, P11-4) | enact 1.5 U/h for 60 min; advance 5 min; `drop_fragment` every fragment on `QualifyingEvents`; `suspend {reason: occlusion}`; advance 3 min; clear the fault; raise `alarm` alone; later `resume`; sync | with no sync, the alarm's basal read finds the stop: one `.suspend` and the temp basal's end at the pump's stop, not at the alarm, and the `.alarm`; the resume closes the suspend; one temp basal row in Trio |
| D18 | An occlusion mid-bolus under a running TBR (#556) | enact 1.5 U/h for 60 min; advance 5 min; 1 U bolus at 0.01 U/s; advance 60 s; `drop_fragment` every fragment on `QualifyingEvents`; `suspend {reason: occlusion}`; clear the fault; raise `alarm`, `pumpSuspend` and `bolusChange` as one event; later `resume`; sync | the basal read leaves the stop for history and the bolus read then finalizes the bolus at the pump's volume in a replacing batch that still carries the TBR, mutable: no omission, nothing deleted in Loop; history ends the TBR at the stop and dates the `.suspend` there; Loop holds the TBR permanent to the stop; one temp basal row in Trio |

## E. Rounding and field semantics (§2, §9 item 7; P07, P19, P22) — folded into A–D

Finalized doses in groups A, B and D are also checked for: `value` == programmed amount,
`deliveredUnits` on the pump's increment (0.001 U bolus, 0.001 U/h basal as the driver reports),
`isMutable` semantics, `manuallyEntered == false` for pump-delivered doses (#337),
`automatic` reflecting the activation type, `insulinType` set, and `syncIdentifier` derived from
`raw` (not set independently).

## F. Outages (§7, §10 suspend/resume; P02-5, P11-4, P13-4; #331, #333, #338)

The pump changes delivery while the phone is out of range: `radio_off`, the change, time passes,
`radio_on`, sync. Every scenario runs with the History Backfill flag on, which is what reads the
pump's history; the driver leaves a change it did not command to the next history pass, which
reports it at the pump's time before the sync that saw it completes
(`TandemPumpManager+DeliveryTransitions`). `OutageConformanceTests`.

| ID | Scenario | Stage | Assert |
|---|---|---|---|
| F1 | Stop during an outage, still stopped at reconnect | `radio_off`; advance 5 min; `suspend {reason: occlusion}`; advance 20 min; `radio_on`; sync; then `resume` in range | one `.suspend` dated at the pump's stop, not the reconnect; `basalDose` suspended since the stop; the later `.resume` closes it in Loop; one PumpSuspend and one PumpResume in Trio |
| F2 | Stop and resume both inside an outage | `radio_off`; `suspend`; advance 10 min; `resume`; advance 5 min; `radio_on`; sync | a `.suspend` and a `.resume` at the pump's times, although both status reads show basal running; Loop holds a closed 10 min suspend |
| F3 | App suspend, pump resumed during the outage | `suspendDelivery`; `radio_off`; advance 10 min; `resume`; advance 10 min; `radio_on`; sync | a `.resume` at the pump's restart, never a `.basal` marker in its place (#331); the app's suspend is not reported again from history; Trio's suspend is closed |
| F4 | Temp basal ended by an occlusion during an outage | enact 1.5 U/h for 60 min; advance 5 min; `radio_off`; advance 3 min; `suspend {reason: occlusion}`; advance 20 min; `radio_on`; sync | the temp basal is finalized at the occlusion with delivered units to it, in the same batch as the `.suspend`; one temp basal row in Trio |
| F5 | Stop during an outage, reported by the reconnect alone (#351) | `radio_off`; advance 5 min; `suspend {reason: occlusion}`; advance 20 min; `radio_on`; no sync | the driver's reconnect syncs on its own: one `.suspend` dated at the pump's stop and a fresh `lastReconciliation` reach the host |

## G. Time changes (§2 dates, §11; #482, #343)

A Tandem pump holds a date and time with no zone and only moves when someone sets it; the driver
decodes pump timestamps with the phone's current UTC offset and takes out the pump clock offset it
last measured, moved by any change in the phone's offset since (`hostDate(forPumpDate:)`), and
`HistoryTimestampReconciler` moves records written before a pump clock change onto the clock now in
force. Every history date goes through both (`HistoryRecordDates`). Each scenario changes one side's clock,
with and without the pump being told, and asserts every dose at the instant the pump delivered it.
Phone and pump start on the same fixed-offset zone; the phone's zone is moved with `PhoneTimeZone`.
G6 alone runs on US Eastern's own rules, on the day of its last DST change before the present, whose
offset the driver's decode (the phone's offset now) agrees with. Both history flags are on.
`TimeChangeConformanceTests`.

| ID | Scenario | Stage | Assert |
|---|---|---|---|
| G1 | The phone changes zone, the pump is not told | phone UTC-4 → UTC-7; sync; app bolus; `radio_off`; pump `suspend`, 10 min, `resume`; pump-programmed bolus; `radio_on`; sync | `pumpClockOffset` +3 h and the time-sync warning shown; the app bolus, the suspend and the resume at their instants; the pump bolus at its instant (#482) |
| G2 | The phone changes zone, the app sets the pump | app temp basal 60 min; `radio_off`; pump-programmed bolus; phone UTC-4 → UTC-7; `radio_on`; `syncPumpTime`; temp basal runs out; pump `suspend`/`resume` | `ChangeTimeDateRequest` sent, pump reads UTC-7, one `TimeChanged`, `didAdjustPumpClockBy` −3 h; offset ~0, warning cleared; the bolus logged before the change at its instant; the temp basal finalized at its programmed end and full volume; the later suspend at its instant |
| G3 | The user sets the pump's clock on the pump | `radio_off`; pump `suspend`; pump clock +1 h on the pump; `resume`; pump-programmed bolus; `radio_on`; sync; `syncPumpTime`; app bolus | `pumpClockOffset` +1 h and the warning; the suspend (before the change) and the resume (after it) at their instants; the pump bolus at its instant (#482); after `syncPumpTime` a second `TimeChanged`, one `didAdjustPumpClockBy` (−1 h), offset ~0, warning cleared, the app bolus at its instant |
| G4 | The phone's offset drops an hour between syncs (DST), the pump is not told | a pump-programmed bolus logged 50 min before tracking began, so it decodes past the reporting floor and has ended before the hosts are compared; phone UTC-4 → UTC-5, no sync; pump `suspend` in range; `radio_off`; `resume`; `radio_on`; sync | the suspend from the qualifying event and the resume from history at their instants; the offset moves an hour with the phone's before the sync measures it again; the old bolus is never reported, though it decodes an hour later and moves past the reporting floor (#482) |
| G5 | The phone falls back with an app temp running, then the app sets the pump (the field crash) | app temp basal 84% 30 min; phone UTC-4 → UTC-5; sync; `syncPumpTime`; 3 min; app temp basal 18%; sync | `pumpClockOffset` +1 h then ~0; `lastPumpClockStep` −1 h, none for the phone's change; no pending replacement, the held temp kept; the first temp finished when the second replaced it; no dose ends before it starts or starts ahead of the phone; both hosts match the pump. faketandem re-stamps the running temp's start on the new clock, so the stale `TempRateResponse` stamp is covered by `DeliveryTransitionReportingTests` |
| G6 | The day the phone's clock changes, a profile with a 06:00 segment | phone and pump on `America/New_York` local time at 05:40 on its last change's day; schedule 1.0 U/h, 1.5 U/h from 06:00; basal cycle on; app temp basal 2 U/h 30 min at 05:50; to 06:05; sync | no basal profile mismatch at 05:40 or after 06:00, schedule still synced; the temp cut at exactly 06:00 on the phone's clock, at 2 U/h before and 3 U/h after; no dose ends before it starts; neither oracle holds a duplicate |
| G7 | The pump's date set two days ahead on the pump, then a bolus on the pump | pump clock +2 d on the pump; sync; pump-programmed bolus; sync; `syncPumpTime`; sync | the clock untrusted (past `pumpClockOffsetTrustLimit`) until `syncPumpTime`. Strict expected failures: the bolus reported at its instant and ended by the phone's clock (it is sent starting when history reads it and ending two days ahead); both hosts match the pump once the clock is set |
| G8 | The pump's date set two days behind on the pump, then a bolus on the pump | pump clock −2 d on the pump; sync; pump-programmed bolus; sync; `syncPumpTime`; sync | the clock untrusted; the bolus reported once, at its instant, by the pass after `syncPumpTime`; no dose out of order; both hosts match the pump |
| G9 | The pump's clock restarts at 2008-01-01 while the app is paired, with no record of the change, and the app sets it | a pump-programmed bolus logged two hours before tracking began; pump clock skewed to 2008-01-01 00:03; sync; pump-programmed bolus; sync; `syncPumpTime`; sync | the clock untrusted; the bolus given on the restarted clock reported once at its instant; both hosts match the pump, since Loop stores no dose until it has ended. Strict expected failure: the bolus from before tracking is not reported (the `TimeChanged` record `syncPumpTime` leaves is added to its stamp, 18.9 years, and it is sent starting at the phone's time). M1's defect without a setup |

## H. Basal from the pump's history (#514, #213, #340)

The pump delivers basal in 5-minute cycles, one `BasalDelivery` (279) record each. With
`basalHistoryReporting` on, the driver compares each closed cycle with what the host counts and
reports a correction where they differ (AGENTS.md "History backfill and dose reporting"). Each
scenario runs faketandem's own basal cycle (`basal_cycle_enabled`), started once the driver is
paired: a BasalDelivery record every five minutes at the rate and source in force, `DailyBasal`
totals, `ControlIQPcmChangeHistoryLog` records, and Control-IQ switched on the pump
(`closed_loop_enabled`) or by the app (`ChangeControlIQSettingsRequest`) at a scripted rate. History
backfill and basal reporting are on. Every scenario that corrects also checks, over its
BasalDelivery records and over each, that Loop's and Trio's net basal equals the pump's
(`PumpTimeline.basalCycles`). Loop's may be 0.025 U off for a cycle a suspend cuts short: Loop
rebuilds the temp basal before a suspend without its `deliveredUnits` and counts it in 0.05 U steps.
`BasalHistoryConformanceTests`.

| ID | Scenario | Assert |
|---|---|---|
| H1 | An app temp runs; Control-IQ switched on by the app for an hour with rates either side of the profile, a BasalDelivery record and a sync every 5 minutes; Control-IQ off; an app temp | The app temp ends at its completion record; one correction per BasalDelivery record off the schedule, at its rate and start, the last before the app's next temp; the sync after the switch-off returns with all of them and the hand-back cleared; Loop keeps every correction, Trio stores every one, and both count the pump's basal |
| H2 | The radio is off for 2 h during Control-IQ, then a sync | One ascending batch of corrections at the pump's rates, one per BasalDelivery record off the schedule; Loop keeps every one, Trio stores every one and its IOB counts the pump's basal; a second pass reports nothing |
| H3 | Relaunch from `rawValue` during Control-IQ | Nothing reported twice; corrections continue |
| H4 | A suspend and resume during Control-IQ | The chunk under way ends at the suspend; no correction in the resume's second; the suspend, resume and corrections in one batch |
| H5 | A5b with reporting on (#340), a BasalDelivery record every 5 minutes | The pump's temp reported live at its pump start and rate; no BasalDelivery record differs and nothing is corrected; Trio's IOB runs |
| H6 | App temps, a cancel and a temp replaced within one cycle; an app temp across a profile segment change; a pump clock 11 minutes ahead across its segment change, with the skew compensation temp (D5) | No difference, nothing reported. The replaced temp is never delivered; the pump rescales the temp at the change and the driver cuts it there; the host is never told of the compensation temp |
| H7 | A temp set on the pump's screen | Reported as its chunks close, with `wasProgrammedByPumpUI` |
| H8 | The pump runs a profile off the app's schedule while out of range (#400) | Corrections at the pump's rate for the cycles before the driver writes the schedule back; the cycle the write lands in is residual; the pump runs the schedule from its next BasalDelivery record |
| H9 | An alarm suspend during an app temp; the temp resumes with delivery | The app's temp ends at the stop; the driver reports it again from a second after the resume, ending at the app's next temp, so basal reconciliation corrects nothing, and both hosts count it |
| H10 | A CGM dropout during Control-IQ: Control-IQ, then the profile, then Control-IQ | Profile chunks at the app's schedule report nothing; the Control-IQ chunks off it do |
| H11 | The same app temp enacted a minute into every cycle ×4, a sync between | One dose and one Trio row per enactment; no BasalDelivery record differs and nothing is reported; both hosts count the pump's basal from the first BasalDelivery record the temp ran |

## I. The pump's IOB against the boluses reported (#354 P21-3)

The driver reads the pump's IOB under the Control-IQ opcode and, with Control-IQ off, holds it
against the full amounts of the boluses reported within the active profile's insulin duration,
flagging a reading that stays above them for `UnreportedInsulinOnBoardMonitor.persistence` (AGENTS.md
"Therapy command validation"). faketandem counts bolus insulin alone with Control-IQ off, decaying
linearly over the active profile's insulin duration, and shows a figure that adds basal above and
below the profile with Control-IQ on (faketandem README "Insulin on board"). Each scenario starts
the bolus ledger before the window and compares the driver's reading with the emulator's. The
verdict is read from `unreportedInsulinOnBoard.flagged`. `InsulinOnBoardConformanceTests`.

| ID | Scenario | Assert |
|---|---|---|
| I1 | Control-IQ off on the pump; a 2 U bolus on the pump; a sync, then 10 minutes and an `iobChange` event | `ControlIQIOBRequest` for each, never `NonControlIQIOBRequest`; `latestInsulinOnBoard` the pump's reading each time; the active profile's insulin duration read at the first sync |
| I2 | An app bolus, delivered and finalized; 30 minutes | The ledger counts it at its delivered amount; most of it still on board; nothing flagged |
| I3 | An app bolus, then a 3 U bolus on the pump with History Dose Reporting off; syncs over 30 minutes; then 3½ hours | Not flagged at first sight nor at 15 minutes; flagged at 30 at the pump's reading less the app's bolus; the host never told of the pump's bolus; cleared once both have worn off below the app's bolus |
| I4 | As I3's pump bolus with History Dose Reporting on | Reported from history; the ledger counts it; nothing flagged 30 minutes on, with most of it still on board, although the read before the report saw an excess |
| I5 | A 2 h profile; a 4 U app bolus, 150 minutes, then a 2 U bolus on the pump | The pump no longer counts the app's bolus, nor does the window; the pump's reading flagged in full |
| I6 | The profile's insulin duration shortened, then lengthened, each followed by a `profileChange` event | Each read without a sync; the shorter keeps the longer window until that long after the change; the longer applies at once |
| I7 | Control-IQ on; a bolus on the pump the host never hears of | The pump answers `iobType` 1 and the driver keeps its Swan figure; nothing compared |

## J. Extended boluses (#424)

A Tandem extended bolus programmed off the app is two doses under one `bolusId`: the up-front part,
reported like any pump bolus, and the extended part, reported mutable as soon as history reads its
`BolexActivated` and finalized when it reads its `BolexCompleted` (AGENTS.md "History backfill and
dose reporting"). faketandem delivers no extended bolus, so each scenario appends the records a pump
writes for one, in the order and at the relative times Tandem's cloud export shows (helpers in
`ExtendedBolusHistory.swift`). Every scenario runs with History Backfill and History Dose Reporting
on and ends with both oracles and the complete-batch check. `ExtendedBolusConformanceTests`.

| ID | Scenario | Assert |
|---|---|---|
| J1 | A 100% extended bolus over 60 minutes, a `BolusDelivery` record and a sync every 5 minutes, then its `BolexCompleted` | Every replacing batch carries it unchanged: mutable, under its first report's date, ending at its programmed end; Loop counts one dose and Trio holds one row at every sync; finalized once, at the delivered amount and its end |
| J2 | t:slim X2 firmware that writes no `BolusDelivery` records: a 50% extended bolus with its `BolusRequestedMsg2` | The extended part runs to the programmed end from `BolusRequestedMsg2`'s `duration`; the up-front part reported once, finished. |
| J3 | A suspend 10 minutes into the extended part: `BolexCompleted` with status 0, then the pump's suspend in the same second | Finalized at what it delivered, ending at the stop; one suspend at the stop; one row in each host |
| J4 | A relaunch while the extended part runs | The relaunched driver carries it in its replacing batches under the same identity and date, never reports it anew, and finalizes it once |
| J5 | Deleting the pump manager 10 minutes into a 2-hour extended part | The batch before `pumpManagerWantsDeletion` finalizes it at the deletion at its share of the programmed amount, and reports the rest as a finalized dose of its own to the programmed end; the two sum to the programmed amount; nothing mutable in either host; Loop stores the rest at the next manager's first batch past its end |
| J6 | A `BolexCompleted` never read | Held through the programmed end and `extendedPartFinalizationWindow` after it, then finalized at its programmed amount, ending at its programmed end, in a replacing batch |
| J7 | An app bolus, a quick bolus on the pump, an extended bolus, then an app bolus that still runs when history reads the extended part's end | The app boluses reported live and never again from history, the quick bolus once from history; the batch that finalizes the extended part carries the running app bolus; each finalized once; four rows in Trio |

## K. The pump set up again (#350, #607)

The host deletes the pump manager (`deactivateDriver`) and sets the same pump up again. Each manager is
set up as TandemKitUI does it: paired before the host has it (`startDriver(attachDelegate: false)`), the
pump read (`readDeliveryForSetup()`), the sync `TandemKitSetupCompleteViewModel` runs, the history load
the Load Pump History step chose (`loadHistoryForSetup()`), and only then adopted
(`Driver.adoptByHost()`). Both managers' batches reach
one host, which must hold every dose the pump gave once: the second manager reports what the first one
did under the same `raw` (AGENTS.md "Setup history load"), and the pump's doses while no manager was
attached reach it from the load. faketandem's basal cycle runs throughout, so the app's temps carry
`SetTempRateResponse` records and both managers reconcile basal. Every scenario checks both oracles for
duplicates, nothing live dropped and nothing left mutable, and that both hosts count what each closed
BasalDelivery record delivered, except a cycle a change the app commanded falls in.
`RepairConformanceTests`.

| ID | Scenario | Assert |
|---|---|---|
| K1 | Before any manager the pump boluses and stops for 10 minutes; the first manager loads them. With it the app gives a bolus, a temp it cancels, a suspend and resume, and the pump a bolus and a 175% temp; the app's next temp and a slow bolus run at the deletion. With no manager the pump finishes both, boluses, stops for 10 minutes and runs a 50% temp. The second manager loads | Every report the second manager makes of something before the deletion carries a `raw` the first made, and it does re-report the boluses, both app temps and the first's corrections; no Trio row before the deletion comes from the second; five boluses, each once at the pump's delivered amount under `HistoryLogSyncIdentifier.bolus`, the interim's `wasProgrammedByPumpUI`; three suspends, each closed at its resume and keyed on its record; one correction per cycle of the pump's two temps and no difference logged over the app's; the app's temps under their temp rate ids and the deletion's remainder |
| K2 | The app's temp runs at the deletion; the pump is set up again 3 minutes later and the new manager's temp replaces it | The load reports the temp under its id and nothing is corrected; Loop holds it to the deletion, the remainder cut where the new temp starts, and the new temp |
| K3 | As K2 with a profile segment change in the remainder; set up again once the temp has run out | The deletion reports the remainder as one dose at the higher of 2.0 and the rescaled 1.6 U/hr, under the temp's first part's identity (`tempRatePart`), which the load reports for the part after the change; both hosts hold two rows at 2.0 U/hr and count the pump's basal exactly up to the change and at least, at no more than 2.0 U/hr, after it |
| K4a | The app's suspend stands at the deletion; the pump is resumed on its screen before it is set up again | The load's resume, keyed on its record, closes the suspend the host holds; one suspend in each host |
| K4b | As K4a, the pump still stopped when set up again; the new manager resumes it | The new manager's first reading reports the suspension at detection under its `PumpingSuspended` record, which both hosts already hold, so neither gains a second suspend; its resume closes it |
| K5 | The app's temp runs at the deletion, the pump boluses meanwhile, and the user chooses Do Not Load | Nothing from before the pairing is reported, the interim bolus included; the temp's cycles after the pairing are corrected at the pump's rate, which both hosts take in place of the remainder |

## L. A first connection to a pump with history (#607)

Setup as TandemKitUI runs it: pairing and the reading of the pump, Control-IQ turned off if the
pump runs it, the onboarding writes and a sync, all with no host attached, then the load or not,
then the host adopting the manager, which is handed what was held (AGENTS.md "Setup history
load"). The pump's past is staged on the shared clock before this app's driver exists: on the pump's
screen, and by another app, a second driver with its own key, over Bluetooth before it goes away. The
pump runs its basal cycle unless a scenario says otherwise, and staged changes fall mid-cycle.
History backfill, dose reporting and basal reporting are on. Only this app's host's batches feed the
oracles. `SetupHistoryLoadConformanceTests`.

| ID | Scenario | Assert |
|---|---|---|
| L1 | Six and a half hours before pairing: on the pump's screen boluses (one stopped part-way), a 150% temp and a suspend and resume; another app's bolus, a temp that runs out and one with 40 minutes left; a bolus and a suspend older than six hours; then the load and 45 minutes of syncs | The load completes with its progress at 100%; the four boluses in the window once each under `HistoryLogSyncIdentifier.bolus`, at the pump's start and volume; the suspend in the window at the pump's times, not the older one; the other app's temps under their `tempRateId`, the running one finished at its programmed end; one correction per BasalDelivery record of the pump's own temp and nothing else; nothing reported again by later passes; both hosts count the pump's bolus insulin and net basal over the window. Loop leaves the running temp out of IOB from a boundary past its end until its next save (strict expected failure, AGENTS.md "Deleting the pump manager") |
| L2 | K1's pump, not loaded; then a bolus, a suspend and a resume on the pump | Nothing from before pairing, none of the other app's temps; the running one corrected from the first BasalDelivery record after pairing; the later bolus and suspend reported once at the pump's times; both hosts count the pump's basal from pairing |
| L3 | Six and a half hours of scheduled basal, an alarm raised and cleared and fill records | The load completes at 100%; every BasalDelivery record in the window compared, none differs, nothing reported, no alarm |
| L4 | An empty log; then an app bolus, temp, suspend and resume and a bolus on the pump | The load completes on its first tick; nothing reported; each later dose once, at the pump's times, and never again from history |
| L5 | A log of a few fill and alarm records written on a clock 51 hours behind, which setup sets; then a bolus on the pump | The load completes; nothing reported; one clock adjustment of the time it was behind; the bolus once at its time |
| L6 | A pump bolus, a suspend and another app's running temp, loaded; then an app bolus, a temp replacing the other app's, a suspend and a resume | Each once under its own identity, nothing loaded reported again, no correction; both hosts count the pump's basal but for what they count from a command the pump runs from its next cycle |
| L7 | A bolus on the pump's screen delivering through pairing and the load | Reported once when history reads its completion, at the pump's start and volume; no boundary held for it after |
| L8 | A pump suspended on its screen before pairing and still suspended when paired, resumed from the app | One suspend in each host, closed at the resume: setup's sync reports the suspend under its `PumpingSuspended` record, which the load then takes as reported rather than a second one in a row. Dated from that sync rather than the pump's stop, so both hosts count the schedule over the stop before pairing (strict expected failure) |
| L9 | The history log status unanswered at the load, then answered | The load fails with `historyUnreadable` after `setupHistoryLoadFailureLimit` reads; Try Again loads |
| L10 | An hour of Control-IQ before pairing, still on when paired | Setup turns it off; one automatic correction per Control-IQ BasalDelivery record off the schedule; both hosts count the pump's basal |
| L11 | A pump in use with its clock 12 hours behind, a bolus on its screen four hours before pairing and one an hour before; loaded, then 140 minutes of syncs | One clock adjustment, of the 12 hours; the later bolus, which setup's first 255-record slice holds, once. Strict expected failure: both hosts hold both boluses. The load measures its six hours back from the phone's clock against stamps on the clock setup replaced, so the first slice's oldest record reads as older than the window and the earlier bolus is never read |

## M. A pump out of shelf mode

A Mobi as one came to setup, its whole log staged from sequence 1 at a pump's record counts: used 201
days before on a right clock, with six boluses on its screen (one stopped part-way, one with an
extended part) up to four hours before a `ShelfMode` record; woken 7 h 21 min before pairing with its
clock at 2008-01-01 and no `TimeChanged` or `DateChange` record for the reset, set on the pump to
2020-01-01, and stopped since. Setup sets its clock, 6.9 years forward. The host adopts the manager,
the pump is resumed, the app gives an SMB and is relaunched 52 minutes after pairing, inside the 7
hours the walk backward covers, then syncs for an hour per 255-record slice of the log and gives a
second SMB. M3 to M6 each change one thing about that pump. `SetupHistoryLoadConformanceTests`.

The store prunes records stamped over 90 days before the phone's clock, which takes the record the
walk backward stopped at, so each hour it reads a slice deeper, past the `ShelfMode` record and into
the old boluses. The clock change setup wrote is added to their stamps, which lands them in 2033, and
each reaches the host starting at the phone's time. The assertions that fail are strict expected
failures. M1 to M4's come out when history is no longer read past a `ShelfMode` record, M5's when a
record from before a clock restart is no longer dated by the clock changes after it, and M6's when
the walk backward no longer depends on a record the store prunes.

| ID | Scenario | Assert |
|---|---|---|
| M1 | The pump above, not loaded | Setup sets the pump's clock and the host is told one adjustment, of what it was behind; the app's two boluses once each. Strict expected failures: no `HistoryLogRequest` asks only for records below the `ShelfMode` record; nothing the pump gave before shelf mode reaches either host, and no finalized dose ends after the phone's clock; the bolus ledger holds no entry dated after the phone's clock and no extended part left mutable |
| M2 | The same pump with the load chosen | The load reports no bolus; the same three strict expected failures |
| M3 | Shelved half an hour after its last bolus and paired five minutes after waking, so the first slice setup reads holds the `ShelfMode` record and the boluses before it | Setup's first `HistoryLogRequest` covers the `ShelfMode` record. Strict expected failures: none of the old boluses is among what the host holds once it has adopted the manager and synced (they arrive then, both clock changes added to their stamps); M1's three |
| M4 | The pump resumed on its screen after waking and a bolus on it four hours before pairing, on the clock setup then sets; loaded | That bolus reported once, at the pump's time. Strict expected failures: the load reports it (as in L11 the load stops at its first slice, and the bolus arrives when the walk backward reaches it); M1's three, the hosts holding that bolus and the app's two from the pump's waking |
| M5 | No `ShelfMode` record: the restart of the clock is all that marks the pump's time away | Strict expected failures: nothing the pump gave before the restart reaches either host, and no finalized dose ends after the phone's clock; the bolus ledger as in M1 |
| M6 | No `ShelfMode` record and the clock kept through the 201 days, paired half an hour after the pump is used again | Nothing from before is reported, its dates being right, and both hosts hold the app's two boluses. Strict expected failure: no `HistoryLogRequest` asks only for records from before the pump was stored. Each prune of the record the walk backward stopped at takes it a slice deeper, to sequence 1 |
