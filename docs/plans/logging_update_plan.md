# TandemKit Logging Update Plan

**Status: ✅ IMPLEMENTED** (Commit 4159093)

## Objective
Update TandemKit to use a unified logging approach with file persistence, modeled after DanaKit and MedtrumKit's `OSLog.swift` implementations.

---

## Current State Analysis

### TandemKit's Existing Logging Infrastructure

**Two parallel systems:**
1. **OSLog extension** (`Sources/TandemCore/Common/OSLog.swift`)
   - Provides convenience methods on `OSLog`: `debug()`, `info()`, `default()`, `error()`
   - Uses subsystem `com.jwoglom.TandemKit`
   - Non-Apple platforms: stub struct with no-ops

2. **PumpLogger** (`Sources/TandemCore/Common/PumpLogger.swift`)
   - 7-level hierarchy: trace, debug, info, notice, warning, error, critical
   - Handler-based extensibility via `PumpLogging.setHandler()`
   - No file persistence by default

**Usage across codebase:**
- 27 Swift files with logging
- Mixed usage of `OSLog` and `PumpLogger`
- No file persistence currently implemented

### DanaKit/MedtrumKit Approach

Both use a single unified logger class with:
- OSLog for console output
- File-based persistence to Documents directory
- Daily log rotation (current + previous day)
- `getDebugLogs()` for retrieving log file URLs
- Automatic file/function/line number capture
- Conditional debug logging via compile flag

---

## Proposed Changes

### Phase 1: Create TandemLogger Class

**New file:** `Sources/TandemCore/Common/TandemLogger.swift`

```swift
import Foundation
#if canImport(os)
import os.log
#endif

public final class TandemLogger {
    private let category: String
    private let subsystem = "com.jwoglom.TandemKit"

    #if canImport(os)
    private let logger: os.Logger
    #endif

    public init(category: String) {
        self.category = category
        #if canImport(os)
        self.logger = os.Logger(subsystem: subsystem, category: category)
        #endif
    }

    // Logging methods with file persistence
    public func debug(_ message: String,
                      file: String = #file,
                      function: String = #function,
                      line: Int = #line)
    public func info(_ message: String, ...)
    public func warning(_ message: String, ...)
    public func error(_ message: String, ...)

    // File management
    public static func getDebugLogs() -> [URL]
    private static func writeToFile(_ entry: String)
    private static func rotateLogs()
}
```

**Key features:**
1. **File persistence** - Write to `Documents/tandemkit/tandemkit_log.txt`
2. **Daily rotation** - Move current to `tandemkit_log_prev.txt` at start of each day
3. **Source location capture** - Include file, function, line in log entries
4. **Conditional debug** - `TANDEMKIT_DEBUG_LOGGING` compile flag for verbose logs
5. **Cross-platform** - Stub file operations on Linux (keep console-only)

### Phase 2: File Persistence Implementation

**Log file structure:**
```
Documents/
  tandemkit/
    tandemkit_log.txt      # Current day's logs
    tandemkit_log_prev.txt # Previous day's logs
```

**Log entry format:**
```
[2026-01-04T12:34:56Z INFO] [BluetoothManager] Connected to peripheral (BluetoothManager.swift:connect():142)
```

**File management logic:**
1. On first write of day, check if current log is from previous day
2. If so, rename current → prev (overwrites old prev)
3. Create new current log with header timestamp
4. Append entries using `FileHandle` for efficiency

### Phase 3: Integrate with Existing PumpLogging Handler

Preserve backward compatibility by integrating with `PumpLogging`:

```swift
// In TandemLogger.log()
private func log(_ level: Level, _ message: String, file: String, function: String, line: Int) {
    let formattedMessage = formatMessage(message, file: file, function: function, line: line)

    // 1. Check handler (existing behavior)
    if PumpLogging.handle(level: level.toPumpLoggerLevel, label: category, message: formattedMessage) {
        return  // Handler suppressed the log
    }

    // 2. Console output via OSLog
    #if canImport(os)
    logger.log(level: level.osLogType, "\(formattedMessage)")
    #else
    print("[\(level)] [\(category)] \(formattedMessage)")
    #endif

    // 3. File persistence
    TandemLogger.writeToFile(formattedMessage, level: level, category: category)
}
```

### Phase 4: Migrate Existing Logging Calls

**Strategy:** Gradual migration, not big-bang refactor

1. **New code** - Use `TandemLogger` exclusively
2. **Key files first** - Migrate high-traffic logging files:
   - `TandemPumpManager.swift`
   - `PumpComm.swift`
   - `PumpCommSession.swift`
   - `BluetoothManager.swift`
   - `PeripheralManager.swift`
3. **Keep PumpLogger API** - Optionally wire `PumpLogger` to use `TandemLogger` internally

**Migration pattern:**
```swift
// Before (OSLog)
private let log = OSLog(category: "PumpComm")
log.info("Message %{public}@", value)

// Before (PumpLogger)
private let log = PumpLogger(label: "TandemKit.PumpComm")
log.info("Message \(value)")

// After (TandemLogger)
private let log = TandemLogger(category: "PumpComm")
log.info("Message \(value)")
```

### Phase 5: Add Public API for Log Retrieval

**New methods in TandemLogger:**
```swift
/// Returns URLs for current and previous log files
public static func getDebugLogs() -> [URL]

/// Returns combined log content as string (for sharing)
public static func getDebugLogContent() -> String

/// Clears all log files
public static func clearLogs()
```

**Integration point for TandemPumpManager:**
```swift
extension TandemPumpManager {
    /// Access debug logs for troubleshooting
    public var debugLogURLs: [URL] {
        TandemLogger.getDebugLogs()
    }
}
```

---

## Files to Modify

### New Files
| File | Purpose |
|------|---------|
| `Sources/TandemCore/Common/TandemLogger.swift` | New unified logger with persistence |

### Files to Update (Priority Order)

**High Priority (Core pump communication):**
| File | Current Logger | Changes |
|------|----------------|---------|
| `Sources/TandemKit/PumpManager/TandemPumpManager.swift` | PumpLogger | Migrate to TandemLogger |
| `Sources/TandemKit/PumpManager/PumpComm.swift` | OSLog | Migrate to TandemLogger |
| `Sources/TandemKit/PumpManager/PumpCommSession.swift` | PumpLogger | Migrate to TandemLogger |
| `Sources/TandemKit/PumpManager/TandemPump.swift` | OSLog | Migrate to TandemLogger |

**Medium Priority (BLE layer):**
| File | Current Logger | Changes |
|------|----------------|---------|
| `Sources/TandemBLE/Bluetooth/BluetoothManager.swift` | OSLog | Migrate to TandemLogger |
| `Sources/TandemBLE/Bluetooth/PeripheralManager.swift` | OSLog + PumpLogger | Migrate to TandemLogger |
| `Sources/TandemKit/PumpManager/PeripheralManagerTransport.swift` | OSLog + PumpLogger | Migrate to TandemLogger |

**Lower Priority (Auth/JPAKE):**
| File | Current Logger | Changes |
|------|----------------|---------|
| `Sources/TandemCore/Jpake/EcJpake.swift` | PumpLogger | Migrate to TandemLogger |
| `Sources/TandemCore/Jpake/JpakeAuthBuilder.swift` | PumpLogger | Migrate to TandemLogger |
| Various other files | Mixed | Migrate as touched |

### Files to Keep (Compatibility)
| File | Reason |
|------|--------|
| `Sources/TandemCore/Common/OSLog.swift` | Keep for backward compatibility during migration |
| `Sources/TandemCore/Common/PumpLogger.swift` | Keep and optionally wire to TandemLogger |

---

## Implementation Details

### Cross-Platform Considerations

```swift
#if canImport(os)
// Apple platforms: Full file persistence + OSLog
#else
// Linux: Console-only logging, skip file operations
// Alternative: Use Foundation file APIs if available
#endif
```

### Thread Safety

```swift
private static let fileQueue = DispatchQueue(label: "com.jwoglom.TandemKit.logger.file")

private static func writeToFile(_ entry: String) {
    fileQueue.async {
        // File operations here
    }
}
```

### Privacy Considerations

- Log files stored in app's Documents directory (user-accessible)
- Sensitive data (pairing codes, derived secrets) should use redaction
- Add `[REDACTED]` helper for sensitive values:
  ```swift
  log.info("Pairing with code: \(code.redacted)")
  ```

### Compile Flags

```swift
#if TANDEMKIT_DEBUG_LOGGING
public func debug(_ message: String, ...) {
    log(.debug, message, ...)
}
#else
public func debug(_ message: String, ...) {
    // No-op in release builds
}
#endif
```

---

## Testing Plan

1. **Unit tests for TandemLogger**
   - Log file creation
   - Daily rotation logic
   - `getDebugLogs()` returns correct URLs
   - Thread safety under concurrent writes

2. **Integration verification**
   - Existing PumpLogging.setHandler() still works
   - Logs appear in both console and file
   - No regression in logging behavior

3. **Manual validation**
   - Run CLI pairing flow, verify logs persist
   - Check log format is readable
   - Verify rotation works across days

---

## Rollout Strategy

1. **Phase 1** - Create `TandemLogger.swift` (non-breaking addition)
2. **Phase 2** - Add file persistence infrastructure
3. **Phase 3** - Migrate TandemPumpManager (highest visibility)
4. **Phase 4** - Migrate BLE layer files
5. **Phase 5** - Migrate remaining files opportunistically
6. **Phase 6** - Deprecate direct OSLog extension usage

---

## Summary of Changes

| Component | Action |
|-----------|--------|
| `TandemLogger` class | **Create** - New unified logger |
| File persistence | **Add** - Documents/tandemkit/ directory |
| Daily rotation | **Add** - Current + previous day logs |
| `getDebugLogs()` | **Add** - Public API for log retrieval |
| Existing `OSLog.swift` | **Keep** - Backward compatibility |
| Existing `PumpLogger.swift` | **Keep** - Wire to TandemLogger optionally |
| 27 logging files | **Migrate** - Gradually to TandemLogger |

---

## References

- DanaKit logging: https://github.com/bastiaanv/DanaKit/blob/dev/Common/OSLog.swift
- MedtrumKit logging: https://github.com/bastiaanv/MedtrumKit/blob/dev/Common/OSLog.swift
