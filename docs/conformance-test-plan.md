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
| A3b | Relaunch mid-bolus with delayed delivered volume (#326) | history backfill off; relaunch while delivering; drop every `LastBolusStatus` response, armed before the pump completes (its `bolusChange` triggers the read); sync; persist and relaunch again; restore responses; sync | bolus remains mutable under its original `raw` while delivery is unknown; the pending finalization survives another relaunch and is finalized once from the pump's delivered volume |
| A3c | Relaunch mid-bolus, delivered volume never readable (#448) | history backfill off; relaunch while delivering; drop every `LastBolusStatus`; pump completes; sync; advance past `bolusFinalizationWindow`; sync | held mutable through the window, then finalized under the original `raw` at the programmed amount, never the persisted 0 U |
| A3d | Stopped bolus recovered from history after a relaunch (#448) | shut down after enact; drop every `LastBolusStatus`; the pump stops the bolus short; relaunch; sync | finalized before the window ends from the `BolusCompleted` record backfill reads: the pump's volume and end, not the programmed fallback |
| A4 | BLE drop mid-temp-basal (P11) | enact 45 min TBR; pump drops the link after the `SetTempRate` ack; advance 10 min; reconnect; sync | TBR reported mutable before the drop; after reconnect same `raw`, still mutable, `endDate` = scheduled end; when it expires on the pump it is finalized (not dropped) with `deliveredUnits` rounded to 0.001 U |
| A5 | Lost `SetTempRate` response after the irreversible stop step (#340, G02) | fault `drop_response` scoped to `SetTempRateRequest`; enact TBR | driver does not report a TBR the pump is not running; the pump's `CurrentBasalStatus` on the next sync wins; the previous TBR is finalized at its true end |
| A5b | The link drops in place of the `SetTempRate` response (#340) | fault `disconnect` scoped to `SetTempRateRequest`; enact TBR; sync | the next sync reads `TempRateRequest`, history ends the previous TBR at its completion and adopts the pump's from its activation: one live TBR at the pump's start, rate and duration |
| A5c | Lost `SuspendPumping` response after the temp stop (#340) | enact TBR; fault `drop_response` scoped to `SuspendPumpingRequest`; `suspendDelivery`; sync | the command reads `CurrentBasalStatus` back and succeeds; the `.suspend` is reported before it returns, at the stop, and not again from history; the TBR is finalized at the stop |
| A5d | `SuspendPumping` refused after the temp stop (#340) | enact TBR; fault `error_response` scoped to `SuspendPumpingRequest`; `suspendDelivery`; sync | the command fails after reading `CurrentBasalStatus` back; no `.suspend`; the TBR is finalized at the stop |
| A6 | Link drops inside a multi-fragment response | fault `disconnect` with `after: partial_response, fragments_sent: 1` on `PumpVersionBRequest` during sync | no dose is emitted or duplicated, `lastReconciliation` does not advance, next sync succeeds |
| A7 | Radio off during a running bolus, on again later | `radio_off` after enact; advance past pump completion; `radio_on`; sync | same as A1; additionally `connectionIssue` surfaced and cleared |
| A8 | Link down across completion, then a pump-programmed bolus runs | `radio_off` after enact; pump completes ours; start a bolus on the pump (`source: pump`); advance past our estimate; `radio_on`; sync | the other bolus id delivering finishes ours: finalized from its own `LastBolusStatus` record under the original `raw`, with its own start and end, never the pump bolus's; `bolusDose` cleared; the pump's bolus is not reported as ours |
| A8b | As A8, delivered volume unreadable | as A8 with history backfill off and `drop_response` on every `LastBolusStatus`; sync; restore responses while the pump's bolus still runs; sync | held mutable with its own start while the record cannot be read; finalized once from its record on the retry |
| A9 | App killed mid-bolus, relaunched while a pump-programmed bolus runs | persist `rawValue` and shut down after enact; pump completes ours; start a bolus on the pump; advance; relaunch from the persisted state; sync | as A8, on the relaunch path with no progress reporter |
| A9b | As A9, delivered volume unreadable | as A9 with history backfill off and `drop_response` on every `LastBolusStatus`; sync; restore; sync | as A8b |

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
| B8 | Cancel whose delivered volume is never readable (#448) | history backfill off; `drop_response` on every `CurrentBolusStatus` (no delivering status seen) and `LastBolusStatus`; enact 3 U; cancel after 1 U; sync; advance past the window; sync | held mutable through the window, then finalized with the time delivery ran at the pump's rate, never 0 U |
| B8b | As B8, volume in history | as B8 with history backfill on; sync until finalized | finalized before the window ends from the `BolusCompleted` record, at the pump's volume |

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
| D4 | Delivered-volume read fails | history backfill off; complete a bolus with `drop_response` on every `LastBolusStatus` request; then with a stale `last_bolus` id; then run past the driver's retry window | dose stays mutable while the driver retries the read, then is finalized under the same `raw` at the programmed amount, never at 0 U (#448, G05) |
| D4b | Delivered volume recovered from history | history backfill on; `drop_response` on every `LastBolusStatus`; the pump stops a bolus short; sync until finalized | finalized before the window ends from the `BolusCompleted` record: the pump's volume and end, below the programmed-amount fallback (#448) |
| D5 | Pump clock skew | `/api/clock pump_offset_seconds: 900`; enact and complete a bolus; TBR | dose dates come from the pump's timeline reconciled to phone time; the clock skew temp runs the phone's scheduled rate while the phone's segment lags; a TBR is worked out against the pump's own segment, so it runs and is reported at the rate asked (#343/#335); `didAdjustPumpClockBy` reported (G03) |
| D6 | Auto-reconnect after a pump-side drop syncs and reports (#351) | pump `disconnectPump` while idle; wait for driver auto-reconnect | a sync runs on reconnect and `hasNewPumpEvents` is called with a fresh `lastReconciliation` |
| D7 | Deleting the pump manager with live doses (#350, G06) | bolus running + TBR running; `prepareForDeactivation` / `notifyDelegateOfDeactivation` | a final batch finalizes the TBR (real end), resolves or marks the bolus, emits `.suspend` if delivery stops, and `pumpManagerWillDeactivate` fires |
| D8 | Cartridge change | `POST /api/state/history/append CartridgeFilled` + `reservoir_units` reset; sync | `.replaceComponent(.reservoir)` or `.prime` event as the guide requires (#349) |
| D9 | Basal transition observed while no delegate (G04) | covered by C7 | — |
| D10 | A wizard finds the pump already stopped (#348) | radio off; pump `suspend`; radio on (no sync, #351); `fetchSuspendStatus`; `resumeDelivery`; sync | a `.suspend` reaches the host no later than the check and is closed by the resume; dated at the pump's stop (#333) |
| D11 | Resume over a TBR the driver still holds (#338) | enact TBR; radio off; pump `suspend`; radio on; `resumeDelivery`; sync | the resume's replacing batch does not drop the TBR; Loop holds it finalized, ended no later than the resume |
| D12 | A bolus programmed on the pump (§7, §11 external doses; #452) | history flags on; pump-source bolus in flight; sync until the backfill has read it; enact TBR; pump completes; sync | nothing reported while it runs (a deliberate departure from §9 item 4, #452); then reported once from history, finalized at the pump's amount, `wasProgrammedByPumpUI`, dated at the pump's start; Loop holds it permanent |
| D13 | A 100% extended bolus programmed on the pump (#424) | history flags on; append `BolexActivated`, 30 min, `BolexCompleted`; sync until the backfill has read them | a dose for the extended bolus at `BolexCompleted`'s delivered amount, spanning the two records. faketandem encodes the two records' payloads from jwoglom/faketandem#39 on; before that they decode as zeros, and the marker fires either way |

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

## G. Time changes (§2 dates, §11; #482, #343)

A Tandem pump holds a date and time with no zone and only moves when someone sets it; the driver
decodes pump timestamps with the phone's current UTC offset and takes out the pump clock offset it
last measured, moved by any change in the phone's offset since (`hostDate(forPumpDate:)`), and
`HistoryTimestampReconciler` moves records written before a pump clock change onto the clock now in
force. Every history date goes through both (`HistoryRecordDates`). Each scenario changes one side's clock,
with and without the pump being told, and asserts every dose at the instant the pump delivered it.
Phone and pump start on the same fixed-offset zone; the phone's zone is moved with `PhoneTimeZone`.
Both history flags are on. `TimeChangeConformanceTests`.

| ID | Scenario | Stage | Assert |
|---|---|---|---|
| G1 | The phone changes zone, the pump is not told | phone UTC-4 → UTC-7; sync; app bolus; `radio_off`; pump `suspend`, 10 min, `resume`; pump-programmed bolus; `radio_on`; sync | `pumpClockOffset` +3 h and the time-sync warning shown; the app bolus, the suspend and the resume at their instants; the pump bolus at its instant (#482) |
| G2 | The phone changes zone, the app sets the pump | app temp basal 60 min; `radio_off`; pump-programmed bolus; phone UTC-4 → UTC-7; `radio_on`; `syncPumpTime`; temp basal runs out; pump `suspend`/`resume` | `ChangeTimeDateRequest` sent, pump reads UTC-7, one `TimeChanged`; offset ~0, warning cleared; the bolus logged before the change at its instant; the temp basal finalized at its programmed end and full volume; the later suspend at its instant |
| G3 | The user sets the pump's clock on the pump | `radio_off`; pump `suspend`; pump clock +1 h on the pump; `resume`; pump-programmed bolus; `radio_on`; sync; `syncPumpTime`; app bolus | `pumpClockOffset` +1 h and the warning; the suspend (before the change) and the resume (after it) at their instants; the pump bolus at its instant (#482); after `syncPumpTime` a second `TimeChanged`, offset ~0, warning cleared, the app bolus at its instant |
| G4 | The phone's offset drops an hour between syncs (DST), the pump is not told | a pump-programmed bolus logged 50 min before tracking began, so it decodes past the reporting floor and has ended before the hosts are compared; phone UTC-4 → UTC-5, no sync; pump `suspend` in range; `radio_off`; `resume`; `radio_on`; sync | the suspend from the qualifying event and the resume from history at their instants; the offset moves an hour with the phone's before the sync measures it again; the old bolus is never reported, though it decodes an hour later and moves past the reporting floor (#482) |

## H. Basal from the pump's history (#514, #213, #340)

The pump delivers basal in 5-minute cycles, one `BasalDelivery` (279) record each. With
`basalHistoryReporting` on, the driver compares each closed cycle with what the host counts and
reports a correction where they differ (AGENTS.md "History backfill and dose reporting"). Each
scenario runs faketandem's own basal cycle (`basal_cycle_enabled`), started once the driver is
paired: a 279 every five minutes at the rate and source in force, `DailyBasal` totals,
`ControlIQPcmChange` records, and Control-IQ switched on the pump (`closed_loop_enabled`) or by the
app (`ChangeControlIQSettingsRequest`) at a scripted rate. History backfill and basal reporting are
on. Every scenario that corrects also checks, over its 279s and over each, that Loop's and Trio's
net basal equals the pump's (`PumpTimeline.basalCycles`). Loop's may be 0.025 U off for a cycle a
suspend cuts short: Loop rebuilds the temp basal before a suspend without its `deliveredUnits` and
counts it in 0.05 U steps. `BasalHistoryConformanceTests`.

| ID | Scenario | Assert |
|---|---|---|
| H1 | An app temp runs; Control-IQ switched on by the app for an hour with rates either side of the profile, a 279 and a sync every 5 minutes; Control-IQ off; an app temp | The app temp ends at its completion record; one correction per 279 off the schedule, at its rate and start, the last before the app's next temp; the sync after the switch-off returns with all of them and the hand-back cleared; Loop keeps every correction, Trio stores every one, and both count the pump's basal |
| H2 | The radio is off for 2 h during Control-IQ, then a sync | One ascending batch of corrections at the pump's rates, one per 279 off the schedule; Loop keeps every one, Trio stores every one and its IOB counts the pump's basal; a second pass reports nothing |
| H3 | Relaunch from `rawValue` during Control-IQ | Nothing reported twice; corrections continue |
| H4 | A suspend and resume during Control-IQ | The chunk under way ends at the suspend; no correction in the resume's second; the suspend, resume and corrections in one batch |
| H5 | A5b with reporting on (#340), a 279 every 5 minutes | The pump's temp reported live at its pump start and rate; no 279 differs and nothing is corrected; Trio's IOB runs |
| H6 | App temps, a cancel and a temp replaced within one cycle; an app temp across a profile segment change; a pump clock 11 minutes ahead across its segment change, with the skew compensation temp (D5) | No difference, nothing reported. The replaced temp is never delivered; the pump rescales the temp at the change and the driver cuts it there; the host is never told of the compensation temp |
| H7 | A temp set on the pump's screen | Reported as its chunks close, with `wasProgrammedByPumpUI` |
| H8 | The pump runs a profile off the app's schedule while out of range (#400) | Corrections at the pump's rate for the cycles before the driver writes the schedule back; the cycle the write lands in is residual; the pump runs the schedule from its next 279 |
| H9 | An alarm suspend during an app temp; the temp resumes with delivery | The app's temp ends at the stop; the temp's chunks after the resume reported, the first after the resume's second and the last ending at the app's next temp, and both hosts count them |
| H10 | A CGM dropout during Control-IQ: Control-IQ, then the profile, then Control-IQ | Profile chunks at the app's schedule report nothing; the Control-IQ chunks off it do |

## Execution order

1. Oracles + the delegate journal + `PumpTimeline` + `advanceBoth` (shared infrastructure; the oracles
   and the journal replay have unit tests).
2. Group C (idempotency) — cheapest to stage, establishes the batch-shape assertions.
3. Group B (cancel), then A (interrupt), then D (pump-side), then F (outages), then G (time changes).
4. Timeline diff on every scenario once 1–3 are green in their expected-failure shape.
