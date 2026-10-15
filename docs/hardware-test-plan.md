# Hardware test plan

The manual procedure for running TandemKit against a real t:slim X2 or Mobi. The integration
tests ([integration-harness.md](integration-harness.md),
[conformance-test-plan.md](conformance-test-plan.md)) run the driver against faketandem, and
faketandem is pumpX2's model of the pump, not its firmware. This plan checks the same journeys on a
pump. It also answers the questions about the firmware that only a pump can answer (below). Each
step names the automated tests that cover the same behaviour against the emulator. When a pump and
those tests disagree, fix the emulator or the test as well as the driver.

This is a test procedure for contributors. It is not a guide to using TandemKit for anyone's
diabetes care, and it is not medical advice. TandemKit is experimental, and passing this plan does
not make it safe for therapy.

## Before you start

**Never run this plan on a pump that is connected to a person.** Almost every step delivers
insulin, stops delivery or changes basal, and some steps deliberately cause errors.

- Use a pump that is not attached to anyone. Fill its cartridge with saline and leave the tubing
  disconnected, with its end over a container.
- Use a phone and a host app install (Trio or Loop) that no one relies on for therapy. Leave the
  host's closed loop off, except in the steps that turn it on.
- The amounts below are test amounts for a pump that is not attached to anyone. They are not
  doses for a person.
- Logs, screenshots and the TandemKit state dump all contain the pump's serial number and its
  therapy settings. Remove them before you attach anything to a public issue or pull request.

### Setup

- **Pump.** Record the model and its firmware and API versions from TandemKit's Pump Information
  screen. Don't record the serial number. Unless a step says otherwise, set the pump's clock to
  the phone's time and give it a profile with no zero rates.
- **Build.** Record the TandemKit commit and the host app's version.
- **Feature flags** (Settings → View Debug Options → Feature Flags). Leave them at their defaults
  unless a step changes one: History Backfill and History Dose Reporting on; Control-IQ Support,
  Quick Bolus Button Support and History Basal Reporting off.
- **Logs.** Use "Share Tandem pump logs" on TandemKit's settings screen at the end of each run, and
  after any step that fails.
- **Mobi.** The Mobi has no screen. Do steps marked *on the pump* on a t:slim X2. On a Mobi, do
  them with whatever the Mobi offers (its button gives a quick bolus), or mark them not applicable.

## Core journeys

| ID | Do | Expect | Automated |
|---|---|---|---|
| P1 | Pair with a wrong 6-digit code. | The alert "The pump did not accept the pairing code." appears, pairing goes back to the step before the code, and scanning restarts once the alert is dismissed. The app doesn't retry the code on its own. Record whether a Mobi drops the link at that point. | `PairingIntegrationTests`, `PairingFailureTests` |
| P2 | Pair with the right code and finish onboarding. | The pump holds the host's basal schedule, max bolus and max basal. Its clock reads the phone's time, its sounds are the ones chosen during onboarding, and its quick bolus is off. Check each on the pump. | `OnboardingIntegrationTests`, `TrioOnboardingTests` |
| P3 | Take the phone out of range for 10 minutes, then bring it back. | While out of range, the status says the pump can't be reached. Back in range, the driver reconnects and syncs on its own, with nothing done in the app. "Pump Pairing Problem" never appears, even when the edge of range cuts a reconnect short. | `ReconnectIntegrationTests`, conformance D6 and F5 |
| P4 | With the phone out of range, pair the pump to a second phone or to Tandem's app, so it no longer accepts TandemKit's key. Bring TandemKit's phone back. | After three failed reconnects, "Pump Pairing Problem" appears and the driver stops reconnecting on its own. For each failed reconnect, record the error the log gives with "Device disconnected" and the JPAKE round it came after. | `ReconnectIntegrationTests`, `JpakeLinkLossTests` |
| B1 | Give a 0.5 U bolus from the host. | Progress shows while the pump delivers. The host then holds one bolus at the amount the pump's history delivered, dated when the pump started it. | `BolusIntegrationTests`, `TrioBolusTests`, `LoopBolusTests` |
| B2 | Give a 3 U bolus from the host and cancel it after about 1 U. | The pump stops. The host holds the amount the pump's history delivered: not 3 U, and not 0. Record both figures. | conformance B1, `TrioBolusTests` |
| B3 | Start a 3 U bolus, then ask the host for another. | The host refuses the second: "A bolus is still being delivered". Only one bolus runs on the pump. | `BolusInFlightTests`, `DeliveryLimitIntegrationTests` |
| T1 | Set a temp basal from the host at 1.5 times the scheduled rate for 30 minutes. After 10 minutes, cancel it. | The pump runs the temp at the percent the host asked for. The host holds the temp from its start to the cancel, and the pump goes back to its profile. | `TrioTempBasalTests`, conformance B3 |
| S1 | Suspend from the host while a temp basal runs, then resume after 5 minutes. | The pump stops and restarts. The host holds the temp ended at the suspend, then the suspend, then the resume, at the pump's times. | `TrioSuspendTests`, `UnansweredSuspendTests` |
| S2 | *On the pump*, suspend with the phone in range, then resume after 5 minutes. | The host holds a suspend and a resume at the times the pump made them. | conformance D1, `TrioSuspendTests` |
| S3 | Take the phone out of range. *On the pump*, suspend, wait 10 minutes and resume. Wait 5 more minutes, then bring the phone back. | After the first sync, the host holds a 10-minute suspend at the pump's times. The status reads never showed it, so this comes from the pump's history. | conformance F2 |
| R1 | Edit the host's basal schedule to three segments and save. | The pump's profile matches the schedule, and the "Syncing Basal Profiles" status clears. A schedule with more than 16 entries is refused, with nothing written. | `BasalScheduleSyncIntegrationTests`, `TrioBasalScheduleTests` |
| K1 | *On the pump*, set its clock 10 minutes ahead. | After the next sync, the "Pump Time Is Off" alert and status appear. Syncing the time from TandemKit's settings clears both, and the pump then reads the phone's time. | conformance D5, `TimeChangeConformanceTests` |
| K2 | As K1, before syncing the time, with a schedule whose rate changes on the hour. In the 10 minutes after the pump's clock passes the hour, set a temp basal from the host at the pump's new rate. | The host still counts the old rate, so the driver sends the pump an explicit 100% temp. Record whether the pump accepts it. If the pump refuses, the host's command fails. | conformance D5 and H6 |
| W1 | Run TandemKit's cartridge, tubing and cannula wizards. | The host records a cartridge change, a tubing prime and a site change. | `CartridgeProcedureIntegrationTests`, `TrioCartridgeTests`, conformance D14 |
| W2 | Start filling tubing in the wizard, then force-quit the host app partway through. Reopen it and start a cartridge change. | Record whether the pump refuses to enter change-cartridge mode. If it refuses, TandemKit asks for the pump to be removed and offers to back it out. After that, the change can be completed. | `CartridgeProcedureIntegrationTests` |

## Conditional configurations

These configurations change what the pump can do without the host. Control-IQ can be on at the
pump when it is paired, and setup turns it off (C5); the rest depend on feature flags that are off
by default.

| ID | Do | Expect | Automated |
|---|---|---|---|
| Q1 | Quick Bolus Button Support off. Before pairing, turn the pump's quick bolus on in the pump's own settings, then pair (P2). Right after onboarding, press the quick bolus button. While still paired, turn quick bolus on again on the pump, then let the host sync. | Quick bolus is off on the pump as soon as onboarding ends, and pressing the button delivers nothing. After the sync, quick bolus is off again. | `QuickBolusEnforcementTests`, `SyncIntegrationTests`, `OnboardingIntegrationTests` |
| Q2 | Turn on Quick Bolus Button Support. On TandemKit's Quick Bolus Settings screen, turn quick bolus on, then give a quick bolus with the pump's button. | Quick bolus stays on after syncs. Nothing is reported while the bolus runs. Once it finishes, the host holds one bolus at the pump's delivered amount, dated at its start, programmed on the pump and not automatic. | `SyncIntegrationTests`, conformance D12, `TrioBolusTests` |
| Q3 | As Q2, but with History Dose Reporting off. | The host never holds the bolus, and nothing in the app says so. While it runs, the driver's log says that the pump is delivering a bolus the app did not start, and that it will never be reported. With Control-IQ off, once TandemKit has been paired for longer than the pump's insulin duration, the log also warns 30 minutes after the bolus that the pump holds more bolus insulin than the host was told of. | conformance I3, `UnreportedInsulinOnBoardTests` |
| C1 | Turn on Control-IQ Support. With a CGM paired to the pump, set Control-IQ's weight and total daily insulin to test values. Long-press the algorithm status on TandemKit's settings screen to switch to Control-IQ. Set a temp basal from the host, then turn the host's closed loop on for a few loop cycles, then give a manual bolus. | The "Control-IQ On" status appears. The temp basal is refused: "Control-IQ is active on the pump". So is every temp basal and automatic bolus the loop asks for. The manual bolus is delivered. Record what the host does with each refusal. | `DeliveryLimitIntegrationTests` (L5), `TandemPumpManagerControlIQTests` |
| C2 | As C1, with History Dose Reporting on. Wait for Control-IQ to give an automatic bolus. It gives one only when it predicts high glucose, so this step may have to wait. | Nothing is reported while the bolus runs. Once it finishes, the host holds it once, as automatic and programmed on the pump. | conformance D16 |
| C3 | As C1, with History Basal Reporting on. Leave Control-IQ running for 30 minutes. | For each 5-minute cycle that Control-IQ ran off the profile, the host gets a temp basal correction at the pump's rate. Each one arrives some minutes after its cycle ends, never while the cycle runs. | conformance H1, `BasalHistoryConformanceTests` |
| C4 | As C3, then switch back from Control-IQ. | The host's temp basals are accepted again. Syncs wait until history has reported Control-IQ's basal up to the switch. | conformance H1, `TandemPumpManagerControlIQTests` |
| C5 | Before pairing, turn Control-IQ on at the pump (in Tandem's app, or on a t:slim X2's screen), then pair (P2). Repeat with Control-IQ Support on (rerun the initial setup from Debug Options). | Right after pairing, both times, the alert "Control-IQ Is On" says Control-IQ will be turned off so that the host uses its own algorithm. OK is its only button. After OK, onboarding finishes, Control-IQ is off at the pump, and the "Control-IQ On" status never appears. | `TandemPumpManagerOnboardingTests`, `TandemKitScanViewModelTests` |

## What this plan settles

Pump behaviour that the driver relies on but that is unconfirmed on firmware. Record the answer in
the run's notes, and correct AGENTS.md if a pump says otherwise.

- **P1, P2.** `JpakeRound1Framing` against firmware. Also whether a Mobi drops the link to refuse a
  code at key confirmation.
- **P4.** Which error a Mobi's drop gives when it refuses a stored key. The driver counts
  `CBError.peripheralDisconnected` ("The specified device has disconnected from us.") towards the
  handshake failure limit, and not `connectionTimeout` ("The connection has timed out
  unexpectedly."), which a weak signal gives. If a refusal shows as `connectionTimeout`, the limit
  is never reached for it.
- **B2.** Whether `LastBolusStatus` reports a cancelled bolus's delivered volume as soon as the
  cancel is acknowledged, on both pumps.
- **K2.** Whether firmware accepts an explicit 100% temp.
- **Q1.** Whether quick bolus can deliver between pairing and onboarding's first read of the
  pump's settings.
- **W2.** Which open cartridge procedures make the pump refuse change-cartridge mode
  (`CartridgeModeRecovery`).
- **C1.** What the host does when every automatic dose is refused under Control-IQ.

## Runs

Add a row for each run in the pull request that runs it, with an issue for each failed step. Leave
out serial numbers and anything else that identifies a pump or a person.

| Date | Pump | Firmware | API | TandemKit commit | Host | Failed steps |
|---|---|---|---|---|---|---|

No run has been recorded yet.
