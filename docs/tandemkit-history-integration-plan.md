# TandemKit Pump History Integration Plan

This document provides a detailed, actionable plan for integrating pump-owned history log fetching into TandemKit, following the patterns established by the Medtronic driver while accounting for Tandem-specific protocol differences.

## Current State (What's Already Implemented)

### ✅ Complete: Low-Level Protocol Layer

**Message Definitions** (`Sources/TandemCore/Messages/HistoryLog/`):
- 50+ fully-implemented history log types with complete parsing/serialization
- All critical insulin delivery events:
  - `BolusActivatedHistoryLog`, `BolusCompletedHistoryLog`, `BolusDeliveryHistoryLog`
  - `TempRateActivatedHistoryLog`, `TempRateCompletedHistoryLog`
  - `BasalRateChangeHistoryLog`, `BasalDeliveryHistoryLog`
  - `PumpingSuspendedHistoryLog`, `PumpingResumedHistoryLog`
- CGM and physiological data: `CGMHistoryLog`, `BGHistoryLog`, `CarbEnteredHistoryLog`
- Alerts and system events: `AlarmActivatedHistoryLog`, `AlertActivatedHistoryLog`
- Time reconciliation events: `DateChangeHistoryLog`, `TimeChangedHistoryLog`
- Cartridge management: `CartridgeFilledHistoryLog`, `CannulaFilledHistoryLog`, `TubingFilledHistoryLog`
- Control-IQ events: `ControlIQPcmChangeHistoryLog`, `ControlIQUserModeChangeHistoryLog`

**Base Infrastructure**:
- `HistoryLog` base class: 26-byte fixed-size record with `typeId`, `pumpTimeSec`, `sequenceNum`
- `HistoryLogParser.parse(_:)`: Type-based dispatch to concrete HistoryLog subclasses
- `UnknownHistoryLog`: Safe fallback for unrecognized event types

**Fetch Protocol**:
- `HistoryLogStatusRequest/Response` (OpCode 58/59): Get metadata (`numEntries`, `firstSequenceNum`, `lastSequenceNum`)
- `HistoryLogRequest/Response` (OpCode 60/61): Request history starting from sequence number
- `HistoryLogStreamResponse` (OpCode -127): Stream-based delivery of parsed `[HistoryLog]` objects

### ❌ Missing: Manager Integration Layer

**No TandemPumpManager Integration**:
- No `fetchPumpHistory()` method
- No conversion from `HistoryLog` → `DoseEntry`/`NewPumpEvent`
- No calls to `pumpManagerDelegate.pumpManager(_:hasNewPumpEvents:...)`
- History not included in `PumpTelemetryScheduler` scheduled tasks

**No Timestamp Reconciliation**:
- `DateChangeHistoryLog` and `TimeChangedHistoryLog` exist but not processed
- No clock-change delta tracking
- No pump-time → UTC conversion utilities

**No Reconciliation with Pending Doses**:
- Locally-tracked pending doses not matched against pump history
- No deduplication or "reconciled" marking

---

## Tandem-Specific Protocol Considerations

### 1. Sequence-Based Fetching (vs. Page-Based Medtronic)
- **Medtronic**: Downloads 1024-byte "pages" (page 0, 1, 2...) and walks backwards
- **Tandem**: Requests by sequence number (`startLog`, `numberOfLogs`) where sequence numbers increment chronologically
- **Implication**: Fetch from oldest-unseen sequence forward (not reverse like Medtronic)

### 2. Stream Responses
- After `HistoryLogRequest`, pump replies with `HistoryLogResponse(status, streamId)`
- Pump then sends one or more `HistoryLogStreamResponse` messages over the `HISTORY_LOG_CHARACTERISTICS` characteristic
- Stream responses contain pre-parsed `[HistoryLog]` objects (already typed)

### 3. Fixed 26-Byte Records
- All history entries are exactly 26 bytes
- No variable-length parsing required (unlike Medtronic)
- CRC/validation already handled by BLE transport layer

### 4. Multi-Part Events Require Pairing
- **Bolus**: `BolusActivatedHistoryLog` + `BolusCompletedHistoryLog` (match by `bolusId`)
- **Temp Basal**: `TempRateActivatedHistoryLog` + `TempRateCompletedHistoryLog` (match by `tempRateId`)
- **Suspend/Resume**: `PumpingSuspendedHistoryLog` + `PumpingResumedHistoryLog` (pair by timestamp proximity)

### 5. Clock Changes
- `DateChangeHistoryLog`: Records `datePrior`, `dateAfter`, `rawRTCTime`
- `TimeChangedHistoryLog`: Records time adjustments
- Must apply deltas to subsequent events to maintain UTC alignment

---

## Implementation Plan (8 Phases)

### Phase 1: Timestamp Reconciliation Utilities

**Goal**: Convert pump timestamps to UTC and handle clock changes.

**Files to Create**:
- `Sources/TandemKit/PumpManager/History/HistoryTimestampReconciler.swift`

**Key Components**:

```swift
/// Tracks clock-change deltas and converts pump time to UTC.
class HistoryTimestampReconciler {
    private var clockChangeDeltas: [(sequenceNum: UInt32, deltaSec: Int)] = []

    /// Add a clock change event from DateChangeHistoryLog or TimeChangedHistoryLog
    func recordClockChange(at sequenceNum: UInt32, deltaSec: Int)

    /// Convert pump timestamp to UTC accounting for clock changes
    func utcDate(pumpTimeSec: UInt32, sequenceNum: UInt32, timeZone: TimeZone) -> Date

    /// Detect large forward jumps that invalidate chronological ordering
    func isValidTimestamp(_ pumpTimeSec: UInt32, sequenceNum: UInt32) -> Bool
}
```

**Acceptance Criteria**:
- [x] Apply clock-change deltas to timestamps after the delta event
- [ ] Reject history if irreversible clock alarm/factory reset detected
- [x] Handle timezone conversions using system TimeZone
- [x] Detect forward jumps > 24 hours and flag as suspicious
- [x] Unit tests covering clock-forward, clock-backward, and DST transitions

**Progress (2026-01-04)**:
- Added DST and backward-clock unit tests for `HistoryTimestampReconciler` to validate timezone offsets and negative deltas.
- Implemented `HistoryToDoseMapper` skeleton (Phase 3) to map bolus/temp basal/suspend/resume/prime/alarm logs to LoopKit `NewPumpEvent` while honoring clock-change deltas.

---

### Phase 2: History Log Deduplication

**Goal**: Prevent duplicate entries across multiple fetches.

**Files to Create**:
- `Sources/TandemKit/PumpManager/History/HistoryDeduplicator.swift`

**Key Components**:

```swift
/// Tracks seen sequence numbers to prevent duplicate processing.
class HistoryDeduplicator {
    private var seenSequenceNumbers = Set<UInt32>()

    /// Check if a sequence number has been processed
    func isSeen(_ sequenceNum: UInt32) -> Bool

    /// Mark a sequence number as processed
    func markSeen(_ sequenceNum: UInt32)

    /// Filter a list of HistoryLog entries to only unseen ones
    func filterUnseen(_ logs: [HistoryLog]) -> [HistoryLog]

    /// Persist seen sequence numbers to disk for cross-session dedup
    func persist(to path: URL) throws
    func restore(from path: URL) throws
}
```

**Acceptance Criteria**:
- [x] Deduplicate by `sequenceNum` (unique identifier)
- [x] Handle overlapping fetch ranges
- [x] Persist deduplication state across app restarts
- [x] Unit tests with overlapping/duplicate sequence numbers

**Progress (2026-01-03)**:
- Implemented `HistoryDeduplicator` with in-memory set, unseen filtering, and JSON persistence helpers.
- Added unit tests covering overlap filtering and persistence/restore flow.

---

### Phase 3: Domain Mapping (HistoryLog → DoseEntry/NewPumpEvent)

**Goal**: Transform Tandem history logs into LoopKit domain objects.

**Files to Create**:
- `Sources/TandemKit/PumpManager/History/HistoryToDoseMapper.swift`

**Key Components**:

```swift
/// Maps Tandem HistoryLog events to LoopKit DoseEntry and NewPumpEvent.
class HistoryToDoseMapper {
    /// Convert a list of HistoryLog entries to NewPumpEvent objects
    func mapToEvents(
        _ logs: [HistoryLog],
        reconciler: HistoryTimestampReconciler,
        insulinType: InsulinType?,
        timeZone: TimeZone
    ) -> [NewPumpEvent]

    /// Pair multi-part events (bolus activated/completed, temp basal activated/completed)
    private func pairBolusEvents(_ logs: [HistoryLog]) -> [(activated: BolusActivatedHistoryLog, completed: BolusCompletedHistoryLog?)]
    private func pairTempBasalEvents(_ logs: [HistoryLog]) -> [(activated: TempRateActivatedHistoryLog, completed: TempRateCompletedHistoryLog?)]
    private func pairSuspendResumeEvents(_ logs: [HistoryLog]) -> [(suspended: PumpingSuspendedHistoryLog, resumed: PumpingResumedHistoryLog?)]
}
```

**Event Mapping Strategy**:

| HistoryLog Type | Maps To | Notes |
|-----------------|---------|-------|
| `BolusActivatedHistoryLog` + `BolusCompletedHistoryLog` | `DoseEntry(.bolus)` | Pair by `bolusId`, calculate duration from timestamps, use `insulinDelivered` if completed |
| `TempRateActivatedHistoryLog` + `TempRateCompletedHistoryLog` | `DoseEntry(.tempBasal)` | Pair by `tempRateId`, duration from `duration` field or completion time |
| `BasalRateChangeHistoryLog` | `DoseEntry(.basal)` | Scheduled basal rate change |
| `PumpingSuspendedHistoryLog` | `DoseEntry(.suspend)` | Suspension event |
| `PumpingResumedHistoryLog` | `DoseEntry(.resume)` | Resumption event |
| `CartridgeFilledHistoryLog`, `CannulaFilledHistoryLog`, `TubingFilledHistoryLog` | `NewPumpEvent(.prime)` | Prime events, no dose |
| `AlarmActivatedHistoryLog`, `AlertActivatedHistoryLog` | `NewPumpEvent(.alarm)` | Alert events, no dose |
| `DateChangeHistoryLog`, `TimeChangedHistoryLog` | _(reconciler state)_ | Not surfaced as events, used for timestamp reconciliation |

**Bolus Duration Calculation**:
```swift
// For paired bolus events:
let duration = completedLog.pumpTimeSec - activatedLog.pumpTimeSec
let deliveredUnits = completedLog.insulinDelivered
let requestedUnits = activatedLog.bolusSize

// If no completion event, mark as isMutable=true
```

**Temp Basal Handling**:
```swift
// From TempRateActivatedHistoryLog:
let percentOfScheduled = log.percent // e.g., 150.0 = 150%
let durationMinutes = log.duration
let scheduledRate = getCurrentScheduledBasalRate(at: log.pumpTimeSec)
let actualRate = scheduledRate * (percentOfScheduled / 100.0)

// DoseEntry:
DoseEntry(
    type: .tempBasal,
    startDate: utcDate,
    endDate: utcDate.addingTimeInterval(durationMinutes * 60),
    value: actualRate,
    unit: .unitsPerHour,
    scheduledBasalRate: HKQuantity(unit: .internationalUnitsPerHour(), doubleValue: scheduledRate),
    ...
)
```

**Acceptance Criteria**:
- [ ] Map all insulin-affecting events (bolus, temp basal, suspend/resume)
- [ ] Pair multi-part events by ID and validate pairing
- [ ] Calculate durations correctly (bolus delivery time, temp basal runtime)
- [ ] Set `isMutable=true` for activated events without completion
- [ ] Annotate with `insulinType` when available
- [ ] Tag prime/rewind events for reservoir continuity
- [ ] Unit tests with fixtures for each event type pairing

---

### Phase 4: Pending Dose Reconciliation

**Goal**: Match locally-tracked pending doses against pump history to mark as reconciled.

**Files to Modify**:
- `Sources/TandemKit/PumpManager/TandemPumpManagerState.swift` (add pending dose tracking)
- `Sources/TandemKit/PumpManager/History/HistoryReconciler.swift` (new file)

**Key Components**:

```swift
/// State structure for tracking pending doses
struct PendingDose: Codable, Equatable {
    let syncIdentifier: String
    let dose: DoseEntry
    let requestedAt: Date
}

/// Reconcile pending doses with pump history
class HistoryReconciler {
    /// Match pending doses against history events, return reconciled events
    func reconcile(
        pendingDoses: [PendingDose],
        historyEvents: [NewPumpEvent]
    ) -> (
        reconciledEvents: [NewPumpEvent],
        stillPending: [PendingDose]
    )
}
```

**Reconciliation Logic**:
1. For each pending dose, search history for matching event by:
   - Event type (bolus, temp basal, suspend)
   - Timestamp proximity (±5 minutes tolerance)
   - Dose amount matching (±0.05U for bolus, ±0.01U/hr for basal)
2. If matched: mark dose as reconciled, remove from pending queue
3. If not matched and >24 hours old: mark as uncertain delivery, report error
4. Annotate reconciled events with `syncIdentifier` from pending dose

**State Storage**:
```swift
// In TandemPumpManagerState.rawValue:
"pendingDoses": [PendingDose]
"lastHistoryReconciliation": Date
```

**Acceptance Criteria**:
- [ ] Track pending boluses issued by `enactBolus()`
- [ ] Track pending temp basals issued by `enactTempBasal()`
- [ ] Match by type, timestamp, and amount with tolerance
- [ ] Remove reconciled doses from pending queue
- [ ] Surface uncertain delivery errors for old unreconciled doses
- [ ] Persist pending doses across app restarts
- [ ] Unit tests with matching/non-matching scenarios

---

### Phase 5: History Fetch Session Logic

**Goal**: Implement the fetch orchestration that requests history from the pump.

**Files to Create**:
- `Sources/TandemKit/PumpManager/History/HistoryFetchSession.swift`

**Key Components**:

```swift
/// Orchestrates a single history fetch session.
class HistoryFetchSession {
    let transport: PumpMessageTransport
    let pumpComm: PumpComm
    let startSequence: UInt32?
    let maxEntries: Int

    /// Execute the fetch and return parsed logs
    func fetch() async throws -> [HistoryLog]
}
```

**Fetch Flow**:

```
1. Send HistoryLogStatusRequest
   ↓
2. Receive HistoryLogStatusResponse(numEntries, firstSequenceNum, lastSequenceNum)
   ↓
3. Determine fetch range:
   - If startSequence provided: use it
   - Else: use firstSequenceNum (oldest available)
   ↓
4. Send HistoryLogRequest(startLog=startSequence, numberOfLogs=min(maxEntries, 100))
   ↓
5. Receive HistoryLogResponse(status, streamId)
   ↓
6. Collect HistoryLogStreamResponse messages matching streamId
   ↓
7. Combine all logs, return sorted by sequenceNum
```

**Stream Response Handling**:
- `HistoryLogStreamResponse` messages may arrive over multiple BLE notifications
- Match by `streamId` from `HistoryLogResponse`
- Combine `historyLogs` arrays from all stream responses
- Sort by `sequenceNum` to ensure chronological order

**Error Handling**:
- `status != 0` in `HistoryLogResponse`: throw specific error
- Unknown `HistoryLog.typeId`: use `UnknownHistoryLog` (don't fail)
- Timeout waiting for stream: retry once, then fail
- BLE disconnection: propagate error to caller for retry

**Acceptance Criteria**:
- [ ] Query status to get available sequence range
- [ ] Request history in batches of ≤100 logs
- [ ] Collect and combine stream responses by `streamId`
- [ ] Sort results by `sequenceNum`
- [ ] Handle unknown event types gracefully
- [ ] Retry transient BLE errors
- [ ] Unit tests with mock transport

**Progress (2026-01-05)**:
- Added `HistoryFetchSession` to orchestrate status lookups, issue ranged history requests, and collect `HistoryLogStreamResponse` notifications until the expected number of records arrive or a timeout triggers.
- Pump manager now forwards history stream notifications to the active fetch session helper.
- Introduced unit tests for streamed collection, stream-id mismatch timeout handling, and start-range clamping.

---

### Phase 6: Manager-Level `fetchPumpHistory()` Integration

**Goal**: Expose delegate-driven history fetch in `TandemPumpManager`.

**Files to Modify**:
- `Sources/TandemKit/PumpManager/TandemPumpManager.swift`
- `Sources/TandemKit/PumpManager/TandemPumpManagerState.swift`

**New Manager Method**:

```swift
// In TandemPumpManager:

/// Fetch pump history since the last reconciliation and deliver to delegate.
public func fetchPumpHistory(
    since startDate: Date? = nil,
    completion: @escaping (Error?) -> Void
) {
    guard let transport = transportLock.value else {
        completion(PumpManagerError.connection(nil))
        return
    }

    historyFetchQueue.async { [weak self] in
        guard let self = self else { return }

        do {
            // 1. Determine start sequence from state or delegate-provided date
            let startSequence = self.getStartSequence(for: startDate)

            // 2. Fetch raw history logs
            let session = HistoryFetchSession(
                transport: transport,
                pumpComm: self.pumpComm,
                startSequence: startSequence,
                maxEntries: 500
            )
            let logs = try await session.fetch()

            // 3. Deduplicate
            let unseen = self.deduplicator.filterUnseen(logs)

            // 4. Reconcile timestamps
            unseen.forEach { log in
                if let clockChange = log as? DateChangeHistoryLog {
                    let delta = Int(clockChange.dateAfter) - Int(clockChange.datePrior)
                    self.reconciler.recordClockChange(at: log.sequenceNum, deltaSec: delta)
                }
            }

            // 5. Map to NewPumpEvent
            let events = self.mapper.mapToEvents(
                unseen,
                reconciler: self.reconciler,
                insulinType: self.state.insulinType,
                timeZone: self.state.timeZone
            )

            // 6. Reconcile with pending doses
            let (reconciledEvents, stillPending) = self.historyReconciler.reconcile(
                pendingDoses: self.state.pendingDoses,
                historyEvents: events
            )

            // 7. Update state
            self.state.pendingDoses = stillPending
            self.state.lastHistoryReconciliation = Date()
            if let lastLog = unseen.last {
                self.state.lastHistorySequenceNum = lastLog.sequenceNum
            }
            self.notifyPumpManagerDelegateDidUpdateState()

            // 8. Deliver events to delegate
            guard let delegate = self.pumpManagerDelegate, let queue = self.delegateQueue else {
                completion(nil)
                return
            }

            queue.async {
                delegate.pumpManager(
                    self,
                    hasNewPumpEvents: reconciledEvents,
                    lastReconciliation: self.state.lastHistoryReconciliation,
                    replacePendingEvents: true,
                    completion: completion
                )
            }

        } catch {
            self.log.error("History fetch failed: \(error)")
            completion(PumpManagerError.communication(error))
        }
    }
}

private func getStartSequence(for date: Date?) -> UInt32? {
    // If date provided, convert to approximate sequence
    // Else, use state.lastHistorySequenceNum + 1
    if let lastSeq = state.lastHistorySequenceNum {
        return lastSeq + 1
    }
    return nil // Will fetch from firstSequenceNum
}
```

**State Additions**:

```swift
// In TandemPumpManagerState:
var lastHistorySequenceNum: UInt32?
var lastHistoryReconciliation: Date?
var pendingDoses: [PendingDose] = []
```

**Acceptance Criteria**:
- [ ] Fetch history since last reconciliation or provided date
- [ ] Pass pending doses to reconciliation
- [ ] Call delegate with `hasNewPumpEvents`
- [ ] Update state with last sequence number and reconciliation time
- [ ] Handle errors and propagate to completion handler
- [ ] Integration test with mock delegate

---

### Phase 7: Scheduled History Fetching

**Goal**: Add periodic history fetch to telemetry scheduler.

**Files to Modify**:
- `Sources/TandemKit/PumpManager/Telemetry/PumpTelemetryScheduler.swift`
- `Sources/TandemKit/PumpManager/TandemPumpManager.swift` (setup scheduler)

**Changes**:

```swift
// In PumpTelemetryKind enum:
enum PumpTelemetryKind: CaseIterable {
    case reservoir
    case battery
    case basal
    case bolus
    case timeSinceReset
    case alerts
    case controlIQ
    case homeScreen
    case notifications
    case history  // <-- NEW
}

// In TandemPumpManager.setupTelemetryScheduler():
telemetryScheduler.schedule(kind: .history, interval: 300.0) { [weak self] in
    self?.fetchPumpHistory { error in
        if let error = error {
            self?.telemetryLogger.error("Scheduled history fetch failed: \(error)")
        }
    }
}
```

**Fetch Frequency**:
- Initial: Every 5 minutes (300s)
- Adjustable based on system load and BLE reliability
- Triggered immediately on reconnection via `triggerAll()`

**Acceptance Criteria**:
- [ ] Add `.history` to telemetry scheduler
- [ ] Fetch every 5 minutes during connected sessions
- [ ] Trigger on reconnection
- [ ] Log fetch successes/failures
- [ ] Integration test with mock scheduler

---

### Phase 8: Testing and Validation

**Goal**: Comprehensive test coverage for all history components.

**Test Files to Create**:
- `Tests/TandemKitTests/History/HistoryTimestampReconcilerTests.swift`
- `Tests/TandemKitTests/History/HistoryDeduplicatorTests.swift`
- `Tests/TandemKitTests/History/HistoryToDoseMapperTests.swift`
- `Tests/TandemKitTests/History/HistoryReconcilerTests.swift`
- `Tests/TandemKitTests/History/HistoryFetchSessionTests.swift`
- `Tests/TandemKitTests/TandemPumpManagerHistoryTests.swift`

**Unit Test Coverage**:

1. **Timestamp Reconciliation**:
   - [ ] Clock-forward delta applied to subsequent events
   - [ ] Clock-backward delta handled correctly
   - [ ] DST transitions
   - [ ] Large forward jump rejected
   - [ ] Factory reset detection

2. **Deduplication**:
   - [ ] Duplicate sequence numbers filtered
   - [ ] Overlapping fetch ranges
   - [ ] Persistence across restarts

3. **Domain Mapping**:
   - [ ] Bolus activated + completed → DoseEntry with correct duration
   - [ ] Bolus activated only → DoseEntry with isMutable=true
   - [ ] Temp basal pairing by tempRateId
   - [ ] Temp basal percent calculation (150% = 1.5x scheduled)
   - [ ] Suspend/resume pairing
   - [ ] Prime events tagged correctly
   - [ ] Alarm events without dose

4. **Reconciliation**:
   - [ ] Pending bolus matched by amount/time
   - [ ] Pending temp basal matched
   - [ ] Unmatched dose after 24h → uncertain delivery error
   - [ ] SyncIdentifier preservation

5. **Fetch Session**:
   - [ ] Status query + log request flow
   - [ ] Stream response collection
   - [ ] Retry on transient error
   - [ ] Unknown event type handling

6. **Integration**:
   - [ ] `fetchPumpHistory()` calls delegate with events
   - [ ] State updated with last sequence
   - [ ] Pending doses reconciled
   - [ ] Scheduled fetch triggered

**Fixtures Required**:
- Sample `HistoryLogStreamResponse` messages with:
  - Complete bolus lifecycle (activated → completed)
  - Incomplete bolus (activated only)
  - Temp basal with completion
  - Suspend/resume pair
  - Clock change event
  - Cartridge fill + cannula fill
  - Alarm activation
  - Unknown event type (typeId not in parser)

**Manual Hardware Testing**:
- [ ] Pair with real pump
- [ ] Issue bolus from Loop, verify appears in history
- [ ] Issue temp basal from Loop, verify appears in history
- [ ] Change pump time, verify clock-change handling
- [ ] Disconnect/reconnect, verify deduplication
- [ ] Observe scheduled fetch logs for 30 minutes

---

## Key Differences from Medtronic Implementation

| Aspect | Medtronic (MinimedKit) | Tandem (TandemKit) |
|--------|------------------------|---------------------|
| **Fetch Method** | Page-based (1024-byte pages) | Sequence-based (by `sequenceNum`) |
| **Iteration** | Reverse (newest → oldest) | Forward (oldest → newest) |
| **Record Size** | Variable per event type | Fixed 26 bytes |
| **Parsing** | Walk raw bytes, link auxiliary records | Pre-parsed by `HistoryLogParser` |
| **CRC Validation** | Per page in `HistoryPage` | BLE transport layer |
| **Response Type** | Synchronous page data | Async stream (`HistoryLogStreamResponse`) |
| **Unknown Events** | Throw error | Return `UnknownHistoryLog` |
| **Multi-Part Events** | Unabsorbed insulin linked to bolus | Pair by ID (`bolusId`, `tempRateId`) |

---

## File Structure Summary

```
Sources/TandemKit/PumpManager/History/
├── HistoryTimestampReconciler.swift       # Phase 1
├── HistoryDeduplicator.swift              # Phase 2
├── HistoryToDoseMapper.swift              # Phase 3
├── HistoryReconciler.swift                # Phase 4
└── HistoryFetchSession.swift              # Phase 5

Sources/TandemKit/PumpManager/
├── TandemPumpManager.swift                # Phase 6 (modify)
└── TandemPumpManagerState.swift           # Phase 4, 6 (modify)

Sources/TandemKit/PumpManager/Telemetry/
└── PumpTelemetryScheduler.swift           # Phase 7 (modify)

Tests/TandemKitTests/History/
├── HistoryTimestampReconcilerTests.swift  # Phase 8
├── HistoryDeduplicatorTests.swift         # Phase 8
├── HistoryToDoseMapperTests.swift         # Phase 8
├── HistoryReconcilerTests.swift           # Phase 8
└── HistoryFetchSessionTests.swift         # Phase 8

Tests/TandemKitTests/
└── TandemPumpManagerHistoryTests.swift    # Phase 8
```

---

## Implementation Checklist

### Progress Updates
- Implemented Phase 1 timestamp reconciliation utilities (`HistoryTimestampReconciler`) with unit coverage to validate clock change deltas, timezone conversion, and large-jump detection.
- Added Phase 2 deduplication helper and Phase 3 domain mapper with coverage for insulin events and clock-change adjustments; added mutable events for unpaired activations.
- Implemented Phase 4 pending dose reconciliation primitives (`PendingDose`, `HistoryReconciler`) with aging detection for uncertain deliveries and sync identifier propagation.
- Completed Phase 5 stream-based fetching and Phase 6 manager integration by wiring `fetchPumpHistory` through deduplication, timestamp reconciliation, domain mapping, and pending-dose matching with delegate delivery and persisted state updates.
 - Added Phase 5 retry handling for stream timeouts so history fetches automatically retry transient failures before surfacing errors.

### Phase 1: Timestamp Reconciliation
- [x] Create `HistoryTimestampReconciler.swift`
- [x] Implement clock-change delta tracking
- [x] Implement UTC conversion
- [x] Add validation for large time jumps
- [x] Write unit tests

### Phase 2: Deduplication
- [x] Create `HistoryDeduplicator.swift`
- [x] Implement sequence number tracking
- [x] Add persistence layer
- [x] Write unit tests

### Phase 3: Domain Mapping
- [x] Create `HistoryToDoseMapper.swift`
- [x] Implement bolus pairing and mapping
- [x] Implement temp basal pairing and mapping
- [x] Implement suspend/resume mapping
- [x] Implement prime/alarm event mapping
- [x] Write unit tests with fixtures

### Phase 4: Pending Dose Reconciliation
- [x] Add `PendingDose` to `TandemPumpManagerState`
- [x] Create `HistoryReconciler.swift`
- [x] Implement matching logic
- [x] Add uncertain delivery error handling
- [x] Write unit tests

### Phase 5: Fetch Session
- [x] Create `HistoryFetchSession.swift`
- [x] Implement status query
- [x] Implement log request
- [x] Implement stream response collection
- [x] Add error handling and retry
- [x] Write unit tests

### Phase 6: Manager Integration
- [x] Add `fetchPumpHistory()` to `TandemPumpManager`
- [x] Wire up all history components
- [x] Implement delegate callback
- [x] Add state persistence
- [x] Write integration tests

### Phase 7: Scheduled Fetching
- [ ] Add `.history` to `PumpTelemetryKind`
- [ ] Schedule periodic fetch
- [ ] Trigger on reconnection
- [ ] Add logging

### Phase 8: Testing
- [ ] Create test fixtures
- [ ] Write all unit tests
- [ ] Write integration tests
- [ ] Perform hardware testing
- [ ] Document known limitations

---

## Success Criteria

✅ **Core Functionality**:
1. Pump history is fetched every 5 minutes during connected sessions
2. All insulin-affecting events (bolus, temp basal, suspend/resume) are delivered to LoopKit
3. Pending doses are reconciled with pump history
4. Clock changes are handled correctly
5. Duplicate events are filtered

✅ **Safety**:
1. Uncertain delivery errors raised for unreconciled doses >24h old
2. Large clock jumps detected and flagged
3. Unknown event types logged but don't crash
4. BLE errors handled gracefully with retry

✅ **Testing**:
1. >80% code coverage for history components
2. All pairing scenarios tested (bolus, temp basal, etc.)
3. Integration tests with mock delegate
4. Manual hardware validation successful

✅ **Documentation**:
1. Architecture documented
2. Known limitations listed
3. Troubleshooting guide for clock-change issues

---

## Known Limitations and Future Work

1. **Basal Rate Schedule Access**: Domain mapping requires access to the current scheduled basal rate to convert temp basal percentages to absolute rates. This requires integrating with `BasalRateSchedule` from `TandemPumpManagerState`.

2. **Sequence Number to Date Mapping**: Converting a `Date` to a `sequenceNum` for targeted fetching requires either:
   - Storing a mapping from date ranges to sequence ranges
   - Or always fetching from the last known sequence

3. **Multi-Page Streaming**: If history exceeds 100 entries, multiple `HistoryLogRequest` calls may be needed. The current design fetches in single batches; pagination should be added for large backfills.

4. **Control-IQ Event Interpretation**: `ControlIQPcmChangeHistoryLog` and related events may affect dosing interpretation but are not yet mapped to LoopKit events.

5. **CGM Data**: `CGMHistoryLog` and `CgmDataSampleHistoryLog` exist but are not mapped to LoopKit's CGM surfaces (out of scope for pump history).

6. **Performance**: Fetching 500 events every 5 minutes may be excessive; adaptive fetch intervals based on pump activity should be considered.

---

## References

- **TandemKit Source**: `/home/user/TandemKit/Sources/TandemCore/Messages/HistoryLog/`
- **pumpX2 Java Reference**: https://github.com/jwoglom/pumpX2
- **LoopKit Protocol**: `/home/user/TandemKit/Sources/LoopKit/LoopKit.swift`
- **Medtronic Reference Design**: `docs/history-log-driver-design.md` (provided)
