# PumpX2 Settings Gap Analysis

This document compares the pump settings configurable via the [pumpX2](https://github.com/jwoglom/pumpX2) Java library against what TandemKit currently exposes, and proposes where missing settings should be added in the UI.

**Constraint:** Besides turning Control-IQ on/off, no other Control-IQ settings should be exposed.

---

## 1. Current State: What TandemKit Already Exposes

### Settings Currently in the UI (TandemKitSettingsView)

| Setting | Control Message | UI Location | Status |
|---|---|---|---|
| Suspend / Resume delivery | `SuspendPumpingRequest` / `ResumePumpingRequest` | Actions section | ✅ Fully wired |
| Stop temp basal rate | `StopTempRateRequest` | Actions section (conditional) | ✅ Fully wired |
| Control-IQ on/off | `ChangeControlIQSettingsRequest` | Pump Status section | ✅ Fully wired |
| Sleep mode toggle | `SetModesRequest` | Pump Status section | ✅ Fully wired |
| Exercise mode toggle | `SetModesRequest` | Pump Status section | ✅ Fully wired |
| Pump sounds | `SetPumpSoundsRequest` | Sound Settings sub-screen | ✅ Fully wired |
| Pump time sync | `ChangeTimeDateRequest` | Pump Time section | ✅ Fully wired |
| Change cartridge | `EnterChangeCartridgeModeRequest` / `ExitChangeCartridgeModeRequest` | Cartridge Ops section (6-step wizard) | ✅ Fully wired |
| Fill tubing | `EnterFillTubingModeRequest` / `ExitFillTubingModeRequest` | Cartridge Ops section (5-step wizard) | ✅ Fully wired |
| Fill cannula | `FillCannulaRequest` | Cartridge Ops section (3-step wizard) | ✅ Fully wired |
| Dismiss notifications | `DismissNotificationRequest` | Notifications sub-screen | ✅ Fully wired |
| Insulin type | *(local setting)* | Pump Status section | ✅ Local only |
| Silent tones | *(local setting)* | Additional Options section | ✅ Local only |
| Auto-acknowledge alerts | *(local setting)* | Notifications section | ✅ Local only |

### Messages Wired in PumpManager But Not in Settings UI

| Setting | Control Message | Manager Method | Notes |
|---|---|---|---|
| Max basal rate limit | `SetMaxBasalLimitRequest` | `TandemPumpManager.updateMaxBasalRate()` | Called during therapy commands, no standalone UI |
| Max bolus limit | `SetMaxBolusLimitRequest` | `TandemPumpManager.updateBolusAmount()` | Called during therapy commands, no standalone UI |

---

## 2. Complete pumpX2 Control Messages Inventory

### Settings-Configuration Messages (37 total in pumpX2)

Organized by functional area, with TandemKit implementation status:

#### A. Profile / IDP Management (6 messages)

| pumpX2 Control Request | What It Configures | TandemCore Message? | Wired in Manager? | UI? |
|---|---|---|---|---|
| `CreateIDPRequest` | Create new insulin delivery profile | ✅ Defined | ❌ No | ❌ No |
| `DeleteIDPRequest` | Delete a profile | ✅ Defined | ❌ No | ❌ No |
| `RenameIDPRequest` | Rename a profile | ✅ Defined | ❌ No | ❌ No |
| `SetActiveIDPRequest` | Switch the active profile | ✅ Defined | ❌ No | ❌ No |
| `SetIDPSettingsRequest` | Edit profile insulin duration / carb entry mode | ✅ Defined | ❌ No | ❌ No |
| `SetIDPSegmentRequest` | Edit a time segment (basal rate, carb ratio, ISF, target BG) | ✅ Defined | ❌ No | ❌ No |

**Corresponding read messages (all defined in TandemCore):**
- `ProfileStatusRequest` → active profile, number of profiles, slot IDs
- `IDPSettingsRequest(idpId)` → profile name, segment count, insulin duration, max bolus, carb entry
- `IDPSegmentRequest(idpId, segmentIndex)` → start time, basal rate, carb ratio, target BG, ISF

#### B. Delivery Limits (2 messages)

| pumpX2 Control Request | What It Configures | TandemCore Message? | Wired in Manager? | UI? |
|---|---|---|---|---|
| `SetMaxBasalLimitRequest` | Maximum hourly basal rate (milliunits) | ✅ Defined | ⚠️ Partial | ❌ No |
| `SetMaxBolusLimitRequest` | Maximum single bolus (milliunits) | ✅ Defined | ⚠️ Partial | ❌ No |

**Corresponding read messages:**
- `BasalLimitSettingsRequest` → current max basal rate + default
- `GlobalMaxBolusSettingsRequest` → current max bolus + default

#### C. Control-IQ / Automation (3 messages) — EXCLUDED PER CONSTRAINT

| pumpX2 Control Request | What It Configures | Expose? |
|---|---|---|
| `ChangeControlIQSettingsRequest` | Enable/disable Control-IQ *(+ weight, TDI)* | ✅ On/off only (already done) |
| `SetModesRequest` | Sleep mode / Exercise mode toggle | ❌ **Do not add** (Control-IQ sub-setting; note: already exists in UI) |
| `SetSleepScheduleRequest` | Control-IQ sleep schedule slots | ❌ **Do not add** (Control-IQ sub-setting) |

> **Note:** The existing sleep/exercise mode toggles are already in the UI and can remain, but no further Control-IQ configuration (weight, TDI, sleep schedule editing) should be added.

#### D. Quick Bolus Settings (1 message)

| pumpX2 Control Request | What It Configures | TandemCore Message? | Wired in Manager? | UI? |
|---|---|---|---|---|
| `SetQuickBolusSettingsRequest` | Enable/disable quick bolus, mode (units/carbs), increment size | ✅ Defined | ❌ No | ❌ No |

**Corresponding read messages:**
- `PumpGlobalsRequest` → `quickBolusEnabled`, `quickBolusEntryType`, `quickBolusIncrement`, `quickBolusIncrementCarbs`, `quickBolusIncrementUnits`

#### E. Pump Sounds (2 messages)

| pumpX2 Control Request | What It Configures | TandemCore Message? | Wired in Manager? | UI? |
|---|---|---|---|---|
| `SetPumpSoundsRequest` | Annunciation mode per category | ✅ Defined | ✅ Yes | ✅ Yes |
| `PlaySoundRequest` | Trigger pump locator sound | ✅ Defined | ❌ No | ❌ No |

#### F. Alert / Snooze Settings (1 message)

| pumpX2 Control Request | What It Configures | TandemCore Message? | Wired in Manager? | UI? |
|---|---|---|---|---|
| `SetPumpAlertSnoozeRequest` | Alert snooze enable + duration (Mobi triple-press) | ✅ Defined | ❌ No | ❌ No |

**Corresponding read messages:**
- `PumpGlobalsRequest` → contains snooze-related fields
- `AlertStatusRequest` → active alert status

#### G. CGM / Dexcom Management (4 messages)

| pumpX2 Control Request | What It Configures | TandemCore Message? | Wired in Manager? | UI? |
|---|---|---|---|---|
| `SetG6TransmitterIdRequest` | Dexcom G6 transmitter ID | ✅ Defined | ❌ No | ❌ No |
| `SetDexcomG7PairingCodeRequest` | Dexcom G7 sensor pairing code | ✅ Defined | ❌ No | ❌ No |
| `StartDexcomG6SensorSessionRequest` | Start G6 CGM session | ✅ Defined | ❌ No | ❌ No |
| `StopDexcomCGMSensorSessionRequest` | Stop CGM session (G6/G7) | ✅ Defined | ❌ No | ❌ No |

**Corresponding read messages:**
- `CGMStatusRequest` → session state, transmitter battery, last calibration
- `CGMHardwareInfoRequest` → hardware info string
- `GetG6TransmitterHardwareInfoRequest` → G6-specific hardware info
- `GetSavedG7PairingCodeRequest` → stored G7 pairing code

#### H. Time / System (2 messages)

| pumpX2 Control Request | What It Configures | TandemCore Message? | Wired in Manager? | UI? |
|---|---|---|---|---|
| `ChangeTimeDateRequest` | Pump clock | ✅ Defined | ✅ Yes | ✅ Yes |
| `DisconnectPumpRequest` | Graceful BLE disconnect | ✅ Defined | ❌ No | ❌ No |

#### I. Bolus Workflow (6 messages)

| pumpX2 Control Request | What It Does | TandemCore Message? | Wired in Manager? | UI? |
|---|---|---|---|---|
| `BolusPermissionRequest` | Request bolus permission | ✅ Defined | ✅ Yes | ✅ Implicit |
| `BolusPermissionReleaseRequest` | Release bolus lock | ✅ Defined | ❌ No | ❌ No |
| `RemoteBgEntryRequest` | Submit BG for bolus calc | ✅ Defined | ❌ No | ❌ No |
| `RemoteCarbEntryRequest` | Submit carbs for bolus calc | ✅ Defined | ❌ No | ❌ No |
| `InitiateBolusRequest` | Start bolus delivery | ✅ Defined | ✅ Yes | ✅ Yes |
| `CancelBolusRequest` | Cancel in-progress bolus | ✅ Defined | ❌ No | ❌ No |

#### J. Temp Rate / Suspend (4 messages)

| pumpX2 Control Request | What It Does | TandemCore Message? | Wired in Manager? | UI? |
|---|---|---|---|---|
| `SetTempRateRequest` | Set temp basal % + duration | ✅ Defined | ✅ Yes | ✅ Yes |
| `StopTempRateRequest` | Cancel temp basal | ✅ Defined | ✅ Yes | ✅ Yes |
| `SuspendPumpingRequest` | Suspend delivery | ✅ Defined | ✅ Yes | ✅ Yes |
| `ResumePumpingRequest` | Resume delivery | ✅ Defined | ✅ Yes | ✅ Yes |

#### K. Cartridge / Tubing / Cannula (5 messages)

All ✅ defined and ✅ in UI via wizard workflows.

---

## 3. Gap Summary

### GAP 1: Profile / IDP Management (HIGH PRIORITY)

**What's missing:** Users cannot view, create, edit, rename, delete, or switch insulin delivery profiles from TandemKit. This is one of the most critical pump configuration surfaces — profiles control basal rates, carb ratios, ISF, and target BG across time-of-day segments.

**Messages needed:**
- Write: `CreateIDPRequest`, `DeleteIDPRequest`, `RenameIDPRequest`, `SetActiveIDPRequest`, `SetIDPSettingsRequest`, `SetIDPSegmentRequest`
- Read: `ProfileStatusRequest`, `IDPSettingsRequest`, `IDPSegmentRequest`

**All messages are already defined in TandemCore** — they just need to be wired through `TandemPumpManager` and surfaced in UI.

### GAP 2: Delivery Limits (HIGH PRIORITY)

**What's missing:** Users cannot view or change the max basal rate or max bolus limits from the settings UI. The manager sets these internally during therapy commands but there is no standalone settings surface.

**Messages needed:**
- Write: `SetMaxBasalLimitRequest`, `SetMaxBolusLimitRequest`
- Read: `BasalLimitSettingsRequest`, `GlobalMaxBolusSettingsRequest`

**Already partially wired** in `TandemPumpManager` — needs UI exposure.

### GAP 3: Quick Bolus Settings (MEDIUM PRIORITY)

**What's missing:** Users cannot configure the quick bolus feature (enable/disable, units vs carbs mode, increment size).

**Messages needed:**
- Write: `SetQuickBolusSettingsRequest`
- Read: `PumpGlobalsRequest`

**Message defined in TandemCore** — needs manager + UI wiring.

### GAP 4: CGM / Dexcom Management (MEDIUM PRIORITY)

**What's missing:** Users cannot pair a Dexcom G6 transmitter, set a G7 pairing code, or start/stop CGM sensor sessions from TandemKit.

**Messages needed:**
- Write: `SetG6TransmitterIdRequest`, `SetDexcomG7PairingCodeRequest`, `StartDexcomG6SensorSessionRequest`, `StopDexcomCGMSensorSessionRequest`
- Read: `CGMStatusRequest`, `CGMHardwareInfoRequest`, `GetG6TransmitterHardwareInfoRequest`, `GetSavedG7PairingCodeRequest`

**All messages defined in TandemCore** — needs manager + UI wiring.

### GAP 5: Alert Snooze Settings (LOW PRIORITY)

**What's missing:** Users cannot configure the alert snooze button behavior (Mobi triple-press to snooze, snooze duration).

**Messages needed:**
- Write: `SetPumpAlertSnoozeRequest`
- Read: `PumpGlobalsRequest`

**Message defined in TandemCore** — needs manager + UI wiring.

### GAP 6: Play Sound / Find Pump (LOW PRIORITY)

**What's missing:** Users cannot trigger the pump to play its locator sound.

**Messages needed:**
- Write: `PlaySoundRequest`

**Message defined in TandemCore** — needs manager + UI wiring.

### GAP 7: Cancel Bolus (MEDIUM PRIORITY)

**What's missing:** Users cannot cancel an in-progress bolus from the TandemKit UI. This is an operational action rather than a setting, but it's important for safety.

**Messages needed:**
- Write: `CancelBolusRequest`
- Read: `CurrentBolusStatusRequest`

**Message defined in TandemCore** — needs manager + UI wiring.

### GAP 8: Remote BG / Carb Entry (LOW PRIORITY)

**What's missing:** Users cannot enter BG readings or carb entries that get recorded on the pump. This is mainly useful for the bolus calculator workflow.

**Messages needed:**
- Write: `RemoteBgEntryRequest`, `RemoteCarbEntryRequest`

**Messages defined in TandemCore** — needs manager + UI wiring.

### GAP 9: Graceful Disconnect (LOW PRIORITY)

**What's missing:** No way to send a graceful BLE disconnect command to the pump (instead of just dropping the connection).

**Messages needed:**
- Write: `DisconnectPumpRequest`

**Message defined in TandemCore** — should be called during `TandemPumpManager.disconnect()`.

---

## 4. Excluded From Scope (Control-IQ Sub-Settings)

Per the stated constraint, the following are **intentionally excluded**:

| Setting | pumpX2 Message | Reason |
|---|---|---|
| Control-IQ weight / total daily insulin | `ChangeControlIQSettingsRequest` fields | Control-IQ sub-setting |
| Sleep schedule configuration | `SetSleepScheduleRequest` | Control-IQ sub-setting |
| Sleep mode on/off | `SetModesRequest(SLEEP_MODE_*)` | Control-IQ sub-setting (already in UI, no expansion needed) |
| Exercise mode on/off | `SetModesRequest(EXERCISE_MODE_*)` | Control-IQ sub-setting (already in UI, no expansion needed) |

---

## 5. Proposed UI Placement

### Current Settings View Structure (for reference)

```
TandemKitSettingsView
├── [Header] Pump image, delivery status, reservoir
├── [Actions] Suspend/Resume, Stop Temp Rate, Refresh
├── [Notifications] View Notifications, Auto-Acknowledge toggle
├── [Pump Status] Control-IQ, User Mode, Temp Rate, Insulin Type, Sound Settings
├── [Cartridge Operations] Change Cartridge, Fill Tubing, Fill Cannula
├── [Pump Time] Current time, Sync button
└── [Additional] Silent Tones, Share Logs, Delete Pump
```

### Proposed Additions

#### New Section: "Profiles" (after Pump Status)

```
[Profiles]
├── Active Profile: "Profile 1"     ← tap to switch active profile (SetActiveIDPRequest)
├── Profile 1 →                     ← NavigationLink to profile detail
│   ├── Name: "Profile 1"          ← editable (RenameIDPRequest)
│   ├── Insulin Duration: 5.0 hrs  ← editable (SetIDPSettingsRequest, changeType=CHANGE_INSULIN_DURATION)
│   ├── Carb Entry: Enabled        ← toggle (SetIDPSettingsRequest, changeType=CHANGE_CARB_ENTRY)
│   └── Time Segments →            ← NavigationLink to segments list
│       ├── 12:00 AM – 6:00 AM    ← tap to edit segment (SetIDPSegmentRequest, MODIFY_SEGMENT_ID)
│       │   ├── Basal Rate: 0.80 U/hr
│       │   ├── Carb Ratio: 1:10
│       │   ├── Correction Factor (ISF): 40 mg/dL
│       │   └── Target BG: 110 mg/dL
│       ├── 6:00 AM – 12:00 PM
│       │   └── ...
│       ├── [+ Add Segment]         ← (SetIDPSegmentRequest, CREATE_SEGMENT)
│       └── [Swipe to delete]       ← (SetIDPSegmentRequest, DELETE_SEGMENT_ID)
├── Profile 2 →
│   └── ...
├── [+ Create Profile]              ← (CreateIDPRequest)
└── [Swipe to delete profile]       ← (DeleteIDPRequest)
```

**Implementation files:**
- New: `TandemKitProfilesView.swift`, `TandemKitProfileDetailView.swift`, `TandemKitSegmentEditView.swift`
- New: `TandemKitProfilesViewModel.swift`
- Wire: `TandemPumpManager` methods for all 6 IDP control messages

#### New Section: "Delivery Limits" (after Profiles)

```
[Delivery Limits]
├── Max Basal Rate: 2.5 U/hr       ← tap to edit (SetMaxBasalLimitRequest)
│   └── [Picker: 1.0 – 15.0 U/hr, 0.1 step]
│   └── Default: X.X U/hr          ← read from BasalLimitSettingsResponse.basalLimitDefault
└── Max Bolus: 25.0 U              ← tap to edit (SetMaxBolusLimitRequest)
    └── [Picker: 1.0 – 25.0 U, 0.5 step]
    └── Default: XX.X U            ← read from GlobalMaxBolusSettingsResponse.maxBolusDefault
```

**Implementation files:**
- New: `TandemKitDeliveryLimitsView.swift`, `TandemKitDeliveryLimitsViewModel.swift`
- Update: `TandemPumpManager` to expose standalone `setMaxBasalLimit()` / `setMaxBolusLimit()` methods
- Read: `BasalLimitSettingsRequest`, `GlobalMaxBolusSettingsRequest` during startup polling

#### New Sub-Section Under "Pump Status": Quick Bolus Settings

```
[Pump Status]
├── ... (existing items) ...
├── Quick Bolus Settings →          ← NavigationLink to sub-screen
│   ├── Enabled: [Toggle]           ← (SetQuickBolusSettingsRequest)
│   ├── Mode: [Units | Carbs]       ← segmented control
│   └── Increment: [Picker]         ← depends on mode:
│       ├── Units mode: 0.5 U, 1.0 U, 2.0 U, 5.0 U
│       └── Carbs mode: 2g, 5g, 10g, 15g
```

**Implementation files:**
- New: `TandemKitQuickBolusSettingsView.swift`, `TandemKitQuickBolusSettingsViewModel.swift`
- Wire: `TandemPumpManager.setQuickBolusSettings()`
- Read: `PumpGlobalsRequest` fields

#### New Section: "CGM" (after Cartridge Operations)

```
[CGM]
├── CGM Status: Active / Inactive   ← read from CGMStatusRequest
├── Session State: [state]           ← read from CGMStatusRequest
├── Transmitter: [info]              ← read from CGMHardwareInfoRequest
│
├── Dexcom G6 →                      ← NavigationLink
│   ├── Transmitter ID: [XXXXXX]     ← editable text field (SetG6TransmitterIdRequest)
│   ├── Start Sensor Session          ← button + sensor code input (StartDexcomG6SensorSessionRequest)
│   └── Stop Sensor Session           ← button with confirmation (StopDexcomCGMSensorSessionRequest)
│
└── Dexcom G7 →                      ← NavigationLink
    ├── Pairing Code: [XXXXXXXX]     ← editable field (SetDexcomG7PairingCodeRequest)
    ├── Saved Code: [display]        ← read from GetSavedG7PairingCodeRequest
    └── Stop Sensor Session           ← button with confirmation (StopDexcomCGMSensorSessionRequest)
```

**Implementation files:**
- New: `TandemKitCGMView.swift`, `TandemKitCGMViewModel.swift`
- Wire: `TandemPumpManager` methods for CGM control messages
- Read: `CGMStatusRequest`, `CGMHardwareInfoRequest`, `GetG6TransmitterHardwareInfoRequest`, `GetSavedG7PairingCodeRequest` during startup

#### Under "Notifications" Section: Alert Snooze

```
[Notifications]
├── ... (existing items) ...
├── Alert Snooze →                   ← NavigationLink (or inline)
│   ├── Snooze Enabled: [Toggle]     ← (SetPumpAlertSnoozeRequest)
│   └── Snooze Duration: [10 | 20 min] ← picker, shown when enabled
```

**Implementation files:**
- Update: `TandemKitNotificationsViewModel` to add snooze management
- Or new: `TandemKitAlertSnoozeView.swift` if warranting a separate screen
- Wire: `TandemPumpManager.setAlertSnooze()`
- Read: `PumpGlobalsRequest` for current snooze state

#### Under "Actions" Section: Cancel Bolus + Find Pump

```
[Actions]
├── ... (existing items) ...
├── Cancel Bolus                     ← button, shown only during active bolus (CancelBolusRequest)
└── Find My Pump                     ← button (PlaySoundRequest)
```

**Implementation files:**
- Update: `TandemKitSettingsViewModel` to expose `cancelBolus()` and `playSound()`
- Wire: `TandemPumpManager.cancelBolus()` and `TandemPumpManager.playSound()`
- Read: `CurrentBolusStatusRequest` to gate cancel button visibility

#### In `TandemPumpManager.disconnect()`: Graceful Disconnect

```
Not a UI surface — wire DisconnectPumpRequest into the existing
TandemPumpManager.disconnect() flow before dropping the BLE connection.
```

**Implementation files:**
- Update: `TandemPumpManager.disconnect()` to send `DisconnectPumpRequest` before BLE teardown

---

## 6. Proposed Settings View Structure (Complete)

```
TandemKitSettingsView
├── [Header]
│   ├── Pump image
│   ├── Delivery status card
│   └── Reservoir status card
│
├── [Actions]
│   ├── Suspend / Resume delivery
│   ├── Stop temp rate (conditional)
│   ├── Cancel bolus (conditional)              ← NEW
│   ├── Find my pump                            ← NEW
│   └── Refresh pump status
│
├── [Notifications]
│   ├── View Notifications → (badge count)
│   ├── Auto-Acknowledge Basal Alerts toggle
│   └── Alert Snooze Settings →                 ← NEW
│       ├── Snooze Enabled toggle
│       └── Snooze Duration picker
│
├── [Pump Status]
│   ├── Control-IQ: Enabled/Disabled
│   ├── User Mode: Standard/Sleep/Exercise
│   ├── Temp Rate details (if active)
│   ├── Insulin Type →
│   ├── Sound Settings →
│   └── Quick Bolus Settings →                  ← NEW
│       ├── Enabled toggle
│       ├── Mode: Units / Carbs
│       └── Increment picker
│
├── [Profiles]                                  ← NEW SECTION
│   ├── Active Profile: "Name" (tap to switch)
│   ├── Profile 1 →
│   │   ├── Name (editable)
│   │   ├── Insulin Duration
│   │   ├── Carb Entry mode
│   │   └── Time Segments →
│   │       ├── Segment rows (tap to edit)
│   │       └── [+ Add Segment]
│   ├── Profile 2 →
│   │   └── ...
│   └── [+ Create Profile]
│
├── [Delivery Limits]                           ← NEW SECTION
│   ├── Max Basal Rate: X.X U/hr (tap to edit)
│   └── Max Bolus: XX.X U (tap to edit)
│
├── [CGM]                                       ← NEW SECTION
│   ├── CGM Status display
│   ├── Dexcom G6 →
│   │   ├── Transmitter ID (editable)
│   │   ├── Start Sensor Session
│   │   └── Stop Sensor Session
│   └── Dexcom G7 →
│       ├── Pairing Code (editable)
│       └── Stop Sensor Session
│
├── [Cartridge Operations]
│   ├── Change Cartridge →
│   ├── Fill Tubing →
│   └── Fill Cannula →
│
├── [Pump Time]
│   ├── Current pump time
│   └── Sync pump time
│
└── [Additional]
    ├── Silent Tones toggle
    ├── Share logs
    └── Delete pump
```

---

## 7. Implementation Priority

### Phase 1 — High Priority (Core Pump Configuration)

| Gap | New Files | Effort |
|---|---|---|
| **Delivery Limits** | `TandemKitDeliveryLimitsView`, `TandemKitDeliveryLimitsViewModel` | Small — messages already partially wired |
| **Cancel Bolus** | Update `TandemKitSettingsViewModel` | Small — single button + gating logic |
| **Graceful Disconnect** | Update `TandemPumpManager.disconnect()` | Small — one message call |

### Phase 2 — High Priority (Profile Management)

| Gap | New Files | Effort |
|---|---|---|
| **Profile Management** | `TandemKitProfilesView`, `TandemKitProfileDetailView`, `TandemKitSegmentEditView`, `TandemKitProfilesViewModel` | Large — 6 control messages, complex UI with list/detail/edit flows |

### Phase 3 — Medium Priority (CGM + Quick Bolus)

| Gap | New Files | Effort |
|---|---|---|
| **CGM Management** | `TandemKitCGMView`, `TandemKitCGMViewModel` | Medium — 4 control messages, text input + session management |
| **Quick Bolus Settings** | `TandemKitQuickBolusSettingsView`, `TandemKitQuickBolusSettingsViewModel` | Small — single screen with toggle + pickers |

### Phase 4 — Low Priority (Polish)

| Gap | New Files | Effort |
|---|---|---|
| **Alert Snooze** | Update `TandemKitNotificationsViewModel` or new view | Small |
| **Find My Pump** | Update `TandemKitSettingsViewModel` | Trivial — single button |
| **Remote BG / Carb Entry** | New views if standalone, or integrate into bolus flow | Medium — depends on bolus calculator integration |

---

## 8. Message Cross-Reference (Read ↔ Write Pairs)

| Setting Domain | Read (CurrentStatus) | Write (Control) | Both in TandemCore? |
|---|---|---|---|
| Profiles — list | `ProfileStatusRequest` | `CreateIDPRequest`, `DeleteIDPRequest` | ✅ |
| Profiles — settings | `IDPSettingsRequest` | `SetIDPSettingsRequest`, `RenameIDPRequest` | ✅ |
| Profiles — segments | `IDPSegmentRequest` | `SetIDPSegmentRequest` | ✅ |
| Active profile | `ProfileStatusRequest` | `SetActiveIDPRequest` | ✅ |
| Max basal rate | `BasalLimitSettingsRequest` | `SetMaxBasalLimitRequest` | ✅ |
| Max bolus | `GlobalMaxBolusSettingsRequest` | `SetMaxBolusLimitRequest` | ✅ |
| Quick bolus | `PumpGlobalsRequest` | `SetQuickBolusSettingsRequest` | ✅ |
| Pump sounds | `PumpGlobalsRequest` | `SetPumpSoundsRequest` | ✅ |
| Alert snooze | `PumpGlobalsRequest` | `SetPumpAlertSnoozeRequest` | ✅ |
| CGM status | `CGMStatusRequest` | `Start/StopDexcomCGMSensorSessionRequest` | ✅ |
| G6 transmitter | `GetG6TransmitterHardwareInfoRequest` | `SetG6TransmitterIdRequest` | ✅ |
| G7 pairing code | `GetSavedG7PairingCodeRequest` | `SetDexcomG7PairingCodeRequest` | ✅ |
| Pump time | `TimeSinceResetRequest` | `ChangeTimeDateRequest` | ✅ |
| Control-IQ on/off | `ControlIQInfoV2Request` | `ChangeControlIQSettingsRequest` | ✅ |

**Key finding:** Every single read/write message pair is already defined in `Sources/TandemCore/Messages/`. No new message types need to be created — only manager wiring and UI surfaces.

---

## 9. Safety Considerations

### Messages Flagged `modifiesInsulinDelivery` in pumpX2

These require extra safety gating (confirmation dialogs, `PumpStateSupplier.enableActionsAffectingInsulinDelivery` checks):

- `CreateIDPRequest` — creating a profile can affect delivery if made active
- `DeleteIDPRequest` — deleting a profile could disrupt delivery
- `RenameIDPRequest` — flagged in pumpX2 but low actual risk
- `SetActiveIDPRequest` — switching profiles immediately changes basal rates
- `SetTempRateRequest` — already gated
- `StopTempRateRequest` — already gated
- `InitiateBolusRequest` — already gated
- `SuspendPumpingRequest` — already gated
- `ResumePumpingRequest` — already gated
- `EnterFillTubingModeRequest` — already gated
- `FillCannulaRequest` — already gated

### Recommended Safety UI Patterns

1. **Delivery Limits:** Show current + default values, require explicit confirmation before lowering limits
2. **Profile Switching:** Confirmation dialog showing the new profile's current-segment basal rate
3. **Profile Deletion:** Prevent deleting the active profile; require confirmation with profile name
4. **CGM Session Start/Stop:** Confirmation dialog; stopping a session has clinical implications
5. **Cancel Bolus:** Prominent button only visible during active bolus; show delivered vs remaining volume
