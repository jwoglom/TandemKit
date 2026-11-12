# Set temp basal from TandemKit's settings: design spec

**Status: draft. The open questions are resolved ([§13](#13-decisions)); nothing is implemented.**

This spec covers a "Set temp basal" screen in TandemKit's settings: one that sets a temp rate when the
pump runs none, and shows and stops the one it runs when it does. It describes the UI as requested,
with the decisions from review folded in, plus the driver work it needs, how Loop and Trio react to
it, and how OmnipodKit's manual temp basal compares. Mockups are ASCII, about phone width. The
contributor-facing parts are written against `dev` at `d10ff40`.

None of the user-facing text here is dosing advice, and the screen should give none. Whether and
when to use a temp basal is for the person and their care team.

---

## Contents

1. [Findings from review](#1-findings-from-review)
2. [Scope](#2-scope)
3. [What the pump accepts](#3-what-the-pump-accepts)
4. [Entry point on the settings screen](#4-entry-point-on-the-settings-screen)
5. [Screen states](#5-screen-states)
6. [Set temp basal (no temp rate running)](#6-set-temp-basal-no-temp-rate-running)
7. [Active temp rate](#7-active-temp-rate)
8. [Driver changes](#8-driver-changes)
9. [How Loop and Trio treat a temp basal](#9-how-loop-and-trio-treat-a-temp-basal)
10. [Comparison with OmnipodKit](#10-comparison-with-omnipodkit)
11. [Copy](#11-copy)
12. [Tests](#12-tests)
13. [Decisions](#13-decisions)

---

## 1. Findings from review

These came out of writing the first draft. Each one is listed with what was decided.

**F1. Loop and Trio already pause automatic dosing for a manual temp basal.**
- Both read the pump's `basalDeliveryState`. A `.tempBasal` whose `DoseEntry.automatic` is `false`
  stops their loop until it ends ([§9](#9-how-loop-and-trio-treat-a-temp-basal)).
- OmnipodKit's manual temp basal relies on exactly this.
- TandemKit reports every temp it sets as `automatic: true` (`TandemPumpManager.swift:1323`), so
  today a temp set from settings would be overridden at the next loop cycle.
- **Decided (D1):** a temp set from settings is reported as manual (`automatic: false`). The host
  pauses automatic dosing while it runs and starts again when it ends or is stopped, so the user does
  not have to go to open loop first.
  - The set form has no closed-loop card. The requested one would be untrue once the temp is
    reported as manual, and nothing replaces it ([§6.2](#62-no-cards)).
  - The driver has to keep the flag `false` everywhere it re-states the temp
    ([§8.4](#84-carrying-automatic-false)).

**F2. In closed loop the pump nearly always runs the loop's own temp.**
- The loop sets a temp almost every cycle. Under the first rule (the set form only when no temp runs),
  the screen would nearly always open on "Active temp rate", and a closed-loop user would have to stop
  the loop's temp to get past it.
- **Decided (D2):** the loop's own temp counts as no temp ([§5.1](#51-deciding-active)).
  - The screen opens on the set form, and "Set temp rate" stops the loop's temp and sets the user's,
    with no extra warning: the user asked for a new temp.
  - Nothing in TandemKit offers to stop the loop's temp on its own.
  - The same holds for a loop temp set after the screen loaded. Any other temp that appeared fails the
    set and reloads the screen ([§6.9](#69-sending-success-and-failure)).
- A temp set on the pump's screen or by another app still opens "Active temp rate", with Stop.

**F3. A 100% temp rate holds the profile rate.**
- The driver treats 100% as "no change" in the host path and sends nothing.
- **Decided (D13):** from TandemKit's settings, 100% goes out as an explicit temp. Reported manual, it
  keeps Loop or Trio from adjusting basal while it runs, at the rate the pump would run anyway.
- The pump takes an explicit 100% temp and flags it as a temp in its basal status.
- The form starts at 100%, as requested, and "Set temp rate" is enabled there
  ([§6.4](#64-percent-rate)).

**F4. A SwiftUI `Alert` cannot show bold text.**
- **Decided (D5):** the confirmations are plain `Alert`s, and the bold in the original request is
  dropped.

**F5. Duration up to 72 hours rules out the standard countdown picker.**
- `UIDatePicker` in `.countDownTimer` mode stops at 23 h 59 min.
- The spec uses two wheels, hours 0–72 and minutes in 5-minute steps (**D3**,
  [§6.6](#66-duration)).

**F6. Some Mobi firmware takes a temp rate under Control-IQ and some doesn't.**
- pumpX2 has notes for both. `SetTempRateRequest` says "Note that ControlIQ must be off before
  setting a temp rate". `ControlIQCycleHistoryLog.getProgrammedBasalRate()` says "On Control-IQ v7.6
  Mobi firmware this is the profile rate even during a temp rate".
- **Decided (D11):** the screen offers a manual temp rate while Control-IQ runs, and the stop works
  then too.
  - Nothing checks the firmware or works out whether the pump will take it. The driver sends the
    command, and a pump that doesn't allow it refuses, like any other refusal.
  - Nothing is stopped before the set under Control-IQ (the host sets no temps then, and clock skew
    compensation is off), so a refusal leaves the pump as it was.

---

## 2. Scope

**In scope**

- A "Set temp basal" row in the Actions section of TandemKit's settings. While a manual temp runs,
  that row becomes "Stop manual temp basal".
- A screen that reads the pump's temp rate status and shows either:
  - a set form: percent or unit rate, a duration and a confirmation, or
  - the active temp rate, with a Stop button and a confirmation.
- A driver entry point that sets a temp rate at a given percent, and a read of the temp rate status.
- Reporting the temp to the host as manual, and keeping it manual.
- Manual temp rates while the pump's Control-IQ algorithm runs (**D11**). The host's own temps stay
  refused then, as today.
- A "Manual Temp Basal" status highlight in the host while a manual temp runs (**D6**).

**Not in scope**

- Changing how the host's own temp basals are enacted (`enactTempBasal(unitsPerHour:for:)`).
- Restoring a manual temp after a suspend and resume. The pump stops the temp at a suspend, and no
  path restores it. OmnipodKit doesn't restore one either.
- A warning in the "Delete Pump" dialog about a running temp (**D9**: no).
- Hiding the screen on any pump model (**D10**: not gated).

---

## 3. What the pump accepts

| Message | Fields | Notes |
|---|---|---|
| `SetTempRateRequest` (`Sources/TandemCore/Messages/Control/SetTempRate.swift`) | `percent` (UInt16), duration as **milliseconds** (UInt32), built from whole `minutes` | Signed; marked `modifiesInsulinDelivery`, `minApi: .mobiApiV3_5`, `supportedDevices: .mobiOnly` (from pumpX2). Nothing enforces those markings, and this screen doesn't either (D10). |
| `SetTempRateResponse` | `status`, `tempRateId` | `status` 0 is accepted. A refusal carries a status code and no reason. |
| `StopTempRateRequest` / `Response` | `status`, `tempRateId` | |
| `TempRateRequest` → `TempRateResponse` (`CurrentStatus/TempRate.swift`) | `active`, `percentage` (one byte), `startTimeRaw` (seconds since 2008-01-01 on the pump's clock), `duration` (seconds) | The read this screen is built on. pumpX2's `TempRateResponseTest` decodes captured 15- and 30-minute temps as 900 and 1800, and ControlX2 shows `duration / 60` as minutes. |
| `CurrentBasalStatusRequest` → `Response` | `basalType`, `profileBasalRate`, `currentBasalRate` | `profileBasalRate` is the pump's own rate in force, the base of any percent. |

Limits and behaviour the UI has to respect:

- **Percent.** A whole percent, 0–250 (`TandemPumpManager.maximumTempBasalPercent`).
- **Duration.** 15 minutes to 72 hours, in whole minutes (`supportedTempBasalMinutes = 15 ... 72 * 60`).
  The pump refuses anything outside that range. The driver refuses it before sending, because the pump
  would refuse only after any running temp had been stopped.
- **Lowest rate.** The pump refuses a non-zero percent whose share of the profile rate is under its
  0.1 U/hr minimum (status 1 on a Mobi; `minimumTempBasalPercent(baseline:)`). For 0.58 U/hr, 17% is
  refused and 18% is the lowest accepted.
- **Highest rate.** The pump refuses a temp above its max basal limit. The limit is read from the pump
  (`state.maxBasalLimitMilliunits`); until that read, the host's synced `settings.maxTempBasalRate`
  stands in.
- **One at a time.** The pump refuses a `SetTempRate` while a temp runs, so a running temp is stopped
  first.
- **Segment changes.** At each profile segment change the pump rescales a running temp: 130% of
  1.00 U/hr becomes 130% of the next segment's rate. A temp is a percent, not a rate.
- **Five-minute cycles.** A change of rate takes effect at the next `BasalDelivery` record, 0–5 minutes
  after the command (CLAUDE.md, Therapy command validation).
- **Unconfirmed.**
  - What the pump does when a segment change takes a running temp above the max basal limit or
    below 0.1 U/hr.
  - Whether it accepts a temp while suspended.
  - What Control-IQ does while a temp runs, on firmware that takes one (F6).

---

## 4. Entry point on the settings screen

The Actions section today (`TandemKitSettingsView.swift:367-414`) holds "Pump notifications" and the
suspend/resume row. The new row goes between them. It has two states.

```
  No manual temp running                   A manual temp running
  ACTIONS                                  ACTIONS
 ┌──────────────────────────────────┐     ┌──────────────────────────────────┐
 │ Pump notifications          (2) ›│     │ Pump notifications          (2) ›│
 ├──────────────────────────────────┤     ├──────────────────────────────────┤
 │ Set temp basal                  ›│     │ Stop manual temp basal          ›│
 ├──────────────────────────────────┤     │ 130% (1.30U/hr) with 1h 12m      │
 │ Suspend Insulin Delivery         │     │ remaining                        │
 └──────────────────────────────────┘     ├──────────────────────────────────┤
                                          │ Suspend Insulin Delivery         │
                                          └──────────────────────────────────┘
```

### 4.1 "Set temp basal"

- Built with the existing `navigationLink(label:value:action:)` helper, so it gets the same chevron
  (`chevron.right`, 35% opacity) as "Pump notifications".
- Tapping it calls a new openTempBasal closure on `TandemKitSettingsViewModel`. That closure pushes
  a new `TandemScreen.tempBasal` from `TandemUICoordinator`, the same way `.notifications` is pushed.
- It shows whenever no manual temp runs. While the loop's own temp runs, the screen opens on the set
  form; while a temp set on the pump's screen or by another app runs, on "Active temp rate".

### 4.2 "Stop manual temp basal"

**When it shows.** In place of "Set temp basal" while the held dose (`state.basalDose`) is a temp
basal with `automatic == false` whose `estimatedEndDate` is still ahead. Only a temp set from this
screen is manual, so the loop's temps and the pump screen's never switch the row.

**What it shows.**
- The label "Stop manual temp basal", with the same chevron as "Set temp basal".
- A `.footnote` subtext in the secondary colour: "XX% (X.XXU/hr) with XXh XXm remaining".
  - The percent is the held dose's `tempPercent`.
  - The rate is the held dose's `value`. After a segment change that is the part now running, which
    `splitAtSegmentChanges` has already rescaled.
  - The time left is `estimatedEndDate - now`, rounded up to the minute and formatted by
    `DateComponentsFormatter`, `.abbreviated` style, `[.hour, .minute]`: "1h 12m", "45m", "72h".
  - It updates once a minute (`TimelineView(.everyMinute)`, as the connection issue banner does).
**Tapping it** opens the temp basal screen, as "Set temp basal" does. The screen reads the pump and
shows the temp on "Active temp rate" ([§7](#7-active-temp-rate)), where "Stop temp rate" asks to stop
it. While the screen reads, its title is already "Active temp rate": the held dose is a temp the host
did not set.

**While Manual Temp Basal Support is off** the row still shows for a manual temp that runs, with no
chevron, the label in the accent colour as a button, and an `ActivityIndicator` at the trailing edge
while the stop is in flight. Tapping it shows the stop confirmation on the settings screen itself,
with no navigation, as the header's tap does ([§4.4](#44-existing-tap-to-stop-in-the-header)):

```
            ┌────────────────────────────────┐
            │                                │
            │ Stop the active temp rate of   │
            │ 130%?                          │
            │                                │
            ├────────────────────────────────┤
            │        Stop temp rate          │  ← .destructive (red)
            ├────────────────────────────────┤
            │            Cancel              │
            └────────────────────────────────┘
```

- This is the same confirmation as the active view's ([§7.3](#73-stop-temp-rate)), as the
  `SettingsAlertType` case stopManualTempBasal.
- Confirming runs the same stop as the active view, stopTempBasalFromSettings ([§8.3](#83-stop)).
- On success the row goes back to "Set temp basal" with the status update. On failure the existing
  "Could not stop temp rate" sheet shows.

### 4.3 When the rows are disabled

| Pump state (from `TandemKitSettingsViewModel`) | "Set temp basal" | "Stop manual temp basal" |
|---|---|---|
| Normal delivery | Enabled | Enabled |
| Suspended (`isDeliverySuspended`) | Disabled. The pump stops a temp at a suspend, and whether it accepts one while suspended is unconfirmed. | Not shown: the suspend ended the temp. |
| Delivery state unknown (`suspendResumeText == nil`) | Disabled, like the "Insulin delivery status unknown" row | Disabled |
| Control-IQ on (`useControlIQ`) | Enabled (D11). | Enabled. The settings stop is not refused under Control-IQ ([§8.3](#83-stop)). |
| A pump command in flight (`isUpdatingPumpState`) | Disabled, as the suspend/resume row is | Disabled, with its spinner if the stop is the command (flag off) |

### 4.4 Existing tap-to-stop in the header

- Tapping the temp rate in the header (`deliveryStatus` in `TandemKitSettingsView.swift`) opened the
  "Temp Basal Active" alert, and a second "WARNING" alert in closed loop.
- While Manual Temp Basal Support is on, that tap opens the screen instead, so a stop always comes with
  the same one confirmation, and nothing offers to stop the loop's own temp. While the flag is off the
  two alerts stay as they were, so turning the screen off takes nothing away.
- `TandemKitSettingsViewModel.stopTempRate()` stays for those alerts. The row in §4.2 follows the
  same rule: with the flag on it opens the screen, and with it off its own confirmation calls
  `stopManualTempBasal()`, the settings stop.

---

## 5. Screen states

The screen reads the pump each time it appears, and does not rely on the held state alone: a temp set
on the pump's screen or by another app may not be in the held state yet. The read is
`TempRateRequest` plus `CurrentBasalStatusRequest`, through a new driver call
([§8.1](#81-read-the-temp-rate-status)).

```
                       screen appears / pull to refresh / Retry
                                        │
                                        ▼
                             ┌─────────────────────┐
                             │ Loading             │
                             │ TempRate +          │
                             │ CurrentBasalStatus  │
                             └─────────────────────┘
                 no answer ╱        │          │        ╲ blocked
                          ╱         │          │         ╲ (§5.2)
                         ▼          │          │          ▼
            ┌──────────────────┐    │          │   ┌──────────────────┐
            │ Can't reach pump │    │          │   │ Unavailable      │
            │ [Retry]          │    │          │   │ (reason card)    │
            └──────────────────┘    │          │   └──────────────────┘
                                    │          │
                           no temp, │          │ a temp, not the
                      or the loop's │          │ loop's or the
                       or skew temp │          │ skew temp
                                    ▼          ▼
                   ┌────────────────────┐  ┌────────────────────┐
                   │ Set temp basal     │  │ Active temp rate   │
                   │ (set form, §6)     │  │ (§7)               │
                   └────────────────────┘  └────────────────────┘
                          │ Set ▸ confirm           │ Stop ▸ confirm
                          ▼                         ▼
                   ┌────────────────────┐  ┌────────────────────┐
                   │ Setting…           │  │ Stopping…          │
                   │ (controls disabled)│  │ (button spinner)   │
                   └────────────────────┘  └────────────────────┘
                     ok │        │ fail        ok │       │ fail
                        ▼        ▼                ▼       ▼
                     Loading   error sheet     Loading   error sheet
                     (→ §7)    (stay on form)  (→ §6)    (stay on view)
```

### 5.1 Deciding "active"

- The screen shows **Active temp rate** when `TempRateResponse.active` is true, except for two temps
  it treats as none. For those it shows the set form, and a temp set from it replaces them.
  - **The loop's own temp (D2).** The held dose is a temp the host set through `enactTempBasal`, and
    it matches the read: same `tempPercent`, and a start within `transitionMatchTolerance` of the
    pump's. The driver records which held temp that is ([§8.1](#81-read-the-temp-rate-status)).
    `automatic == true` alone is not enough: history adopts a temp another app set over Bluetooth as
    automatic (`TandemPumpManager+DeliveryTransitions.swift:597`).
  - **The driver's clock skew compensation temp** (`skewCompensationTemp != nil`, CLAUDE.md Therapy
    command validation). It stands in for the profile while the pump's clock is skewed, and the host is
    never told of it.
- Every other temp opens Active temp rate: one set from this screen, on the pump's screen, or by
  another app.
- A temp that runs out while the screen is open: a timer at the end the read gives
  ([§7.2](#72-where-each-value-comes-from)) reloads the screen.

### 5.2 Blocked states

- **Suspended** (the read's `basalType == .suspend`) replaces the form with "Insulin delivery is
  suspended. Resume delivery before setting a temp basal."
- **Everything else the driver refuses** reaches the user as its refusal when they press Set or Stop,
  in the error sheet: a running bolus, an untrusted pump clock, a profile never synced or whose update
  failed, a 0 U/hr profile. Each already has a description and a recovery suggestion, and the driver
  checks them again at the command anyway. A 0% temp skips the last four, as the host path does
  (CLAUDE.md: "A zero temp basal is always allowed").
- Control-IQ blocks nothing here (D11).

---

## 6. Set temp basal (no temp rate running)

Also shown while the loop's own temp or the clock-skew temp runs ([§5.1](#51-deciding-active)).

### 6.1 Layout

Percent tab:

```
┌──────────────────────────────────────────┐
│ ‹ Tandem Mobi                            │
│                                          │
│ Set temp basal                           │
│                                          │
│  ┌──────────────────┬─────────────────┐  │
│  │▐  Percent rate  ▌│    Unit rate    │  │
│  └──────────────────┴─────────────────┘  │
│                                          │
│ Rate                                     │
│ ┌──────────────────────────────────────┐ │
│ │                                      │ │
│ │   (−)         100%           (+)     │ │
│ │                                      │ │
│ │           of profile basal           │ │
│ └──────────────────────────────────────┘ │
│                                          │
│ Duration                                 │
│ ┌──────────────────────────────────────┐ │
│ │       0 hr              30 min     ⌄ │ │
│ └──────────────────────────────────────┘ │
│                                          │
│ ──────────────────────────────────────── │
│                                          │
│ Effective basal rates                    │
│ ┌──────────────────────────────────────┐ │
│ │ Now – 2:30 PM              1.00 U/hr │ │
│ └──────────────────────────────────────┘ │
│                                          │
│ ┌──────────────────────────────────────┐ │
│ │           Set temp rate              │ │
│ └──────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

- Navigation title "Set temp basal" (large).
- The view is a `List` in `InsetGroupedListStyle`, like the settings screen.
- The primary button sits below the list: `ContinueButton`, which is `ActionButtonStyle(.primary)`
  with a spinner while `loading`.

### 6.2 No cards

The set form shows no warning or notice card, in any loop mode or under Control-IQ (D1, D11).

- The closed-loop card first requested ("…You need to move to open loop before setting a temp basal,
  or it will be overridden in the next loop cycle.") would be untrue once the temp is reported as
  manual (D1).
- Nothing replaces it. While a manual temp runs, the host says its loop is paused, and TandemKit's
  "Manual Temp Basal" status highlight shows ([§8.5](#85-status-highlight)).

### 6.3 Percent rate / Unit rate

- A segmented `Picker` with "Percent rate" (the default) and "Unit rate".
- Both tabs edit **one value**, the whole percent that will be sent. The unit view shows that percent
  as a rate and turns what is typed into a percent ([§6.5](#65-unit-rate)). Switching tabs never
  changes the value.
- The chosen tab may be remembered per user; the value itself is not.

### 6.4 Percent rate

**The value**
- Large, centred text, "100%".
- Under it, "of profile basal". The temp's rate in U/hr is in the effective basal rates
  ([§6.7](#67-effective-basal-rates)).

**Typing**
- Tapping the number opens a text field with the number pad.
- The value is checked as typed. One outside the valid set (below) shows in
  `guidanceColors.critical` and disables "Set temp rate". There is no subtitle under the section.
- A typed value is never clamped or rounded silently. If the user typed 300, the screen does not
  change it to 250 for them.

**Stepping**
- (−) and (+) go to the next multiple of 10 below or above, so 95 + → 100 and 100 + → 110.
- Within the valid set:
  - (+) from 0 goes to the lowest valid non-zero value (10%, or the minimum, whichever is higher).
  - (−) from the minimum goes to 0.
  - (−) never steps past the minimum: with an 18% minimum, 20 − → 18 − → 0.
- Each button is disabled at its end of the range.

**The valid set**

```
valid = { 0 }  ∪  [ pMin , pMax ]

pMin = max over the profile rates r in force during the duration of
         minimumTempBasalPercent(baseline: r)        (pump's 0.1 U/hr minimum)
pMax = min( 250,
            min over those r of floor(maxBasalLimit / r × 100) )
```

- "The profile rates in force during the duration" is `profileBasalRate` now, plus each
  `pumpSegmentChanges(after: now, through: now + duration)` rate.
- Working the bounds out over the whole duration is the conservative choice. What the pump does when
  a segment change takes a temp past its limits is unconfirmed ([§3](#3-what-the-pump-accepts)).
- Changing the duration can therefore move the bounds. A value that falls outside them turns red,
  and is not clamped.

**100%** holds the profile rate (F3, D13), and can be set like any other value.
- 100% stays the starting value as requested. It is the user's current rate, so nothing is preset.

### 6.5 Unit rate

```
│ RATE                                     │
│ ┌──────────────────────────────────────┐ │
│ │                                      │ │
│ │   (−)       1.30 U/hr        (+)     │ │
│ │                                      │ │
│ │     130% of the 1.00 U/hr profile    │ │
│ │     basal rate                       │ │
│ └──────────────────────────────────────┘ │
```

- **The value** shown is `profileBasalRate × percent / 100`, rounded to two decimals. The pump's own
  rounding is unknown; its read-back is checked to one 0.01 U/hr step (`tempBasalReadbackMatches`).
- **Stepping.** (−) and (+) move the underlying percent by 10, under the same rules as the percent
  tab. One step is therefore 10% of the profile rate (0.10 U/hr at a 1.00 U/hr profile), as requested.
- **Typing.**
  - Tapping the number opens a decimal-pad field.
  - A typed rate becomes the nearest whole percent: `round(u / profileBasalRate × 100)`.
  - That percent's rate is then shown in place of what was typed, with the percent under it. For
    example, 1.05 at a 0.85 U/hr profile becomes 124%, shown as 1.05 U/hr.
  - If the nearest percent falls outside the valid set, the value turns red and the field keeps what
    was typed.
- **The highest rate** is the highest valid percent of `profileBasalRate`: 250% of the profile, or less if the pump's max
  basal limit is lower.
- **Segment changes.** A temp crossing one runs at a different rate after it, which
  [§6.7](#67-effective-basal-rates) covers.

### 6.6 Duration

The pump takes whole minutes from 15 minutes to 72 hours. `UIDatePicker`'s countdown mode stops at
23 h 59 min, so the duration is a row that expands into two wheel `Picker`s, as Apple's Timer and
Health apps do.

```
│ Duration                                 │
│ ┌──────────────────────────────────────┐ │
│ │       1 hr              30 min     ⌃ │ │
│ ├──────────────────────────────────────┤ │
│ │           0   hours      25   min    │ │
│ │       ▶   1   hours      30   min    │ │
│ │           2   hours      35   min    │ │
│ └──────────────────────────────────────┘ │
```

- **Hours wheel:** 0–72.
- **Minutes wheel:** 00–55 in 5-minute steps (**D3**). Every value it offers is a whole number of
  minutes, which is all the pump asks.
- **Out of range** (0 h with under 15 min, or 72 h with any minutes) shows the collapsed row's value in
  `guidanceColors.critical` and disables "Set temp rate". The wheels are not moved for the user, and
  there is no subtitle under the section.
- **Default:** 30 minutes (**D4**), as in OmnipodKit's entry view and in the hosts' own temps.
- **Collapsed row:** the wheels' selected hours and minutes, "X hr" and "Y min", each centred over its
  wheel and both shown even when zero, with no "Duration" label: the section header says it.

### 6.7 Effective basal rates

Under the duration, past a divider, an "Effective basal rates" section lists the rate the temp runs
at from now to its end, one row per rate:

```
│ ──────────────────────────────────────── │
│                                          │
│ Effective basal rates                    │
│ ┌──────────────────────────────────────┐ │
│ │ Now – 2:00 PM              1.30 U/hr │ │
│ ├──────────────────────────────────────┤ │
│ │ 2:00 PM – 2:40 PM          1.04 U/hr │ │
│ └──────────────────────────────────────┘ │
```

- The first row starts "Now"; the last ends at now plus the duration.
- The pump rescales a temp at each profile segment change, so each change inside the duration
  (`pumpSegmentChanges(after:through:)`, on the pump's clock) starts a row at `percent` of the new
  profile rate (`ManualTempBasalForm.effectiveRates`). A change that leaves the rate on the pump's
  0.01 U/hr grid as it was, as every change does at 0%, starts none.
- A time not on today's date names its day ("Fri 2:00 PM"): a temp can run 72 hours.
- The form is redrawn each minute (`TimelineView(.everyMinute)`), so "Now" and the end stay current.
- Hidden while the duration is one the pump refuses.
- Without it, a user who sets "1.30 U/hr" in the unit tab gets a different rate an hour later
  without being told.

### 6.8 Set temp rate and its confirmation

"Set temp rate" is the primary button. It is enabled when:
- the value is in the valid set,
- the duration is valid, and
- nothing is in flight.

Tapping it shows a confirmation, a plain SwiftUI `Alert` (**D5**).

```
            ┌────────────────────────────────┐
            │                                │
            │ Set a temp rate for 130% of    │
            │ profile basal for a duration   │
            │ of 1 hour, 30 minutes?         │
            │                                │
            │ Your new effective basal rate  │
            │ will be 1.30 U/hr.             │
            │                                │
            ├────────────────────────────────┤
            │         Set temp rate          │
            ├────────────────────────────────┤
            │            Cancel              │
            └────────────────────────────────┘
```

> Set a temp rate for XXX% of profile basal for a duration of N hours M minutes?
>
> Your new effective basal rate will be X.XX U/hr.

- **The effective basal rate** is the temp's own rate now, `profileBasalRate × percent / 100`
  (**D8**): 130% of a 1.00 U/hr profile shows 1.30 U/hr. The rate after a segment change is not in
  the sentence; the form lists it ([§6.7](#67-effective-basal-rates)).
- **The duration** is formatted with `DateComponentsFormatter`, `.full` style, `[.hour, .minute]`:
  - "1 hour, 30 minutes", "2 hours", "45 minutes";
  - not "0 hours 45 minutes" or "2 hours 0 minutes".
  - It is localized and pluralized for free.
- **Buttons.** "Set temp rate" is the default button. It is not destructive: a temp is a normal
  action. "Cancel" is `.cancel`.
- **In the unit tab** the same sentence is used. The command is a percent, and the sentence gives both
  numbers.

### 6.9 Sending, success and failure

**Sending**
- Every control is disabled, and the button shows an `ActivityIndicator`.
- The driver call is enactManualTempBasal(percent:duration:) ([§8.2](#82-set-a-temp-rate-at-a-percent)).

**Success**
- The screen goes back to Loading and reads the pump again.
- It should land on Active temp rate, which is the confirmation that the temp runs. There is no
  separate success message.
- Back on the settings screen, the row reads "Stop manual temp basal".

**Failure**
- An `ErrorSheetView` (`Utils/ErrorSheet.swift`) with `guidanceColors.critical`, titled "Could not set
  temp rate", and the error's description as the message.
- The driver's refusal texts already say why where it can tell (`PumpRefusal.tempBasal`): below the
  pump's 0.1 U/hr, or above its max basal limit.
- The form keeps its values.

**A temp running when Set is confirmed.** The loop's temp may have been there when the screen
loaded, or the loop may have set one since.
- **The loop's own temp** ([§5.1](#51-deciding-active)) or the clock-skew temp:
  enactManualTempBasal stops it and sets the user's temp, with no extra warning. If the pump then
  refuses the set, the stopped temp is put back (`restoreStoppedTempBasal`), as the host path does.
- **Anything else** (a manual temp, a temp set on the pump's screen or by another app, or one the
  driver doesn't hold): enactManualTempBasal fails with a new tempBasalAlreadyRunning and stops
  nothing.
  - The sheet says "A temp rate started while you were on this screen."
  - The screen reloads into Active temp rate.

**Under Control-IQ**, firmware that doesn't allow a temp then refuses the set (F6).
- The sheet gives the pump's refusal, as for any other. Nothing is checked beforehand.
- `PumpRefusal.tempBasal` adds a sentence when `useControlIQ` is on: "Control-IQ is on, and the pump
  may not take a temp rate while it runs." The pump gives only a status code, so this is the one hint
  the user gets.

**No answer** (`.communication(noResponse)`)
- The pump may still have started the temp. The driver reads it back first, as the host path does
  (`adoptUnansweredTempBasal`).
- The screen reloads either way, so it shows what the pump actually runs.

---

## 7. Active temp rate

Shown for a temp set from this screen, on the pump's screen, or by another app; never for the loop's
own temp ([§5.1](#51-deciding-active)).

### 7.1 Layout

```
┌──────────────────────────────────────────┐
│ ‹ Tandem Mobi                            │
│                                          │
│ Active temp rate                         │
│                                          │
│ ┌──────────────────────────────────────┐ │
│ │                                      │ │
│ │                130%                  │ │
│ │                                      │ │
│ │        1.30 U/hr right now           │ │
│ │   (130% of the 1.00 U/hr profile)    │ │
│ ├──────────────────────────────────────┤ │
│ │ Remaining              1 hr 12 min   │ │
│ └──────────────────────────────────────┘ │
│                                          │
│ ┌──────────────────────────────────────┐ │
│ │           Stop temp rate             │ │  ← red, filled
│ └──────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

- Navigation title "Active temp rate".
- The view shows the percent, the rate it delivers through the profile, and the time left, as
  requested. No other rows (**D7**).
- "Remaining" updates once a minute (`TimelineView(.everyMinute)`), rounded up so that 30 seconds left
  reads "1 min".

### 7.2 Where each value comes from

| Field | Source, in order of preference |
|---|---|
| Percent | `TempRateResponse.percentage`. |
| Rate right now | `CurrentBasalStatusResponse.currentBasalRate`: what the pump runs, already rescaled at any segment change. |
| Profile rate | `CurrentBasalStatusResponse.profileBasalRate`. |
| Remaining | `startTimeRaw + duration`, less the pump's time now, all in seconds on the pump's clock. The pump's time now is the phone's `now` plus `state.pumpClockOffset`, from the last `TimeSinceReset` read. Nothing is converted to the phone's clock, so it holds however far off the pump's clock is. |

- The read covers every temp the same way, whoever set it. A temp set on the pump's screen is
  reported to the host finished at detection (`closeReplacement`,
  `TandemPumpManager+DeliveryTransitions.swift:378-397`), so the held dose could not show it.
- The pump stamps the start on the clock in force when the temp began. A pump clock set while the
  temp runs (as at a DST change) moves the stamped start by the step (`lastPumpClockStep`), so the
  time left is off by that step until the temp ends.

### 7.3 Stop temp rate

"Stop temp rate" is a full-width `ActionButtonStyle(.destructive)` button, which is red. It shows the
confirmation: "Stop the active temp rate of XX%?" with a red
"Stop temp rate" and "Cancel".

**Confirming**
- Calls stopTempBasalFromSettings ([§8.3](#83-stop)), the cancel path that
  `TandemKitSettingsViewModel.stopTempRate()` reaches today through
  `enactTempBasal(unitsPerHour: 0, for: 0)`, without its Control-IQ refusal.
- That path stops the temp, starts the scheduled basal dose, reports both to the host and moves the
  boundary.

**Success**
- Reload. The screen should land on the set form.
- The 1 s pause and `syncPumpData` that `stopTempRate()` runs today are not needed here: the reload is
  the read-back.

**Failure**
- The existing "Could not stop temp rate" sheet.
- Its message ("The pump rejected stopping the temp rate…") should give way to the driver's error
  description when there is one. `PumpRefusal.stopTempBasal` already words it, and "rejected" is wrong
  for a lost answer.

**What happens next in the host**
- A manual temp: stopping it ends the host's pause. Trio runs a loop at once
  (`APSManager.swift:268-280`); Loop resumes at the status update.
- A temp set on the pump's screen or by another app: the host counts the scheduled basal from the
  stop. In closed loop it sets its next temp at its next cycle.

---

## 8. Driver changes

### 8.1 Read the temp rate status

```swift
public struct TempRateStatus {
    public let isActive: Bool
    public let percent: Int?                 // nil when inactive
    public let startDate: Date?              // phone clock
    public let endDate: Date?                // phone clock, from the pump's (§7.2); nil when inactive
    public let profileBasalRate: Double
    public let currentBasalRate: Double
    public let isSuspended: Bool
    public let isClockSkewCompensation: Bool
    public let isLoopTemp: Bool              // the held temp the host set, matching the read (§5.1)
}

public func readTempRateStatus(completion: @escaping (Result<TempRateStatus, PumpManagerError>) -> Void)
```

- `ensureConnected`, then `TempRateRequest` and `CurrentBasalStatusRequest` on the command queue,
  under `watchdogged`.
- **Required:** pass the basal read to `observeDeliveryState(_:)`, as every other
  `CurrentBasalStatus` read does. A read that sees a change of delivery has to start the transition
  machinery, or the screen would show a temp, or its absence, that the host has not been told of.
- No answer to either read is `.communication(noResponse)`.
- **The loop's temp.** `recordTempBasal` called from `enactTempBasal` records the held temp as the
  host's, in a persisted flag on the held dose that every re-statement of it carries, as `automatic`
  is. isLoopTemp is that, matched to the read as in §5.1. A temp adopted from
  history, set from settings or restored keeps whatever it had: only the host path sets it.

### 8.2 Set a temp rate at a percent

```swift
public func enactManualTempBasal(
    percent: Int,
    duration: TimeInterval,
    completion: @escaping (PumpManagerError?) -> Void
)
```

It differs from `enactTempBasal(unitsPerHour:for:)` where the user, not the host, chose the number:

| | `enactTempBasal` (host) | enactManualTempBasal (settings) |
|---|---|---|
| Input | U/hr, turned into a percent (`tempBasalPercentAndRate`) | Percent, sent as given |
| Over the pump's max basal limit | Clamped to the limit (`clampedToPumpMaximumBasalRate`) | **Refused** (manualTempBasalOutOfRange). The user confirmed a number, so no other number goes out. |
| Under the pump's 0.1 U/hr minimum | Raised to the lowest accepted percent | **Refused**, as above |
| Within `segmentChangeWindow` of a change | Worked out against the larger rate, reported at the request | Sent as given; reported at `percent × profileBasalRate`, and cut at the change by `splitAtSegmentChanges` as any temp is |
| 100% | No command; scheduled basal restarted | Sent as given (D13): reported manual, it keeps the host from adjusting basal while the profile rate runs |
| A temp already running | Stopped, then replaced (`restoreStoppedTempBasal` on refusal) | The loop's own temp (§5.1) or the clock-skew temp: stopped, then replaced, with `restoreStoppedTempBasal` on refusal. **Anything else: refused** (tempBasalAlreadyRunning), nothing stopped. |
| Control-IQ on | Refused (`controlIQModeActive`) | **Allowed** (D11) |
| Read-back after the set | `tempBasalReadbackMatches`: a temp within one 0.01 U/hr step of the percent | The same without Control-IQ, 100% included. Under it, `TempRateResponse` active at the percent sent, since Control-IQ may set `currentBasalRate`; a temp the pump took but reports at another percent, or none, fails (`tempRateReadbackMismatch`) and is reported as the pump reports it. |
| Reported `automatic` | `true` | `false` |

**Shared with the host path, factored out rather than copied**
- A bolus running refused, before and after connecting.
- Duration outside 15 min–72 h refused; whole minutes only.
- Pump clock untrusted, profile not synced, profile update failed and a 0 U/hr profile refused for a
  non-zero percent.
- The `SetTempRate` read-back check without Control-IQ (`tempBasalReadbackMatches`,
  `rejectMismatchedTempBasal`).
- `adoptUnansweredTempBasal` on a lost answer.
- `recordTempBasal` under Control-IQ too. The host counts the temp's rate. With
  `basalHistoryReporting`, basal reconciliation corrects any 5-minute cycle Control-IQ ran at another
  rate, as it does for a held temp the pump runs at another rate.
- `recordTempBasal`, with an `automatic` parameter added in place of the hard-coded `true`.

### 8.3 Stop

```swift
public func stopTempBasalFromSettings(completion: @escaping (PumpManagerError?) -> Void)
```

- The cancel half of `enactTempBasal` (stop, start the scheduled basal dose, report both), factored
  out and called by both. The settings row and the active view use this one.
- It has the cancel's guards (a running bolus) but not the Control-IQ one, so a manual temp set under
  Control-IQ can always be stopped from where it was set.
- `enactTempBasal(unitsPerHour: 0, for: 0)` from the host stays refused under Control-IQ.

### 8.4 Carrying `automatic: false`

The flag has to stay `false` everywhere the temp is re-stated. Otherwise the host sees a manual temp
turn automatic partway through, and its pause ends early.
- `UnfinalizedDose.automatic` is already persisted. `basalDeliveryState` passes it through
  (`TandemPumpManagerState.swift:798-799`).
- These already carry it: `splitAtSegmentChanges` (`running.automatic`) and the `interruptedTemp`
  continuation.
- These need changing:
  - **`recordTempBasal`** (`TandemPumpManager.swift:1318`): `automatic: true` becomes a parameter.
    `restoreStoppedTempBasal` and `adoptUnansweredTempBasal` pass the stopped or requested temp's flag.
  - **History adoption** (`TandemPumpManager+DeliveryTransitions.swift:597`): it marks a temp
    `automatic` whenever a `SetTempRateResponse` record names its `tempRateId`, which a temp set from
    settings also has. Keep a small persisted set of manual `tempRateId`s on state, and treat those
    as manual.
  - **Basal reconciliation** (`TandemPumpManager+BasalReconciliation.swift:483`): `setByTheApp` counts
    as automatic, and needs the same exception.
  - **Setup history load:** a temp set from settings before a re-pair would come back automatic. That
    is acceptable, since it is history only, but say so in CLAUDE.md.
- **The status push.** Trio's `isManualTempBasal` has no end-date check
  (`BasalDeliveryState+Extension.swift`), so Trio stays paused until the driver's status shows the
  temp ended. The driver closes an ended temp at the next reading after its end. Check that Trio
  still asks for pump data while paused, so that the reading comes. Loop checks `endDate` itself.

### 8.5 Status highlight

Add a "Manual Temp Basal" highlight to `buildPumpStatusHighlight()`
(`Sources/TandemKitUI/TandemPumpManager+UI.swift:110`) (**D6**).
- It comes last, after "Control-IQ On", so every other highlight wins. A manual temp under Control-IQ
  therefore shows "Control-IQ On".
- `imageName: "exclamationmark.circle.fill"`, `state: .warning`, as "Control-IQ On" has.
- The condition is the one that switches the settings row ([§4.2](#42-stop-manual-temp-basal)): the
  held dose is a temp with `automatic == false` and its end is still ahead.
- It is title case, like the other highlights. Trio and Loop show it in their pump status area, so a
  temp that can run for 72 hours is visible outside TandemKit's settings.

### 8.6 Interactions with existing driver behaviour

These already happen to any temp, and should be covered in the tests.

- **A basal schedule save that changes the rate in force stops a running non-zero temp**
  (CLAUDE.md, Onboarding and the basal schedule). A manual temp is stopped too, and that ends the
  host's pause.
- **A suspend stops the temp** (`suspendDelivery`, `TandemPumpManager.swift:1444-1460`). A resume
  does not restore it.
- **Clock skew compensation leaves a temp it did not set alone** (`maintainPumpClockSkewCompensation`),
  so it will not fight a manual temp. When the manual temp ends, compensation resumes on the next read.
- **Deleting the pump in the app** finalizes the held temp (`prepareForDeactivation`), but the pump
  keeps running it to its end: up to 72 hours. The delete dialog is unchanged (D9).
- **Control-IQ turned on or off** while a manual temp runs: whether the pump keeps the temp is
  unconfirmed (T8). Whatever it does, the next reading closes the driver's held temp if it ended.
- **`CurrentBasalStatus` under Control-IQ.** `basalType` matches `basalModifiedBitmask` exactly
  (`0x01` suspend, `0x02` temp, anything else basal). A temp with a Control-IQ bit also set would read
  as `.basal`, so `observeDeliveryState` would take the temp as ended.
  - The screen decides "active" from `TempRateResponse`, so it is not affected.
  - The driver's delivery tracking may need to test the temp bit rather than the whole value. T8
    records the bitmask.

---

## 9. How Loop and Trio treat a temp basal

References are to Loop `b05f7be` and Trio `nightscout/Trio@23bb3be` (dev).

| | Loop | Trio |
|---|---|---|
| How the pump manager learns the loop is on | `automaticDosingEnabled` = `isAutomaticDosingAllowed && dosingEnabled` (`LoopAppManager.swift:291-295`) | `dosingMode.automation != .off` (`DeviceDataManager.swift:358-360`): closed, low glucose suspend and basal testing |
| A temp reported `automatic: true` (the loop's own) | Its own. Replaced at the next cycle in closed loop. Cancelled when closed loop is turned off, when the max basal rate drops below it, and when CGM data is unreliable while it is above the schedule (`LoopDataManager.swift:226-234, 619-641, 1930-1938`). | Its own. Replaced at the next determination. Cancelled when basal testing starts (`APSManager.swift:1503`); not when closed loop is turned off. |
| A temp reported `automatic: false` (set from settings), not ended | `pumpIsAllowingAutomation = false` (`DeviceDataManager.swift:1203-1209`), so automatic dosing is off. The closed-loop switch says "Your pump is delivering a manual temporary basal rate." None of the cancels above touch it. | `isManualTempBasal` (`BasalDeliveryState+Extension.swift`). Each loop ends with `APSError.manualBasalTemp` (`APSManager.swift:786-788`), raised as a "Manual Temp Basal Active" alert (fired at once). The loop icon shows the manual-temp state. "Not Looping" alerts are held off (`NotLoopingMonitor.swift:96`). |
| When the manual temp ends | Automation allowed again at the next status update after `endDate`. | `isManualTempBasal` goes false at the status update that drops the temp, and Trio runs `loop()` at once (`APSManager.swift:268-280`). |

So a temp set from settings is left alone by both hosts, as OmnipodKit's is, and the user does not
leave closed loop for it. In Trio the user also gets "Manual Temp Basal Active" from Trio itself, on
top of TandemKit's status highlight; check that the two don't read as two different problems (T7).

---

## 10. Comparison with OmnipodKit

Reference: `loopandlearn/OmnipodKit@0c6d68b`, mainly `PumpManagerUI/Views/ManualTempBasalEntryView.swift`,
`PumpManagerUI/Views/OmniSettingsView.swift` (lines 412–440), `PumpManagerUI/ViewModels/OmniSettingsViewModel.swift`
and `PumpManager/OmniPumpManager.swift` (lines 2846–2997).

### 10.1 Side by side

| | OmnipodKit | TandemKit (this spec) |
|---|---|---|
| **Entry point** | "Set Temporary Basal Rate", in its own untitled section after Actions. Opens a modal sheet. | "Set temp basal" › in Actions, between "Pump notifications" and suspend/resume. Pushes a screen. |
| **Row while a manual temp runs** | Becomes "Cancel Manual Basal" (warning icon) plus a separate "Remaining 1 hour, 29 minutes" row. | Becomes "Stop manual temp basal", subtext "130% (1.30U/hr) with 1h 12m remaining". |
| **Row while another temp runs** | The normal "Set" row; the sheet can replace it. | The normal "Set temp basal" row. For the loop's own temp the screen opens on the set form and Set replaces it; for a pump-screen or other app's temp, on "Active temp rate". |
| **Row disabled when** | No pod, activating, deactivating or faulted. Not while suspended, bolusing or in closed loop. | Suspended, delivery state unknown, or a command in flight. A running bolus is explained on the screen. |
| **Title** | "Temporary Basal" (sheet) | "Set temp basal" / "Active temp rate" |
| **Rate input** | Absolute U/hr only: one wheel, 0–max basal in 0.05 U/hr steps, 0.00 included. | Percent (default) or U/hr view of a percent. Steppers of 10%, typed entry. 0 or pMin–pMax whole %. |
| **Rate ceiling** | The host-synced max basal rate (`state.maxBasalRateUnitsPerHour`). Above it, the driver only logs. | min(250%, pump's max basal limit ÷ profile) over the duration's segments. Above it, the driver refuses. |
| **Rate floor** | 0 U/hr; any 0.05 step | 0%, or the lowest % the pump accepts (≥ 0.1 U/hr) |
| **Duration** | One wheel, 30 min–12 h in 30-min steps (24 choices) | Hours + minutes wheels, 15 min–72 h, 5-minute steps |
| **Defaults** | 0.00 U/hr for 30 min (a zero temp, one tap from set) | 100% for 30 min |
| **Closed loop** | No detection. A static footnote: "Your insulin delivery will not be automatically adjusted until the temporary basal rate finishes or is canceled." | Nothing on either screen. The host shows its own pause, and TandemKit's status highlight shows. |
| **Confirmation to set** | None | "Set a temp rate for 130% of profile basal for a duration of 1 hour, 30 minutes?" then "Your new effective basal rate will be 1.30 U/hr." |
| **Set errors** | Alert "Temporary Basal Failed": "Unable to set a temporary basal rate: …". The sheet stays open. | Error sheet "Could not set temp rate" with the driver's reason. The form keeps its values. |
| **Success** | The sheet closes; the settings row turns into Cancel + Remaining. | Reloads into "Active temp rate"; the settings row turns into "Stop manual temp basal". |
| **Viewing a running temp** | Settings rows only: no rate, no end time. The header shows the U/hr. "Remaining" does not tick. | The settings row (%, U/hr, time left, ticking) for a manual temp, and a dedicated view (%, U/hr now, profile, time left) for any temp but the loop's. |
| **Stop** | "Cancel Manual Basal": immediate, **no confirmation**. Error alert "Failed to Cancel Manual Basal". | "Stop manual temp basal" on the row, or the red "Stop temp rate" on the active view, both with "Stop the active temp rate of 130%?" |
| **Manual vs automatic** | `enactTempBasal(…, automatic: false)`. Persisted in `UnfinalizedDose` and `PendingCommand`. | enactManualTempBasal, reported `automatic: false`. Persisted in `UnfinalizedDose`, and kept manual through history and reconciliation (§8.4). |
| **A temp in the way** | Cancels any running temp first. | Replaces the loop's own, with no warning; refuses any other. No way to stop the loop's temp on its own. |
| **Other driver guards** | Refuses when suspended. A bolus running is only logged. | Refuses a running bolus, an untrusted clock and an unsynced profile, as the host path does. Allows Control-IQ, which the host path refuses (D11). |
| **Status highlight** | "Manual Basal", `exclamationmark.circle.fill`, warning, lowest priority. | "Manual Temp Basal", `exclamationmark.circle.fill`, warning, lowest priority. |
| **Suspend / resume** | A suspend cancels it; a resume doesn't restore it. | The same (pump behaviour). |
| **Relaunch** | Persisted; the highlight and the Cancel row come back. | Persisted (held dose); the highlight and the Stop row come back. The screen reads the pump anyway. |
| **Tests** | None pin manual temp behaviour. | See §12. |

### 10.2 What differs, and why

- **Percent.** A Tandem pump takes a percent of its profile, not a rate, and rescales it at segment
  changes. OmnipodKit's U/hr wheel suits Omnipod, which takes an absolute rate. TandemKit's unit tab
  is a view of a percent, and §6.7's effective basal rates exist because "1.30 U/hr" does not stay 1.30 U/hr
  on a Tandem pump.
- **Refuse, don't clamp.** OmnipodKit only logs a rate over max basal, as a workaround for hosts that
  send one. That reasoning is about host commands. For a number a person typed and confirmed, sending
  a different one is worse than refusing.
- **Duration.** The Tandem pump takes 15 min–72 h to the minute. A 30-minute grid up to 12 h would
  throw most of that away.
- **Confirmation.** OmnipodKit sets with one tap from a sheet that opens on a zero temp, and cancels
  with one tap. TandemKit confirms both.
- **Closed loop** now works the same way in both: the temp is reported manual and the host pauses.
  OmnipodKit says so in a footnote; TandemKit's set form says nothing about it.
- **The cost of manual reporting.** OmnipodKit's flag is set once and never re-derived. TandemKit
  re-derives `automatic` from history and basal reconciliation, so it needs §8.4 to keep it.

### 10.3 Taken from OmnipodKit, and not

- **Taken:**
  - `automatic: false` and the host pause (D1).
  - The settings row that turns into a stop control with the time left (D7). TandemKit's adds the
    percent and rate, and a confirmation.
  - The status highlight (D6).
- **Not taken:**
  - The zero-temp default.
  - Set and cancel without confirmation.
  - The U/hr-only wheel.
  - Logging a rate over max basal instead of refusing it.

---

## 11. Copy

All strings go in `Localizable.xcstrings` with comments. `<App>` is `HostApp`'s name: "Trio",
"Loop", "This app" at the start of a sentence, "this app" mid-sentence.

| Key / place | English |
|---|---|
| Settings row | Set temp basal |
| Settings row, manual temp running | Stop manual temp basal |
| Settings row subtext | %1$d%% (%2$@U/hr) with %3$@ remaining |
| Status highlight | Manual Temp Basal |
| Screen title (no temp) | Set temp basal |
| Screen title (temp) | Active temp rate |
| Set refused under Control-IQ (added to the refusal) | Control-IQ is on, and the pump may not take a temp rate while it runs. |
| Tabs | Percent rate · Unit rate |
| Percent caption | of profile basal |
| Unit caption | %d%% of the %@ U/hr profile basal rate |
| Duration section | Duration |
| Duration row and wheels | %d hr · %d min |
| Effective rates section | Effective basal rates |
| Effective rate rows | Now – %@ · %1$@ – %2$@ · %@ U/hr |
| Primary button | Set temp rate |
| Set confirmation | Set a temp rate for %1$d%% of profile basal for a duration of %2$@?\n\nYour new effective basal rate will be %3$@ U/hr. |
| Set confirmation buttons | Set temp rate · Cancel |
| Set failure title | Could not set temp rate |
| Temp started meanwhile | A temp rate started while you were on this screen. |
| Active: rate line | %@ U/hr right now |
| Active: row | Remaining |
| Stop button | Stop temp rate |
| Stop confirmation | Stop the active temp rate of %d%%? |
| Stop confirmation buttons | Stop temp rate (destructive) · Cancel |
| Blocked: suspended | Insulin delivery is suspended. Resume delivery before setting a temp basal. |
| Blocked: bolus | A bolus is being delivered. You can set a temp basal once it finishes. |
| Blocked: clock | The pump's clock is more than a day off this phone's. Sync the pump time before setting a temp basal. |
| Can't reach pump | Could not read the pump's temp rate. Keep the pump near your phone and try again. · Retry |

These strings say what the pump and the loop will do, and do not suggest when to use a temp basal or
at what rate.

---

## 12. Tests

Every new test file goes in the `TandemKitTests` target (`scripts/check_xcodeproj_source_membership.rb --fix`).

### 12.1 Unit tests

**TandemKitTempBasalViewModelTests**
- The screen state follows the read:
  - inactive → form;
  - active → active view, except the loop's own temp → form;
  - a temp another app set over Bluetooth, adopted as automatic, is not the loop's → active view;
  - the clock-skew temp → form;
  - no answer → error;
  - each blocked state → its card.
- The valid set:
  - pMin at 0.58 U/hr is 18%;
  - pMax is capped by the max basal limit;
  - both are worked out over the duration's segments;
  - changing the duration moves them.
- Steppers:
  - 95 + → 100;
  - 20 − → 18 − → 0 at an 18% minimum;
  - 0 + → the minimum;
  - disabled at the ends.
- A typed value outside the set is kept, shows in red and disables Set. It is never clamped.
- The unit tab:
  - a typed rate becomes the nearest whole percent;
  - one step is 10%;
  - switching tabs keeps the percent.
- 100% can be set.
- The duration:
  - the minutes wheel offers 00–55 in steps of 5;
  - 0 h 10 min and 72 h 5 min disable Set;
  - the default is 30 min;
  - the formatter gives "1 hour, 30 minutes" and "45 minutes".
- Neither screen shows a card, in any loop mode or under Control-IQ.
- The confirmation text, for each tab, with the temp's rate in brackets.
- A failure keeps the form's values. A success reloads.
- Remaining is `startTimeRaw + duration` less the pump's time now, and is the same whatever the
  pump clock's offset from the phone.

**`TandemKitSettingsViewModelTests`**
- The row is "Set temp basal" with no temp, with an automatic temp and with a pump-screen temp.
- The row is "Stop manual temp basal" with a manual temp, with the subtext "130% (1.30U/hr) with
  1h 12m remaining", and goes back to "Set temp basal" once the temp's end has passed.
- The row's enabled state for each pump state in [§4.3](#43-when-the-rows-are-disabled).
- Tapping the stop row asks for confirmation, and only a confirmed stop sends the cancel.
- The header tap opens the screen.

**ManualTempBasalTests** (driver)
- The percent is sent as given, with the duration in whole minutes as milliseconds.
- Refused, with nothing sent:
  - over the max basal limit;
  - under 0.1 U/hr;
  - outside 15 min–72 h;
  - while a bolus runs;
  - an untrusted clock (non-zero only);
  - an unsynced profile (non-zero only).
- A temp in the way:
  - the loop's own temp is stopped and replaced, whether it ran when the screen loaded or started since;
  - a refused set after that stop puts the loop's temp back;
  - the clock-skew temp is replaced;
  - a manual temp, or one the driver doesn't hold, fails tempBasalAlreadyRunning with no
    `StopTempRate` sent.
- The read-back mismatch, and a lost answer adopted, as `UnansweredTempBasalTests` does for the host path.
- 100% goes out, reported manual.
- Under Control-IQ:
  - the set goes out, and the read-back takes `TempRateResponse` active at the percent, whatever
    `currentBasalRate` says;
  - a temp the pump took but runs at another percent, or not at all, fails `tempRateReadbackMismatch`;
  - a lost answer is adopted from `TempRateResponse` alone;
  - a refusal carries the Control-IQ sentence;
  - stopTempBasalFromSettings stops the temp;
  - the host's `enactTempBasal`, cancel included, is still refused.
- The reported dose: `percent × profileBasalRate`, `tempPercent`, `eventRaw` from `tempRateId`, and
  `automatic: false`.
- `automatic: false` survives:
  - a segment cut;
  - an occlusion stop and its continuation;
  - a restore after a refused replacement;
  - history adoption (`observeReplacedTempBasal`);
  - basal reconciliation;
  - a relaunch (`rawValue` round trip).
- The status highlight is "Manual Temp Basal" for a manual temp, is outranked by every other
  highlight, and clears once the temp ends.
- readTempRateStatus passes its basal reading to `observeDeliveryState`. A temp found running that
  the held state lacks is handled as the sync path handles it.

### 12.2 Integration (faketandem)

- A manual temp basal integration test:
  - set 130% for 45 min from the settings path, read back active, stop it, read back inactive;
  - the host receives a manual temp and the stop;
  - with the host's own temp running, open the screen (the set form) and set from settings: the
    host's temp is replaced.
- The host pause itself (no `enactTempBasal` from the host while the manual temp runs) belongs in
  conformance tests if the harness can't drive the host side.
- If it is a flagged-only class, name it in both the macOS `integration` job and the Linux
  `virtual-pump` job (CLAUDE.md).

### 12.3 Hardware test plan additions

Rows for [docs/hardware-test-plan.md](hardware-test-plan.md):

| ID | Steps | Expected / record |
|---|---|---|
| T3 | In open loop, set 130% for 45 minutes from TandemKit's settings. Read the pump's screen. Stop it from the settings row after 10 minutes. | The pump shows a 130% temp with about 45 min left. The row and the active view show 130%, the rate, and a time left that matches the pump's. After the stop, the pump and the host return to the profile rate. |
| T4 | Set a temp rate on the pump's own screen for 1 h 15 min, then open the screen. | It shows "Active temp rate" with the pump's percent, and the time left the pump's screen shows. |
| T5 | With a profile segment change 20 minutes away, set 130% for 1 hour. | Record the pump's rate before and after the change, and that the host's held dose is cut there and stays manual. |
| T6 | With the max basal limit at 2.0 U/hr and a segment change from 0.8 to 1.0 U/hr ahead, set 250% across it. | The screen refuses 250% (the highest valid percent is 200%). Separately, set 240% just before the change on the pump's screen, and record what the pump does at the change (2.4 U/hr > limit). |
| T7 | In Trio's and in Loop's closed loop, with the loop's temp running, open the screen and set a temp from settings. Let it run past a few loop cycles, then stop it. Repeat, letting it run to its end. | The screen opens on the set form, and the user's temp replaces the loop's. The host stops dosing for its length (Trio: "Manual Temp Basal Active"; Loop: the closed-loop switch explains why), the "Manual Temp Basal" highlight shows, and the host resumes at the stop and at the end. Record how Trio's alert and TandemKit's highlight read together. |
| T8 | Turn Control-IQ on. Set 130% for 30 minutes from TandemKit's settings, watch a few 5-minute cycles, then stop it from the settings row. Repeat with the temp set on the pump's screen, and turn Control-IQ off and on while one runs. Run it on more than one firmware version. | **Record** the firmware version and: on firmware that refuses, the status code, and that the refusal reaches the user with nothing else changed; on firmware that takes it, `basalModifiedBitmask` and `currentBasalRate` while the temp runs, whether Control-IQ keeps adjusting delivery and around which rate, whether the temp survives Control-IQ being turned off or on, and that the stop works. |

---

## 13. Decisions

| ID | Question | Decided |
|---|---|---|
| D1 | Report a temp set from settings as manual (`automatic: false`), so Loop and Trio pause automatic dosing while it runs? | **Yes.** Neither screen shows a closed-loop card (§6.2). The driver keeps the flag (§8.4). |
| D2 | While the loop's own temp runs, what does the screen show? | **The set form.** The loop's temp counts as no temp, and "Set temp rate" replaces it with no extra warning, whether it was there at load or started since. Nothing offers to stop the loop's temp on its own. |
| D12 | A temp set on the pump's screen or by another app? | **"Active temp rate" with Stop**, and a Set while one runs fails and reloads (§6.9). |
| D3 | Minutes wheel step? | **5 minutes.** |
| D4 | Default duration? | **30 minutes.** |
| D5 | Bold text in the confirmations? | **No.** Plain `Alert`s. |
| D6 | A status highlight while a manual temp runs? | **Yes**, "Manual Temp Basal", warning, lowest priority (§8.5). |
| D7 | Extra details? | **The settings row** turns into "Stop manual temp basal" with "XX% (X.XXU/hr) with XXh XXm remaining" while a manual temp runs, and tapping it asks to stop (§4.2). Manual temps only. No percent on the "Set temp basal" row, and no "Started", "Ends at" or "Set by" on the active view. |
| D8 | The set confirmation's rate: the temp's or the profile's? | **The temp's rate**, as "Your new effective basal rate will be X.XX U/hr." |
| D9 | Warn on "Delete Pump" while a temp runs? | **No.** |
| D10 | Hide the screen on pumps pumpX2 doesn't mark as supported? | **No**, not gated. |
| D13 | Allow a manual 100% temp? | **Yes.** It holds the profile rate, and reported manual it keeps Loop or Trio from adjusting basal while it runs. "Set temp rate" is enabled at 100% (§6.4). |
| D11 | Allow a manual temp rate while Control-IQ runs? | **Yes, with no firmware check.** Some Mobi firmware takes it and some doesn't; the driver sends it and relies on the pump to refuse. The set and the settings stop skip the driver's Control-IQ refusal; the host's temps stay refused. No Control-IQ card (F6). |
