# Three-way cross-reference: pumpX2 (Java) · TandemKit (Swift) · tconnectsync (Python) history logs

Field-by-field comparison of the three independent parsers of the Tandem pump history-log record format, with **pumpX2 treated as the reference implementation**:

- **Java (reference)**: [`pumpX2 .../response/historyLog`](https://github.com/jwoglom/pumpX2/tree/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog) — the upstream protocol definition.
- **Swift**: [`TandemKit Sources/TandemCore/Messages/HistoryLog`](https://github.com/jwoglom/TandemKit/tree/dev/Sources/TandemCore/Messages/HistoryLog) — a *port of pumpX2*.
- **Python**: [`tconnectsync/eventparser/events.py`](https://github.com/jwoglom/tconnectsync/blob/master/tconnectsync/eventparser/events.py) — *independently* derived from Tandem cloud exports.

Because Swift is a port of Java, a Swift-vs-Java difference is a **porting bug** in TandemKit (tagged `[PORT-BUG]`). Because Python is independently derived, a Python-vs-Java difference is an **interpretation divergence** (tagged `[PY-DIVERGENCE]`) — it may indicate a genuine format ambiguity or a bug on either side.

> This supersedes the earlier two-way (Python↔Swift) report; the Java reference column now adjudicates which side of each earlier disagreement matches upstream.

## Record layout & methodology

All three parsers consume a 26-byte event record: bytes 0–1 = event type ID (opCode), 2–5 = pump timestamp, 6–9 = sequence number, payload at bytes 10–25. Offsets are absolute within the record and directly comparable.

**Endianness is intentionally different and NOT reported as an inconsistency**: Java and Swift parse little-endian BLE payloads; Python parses big-endian cloud exports. Field-name differences alone are noted, not flagged.

Each opCode was analyzed by a dedicated agent reading all available sources. Of pumpX2's 133 event classes, 132 are event records compared here; opCode −127 (`HistoryLogStreamResponse`) is the BLE stream wrapper, not an event, and is excluded.

## Headline findings

- **25 `[PORT-BUG]` findings** across **16 event types** where TandemKit's Swift port diverges from the pumpX2 Java reference. These are the highest-value results — they are TandemKit bugs, not format ambiguities.
- **Severity across all 132 opCodes**: 37 major, 28 minor, 67 fully consistent.
- **59 opCodes** have all three parsers (Java+Swift+Python); the remaining 73 exist only in Java+Swift (tconnectsync has no parser for them).
- Most Java↔Swift pairs match exactly; the bulk of major findings on the three-way events are `[PY-DIVERGENCE]` — tconnectsync reading a different layout than upstream (carried over from the two-way report and now confirmed against Java).

## ⭐ TandemKit port bugs (Swift diverges from pumpX2 Java reference)

The actionable list for TandemKit. Grouped by whether the divergence changes decoded values (**decode bug**) or only omits a convenience enum/serializer present upstream (**completeness gap**).

### Decode-affecting port bugs (wrong or missing decoded values)

| opCode | Swift class | Divergence from Java reference |
|---:|---|---|
| 16 | `BGHistoryLog` | Swift BGHistoryLog init(cargo:) reads spare = Bytes.readUint32(raw, 22) where Java parse() reads selectedIOB = raw[22] (uint8), bgSourceType = raw[23] (uint8), spare = Bytes.readShort(raw, 24) (uint16). Swift drops selectedIOB and bgSourceType entirely and mis-decodes spare as a uint32 at offset 22 that concatenates all four bytes 22-25. |
| 16 | `BGHistoryLog` | Swift buildCargo serializes Bytes.toUint32(spare) at offset 22 in place of Java's selectedIOB byte @22 + bgSourceType byte @23 + firstTwoBytesLittleEndian(spare) @24. Swift is internally consistent with its own parser but produces/consumes a wire layout incompatible with the Java reference for bytes 22-25 (e.g. selectedIOB=1, bgSourceType=1, spare=0 encodes java bytes [01,01,00,00] but any Swift round-trip of that record yields spare=0x0101, selectedIOB/bgSourceType lost). |
| 244 | `AaEnableSettingChangeHistoryLog` | enabled interpretation: Swift init(cargo:) uses cargo[10] != 0 (nonzero-truthy Bool) while Java isEnabled() requires raw[10] == 1 exactly and getEnabled() exposes the raw int; for a raw byte value like 2 the two sides decode opposite enabled states, and Swift discards the raw value entirely. Byte offset and width are otherwise identical (uint8@10). |
| 372 | `CgmDataFsl2HistoryLog` | Swift's `init(cargo:)` never parses any payload field -- it only calls `super.init(cargo: cargo)`. None of Java's 7 fields (status uint16@10, type uint8@12, rate uint8@13, rssi uint8@15, value uint16@16, timestamp uint32@18, transmitterTimestamp uint32@22) have corresponding stored properties, computed accessors, or getters in the Swift class -- the entire payload of this history log type is unreachable from Swift consumers. |
| 372 | `CgmDataFsl2HistoryLog` | Swift's `buildCargo(pumpTimeSec:sequenceNum:)` only takes a timestamp and sequence number and produces a cargo whose payload bytes 10-25 are implicitly zero-filled by `HistoryLog.fillCargo` padding, whereas Java's `buildCargo(pumpTimeSec, sequenceNum, status, type, rate, rssi, value, timestamp, transmitterTimestamp)` explicitly serializes all 7 fields via `Bytes.firstTwoBytesLittleEndian`/`Bytes.toUint32`. Any Swift-constructed CgmDataFsl2HistoryLog record for testing/mocking silently loses all CGM payload data. |
| 399 | `DexcomG7CGMHistoryLog` | rssi: java raw[15] is a Java byte that auto-sign-extends into the int rssi field (range -128..127, matching real negative dBm RSSI readings), but Swift's `Int(cargo[15])` reads cargo[15] as an unsigned UInt8 and does NOT sign-extend, so Swift decodes the identical byte as 0..255 — e.g. a real -60 dBm reading (byte 0xC4) decodes as -60 in Java but 196 in Swift. This changes the decoded value for the common real-world case and is the highest-severity finding. |
| 399 | `DexcomG7CGMHistoryLog` | rate: same signedness bug as rssi — java raw[13] sign-extends into int rate (rate is documented as mg/dL/min/10, which can be negative), but Swift's `Int(cargo[13]))` treats it as unsigned 0..255. Numeric impact is smaller than rssi since \|rate\| rarely exceeds 127*0.1 mg/dL/min, but the type is still ported incorrectly. |
| 480 | `CgmDataFsl3HistoryLog` | Swift CgmDataFsl3HistoryLog.swift declares NO payload properties or parsing logic at all -- it only defines `typeId = 480` and a `buildCargo(pumpTimeSec:sequenceNum:)` that zero-fills the remaining 16 payload bytes via HistoryLog.fillCargo. Every Java field (status uint16@10, type uint8@12, rate uint8@13, rssi uint8@15, value uint16@16, timestamp uint32@18, transmitterTimestamp uint32@22) is unparsed in Swift, and there is no getter surface (getStatus/getType/getRate/getRssi/getValue/getTimestamp/getTransmitterTimestamp) mirroring Java's public accessors. This is a functional stub, not a port of Java's parse() logic. |

### Completeness-gap port bugs (correct decode, but missing upstream enum/serializer)

| opCode | Swift class | Gap vs Java reference |
|---:|---|---|
| 26 | `AlertClearedHistoryLog` | Swift AlertClearedHistoryLog has no buildCargo()/serializer counterpart to Java's static buildCargo (typeId 26 + uint32 alertId + uint32 faultLocatorData) and no getAlertResponseType() enum accessor — parse-only port; decoded values are unaffected. |
| 165 | `CgmHgaSettingsHistoryLog` | modifiedField: Swift port omits Java's nested ModifiedField enum (0=ENABLE, 1=THRESHOLD, 2=DURATION, 3=INVALID) and the getModifiedFieldEnum() accessor; raw uint16@16 decoding matches, so this is a label/typing gap only, not a value-changing bug. |
| 167 | `CgmRraSettingsHistoryLog` | modifiedField: Swift port omits Java's nested ModifiedField enum (ENABLE=0, THRESHOLD=1, DURATION=2, INVALID=3) and the getModifiedFieldEnum() accessor; Swift exposes only the raw uint16@16 as Int. Label/semantics gap only — decoded values are identical (java uint16@16 = swift uint16@16). |
| 169 | `CgmOorSettingsHistoryLog` | Swift port omits Java's ModifiedField enum (0=ENABLE,1=THRESHOLD,2=DURATION,3=INVALID) and the getModifiedFieldEnum() accessor; modifiedField is exposed only as a raw Int. Decoded values are unaffected — enum-label gap only. |
| 171 | `CgmAlertActivatedHistoryLog` | Completeness gap, not a decode error: Swift CgmAlertActivatedHistoryLog omits Java's typed alert accessor (Java exposes getAlert() = CGMAlertStatusResponse.CGMAlert.fromId(alertId); Swift exposes only raw alertId even though TandemCore has the CGMAlert enum in CGMAlertStatus.swift) and omits Java's buildCargo(pumpTimeSec, sequenceNum, alertId) serializer/convenience constructors. Parsing itself is byte-identical (uint32@10). |
| 172 | `CgmAlertClearedHistoryLog` | Swift CgmAlertClearedHistoryLog omits the derived `alert` enum field: Java parse() sets alert = CGMAlertStatusResponse.CGMAlert.fromId((int) alertId) and exposes getAlert(); Swift only exposes raw alertId (uint32@10) despite CGMAlertStatus.swift defining an equivalent CGMAlert enum. Raw decode is unaffected. |
| 172 | `CgmAlertClearedHistoryLog` | Swift CgmAlertClearedHistoryLog has no buildCargo()/serializer counterpart to Java's static buildCargo(pumpTimeSec, sequenceNum, alertId); the Swift class is parse-only, so it cannot round-trip a record like the Java reference. |
| 369 | `CgmAlertActivatedDexHistoryLog (historyLog)` | Swift's CgmAlertActivatedDexHistoryLog.swift provides only init(cargo:) with no buildCargo()/serializer counterpart to Java's static buildCargo(pumpTimeSec, sequenceNum, alertId) -- unlike ~116 of the other 137 Swift HistoryLog files, which do carry a buildCargo(). This Swift type can decode but not construct a record of this type, unlike Java. |
| 370 | `CgmAlertClearedDexHistoryLog` | Swift CgmAlertClearedDexHistoryLog.swift implements only `required init(cargo:)` and has no `buildCargo(pumpTimeSec:sequenceNum:alertId:)` static serializer, whereas Java provides `public static byte[] buildCargo(long pumpTimeSec, long sequenceNum, long alertId)` (lines 54-60) that mirrors the parse layout ({370,0} + toUint32(pumpTimeSec) + toUint32(sequenceNum) + toUint32(alertId)). This asymmetry means the Swift port cannot construct/serialize a CgmAlertClearedDexHistoryLog record (no round-trip test capability), unlike sibling ports such as AlertActivatedHistoryLog.swift or CgmAlertAckHistoryLog.swift which do implement matching buildCargo methods. |
| 370 | `CgmAlertClearedDexHistoryLog` | Swift exposes no decoded alert-enum equivalent to Java's `CGMAlertStatusResponse.CGMAlert alert` field / `getAlert()` accessor (populated via `CGMAlert.fromId((int) alertId)` in both the byte[]-based and the (pumpTimeSec,sequenceNum,alertId) constructors); Swift only stores the raw `alertId: UInt32` with no enum mapping at all, dropping label/semantic information that the port target is expected to carry. |
| 371 | `CgmAlertAckDexHistoryLog` | swift CgmAlertAckDexHistoryLog exposes only the raw `alertId: UInt32` and omits java's derived `alert: CGMAlertStatusResponse.CGMAlert` property (set via CGMAlert.fromId((int) alertId) in parse()), so the typed alert classification available in java (getAlert()) has no equivalent accessor in the Swift port. |
| 399 | `DexcomG7CGMHistoryLog` | DexcomG7CGMHistoryLog.swift has no buildCargo()/serializer and no full-field initializer, unlike Java's buildCargo() and unlike sibling Swift ports such as CgmDataGxHistoryLog.swift (which implements buildCargo(), a full initializer, and a description property). Only init(cargo:) exists, so the Swift type can be deserialized but not constructed/serialized — asymmetric with Java and with the rest of the Swift HistoryLog catalog. |
| 399 | `DexcomG7CGMHistoryLog` | Swift exposes only raw Int fields for glucoseValueStatus, algorithmState, cgmDataType, and egvInfoBitmask; it ports none of Java's nested enums/Set<> bitmask decoders (GlucoseValueStatus, AlgorithmState, CgmDataType, EgvInfo) or their fromId()/getX() accessors. |
| 460 | `CgmAlertActivatedFsl2HistoryLog` | Swift's CgmAlertActivatedFsl2HistoryLog only stores the raw `alertId: UInt32` and never resolves it to a decoded alert enum, whereas Java's class additionally stores `alert: CGMAlertStatusResponse.CGMAlert` via `CGMAlertStatusResponse.CGMAlert.fromId((int) alertId)` and exposes `getAlert()`. TandemKit does have an equivalent `CGMAlertStatusResponse.CGMAlert` enum (Sources/TandemCore/Messages/CurrentStatus/CGMAlertStatus.swift) but it is not used here, and that Swift enum exposes only `fromBitmask(_:)`, not a `fromId`/lookup-by-single-value counterpart to Java's `fromId`. Net effect: swift callers of this history log entry lose the semantic alert-name decoding that java provides for the same raw bytes. |
| 460 | `CgmAlertActivatedFsl2HistoryLog` | Java exposes a static `buildCargo(pumpTimeSec, sequenceNum, alertId)` serializer plus public constructors that use it, allowing this history-log entry type to be synthesized/round-tripped (e.g. for tests). TandemKit's Swift port has no buildCargo()/serializer counterpart for CgmAlertActivatedFsl2HistoryLog — in fact no HistoryLog subclass in Sources/TandemCore/Messages/HistoryLog defines a buildCargo() at all — so there is no way to construct a synthetic record and no internal-consistency check possible between a swift parser and swift serializer for this type. |
| 461 | `CgmAlertClearedFsl2HistoryLog (historyLog)` | Swift's CgmAlertClearedFsl2HistoryLog exposes only the raw `alertId: UInt32` with no equivalent to Java's `CGMAlertStatusResponse.CGMAlert.fromId((int) alertId)` enum lookup (Java's `alert`/`getAlert()`), so Swift callers lose the labeled/typed alert value that Java provides from the same bytes. |
| 480 | `CgmDataFsl3HistoryLog` | Swift's buildCargo signature only accepts (pumpTimeSec, sequenceNum) whereas Java's buildCargo(pumpTimeSec, sequenceNum, status, type, rate, rssi, value, timestamp, transmitterTimestamp) accepts and serializes all 7 payload fields; Swift can only ever construct a record with every payload byte hard-zeroed, so round-tripping a real CGM reading through Swift's constructor is impossible. |

## Summary of all 132 opCodes

| opCode | Java (reference) | Swift | Python | Severity | Port bugs | Total findings |
|---:|---|---|---|---|:---:|---:|
| 0 | `LogErasedHistoryLog` | `LogErasedHistoryLog` | — | 🟢 none | — | — |
| 2 | `TempRateActivatedHistoryLog` | `TempRateActivatedHistoryLog` | — | 🟢 none | — | — |
| 3 | `BasalRateChangeHistoryLog` | `BasalRateChangeHistoryLog` | `LidBasalRateChange` | 🔴 major | — | 4 |
| 4 | `AlertActivatedHistoryLog` | `AlertActivatedHistoryLog` | `LidAlertActivated` | 🟡 minor | — | 3 |
| 5 | `AlarmActivatedHistoryLog` | `AlarmActivatedHistoryLog` | `LidAlarmActivated` | 🟡 minor | — | 3 |
| 6 | `MalfunctionHistoryLog` | `MalfunctionHistoryLog` | `LidMalfunctionActivated` | 🟢 none | — | — |
| 7 | `MalfunctionAckHistoryLog` | `MalfunctionAckHistoryLog` | — | 🟢 none | — | — |
| 8 | `AlarmAckHistoryLog` | `AlarmAckHistoryLog` | — | 🟢 none | — | — |
| 11 | `PumpingSuspendedHistoryLog` | `PumpingSuspendedHistoryLog` | `LidPumpingSuspended` | 🔴 major | — | 6 |
| 12 | `PumpingResumedHistoryLog` | `PumpingResumedHistoryLog` | `LidPumpingResumed` | 🔴 major | — | 3 |
| 13 | `TimeChangedHistoryLog` | `TimeChangedHistoryLog` | `LidTimeChanged` | 🟢 none | — | — |
| 14 | `DateChangeHistoryLog` | `DateChangeHistoryLog` | `LidDateChanged` | 🟢 none | — | — |
| 15 | `TempRateCompletedHistoryLog` | `TempRateCompletedHistoryLog` | — | 🟡 minor | — | 1 |
| 16 | `BGHistoryLog` | `BGHistoryLog` | `LidBgReadingTaken` | 🔴 major | 2 | 11 |
| 20 | `BolusCompletedHistoryLog` | `BolusCompletedHistoryLog` | `LidBolusCompleted` | 🔴 major | — | 2 |
| 21 | `BolexCompletedHistoryLog` | `BolexCompletedHistoryLog` | `LidBolexCompleted` | 🔴 major | — | 3 |
| 25 | `ReminderActivatedHistoryLog` | `ReminderActivatedHistoryLog` | — | 🟢 none | — | — |
| 26 | `AlertClearedHistoryLog` | `AlertClearedHistoryLog` | `LidAlertCleared` | 🟡 minor | 1 | 2 |
| 27 | `AlertAckHistoryLog` | `AlertAckHistoryLog` | — | 🟢 none | — | — |
| 28 | `AlarmClearedHistoryLog` | `AlarmClearedHistoryLog` | `LidAlarmCleared` | 🟢 none | — | — |
| 29 | `ReminderDismissedHistoryLog` | `ReminderDismissedHistoryLog` | — | 🟢 none | — | — |
| 30 | `ReminderSnoozedHistoryLog` | `ReminderSnoozedHistoryLog` | — | 🟢 none | — | — |
| 31 | `CartridgeRemovedHistoryLog` | `CartridgeRemovedHistoryLog` | — | 🟢 none | — | — |
| 32 | `CartridgeInsertedHistoryLog` | `CartridgeInsertedHistoryLog` | — | 🟢 none | — | — |
| 33 | `CartridgeFilledHistoryLog` | `CartridgeFilledHistoryLog` | `LidCartridgeFilled` | 🟢 none | — | — |
| 36 | `UsbConnectedHistoryLog` | `UsbConnectedHistoryLog` | `LidUsbConnected` | 🟢 none | — | — |
| 37 | `UsbDisconnectedHistoryLog` | `UsbDisconnectedHistoryLog` | `LidUsbDisconnected` | 🟢 none | — | — |
| 41 | `ConfirmCartridgeFilledHistoryLog` | `ConfirmCartridgeFilledHistoryLog` | — | 🟢 none | — | — |
| 48 | `CarbEnteredHistoryLog` | `CarbEnteredHistoryLog` | `LidCarbsEntered` | 🟢 none | — | — |
| 53 | `ShelfModeHistoryLog` | `ShelfModeHistoryLog` | `LidShelfMode` | 🟡 minor | — | 2 |
| 55 | `BolusActivatedHistoryLog` | `BolusActivatedHistoryLog` | `LidBolusActivated` | 🔴 major | — | 4 |
| 57 | `IdpActionMsg2HistoryLog` | `IdpActionMsg2HistoryLog` | — | 🟡 minor | — | 1 |
| 59 | `BolexActivatedHistoryLog` | `BolexActivatedHistoryLog` | `LidBolexActivated` | 🔴 major | — | 3 |
| 60 | `DataLogCorruptionHistoryLog` | `DataLogCorruptionHistoryLog` | `LidDataLogCorruption` | 🔴 major | — | 2 |
| 61 | `CannulaFilledHistoryLog` | `CannulaFilledHistoryLog` | `LidCannulaFilled` | 🟡 minor | — | 1 |
| 63 | `TubingFilledHistoryLog` | `TubingFilledHistoryLog` | `LidTubingFilled` | 🟡 minor | — | 2 |
| 64 | `BolusRequestedMsg1HistoryLog` | `BolusRequestedMsg1HistoryLog` | `LidBolusRequestedMsg1` | 🔴 major | — | 3 |
| 65 | `BolusRequestedMsg2HistoryLog` | `BolusRequestedMsg2HistoryLog` | `LidBolusRequestedMsg2` | 🔴 major | — | 6 |
| 66 | `BolusRequestedMsg3HistoryLog` | `BolusRequestedMsg3HistoryLog` | `LidBolusRequestedMsg3` | 🔴 major | — | 2 |
| 67 | `UsbEnumeratedHistoryLog` | `UsbEnumeratedHistoryLog` | — | 🟢 none | — | — |
| 68 | `IdpTimeDependentSegmentHistoryLog` | `IdpTimeDependentSegmentHistoryLog` | — | 🟢 none | — | — |
| 69 | `IdpActionHistoryLog` | `TandemCore.IdpActionHistoryLog (Sources/TandemCore/Messages/HistoryLog/IdpActionHistoryLog.swift)` | — | 🟡 minor | — | 1 |
| 70 | `IdpBolusHistoryLog` | `TandemCore/Messages/HistoryLog/IdpBolusHistoryLog.swift IdpBolusHistoryLog` | — | 🟡 minor | — | 1 |
| 71 | `IdpListHistoryLog` | `IdpListHistoryLog` | — | 🟡 minor | — | 1 |
| 73 | `ParamChangePumpSettingsHistoryLog` | `ParamChangePumpSettingsHistoryLog` | — | 🔴 major | — | 1 |
| 74 | `ParamChangeGlobalSettingsHistoryLog` | `ParamChangeGlobalSettingsHistoryLog` | — | 🟢 none | — | — |
| 81 | `DailyBasalHistoryLog` | `DailyBasalHistoryLog` | `LidDailyBasal` | 🟡 minor | — | 3 |
| 82 | `FactoryResetHistoryLog` | `FactoryResetHistoryLog` | — | 🟢 none | — | — |
| 90 | `NewDayHistoryLog` | `NewDayHistoryLog` | `LidNewDay` | 🔴 major | — | 2 |
| 93 | `CorrectionDeclinedHistoryLog` | `CorrectionDeclinedHistoryLog` | — | 🟢 none | — | — |
| 96 | `ParamChangeReminderHistoryLog` | `ParamChangeReminderHistoryLog` | — | 🟢 none | — | — |
| 97 | `ParamChangeRemSettingsHistoryLog` | `ParamChangeRemSettingsHistoryLog` | — | 🟡 minor | — | 1 |
| 98 | `FillEstimateFinalHistoryLog` | `FillEstimateFinalHistoryLog` | — | 🟢 none | — | — |
| 99 | `ArmInitHistoryLog` | `ArmInitHistoryLog` | `LidArmInit` | 🟢 none | — | — |
| 140 | `PlgsPeriodicHistoryLog` | `PlgsPeriodicHistoryLog` | `LidPlgsPeriodic` | 🔴 major | — | 4 |
| 142 | `BasalIqSettingsChangeHistoryLog` | `BasalIqSettingsChangeHistoryLog` | — | 🟢 none | — | — |
| 151 | `CgmDataSampleHistoryLog` | `CgmDataSampleHistoryLog (Sources/TandemCore/Messages/HistoryLog/CgmDataSampleHistoryLog.swift)` | — | 🟡 minor | — | 1 |
| 156 | `CgmTransmitterIdHistoryLog` | `CgmTransmitterIdHistoryLog` | — | 🟢 none | — | — |
| 157 | `CgmAnnuSettingsHistoryLog` | `CgmAnnuSettingsHistoryLog` | — | 🟢 none | — | — |
| 160 | `CgmCalibrationHistoryLog` | `CgmCalibrationHistoryLog` | — | 🟢 none | — | — |
| 162 | `CgmStopSessionMsg1HistoryLog` | `CgmStopSessionMsg1HistoryLog (Sources/TandemCore/Messages/HistoryLog/CgmStopSessionMsg1HistoryLog.swift)` | — | 🟢 none | — | — |
| 163 | `CgmStopSessionMsg2HistoryLog` | `CgmStopSessionMsg2HistoryLog` | — | 🟢 none | — | — |
| 165 | `CgmHgaSettingsHistoryLog` | `Sources/TandemCore/Messages/HistoryLog/CgmHgaSettingsHistoryLog.swift (CgmHgaSettingsHistoryLog)` | — | 🟡 minor | 1 | 1 |
| 166 | `CgmLgaSettingsHistoryLog` | `Sources/TandemCore/Messages/HistoryLog/CgmLgaSettingsHistoryLog.swift (CgmLgaSettingsHistoryLog)` | — | 🟡 minor | — | 1 |
| 167 | `CgmRraSettingsHistoryLog` | `CgmRraSettingsHistoryLog (Sources/TandemCore/Messages/HistoryLog/CgmRraSettingsHistoryLog.swift)` | — | 🟡 minor | 1 | 1 |
| 168 | `CgmFraSettingsHistoryLog` | `CgmFraSettingsHistoryLog` | — | 🟡 minor | — | 1 |
| 169 | `CgmOorSettingsHistoryLog` | `CgmOorSettingsHistoryLog` | — | 🟡 minor | 1 | 1 |
| 171 | `CgmAlertActivatedHistoryLog` | `CgmAlertActivatedHistoryLog (/home/user/TandemKit/Sources/TandemCore/Messages/HistoryLog/CgmAlertActivatedHistoryLog.swift)` | `LidCgmAlertActivated` | 🔴 major | 1 | 3 |
| 172 | `CgmAlertClearedHistoryLog` | `CgmAlertClearedHistoryLog` | `LidCgmAlertCleared` | 🟡 minor | 2 | 3 |
| 173 | `CgmAlertAckHistoryLog` | `CgmAlertAckHistoryLog` | — | 🟡 minor | — | 1 |
| 187 | `CgmUnexpectedGeAlertHistoryLog` | `CgmUnexpectedGeAlertHistoryLog` | — | 🟢 none | — | — |
| 191 | `VersionInfoHistoryLog` | `VersionInfoHistoryLog` | `LidVersionInfo` | 🟢 none | — | 1 |
| 198 | `HypoMinimizerSuspendHistoryLog` | `HypoMinimizerSuspendHistoryLog (Sources/TandemCore/Messages/HistoryLog/HypoMinimizerSuspendHistoryLog.swift)` | — | 🟢 none | — | — |
| 199 | `HypoMinimizerResumeHistoryLog` | `HypoMinimizerResumeHistoryLog` | — | 🟢 none | — | — |
| 203 | `UpdateStatusHistoryLog` | `UpdateStatusHistoryLog (Sources/TandemCore/Messages/HistoryLog/UpdateStatusHistoryLog.swift)` | `LidUpdateStatus` | 🟡 minor | — | 3 |
| 210 | `CgmCalibrationGxHistoryLog` | `CgmCalibrationGxHistoryLog` | — | 🟢 none | — | — |
| 211 | `CgmDataGxHistoryLog` | `CgmDataGxHistoryLog` | — | 🟡 minor | — | 1 |
| 212 | `CgmStartSessionHistoryLog` | `CgmStartSessionHistoryLog (Sources/TandemCore/Messages/HistoryLog/CgmStartSessionHistoryLog.swift)` | `LidCgmStartSessionGx` | 🔴 major | — | 2 |
| 213 | `CgmJoinSessionHistoryLog` | `CgmJoinSessionHistoryLog` | `LidCgmJoinSessionGx` | 🔴 major | — | 3 |
| 214 | `CgmStopSessionHistoryLog` | `CgmStopSessionHistoryLog` | `LidCgmStopSessionGx` | 🟡 minor | — | 1 |
| 215 | `CgmInactiveGxHistoryLog` | `CgmInactiveGxHistoryLog` | — | 🟢 none | — | — |
| 216 | `CgmTransmitterIdGxHistoryLog` | `CgmTransmitterIdGxHistoryLog` | — | 🟢 none | — | — |
| 217 | `CgmStartSessionReqGxHistoryLog` | `CgmStartSessionReqGxHistoryLog` | — | 🟢 none | — | — |
| 218 | `CgmStopSessionReqGxHistoryLog` | `CgmStopSessionReqGxHistoryLog` | — | 🟢 none | — | — |
| 220 | `CgmTransmitterVersionGxHistoryLog` | `CgmTransmitterVersionGxHistoryLog` | — | 🟢 none | — | — |
| 229 | `ControlIQUserModeChangeHistoryLog` | `ControlIQUserModeChangeHistoryLog` | `LidAaUserModeChange` | 🔴 major | — | 5 |
| 230 | `ControlIQPcmChangeHistoryLog` | `ControlIQPcmChangeHistoryLog` | `LidAaPcmChange` | 🔴 major | — | 5 |
| 235 | `AaSleepScheduleChangeHistoryLog` | `AaSleepScheduleChangeHistoryLog (Sources/TandemCore/Messages/HistoryLog/AaSleepScheduleChangeHistoryLog.swift)` | — | 🟢 none | — | — |
| 238 | `AaDeliveryStatusChangeHistoryLog` | `AaDeliveryStatusChangeHistoryLog` | — | 🟢 none | — | — |
| 244 | `AaEnableSettingChangeHistoryLog` | `AaEnableSettingChangeHistoryLog` | — | 🟡 minor | 1 | 1 |
| 245 | `AaTdiSettingChangeHistoryLog` | `AaTdiSettingChangeHistoryLog (Sources/TandemCore/Messages/HistoryLog/AaTdiSettingChangeHistoryLog.swift)` | — | 🟢 none | — | — |
| 246 | `AaWeightSettingChangeHistoryLog` | `AaWeightSettingChangeHistoryLog` | — | 🟢 none | — | — |
| 256 | `DexcomG6CGMHistoryLog` | `DexcomG6CGMHistoryLog (and duplicate CGMHistoryLog, both typeId 256)` | `LidCgmDataGxb` | 🔴 major | — | 7 |
| 267 | `CgmSessionTypeChangeHistoryLog` | `CgmSessionTypeChangeHistoryLog` | — | 🟢 none | — | — |
| 279 | `BasalDeliveryHistoryLog` | `BasalDeliveryHistoryLog` | `LidBasalDelivery` | 🔴 major | — | 7 |
| 280 | `BolusDeliveryHistoryLog` | `BolusDeliveryHistoryLog (Sources/TandemCore/Messages/HistoryLog/BolusDeliveryHistoryLog.swift)` | `LidBolusDelivery` | 🔴 major | — | 9 |
| 283 | `WumpOcclusionDebugHistoryLog` | `WumpOcclusionDebugHistoryLog` | — | 🟢 none | — | — |
| 286 | `SnoozeActivatedHistoryLog` | `SnoozeActivatedHistoryLog` | — | 🟢 none | — | — |
| 288 | `AaAutoBolusRejectedHistoryLog` | `AaAutoBolusRejectedHistoryLog` | — | 🟢 none | — | — |
| 291 | `TipscReqPrimeCannulaHistoryLog` | `TipscReqPrimeCannulaHistoryLog` | — | 🟢 none | — | — |
| 301 | `WumpCartridgeFilledHistoryLog` | `WumpCartridgeFilledHistoryLog` | — | 🟢 none | — | — |
| 302 | `WumpCartridgeRemovedHistoryLog` | `WumpCartridgeRemovedHistoryLog` | — | 🟢 none | — | — |
| 307 | `VersionsAHistoryLog` | `VersionsAHistoryLog` | `LidVersionsA` | 🟡 minor | — | 2 |
| 313 | `DailyStatusHistoryLog` | `DailyStatusHistoryLog` | `LidAaDailyStatus` | 🟡 minor | — | 2 |
| 318 | `AAExerciseTimeChangeHistoryLog` | `AaExerciseTimeChangeHistoryLog` | — | 🟢 none | — | — |
| 319 | `AAExerciseChoiceChangeHistoryLog` | `AaExerciseChoiceChangeHistoryLog` | — | 🟢 none | — | — |
| 332 | `AATdiEstChangeHistoryLog` | `AaTdiEstChangeHistoryLog` | — | 🟢 none | — | — |
| 348 | `PrimeInprocessHistoryLog` | `PrimeInprocessHistoryLog` | — | 🟢 none | — | — |
| 367 | `CgmRejoinSessionHistoryLog` | `CgmRejoinSessionHistoryLog.swift` | — | 🟢 none | — | — |
| 368 | `CgmSensorTypeChangeHistoryLog` | `CgmSensorTypeChangeHistoryLog` | — | 🟢 none | — | — |
| 369 | `CgmAlertActivatedDexHistoryLog (historyLog)` | `CgmAlertActivatedDexHistoryLog.swift (Sources/TandemCore/Messages/HistoryLog)` | `LidCgmAlertActivatedDex (events.py, line 4505)` | 🔴 major | 1 | 4 |
| 370 | `CgmAlertClearedDexHistoryLog` | `CgmAlertClearedDexHistoryLog` | `LidCgmAlertClearedDex` | 🔴 major | 2 | 5 |
| 371 | `CgmAlertAckDexHistoryLog` | `CgmAlertAckDexHistoryLog` | `LidCgmAlertAckDex` | 🔴 major | 1 | 4 |
| 372 | `CgmDataFsl2HistoryLog` | `CgmDataFsl2HistoryLog` | `LidCgmDataFsl2` | 🔴 major | 2 | 5 |
| 390 | `CgmStartSensorReqG7HistoryLog` | `CgmStartSensorReqG7HistoryLog` | — | 🟢 none | — | — |
| 394 | `CgmJoinSessionG7HistoryLog` | `CgmJoinSessionG7HistoryLog` | `LidCgmJoinSessionG7` | 🟡 minor | — | 4 |
| 395 | `CgmPairingCodeG7HistoryLog` | `CgmPairingCodeG7HistoryLog` | — | 🟢 none | — | — |
| 399 | `DexcomG7CGMHistoryLog` | `DexcomG7CGMHistoryLog (Sources/TandemCore/Messages/HistoryLog/DexcomG7CGMHistoryLog.swift)` | `LidCgmDataG7` | 🔴 major | 4 | 14 |
| 404 | `CgmStartSessionFsl2HistoryLog` | `CgmStartSessionFsl2HistoryLog` | `LidCgmStartSessionFsl2` | 🔴 major | — | 3 |
| 405 | `CgmStopSessionFsl2HistoryLog` | `CgmStopSessionFsl2HistoryLog` | `LidCgmStopSessionFsl2` | 🔴 major | — | 3 |
| 406 | `CgmJoinSessionFsl2HistoryLog` | `CgmJoinSessionFsl2HistoryLog` | `LidCgmJoinSessionFsl2` | 🔴 major | — | 4 |
| 419 | `TipsErrorHistoryLog` | `TipsErrorHistoryLog` | — | 🟢 none | — | — |
| 438 | `CgmCalibrationG7HistoryLog` | `CgmCalibrationG7HistoryLog` | — | 🟢 none | — | — |
| 439 | `CgmBleCalibrationEvtG7HistoryLog` | `CgmBleCalibrationEvtG7HistoryLog` | — | 🟢 none | — | — |
| 441 | `CgmInactiveG7HistoryLog` | `CgmInactiveG7HistoryLog` | — | 🟢 none | — | 3 |
| 443 | `CgmStopSessionReqG7HistoryLog` | `CgmStopSessionReqG7HistoryLog` | — | 🟢 none | — | — |
| 447 | `CgmStopSessionG7HistoryLog` | `CgmStopSessionG7HistoryLog` | `LidCgmStopSessionG7` | 🔴 major | — | 3 |
| 460 | `CgmAlertActivatedFsl2HistoryLog` | `CgmAlertActivatedFsl2HistoryLog (Sources/TandemCore/Messages/HistoryLog/CgmAlertActivatedFsl2HistoryLog.swift)` | `LidCgmAlertActivatedFsl2` | 🔴 major | 2 | 4 |
| 461 | `CgmAlertClearedFsl2HistoryLog (historyLog)` | `CgmAlertClearedFsl2HistoryLog.swift (Sources/TandemCore/Messages/HistoryLog)` | `LidCgmAlertClearedFsl2` | 🔴 major | 1 | 4 |
| 477 | `CgmJoinSessionFsl3HistoryLog` | `CgmJoinSessionFsl3HistoryLog` | `LidCgmJoinSessionFsl3` | 🔴 major | — | 4 |
| 480 | `CgmDataFsl3HistoryLog` | `CgmDataFsl3HistoryLog` | `LidCgmDataFsl3` | 🔴 major | 2 | 7 |
| 486 | `CgmStopSessionFsl3HistoryLog` | `CgmStopSessionFsl3HistoryLog` | `LidCgmStopSessionFsl3` | 🔴 major | — | 3 |

## Per-event field cross-reference

### opCode 0 — LID_LOG_ERASED

`LogErasedHistoryLog` (java) ↔ `LogErasedHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| numErased | `numErased`<br>uint32 @10 | `numErased`<br>uint32 @10 | — | ✅ match | numErased: java uint32@10 (Bytes.readUint32(raw, 10)) = swift uint32@10 (Bytes.readUint32(raw, 10)); both serializers write Bytes.toUint32(numErased) at payload offset 10 after 2-byte typeId + uint32 timestamp + uint32 sequenceNum — fully consistent; no Python parser exists for opCode 0 |

_No inconsistencies found._

### opCode 2 — LID_TEMP_RATE_ACTIVATED

`TempRateActivatedHistoryLog` (java) ↔ `TempRateActivatedHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| percent | `percent`<br>float32 @10 | `percent`<br>float32 @10 | — | ✅ match | percent: java float32@10 (Bytes.readFloat(raw, 10)) = swift float32@10 (Bytes.readFloat(cargo, 10)); serializers both emit Bytes.toFloat(percent) at the same position |
| duration | `duration`<br>float32 @14 | `durationMilliseconds`<br>float32 @14 | — | ✅ match | duration: java float32@14 = swift float32@14. Name-only difference: Swift renames 'duration' to 'durationMilliseconds' (adds a unit claim absent from the Java reference); layout identical, not counted as an inconsistency |
| tempRateId | `tempRateId`<br>uint16 @20 | `tempRateId`<br>uint16 @20 | — | ✅ match | tempRateId: java uint16@20 (Bytes.readShort(raw, 20)) = swift uint16@20 (Bytes.readShort(cargo, 20)); both serialize via Bytes.firstTwoBytesLittleEndian(tempRateId) |

_No inconsistencies found._

### opCode 3 — LID_BASAL_RATE_CHANGE

`BasalRateChangeHistoryLog` (java) ↔ `BasalRateChangeHistoryLog` (swift) ↔ `LidBasalRateChange` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| commandBasalRate | `commandBasalRate`<br>float32 @10 | `commandBasalRate`<br>float32 @10 | `commandedBasalRate`<br>float32 @10 | ✅ match | float32@10 on all three sides; py name differs (commandedBasalRate) but that is cosmetic |
| baseBasalRate | `baseBasalRate`<br>float32 @14 | `baseBasalRate`<br>float32 @14 | `baseBasalRate`<br>float32 @14 | ✅ match | float32@14 on all three sides |
| maxBasalRate | `maxBasalRate`<br>float32 @18 | `maxBasalRate`<br>float32 @18 | `maxBasalRate`<br>float32 @18 | ✅ match | float32@18 on all three sides |
| insulinDeliveryProfile | `insulinDeliveryProfile`<br>uint16 @22 | `insulinDeliveryProfile`<br>uint16 @22 | `idp`<br>uint16 @24 | ❌ py-diverges-from-java | idp: java Bytes.readShort(raw,22) uint16@22 = swift Bytes.readShort(cargo,22) uint16@22; py struct.unpack_from(UINT16, raw, 24) uint16@24 — py diverges by 2 bytes |
| changeTypeId | `changeTypeId`<br>uint8 @24 | `changeTypeId`<br>uint8 @24 | `changeTypeRaw`<br>uint8 @23 | ❌ py-diverges-from-java | changeType: java raw[24] uint8@24 (buildCargo pads a zero at 25) = swift cargo[24] uint8@24; py struct.unpack_from(UINT8, raw, 23) uint8@23 — py reads changeType BEFORE idp, java/swift read idp(22-23) then changeType(24) |

**Enum / value-map findings:**

- ✅ `ChangeType.TIMED_SEGMENT..PUMP_SHUT_DOWN` — *match*: Values 1,2,4,8,16,32,64 identical across java ChangeType, swift ChangeType (timedSegment=1..pumpShutDown=64), and py ChangetypeBitmask (TimedSegment=2**0..PumpShutDown=2**6)
- ⚠️ `ChangeType.BASAL_LIMIT` — *missing-in-java*: Python ChangetypeBitmask.BasalLimit=2**7 (128) and ChangetypeMap key "7" ('basal limit') have no counterpart in java ChangeType or swift ChangeType, which both stop at PUMP_SHUT_DOWN=64; missing in both java and swift
- ⚠️ `ChangeType interpretation (single value vs bitmask)` — *partial*: Java ChangeType.fromId(id) and Swift ChangeType(rawValue:) require an exact single value and return null/nil for combined flags; Python treats the byte as an IntFlag bitmask allowing OR'd combinations (e.g. 1\|16). Same underlying values, different combinability semantics

**Inconsistencies:**

- [PY-DIVERGENCE] insulinDeliveryProfile/idp: java uint16@22 (Bytes.readShort(raw,22)) = swift uint16@22, py uint16@24 (unpack_from(UINT16, raw, 24)) — py reads idp 2 bytes later than the reference
- [PY-DIVERGENCE] changeType: java uint8@24 (raw[24]) = swift uint8@24, py uint8@23 (unpack_from(UINT8, raw, 23)) — field order swapped: java/swift layout is idp@22-23 then changeType@24 + zero pad@25, python layout is changeType@23 then idp@24-25
- [PY-DIVERGENCE] enum value set: python ChangetypeBitmask/ChangetypeMap include BasalLimit=128 (bit 7, 'basal limit'), absent from java ChangeType and swift ChangeType which end at PUMP_SHUT_DOWN=64
- [PY-DIVERGENCE] enum semantics: java ChangeType.fromId / swift ChangeType(rawValue:) exact-match a single value (combined flag bytes decode to null/nil), while python ChangetypeBitmask is an IntFlag that accepts bitwise combinations

### opCode 4 — LID_ALERT_ACTIVATED

`AlertActivatedHistoryLog` (java) ↔ `AlertActivatedHistoryLog` (swift) ↔ `LidAlertActivated` (py) — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alertId | `alertId`<br>uint32 @10 | `alertId`<br>uint32 @10 | `alertIdRaw`<br>uint32 @10 | ✅ match | alertId: java uint32@10 (Bytes.readUint32(raw,10)) = swift uint32@10 (Bytes.readUint32(cargo,10)) = py uint32@10 (unpack_from(UINT32,...,10) as alertIdRaw). Name difference only on Python side. buildCargo on Java and Swift both serialize uint32 at 10, internally consistent. |
| faultLocatorData | — | — | `faultLocatorData`<br>uint32 @14 | ❌ missing-in-java | py uint32@14 only; absent from Java parse() (which notes '// other unknown fields') and absent from Swift init(cargo:). Java/Swift buildCargo zero-fill bytes 14-25 via fillCargo. |
| param1 | — | — | `param1`<br>uint32 @18 | ❌ missing-in-java | py uint32@18 only; absent from Java and Swift parsers (Java comment acknowledges unknown trailing fields). |
| param2 | — | — | `param2`<br>float32 @22 | ❌ missing-in-java | py float32@22 only; absent from Java and Swift parsers. |

**Enum / value-map findings:**

- ⚠️ `alertId value 49` — *values-differ*: Swift AlertResponseType has FILL_TUBING_STILL_IN_PROGRESS = 49 (AlertStatus.swift:102); Python AlertidMap/AlertidEnum has 49 = DEFAULT_ALERT_49. Same numeric value, different meaning label. Java AlertStatusResponse enum source was not included in the provided scratchpad so the Java-side label could not be verified directly.
- ⚠️ `alertId value 51` — *values-differ*: Python maps 51 = CONTROL_IQ_LOW; Swift has DEFAULT_ALERT_51 = 51 (AlertStatus.swift:104). Same numeric value, conflicting label/meaning.
- ✅ `alertId value 31` — *match*: Value 31 is absent from both Swift AlertResponseType and Python AlertidMap/AlertidEnum (both jump 30 -> 32); consistent gap.
- ⚠️ `alertId enum lookup semantics` — *partial*: Java exposes AlertStatusResponse.AlertResponseType.fromSingularId(alertId); Swift uses AlertResponseType(rawValue: Int(alertId)) where the Swift enum raw values are the singular ids 0-63, so lookup semantics agree. Python AlertidEnum(alertIdRaw) uses the same singular-id values 0-63.

**Inconsistencies:**

- [PY-DIVERGENCE] Python LidAlertActivated decodes three extra payload fields absent from the Java reference: faultLocatorData uint32@14, param1 uint32@18, param2 float32@22. Java parse() reads only alertId uint32@10 and comments '// other unknown fields'; Swift matches Java. Not a decode error on any side, but Java/Swift discard payload bytes 14-25 that Python interprets.
- [PY-DIVERGENCE] Enum label conflicts in the alertId value map: value 49 = FILL_TUBING_STILL_IN_PROGRESS in Swift (ported from Java) vs DEFAULT_ALERT_49 in Python; value 51 = DEFAULT_ALERT_51 in Swift vs CONTROL_IQ_LOW in Python.
- Swift alertResponseType uses AlertResponseType(rawValue:) returning Optional, whereas Java fromSingularId may have different unknown-value behavior; functionally equivalent for defined ids 0-63 since Swift raw values are the singular ids. No port bug found: Swift alertId offset/type/serializer match Java exactly (uint32@10, buildCargo typeId+timestamp+seqNum+alertId).

### opCode 5 — LID_ALARM_ACTIVATED

`AlarmActivatedHistoryLog` (java) ↔ `AlarmActivatedHistoryLog` (swift) ↔ `LidAlarmActivated` (py) — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alarmId | `alarmId`<br>uint32 @10 | `alarmId`<br>uint32 @10 | `alarmIdRaw`<br>uint32 @10 | ✅ match | alarmId: java uint32@10 = swift uint32@10 = py uint32@10 — all agree |
| faultLocatorData | — | — | `faultLocatorData`<br>uint32 @14 | ❌ missing-in-java | py-only field uint32@14; Java parse() reads nothing past offset 13 (buildCargo pads bytes 14-25 via fillCargo) and Swift port likewise omits it — absent in both java and swift |
| param1 | — | — | `param1`<br>uint32 @18 | ❌ missing-in-java | py-only field uint32@18; absent in both java and swift, which treat bytes 14-25 as padding |
| param2 | — | — | `param2`<br>float32 @22 | ❌ missing-in-java | py-only field float32@22; absent in both java and swift, which treat bytes 14-25 as padding |

**Enum / value-map findings:**

- ⚠️ `alarmId enum (Java/Swift AlarmStatusResponse.AlarmResponseType vs Python AlarmidEnum/AlarmidMap)` — *partial*: Swift enum raw values 0-63 and Python AlarmidEnum 0-63 align except value 34: Swift = CARTRIDGE_ALARM_34, Python = DEFAULT_ALARM_34/DefaultAlarm34 — label-only divergence. Java's AlarmResponseType lives in AlarmStatusResponse.java which is not present in the provided pumpX2 scratchpad, so the Java value set could not be verified directly.
- ⚠️ `alarmId enum lookup semantics` — *values-differ*: Java resolves via AlarmResponseType.fromSingularId(alarmId) (singular-id lookup helper) while Swift uses AlarmResponseType(rawValue: Int(alarmId)) direct raw-value init; equivalent only if Java singularIds equal the 0-63 ordinals used as Swift raw values — unverifiable here since AlarmStatusResponse.java is not in the scratchpad.

**Inconsistencies:**

- [PY-DIVERGENCE] Python LidAlarmActivated decodes three extra payload fields that the Java reference (and Swift port) never parse: faultLocatorData uint32@14, param1 uint32@18, param2 float32@22. Java parse() only reads alarmId uint32@10 and buildCargo() zero-pads bytes 14-25 via fillCargo, so Java/Swift silently drop fault-locator diagnostics that Tandem's cloud format exposes.
- [PY-DIVERGENCE] Enum label mismatch at value 34: Swift AlarmResponseType has CARTRIDGE_ALARM_34 = 34 while Python AlarmidMap has "34": "DEFAULT_ALARM_34" — same numeric value, different meaning label (Java enum source not available in scratchpad to arbitrate).
- Swift port note (not confirmed as a bug): Java maps alarmId via AlarmResponseType.fromSingularId(alarmId) whereas Swift uses AlarmResponseType(rawValue: Int(alarmId)); these agree only if Java's singularId values are the same 0-63 ordinals Swift uses as raw values. AlarmStatusResponse.java was not in the provided pumpX2 tree, so this could not be verified.

### opCode 6 — LID_MALFUNCTION_ACTIVATED

`MalfunctionHistoryLog` (java) ↔ `MalfunctionHistoryLog` (swift) ↔ `LidMalfunctionActivated` (py) — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| malfId | `malfId`<br>uint32 @10 | `malfId`<br>uint32 @10 | `malfIdRaw`<br>uint32 @10 | ✅ match | java uint32@10 = swift uint32@10 = py uint32@10; py names it malfIdRaw (name difference only) |
| faultLocatorData | `faultLocatorData`<br>uint32 @14 | `faultLocatorData`<br>uint32 @14 | `faultLocatorData`<br>uint32 @14 | ✅ match | uint32@14 on all three sides |
| param1 | `param1`<br>uint32 @18 | `param1`<br>uint32 @18 | `param1`<br>uint32 @18 | ✅ match | uint32@18 on all three sides |
| param2 | `param2`<br>float32 @22 | `param2`<br>float32 @22 | `param2`<br>float32 @22 | ✅ match | float32@22 on all three sides |

**Enum / value-map findings:**

- ✅ `malfId` — *match*: No value map on any side: Java has no nested enum, Swift has none, and Python carries only a placeholder comment '# Dictionary unknown: malfs' with no malfsMap dict — malfId is raw on all three sides

_No inconsistencies found._

### opCode 7 — LID_MALFUNCTION_ACK

`MalfunctionAckHistoryLog` (java) ↔ `MalfunctionAckHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| malfId | `malfId`<br>uint32 @10 | `malfId`<br>uint32 @10 | — | ✅ match | malfId: java Bytes.readUint32(raw,10) = swift Bytes.readUint32(cargo,10); both serializers emit Bytes.toUint32(malfId) after the 10-byte header. No Python parser exists. |

_No inconsistencies found._

### opCode 8 — LID_ALARM_ACK

`AlarmAckHistoryLog` (java) ↔ `AlarmAckHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alarmId | `alarmId`<br>uint32 @10 | `alarmId`<br>uint32 @10 | — | ✅ match | alarmId: java Bytes.readUint32(raw,10) = swift Bytes.readUint32(cargo,10); both buildCargo serializers write Bytes.toUint32(alarmId) at offset 10 — fully consistent |

_No inconsistencies found._

### opCode 11 — LID_PUMPING_SUSPENDED

`PumpingSuspendedHistoryLog` (java) ↔ `PumpingSuspendedHistoryLog` (swift) ↔ `LidPumpingSuspended` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| insulinAmount | `insulinAmount`<br>uint16 @14 | `insulinAmount`<br>uint16 @14 | `insulinAmount`<br>uint16 @16 | ❌ py-diverges-from-java | java uint16@14 (Bytes.readShort(raw,14)) = swift uint16@14; py uint16@16 (unpack_from(UINT16, raw, 16)) — py diverges. Unit comments also differ: java javadoc says milliunits, py comment says units. |
| suspendReason | `reasonId`<br>uint8 @16 | `reasonId`<br>uint8 @16 | `suspendReasonRaw`<br>uint8 @15 | ❌ py-diverges-from-java | java uint8@16 (raw[16]) = swift uint8@16 (cargo[16]); py uint8@15 — py diverges. Enum value sets identical on all three sides: {0,1,2,6}. |
| preSuspendState | — | — | `preSuspendState`<br>uint32 @10 | ❌ missing-in-java | py uint32@10; absent from Java parse() and Swift init(cargo:) — Java parses nothing at offsets 10-13, and Swift buildCargo() zero-fills those 4 bytes (Data(repeating:0,count:4)). Missing in both Java and Swift (schema allows only one missing-in-X; Java is the reference). |
| rpaTimeout | — | — | `rpaTimeout`<br>uint8 @14 | ❌ missing-in-java | py uint8@14 (minutes); absent from Java and Swift parsers. Note py@14 overlaps the low byte of java/swift insulinAmount uint16@14 — the two layouts are mutually exclusive at this offset. |

**Enum / value-map findings:**

- ✅ `suspendReason` — *match*: Java SuspendReason: USER_ABORTED=0, ALARM=1, MALFUNCTION=2, AUTO_SUSPEND_PREDICTIVE_LOW_GLUCOSE=6. Swift SuspendReason: userAborted=0, alarm=1, malfunction=2, autoSuspendPredictiveLowGlucose=6. Python SuspendreasonMap/SuspendreasonEnum: 0='User Aborted', 1='Terminated by Alarm', 2='Terminated by Malfunction', 6='Auto Suspend by PLGS'. Value sets and meanings identical; labels differ only cosmetically.

**Inconsistencies:**

- [PY-DIVERGENCE] insulinAmount: java uint16@14 = swift uint16@14, py uint16@16 — py reads insulin amount 2 bytes later than the reference.
- [PY-DIVERGENCE] suspendReason: java uint8@16 = swift uint8@16, py uint8@15 — py reads the reason one byte earlier than the reference.
- [PY-DIVERGENCE] preSuspendState: py parses uint32@10; Java and Swift parse nothing at offsets 10-13 (Swift buildCargo explicitly zero-pads these 4 bytes).
- [PY-DIVERGENCE] rpaTimeout: py parses uint8@14 (minutes); absent in Java/Swift, and it collides with the low byte of java/swift insulinAmount uint16@14 — the Python layout (u32@10, u8@14, u8@15, u16@16) and Java layout (u16@14, u8@16) cannot both be correct for the same binary record.
- Java internal inconsistency: buildCargo() writes insulinAmount at offset 10 (firstTwoBytesLittleEndian immediately after the 10-byte header) and reason at offset 12, but its own parse() reads insulinAmount@14 and reason@16 — the Java serializer omits 4 bytes at offsets 10-13. Round-tripping buildCargo→parse in pumpX2 yields wrong values. Swift is NOT bugged here: its buildCargo() inserts Data(repeating:0,count:4) so serializer and parser agree at @14/@16 — the port deliberately fixed the reference bug (an intentional, beneficial divergence from Java's serializer, not a [PORT-BUG]).
- Minor doc mismatch: java javadoc calls insulinAmount 'milliunits' (possibly IOB); python comment calls it 'units'.

### opCode 12 — LID_PUMPING_RESUMED

`PumpingResumedHistoryLog` (java) ↔ `PumpingResumedHistoryLog` (swift) ↔ `LidPumpingResumed` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| preResumeState | — | — | `preResumeState`<br>uint32 @10 | ❌ missing-in-java | py uint32@10 (preResumeState); absent from Java and Swift parsers. Java buildCargo writes 4 placeholder bytes at 10-13 with comment 'unknown -- uint32(100)', so Java/pumpX2 knows bytes 10-13 exist but does not decode them; Swift mirrors Java (writes 4 zero bytes, no field). Missing in both Java and Swift. |
| insulinAmount | `insulinAmount`<br>uint16 @14 | `insulinAmount`<br>uint16 @14 | `insulinAmount`<br>uint16 @16 | ❌ py-diverges-from-java | insulinAmount: java uint16@14 (Bytes.readShort(raw,14)) = swift uint16@14 (Bytes.readShort(cargo,14)); py uint16@16 (unpack_from(UINT16, raw, 16)) — py reads 2 bytes later than Java. Combined with py preResumeState being uint32@10-13, py's layout implies bytes 14-15 are unaccounted for on the py side (or 10-13 is not a full uint32 on the Java side). |

**Inconsistencies:**

- [PY-DIVERGENCE] insulinAmount offset mismatch: java/swift uint16@14 vs py uint16@16 — the two sides decode different bytes of the record for the same semantic field; one of them yields wrong values.
- [PY-DIVERGENCE] preResumeState uint32@10 exists only in Python; Java leaves bytes 10-13 as an unknown placeholder (buildCargo comment 'unknown -- uint32(100)') and Swift ports that placeholder. If Python's layout (preResumeState@10-13, insulinAmount@16-17) is correct, Java/Swift insulinAmount@14 is reading the middle of the record incorrectly; if Java is correct, Python's insulinAmount@16 is off by 2.
- Java internal note: buildCargo comment says the unknown uint32 at 10-13 is typically 100, but it serializes zeros (new byte[4]); parse() never reads it — internally consistent but round-trips of real records lose no data since raw cargo is retained.

### opCode 13 — LID_TIME_CHANGED

`TimeChangedHistoryLog` (java) ↔ `TimeChangedHistoryLog` (swift) ↔ `LidTimeChanged` (py) — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| timePrior | `timePrior`<br>uint32 @10 | `timePrior`<br>uint32 @10 | `timePrior`<br>uint32 @10 | ✅ match | java uint32@10 = swift uint32@10 = py uint32@10 ('>I'); serializers agree with parsers on all sides |
| timeAfter | `timeAfter`<br>uint32 @14 | `timeAfter`<br>uint32 @14 | `timeAfter`<br>uint32 @14 | ✅ match | java uint32@14 = swift uint32@14 = py uint32@14; serializers agree |
| rawRTC | `rawRTC`<br>uint32 @18 | `rawRTC`<br>uint32 @18 | `rawRtcTime`<br>uint32 @18 | ✅ match | java uint32@18 = swift uint32@18 = py uint32@18; name differs only (rawRTC vs rawRtcTime). Python dataclass comments annotate all three fields as '# ms', which is likely a doc-comment error (values are pump-time seconds/RTC ticks), but does not affect parsing layout |

_No inconsistencies found._

### opCode 14 — LID_DATE_CHANGED

`DateChangeHistoryLog` (java) ↔ `DateChangeHistoryLog` (swift) ↔ `LidDateChanged` (py) — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| datePrior | `datePrior`<br>uint32 @10 | `datePrior`<br>uint32 @10 | `datePrior`<br>uint32 @10 | ✅ match | java uint32@10 = swift uint32@10 = py uint32@10 (days since Jan 1 2008 epoch per Java Dates.fromJan12008EpochDaysToDate; py comment '# day' agrees) |
| dateAfter | `dateAfter`<br>uint32 @14 | `dateAfter`<br>uint32 @14 | `dateAfter`<br>uint32 @14 | ✅ match | java uint32@14 = swift uint32@14 = py uint32@14 |
| rawRTCTime | `rawRTCTime`<br>uint32 @18 | `rawRTCTime`<br>uint32 @18 | `rawRtcTime`<br>uint32 @18 | ✅ match | java uint32@18 = swift uint32@18 = py uint32@18; name casing differs only (rawRTCTime vs rawRtcTime). Py comment says '# ms' while Java exposes it as raw RTC time with no unit conversion — annotation-only difference, not a layout issue |

_No inconsistencies found._

### opCode 15 — LID_TEMP_RATE_COMPLETED

`TempRateCompletedHistoryLog` (java) ↔ `TempRateCompletedHistoryLog` (swift) — *no Python parser* — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| tempRateId | `tempRateId`<br>uint16 @12 | `tempRateId`<br>uint16 @12 | — | ✅ match | java Bytes.readShort(raw,12) = swift Bytes.readShort(cargo,12); identical. |
| timeLeft | `timeLeft`<br>uint32 @14 | `timeLeft`<br>uint32 @14 | — | ✅ match | java Bytes.readUint32(raw,14) = swift Bytes.readUint32(cargo,14); identical. |

**Inconsistencies:**

- Internal parser/serializer mismatch present identically in BOTH Java and Swift (inherited from reference, not a port bug): buildCargo() writes tempRateId at offset 10 (firstTwoBytesLittleEndian after 2-byte header + 4-byte time + 4-byte seq) and timeLeft at offset 12, but parse()/init(cargo:) read tempRateId at offset 12 and timeLeft at offset 14 — a self-built cargo round-trips incorrectly, leaving offsets 10-11 unwritten by the parser's expectations.

### opCode 16 — LID_BG_READING_TAKEN

`BGHistoryLog` (java) ↔ `BGHistoryLog` (swift) ↔ `LidBgReadingTaken` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| bg | `bg`<br>uint16 @10 | `bg`<br>uint16 @10 | `bg`<br>uint16 @12 | ❌ py-diverges-from-java | bg: java uint16@10 = swift uint16@10, py uint16@12 — py diverges |
| cgmCalibration | `cgmCalibration`<br>uint8 @12 | `cgmCalibration`<br>uint8 @12 | `cgmCalibrationRaw`<br>uint8 @11 | ❌ py-diverges-from-java | cgmCalibration: java uint8@12 = swift uint8@12, py uint8@11 — py diverges |
| bgSourceId | `bgSourceId`<br>uint8 @13 | `bgSourceId`<br>uint8 @13 | `bgEntryTypeRaw`<br>uint8 @10 | ❌ py-diverges-from-java | bgSourceId (java/swift, maps to LastBGResponse.BgSource CGM-vs-manual) semantically = py bgEntryType (manual vs auto-populated Dexcom EGV): java uint8@13 = swift uint8@13, py uint8@10 — py diverges |
| iob | `iob`<br>float32 @14 | `iob`<br>float32 @14 | `iob`<br>float32 @14 | ✅ match | iob: float32@14 on all three sides |
| targetBG | `targetBG`<br>uint16 @18 | `targetBG`<br>uint16 @18 | `targetBg`<br>uint16 @20 | ❌ py-diverges-from-java | targetBG: java uint16@18 = swift uint16@18, py uint16@20 — py diverges (swapped with isf relative to java) |
| isf | `isf`<br>uint16 @20 | `isf`<br>uint16 @20 | `isf`<br>uint16 @18 | ❌ py-diverges-from-java | isf: java uint16@20 = swift uint16@20, py uint16@18 — py diverges (swapped with targetBG relative to java) |
| selectedIOB | `selectedIOB`<br>uint8 @22 | — | `selectedIobRaw`<br>uint8 @25 | ❌ missing-in-swift | selectedIOB: java uint8@22, py uint8@25 (py also diverges), swift has NO field — bytes 22-23 absorbed into Swift's spare=readUint32(raw,22). Swift port bug. |
| bgSourceType | `bgSourceType`<br>uint8 @23 | — | `bgSourceTypeRaw`<br>uint8 @24 | ❌ missing-in-swift | bgSourceType: java uint8@23, py uint8@24 (py also diverges), swift has NO field — absorbed into Swift's spare uint32@22. Swift port bug. |
| spare | `spare`<br>uint16 @24 | `spare`<br>uint32 @22 | — | ❌ swift-diverges-from-java | spare: java uint16@24 (Bytes.readShort(raw,24)); swift uint32@22 (Bytes.readUint32(raw,22)) — wrong offset AND width, swallows java selectedIOB@22 and bgSourceType@23. Python has no spare field (not an inconsistency by itself since bytes 24-25 are py's bgSourceType/selectedIob). |

**Enum / value-map findings:**

- ✅ `bgSourceId/bgEntryType` — *match*: Swift LastBGResponse.BgSource {manual=0, cgm=1} agrees with py BgentrytypeEnum {0=Manual Entry via Numpad, 1=Auto Populated BG using Dexcom EGV}. Java delegates to LastBGResponse.BgSource.fromId (javadoc: 'CGM or manual'); Java LastBGResponse source not present in scratchpad checkout so exact Java values verified only via the Swift port.
- ⚠️ `selectedIOB` — *partial*: Python defines SelectediobEnum {0=Mudaliar IOB, 1=Swan IOB Meal}; Java exposes plain int with no enum/javadoc; Swift lacks the field entirely.
- ⚠️ `bgSourceType` — *partial*: Python defines BgsourcetypeEnum {0=Local Pump entry, 1=Remote entry}; Java exposes plain int with no enum; Swift lacks the field entirely.
- ⚠️ `cgmCalibration` — *partial*: Python defines CgmcalibrationEnum {0=No not used to calibrate, 1=Yes used to calibrate}; Java javadoc says 'TODO(unknown)' and Swift is a plain Int — value semantics only documented in python.

**Inconsistencies:**

- [PORT-BUG] Swift BGHistoryLog init(cargo:) reads spare = Bytes.readUint32(raw, 22) where Java parse() reads selectedIOB = raw[22] (uint8), bgSourceType = raw[23] (uint8), spare = Bytes.readShort(raw, 24) (uint16). Swift drops selectedIOB and bgSourceType entirely and mis-decodes spare as a uint32 at offset 22 that concatenates all four bytes 22-25.
- [PORT-BUG] Swift buildCargo serializes Bytes.toUint32(spare) at offset 22 in place of Java's selectedIOB byte @22 + bgSourceType byte @23 + firstTwoBytesLittleEndian(spare) @24. Swift is internally consistent with its own parser but produces/consumes a wire layout incompatible with the Java reference for bytes 22-25 (e.g. selectedIOB=1, bgSourceType=1, spare=0 encodes java bytes [01,01,00,00] but any Swift round-trip of that record yields spare=0x0101, selectedIOB/bgSourceType lost).
- [PY-DIVERGENCE] bg: java uint16@10 (= swift), py uint16@12 — a 26-byte record with bg=120 decodes differently on the py side.
- [PY-DIVERGENCE] cgmCalibration: java uint8@12 (= swift), py uint8@11.
- [PY-DIVERGENCE] bgSourceId/bgEntryType: java uint8@13 (= swift), py uint8@10.
- [PY-DIVERGENCE] targetBG: java uint16@18 (= swift), py uint16@20 — targetBG and isf are transposed between java and py.
- [PY-DIVERGENCE] isf: java uint16@20 (= swift), py uint16@18.
- [PY-DIVERGENCE] selectedIOB: java uint8@22, py uint8@25.
- [PY-DIVERGENCE] bgSourceType: java uint8@23, py uint8@24.
- [PY-DIVERGENCE] Python has no spare field; java's spare uint16@24 region is occupied by py's bgSourceType@24 and selectedIob@25 (bytes 10-13 and 18-25 are laid out differently overall between the BLE and cloud-export formats; iob@14 is the only payload field at a common offset).
- Enum coverage gap (minor): python documents value maps for selectedIob {0=Mudaliar IOB,1=Swan IOB Meal}, bgSourceType {0=Local Pump entry,1=Remote entry}, and cgmCalibration {0=No,1=Yes} that java (plain ints, cgmCalibration javadoc'd TODO(unknown)) and swift lack.

### opCode 20 — LID_BOLUS_COMPLETED

`BolusCompletedHistoryLog` (java) ↔ `BolusCompletedHistoryLog` (swift) ↔ `LidBolusCompleted` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| completionStatus | `completionStatusId`<br>uint16 @10 | `completionStatusId`<br>uint16 @10 | `completionStatusRaw`<br>uint16 @12 | ❌ py-diverges-from-java | completionStatus: java uint16@10 (Bytes.readShort(raw,10)) = swift uint16@10 (Bytes.readShort(cargo,10)); py uint16@12 (unpack_from(UINT16, raw, 12)) — py reads it at the offset java uses for bolusId (swapped pair) |
| bolusId | `bolusId`<br>uint16 @12 | `bolusId`<br>uint16 @12 | `bolusId`<br>uint16 @10 | ❌ py-diverges-from-java | bolusId: java uint16@12 (Bytes.readShort(raw,12)) = swift uint16@12; py uint16@10 (unpack_from(UINT16, raw, 10)) — py reads it at the offset java uses for completionStatus (swapped pair) |
| iob | `iob`<br>float32 @14 | `iob`<br>float32 @14 | `iob`<br>float32 @14 | ✅ match | float32@14 on all three sides; java doc says milliunits while py comment says units (doc-only discrepancy, same bytes) |
| insulinDelivered | `insulinDelivered`<br>float32 @18 | `insulinDelivered`<br>float32 @18 | `insulinDelivered`<br>float32 @18 | ✅ match | float32@18 on all three sides |
| insulinRequested | `insulinRequested`<br>float32 @22 | `insulinRequested`<br>float32 @22 | `insulinRequested`<br>float32 @22 | ✅ match | float32@22 on all three sides |

**Enum / value-map findings:**

- ⚠️ `completionStatus` — *partial*: Java maps via LastBolusStatusAbstractResponse.BolusStatus (Java source for the enum not present in the sparse checkout; the Swift port of that enum has stopped=0, complete=3). Swift LastBolusStatusAbstractResponseBolusStatus: stopped=0, complete=3 only. Python CompletionstatusMap covers 0-8: 0=User Aborted, 1=Terminated by Alarm, 2=Terminated by Malfunction, 3=Completed, 4=Reserved, 5=Bolus rejected, 6=Aborted by PLGS, 7=Reserved, 8=Reserved; CompletionstatusEnum covers 0,1,2,3,5,6. Values 0 and 3 agree semantically (stopped/aborted vs completed); values 1,2,5,6 are unmapped in Java/Swift, so those decode to null/nil there.

**Inconsistencies:**

- [PY-DIVERGENCE] completionStatus/bolusId offsets are swapped: java+swift read completionStatus uint16@10 and bolusId uint16@12; python LidBolusCompleted.build reads bolusId uint16@10 and completionStatus uint16@12. On the same 26-byte record one side decodes the two fields transposed — major layout conflict.
- [PY-DIVERGENCE] completionStatus enum coverage differs: python maps values 0-8 (1=Terminated by Alarm, 2=Terminated by Malfunction, 5=Bolus rejected, 6=Aborted by PLGS, etc.) while java/swift BolusStatus only defines 0 (stopped) and 3 (complete); intermediate values decode to null/nil in java/swift.

### opCode 21 — LID_BOLEX_COMPLETED

`BolexCompletedHistoryLog` (java) ↔ `BolexCompletedHistoryLog` (swift) ↔ `LidBolexCompleted` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| completionStatus | `completionStatusId`<br>uint16 @10 | `completionStatus`<br>uint16 @10 | `completionStatusRaw`<br>uint16 @12 | ❌ py-diverges-from-java | completionStatus: java uint16@10 = swift uint16@10; py uint16@12 — py reads it where java has bolusId (offsets swapped with bolusId) |
| bolusId | `bolusId`<br>uint16 @12 | `bolusId`<br>uint16 @12 | `bolusId`<br>uint16 @10 | ❌ py-diverges-from-java | bolusId: java uint16@12 = swift uint16@12; py uint16@10 — py reads it where java has completionStatus (offsets swapped with completionStatus) |
| iob | `iob`<br>float32 @14 | `iob`<br>float32 @14 | `iob`<br>float32 @14 | ✅ match | iob: float32@14 on all three sides |
| insulinDelivered | `insulinDelivered`<br>float32 @18 | `insulinDelivered`<br>float32 @18 | `insulinDelivered`<br>float32 @18 | ✅ match | insulinDelivered: float32@18 on all three sides |
| insulinRequested | `insulinRequested`<br>float32 @22 | `insulinRequested`<br>float32 @22 | `insulinRequested`<br>float32 @22 | ✅ match | insulinRequested: float32@22 on all three sides |

**Enum / value-map findings:**

- ⚠️ `completionStatus` — *values-differ*: Java maps completionStatusId via LastBolusStatusAbstractResponse.BolusStatus (Swift port of that enum: stopped=0, complete=3 — only 2 values). Python CompletionstatusMap/CompletionstatusEnum covers 0..8: 0=User Aborted, 1=Terminated by Alarm, 2=Terminated by Malfunction, 3=Completed, 4=Reserved, 5=Bolus rejected, 6=Aborted by PLGS, 7=Reserved, 8=Reserved. Values 0 and 3 overlap (label 0: 'STOPPED/stopped' vs 'User Aborted'); Python has 7 extra values Java/Swift lack. Java source enum file not present in scratchpad; values inferred from the Swift port of the same class.
- ⚠️ `completionStatus` — *missing-in-swift*: Swift BolexCompletedHistoryLog stores completionStatus only as raw Int and never maps it through LastBolusStatusAbstractResponseBolusStatus, whereas Java parse() also populates the typed BolusStatus enum via fromId(). Decoded raw value is identical, so cosmetic only.

**Inconsistencies:**

- [PY-DIVERGENCE] completionStatus/bolusId offsets are swapped in Python: java/swift completionStatus=uint16@10, bolusId=uint16@12; python bolusId=uint16@10, completionStatus=uint16@12 (events.py build(): unpack UINT16@12 -> completionStatus, UINT16@10 -> bolusId). One side decodes these two fields transposed for opCode 21.
- [PY-DIVERGENCE] completionStatus value map: Python defines 9 completion-status values (0=User Aborted,1=Terminated by Alarm,2=Terminated by Malfunction,3=Completed,5=Bolus rejected,6=Aborted by PLGS,4/7/8=Reserved) while Java reuses LastBolusStatusAbstractResponse.BolusStatus which (per the Swift port) has only stopped=0/complete=3; values 1,2,4,5,6,7,8 map to null in Java/Swift.
- Swift port omits the typed completionStatus enum lookup (Java's LastBolusStatusAbstractResponse.BolusStatus.fromId); it exposes only the raw Int. Raw bytes decode identically, so this is a fidelity gap, not a decode bug.

### opCode 25 — LID_REMINDER_ACTIVATED

`ReminderActivatedHistoryLog` (java) ↔ `ReminderActivatedHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| reminderId | `reminderId`<br>uint32 @10 | `reminderId`<br>uint32 @10 | — | ✅ match | java Bytes.readUint32(raw,10) = swift Bytes.readUint32(cargo,10); both serializers write typeId(2)+pumpTimeSec uint32+sequenceNum uint32+reminderId uint32, consistent with their parsers |

_No inconsistencies found._

### opCode 26 — LID_ALERT_CLEARED

`AlertClearedHistoryLog` (java) ↔ `AlertClearedHistoryLog` (swift) ↔ `LidAlertCleared` (py) — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alertId | `alertId`<br>uint32 @10 | `alertId`<br>uint32 @10 | `alertIdRaw`<br>uint32 @10 | ✅ match | alertId: java uint32@10 = swift uint32@10 = py uint32@10 (py names it alertIdRaw with alertId property mapping to AlertidEnum) — layouts identical |
| faultLocatorData | `faultLocatorData`<br>uint32 @14 | `faultLocatorData`<br>uint32 @14 | `faultLocatorData`<br>uint32 @14 | ✅ match | faultLocatorData: java uint32@14 = swift uint32@14 = py uint32@14 — layouts identical |

**Enum / value-map findings:**

- ⚠️ `alertId value 49` — *values-differ*: Swift AlertResponseType (Sources/TandemCore/Messages/CurrentStatus/AlertStatus.swift:102) has 49=FILL_TUBING_STILL_IN_PROGRESS; Python AlertidMap/AlertidEnum has 49=DEFAULT_ALERT_49. Java AlertStatusResponse.java was not available in the scratchpad checkout to arbitrate, but Swift is the Java port so Python likely lags the named value.
- ⚠️ `alertId value 51` — *values-differ*: Python AlertidMap has 51=CONTROL_IQ_LOW; Swift AlertResponseType has 51=DEFAULT_ALERT_51. Python carries a named meaning Swift/Java-port lacks.
- ✅ `alertId enum coverage` — *match*: Both Swift AlertResponseType and Python AlertidEnum cover values 0-30 and 32-63 (31 absent on both sides); all other labels agree semantically (case-style naming differences only).
- ⚠️ `getAlertResponseType accessor` — *missing-in-swift*: Java AlertClearedHistoryLog.getAlertResponseType() maps alertId via AlertStatusResponse.AlertResponseType.fromSingularId; Swift AlertClearedHistoryLog exposes only raw alertId with no enum accessor (the enum itself exists in AlertStatus.swift). Python exposes the equivalent via its alertId property.

**Inconsistencies:**

- [PORT-BUG] Swift AlertClearedHistoryLog has no buildCargo()/serializer counterpart to Java's static buildCargo (typeId 26 + uint32 alertId + uint32 faultLocatorData) and no getAlertResponseType() enum accessor — parse-only port; decoded values are unaffected.
- [PY-DIVERGENCE] alertId label map: py 49=DEFAULT_ALERT_49 vs swift(java-port) 49=FILL_TUBING_STILL_IN_PROGRESS; py 51=CONTROL_IQ_LOW vs swift 51=DEFAULT_ALERT_51 — label/value-map gaps only, binary layout identical.

### opCode 27 — LID_ALERT_ACK

`AlertAckHistoryLog` (java) ↔ `AlertAckHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alertId | `alertId`<br>uint32 @10 | `alertId`<br>uint32 @10 | — | ✅ match | java Bytes.readUint32(raw,10) = swift Bytes.readUint32(cargo,10); both buildCargo() serializers write typeId(2) + pumpTimeSec uint32 + sequenceNum uint32 + alertId uint32, so serializer offset 10 agrees with parser on both sides. No Python parser exists for opcode 27. |

_No inconsistencies found._

### opCode 28 — LID_ALARM_CLEARED

`AlarmClearedHistoryLog` (java) ↔ `AlarmClearedHistoryLog` (swift) ↔ `LidAlarmCleared` (py) — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alarmId | `alarmId`<br>uint32 @10 | `alarmId`<br>uint32 @10 | `alarmIdRaw`<br>uint32 @10 | ✅ match | alarmId: java Bytes.readUint32(raw,10) = swift Bytes.readUint32(cargo,10) = py struct.unpack_from('>I',raw[:26],10) — all uint32@10. Java buildCargo also writes uint32 at 10 (internally consistent). Swift class defines no buildCargo serializer and omits Java's getAlarmResponseType() accessor, but parsing layout is identical. |

**Enum / value-map findings:**

- ✅ `alarmId` — *match*: Python AlarmidMap/AlarmidEnum covers 0-63 (CARTRIDGE_ALARM=0, CARTRIDGE_ALARM2=1, OCCLUSION_ALARM=2, PUMP_RESET_ALARM=3, AUTO_OFF_ALARM=7, EMPTY_CARTRIDGE_ALARM=8, BATTERY_SHUTDOWN_ALARM=12, INVALID_DATE_ALARM=14, RESUME_PUMP_ALARM=18, ALTITUDE_ALARM=21, STUCK_BUTTON_ALARM=22, ATMOSPHERIC_PRESSURE_OUT_OF_RANGE_ALARM=24, CARTRIDGE_REMOVED_ALARM=25, OCCLUSION_ALARM2=26, plus DEFAULT_ALARM_N placeholders). Java maps via AlarmStatusResponse.AlarmResponseType.fromSingularId (source file not available in scratchpad for direct comparison), but the Swift port of that enum (Sources/TandemCore/Messages/CurrentStatus/AlarmStatus.swift) matches the Python values at all sampled points (CARTRIDGE_ALARM=0, CARTRIDGE_ALARM_2=1, CARTRIDGE_ALARM_3=5, CARTRIDGE_ALARM_4=6, EMPTY_CARTRIDGE_ALARM=8, CARTRIDGE_ALARM_5=9, CARTRIDGE_ALARM_6=16, CARTRIDGE_ALARM_7=20). No value-set divergence detected.

_No inconsistencies found._

### opCode 29 — LID_REMINDER_DISMISSED

`ReminderDismissedHistoryLog` (java) ↔ `ReminderDismissedHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| reminderId | `reminderId`<br>uint32 @10 | `reminderId`<br>uint32 @10 | — | ✅ match | java Bytes.readUint32(raw, 10) = swift Bytes.readUint32(cargo, 10); both buildCargo() serializers write Bytes.toUint32(reminderId) at offset 10 after the 2-byte typeId, 4-byte pumpTimeSec, and 4-byte sequenceNum — parser and serializer agree on both sides |

_No inconsistencies found._

### opCode 30 — LID_REMINDER_SNOOZED

`ReminderSnoozedHistoryLog` (java) ↔ `ReminderSnoozedHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| reminderId | `reminderId`<br>uint32 @10 | `reminderId`<br>uint32 @10 | — | ✅ match | java Bytes.readUint32(raw, 10) = swift Bytes.readUint32(cargo, 10); buildCargo on both sides writes Bytes.toUint32(reminderId) after the 10-byte header — fully consistent. No Python parser for this event. |

_No inconsistencies found._

### opCode 31 — LID_CARTRIDGE_REMOVED

`CartridgeRemovedHistoryLog` (java) ↔ `CartridgeRemovedHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 32 — LID_CARTRIDGE_INSERTED

`CartridgeInsertedHistoryLog` (java) ↔ `CartridgeInsertedHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| pumpTimeSec | `pumpTimeSec`<br>uint32 @2 | `pumpTimeSec`<br>uint32 @2 | — | ✅ match | Header field parsed by HistoryLog base (parseBase/super.init); serialized identically via Bytes.toUint32 at offset 2 in both buildCargo implementations. |
| sequenceNum | `sequenceNum`<br>uint32 @6 | `sequenceNum`<br>uint32 @6 | — | ✅ match | Header field parsed by HistoryLog base; serialized identically via Bytes.toUint32 at offset 6 in both buildCargo implementations. |

_No inconsistencies found._

### opCode 33 — LID_CARTRIDGE_FILLED

`CartridgeFilledHistoryLog` (java) ↔ `CartridgeFilledHistoryLog` (swift) ↔ `LidCartridgeFilled` (py) — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| insulinDisplay | `insulinDisplay`<br>uint32 @10 | `insulinDisplay`<br>uint32 @10 | `insulinVolume`<br>uint32 @10 | ✅ match | java Bytes.readUint32(raw,10) = swift Bytes.readUint32(cargo,10) = py UINT32@10 ('>I'). Name differs in Python (insulinVolume) but concept identical; all serializers/parsers agree. |
| insulinActual | `insulinActual`<br>float32 @14 | `insulinActual`<br>float32 @14 | `v2Volume`<br>float32 @14 | ✅ match | java Bytes.readFloat(raw,14) = swift Bytes.readFloat(cargo,14) = py FLOAT32@14 ('>f'). Name differs in Python (v2Volume) but concept identical. |

_No inconsistencies found._

### opCode 36 — LID_USB_CONNECTED

`UsbConnectedHistoryLog` (java) ↔ `UsbConnectedHistoryLog` (swift) ↔ `LidUsbConnected` (py) — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| negotiatedCurrentmA | `negotiatedCurrentmA`<br>float32 @10 | `negotiatedCurrentmA`<br>float32 @10 | `negotiatedCurrent`<br>float32 @10 | ✅ match | java float32@10 (Bytes.readFloat(raw,10)) = swift float32@10 (Bytes.readFloat(cargo,10)) = py float32@10 (unpack_from(FLOAT32,...,10)); py name lacks the mA suffix but documents mA in a comment — cosmetic only. Java and Swift buildCargo() both serialize header + toUint32(pumpTimeSec) + toUint32(sequenceNum) + toFloat at offset 10, matching their parsers. |

_No inconsistencies found._

### opCode 37 — LID_USB_DISCONNECTED

`UsbDisconnectedHistoryLog` (java) ↔ `UsbDisconnectedHistoryLog` (swift) ↔ `LidUsbDisconnected` (py) — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| negotiatedCurrentMilliAmps | `negotiatedCurrentMilliAmps`<br>float32 @10 | `negotiatedCurrentmA`<br>float32 @10 | `negotiatedCurrent`<br>float32 @10 | ✅ match | java Bytes.readFloat(raw,10) = swift Bytes.readFloat(cargo,10) = py FLOAT32@10 — all float32@10; only naming differs (negotiatedCurrentMilliAmps / negotiatedCurrentmA / negotiatedCurrent) |

_No inconsistencies found._

### opCode 41 — LID_CONFIRM_CARTRIDGE_FILLED

`ConfirmCartridgeFilledHistoryLog` (java) ↔ `ConfirmCartridgeFilledHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 48 — LID_CARBS_ENTERED

`CarbEnteredHistoryLog` (java) ↔ `CarbEnteredHistoryLog` (swift) ↔ `LidCarbsEntered` (py) — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| carbs | `carbs`<br>float32 @10 | `carbs`<br>float32 @10 | `carbs`<br>float32 @10 | ✅ match | carbs: java Bytes.readFloat(raw,10) = swift Bytes.readFloat(cargo,10) = py struct.unpack_from(FLOAT32, raw[:26], 10) — all float32@10, fully consistent |

_No inconsistencies found._

### opCode 53 — LID_SHELF_MODE

`ShelfModeHistoryLog` (java) ↔ `ShelfModeHistoryLog` (swift) ↔ `LidShelfMode` (py) — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| msecSinceReset | `msecSinceReset`<br>uint32 @10 | `msecSinceReset`<br>uint32 @10 | `msecSinceReset`<br>uint32 @10 | ✅ match | java uint32@10 = swift uint32@10 = py uint32@10 |
| lipoIbc | `lipoIbc`<br>uint8 @14 | `lipoIbc`<br>uint8 @14 | `liPoIbc`<br>uint8 @14 | ✅ match | java raw[14] uint8 = swift cargo[14] uint8 = py UINT8@14 |
| lipoAbc | `lipoAbc`<br>uint8 @15 | `lipoAbc`<br>uint8 @15 | `liPoAbc`<br>uint8 @15 | ✅ match | java raw[15] uint8 = swift cargo[15] uint8 = py UINT8@15 |
| lipoCurrent | `lipoCurrent`<br>uint16 @16 | `lipoCurrent`<br>uint16 @16 | `liPoCurrent`<br>int16 @16 | ❌ signedness-mismatch | java Bytes.readShort@16 (uint16) = swift Bytes.readShort@16 (uint16); py struct INT16@16 (signed, commented '# mA') — same offset/width, py interprets sign bit (values >= 0x8000 decode negative in py, large positive in java/swift) |
| lipoRemCap | `lipoRemCap`<br>uint32 @18 | `lipoRemCap`<br>uint32 @18 | `liPoRemCap`<br>uint32 @18 | ✅ match | java uint32@18 = swift uint32@18 = py uint32@18 |
| lipoMv | `lipoMv`<br>uint32 @22 | `lipoMv`<br>uint32 @22 | `liPoMV`<br>uint32 @22 | ✅ match | java uint32@22 = swift uint32@22 = py uint32@22 |

**Inconsistencies:**

- [PY-DIVERGENCE] lipoCurrent: java uint16@16 (Bytes.readShort) = swift uint16@16; py reads INT16 (signed) at offset 16 — same offset/width but signed interpretation, so raw values >= 0x8000 decode as negative mA in tconnectsync but as 32768..65535 in pumpX2/TandemKit. Python's signed reading is likely physically correct for a charge/discharge current, meaning java/swift may mis-decode negative currents, but treating java as baseline this is a py divergence.
- Swift ShelfModeHistoryLog has init(cargo:) only, no buildCargo() serializer (Java has buildCargo consistent with its parse: uint32@10, uint8@14, uint8@15, 2-byte LE@16, uint32@18, uint32@22); parse-only port, field layout matches Java exactly.

### opCode 55 — LID_BOLUS_ACTIVATED

`BolusActivatedHistoryLog` (java) ↔ `BolusActivatedHistoryLog` (swift) ↔ `LidBolusActivated` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| bolusId | `bolusId`<br>uint16 @10 | `bolusId`<br>uint16 @10 | `bolusId`<br>uint16 @12 | ❌ py-diverges-from-java | bolusId: java Bytes.readShort(raw,10) = swift Bytes.readShort(cargo,10), py struct UINT16@12 — py diverges by +2 bytes |
| iob | `iob`<br>float32 @14 | `iob`<br>float32 @14 | `iob`<br>float32 @14 | ✅ match | iob: float32@14 on all three sides (java readFloat(raw,14), swift readFloat(cargo,14), py FLOAT32@14) |
| bolusSize | `bolusSize`<br>float32 @18 | `bolusSize`<br>float32 @18 | `bolusSize`<br>float32 @18 | ✅ match | bolusSize: float32@18 on all three sides |
| selectedIob | — | — | `selectedIobRaw`<br>uint8 @11 | ❌ missing-in-java | selectedIob: py uint8@11 with SelectediobEnum {0: Mudaliar IOB, 1: Swan IOB Meal}; absent in BOTH java and swift parsers (java/swift never read byte 11 as a separate field — byte 11 falls inside java's uint16 bolusId@10-11, so the layouts conflict) |

**Enum / value-map findings:**

- ⚠️ `selectedIob` — *missing-in-java*: Python defines SelectediobMap/SelectediobEnum (0=Mudaliar IOB, 1=Swan IOB Meal); Java and Swift have no selectedIob field or enum at all

**Inconsistencies:**

- [PY-DIVERGENCE] bolusId: java uint16@10 = swift uint16@10, py uint16@12 — py reads bolusId 2 bytes later; combined with py's selectedIob uint8@11, python treats bytes 10-13 as {pad@10?, selectedIob u8@11, bolusId u16@12-13} while java/swift treat them as {bolusId u16@10-11, unused@12-13}
- [PY-DIVERGENCE] selectedIob: py uint8@11 (enum 0=Mudaliar IOB, 1=Swan IOB Meal) has no counterpart in java or swift; byte 11 is consumed by java/swift's bolusId uint16@10-11
- Java internal parse/serializer mismatch: parse() reads iob@14 and bolusSize@18, but buildCargo() emits [55,0]+uint32(ts)+uint32(seq)+firstTwoBytesLittleEndian(bolusId)+toFloat(iob)+toFloat(bolusSize), placing iob@12-15 and bolusSize@16-19 with no 2-byte gap at 12-13 — round-tripping buildCargo through parse() shifts iob/bolusSize by 2 bytes (upstream pumpX2 bug, not a TandemKit issue)
- Swift buildCargo() faithfully ports the same internal mismatch (iob emitted at 12, bolusSize at 16, while init(cargo:) reads 14/18) — identical to Java, so not a port bug, but Swift round-trip is also self-inconsistent

### opCode 57 — LID_IDP_MSG2

`IdpActionMsg2HistoryLog` (java) ↔ `IdpActionMsg2HistoryLog` (swift) — *no Python parser* — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| idp | `idp`<br>uint8 @10 | `idp`<br>uint8 @10 | — | ✅ match | idp: java uint8@10 (raw[10]) = swift uint8@10 (cargo[10]); serializers also both emit it at offset 10 |
| name | `name`<br>string(8) @18 | `name`<br>string(8) @18 | — | ✅ match | name: java string(8)@18 (Bytes.readString(raw,18,8)) = swift string(8)@18 (Bytes.readString(cargo,18,8)). Note both buildCargo() serializers write the 8-byte string at offset 11-18 (immediately after idp), disagreeing with their own parsers' offset 18 — a shared internal quirk inherited from the Java reference, not a cross-side divergence |

**Inconsistencies:**

- Internal parse/serialize mismatch shared by Java and Swift: parse() reads name at offset 18-25 (Bytes.readString(raw, 18, 8)) but buildCargo() writes Bytes.writeString(name, 8) contiguously after the idp byte at offset 11-18; the Swift port replicates this exactly (init(cargo:) reads @18, buildCargo writes @11), so round-tripped records would decode name from the zero-padding region on both sides. Inherited from the pumpX2 reference — NOT a [PORT-BUG].

### opCode 59 — LID_BOLEX_ACTIVATED

`BolexActivatedHistoryLog` (java) ↔ `BolexActivatedHistoryLog` (swift) ↔ `LidBolexActivated` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| selectedIob | — | — | `selectedIobRaw`<br>uint8 @11 | ❌ missing-in-java | Python-only field: uint8@11 with enum map (0=Mudaliar IOB, 1=Swan IOB Meal). Java parse() reads bolusId as uint16@10-11, so Java folds byte 11 into bolusId (little-endian high byte) instead of exposing selectedIob; Swift ports Java exactly and also lacks it. |
| bolusId | `bolusId`<br>uint16 @10 | `bolusId`<br>uint16 @10 | `bolusId`<br>uint16 @12 | ❌ py-diverges-from-java | bolusId: java uint16@10 (Bytes.readShort(raw,10)) = swift uint16@10 (Bytes.readShort(cargo,10)); py uint16@12 (unpack_from UINT16 at 12) — py diverges by +2 bytes. Python treats byte 10 as unread padding and byte 11 as selectedIob; Java/Swift treat 10-11 as the bolusId field and leave 12-13 unread. |
| iob | `iob`<br>float32 @14 | `iob`<br>float32 @14 | `iob`<br>float32 @14 | ✅ match | float32@14 on all three sides (parsers). Note Java/Swift buildCargo serializers place iob at offset 12, disagreeing with their own parsers (see inconsistencies). |
| bolexSize | `bolexSize`<br>float32 @18 | `bolexSize`<br>float32 @18 | `bolexSize`<br>float32 @18 | ✅ match | float32@18 on all three sides (parsers). Java/Swift buildCargo serializers place it at offset 16, disagreeing with their own parsers. |

**Enum / value-map findings:**

- ⚠️ `selectedIob` — *missing-in-java*: Python defines SelectediobMap/SelectediobEnum {0: Mudaliar IOB, 1: Swan IOB Meal} for the uint8@11 field; Java and Swift have no corresponding field or enum at all.

**Inconsistencies:**

- [PY-DIVERGENCE] bolusId: java uint16@10 = swift uint16@10, py uint16@12 — py reads bolusId two bytes later; py additionally reads selectedIob uint8@11 which java/swift fold into (or ignore within) bytes 10-11. One layout must be wrong: either bolusId is at 10-11 with 12-13 padding (Java/Swift) or byte 10 is padding, 11=selectedIob, 12-13=bolusId (Python).
- [PY-DIVERGENCE] selectedIob uint8@11 (enum 0=Mudaliar IOB, 1=Swan IOB Meal) exists only in Python; missing from Java parse() and Swift init(cargo:).
- Java internal inconsistency (reference bug, faithfully ported to Swift): parse() reads iob@14 and bolexSize@18, but buildCargo() emits opcode(0-1)+time(2-5)+seq(6-9)+bolusId(10-11)+toFloat(iob)@12-15+toFloat(bolexSize)@16-19 with no 2-byte gap after bolusId — round-tripping buildCargo through parse() yields shifted iob/bolexSize values. Swift buildCargo has the identical layout, so this is NOT a port bug, but both serializers disagree with their own parsers by 2 bytes.

### opCode 60 — LID_DATA_LOG_CORRUPTION

`DataLogCorruptionHistoryLog` (java) ↔ `DataLogCorruptionHistoryLog` (swift) ↔ `LidDataLogCorruption` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| block | — | — | `block`<br>uint32 @10 | ❌ missing-in-java | py uint32@10; absent from BOTH java and swift parsers (Java parse() only calls parseBase and validates length 26; Swift has no init-time field parsing). Java is baseline, so status=missing-in-java; it is equally missing in swift. |
| reason | — | — | `reason`<br>uint8 @17 | ❌ missing-in-java | py uint8@17; absent from BOTH java and swift parsers. Note python skips bytes 14-16 between block (10-13) and reason (17), suggesting the layout comes from Tandem cloud export metadata rather than the pumpX2 record model. |

**Inconsistencies:**

- [PY-DIVERGENCE] Python LidDataLogCorruption decodes payload fields block (uint32@10) and reason (uint8@17) that the Java reference does not parse at all — Java parse() only validates raw.length==26 and calls parseBase(raw), and buildCargo() emits only opcode+timestamp+seqNum with zero-filled payload. Swift matches Java (header-only), so Java/Swift consumers silently drop block/reason data that Python surfaces.
- Java buildCargo(pumpTimeSec, sequenceNum) and Swift buildCargo produce a record with an all-zero payload; if the pump actually populates block@10 and reason@17 (as Python assumes), round-tripping a real record through Java/Swift constructors loses those bytes.

### opCode 61 — LID_CANNULA_FILLED

`CannulaFilledHistoryLog` (java) ↔ `CannulaFilledHistoryLog` (swift) ↔ `LidCannulaFilled` (py) — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| primeSize | `primeSize`<br>float32 @10 | `primeSize`<br>float32 @10 | `primeSize`<br>float32 @10 | ✅ match | primeSize: java float32@10 (Bytes.readFloat(raw, 10)) = swift float32@10 (Bytes.readFloat(cargo, 10)) = py float32@10 (unpack_from(FLOAT32, raw[:26], 10)); all sides agree |
| completionStatus | — | — | `completionStatusRaw`<br>uint32 @14 | ❌ missing-in-java | completionStatus: py uint32@14 with CompletionstatusEnum {0:User Aborted, 1:Terminated by Alarm, 2:Terminated by Malfunction, 3:Completed}; absent in BOTH java and swift parsers (java parse() only reads primeSize@10 and buildCargo pads bytes 14-25 via fillCargo). Java field would be missing-in-swift-and-python-style inverse: field exists only in Python. |

**Enum / value-map findings:**

- ⚠️ `completionStatus` — *missing-in-java*: Python defines CompletionstatusMap/CompletionstatusEnum: 0=User Aborted, 1=Terminated by Alarm, 2=Terminated by Malfunction, 3=Completed (uint32@14). Java and Swift have no corresponding field or enum; bytes 14-17 are unparsed/zero-padded on those sides.

**Inconsistencies:**

- [PY-DIVERGENCE] completionStatus: python parses uint32@14 (CompletionstatusEnum 0=User Aborted, 1=Terminated by Alarm, 2=Terminated by Malfunction, 3=Completed) but java reference parses only primeSize float32@10 and leaves bytes 14-25 unparsed (buildCargo zero-pads them via fillCargo); swift matches java. Field exists only in Python — likely real pump data that pumpX2/TandemKit drop.

### opCode 63 — LID_TUBING_FILLED

`TubingFilledHistoryLog` (java) ↔ `TubingFilledHistoryLog` (swift) ↔ `LidTubingFilled` (py) — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| primeSize | `primeSize`<br>float32 @10 | `primeSize`<br>float32 @10 | `primeSize`<br>float32 @10 | ✅ match | java Bytes.readFloat(raw,10) = swift Bytes.readFloat(cargo,10) = py struct.unpack_from(FLOAT32, raw, 10); all three agree. Java buildCargo and Swift buildCargo both serialize primeSize immediately after the 10-byte header (offset 10), internally consistent with their parsers. |
| completionStatus | — | — | `completionStatusRaw`<br>uint32 @14 | ❌ missing-in-swift-and-python | Python-only field: uint32@14 with CompletionstatusEnum {0=User Aborted, 1=Terminated by Alarm, 2=Terminated by Malfunction, 3=Completed}. Absent from Java parse()/buildCargo() and from the Swift port (bytes 14-17 are zero-padding in Java/Swift fillCargo). Status enum lacks a 'missing-in-java-and-swift' value; recorded as missing-in-swift-and-python does not fit either — this field exists ONLY in Python, so treat as missing-in-java on the Java side and missing-in-swift on the Swift side. |
| position | — | — | `position`<br>uint32 @18 | ❌ missing-in-java | Python-only field: uint32@18 (documented as 'counts'). Absent from Java parse()/buildCargo() and the Swift port; those implementations leave bytes 18-21 as zero fill. Also missing-in-swift. |

**Enum / value-map findings:**

- ⚠️ `completionStatus` — *missing-in-java*: Python defines CompletionstatusMap/CompletionstatusEnum {0:User Aborted, 1:Terminated by Alarm, 2:Terminated by Malfunction, 3:Completed} for uint32@14; Java and Swift have no corresponding field or enum at all.

**Inconsistencies:**

- [PY-DIVERGENCE] completionStatus: py uint32@14 (enum 0=User Aborted, 1=Terminated by Alarm, 2=Terminated by Malfunction, 3=Completed) is parsed by Python but entirely absent from Java (reference parses only primeSize float32@10) and from the Swift port.
- [PY-DIVERGENCE] position: py uint32@18 ('counts') is parsed by Python but absent from both Java and Swift, which treat bytes 14-25 as zero padding.

### opCode 64 — LID_BOLUS_REQUESTED_MSG1

`BolusRequestedMsg1HistoryLog` (java) ↔ `BolusRequestedMsg1HistoryLog` (swift) ↔ `LidBolusRequestedMsg1` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| bolusId | `bolusId`<br>uint16 @10 | `bolusId`<br>uint16 @10 | `bolusId`<br>uint16 @12 | ❌ py-diverges-from-java | bolusId: java uint16@10 = swift uint16@10; py uint16@12 — py reads it two bytes later |
| bolusType | `bolusTypeId`<br>uint8 @12 | `bolusTypeId`<br>uint8 @12 | `bolusTypeRaw`<br>uint8 @11 | ❌ py-diverges-from-java | bolusType: java uint8@12 = swift uint8@12; py uint8@11 — py diverges. Semantics also differ: java/swift decode it as a bitmask Set via BolusDeliveryHistoryLog.BolusType.fromBitmask (FOOD1=1, CORRECTION=2, EXTENDED=4, FOOD2=8); py treats it as a scalar enum (Insulin=0, Carb=1, AutomaticCorrection=2, Remote=3) |
| correctionBolusIncluded | `correctionBolusIncluded`<br>uint8 @13 | `correctionBolusIncluded`<br>uint8 @13 | `correctionBolusIncludedRaw`<br>uint8 @10 | ❌ py-diverges-from-java | correctionBolusIncluded: java uint8@13 (bool, raw[13]!=0) = swift uint8@13 (cargo[13]!=0); py uint8@10 — py diverges |
| carbAmount | `carbAmount`<br>uint16 @14 | `carbAmount`<br>uint16 @14 | `carbAmount`<br>uint16 @16 | ❌ py-diverges-from-java | carbAmount (grams): java uint16@14 = swift uint16@14; py uint16@16 — py diverges (py's carbAmount sits where java's bg is) |
| bg | `bg`<br>uint16 @16 | `bg`<br>uint16 @16 | `bg`<br>uint16 @14 | ❌ py-diverges-from-java | bg (mg/dL): java uint16@16 = swift uint16@16; py uint16@14 — py diverges (bg and carbAmount are swapped relative to java) |
| iob | `iob`<br>float32 @18 | `iob`<br>float32 @18 | `iob`<br>float32 @18 | ✅ match | iob: float32@18 on all three sides |
| carbRatio | `carbRatio`<br>uint32 @22 | `carbRatio`<br>uint32 @22 | `carbRatioRaw`<br>uint32 @22 | ✅ match | carbRatio: uint32@22 on all three sides; py additionally exposes a scaled carbRatio property = raw*0.001 (g/u), java/swift return the raw uint32 only — presentation difference, not a layout mismatch |

**Enum / value-map findings:**

- ⚠️ `bolusType` — *values-differ*: java/swift: bitmask Set from BolusDeliveryHistoryLog.BolusType {FOOD1=1, CORRECTION=2, EXTENDED=4, FOOD2=8} via fromBitmask(); python: scalar BolustypeEnum {Insulin=0, Carb=1, AutomaticCorrection=2, Remote=3}. Value sets and interpretation model (bitmask vs scalar) are entirely different; e.g. raw value 3 = {FOOD1, CORRECTION} in java/swift but 'Remote' in python
- ⚠️ `correctionBolusIncluded` — *partial*: java/swift decode as boolean (any nonzero = true); python CorrectionbolusincludedEnum {No=0, Yes=1} returns None (with error log) for any raw value other than 0/1

**Inconsistencies:**

- [PY-DIVERGENCE] Python field layout at offsets 10-17 is scrambled relative to Java: java has bolusId uint16@10, bolusType uint8@12, correctionBolusIncluded uint8@13, carbAmount uint16@14, bg uint16@16; python has correctionBolusIncluded uint8@10, bolusType uint8@11, bolusId uint16@12, bg uint16@14, carbAmount uint16@16. Only iob float32@18 and carbRatio uint32@22 agree.
- [PY-DIVERGENCE] bolusType value semantics differ: java/swift treat the byte as a bitmask (FOOD1=1, CORRECTION=2, EXTENDED=4, FOOD2=8, decoded to a Set); python treats it as a scalar enum (Insulin=0, Carb=1, AutomaticCorrection=2, Remote=3).
- Python carbRatio property applies a *0.001 scale (g/u) to the raw uint32; java getCarbRatio() and swift carbRatio return the raw milli-units value — consumers comparing across sides will see values 1000x apart.

### opCode 65 — LID_BOLUS_REQUESTED_MSG2

`BolusRequestedMsg2HistoryLog` (java) ↔ `BolusRequestedMsg2HistoryLog` (swift) ↔ `LidBolusRequestedMsg2` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| bolusId | `bolusId`<br>uint16 @10 | `bolusId`<br>uint16 @10 | `bolusId`<br>uint16 @12 | ❌ py-diverges-from-java | java uint16@10 = swift uint16@10; py uint16@12 — py diverges |
| options | `options`<br>uint8 @12 | `options`<br>uint8 @12 | `optionsRaw`<br>uint8 @11 | ❌ py-diverges-from-java | java uint8@12 = swift uint8@12; py uint8@11 — py diverges |
| standardPercent | `standardPercent`<br>uint8 @13 | `standardPercent`<br>uint8 @13 | `standardPercent`<br>uint8 @10 | ❌ py-diverges-from-java | java uint8@13 = swift uint8@13; py uint8@10 — py diverges |
| duration | `duration`<br>uint16 @14 | `duration`<br>uint16 @14 | `duration`<br>uint16 @16 | ❌ py-diverges-from-java | java uint16@14 = swift uint16@14; py uint16@16 — py diverges (py's @16 slot is Java's spare1) |
| spare1 | `spare1`<br>uint16 @16 | `spare1`<br>uint16 @16 | — | ❌ missing-in-python | java uint16@16 = swift uint16@16; py has no spare1 field (py reads duration at @16); py also never reads bytes 14-15 |
| isf | `isf`<br>uint16 @18 | `isf`<br>uint16 @18 | `isf`<br>uint16 @20 | ❌ py-diverges-from-java | java uint16@18 = swift uint16@18; py uint16@20 — py diverges (isf and targetBG slots are swapped relative to Java) |
| targetBG | `targetBG`<br>uint16 @20 | `targetBG`<br>uint16 @20 | `targetBg`<br>uint16 @18 | ❌ py-diverges-from-java | java uint16@20 = swift uint16@20; py uint16@18 — py diverges (swapped with isf relative to Java) |
| userOverride | `userOverride`<br>uint8 @22 | `userOverride`<br>uint8 @22 | `userOverrideRaw`<br>uint8 @25 | ❌ py-diverges-from-java | java bool(uint8)@22 = swift bool(uint8)@22; py uint8@25 — py diverges; py never reads byte 22 |
| declinedCorrection | `declinedCorrection`<br>uint8 @23 | `declinedCorrection`<br>uint8 @23 | `declinedCorrectionRaw`<br>uint8 @24 | ❌ py-diverges-from-java | java bool(uint8)@23 = swift bool(uint8)@23; py uint8@24 — py diverges |
| selectedIOB | `selectedIOB`<br>uint8 @24 | `selectedIOB`<br>uint8 @24 | `selectedIobRaw`<br>uint8 @23 | ❌ py-diverges-from-java | java uint8@24 = swift uint8@24; py uint8@23 — py diverges |
| spare2 | `spare2`<br>uint8 @25 | `spare2`<br>uint8 @25 | — | ❌ missing-in-python | java uint8@25 = swift uint8@25; py has no spare2 (py reads userOverride at @25). Swift init(cargo:) defensively reads spare2 as 0 when cargo.count <= 25 (Java Validate.isTrue(raw.length==26) would throw instead) — behavioral nuance only, not a layout divergence |

**Enum / value-map findings:**

- ⚠️ `options` — *partial*: Python defines OptionsEnum/OptionsMap: 0=Standard Bolus, 1=Extended Bolus, 2=Quick Bolus, 3=Automatic Bolus, 4=BLE Standard Bolus, 5=BLE Extended Bolus, 6=Eating Soon Automatic Bolus, 7=Late Bolus. Java and Swift expose options as a plain int with no enum or javadoc value comments.
- ⚠️ `selectedIOB` — *partial*: Python defines SelectediobEnum/SelectediobMap: 0=Mudaliar IOB, 1=Swan IOB Meal. Java getSelectedIOB() is documented 'TODO(unknown)' and Swift has no enum — Python carries value semantics missing from Java/Swift.
- ✅ `userOverride` — *match*: Python UseroverrideEnum {0=No, 1=Yes} agrees with Java/Swift bool (raw != 0) semantics.
- ✅ `declinedCorrection` — *match*: Python DeclinedcorrectionEnum {0=No, 1=Yes} agrees with Java/Swift bool (raw != 0) semantics.

**Inconsistencies:**

- [PY-DIVERGENCE] Python uses an entirely reordered payload layout vs Java: py standardPercent uint8@10 / options uint8@11 / bolusId uint16@12 vs java bolusId uint16@10 / options uint8@12 / standardPercent uint8@13
- [PY-DIVERGENCE] duration: java uint16@14 = swift uint16@14, py uint16@16 — py reads duration where Java has spare1, and py never reads bytes 14-15
- [PY-DIVERGENCE] isf/targetBG swapped: java isf uint16@18 & targetBG uint16@20 vs py targetBg uint16@18 & isf uint16@20
- [PY-DIVERGENCE] trailing bytes reordered: java userOverride@22, declinedCorrection@23, selectedIOB@24, spare2@25 vs py selectedIob@23, declinedCorrection@24, userOverride@25 (py never reads byte 22; py has no spare1/spare2 fields)
- Enum gap: Python documents options values 0-7 (Standard/Extended/Quick/Automatic/BLE Standard/BLE Extended/Eating Soon Automatic/Late Bolus) and selectedIOB values 0-1 (Mudaliar IOB / Swan IOB Meal); Java (getSelectedIOB javadoc says TODO(unknown)) and Swift expose plain ints with no value maps
- Minor internal nuance (not a layout bug): Swift init(cargo:) reads spare2 as 'cargo.count > 25 ? cargo[25] : 0', silently tolerating a 25-byte record where Java's parse() enforces raw.length == 26; Swift buildCargo() otherwise mirrors Java buildCargo() field-for-field

### opCode 66 — LID_BOLUS_REQUESTED_MSG3

`BolusRequestedMsg3HistoryLog` (java) ↔ `BolusRequestedMsg3HistoryLog` (swift) ↔ `LidBolusRequestedMsg3` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| bolusId | `bolusId`<br>uint16 @10 | `bolusId`<br>uint16 @10 | `bolusId`<br>uint16 @12 | ❌ py-diverges-from-java | bolusId: java uint16@10 (Bytes.readShort(raw,10)) = swift uint16@10 (Bytes.readShort(cargo,10)); py uint16@12 (unpack_from(UINT16,raw,12)) — py reads at java's spare offset, off by 2 bytes |
| spare | `spare`<br>uint16 @12 | `spare`<br>uint16 @12 | — | ❌ missing-in-python | spare: java uint16@12 = swift uint16@12; absent in python (its bolusId occupies offset 12 instead) |
| foodBolusSize | `foodBolusSize`<br>float32 @14 | `foodBolusSize`<br>float32 @14 | `foodBolusSize`<br>float32 @14 | ✅ match | float32@14 on all three sides |
| correctionBolusSize | `correctionBolusSize`<br>float32 @18 | `correctionBolusSize`<br>float32 @18 | `correctionBolusSize`<br>float32 @18 | ✅ match | float32@18 on all three sides |
| totalBolusSize | `totalBolusSize`<br>float32 @22 | `totalBolusSize`<br>float32 @22 | `totalBolusSize`<br>float32 @22 | ✅ match | float32@22 on all three sides |

**Inconsistencies:**

- [PY-DIVERGENCE] bolusId: java/swift read uint16@10; python LidBolusRequestedMsg3.build reads uint16@12 — python's bolusId lands on the record's spare field, so python decodes spare as bolusId (unless cloud exports genuinely shift this field, python's binary-path bolusId is wrong)
- [PY-DIVERGENCE] spare (java uint16@12, swift uint16@12) has no python counterpart; python has no field at offset 10 at all — bytes 10-11 are never decoded in python

### opCode 67 — LID_USB_ENUMERATED

`UsbEnumeratedHistoryLog` (java) ↔ `UsbEnumeratedHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| negotiatedCurrentMilliAmps | `negotiatedCurrentMilliAmps`<br>uint8 @10 | `negotiatedCurrentmA`<br>uint8 @10 | — | ✅ match | java uint8@10 (raw[10]) = swift uint8@10 (Int(cargo[10])); both serializers write a single byte at offset 10 after the 10-byte header. Name differs (negotiatedCurrentMilliAmps vs negotiatedCurrentmA) — cosmetic only. |

_No inconsistencies found._

### opCode 68 — LID_IDP_TD_SEG

`IdpTimeDependentSegmentHistoryLog` (java) ↔ `IdpTimeDependentSegmentHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| idp | `idp`<br>uint8 @10 | `idp`<br>uint8 @10 | — | ✅ match | java raw[10] uint8 = swift cargo[10] uint8 |
| status | `status`<br>uint8 @11 | `status`<br>uint8 @11 | — | ✅ match | java raw[11] uint8 = swift cargo[11] uint8 |
| segmentIndex | `segmentIndex`<br>uint8 @12 | `segmentIndex`<br>uint8 @12 | — | ✅ match | java raw[12] uint8 = swift cargo[12] uint8 |
| modificationType | `modificationType`<br>uint8 @13 | `modificationType`<br>uint8 @13 | — | ✅ match | java raw[13] uint8 = swift cargo[13] uint8 |
| startTime | `startTime`<br>uint16 @14 | `startTime`<br>uint16 @14 | — | ✅ match | java Bytes.readShort(raw,14) = swift Bytes.readShort(cargo,14) |
| basalRate | `basalRate`<br>uint16 @16 | `basalRate`<br>uint16 @16 | — | ✅ match | java Bytes.readShort(raw,16) = swift Bytes.readShort(cargo,16) |
| isf | `isf`<br>uint16 @18 | `isf`<br>uint16 @18 | — | ✅ match | java Bytes.readShort(raw,18) = swift Bytes.readShort(cargo,18) |
| targetBg | `targetBg`<br>uint32 @20 | `targetBg`<br>uint32 @20 | — | ✅ match | java Bytes.readUint32(raw,20) = swift Bytes.readUint32(cargo,20) |
| carbRatio | `carbRatio`<br>uint8 @24 | `carbRatio`<br>uint8 @24 | — | ✅ match | java raw[24] uint8 = swift cargo[24] uint8 |

_No inconsistencies found._

### opCode 69 — LID_IDP

`IdpActionHistoryLog` (java) ↔ `TandemCore.IdpActionHistoryLog (Sources/TandemCore/Messages/HistoryLog/IdpActionHistoryLog.swift)` (swift) — *no Python parser* — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| idp | `idp`<br>uint8 @10 | `idp`<br>uint8 @10 | — | ✅ match | java uint8@10 (raw[10]) = swift uint8@10 (cargo[10]); no python parser |
| status | `status`<br>uint8 @11 | `status`<br>uint8 @11 | — | ✅ match | java uint8@11 = swift uint8@11; no enum/value map on either side despite name suggesting coded action values |
| sourceIdp | `sourceIdp`<br>uint8 @12 | `sourceIdp`<br>uint8 @12 | — | ✅ match | java uint8@12 = swift uint8@12 |
| name | `name`<br>string(8) @18 | `name`<br>string(8) @18 | — | ✅ match | parse side: java Bytes.readString(raw,18,8) = swift Bytes.readString(cargo,18,8). Serialize side: BOTH buildCargo() implementations emit the name at offset 13 (immediately after sourceIdp@12) with no padding for bytes 13-17, so serializer disagrees with parser identically in both codebases — Swift faithfully ports Java's internal round-trip bug |

**Inconsistencies:**

- Internal serializer/parser mismatch inherited from the Java reference (NOT a Swift port bug — Swift matches Java byte-for-byte): parse() reads name as string(8)@18, but buildCargo() concatenates header(2)+pumpTimeSec(4)+seqNum(4)+idp(1)+status(1)+sourceIdp(1)+writeString(name,8), placing the name at offsets 13-20; bytes 13-17 that parse() skips are never emitted, so a constructed record round-trips with a corrupted/truncated name (only name bytes landing at 18-20 plus fillCargo zero padding survive). Present identically in IdpActionHistoryLog.java lines 52-61 and IdpActionHistoryLog.swift lines 44-63.

### opCode 70 — LID_IDP_BOLUS

`IdpBolusHistoryLog` (java) ↔ `TandemCore/Messages/HistoryLog/IdpBolusHistoryLog.swift IdpBolusHistoryLog` (swift) — *no Python parser* — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| idp | `idp`<br>uint8 @10 | `idp`<br>uint8 @10 | — | ✅ match | idp: java uint8@10 (raw[10]) = swift uint8@10 (cargo[10]) |
| modification | `modification`<br>uint8 @11 | `modification`<br>uint8 @11 | — | ✅ match | modification: java uint8@11 = swift uint8@11 |
| bolusStatus | `bolusStatus`<br>uint8 @12 | `bolusStatus`<br>uint8 @12 | — | ✅ match | bolusStatus: java uint8@12 = swift uint8@12; no enum/value map on either side |
| insulinDuration | `insulinDuration`<br>uint16 @14 | `insulinDuration`<br>uint16 @14 | — | ✅ match | insulinDuration: java Bytes.readShort(raw,14) = swift Bytes.readShort(cargo,14); parse skips byte 13 on both sides |
| maxBolusSize | `maxBolusSize`<br>uint16 @16 | `maxBolusSize`<br>uint16 @16 | — | ✅ match | maxBolusSize: java uint16@16 = swift uint16@16 |
| bolusEntryType | `bolusEntryType`<br>uint8 @18 | `bolusEntryType`<br>uint8 @18 | — | ✅ match | bolusEntryType: java uint8@18 = swift uint8@18; no enum/value map on either side |

**Inconsistencies:**

- Internal parse/serialize offset disagreement present IDENTICALLY in both Java (reference) and Swift, so NOT a porting bug: parse() reads insulinDuration@14, maxBolusSize@16, bolusEntryType@18 (skipping a padding byte at offset 13), but buildCargo() writes the fields contiguously after bolusStatus@12 — insulinDuration lands at 13-14, maxBolusSize at 15-16, bolusEntryType at 17. A record built by buildCargo() and re-parsed would decode shifted values on both sides equally (Java IdpBolusHistoryLog.java lines 47-66; Swift IdpBolusHistoryLog.swift lines 22-84). Swift faithfully mirrors the reference, so cross-implementation decoding of real pump records is consistent.

### opCode 71 — LID_IDP_LIST

`IdpListHistoryLog` (java) ↔ `IdpListHistoryLog` (swift) — *no Python parser* — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| numProfiles | `numProfiles`<br>uint8 @10 | `numProfiles`<br>uint8 @10 | — | ✅ match | java uint8@10 = swift uint8@10 |
| slot1 | `slot1`<br>uint8 @14 | `slot1`<br>uint8 @14 | — | ✅ match | java uint8@14 = swift uint8@14; but both serializers write slot1 at offset 11 (see inconsistencies) |
| slot2 | `slot2`<br>uint8 @15 | `slot2`<br>uint8 @15 | — | ✅ match | java uint8@15 = swift uint8@15; serializers write slot2 at offset 12 |
| slot3 | `slot3`<br>uint8 @16 | `slot3`<br>uint8 @16 | — | ✅ match | java uint8@16 = swift uint8@16; serializers write slot3 at offset 13 |
| slot4 | `slot4`<br>uint8 @17 | `slot4`<br>uint8 @17 | — | ✅ match | java uint8@17 = swift uint8@17; serializers write slot4 at offset 14 |
| slot5 | `slot5`<br>uint8 @18 | `slot5`<br>uint8 @18 | — | ✅ match | java uint8@18 = swift uint8@18; serializers write slot5 at offset 15 |
| slot6 | `slot6`<br>uint8 @19 | `slot6`<br>uint8 @19 | — | ✅ match | java uint8@19 = swift uint8@19; serializers write slot6 at offset 16 |

**Inconsistencies:**

- Internal parse/serialize mismatch inherited from the Java reference (identical in both, so NOT a port bug): parse() reads slot1..slot6 at uint8@14..19 with bytes 11-13 unread, but buildCargo() emits numProfiles@10 followed immediately by slot1..slot6 at contiguous offsets 11..16 (Java IdpListHistoryLog.java:52-57 vs 66-72; Swift IdpListHistoryLog.swift:25-30 vs 82-88). Synthetic cargo built via buildCargo would decode as slot1=slot4-input, slot2=slot5-input, slot3=slot6-input, slot4..6=0 in both codebases.

### opCode 73 — LID_PARAM_PUMP_SETTINGS

`ParamChangePumpSettingsHistoryLog` (java) ↔ `ParamChangePumpSettingsHistoryLog` (swift) — *no Python parser* — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| modification | `modification`<br>uint8 @10 | `modification`<br>uint8 @10 | — | ✅ match | java uint8@10 (raw[10]) = swift uint8@10 (cargo[10]) |
| status | `status`<br>uint16 @12 | `status`<br>uint16 @12 | — | ✅ match | java uint16@12 (Bytes.readShort(raw,12)) = swift uint16@12; byte 11 is unread padding in both parsers, but both buildCargo() serializers write status at 11-12 (see inconsistencies) |
| lowInsulinThreshold | `lowInsulinThreshold`<br>uint8 @14 | `lowInsulinThreshold`<br>uint8 @14 | — | ✅ match | java uint8@14 = swift uint8@14 |
| cannulaPrimeSize | `cannulaPrimeSize`<br>uint8 @15 | `cannulaPrimeSize`<br>uint8 @15 | — | ✅ match | java uint8@15 = swift uint8@15 |
| isFeatureLocked | `isFeatureLocked`<br>uint8 @16 | `isFeatureLocked`<br>uint8 @16 | — | ✅ match | java uint8@16 = swift uint8@16 |
| autoShutdownEnabled | `autoShutdownEnabled`<br>uint8 @17 | `autoShutdownEnabled`<br>uint8 @17 | — | ✅ match | java uint8@17 = swift uint8@17 |
| oledTimeout | `oledTimeout`<br>uint8 @19 | `oledTimeout`<br>uint8 @19 | — | ✅ match | java uint8@19 = swift uint8@19; byte 18 is unread padding in both parsers |
| autoShutdownDuration | `autoShutdownDuration`<br>uint16 @20 | `autoShutdownDuration`<br>uint16 @20 | — | ✅ match | java uint16@20 (Bytes.readShort(raw,20)) = swift uint16@20 |

**Inconsistencies:**

- Java-internal serializer/parser mismatch (inherited verbatim by Swift, so not a port divergence): buildCargo() omits the two padding bytes the parser expects. Serializer writes modification@10, status@11-12, lowInsulinThreshold@13, cannulaPrimeSize@14, isFeatureLocked@15, autoShutdownEnabled@16, oledTimeout@17, autoShutdownDuration@18-19, while parse()/init(cargo:) read status@12-13, lowInsulinThreshold@14, cannulaPrimeSize@15, isFeatureLocked@16, autoShutdownEnabled@17, oledTimeout@19, autoShutdownDuration@20-21 (bytes 11 and 18 padding). A record built via the field-based constructor and re-parsed decodes every field after modification incorrectly, in BOTH Java and Swift.

### opCode 74 — LID_PARAM_GLOBAL_SETTINGS

`ParamChangeGlobalSettingsHistoryLog` (java) ↔ `ParamChangeGlobalSettingsHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| modifiedData | `modifiedData`<br>uint8 @10 | `modifiedData`<br>uint8 @10 | — | ✅ match | java raw[10] = swift cargo[10] |
| qbDataStatus | `qbDataStatus`<br>uint8 @11 | `qbDataStatus`<br>uint8 @11 | — | ✅ match | java raw[11] = swift cargo[11] |
| qbActive | `qbActive`<br>uint8 @12 | `qbActive`<br>uint8 @12 | — | ✅ match | java raw[12] = swift cargo[12] |
| qbDataEntryType | `qbDataEntryType`<br>uint8 @13 | `qbDataEntryType`<br>uint8 @13 | — | ✅ match | java raw[13] = swift cargo[13] |
| qbIncrementUnits | `qbIncrementUnits`<br>uint16 @14 | `qbIncrementUnits`<br>uint16 @14 | — | ✅ match | java Bytes.readShort(raw,14) = swift Bytes.readShort(cargo,14) |
| qbIncrementCarbs | `qbIncrementCarbs`<br>uint16 @16 | `qbIncrementCarbs`<br>uint16 @16 | — | ✅ match | java Bytes.readShort(raw,16) = swift Bytes.readShort(cargo,16) |
| buttonVolume | `buttonVolume`<br>uint8 @18 | `buttonVolume`<br>uint8 @18 | — | ✅ match | java raw[18] = swift cargo[18] |
| qbVolume | `qbVolume`<br>uint8 @19 | `qbVolume`<br>uint8 @19 | — | ✅ match | java raw[19] = swift cargo[19] |
| bolusVolume | `bolusVolume`<br>uint8 @20 | `bolusVolume`<br>uint8 @20 | — | ✅ match | java raw[20] = swift cargo[20] |
| reminderVolume | `reminderVolume`<br>uint8 @21 | `reminderVolume`<br>uint8 @21 | — | ✅ match | java raw[21] = swift cargo[21] |
| alertVolume | `alertVolume`<br>uint8 @22 | `alertVolume`<br>uint8 @22 | — | ✅ match | java raw[22] = swift cargo[22] |

_No inconsistencies found._

### opCode 81 — LID_DAILY_BASAL

`DailyBasalHistoryLog` (java) ↔ `DailyBasalHistoryLog` (swift) ↔ `LidDailyBasal` (py) — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| dailyTotalBasal | `dailyTotalBasal`<br>float32 @10 | `dailyTotalBasal`<br>float32 @10 | `dailyTotalBasal`<br>float32 @10 | ✅ match | java float32@10 = swift float32@10 = py float32@10; all agree |
| lastBasalRate | `lastBasalRate`<br>float32 @14 | `lastBasalRate`<br>float32 @14 | `lastBasalRate`<br>float32 @14 | ✅ match | java float32@14 = swift float32@14 = py float32@14; all agree |
| iob | `iob`<br>float32 @18 | `iob`<br>float32 @18 | `iob`<br>float32 @18 | ✅ match | java float32@18 = swift float32@18 = py float32@18; all agree |
| finalEventForDay / batteryChargePercentMSBRaw (byte 22) | `finalEventForDay`<br>uint8 @22 | `finalEventForDay`<br>uint8 @22 | `batteryChargePercentMSBRaw`<br>uint8 @22 | ❌ py-diverges-from-java | Same uint8@22 on all sides but semantics differ: java/swift decode it as boolean finalEventForDay (raw[22]==1, and java javadoc marks it TODO(confirm)); python treats it as the MSB of a 2-byte battery-charge value feeding batteryChargePercent = (256*(MSB-14)+LSB)/(3*256) |
| batteryChargeRaw / batteryChargePercentLSBRaw (byte 23) | `batteryChargeRaw`<br>uint8 @23 | `batteryChargeRaw`<br>uint8 @23 | `batteryChargePercentLSBRaw`<br>uint8 @23 | ✅ match | uint8@23 on all three; java (batteryChargeRaw, signed byte via raw[23]) derives percent as 100*((raw+256.0)/512.0), python (unsigned '>B') treats it as LSB combined with byte 22 via (256*(MSB-14)+LSB)/(3*256) — raw parse matches, derived percent formulas disagree |
| lipoMv | `lipoMv`<br>uint16 @24 | `lipoMv`<br>uint16 @24 | `batteryLipoMilliVolts`<br>uint16 @24 | ✅ match | java uint16@24 = swift uint16@24 = py uint16@24; name differs only (lipoMv vs batteryLipoMilliVolts) |

**Enum / value-map findings:**

- ⚠️ `batteryChargePercent (derived)` — *values-differ*: Not an enum but a derived value map: java getBatteryChargePercent() = 100*((batteryChargeRaw+256.0)/512.0) using only byte 23 (read as signed java byte, range -128..127 -> 25%..~75%); python batteryChargePercent = (256*(batteryChargePercentMSBRaw-14)+batteryChargePercentLSBRaw)/(3*256) using bytes 22 AND 23. Swift ports the raw field but implements no percent conversion at all.

**Inconsistencies:**

- [PY-DIVERGENCE] byte 22: java/swift decode uint8@22 as boolean finalEventForDay (raw[22]==1; java javadoc says TODO(confirm)); python decodes the same uint8@22 as batteryChargePercentMSBRaw, the high byte of a battery-charge value — python has no finalEventForDay concept and java/swift have no MSB concept
- [PY-DIVERGENCE] battery percent formula: java getBatteryChargePercent() = 100*((batteryChargeRaw+256.0)/512.0) from byte 23 only (byte read as signed via raw[23]); python batteryChargePercent = (256*(MSB@22-14)+LSB@23)/(3*256) combining bytes 22-23 — mutually incompatible derived values from identical raw bytes
- Swift port note: no [PORT-BUG] found — init(cargo:) offsets/widths (float32@10/14/18, uint8@22 bool, uint8@23, uint16@24) and buildCargo() ordering exactly mirror Java parse()/buildCargo(); Swift reads cargo[23] as unsigned UInt8 while Java raw[23] is a signed byte, but Swift also omits the getBatteryChargePercent() helper where that sign difference would matter, so decoded raw fields are equivalent for 0..127 and differ only in raw representation (e.g. 0xFF -> -1 java vs 255 swift)

### opCode 82 — LID_FACTORY_RESET

`FactoryResetHistoryLog` (java) ↔ `FactoryResetHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 90 — LID_NEW_DAY

`NewDayHistoryLog` (java) ↔ `NewDayHistoryLog` (swift) ↔ `LidNewDay` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| commandedBasalRate | `commandedBasalRate`<br>float32 @10 | `commandedBasalRate`<br>float32 @10 | `commandedBasalRate`<br>float32 @10 | ✅ match | java float32@10 = swift float32@10 = py float32@10 — all agree; serializers (Java buildCargo / Swift buildCargo) consistent with their parsers |
| featuresBitmask | — | — | `featuresBitmask`<br>uint32 @14 | ❌ missing-in-java | py uint32@14 only; Java parse() reads nothing past offset 13 (buildCargo zero-pads bytes 14-25 via fillCargo) and Swift mirrors Java exactly, so absent in both Java and Swift |
| featureBitmaskIndex | — | — | `featureBitmaskIndex`<br>uint32 @18 | ❌ missing-in-java | py uint32@18 only; absent from Java reference parser and from the Swift port (Swift matches Java, not a port bug) |

**Inconsistencies:**

- [PY-DIVERGENCE] featuresBitmask: py uint32@14 has no counterpart in Java or Swift — pumpX2 reference decodes only commandedBasalRate float32@10 and leaves bytes 14-25 as zero padding
- [PY-DIVERGENCE] featureBitmaskIndex: py uint32@18 has no counterpart in Java or Swift — extra Python-only field beyond the Java reference layout

### opCode 93 — LID_CORRECTION_DECLINED

`CorrectionDeclinedHistoryLog` (java) ↔ `CorrectionDeclinedHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| bg | `bg`<br>uint16 @10 | `bg`<br>uint16 @10 | — | ✅ match | java Bytes.readShort(raw,10) = swift Bytes.readShort(cargo,10); no python parser |
| bolusId | `bolusId`<br>uint16 @12 | `bolusId`<br>uint16 @12 | — | ✅ match | java Bytes.readShort(raw,12) = swift Bytes.readShort(cargo,12); no python parser |
| iob | `iob`<br>float32 @14 | `iob`<br>float32 @14 | — | ✅ match | java Bytes.readFloat(raw,14) = swift Bytes.readFloat(cargo,14); no python parser |
| targetBg | `targetBg`<br>uint16 @18 | `targetBg`<br>uint16 @18 | — | ✅ match | java Bytes.readShort(raw,18) = swift Bytes.readShort(cargo,18); no python parser |
| isf | `isf`<br>uint16 @20 | `isf`<br>uint16 @20 | — | ✅ match | java Bytes.readShort(raw,20) = swift Bytes.readShort(cargo,20); no python parser |

_No inconsistencies found._

### opCode 96 — LID_PARAM_REMINDER

`ParamChangeReminderHistoryLog` (java) ↔ `ParamChangeReminderHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| modification | `modification`<br>uint8 @10 | `modification`<br>uint8 @10 | — | ✅ match | java raw[10] uint8 = swift cargo[10] uint8; both serializers emit 1 byte at offset 10 |
| reminderId | `reminderId`<br>uint8 @11 | `reminderId`<br>uint8 @11 | — | ✅ match | java raw[11] uint8 = swift cargo[11] uint8 |
| status | `status`<br>uint8 @12 | `status`<br>uint8 @12 | — | ✅ match | java raw[12] uint8 = swift cargo[12] uint8 |
| enable | `enable`<br>uint8 @13 | `enable`<br>uint8 @13 | — | ✅ match | java raw[13] uint8 = swift cargo[13] uint8 |
| frequencyMinutes | `frequencyMinutes`<br>uint32 @14 | `frequencyMinutes`<br>uint32 @14 | — | ✅ match | java Bytes.readUint32(raw,14) = swift Bytes.readUint32(cargo,14); both serialize via Bytes.toUint32 |
| startTime | `startTime`<br>uint16 @18 | `startTime`<br>uint16 @18 | — | ✅ match | java Bytes.readShort(raw,18) = swift Bytes.readShort(cargo,18); both serialize via firstTwoBytesLittleEndian |
| endTime | `endTime`<br>uint16 @20 | `endTime`<br>uint16 @20 | — | ✅ match | java Bytes.readShort(raw,20) = swift Bytes.readShort(cargo,20) |
| activeDays | `activeDays`<br>uint8 @22 | `activeDays`<br>uint8 @22 | — | ✅ match | java raw[22] uint8 = swift cargo[22] uint8 |

_No inconsistencies found._

### opCode 97 — LID_PARAM_CHANGE_REM_SETTINGS

`ParamChangeRemSettingsHistoryLog` (java) ↔ `ParamChangeRemSettingsHistoryLog` (swift) — *no Python parser* — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| modification | `modification`<br>uint8 @10 | `modification`<br>uint8 @10 | — | ✅ match | java uint8@10 (raw[10]) = swift uint8@10 (cargo[10]) |
| status | `status`<br>uint8 @11 | `status`<br>uint8 @11 | — | ✅ match | java uint8@11 = swift uint8@11 |
| lowBgThreshold | `lowBgThreshold`<br>uint16 @14 | `lowBgThreshold`<br>uint16 @14 | — | ✅ match | java Bytes.readShort(raw,14) = swift Bytes.readShort(cargo,14); parser skips bytes 12-13, but both sides' buildCargo() writes this field contiguously right after status (i.e. at offset 12-13) — internal parse/serialize mismatch inherited identically in both implementations |
| highBgThreshold | `highBgThreshold`<br>uint16 @16 | `highBgThreshold`<br>uint16 @16 | — | ✅ match | java Bytes.readShort(raw,16) = swift Bytes.readShort(cargo,16); buildCargo() on both sides would place it at offset 14-15 instead |
| siteChangeDays | `siteChangeDays`<br>uint8 @18 | `siteChangeDays`<br>uint8 @18 | — | ✅ match | java raw[18] = swift cargo[18]; buildCargo() on both sides would place it at offset 16 instead |

**Inconsistencies:**

- Internal parse/serialize mismatch in the Java reference, faithfully reproduced in Swift (NOT a port bug): parse() reads lowBgThreshold@14, highBgThreshold@16, siteChangeDays@18 (skipping bytes 12-13), but buildCargo() emits the payload contiguously after status@11, placing lowBgThreshold@12-13, highBgThreshold@14-15, siteChangeDays@16. A record built with buildCargo() and re-parsed with parse() would yield lowBgThreshold=highBgThreshold's serialized value shifted, etc. Swift's init(cargo:) and buildCargo() replicate the exact same offsets, so round-trip is broken identically on both sides but the two parsers agree with each other.

### opCode 98 — LID_FILL_ESTIMATE_FINAL

`FillEstimateFinalHistoryLog` (java) ↔ `FillEstimateFinalHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 99 — LID_ARM_INIT

`ArmInitHistoryLog` (java) ↔ `ArmInitHistoryLog` (swift) ↔ `LidArmInit` (py) — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| version | `version`<br>uint32 @10 | `version`<br>uint32 @10 | `version`<br>uint32 @10 | ✅ match | version: java uint32@10 = swift uint32@10 = py uint32@10 (>I) — all agree |
| configABits | `configABits`<br>uint32 @14 | `configABits`<br>uint32 @14 | `configABits`<br>uint32 @14 | ✅ match | configABits: java uint32@14 = swift uint32@14 = py uint32@14 (>I) — all agree |
| configBBits | `configBBits`<br>uint32 @18 | `configBBits`<br>uint32 @18 | `configBBits`<br>uint32 @18 | ✅ match | configBBits: java uint32@18 = swift uint32@18 = py uint32@18 (>I) — all agree |
| numLogEntries | `numLogEntries`<br>uint32 @22 | `numLogEntries`<br>uint32 @22 | `numLogEntries`<br>uint32 @22 | ✅ match | numLogEntries: java uint32@22 = swift uint32@22 = py uint32@22 (>I) — all agree; record fully consumed at byte 26 |

_No inconsistencies found._

### opCode 140 — LID_PLGS_PERIODIC

`PlgsPeriodicHistoryLog` (java) ↔ `PlgsPeriodicHistoryLog` (swift) ↔ `LidPlgsPeriodic` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| timestamp | — | — | `timestamp`<br>uint32 @10 | ❌ missing-in-java | py uint32@10 (labeled 'sec'); Java parse() only calls parseBase(raw) and decodes NO payload fields, Swift port likewise has no payload parsing — absent in both Java and Swift |
| pgv | — | — | `pgv`<br>uint16 @14 | ❌ missing-in-java | py uint16@14 (mg/dL, PLGS glucose value); absent in Java and Swift (both are stub parsers with no payload fields) |
| fmr | — | — | `fmr`<br>uint16 @16 | ❌ missing-in-java | py uint16@16 (mg/dL, five-minute reading); absent in Java and Swift |
| hoMinState | — | — | `hoMinStateRaw`<br>uint8 @18 | ❌ missing-in-java | py uint8@18 with HominstateEnum {0 On and available, 1 On and suspended, 2 Off, 3 On and not available}; absent in Java and Swift |
| ruleState | — | — | `ruleStateRaw`<br>uint8 @19 | ❌ missing-in-java | py uint8@19 with RulestateBitmask {bit0 HO_SUSPEND_RULE, bit1 HO_RECOVERY_RULE, bit2 HO_UNAVAILABLE_RULE}; absent in Java and Swift |
| pgvValid | — | — | `pgvValidRaw`<br>uint8 @20 | ❌ missing-in-java | py uint8@20 boolean (PgvvalidEnum 0=FALSE,1=TRUE); absent in Java and Swift |
| fmrStatus | — | — | `fmrStatusRaw`<br>uint8 @21 | ❌ missing-in-java | py uint8@21 with FmrstatusEnum values 0-6; absent in Java and Swift |
| status | — | — | `statusRaw`<br>uint32 @22 | ❌ missing-in-java | py uint32@22 (fills bytes 22-25, exactly to the 26-byte record end) with StatusBitmask bits 0-13 (bits 2,3,5 unused); absent in Java and Swift |

**Enum / value-map findings:**

- ⚠️ `fmrStatus` — *missing-in-java*: Python FmrstatusEnum/FmrstatusMap {0 No FMR, 1 Periodic glucose reading, 2 Calibration response glucose reading, 3 Sensor session stopped, 4 Sensor session started, 5 Calibration entered, 6 Pumping event}; Java/Swift have no enum because they do not parse the field
- ⚠️ `pgvValid` — *missing-in-java*: Python PgvvalidEnum {0 FALSE, 1 TRUE}; no Java/Swift counterpart
- ⚠️ `ruleState` — *missing-in-java*: Python RulestateBitmask (IntFlag) {1 HO_SUSPEND_RULE, 2 HO_RECOVERY_RULE, 4 HO_UNAVAILABLE_RULE}; no Java/Swift counterpart
- ⚠️ `hoMinState` — *missing-in-java*: Python HominstateEnum {0 On and available, 1 On and suspended, 2 Off, 3 On and not available}; no Java/Swift counterpart
- ⚠️ `status` — *missing-in-java*: Python StatusBitmask (IntFlag) bits: 1 Suspend Predicted, 2 Suspend Current, 16 Resume EGV Rise, 64 Resume Nadir Lock, 128 Unavailable-Time Small, 256 Unavailable-Suspend Override, 512 Unavailable-CGM Off, 1024 Unavailable-High EGV, 2048 Unavailable-Not Therapy, 4096 Unavailable-Bolus Active, 8192 Unavailable-No Current (bits 2,3,5 unused); no Java/Swift counterpart

**Inconsistencies:**

- Java PlgsPeriodicHistoryLog is a stub parser: parse() only validates length==26 and calls parseBase(raw) (header typeId@0, timestamp@2, seqNum@6); it decodes zero payload bytes. Python LidPlgsPeriodic decodes 8 payload fields: timestamp uint32@10, pgv uint16@14, fmr uint16@16, hoMinState uint8@18, ruleState uint8@19, pgvValid uint8@20, fmrStatus uint8@21, status uint32@22. All 8 fields are missing-in-java (and missing-in-swift).
- Swift port exactly mirrors the Java stub (init(cargo:) defers to HistoryLog base, buildCargo writes only typeId + pumpTimeSec + seqNum) — no [PORT-BUG]; Swift and Java are internally consistent with their own (payload-less) serializers.
- Java buildCargo(pumpTimeSec, sequenceNum) and the Swift equivalent zero-fill bytes 10-25 via fillCargo, so records round-tripped through Java/Swift lose all PLGS payload data that Python would decode (fmr, pgv, status flags, etc.).
- Python-only enum/value maps (FmrstatusEnum, PgvvalidEnum, RulestateBitmask, HominstateEnum, StatusBitmask) have no Java/Swift counterparts because the fields themselves are unparsed there.

### opCode 142 — LID_BASAL_IQ_SETTINGS_CHANGE

`BasalIqSettingsChangeHistoryLog` (java) ↔ `BasalIqSettingsChangeHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 151 — LID_CGM_DATA_SAMPLE

`CgmDataSampleHistoryLog` (java) ↔ `CgmDataSampleHistoryLog (Sources/TandemCore/Messages/HistoryLog/CgmDataSampleHistoryLog.swift)` (swift) — *no Python parser* — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| status | `status`<br>uint16 @10 | `status`<br>uint16 @10 | — | ✅ match | java Bytes.readShort(raw,10) = swift Bytes.readShort(cargo,10); both serialize status at offset 10 via firstTwoBytesLittleEndian |
| value | `value`<br>uint16 @19 | `value`<br>uint16 @19 | — | ✅ match | java Bytes.readShort(raw,19) = swift Bytes.readShort(cargo,19); parsers agree. However, BOTH buildCargo() implementations write value immediately after status (absolute offset 12), not at 19 — a shared parse/serialize mismatch inherited from the Java reference |

**Inconsistencies:**

- Internal parse/serialize mismatch shared by Java and Swift (not a porting divergence): parse()/init(cargo:) read value as uint16@19, but buildCargo() places value at offset 12 (2-byte typeId + 4-byte timestamp + 4-byte seqNum + 2-byte status + 2-byte value). Round-tripping a constructed log through the parser decodes value=0 (fillCargo zero padding at 19) instead of the given value, on both sides identically. Java class is annotated 'NOTE: not used in current firmware', so practical impact is low.

### opCode 156 — LID_CGM_TRANSMITTER_ID

`CgmTransmitterIdHistoryLog` (java) ↔ `CgmTransmitterIdHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 157 — LID_CGM_ANNU_SETTINGS

`CgmAnnuSettingsHistoryLog` (java) ↔ `CgmAnnuSettingsHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 160 — LID_CGM_CALIBRATION

`CgmCalibrationHistoryLog` (java) ↔ `CgmCalibrationHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| currentTime | `currentTime`<br>uint32 @10 | `currentTime`<br>uint32 @10 | — | ✅ match | java uint32@10 (Bytes.readUint32(raw,10)) = swift uint32@10 (Bytes.readUint32(cargo,10)); no py side |
| timestamp | `timestamp`<br>uint32 @14 | `timestamp`<br>uint32 @14 | — | ✅ match | java uint32@14 = swift uint32@14 |
| calTimestamp | `calTimestamp`<br>uint32 @18 | `calTimestamp`<br>uint32 @18 | — | ✅ match | java uint32@18 = swift uint32@18 |
| value | `value`<br>uint16 @22 | `value`<br>uint16 @22 | — | ✅ match | java uint16@22 (Bytes.readShort) = swift uint16@22 (Bytes.readShort, stored as Int) |
| currentDisplayValue | `currentDisplayValue`<br>uint16 @24 | `currentDisplayValue`<br>uint16 @24 | — | ✅ match | java uint16@24 = swift uint16@24; last payload field, fills record to 26 bytes |

_No inconsistencies found._

### opCode 162 — LID_CGM_STOP_SESSION_MSG1

`CgmStopSessionMsg1HistoryLog` (java) ↔ `CgmStopSessionMsg1HistoryLog (Sources/TandemCore/Messages/HistoryLog/CgmStopSessionMsg1HistoryLog.swift)` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 163 — LID_CGM_STOP_SESSION_MSG2

`CgmStopSessionMsg2HistoryLog` (java) ↔ `CgmStopSessionMsg2HistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 165 — LID_CGM_HGA_SETTINGS

`CgmHgaSettingsHistoryLog` (java) ↔ `Sources/TandemCore/Messages/HistoryLog/CgmHgaSettingsHistoryLog.swift (CgmHgaSettingsHistoryLog)` (swift) — *no Python parser* — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alertLevel | `alertLevel`<br>uint16 @10 | `alertLevel`<br>uint16 @10 | — | ✅ match | alertLevel: java Bytes.readShort@10 = swift Bytes.readShort@10; buildCargo emits firstTwoBytesLittleEndian at same position on both sides |
| repeatDuration | `repeatDuration`<br>uint16 @12 | `repeatDuration`<br>uint16 @12 | — | ✅ match | repeatDuration: java Bytes.readShort@12 = swift Bytes.readShort@12; serializers agree |
| isEnabled | `isEnabled`<br>uint8 @14 | `isEnabled`<br>uint8 @14 | — | ✅ match | isEnabled: java raw[14]!=0 = swift cargo[14]!=0 (bool from uint8); both buildCargo() write [isEnabled?1:0, 0] so byte 15 is a zero pad on both sides |
| modifiedField | `modifiedField`<br>uint16 @16 | `modifiedField`<br>uint16 @16 | — | ✅ match | modifiedField: java Bytes.readShort@16 = swift Bytes.readShort@16; java has nested ModifiedField enum (ENABLE=0, THRESHOLD=1, DURATION=2, INVALID=3, fromId defaults to INVALID); swift exposes raw Int only, no enum — decoded value identical |

**Enum / value-map findings:**

- ⚠️ `modifiedField` — *missing-in-swift*: Java defines nested enum ModifiedField {ENABLE=0, THRESHOLD=1, DURATION=2, INVALID=3} with fromId() falling back to INVALID; Swift port has no corresponding enum and exposes only the raw Int. Label-mapping gap only — raw decoded value matches.

**Inconsistencies:**

- [PORT-BUG] modifiedField: Swift port omits Java's nested ModifiedField enum (0=ENABLE, 1=THRESHOLD, 2=DURATION, 3=INVALID) and the getModifiedFieldEnum() accessor; raw uint16@16 decoding matches, so this is a label/typing gap only, not a value-changing bug.

### opCode 166 — LID_CGM_LGA_SETTINGS

`CgmLgaSettingsHistoryLog` (java) ↔ `Sources/TandemCore/Messages/HistoryLog/CgmLgaSettingsHistoryLog.swift (CgmLgaSettingsHistoryLog)` (swift) — *no Python parser* — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alertLevel | `alertLevel`<br>uint16 @10 | `alertLevel`<br>uint16 @10 | — | ✅ match | java Bytes.readShort(raw,10) = swift Bytes.readShort(cargo,10); serializers both write firstTwoBytesLittleEndian at same position |
| repeatDuration | `repeatDuration`<br>uint16 @12 | `repeatDuration`<br>uint16 @12 | — | ✅ match | java Bytes.readShort(raw,12) = swift Bytes.readShort(cargo,12) |
| isEnabled | `isEnabled`<br>uint8 @14 | `isEnabled`<br>uint8 @14 | — | ✅ match | java raw[14]!=0 = swift cargo[14]!=0; both serializers emit {enabled?1:0, 0} leaving byte 15 as padding |
| modifiedField | `modifiedField`<br>uint16 @16 | `modifiedField`<br>uint16 @16 | — | ✅ match | java Bytes.readShort(raw,16) = swift Bytes.readShort(cargo,16); Java exposes ModifiedField enum (0=ENABLE,1=THRESHOLD,2=DURATION,3=INVALID, fromId defaults to INVALID), Swift exposes only raw Int with no enum |

**Enum / value-map findings:**

- ⚠️ `modifiedField` — *missing-in-swift*: Java nested enum ModifiedField {ENABLE=0, THRESHOLD=1, DURATION=2, INVALID=3} with fromId fallback to INVALID; Swift port has no corresponding enum and exposes modifiedField only as a raw Int — decoded numeric values are unaffected

**Inconsistencies:**

- Swift port omits Java's ModifiedField enum (0=ENABLE, 1=THRESHOLD, 2=DURATION, 3=INVALID); modifiedField uint16@16 decodes identically on both sides but Swift lacks the semantic labels/getModifiedFieldEnum equivalent

### opCode 167 — LID_CGM_RRA_SETTINGS

`CgmRraSettingsHistoryLog` (java) ↔ `CgmRraSettingsHistoryLog (Sources/TandemCore/Messages/HistoryLog/CgmRraSettingsHistoryLog.swift)` (swift) — *no Python parser* — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alertLevel | `alertLevel`<br>uint16 @10 | `alertLevel`<br>uint16 @10 | — | ✅ match | java Bytes.readShort(raw,10) = swift Bytes.readShort(cargo,10); serializers both write firstTwoBytesLittleEndian at 10-11 |
| repeatDuration | `repeatDuration`<br>uint16 @12 | `repeatDuration`<br>uint16 @12 | — | ✅ match | java uint16@12 = swift uint16@12 |
| isEnabled | `isEnabled`<br>uint8 @14 | `isEnabled`<br>uint8 @14 | — | ✅ match | java raw[14]!=0 = swift cargo[14]!=0; both serializers write {enabled?1:0, 0} leaving padding byte at offset 15 |
| modifiedField | `modifiedField`<br>uint16 @16 | `modifiedField`<br>uint16 @16 | — | ✅ match | java uint16@16 = swift uint16@16; Java exposes ModifiedField enum (0=ENABLE,1=THRESHOLD,2=DURATION,3=INVALID with fromId fallback to INVALID), Swift exposes raw Int only — enum omitted in port but decoded value identical |

**Enum / value-map findings:**

- ⚠️ `modifiedField` — *missing-in-swift*: Java nested enum ModifiedField {ENABLE=0, THRESHOLD=1, DURATION=2, INVALID=3} with getModifiedFieldEnum()/fromId (unknown ids map to INVALID); Swift has no corresponding enum, only raw Int modifiedField. Values decoded are unchanged.

**Inconsistencies:**

- [PORT-BUG] modifiedField: Swift port omits Java's nested ModifiedField enum (ENABLE=0, THRESHOLD=1, DURATION=2, INVALID=3) and the getModifiedFieldEnum() accessor; Swift exposes only the raw uint16@16 as Int. Label/semantics gap only — decoded values are identical (java uint16@16 = swift uint16@16).

### opCode 168 — LID_CGM_FRA_SETTINGS

`CgmFraSettingsHistoryLog` (java) ↔ `CgmFraSettingsHistoryLog` (swift) — *no Python parser* — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alertLevel | `alertLevel`<br>uint16 @10 | `alertLevel`<br>uint16 @10 | — | ✅ match | java Bytes.readShort(raw,10) = swift Bytes.readShort(cargo,10); both serialize via firstTwoBytesLittleEndian |
| repeatDuration | `repeatDuration`<br>uint16 @12 | `repeatDuration`<br>uint16 @12 | — | ✅ match | java Bytes.readShort(raw,12) = swift Bytes.readShort(cargo,12); both serialize via firstTwoBytesLittleEndian |
| isEnabled | `isEnabled`<br>uint8 @14 | `isEnabled`<br>uint8 @14 | — | ✅ match | java raw[14]!=0 = swift cargo[14]!=0; both serializers write {enabled?1:0, 0} so byte 15 is padding in both |
| modifiedField | `modifiedField`<br>uint16 @16 | `modifiedField`<br>uint16 @16 | — | ✅ match | java Bytes.readShort(raw,16) = swift Bytes.readShort(cargo,16); both serialize via firstTwoBytesLittleEndian |

**Enum / value-map findings:**

- ⚠️ `modifiedField` — *missing-in-swift*: Java has nested ModifiedField enum {ENABLE=0, THRESHOLD=1, DURATION=2, INVALID=3} with fromId() defaulting to INVALID; Swift port exposes modifiedField only as raw Int with no equivalent enum. Decoded numeric value is unaffected.

**Inconsistencies:**

- Swift port omits the Java ModifiedField enum (0=ENABLE, 1=THRESHOLD, 2=DURATION, 3=INVALID); modifiedField is exposed only as a raw Int — label/value-map gap only, decoded bytes identical.

### opCode 169 — LID_CGM_OOR_SETTINGS

`CgmOorSettingsHistoryLog` (java) ↔ `CgmOorSettingsHistoryLog` (swift) — *no Python parser* — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alertLevel | `alertLevel`<br>uint16 @10 | `alertLevel`<br>uint16 @10 | — | ✅ match | java Bytes.readShort(raw,10) = swift Bytes.readShort(cargo,10); both serializers write firstTwoBytesLittleEndian at same position |
| repeatDuration | `repeatDuration`<br>uint16 @12 | `repeatDuration`<br>uint16 @12 | — | ✅ match | java Bytes.readShort(raw,12) = swift Bytes.readShort(cargo,12) |
| isEnabled | `isEnabled`<br>uint8 @14 | `isEnabled`<br>uint8 @14 | — | ✅ match | java raw[14]!=0 = swift cargo[14]!=0; both serializers write a 2-byte {flag,0} pair so byte 15 is padding on both sides |
| modifiedField | `modifiedField`<br>uint16 @16 | `modifiedField`<br>uint16 @16 | — | ✅ match | java Bytes.readShort(raw,16) = swift Bytes.readShort(cargo,16); values 0=ENABLE,1=THRESHOLD,2=DURATION,3=INVALID per Java enum/javadoc |

**Enum / value-map findings:**

- ⚠️ `modifiedField` — *missing-in-swift*: Java defines nested ModifiedField enum (ENABLE=0, THRESHOLD=1, DURATION=2, INVALID=3, fromId defaults to INVALID) with getModifiedFieldEnum(); Swift exposes only the raw Int with no enum. Decoded integer values are identical, so this is cosmetic.

**Inconsistencies:**

- [PORT-BUG] Swift port omits Java's ModifiedField enum (0=ENABLE,1=THRESHOLD,2=DURATION,3=INVALID) and the getModifiedFieldEnum() accessor; modifiedField is exposed only as a raw Int. Decoded values are unaffected — enum-label gap only.

### opCode 171 — LID_CGM_ALERT_ACTIVATED

`CgmAlertActivatedHistoryLog` (java) ↔ `CgmAlertActivatedHistoryLog (/home/user/TandemKit/Sources/TandemCore/Messages/HistoryLog/CgmAlertActivatedHistoryLog.swift)` (swift) ↔ `LidCgmAlertActivated` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alertId | `alertId`<br>uint32 @10 | `alertId`<br>uint32 @10 | `dalertIdRaw`<br>uint32 @10 | ✅ match | alertId: java uint32@10 (Bytes.readUint32(raw,10)) = swift uint32@10 (Bytes.readUint32(cargo,10)) = py uint32@10 (unpack_from UINT32 @10). Java buildCargo also writes uint32 at 10 (opcode 2 + time 4 + seq 4), internally consistent. Names differ only (dalertIdRaw vs alertId). |
| faultLocatorData | — | — | `faultLocatorData`<br>uint32 @14 | ❌ missing-in-java | py uint32@14; absent from BOTH Java parse() and Swift init(cargo:) — Java buildCargo zero-fills bytes 14-25 via fillCargo. Python-only payload field derived from Tandem cloud export property 'faultlocatordata'. |
| param1 | — | — | `param1`<br>uint32 @18 | ❌ missing-in-java | py uint32@18; absent from both Java and Swift parsers (bytes 18-21 unparsed on those sides). |
| param2 | — | — | `param2`<br>float32 @22 | ❌ missing-in-java | py float32@22; absent from both Java and Swift parsers (bytes 22-25 unparsed on those sides). |

**Enum / value-map findings:**

- ✅ `alertId (CGMAlert / DalertidEnum) — shared values` — *match*: Values 1,2,3,8,11,12,13,14,20,22,26,27,39,40 agree semantically: 1=Fixed Low, 2=High, 3=Low, 8=Rapid Fall, 11=Sensor Failed, 12=Sensor Expiring, 13=Sensor Expired, 14=Out Of Range, 20=Transmitter, 22=Sensor Expiring 2, 26=Temperature, 27=Failed Connection, 39=Transmitter Expired, 40=Pump Bluetooth Error. Value 25 is same concept with different label: Java/Swift SENSOR_REUSE vs Python 'CGM Replace Sensor'. Java enum compared via its Swift port (CGMAlertStatus.swift CGMAlert), since the Java history log delegates to CGMAlertStatusResponse.CGMAlert.
- ⚠️ `alertId values 4,5,6,7,9,10,16,17,18,19` — *missing-in-python*: Java/Swift name these (4=CALIBRATION_REQUEST, 5=RISE, 6=RAPID_RISE, 7=FALL, 9=LOW_CALIBRATION_ERROR, 10=HIGH_CALIBRATION_ERROR, 16/17=FIRST/SECOND_START_CALIBRATION, 18=CALIBRATION_REQUIRED, 19=LOW_TRANSMITTER); Python DalertidMap/DalertidEnum omit them entirely — DalertidEnum(raw) returns None for these raw values.
- ⚠️ `alertId values 45,46,48` — *values-differ*: Python names them (45='CGM Transmitter Expiring Soon', 46='CGM Transmitter Expiring 2', 48='CGM Unavailable') while Java/Swift only have placeholder DEFAULT_CGM_ALERT_45/46/48 cases — Python carries richer labels for these ids.
- ⚠️ `alertId values 0,15,21,23,24,28-38,41-44,47,49-63` — *missing-in-python*: Java/Swift define placeholder DEFAULT_CGM_ALERT_* cases for these ids (so decoding never fails); Python DalertidEnum has no entry and logs an error / returns None for them.

**Inconsistencies:**

- [PY-DIVERGENCE] Python parses three extra payload fields absent from the Java reference and Swift port: faultLocatorData uint32@14, param1 uint32@18, param2 float32@22. Java parse() reads only alertId uint32@10 and buildCargo() zero-fills bytes 14-25 via HistoryLog.fillCargo; Swift likewise reads only uint32@10. Bytes 14-25 of the record are decoded by Python only.
- [PY-DIVERGENCE] Enum map gaps: Python DalertidEnum lacks ids 4,5,6,7,9,10,16,17,18,19 that Java/Swift CGMAlert name (calibration/rise/fall/low-transmitter alerts) and returns None for unknown ids, while Python uniquely labels 45/46/48 (Transmitter Expiring Soon / Expiring 2 / CGM Unavailable) which Java/Swift only carry as DEFAULT_CGM_ALERT_45/46/48 placeholders. Value 25 label differs: SENSOR_REUSE (Java/Swift) vs 'CGM Replace Sensor' (Python) — same concept.
- [PORT-BUG] Completeness gap, not a decode error: Swift CgmAlertActivatedHistoryLog omits Java's typed alert accessor (Java exposes getAlert() = CGMAlertStatusResponse.CGMAlert.fromId(alertId); Swift exposes only raw alertId even though TandemCore has the CGMAlert enum in CGMAlertStatus.swift) and omits Java's buildCargo(pumpTimeSec, sequenceNum, alertId) serializer/convenience constructors. Parsing itself is byte-identical (uint32@10).

### opCode 172 — LID_CGM_ALERT_CLEARED

`CgmAlertClearedHistoryLog` (java) ↔ `CgmAlertClearedHistoryLog` (swift) ↔ `LidCgmAlertCleared` (py) — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alertId | `alertId`<br>uint32 @10 | `alertId`<br>uint32 @10 | `dalertIdRaw`<br>uint32 @10 | ✅ match | alertId: java uint32@10 (Bytes.readUint32(raw,10)) = swift uint32@10 (Bytes.readUint32(cargo,10)) = py uint32@10 (unpack_from(UINT32, raw, 10)). Java buildCargo writes Bytes.toUint32(alertId) after 2-byte header + pumpTimeSec + sequenceNum, landing at offset 10 — internally consistent. |
| alertEnum (derived from alertId) | `alert (CGMAlertStatusResponse.CGMAlert)`<br>derived enum | — | `dalertId (DalertidEnum property)`<br>derived enum | ❌ missing-in-swift | Java derives alert = CGMAlertStatusResponse.CGMAlert.fromId(alertId) in parse(); Python exposes dalertId via DalertidEnum(dalertIdRaw). Swift stores only raw UInt32 alertId with no CGMAlert enum mapping even though Sources/TandemCore/Messages/CurrentStatus/CGMAlertStatus.swift defines a matching CGMAlert enum. Derived value only — raw bytes decode identically. |

**Enum / value-map findings:**

- ⚠️ `alertId enum (CGMAlert vs DalertidEnum/DalertidMap)` — *partial*: Python DalertidMap/DalertidEnum has 18 named values (1,2,3,8,11,12,13,14,20,22,25,26,27,39,40,45,46,48); Java/Swift CGMAlert enumerates ids 0-63. Overlapping ids agree semantically (e.g. 1=Fixed Low, 2=High, 3=Low, 8=Rapid Fall, 11=Sensor Fail, 13=Sensor Expired, 14=Out of Range, 20=Transmitter, 26=Temperature, 27=Failed Connection, 39=Transmitter Expired, 40=Pump Bluetooth Error). Divergences: py names 45='CGM Transmitter Expiring Soon', 46='CGM Transmitter Expiring 2', 48='CGM Unavailable' where Swift port has only DEFAULT_CGM_ALERT_45/46/48 placeholders; id 25 is 'CGM Replace Sensor' in py vs SENSOR_REUSE in Swift (same meaning, different label).
- ⚠️ `alert enum on Swift history-log class` — *missing-in-swift*: Swift CgmAlertClearedHistoryLog exposes no typed alert accessor; Java parse() populates CGMAlert alert and getAlert().

**Inconsistencies:**

- [PORT-BUG] Swift CgmAlertClearedHistoryLog omits the derived `alert` enum field: Java parse() sets alert = CGMAlertStatusResponse.CGMAlert.fromId((int) alertId) and exposes getAlert(); Swift only exposes raw alertId (uint32@10) despite CGMAlertStatus.swift defining an equivalent CGMAlert enum. Raw decode is unaffected.
- [PORT-BUG] Swift CgmAlertClearedHistoryLog has no buildCargo()/serializer counterpart to Java's static buildCargo(pumpTimeSec, sequenceNum, alertId); the Swift class is parse-only, so it cannot round-trip a record like the Java reference.
- [PY-DIVERGENCE] Python DalertidMap names alert ids 45 ('CGM Transmitter Expiring Soon'), 46 ('CGM Transmitter Expiring 2'), and 48 ('CGM Unavailable') that the Java/Swift CGMAlert enum leaves as DEFAULT_CGM_ALERT_45/46/48 placeholders — enum-label gap only, byte layout identical (uint32@10 on all sides).

### opCode 173 — LID_CGM_ALERT_ACK

`CgmAlertAckHistoryLog` (java) ↔ `CgmAlertAckHistoryLog` (swift) — *no Python parser* — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alertId | `alertId`<br>uint32 @10 | `alertId`<br>uint32 @10 | — | ✅ match | alertId: java uint32@10 (Bytes.readUint32(raw,10)) = swift uint32@10 (Bytes.readUint32(cargo,10)); both buildCargo() serializers write Bytes.toUint32(alertId) after the 10-byte header, internally consistent on both sides |

**Enum / value-map findings:**

- ⚠️ `alertId -> CGMAlert enum` — *missing-in-swift*: Java derives alert = CGMAlertStatusResponse.CGMAlert.fromId((int) alertId) as a convenience field; Swift exposes only the raw UInt32 alertId with no CGMAlert enum mapping. Raw decoded value is identical, so this is label-level only.

**Inconsistencies:**

- Swift port omits the derived CGMAlertStatusResponse.CGMAlert enum accessor that Java provides via CGMAlert.fromId(alertId); raw alertId uint32@10 decodes identically on both sides, so this is an enum-label convenience gap, not a layout bug

### opCode 187 — LID_CGM_UNEXPECTED_GE_ALERT

`CgmUnexpectedGeAlertHistoryLog` (java) ↔ `CgmUnexpectedGeAlertHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 191 — LID_VERSION_INFO

`VersionInfoHistoryLog` (java) ↔ `VersionInfoHistoryLog` (swift) ↔ `LidVersionInfo` (py) — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| version | `version`<br>uint32 @10 | `version`<br>uint32 @10 | `version`<br>uint32 @10 | ✅ match | java uint32@10 = swift uint32@10 = py uint32@10 |
| configABits | `configABits`<br>uint32 @14 | `configABits`<br>uint32 @14 | `configABits`<br>uint32 @14 | ✅ match | java uint32@14 = swift uint32@14 = py uint32@14 |
| configBBits | `configBBits`<br>uint32 @18 | `configBBits`<br>uint32 @18 | `configBBits`<br>uint32 @18 | ✅ match | java uint32@18 = swift uint32@18 = py uint32@18 |
| armCrc | `armCrc`<br>uint16 @24 | `armCrc`<br>uint16 @24 | `armCrc`<br>uint16 @24 | ✅ match | java uint16@24 = swift uint16@24 = py uint16@24; bytes 22-23 are padding (Java buildCargo writes explicit zeros there, consistent with its parser skipping 22-23) |

**Inconsistencies:**

- Swift VersionInfoHistoryLog has no buildCargo() serializer (Java has one writing version@10, configA@14, configB@18, zeros@22-23, armCrc@24); parse paths are identical on all three sides, so this is an informational port gap, not a decode divergence.

### opCode 198 — LID_HYPO_MINIMIZER_SUSPEND

`HypoMinimizerSuspendHistoryLog` (java) ↔ `HypoMinimizerSuspendHistoryLog (Sources/TandemCore/Messages/HistoryLog/HypoMinimizerSuspendHistoryLog.swift)` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 199 — LID_HYPO_MINIMIZER_RESUME

`HypoMinimizerResumeHistoryLog` (java) ↔ `HypoMinimizerResumeHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| reason | `reason`<br>uint32 @10 | `reason`<br>uint32 @10 | — | ✅ match | java uint32@10 (Bytes.readUint32(raw, 10)) = swift uint32@10 (Bytes.readUint32(cargo, 10)); buildCargo on both sides serializes reason as uint32 immediately after the 10-byte header, agreeing with their parsers. No enum/value map on either side. No Python parser exists. |

_No inconsistencies found._

### opCode 203 — LID_UPDATE_STATUS

`UpdateStatusHistoryLog` (java) ↔ `UpdateStatusHistoryLog (Sources/TandemCore/Messages/HistoryLog/UpdateStatusHistoryLog.swift)` (swift) ↔ `LidUpdateStatus` (py) — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| metadataAndVersionStatus | `metadataAndVersionStatus`<br>uint16 @10 | `metadataAndVersionStatus`<br>uint16 @10 | `metadataAndVersionStatus`<br>uint16 @10 | ✅ match | java uint16@10 = swift uint16@10 = py uint16@10 |
| swUpdateStatus | `swUpdateStatus`<br>uint16 @12 | `swUpdateStatus`<br>uint16 @12 | `swUpdateStatus`<br>uint16 @12 | ✅ match | java uint16@12 = swift uint16@12 = py uint16@12 |
| fileDlAndSideloadStatus | `fileDlAndSideloadStatus`<br>uint16 @14 | `fileDlAndSideloadStatus`<br>uint16 @14 | `fileDlAndSideloadStatus`<br>uint16 @14 | ✅ match | java uint16@14 = swift uint16@14 = py uint16@14 |
| fullDlAndCrcStatus | `fullDlAndCrcStatus`<br>uint16 @16 | `fullDlAndCrcStatus`<br>uint16 @16 | `fullDlAndCrcStatus`<br>uint16 @16 | ✅ match | java uint16@16 = swift uint16@16 = py uint16@16 |
| updateSuccessful | `updateSuccessful`<br>uint8 @19 | `updateSuccessful`<br>uint8 @19 | `updateSuccessfulRaw (exposed via updateSuccessful enum property)`<br>uint8 @19 | ✅ match | java raw[19] uint8 = swift cargo[19] uint8 = py '>B'@19; byte 18 is padding on all sides (Java buildCargo writes new byte[]{0, updateSuccessful} placing 0 at offset 18) |
| externalFlashStatus | `externalFlashStatus`<br>uint16 @20 | `externalFlashStatus`<br>uint16 @20 | `externalFlashStatus`<br>uint16 @20 | ✅ match | java uint16@20 = swift uint16@20 = py uint16@20 |
| swPartNum | `swPartNum`<br>uint32 @22 | `swPartNum`<br>uint32 @22 | `swPartNum`<br>uint32 @22 | ✅ match | java Bytes.readUint32@22 = swift Bytes.readUint32@22 = py '>I'@22 |

**Enum / value-map findings:**

- ⚠️ `updateSuccessful` — *partial*: Python only: UpdatesuccessfulMap/UpdatesuccessfulEnum {0: Update Not Successful, 1: Update Successful}. Java and Swift expose a plain int with no enum or javadoc value comments. Value semantics do not conflict; Python is simply richer.

**Inconsistencies:**

- Swift UpdateStatusHistoryLog has no buildCargo() serializer (init(cargo:) only), while Java has a full buildCargo(); decode-only port, round-trip serialization cannot be verified on the Swift side. Decoded values are unaffected.
- Java buildCargo() is internally consistent with parse(): fields written at 10/12/14/16, padding 0 at 18, updateSuccessful at 19, externalFlashStatus at 20, swPartNum at 22 (26 bytes total).
- updateSuccessful enum labels (0=Update Not Successful, 1=Update Successful) exist only in Python; Java/Swift treat it as an unannotated int (label gap only, no value conflict).

### opCode 210 — LID_CGM_CAL_GX

`CgmCalibrationGxHistoryLog` (java) ↔ `CgmCalibrationGxHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| value | `value`<br>uint16 @10 | `value`<br>uint16 @10 | — | ✅ match | value: java Bytes.readShort(raw,10) uint16@10 = swift Bytes.readShort(cargo,10) uint16@10; both serializers write it via Bytes.firstTwoBytesLittleEndian at the same position — consistent |

_No inconsistencies found._

### opCode 211 — LID_CGM_DATA_GX

`CgmDataGxHistoryLog` (java) ↔ `CgmDataGxHistoryLog` (swift) — *no Python parser* — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| status | `status`<br>uint16 @10 | `status`<br>uint16 @10 | — | ✅ match | status: java uint16@10 (Bytes.readShort) = swift uint16@10 — match |
| type | `type`<br>uint8 @12 | `type`<br>uint8 @12 | — | ✅ match | type: java uint8@12 (raw[12]) = swift uint8@12 (cargo[12]) — match |
| rate | `rate`<br>uint8 @13 | `rate`<br>uint8 @13 | — | ✅ match | rate: java uint8@13 = swift uint8@13 — match; byte 14 is skipped by both parsers (gap byte) |
| rssi | `rssi`<br>uint8 @15 | `rssi`<br>uint8 @15 | — | ✅ match | rssi: java uint8@15 (raw[15]) = swift uint8@15 — match in parse; but both buildCargo() serializers emit rssi at 14 (no gap byte), see inconsistencies |
| value | `value`<br>uint16 @16 | `value`<br>uint16 @16 | — | ✅ match | value: java uint16@16 = swift uint16@16 — match in parse; both serializers emit it at 15-16 due to the shared missing-gap-byte serializer bug |
| timestamp | `timestamp`<br>uint32 @18 | `timestamp`<br>uint32 @18 | — | ✅ match | timestamp: java uint32@18 = swift uint32@18 — match in parse; serializers emit at 17 (shifted -1) |
| transmitterTimestamp | `transmitterTimestamp`<br>uint32 @22 | `transmitterTimestamp`<br>uint32 @22 | — | ✅ match | transmitterTimestamp: java uint32@22 = swift uint32@22 — match in parse; serializers emit at 21 (shifted -1) |

**Inconsistencies:**

- Shared internal parser/serializer mismatch inherited from reference (NOT a port bug — Swift replicates Java byte-for-byte): parse() reads rssi@15, value@16, timestamp@18, transmitterTimestamp@22 with an unused gap byte at offset 14, but buildCargo() concatenates status(2)+type(1)+rate(1)+rssi(1)+value(2)+timestamp(4)+transmitterTimestamp(4) contiguously with NO gap byte, placing rssi@14, value@15, timestamp@17, transmitterTimestamp@21 and relying on fillCargo end-padding to reach 26 bytes. A record built via buildCargo and re-parsed decodes rssi from the low byte of value, and all later fields shifted by one. Identical defect in Java (CgmDataGxHistoryLog.java parse lines 51-57 vs buildCargo lines 61-73) and Swift (CgmDataGxHistoryLog.swift init(cargo:) lines 16-22 vs buildCargo lines 69-82).

### opCode 212 — LID_CGM_START_SESSION_GX

`CgmStartSessionHistoryLog` (java) ↔ `CgmStartSessionHistoryLog (Sources/TandemCore/Messages/HistoryLog/CgmStartSessionHistoryLog.swift)` (swift) ↔ `LidCgmStartSessionGx` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| currentTransmitterTime | — | — | `currentTransmitterTime`<br>uint32 @10 | ❌ missing-in-java | py uint32@10 (seconds); Java parse() decodes no payload fields (only parseBase header) and Swift port likewise has none — absent in both Java and Swift |
| sessionStartTime | — | — | `sessionStartTime`<br>uint32 @14 | ❌ missing-in-java | py uint32@14 (seconds); absent in Java reference and in Swift port (both parse only the 10-byte header) |
| sessionDuration | — | — | `sessionDuration`<br>uint8 @25 | ❌ missing-in-java | py uint8@25 (days) — last byte of the 26-byte record; absent in Java reference and in Swift port |

**Inconsistencies:**

- [PY-DIVERGENCE] Java/Swift treat opCode 212 as a payload-less stub (parse() only validates length==26 and calls parseBase; buildCargo emits typeId+timestamp+seqNum zero-filled), while Python decodes three payload fields: currentTransmitterTime uint32@10, sessionStartTime uint32@14, sessionDuration uint8@25. Java (and the Swift port) silently drop this CGM session-start data.
- Java buildCargo(long,long) takes no payload arguments, so any round-tripped record loses bytes 10-25; Swift buildCargo is identical. Both are internally self-consistent (serializer matches their own empty parser) — the gap is only vs. Python.

### opCode 213 — LID_CGM_JOIN_SESSION_GX

`CgmJoinSessionHistoryLog` (java) ↔ `CgmJoinSessionHistoryLog` (swift) ↔ `LidCgmJoinSessionGx` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| currentTransmitterTime | — | — | `currentTransmitterTime`<br>uint32 @10 | ❌ missing-in-java | py uint32@10 (seconds); Java parse() only calls parseBase(raw) and decodes NO payload fields, Swift init(cargo:) likewise decodes nothing — field absent in both Java and Swift. Not a port bug (Swift faithfully mirrors Java's empty parser). |
| sessionStartTime | — | — | `sessionStartTime`<br>uint32 @14 | ❌ missing-in-java | py uint32@14 (seconds); absent in both Java (parseBase only) and Swift (port of Java). Not a port bug. |
| sessionJoinReason | — | — | `sessionJoinReasonRaw`<br>uint8 @24 | ❌ missing-in-java | py uint8@24 with SessionjoinreasonEnum (DEXBLES_REASON_* values 0-13, 2 and 7 reserved); absent in both Java and Swift. Not a port bug. |
| sessionDuration | — | — | `sessionDuration`<br>uint8 @25 | ❌ missing-in-java | py uint8@25 (days); absent in both Java and Swift. Not a port bug. Note py leaves bytes 18-23 unparsed and reads duration@25 after reason@24. |

**Enum / value-map findings:**

- ⚠️ `sessionJoinReason` — *missing-in-java*: Python defines SessionjoinreasonMap/SessionjoinreasonEnum (0=DEXBLES_REASON_USER, 1=UNKNOWN, 3=TX_END_OF_LIFE, 4=TRANSMITTER_ERROR, 5=SESSION_STOP_SUCCESS, 6=TRANSMITTER_NOT_IN_SESSION, 8=NEW_SESSION_STARTED_SUCCESS, 9=SESSION_STARTED_IN_PROGRESS, 10=TRANSMITTER_IN_SESSION, 11=BLESTACK_INVALID, 12=NEW_AUTOCAL_SESSION_STARTED_SUCCESS, 13=NO_AUTOCAL_SESSION_IN_PROGRESS; 2 and 7 Reserved). Java and Swift have no enum because they don't parse the field at all.

**Inconsistencies:**

- [PY-DIVERGENCE] Payload fields parsed only by Python: Java CgmJoinSessionHistoryLog.parse() calls parseBase(raw) only and its buildCargo(pumpTimeSec, sequenceNum) writes only the 10-byte header (typeId 213 + uint32 timestamp + uint32 seqNum) zero-filled to 26 bytes; Python LidCgmJoinSessionGx decodes currentTransmitterTime uint32@10, sessionStartTime uint32@14, sessionJoinReason uint8@24, sessionDuration uint8@25. Java (and its Swift port) silently drop all four payload fields.
- Swift port is faithful to Java: both parse no payload fields and both buildCargo() serializers emit only typeId+timestamp+seqNum padded to 26 bytes — no [PORT-BUG] findings for opcode 213.
- Internal consistency: Java and Swift buildCargo() agree with their own (empty) parsers; Python has no serializer to check. Python leaves bytes 18-23 of the record unparsed.

### opCode 214 — LID_CGM_STOP_SESSION_GX

`CgmStopSessionHistoryLog` (java) ↔ `CgmStopSessionHistoryLog` (swift) ↔ `LidCgmStopSessionGx` (py) — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| currentTransmitterTime | — | — | `currentTransmitterTime`<br>uint32 @10 | ❌ missing-in-java | py uint32@10 only; Java reference parses no payload fields (parse() calls parseBase only) and Swift port likewise has no payload parsing — absent in both Java and Swift |
| sessionStartTime | — | — | `sessionStartTime`<br>uint32 @14 | ❌ missing-in-java | py uint32@14 only; absent in Java reference and Swift port |
| sessionStopTime | — | — | `sessionStopTime`<br>uint32 @18 | ❌ missing-in-java | py uint32@18 only; absent in Java reference and Swift port |
| sessionStopReason | — | — | `sessionStopReasonRaw`<br>uint8 @24 | ❌ missing-in-java | py uint8@24 with SessionstopreasonEnum mapping; absent in Java reference and Swift port |
| sessionDuration | — | — | `sessionDuration`<br>uint8 @25 | ❌ missing-in-java | py uint8@25 (days); absent in Java reference and Swift port |

**Enum / value-map findings:**

- ⚠️ `sessionStopReason` — *missing-in-java*: Python defines SessionstopreasonMap/SessionstopreasonEnum with values 0=DEXBLES_REASON_USER, 1=UNKNOWN, 2=Reserved, 3=TX_END_OF_LIFE, 4=TRANSMITTER_ERROR, 5=SESSION_STOP_SUCCESS, 6=TRANSMITTER_NOT_IN_SESSION, 7=Reserved, 8=NEW_SESSION_STARTED_SUCCESS, 9=SESSION_STARTED_IN_PROGRESS, 10=TRANSMITTER_IN_SESSION, 11=BLESTACK_INVALID, 12=NEW_AUTOCAL_SESSION_STARTED_SUCCESS, 13=NO_AUTOCAL_SESSION_IN_PROGRESS. Java and Swift have no corresponding field or enum at all.

**Inconsistencies:**

- [PY-DIVERGENCE] Python LidCgmStopSessionGx decodes 5 payload fields (currentTransmitterTime uint32@10, sessionStartTime uint32@14, sessionStopTime uint32@18, sessionStopReason uint8@24, sessionDuration uint8@25) that the Java reference CgmStopSessionHistoryLog does not parse at all — Java parse() only calls parseBase(raw) and its buildCargo() takes only pumpTimeSec/sequenceNum, zero-filling bytes 10-25. Swift matches Java (base-only), so this is a Java/Swift coverage gap relative to Python, not a layout conflict.

### opCode 215 — LID_CGM_INACTIVE_GX

`CgmInactiveGxHistoryLog` (java) ↔ `CgmInactiveGxHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| pumpTimeSec | `pumpTimeSec`<br>uint32 @2 | `pumpTimeSec`<br>uint32 @2 | — | ✅ match | base-header field parsed by HistoryLog.parseBase in Java and HistoryLog base init in Swift; both uint32@2 |
| sequenceNum | `sequenceNum`<br>uint32 @6 | `sequenceNum`<br>uint32 @6 | — | ✅ match | base-header field; both uint32@6 |

_No inconsistencies found._

### opCode 216 — LID_CGM_TRANSMITTER_ID_GX

`CgmTransmitterIdGxHistoryLog` (java) ↔ `CgmTransmitterIdGxHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| pumpTimeSec | `pumpTimeSec`<br>uint32 @2 | `pumpTimeSec`<br>uint32 @2 | — | ✅ match | Base header field parsed by parseBase/HistoryLog base class in both; buildCargo writes Bytes.toUint32(pumpTimeSec) at offset 2 in both Java and Swift. |
| sequenceNum | `sequenceNum`<br>uint32 @6 | `sequenceNum`<br>uint32 @6 | — | ✅ match | Base header field in both; buildCargo writes Bytes.toUint32(sequenceNum) at offset 6 in both Java and Swift. |

_No inconsistencies found._

### opCode 217 — LID_CGM_START_SESSION_REQ_GX

`CgmStartSessionReqGxHistoryLog` (java) ↔ `CgmStartSessionReqGxHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| pumpTimeSec | `pumpTimeSec`<br>uint32 @2 | `pumpTimeSec`<br>uint32 @2 | — | ✅ match | Base header field parsed via parseBase()/HistoryLog superclass on both sides; buildCargo writes Bytes.toUint32(pumpTimeSec) at offset 2 in both Java and Swift. |
| sequenceNum | `sequenceNum`<br>uint32 @6 | `sequenceNum`<br>uint32 @6 | — | ✅ match | Base header field; buildCargo writes Bytes.toUint32(sequenceNum) at offset 6 in both Java and Swift. |

_No inconsistencies found._

### opCode 218 — LID_CGM_STOP_SESSION_REQ_GX

`CgmStopSessionReqGxHistoryLog` (java) ↔ `CgmStopSessionReqGxHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| pumpTimeSec | `pumpTimeSec`<br>uint32 @2 | `pumpTimeSec`<br>uint32 @2 | — | ✅ match | Base header field parsed by parseBase/HistoryLog superclass on both sides; buildCargo writes Bytes.toUint32(pumpTimeSec) at offset 2 in both Java and Swift. |
| sequenceNum | `sequenceNum`<br>uint32 @6 | `sequenceNum`<br>uint32 @6 | — | ✅ match | Base header field; buildCargo writes Bytes.toUint32(sequenceNum) at offset 6 in both Java and Swift. |

_No inconsistencies found._

### opCode 220 — LID_CGM_TRANSMITTER_VERSION_GX

`CgmTransmitterVersionGxHistoryLog` (java) ↔ `CgmTransmitterVersionGxHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 229 — LID_AA_USER_MODE_CHANGE

`ControlIQUserModeChangeHistoryLog` (java) ↔ `ControlIQUserModeChangeHistoryLog` (swift) ↔ `LidAaUserModeChange` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| currentUserMode | `currentUserMode`<br>uint8 @10 | `currentUserMode`<br>uint8 @10 | `currentUserModeRaw`<br>uint8 @13 | ❌ py-diverges-from-java | java uint8@10 (raw[10]) = swift uint8@10 (raw[10]); py uint8@13 — py diverges by 3 bytes. buildCargo on Java/Swift also writes it at offset 10. |
| previousUserMode | `previousUserMode`<br>uint8 @11 | `previousUserMode`<br>uint8 @11 | `previousUserModeRaw`<br>uint8 @12 | ❌ py-diverges-from-java | java uint8@11 (raw[11]) = swift uint8@11 (raw[11]); py uint8@12 — py diverges by 1 byte. Note py offset 12 collides with nothing in Java, but Java's offset 11 is where py reads requestedAction. |
| requestedAction | — | — | `requestedActionRaw`<br>uint8 @11 | ❌ missing-in-java | py-only uint8@11; absent from both Java parse() and Swift init(cargo:). Py offset 11 overlaps Java/Swift previousUserMode@11, so the same byte is interpreted differently across implementations. |
| exerciseChoice | — | — | `exerciseChoiceRaw`<br>uint8 @20 | ❌ missing-in-java | py-only uint8@20 (enum 0=Continuous, 1=Timed); absent in Java and Swift. |
| exerciseTime | — | — | `exerciseTime`<br>uint16 @18 | ❌ missing-in-java | py-only uint16@18 (minutes); absent in Java and Swift. |
| sleepStartedByGui | — | — | `sleepStartedByGuiRaw`<br>uint8 @17 | ❌ missing-in-java | py-only uint8@17 boolean; absent in Java and Swift. |
| activeSleepSchedule | — | — | `activeSleepScheduleRaw`<br>uint8 @16 | ❌ missing-in-java | py-only uint8@16 bitmask (bits 0-3 = Sleep Schedule 1-4 active); absent in Java and Swift. |
| exerciseStoppedByTimer | — | — | `exerciseStoppedByTimerRaw`<br>uint8 @21 | ❌ missing-in-java | py-only uint8@21 boolean; absent in Java and Swift. |
| eatingSoonStoppedByTimer | — | — | `eatingSoonStoppedByTimerRaw`<br>uint8 @25 | ❌ missing-in-java | py-only uint8@25 boolean (last byte of the 26-byte record); absent in Java and Swift. |

**Enum / value-map findings:**

- ⚠️ `currentUserMode/previousUserMode value map` — *missing-in-java*: Python defines CurrentusermodeEnum/PrevioususermodeEnum {0=Normal, 1=Sleeping, 2=Exercising, 3=EatingSoon}; Java stores plain int with no enum or javadoc values; Swift stores plain Int with no enum. Also missing in Swift.
- ⚠️ `requestedAction value map` — *missing-in-java*: Python-only RequestedactionEnum {0=NoUserRequest, 1=StartSleep, 2=StopSleep, 3=StartExercise, 4=StopExercise, 5=StopAll, 6=StartEatingSoon, 7=StopEatingSoon}; field and enum absent in Java and Swift.
- ⚠️ `exerciseChoice value map` — *missing-in-java*: Python-only ExercisechoiceEnum {0=Continuous, 1=Timed}; field and enum absent in Java and Swift.
- ⚠️ `activeSleepSchedule bitmask` — *missing-in-java*: Python-only ActivesleepscheduleBitmask IntFlag {bit0=SleepSchedule1, bit1=SleepSchedule2, bit2=SleepSchedule3, bit3=SleepSchedule4}; field and bitmask absent in Java and Swift.

**Inconsistencies:**

- [PY-DIVERGENCE] currentUserMode: java uint8@10 = swift uint8@10, py uint8@13 — py diverges (3-byte shift).
- [PY-DIVERGENCE] previousUserMode: java uint8@11 = swift uint8@11, py uint8@12 — py diverges; py additionally reads requestedActionRaw uint8@11, the byte Java/Swift decode as previousUserMode.
- [PY-DIVERGENCE] Python parses 7 payload fields absent from Java/Swift: requestedActionRaw uint8@11, activeSleepScheduleRaw uint8@16 (bitmask), sleepStartedByGuiRaw uint8@17, exerciseTime uint16@18, exerciseChoiceRaw uint8@20, exerciseStoppedByTimerRaw uint8@21, eatingSoonStoppedByTimerRaw uint8@25. Java/Swift parse only 2 payload bytes (@10, @11) and their buildCargo() zero-fills offsets 12-25, so records round-tripped through Java/Swift lose these fields.
- Python has no enum values for user modes in Java/Swift: CurrentusermodeEnum/PrevioususermodeEnum {0=Normal,1=Sleeping,2=Exercising,3=EatingSoon} exist only in Python; Java and Swift expose bare ints (minor).
- No Swift port bugs found: Swift init(cargo:) reads raw[10]/raw[11] and buildCargo() writes [opcode 229,0][uint32 time][uint32 seq][currentUserMode][previousUserMode], byte-for-byte identical to Java parse()/buildCargo(); both are internally self-consistent.

### opCode 230 — LID_AA_PCM_CHANGE

`ControlIQPcmChangeHistoryLog` (java) ↔ `ControlIQPcmChangeHistoryLog` (swift) ↔ `LidAaPcmChange` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| currentPcmId | `currentPcmId`<br>uint8 @10 | `currentPcm`<br>uint8 @10 | `currentPcmRaw`<br>uint8 @13 | ❌ py-diverges-from-java | currentPcm: java uint8@10 (raw[10]) = swift uint8@10 (raw[10]); py uint8@13 — py diverges. Java/Swift buildCargo both serialize it back at offset 10. |
| previousPcmId | `previousPcmId`<br>uint8 @11 | `previousPcm`<br>uint8 @11 | `previousPcmRaw`<br>uint8 @12 | ❌ py-diverges-from-java | previousPcm: java uint8@11 (raw[11]) = swift uint8@11 (raw[11]); py uint8@12 — py diverges. Note py places current@13/previous@12, the reverse ordering of java's current@10/previous@11 within a 4-byte word. |
| pumpSuspended | — | — | `pumpSuspendedRaw`<br>uint8 @11 | ❌ missing-in-java | py uint8@11 (bool 0/1); absent from both Java and Swift parsers. py@11 collides with the byte Java/Swift decode as previousPcmId. |
| calculationAvailable | — | — | `calculationAvailableRaw`<br>uint8 @10 | ❌ missing-in-java | py uint8@10 (bool 0/1); absent from Java and Swift. py@10 collides with the byte Java/Swift decode as currentPcmId. |
| cgmAvailable | — | — | `cgmAvailableRaw`<br>uint8 @17 | ❌ missing-in-java | py uint8@17 (bool 0/1); absent from Java and Swift. |
| closedLoopPreferred | — | — | `closedLoopPreferredRaw`<br>uint8 @16 | ❌ missing-in-java | py uint8@16 (bool 0/1); absent from Java and Swift. |
| sufficientClosedLoopParams | — | — | `sufficientClosedLoopParamsRaw`<br>uint8 @15 | ❌ missing-in-java | py uint8@15 (bool 0/1); absent from Java and Swift. Offset 14 is unused by py, mirroring the reversed-word pattern (15,16,17 vs a hypothetical 14,15,16). |

**Enum / value-map findings:**

- ⚠️ `currentPcm/previousPcm PCM enum` — *partial*: Java PCM: 0=NO_CONTROL, 1=OPEN_LOOP, 2=CGM_INACTIVE, 3=CLOSED_LOOP. Python Currentpcm/Previouspcm maps: 0='No Control', 1='Open Loop', 2='Pining', 3='Closed Loop'. Value 2 label differs: Java CGM_INACTIVE vs Python 'Pining' (likely a corrupted label in the cloud-export-derived source). Values 0,1,3 agree.
- ⚠️ `PCM enum in Swift` — *missing-in-swift*: Swift port exposes currentPcm/previousPcm only as raw Int; the Java nested PCM enum (NO_CONTROL/OPEN_LOOP/CGM_INACTIVE/CLOSED_LOOP) was not ported. Decoded byte values are unaffected.
- ⚠️ `boolean maps (pumpSuspended, calculationAvailable, cgmAvailable, closedLoopPreferred, sufficientClosedLoopParams)` — *missing-in-java*: Python defines 0=FALSE/1=TRUE maps for five boolean fields that Java and Swift do not parse at all.

**Inconsistencies:**

- [PY-DIVERGENCE] currentPcm: java uint8@10 = swift uint8@10, py uint8@13 — py reads currentPcm from a different absolute offset (reversed within the 10-13 word).
- [PY-DIVERGENCE] previousPcm: java uint8@11 = swift uint8@11, py uint8@12 — py diverges; combined with the above, py decodes bytes 10/11 (Java's currentPcm/previousPcm positions) as calculationAvailable/pumpSuspended instead.
- [PY-DIVERGENCE] Python parses five extra uint8 boolean fields absent from Java/Swift: calculationAvailable@10, pumpSuspended@11, sufficientClosedLoopParams@15, closedLoopPreferred@16, cgmAvailable@17. If the on-pump record truly carries these, Java/Swift under-parse the payload; if not, Python is misaligned.
- [PY-DIVERGENCE] PCM enum value 2 label: Java CGM_INACTIVE vs Python 'Pining' — same numeric value, contradictory meaning labels.
- Swift port note (not a decode bug): Swift omits Java's nested PCM enum, exposing only raw Int ids; offsets, widths, and buildCargo serialization otherwise match Java exactly (uint8@10, uint8@11).

### opCode 235 — LID_AA_SLEEP_SCHEDULE_CHANGE

`AaSleepScheduleChangeHistoryLog` (java) ↔ `AaSleepScheduleChangeHistoryLog (Sources/TandemCore/Messages/HistoryLog/AaSleepScheduleChangeHistoryLog.swift)` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 238 — LID_AA_DELIVERY_STATUS_CHANGE

`AaDeliveryStatusChangeHistoryLog` (java) ↔ `AaDeliveryStatusChangeHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 244 — LID_AA_ENABLE_SETTING_CHANGE

`AaEnableSettingChangeHistoryLog` (java) ↔ `AaEnableSettingChangeHistoryLog` (swift) — *no Python parser* — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| enabled | `enabled`<br>uint8 @10 | `enabled`<br>uint8 @10 | — | ✅ match | enabled: java uint8@10 (raw[10], stored as int) = swift uint8@10 (cargo[10]). Offsets/widths identical; both buildCargo() serializers write the byte back at offset 10 and agree with their own parsers. Minor interpretation nuance: Swift stores Bool via cargo[10] != 0 (any nonzero = enabled) whereas Java preserves the raw int and isEnabled() requires enabled == 1; a raw value of 2 decodes as enabled=true in Swift but isEnabled()=false in Java. |

**Inconsistencies:**

- [PORT-BUG] enabled interpretation: Swift init(cargo:) uses cargo[10] != 0 (nonzero-truthy Bool) while Java isEnabled() requires raw[10] == 1 exactly and getEnabled() exposes the raw int; for a raw byte value like 2 the two sides decode opposite enabled states, and Swift discards the raw value entirely. Byte offset and width are otherwise identical (uint8@10).

### opCode 245 — LID_AA_TDI_SETTING_CHANGE

`AaTdiSettingChangeHistoryLog` (java) ↔ `AaTdiSettingChangeHistoryLog (Sources/TandemCore/Messages/HistoryLog/AaTdiSettingChangeHistoryLog.swift)` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 246 — LID_AA_WEIGHT_SETTING_CHANGE

`AaWeightSettingChangeHistoryLog` (java) ↔ `AaWeightSettingChangeHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 256 — LID_CGM_DATA_GXB

`DexcomG6CGMHistoryLog` (java) ↔ `DexcomG6CGMHistoryLog (and duplicate CGMHistoryLog, both typeId 256)` (swift) ↔ `LidCgmDataGxb` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| glucoseValueStatus | `glucoseValueStatusRaw`<br>uint16 @10 | `glucoseValueStatus`<br>uint16 @10 | `glucoseValueStatusRaw`<br>uint16 @12 | ❌ py-diverges-from-java | java uint16@10 = swift uint16@10; py uint16@12 — py diverges (consistent with 32-bit word-swapped cloud export layout) |
| cgmDataType | `cgmDataTypeRaw`<br>uint8 @12 | `cgmDataType`<br>uint8 @12 | `cgmDataTypeRaw`<br>uint8 @11 | ❌ py-diverges-from-java | java uint8@12 = swift uint8@12; py uint8@11 — py diverges |
| rate | `rate`<br>uint8 @13 | `rate`<br>uint8 @13 | `rateRaw`<br>int8 @10 | ❌ py-diverges-from-java | java uint8@13 (raw[13]) = swift uint8@13; py int8@10 ('>b') — offset AND signedness differ; py also exposes scaled property rate = rateRaw*0.1 mg/dL/min while java/swift expose raw only |
| algorithmState | `algorithmState`<br>uint8 @14 | `algorithmState`<br>uint8 @14 | `algorithmState`<br>uint8 @17 | ❌ py-diverges-from-java | java uint8@14 = swift uint8@14; py uint8@17 — py diverges |
| rssi | `rssi`<br>uint8 @15 | `rssi`<br>uint8 @15 | `rssi`<br>int8 @16 | ❌ py-diverges-from-java | java uint8@15 (raw[15]) = swift uint8@15; py int8@16 ('>b', dBm) — offset AND signedness differ; signed is physically plausible for RSSI in dBm |
| currentGlucoseDisplayValue | `currentGlucoseDisplayValue`<br>uint16 @16 | `currentGlucoseDisplayValue`<br>uint16 @16 | `currentGlucoseDisplayValue`<br>uint16 @14 | ❌ py-diverges-from-java | java uint16@16 = swift uint16@16; py uint16@14 — py diverges |
| timeStampSeconds | `timeStampSeconds`<br>uint32 @18 | `timeStampSeconds`<br>uint32 @18 | `egvTimeStamp`<br>uint32 @18 | ✅ match | uint32@18 on all three sides (name differs in py: egvTimeStamp; endianness difference is intentional) |
| egvInfoBitmask | `egvInfoBitmaskRaw`<br>uint16 @22 | `egvInfoBitmask`<br>uint16 @22 | `egvInfoBitmaskRaw`<br>uint16 @24 | ❌ py-diverges-from-java | java uint16@22 = swift uint16@22; py uint16@24 — py diverges |
| interval | `interval`<br>uint8 @24 | `interval`<br>uint8 @24 | `interval`<br>uint8 @23 | ❌ py-diverges-from-java | java uint8@24 = swift uint8@24; py uint8@23 — py diverges |
| trailingPadByte | `(unnamed, serializer only)`<br>uint8 @25 | `(unnamed, serializer only)`<br>uint8 @25 | — | ✅ match | java buildCargo writes constant 1 @25 with comment 'missing param?'; swift CGMHistoryLog.buildCargo mirrors it; neither parser reads @25; py does not read the corresponding word-swapped byte @22 either — consistently unparsed on all sides |

**Enum / value-map findings:**

- ⚠️ `glucoseValueStatus` — *partial*: java GlucoseValueStatus {0 PRECISE_VALUE, 1 SPECIAL_HIGH, 2 SPECIAL_LOW, 6 DO_NOT_SHOW}; py GlucosevaluestatusEnum {0,1,2} — missing DO_NOT_SHOW(6), so glucoseValueStatusRaw=6 logs an error and returns None in py; swift has no enum at all (raw Int only)
- ⚠️ `cgmDataType` — *partial*: java CgmDataType bitmask {1 FIVE_MINUTE_READING, 2 BACKFILL, 4 IMMEDIATE_MATCH_VALUE, 8 CALIBRATION, 16 NONE} exactly matches py CgmdatatypeBitmask {2^0..2^4}; swift has no enum — missing-in-swift
- ⚠️ `egvInfoBitmask` — *partial*: java EgvInfo {1,2,4,8,16 NO_EGV,32 VALID_TIMESTAMP,64 VALID_EGV_RANGE,128 VALID_ALG_STATE,256 EGV_PROCESSED} matches py EgvinfobitmaskBitmask {2^0..2^8} in values and meanings; swift has no enum — missing-in-swift

**Inconsistencies:**

- [PY-DIVERGENCE] Every payload field except the uint32 timestamp is at a different offset in python: glucoseValueStatus java/swift uint16@10 vs py uint16@12; cgmDataType uint8@12 vs uint8@11; rate uint8@13 vs int8@10; algorithmState uint8@14 vs uint8@17; rssi uint8@15 vs int8@16; currentGlucoseDisplayValue uint16@16 vs uint16@14; egvInfoBitmask uint16@22 vs uint16@24; interval uint8@24 vs uint8@23. The pattern is exactly a byte-reversal of each 4-byte word of the payload (words 10-13, 14-17, 18-21, 22-25), consistent with tconnectsync's big-endian cloud-export source rather than an arbitrary bug; Java's own parse() carries a TODO: 'this needs to be checked against the tconnectsync eventparser code since they seem to differ'.
- [PY-DIVERGENCE] Signedness: py reads rate as int8 ('>b' @10) and rssi as int8 ('>b' @16); java/swift read both as uint8 (raw[13]/raw[15], cargo[13]/cargo[15]). Negative rates (falling glucose) and dBm RSSI values decode differently: e.g. raw byte 0xF6 -> java/swift 246, py -10.
- [PY-DIVERGENCE] py GlucosevaluestatusEnum lacks Java's DO_NOT_SHOW(6); a record with glucoseValueStatusRaw=6 yields glucoseValueStatus=None plus an error log in tconnectsync but decodes to DO_NOT_SHOW in pumpX2.
- [PY-DIVERGENCE] py adds semantics java lacks: rate property scales rateRaw by 0.1 to mg/dL/min; java/swift getRate()/rate return the raw byte unscaled.
- Swift port has TWO classes claiming typeId 256: Sources/TandemCore/Messages/HistoryLog/CGMHistoryLog.swift and Sources/TandemCore/Messages/HistoryLog/DexcomG6CGMHistoryLog.swift, with identical field layouts; potential parser-registry ambiguity for opcode 256, though not a decoding divergence.
- Swift DexcomG6CGMHistoryLog omits Java's buildCargo() serializer and all three Java enums (GlucoseValueStatus, CgmDataType, EgvInfo); the duplicate CGMHistoryLog.swift supplies buildCargo (matching Java byte-for-byte, including the trailing constant 1 @25) but also lacks the enums — enum decoding is missing in swift.
- Java internal quirk (faithfully ported to swift CGMHistoryLog.buildCargo): serializer appends a constant byte 1 at offset 25 annotated '// missing param?' that parse() never reads.

### opCode 267 — LID_CGM_SESSION_TYPE_CHANGE

`CgmSessionTypeChangeHistoryLog` (java) ↔ `CgmSessionTypeChangeHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 279 — LID_BASAL_DELIVERY

`BasalDeliveryHistoryLog` (java) ↔ `BasalDeliveryHistoryLog` (swift) ↔ `LidBasalDelivery` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| commandedRateSource | `commandedRateSource`<br>uint16 @10 | `commandedRateSource`<br>uint16 @10 | `commandedRateSourceRaw`<br>uint16 @12 | ❌ py-diverges-from-java | java uint16@10 = swift uint16@10; py uint16@12 — py diverges by +2 |
| commandedRate | `commandedRate`<br>uint16 @14 | `commandedRate`<br>uint16 @14 | `commandedRate`<br>uint16 @16 | ❌ py-diverges-from-java | java uint16@14 = swift uint16@14; py uint16@16 — py diverges by +2 |
| profileBasalRate | `profileBasalRate`<br>uint16 @16 | `profileBasalRate`<br>uint16 @16 | `profileBasalRate`<br>uint16 @14 | ❌ py-diverges-from-java | java uint16@16 = swift uint16@16; py uint16@14 — py places profileBasalRate BEFORE commandedRate (order swapped vs java) |
| algorithmRate | `algorithmRate`<br>uint16 @18 | `algorithmRate`<br>uint16 @18 | `algorithmRate`<br>uint16 @20 | ❌ py-diverges-from-java | java uint16@18 = swift uint16@18; py uint16@20 — py diverges by +2 |
| tempRate | `tempRate`<br>uint16 @20 | `tempRate`<br>uint16 @20 | `tempRate`<br>uint16 @18 | ❌ py-diverges-from-java | java uint16@20 = swift uint16@20; py uint16@18 — py places tempRate BEFORE algorithmRate (order swapped vs java) |

**Enum / value-map findings:**

- ⚠️ `commandedRateSource` — *missing-in-java*: Python defines CommandedratesourceEnum/Map {0:Suspended, 1:Profile, 2:'Temp Rate', 3:Algorithm, 4:'Temp Rate and Algorithm'}; Java and Swift both expose commandedRateSource as a bare int with no enum or javadoc value comments

**Inconsistencies:**

- [PY-DIVERGENCE] commandedRateSource: java/swift uint16@10, py uint16@12 — py reads 2 bytes later; java parse() leaves a gap at bytes 12-13 that py does not have
- [PY-DIVERGENCE] commandedRate: java/swift uint16@14, py uint16@16
- [PY-DIVERGENCE] profileBasalRate: java/swift uint16@16, py uint16@14 — field order swapped: py layout is source@12, profile@14, commanded@16 vs java source@10, (gap@12), commanded@14, profile@16
- [PY-DIVERGENCE] algorithmRate: java/swift uint16@18, py uint16@20
- [PY-DIVERGENCE] tempRate: java/swift uint16@20, py uint16@18 — temp/algorithm order swapped vs java (java: algorithm@18, temp@20; py: temp@18, algorithm@20)
- Java-internal serializer/parser mismatch (faithfully copied into Swift, so not a port bug): buildCargo() writes the five uint16 fields contiguously at offsets 10,12,14,16,18 (Bytes.firstTwoBytesLittleEndian x5 immediately after the 10-byte header), but parse()/init(cargo:) reads them at 10,14,16,18,20 — round-tripping buildCargo through parse shifts commandedRate<-profileBasalRate, profileBasalRate<-algorithmRate, algorithmRate<-tempRate, and tempRate<-0 (fillCargo padding). Constructed/synthetic cargo does not match wire layout assumed by the parser.
- commandedRateSource value map (0=Suspended, 1=Profile, 2=Temp Rate, 3=Algorithm, 4=Temp Rate and Algorithm) exists only in Python; Java and Swift expose raw int with no enum

### opCode 280 — LID_BOLUS_DELIVERY

`BolusDeliveryHistoryLog` (java) ↔ `BolusDeliveryHistoryLog (Sources/TandemCore/Messages/HistoryLog/BolusDeliveryHistoryLog.swift)` (swift) ↔ `LidBolusDelivery` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| bolusId | `bolusID`<br>uint16 @10 | `bolusID`<br>uint16 @10 | `bolusId`<br>uint16 @12 | ❌ py-diverges-from-java | java uint16@10 = swift uint16@10; py uint16@12 — py diverges |
| bolusDeliveryStatus | `bolusDeliveryStatusId`<br>uint8 @12 | `bolusDeliveryStatus`<br>uint8 @12 | `bolusDeliveryStatusRaw`<br>uint8 @11 | ❌ py-diverges-from-java | java uint8@12 = swift uint8@12; py uint8@11 — py diverges |
| bolusTypeBitmask | `bolusTypeBitmask`<br>uint8 @13 | `bolusTypeBitmask`<br>uint8 @13 | `bolusTypeRaw`<br>uint8 @10 | ❌ py-diverges-from-java | java uint8@13 = swift uint8@13; py uint8@10 — py diverges; bitmask value meanings also differ (see enum findings) |
| bolusSource | `bolusSource`<br>uint8 @14 | `bolusSource`<br>uint8 @14 | `bolusSourceRaw`<br>uint8 @17 | ❌ py-diverges-from-java | java uint8@14 = swift uint8@14; py uint8@17 — py diverges |
| reserved | `reserved`<br>uint8 @15 | `reserved`<br>uint8 @15 | — | ❌ missing-in-python | java uint8@15 = swift uint8@15; Python has no 'reserved' field (Python's closest analogue is remoteId uint8@16, a different offset and name) |
| remoteId | — | — | `remoteId`<br>uint8 @16 | ❌ missing-in-java | py-only uint8@16; absent in Java and Swift (both leave no named field at 16 as a uint8 — Java reads requestedNow uint16@16 there instead) |
| requestedNow | `requestedNow`<br>uint16 @16 | `requestedNow`<br>uint16 @16 | `requestedNow`<br>uint16 @14 | ❌ py-diverges-from-java | java uint16@16 = swift uint16@16; py uint16@14 — py diverges |
| requestedLater | `requestedLater`<br>uint16 @18 | `requestedLater`<br>uint16 @18 | `requestedLater`<br>uint16 @20 | ❌ py-diverges-from-java | java uint16@18 = swift uint16@18; py uint16@20 — py diverges |
| correction | `correction`<br>uint16 @20 | `correction`<br>uint16 @20 | `correction`<br>uint16 @18 | ❌ py-diverges-from-java | java uint16@20 = swift uint16@20; py uint16@18 — py diverges (correction and requestedLater are swapped relative to Java) |
| extendedDurationRequested | `extendedDurationRequested`<br>uint16 @22 | `extendedDurationRequested`<br>uint16 @22 | `extendedDurationRequested`<br>uint16 @24 | ❌ py-diverges-from-java | java uint16@22 = swift uint16@22; py uint16@24 — py diverges |
| deliveredTotal | `deliveredTotal`<br>uint16 @24 | `deliveredTotal`<br>uint16 @24 | `deliveredTotal`<br>uint16 @22 | ❌ py-diverges-from-java | java uint16@24 = swift uint16@24; py uint16@22 — py diverges (deliveredTotal and extendedDurationRequested are swapped relative to Java) |

**Enum / value-map findings:**

- ⚠️ `bolusDeliveryStatus` — *missing-in-java*: Python defines BolusdeliverystatusEnum {0: BolusCompleted, 1: BolusStarted}; Java and Swift expose only the raw int with no enum or value comments
- ⚠️ `bolusType` — *values-differ*: Java/Swift bitmask: FOOD1=1, CORRECTION=2, EXTENDED=4, FOOD2=8. Python BolustypeBitmask: Now=1, Later=2, Override=4, Correction=8, Carb=16, EatingSoonMode=32. Completely different bit meanings (e.g. bit 2 = CORRECTION in Java but Later in Python; bit 8 = FOOD2 in Java but Correction in Python). Swift matches Java exactly
- ⚠️ `bolusSource` — *partial*: Overlap on 0/1/7/8: Java QUICK_BOLUS=0/GUI=1/CONTROL_IQ_AUTO_BOLUS=7/BLUETOOTH_REMOTE_BOLUS=8 vs Python PumpButton=0/PumpGui=1/Algorithm=7/Ble=8 (label differences only). Python additionally defines Remote=5 and EatingSoonBolus=9 which are missing from Java/Swift. Swift enum matches Java exactly

**Inconsistencies:**

- [PY-DIVERGENCE] bolusId: java uint16@10 = swift uint16@10; py uint16@12 — Python places bolusTypeRaw uint8@10 and bolusDeliveryStatus uint8@11 before bolusId, whereas Java puts bolusID first at 10-11
- [PY-DIVERGENCE] bolusDeliveryStatus: java uint8@12 = swift uint8@12; py uint8@11
- [PY-DIVERGENCE] bolusTypeBitmask: java uint8@13 = swift uint8@13; py uint8@10; and the bitmask semantics differ entirely (java FOOD1=1/CORRECTION=2/EXTENDED=4/FOOD2=8 vs py Now=1/Later=2/Override=4/Correction=8/Carb=16/EatingSoonMode=32)
- [PY-DIVERGENCE] bolusSource: java uint8@14 = swift uint8@14; py uint8@17; Python also defines extra source values Remote=5 and EatingSoonBolus=9 absent from Java/Swift
- [PY-DIVERGENCE] requestedNow: java uint16@16 = swift uint16@16; py uint16@14
- [PY-DIVERGENCE] requestedLater vs correction swapped: java requestedLater uint16@18 / correction uint16@20 (= swift); py correction uint16@18 / requestedLater uint16@20
- [PY-DIVERGENCE] deliveredTotal vs extendedDurationRequested swapped: java extendedDurationRequested uint16@22 / deliveredTotal uint16@24 (= swift); py deliveredTotal uint16@22 / extendedDurationRequested uint16@24
- [PY-DIVERGENCE] reserved/remoteId: java 'reserved' uint8@15 (= swift) has no Python counterpart; Python 'remoteId' uint8@16 has no Java/Swift counterpart — the entire 10-25 payload layout is a different permutation between the BLE (Java/Swift) and cloud-export (Python) formats
- Enum gap (minor): Python names bolusDeliveryStatus values (0=Bolus Completed, 1=Bolus Started); Java/Swift leave the field an undocumented raw int

### opCode 283 — LID_WUMP_OCCLUSION_DEBUG

`WumpOcclusionDebugHistoryLog` (java) ↔ `WumpOcclusionDebugHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 286 — LID_SNOOZE_ACTIVATED

`SnoozeActivatedHistoryLog` (java) ↔ `SnoozeActivatedHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| (no payload fields) | `-` | `-` | — | ✅ match | Event has no payload beyond the common header: java parse() only Validate.isTrue(raw.length == 26) + parseBase(raw); buildCargo writes typeId bytes {30,1} + uint32 pumpTimeSec + uint32 sequenceNum. Swift buildCargo emits identical little-endian typeId (286 & 0xFF, >>8) + Bytes.toUint32(pumpTimeSec) + Bytes.toUint32(sequenceNum) and init(cargo:) defers entirely to HistoryLog base. Both serializers agree with their own parsers. |

_No inconsistencies found._

### opCode 288 — LID_AA_AUTO_BOLUS_REJECTED

`AaAutoBolusRejectedHistoryLog` (java) ↔ `AaAutoBolusRejectedHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 291 — LID_TIPSC_REQ_PRIME_CANNULA

`TipscReqPrimeCannulaHistoryLog` (java) ↔ `TipscReqPrimeCannulaHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| (no payload fields) | `-` | `-` | — | ✅ match | Java parse() only validates raw.length == 26 and calls parseBase(raw); no payload fields beyond the common header (typeId@0-1, pumpTimeSec uint32@2, sequenceNum uint32@6). Swift init(cargo:) likewise only calls the HistoryLog base initializer. Both buildCargo() serializers emit typeId bytes [35,1] + toUint32(pumpTimeSec) + toUint32(sequenceNum), consistent with their parsers. |

_No inconsistencies found._

### opCode 301 — LID_WUMP_CARTRIDGE_FILLED

`WumpCartridgeFilledHistoryLog` (java) ↔ `WumpCartridgeFilledHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| pumpTimeSec | `pumpTimeSec`<br>uint32 @2 | `pumpTimeSec`<br>uint32 @2 | — | ✅ match | base header field parsed via parseBase/HistoryLog superclass on both sides; java uint32@2 = swift uint32@2 |
| sequenceNum | `sequenceNum`<br>uint32 @6 | `sequenceNum`<br>uint32 @6 | — | ✅ match | base header field; java uint32@6 = swift uint32@6 |

_No inconsistencies found._

### opCode 302 — LID_WUMP_CARTRIDGE_REMOVED

`WumpCartridgeRemovedHistoryLog` (java) ↔ `WumpCartridgeRemovedHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 307 — LID_VERSIONS_A

`VersionsAHistoryLog` (java) ↔ `VersionsAHistoryLog` (swift) ↔ `LidVersionsA` (py) — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| armPartNumber | — | — | `armPartNumber`<br>uint32 @10 | ❌ missing-in-java | py uint32@10 (UINT32 unpack_from at 10); absent from Java parse() (which parses no payload fields beyond the base header) and equally absent from the Swift port, so Swift faithfully mirrors Java |
| armSwVersion | — | — | `armSwVersion`<br>uint32 @14 | ❌ missing-in-java | py uint32@14; absent from both Java and Swift parsers (neither reads any payload bytes for opCode 307) |
| blePartNumber | — | — | `blePartNumber`<br>uint32 @18 | ❌ missing-in-java | py uint32@18; absent from both Java and Swift parsers |
| bleSwVersion | — | — | `bleSwVersion`<br>uint32 @22 | ❌ missing-in-java | py uint32@22; absent from both Java and Swift parsers |

**Inconsistencies:**

- [PY-DIVERGENCE] Python LidVersionsA decodes four uint32 payload fields (armPartNumber@10, armSwVersion@14, blePartNumber@18, bleSwVersion@22) that the Java reference VersionsAHistoryLog does not parse at all — Java parse() only validates length==26 and calls parseBase(raw), and its buildCargo(pumpTimeSec, sequenceNum) zero-fills bytes 10-25. Java/Swift therefore silently drop the version payload that Python exposes; no side decodes wrong values, but Java/Swift lose information relative to Python.
- Java internal note: buildCargo cannot round-trip a real pump record's payload (bytes 10-25 are zero-filled), consistent with the parser deliberately ignoring the payload. Swift buildCargo has the identical behavior, so Java and Swift are internally consistent with their own parsers.

### opCode 313 — LID_AA_DAILY_STATUS

`DailyStatusHistoryLog` (java) ↔ `DailyStatusHistoryLog` (swift) ↔ `LidAaDailyStatus` (py) — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| sensorType | `sensorType`<br>uint8 @11 | `sensorType`<br>uint8 @11 | `sensorTypeRaw`<br>uint8 @11 | ✅ match | java uint8@11 (raw[11]) = swift uint8@11 (cargo[11]) = py uint8@11 (UINT8 @11) — all match |
| userMode | `userMode`<br>uint8 @12 | `userMode`<br>uint8 @12 | `usermodeRaw`<br>uint8 @12 | ✅ match | java uint8@12 = swift uint8@12 = py uint8@12 — all match; name differs only in casing (py 'usermode') |
| pumpControlState | `pumpControlState`<br>uint8 @13 | `pumpControlState`<br>uint8 @13 | `pumpControlStateRaw`<br>uint8 @13 | ✅ match | java uint8@13 = swift uint8@13 = py uint8@13 — all match. Byte @10 is padding (Java buildCargo writes 0 there; no side parses it) |

**Enum / value-map findings:**

- ⚠️ `sensorType` — *missing-in-java*: Python SensortypeEnum/SensortypeMap: 0=CGM_TYPE_NONE, 1=CGM_TYPE_DEXCOM_G6, 2=CGM_TYPE_LIBRE2, 3=CGM_TYPE_DEXCOM_G7. Java and Swift expose raw int with no enum or value comments — no conflict possible, just absent.
- ⚠️ `userMode` — *missing-in-java*: Python UsermodeEnum/UsermodeMap: 0=Normal, 1=Sleeping, 2=Exercising. Java and Swift expose raw int only.
- ⚠️ `pumpControlState` — *missing-in-java*: Python PumpcontrolstateEnum/PumpcontrolstateMap: 0=PCM No Control (No cartridge installed), 1=PCM Open Loop, 2=PCM Pining, 3=PCM Closed Loop. Java and Swift expose raw int only.

**Inconsistencies:**

- Swift DailyStatusHistoryLog has no buildCargo() serializer (Java buildCargo writes {0, sensorType, userMode, pumpControlState} at offsets 10-13, consistent with its own parse()); Swift is parse-only, so no round-trip check possible — not a layout bug, all parsed offsets/widths match Java exactly.
- Enum value maps for sensorType/userMode/pumpControlState exist only in Python; Java (reference) and Swift expose raw ints with no enums or value comments — label gap only, no value conflicts.

### opCode 318 — LID_AA_EXERCISE_TIME_CHANGE

`AAExerciseTimeChangeHistoryLog` (java) ↔ `AaExerciseTimeChangeHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 319 — LID_AA_EXERCISE_CHOICE_CHANGE

`AAExerciseChoiceChangeHistoryLog` (java) ↔ `AaExerciseChoiceChangeHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 332 — LID_AA_TDIEST_CHANGE

`AATdiEstChangeHistoryLog` (java) ↔ `AaTdiEstChangeHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 348

`PrimeInprocessHistoryLog` (java) ↔ `PrimeInprocessHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 367

`CgmRejoinSessionHistoryLog` (java) ↔ `CgmRejoinSessionHistoryLog.swift` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 368

`CgmSensorTypeChangeHistoryLog` (java) ↔ `CgmSensorTypeChangeHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 369 — LID_CGM_ALERT_ACTIVATED_B

`CgmAlertActivatedDexHistoryLog (historyLog)` (java) ↔ `CgmAlertActivatedDexHistoryLog.swift (Sources/TandemCore/Messages/HistoryLog)` (swift) ↔ `LidCgmAlertActivatedDex (events.py, line 4505)` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alertId | `alertId`<br>uint32 @10 | `alertId`<br>uint32 @10 | `dalertIdRaw`<br>uint8 @13 | ❌ py-diverges-from-java | java: Bytes.readUint32(raw,10) -> alertId (4 bytes, offset 10-13). swift: Bytes.readUint32(cargo,10) -> alertId UInt32 (matches java exactly). py: struct.unpack_from(UINT8, raw[:26], 13) -> dalertIdRaw (1 byte, offset 13 only). Offset (10 vs 13) and width (32-bit vs 8-bit) both diverge; python decodes only 1 of the 4 bytes java/swift use, and starts 3 bytes later, so the decoded 'alert id' concept is not comparable in raw form between python and java/swift. |
| alert (derived enum from alertId) | `alert`<br>CGMAlertStatusResponse.CGMAlert (derived via CGMAlert.fromId((int) alertId)) @-1 | @-1 | `dalertId (property)`<br>DalertidEnum (derived from dalertIdRaw via lookup, 18 named values 1-48) @-1 | ❌ missing-in-swift | java derives a typed CGMAlert enum from the raw alertId via CGMAlertStatusResponse.CGMAlert.fromId(); python derives DalertidEnum/DalertidMap from dalertIdRaw with an 18-entry value map (1=CgmFixedLow ... 48=CgmUnavailable). swift only exposes the raw UInt32 alertId with no enum/lookup counterpart at all. Could not locate CGMAlertStatusResponse.java in the provided pumpX2 checkout to diff exact java enum values against python's DalertidMap. |
| sensorType | @-1 | @-1 | `sensorTypeRaw`<br>uint8 @12 | ❌ missing-in-java | python-only field, struct.unpack_from(UINT8, raw[:26], 12). java parse() and swift init(cargo:) never read byte 12 at all -- also missing-in-swift (schema has no combined enum value, noting here). |
| faultLocatorData | @-1 | @-1 | `faultLocatorData`<br>uint32 @14 | ❌ missing-in-java | python-only field, struct.unpack_from(UINT32, raw[:26], 14). java/swift never read bytes 14-17 -- also missing-in-swift. |
| param1 | @-1 | @-1 | `param1`<br>uint32 @18 | ❌ missing-in-java | python-only field, struct.unpack_from(UINT32, raw[:26], 18). java/swift never read bytes 18-21 -- also missing-in-swift. |
| param2 | @-1 | @-1 | `param2`<br>float32 @22 | ❌ missing-in-java | python-only field, struct.unpack_from(FLOAT32, raw[:26], 22), fills out the record to the full 26-byte length (22+4=26). java/swift never read bytes 22-25 -- also missing-in-swift. |

**Inconsistencies:**

- [PY-DIVERGENCE] alertId: java uint32@10 (Bytes.readUint32(raw,10)) matches swift UInt32@10, but python's dalertIdRaw is only uint8@13 (struct.unpack_from(UINT8, raw[:26], 13)) -- offset shifted by 3 bytes and width shrunk from 32-bit to 8-bit, so python decodes a different byte range than java/swift for the same nominal 'alert id' concept.
- [PY-DIVERGENCE] python defines 4 additional payload fields with no java/swift counterpart at all: sensorTypeRaw (uint8@12), faultLocatorData (uint32@14), param1 (uint32@18), param2 (float32@22). Java's parse()/buildCargo() and Swift's init(cargo:) only ever touch bytes 10-13 (the single alertId uint32) and completely ignore bytes 12 and 14-25, which python treats as meaningful data filling the full 26-byte record.
- Naming mismatch beyond a simple label difference: the Java @HistoryLogProps annotation for opCode 369 declares internalName = 'LID_CGM_ALERT_ACTIVATED_B' / displayName = 'CGM Alert Activated B', even though the Java (and ported Swift) class itself is named CgmAlertActivatedDexHistoryLog. Python's independently-derived event for the same opCode 369 is named 'LID_CGM_ALERT_ACTIVATED_DEX' and has a completely different, richer field layout (5 fields vs java/swift's 1). This is consistent with pumpX2's own internalName annotation being stale/mislabeled relative to its class name, and/or opcode 369 covering two structurally different firmware-generation payloads that only java/swift's minimal single-uint32 parser happens to be compatible with by accident.
- [PORT-BUG] Swift's CgmAlertActivatedDexHistoryLog.swift provides only init(cargo:) with no buildCargo()/serializer counterpart to Java's static buildCargo(pumpTimeSec, sequenceNum, alertId) -- unlike ~116 of the other 137 Swift HistoryLog files, which do carry a buildCargo(). This Swift type can decode but not construct a record of this type, unlike Java.

### opCode 370 — LID_CGM_ALERT_CLEARED_B

`CgmAlertClearedDexHistoryLog` (java) ↔ `CgmAlertClearedDexHistoryLog` (swift) ↔ `LidCgmAlertClearedDex` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alertId | `alertId`<br>uint32 @10 | `alertId`<br>uint32 @10 | `dalertIdRaw`<br>uint8 @13 | ❌ py-diverges-from-java | java: alertId = Bytes.readUint32(raw,10) (4 bytes, offsets 10-13); swift: alertId = Bytes.readUint32(cargo,10) — matches java exactly; py: dalertIdRaw = struct.unpack_from(UINT8, raw, 13) — single byte at offset 13, not a uint32 spanning 10-13. Java/Swift's 4-byte read absorbs 3 extra bytes (10,11, and py's separate sensorType byte at 12) that Python treats as distinct/unused fields, so java/swift's decoded 'alertId' integer will not equal py's dalertIdRaw whenever bytes 10-12 are nonzero. |
| sensorType | `(absent)`<br>@-1 | `(absent)`<br>@-1 | `sensorTypeRaw`<br>uint8 @12 | ❌ missing-in-java | python defines a distinct sensorTypeRaw = uint8@12 (SensortypeEnum: 0=Invalid,1=CGM_TYPE_DEXCOM_G6,3=CGM_TYPE_DEXCOM_G7) that has no counterpart field in java's single alertId uint32@10 model; swift mirrors java and also has no sensorType field (status recorded as missing-in-java; note it is also absent in swift). |
| alertId enum/label lookup | `alert (CGMAlertStatusResponse.CGMAlert, via fromId)`<br>enum-lookup @10 | `(absent)`<br>@-1 | `dalertId (DalertidEnum property, DalertidMap labels)`<br>enum-lookup @13 | ❌ missing-in-swift | java stores a decoded CGMAlertStatusResponse.CGMAlert enum (via CGMAlert.fromId((int)alertId)) alongside the raw long alertId, and exposes getAlert(); python defines DalertidEnum with 18 named members (CgmFixedLow=1, CgmHigh=2, CgmLow=3, CgmRapidFall=8, CgmSensorFail=11, CgmSensorExpiringSoon=12, CgmSensorExpired=13, CgmOutOfRange=14, CgmTransmitterError=20, CgmSensorExpiring2=22, CgmReplaceSensor=25, CgmTemperature=26, CgmFailedConnection=27, CgmTransmitterExpired=39, PumpBluetoothError=40, CgmTransmitterExpiringSoon=45, CgmTransmitterExpiring2=46, CgmUnavailable=48) plus DalertidMap string labels; swift exposes only the raw UInt32 alertId with no enum type or lookup at all. |

**Enum / value-map findings:**

- ⚠️ `alertId enum (CGMAlert / DalertidEnum)` — *missing-in-swift*: Java: CGMAlertStatusResponse.CGMAlert.fromId(int) resolves alertId to a named alert enum, retained as `alert` and exposed via getAlert(). Python: DalertidEnum has 18 members with matching numeric ids (CgmFixedLow=1, CgmHigh=2, CgmLow=3, CgmRapidFall=8, CgmSensorFail=11, CgmSensorExpiringSoon=12, CgmSensorExpired=13, CgmOutOfRange=14, CgmTransmitterError=20, CgmSensorExpiring2=22, CgmReplaceSensor=25, CgmTemperature=26, CgmFailedConnection=27, CgmTransmitterExpired=39, PumpBluetoothError=40, CgmTransmitterExpiringSoon=45, CgmTransmitterExpiring2=46, CgmUnavailable=48), each with a corresponding DalertidMap string label. Swift: no enum type or lookup exists; only the raw UInt32 alertId is stored/exposed.
- ⚠️ `sensorType enum (SensortypeEnum)` — *missing-in-swift*: Python defines SensortypeEnum (0=Invalid, 1=CgmTypeDexcomG6, 3=CgmTypeDexcomG7) with SensortypeMap string labels for the uint8@12 sensorType byte. Neither Java nor Swift has any field, enum, or byte read corresponding to this sensorType concept for opCode 370.

**Inconsistencies:**

- [PY-DIVERGENCE] alertId: java uint32@10 (bytes 10-13, Bytes.readUint32(raw,10)) = swift uint32@10 (Bytes.readUint32(cargo,10)); py reads dalertIdRaw as a single uint8@13 (struct.unpack_from(UINT8, raw, 13)) — offset and width both diverge from java, so py's decoded alert id will differ from java/swift's decoded uint32 whenever the intervening bytes (10-12) are nonzero.
- [PY-DIVERGENCE] sensorType: python's build() also reads a separate sensorTypeRaw = uint8@12 (with SensortypeMap/SensortypeEnum: 0=Invalid, 1=CGM_TYPE_DEXCOM_G6, 3=CGM_TYPE_DEXCOM_G7) that has no corresponding field anywhere in java or swift, both of which fold that byte into the single 4-byte alertId read starting at offset 10.
- [PORT-BUG] Swift CgmAlertClearedDexHistoryLog.swift implements only `required init(cargo:)` and has no `buildCargo(pumpTimeSec:sequenceNum:alertId:)` static serializer, whereas Java provides `public static byte[] buildCargo(long pumpTimeSec, long sequenceNum, long alertId)` (lines 54-60) that mirrors the parse layout ({370,0} + toUint32(pumpTimeSec) + toUint32(sequenceNum) + toUint32(alertId)). This asymmetry means the Swift port cannot construct/serialize a CgmAlertClearedDexHistoryLog record (no round-trip test capability), unlike sibling ports such as AlertActivatedHistoryLog.swift or CgmAlertAckHistoryLog.swift which do implement matching buildCargo methods.
- [PORT-BUG] Swift exposes no decoded alert-enum equivalent to Java's `CGMAlertStatusResponse.CGMAlert alert` field / `getAlert()` accessor (populated via `CGMAlert.fromId((int) alertId)` in both the byte[]-based and the (pumpTimeSec,sequenceNum,alertId) constructors); Swift only stores the raw `alertId: UInt32` with no enum mapping at all, dropping label/semantic information that the port target is expected to carry.
- Naming-only difference (not a bug): java internalName/displayName is "LID_CGM_ALERT_CLEARED_B" / "CGM Alert Cleared B" while python's NAME is "LID_CGM_ALERT_CLEARED_DEX" — same opCode 370 and same semantic event, just different label text; swift has no displayName/internalName metadata field at all for this class.

### opCode 371 — LID_CGM_ALERT_ACK_B

`CgmAlertAckDexHistoryLog` (java) ↔ `CgmAlertAckDexHistoryLog` (swift) ↔ `LidCgmAlertAckDex` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alertId | `alertId`<br>uint32 @10 | `alertId`<br>uint32 @10 | `dalertIdRaw`<br>uint8 @13 | ❌ py-diverges-from-java | java: `this.alertId = Bytes.readUint32(raw, 10)` (4 bytes, offset 10-13); swift: `alertId = Bytes.readUint32(cargo, 10)` matches java exactly. python: `dalertId, = struct.unpack_from(UINT8, raw[:26], 13)` — reads a single byte at offset 13 only, treating it as the alert-id value, whereas java/swift consume all 4 bytes 10-13 as one uint32 alertId. This is a real layout/width divergence (uint32@10 vs uint8@13), not just endianness. |
| sensorType | — | — | `sensorTypeRaw`<br>uint8 @12 | ❌ missing-in-java | [PY-DIVERGENCE] python: `sensorType, = struct.unpack_from(UINT8, raw[:26], 12)` (SensortypeEnum: 0=Invalid,1=CGM_TYPE_DEXCOM_G6,3=CGM_TYPE_DEXCOM_G7). Byte 12 falls inside java/swift's single 4-byte alertId@10 field; java's parse() and swift's init(cargo:) never expose this byte as its own field. |
| ackSource | — | — | `ackSourceRaw`<br>uint32 @14 | ❌ missing-in-java | [PY-DIVERGENCE] python: `ackSource, = struct.unpack_from(UINT32, raw[:26], 14)` (AcksourceEnum: 0=Alert Acknowledged by User, 1=Alert Acknowledged by Software), occupying bytes 14-17. Neither java's parse()/buildCargo() nor swift's init(cargo:) read anything at offset 14 — bytes 14-17 are completely unread on the java/swift side. |
| alert (decoded enum from alertId) | `alert`<br>enum CGMAlertStatusResponse.CGMAlert (derived via CGMAlert.fromId((int) alertId)) | — | — | ❌ missing-in-swift | [PORT-BUG] java's parse() additionally sets `this.alert = CGMAlertStatusResponse.CGMAlert.fromId((int) alertId)` and exposes getAlert(); java also has a constructor overload taking CGMAlertStatusResponse.CGMAlert directly. Swift's CgmAlertAckDexHistoryLog only stores the raw `alertId: UInt32` with no equivalent enum-decoding property or convenience initializer. |

**Enum / value-map findings:**

- ⚠️ `sensorType` — *missing-in-swift*: python-only SensortypeEnum (0=Invalid,1=CgmTypeDexcomG6,3=CgmTypeDexcomG7); no corresponding enum/field exists in java or swift for this opcode.
- ⚠️ `ackSource` — *missing-in-swift*: python-only AcksourceEnum (0=AlertAcknowledgedByUser,1=AlertAcknowledgedBySoftware); no corresponding enum/field exists in java or swift for this opcode.
- ⚠️ `alert/dalertId value map` — *partial*: python's DalertidEnum enumerates 18 named alert ids (1,2,3,8,11,12,13,14,20,22,25,26,27,39,40,45,46,48) sourced from cloud data; java instead derives the label via the separate CGMAlertStatusResponse.CGMAlert.fromId(...) enum (not opened in this review) rather than defining its own map on this class. Even setting aside label-set parity, python decodes the id from a 1-byte field (offset 13) while java derives it from the full 4-byte alertId (offset 10), so the raw values feeding the two enums differ per the offset/width divergence noted above.

**Inconsistencies:**

- [PY-DIVERGENCE] alertId: java/swift uint32@10 (bytes 10-13) vs python dalertIdRaw uint8@13 only — python additionally decodes sensorTypeRaw uint8@12 (a byte java/swift fold into their single 4-byte alertId) and ackSourceRaw uint32@14 (bytes java/swift never read at all). This is a genuine field-layout divergence, not merely an endianness difference.
- [PY-DIVERGENCE] sensorType (uint8@12) and ackSource (uint32@14) are unique to LidCgmAlertAckDex in tconnectsync; CgmAlertAckDexHistoryLog.java's parse()/buildCargo() (and the matching swift init(cargo:)) have no fields at these offsets whatsoever.
- [PORT-BUG] swift CgmAlertAckDexHistoryLog exposes only the raw `alertId: UInt32` and omits java's derived `alert: CGMAlertStatusResponse.CGMAlert` property (set via CGMAlert.fromId((int) alertId) in parse()), so the typed alert classification available in java (getAlert()) has no equivalent accessor in the Swift port.
- [PORT-BUG, minor] java defines a static buildCargo(pumpTimeSec, sequenceNum, alertId) serializer (and constructors that call it) for round-tripping/tests; the swift class provides no buildCargo()/serializer at all, only init(cargo:) — an internal-consistency completeness gap versus java, though not itself a decode-correctness bug since swift is parse-only here.

### opCode 372 — LID_CGM_DATA_FSL2

`CgmDataFsl2HistoryLog` (java) ↔ `CgmDataFsl2HistoryLog` (swift) ↔ `LidCgmDataFsl2` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| glucoseValueStatus (Java: status) | `status`<br>uint16 @10 | — | `glucoseValueStatusRaw`<br>uint8 @13 | ❌ missing-in-swift | Java reads Bytes.readShort(raw,10) -> uint16 @10-11. Python reads struct.unpack_from(UINT8, raw, 13) -> uint8 @13. [PY-DIVERGENCE] offset AND width both differ (java 2 bytes@10, python 1 byte@13); these are not simply mislabeled aliases of the same bytes. Swift has no stored property, computed accessor, or parse logic for this concept at all -- init(cargo:) only calls super.init and buildCargo() only accepts pumpTimeSec/sequenceNum. |
| cgmDataType (Java: type) | `type`<br>uint8 @12 | — | `cgmDataTypeRaw`<br>uint8 @12 | ❌ missing-in-swift | Java raw[12] and Python struct.unpack_from(UINT8, raw, 12) agree on offset 12, width uint8 (java/python match here). Swift entirely omits this field -- no property, no parse. |
| rate | `rate`<br>uint8 @13 | — | `rateRaw`<br>int16 @10 | ❌ missing-in-swift | Java raw[13] -> uint8@13, raw counts, no scaling exposed via getRate(). Python struct.unpack_from(INT16, raw, 10) -> int16@10, with self.rate = rateRaw * 0.1 (mg/dL/min). [PY-DIVERGENCE] offset differs (13 vs 10), width differs (1 byte vs 2 bytes), and python applies a 0.1 scale factor java does not. Note java's byte@10-11 is the same span Python assigns to `rate`, but Java assigns that span to `status` instead -- the two implementations' field layouts for offsets 10-13 are effectively swapped/scrambled relative to each other. Swift has no field. |
| rssi | `rssi`<br>uint8 @15 | — | `rssi`<br>int8 @16 | ❌ missing-in-swift | Java raw[15] -> uint8@15 (unsigned). Python struct.unpack_from(INT8, raw, 16) -> int8@16 (signed, dBm). [PY-DIVERGENCE] offset differs by one byte (15 vs 16) and signedness differs (uint8 vs int8) -- RSSI in dBm is conventionally signed, suggesting Java's unsigned uint8 read may itself be semantically wrong, but regardless the two disagree on both offset and signedness. Swift has no field. |
| value / currentGlucoseDisplayValue | `value`<br>uint16 @16 | — | `currentGlucoseDisplayValue`<br>uint16 @14 | ❌ missing-in-swift | Java Bytes.readShort(raw,16) -> uint16@16-17 (glucose value in mg/dL per javadoc). Python struct.unpack_from(UINT16, raw, 14) -> uint16@14-15. [PY-DIVERGENCE] offset differs by 2 bytes (16 vs 14); java's byte range 16-17 actually collides with python's separately-decoded rssi(@16, 1 byte) + algorithmState(@17, 1 byte) fields rather than corresponding to python's currentGlucoseDisplayValue. Swift has no field. |
| timestamp / egvTimeStamp | `timestamp`<br>uint32 @18 | — | `egvTimeStamp`<br>uint32 @18 | ❌ missing-in-swift | Java Bytes.readUint32(raw,18) and Python struct.unpack_from(UINT32, raw, 18) both agree: uint32@18-21 (java/python match). Swift has no field or accessor for this timestamp at all despite it being distinct from the base-record pump timestamp at offset 2. |
| transmitterTimestamp | `transmitterTimestamp`<br>uint32 @22 | — | — | ❌ missing-in-swift-and-python | Java Bytes.readUint32(raw,22) -> uint32@22-25, described via getTransmitterTimestamp(). [PY-DIVERGENCE] Python has no field mapped to this concept; instead python treats byte 22 as unused/unread, decodes `interval` as uint8@23, and `egvInfoBitmaskRaw` as uint16@24-25 -- i.e. Java's single 4-byte transmitterTimestamp concept doesn't exist in python's model of these bytes at all; the byte range is repurposed into two smaller, semantically different fields (interval, egvInfoBitmask) plus one unread byte. Swift has no field either. |
| algorithmState | — | — | `algorithmStateRaw`<br>uint8 @17 | ❌ missing-in-java | [PY-DIVERGENCE] Python-only concept: struct.unpack_from(UINT8, raw, 17) with AlgorithmstateEnum (Warmup=2, OkState=100, RfErrorState=101, SensorSignalLowState=102, TempHighState=103, TempLowState=104, InvalidDataState=105, OtherState=106). Java's parser never treats offset 17 as an independent field -- it is subsumed into Java's 2-byte `value` read at offset 16-17. Also missing-in-swift (no Java or Swift equivalent exists). |
| interval | — | — | `interval`<br>uint8 @23 | ❌ missing-in-java | [PY-DIVERGENCE] Python-only concept: struct.unpack_from(UINT8, raw, 23). Falls inside Java's 4-byte `transmitterTimestamp`@22-25 span, which Java treats as one opaque uint32 rather than decomposing it. Also missing-in-swift. |
| egvInfoBitmask | — | — | `egvInfoBitmaskRaw`<br>uint16 @24 | ❌ missing-in-java | [PY-DIVERGENCE] Python-only concept: struct.unpack_from(UINT16, raw, 24) with EgvinfobitmaskBitmask (11 flag bits 0-10: FiveMinuteReadingFmr, Backfill, ImmediateMatchValue, CrrEgvIsResultOfCalibration, NoEgvMessage, ValidTimestamp, ValidEgvValidRange, ValidAlgstateAlgstateIs100, EgvWasSuccessfullyAddedToCgmSubsystemArrayE, OmrReadingType, RealTimeReadingFromNfcScan) and EgvinfobitmaskMap. Falls inside Java's `transmitterTimestamp`@22-25 span (the trailing 2 bytes), which Java treats as opaque uint32. Also missing-in-swift. |

**Enum / value-map findings:**

- ⚠️ `glucoseValueStatus (status)` — *missing-in-java*: Java's `status` field (uint16@10) has no enum/value comments at all — plain int getter. Python defines GlucosevaluestatusEnum {PreciseValue=0, SpecialHigh=1, SpecialLow=2} plus GlucosevaluestatusMap for a semantically-similar uint8@13 field. Swift has no field and no enum. Also missing-in-swift.
- ⚠️ `cgmDataType (type)` — *missing-in-java*: Java's `type` (uint8@12, matches Python's cgmDataType uint8@12 offset/width) has no enum. Python defines CgmdatatypeBitmask (FiveMinuteReadingFmr=2^0, Backfill=2^1, NoneVal=2^4, OneMinuteReadingOmr=2^5, RealTimeReading=2^6) and a separate CgmdatatypeMap keyed 0/1/4/5/6 (literal values, not bit-shifted) — note the Map keys (0,1,4,5,6) don't match the IntFlag's actual bit values (1,2,16,32,64), a Python-internal inconsistency worth separate scrutiny. Java/Swift have nothing. Also missing-in-swift.
- ⚠️ `algorithmState` — *missing-in-java*: Python-only field (uint8@17) with AlgorithmstateEnum {Warmup=2, OkState=100, RfErrorState=101, SensorSignalLowState=102, TempHighState=103, TempLowState=104, InvalidDataState=105, OtherState=106} and matching AlgorithmstateMap. Java's parser never reads offset 17 as a distinct field (it is folded into Java's 2-byte `value`@16 uint16 read). Also missing-in-swift.
- ⚠️ `egvInfoBitmask` — *missing-in-java*: Python-only field (uint16@24) with EgvinfobitmaskBitmask defining 11 flag bits (FiveMinuteReadingFmr..RealTimeReadingFromNfcScan, bits 0-10) and EgvinfobitmaskMap with matching descriptive text. Java has no field covering offset 24-25 as a distinct concept (it's folded into Java's 4-byte `transmitterTimestamp`@22 uint32). Also missing-in-swift.

**Inconsistencies:**

- [PORT-BUG] Swift's `init(cargo:)` never parses any payload field -- it only calls `super.init(cargo: cargo)`. None of Java's 7 fields (status uint16@10, type uint8@12, rate uint8@13, rssi uint8@15, value uint16@16, timestamp uint32@18, transmitterTimestamp uint32@22) have corresponding stored properties, computed accessors, or getters in the Swift class -- the entire payload of this history log type is unreachable from Swift consumers.
- [PORT-BUG] Swift's `buildCargo(pumpTimeSec:sequenceNum:)` only takes a timestamp and sequence number and produces a cargo whose payload bytes 10-25 are implicitly zero-filled by `HistoryLog.fillCargo` padding, whereas Java's `buildCargo(pumpTimeSec, sequenceNum, status, type, rate, rssi, value, timestamp, transmitterTimestamp)` explicitly serializes all 7 fields via `Bytes.firstTwoBytesLittleEndian`/`Bytes.toUint32`. Any Swift-constructed CgmDataFsl2HistoryLog record for testing/mocking silently loses all CGM payload data.
- [PY-DIVERGENCE] Nearly the entire offset-10-through-17 span is scrambled between Java and Python: java assigns status(uint16)@10, type(uint8)@12, rate(uint8)@13, [pad]@14, rssi(uint8)@15, value(uint16)@16-17; python assigns rate(int16,*0.1)@10, cgmDataType(uint8)@12, glucoseValueStatus(uint8)@13, currentGlucoseDisplayValue(uint16)@14-15, rssi(int8)@16, algorithmState(uint8)@17. Only the `type`/`cgmDataType` field @12 (uint8) lines up exactly between java and python in both offset and width; every other field in that range disagrees on offset, width, or both.
- [PY-DIVERGENCE] Java's `transmitterTimestamp` (uint32@22-25) has no Python counterpart; Python instead decodes that byte range as one unread byte@22, `interval` (uint8@23), and `egvInfoBitmaskRaw` (uint16@24-25). Java's single opaque 4-byte timestamp concept does not exist in Python's model of the record.
- Internal consistency check: Java's own parse()/buildCargo() agree with each other (byte offset 14 is deliberately left unread by parse() and written as a fixed `{0}` by buildCargo(), i.e. intentional reserved padding -- no self-inconsistency). Swift's init(cargo:)/buildCargo() are also mutually consistent with each other, but only for the header fields (typeId/pumpTimeSec/sequenceNum) -- both sides agree in omitting the payload entirely, which is consistent-but-incomplete rather than self-contradictory.

### opCode 390

`CgmStartSensorReqG7HistoryLog` (java) ↔ `CgmStartSensorReqG7HistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 394 — LID_CGM_JOIN_SESSION_G7

`CgmJoinSessionG7HistoryLog` (java) ↔ `CgmJoinSessionG7HistoryLog` (swift) ↔ `LidCgmJoinSessionG7` (py) — severity: **🟡 minor**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| cgmTimestamp | — | — | `cgmTimestamp`<br>uint32 @10 | ❌ missing-in-java | Java parse() only calls parseBase(raw) and never extracts any payload fields; buildCargo() only writes typeId+timestamp+seqNum via HistoryLog.fillCargo, leaving bytes 10-25 as implicit zero-padding with no named field. Swift's init(cargo:) likewise calls only super.init and buildCargo() writes no payload — Swift is a faithful (matching) port of Java's no-op payload handling, so this field is also missing-in-swift. Python's LidCgmJoinSessionG7.build() reads cgmTimestamp = uint32 @ offset 10 ('>I', raw[:26], 10) that has no counterpart in Java or Swift. |
| sessionSignature | — | — | `sessionSignature`<br>uint32 @14 | ❌ missing-in-java | Same situation as cgmTimestamp: Java/Swift never decode any payload field at all for this event (parse() is parseBase-only, buildCargo() writes no payload bytes) — also missing-in-swift. Python decodes sessionSignature = uint32 @ offset 14 ('>I', raw[:26], 14), which is absent from both Java and Swift. |

**Inconsistencies:**

- [PY-DIVERGENCE] cgmTimestamp: java has no payload field at all (parse() only calls parseBase(raw); buildCargo() emits only typeId+timestamp+seqNum, 10 bytes total before HistoryLog.fillCargo padding) — py decodes cgmTimestamp as uint32 @ offset 10 that java/swift never expose.
- [PY-DIVERGENCE] sessionSignature: java has no payload field at all (same parse()/buildCargo() as above) — py decodes sessionSignature as uint32 @ offset 14 that java/swift never expose.
- Swift is fully faithful to Java for this event type: init(cargo:) calls only super.init(cargo:) and buildCargo(pumpTimeSec:sequenceNum:) writes only the 2-byte typeId + uint32 timestamp + uint32 sequenceNum, with zero payload fields — identical structure/behavior to Java's parse()/buildCargo(), so there is no Swift porting bug here.
- Internal consistency: Java's parse() (no field extraction) is consistent with its own buildCargo() (no field serialization) — both are payload-blind for this event. Swift's init(cargo:) is likewise consistent with its own buildCargo() for the same reason. Python's build() (parses 2 uint32 fields) is consistent with its own build_from_json() (reads matching 'cgmtimestamp'/'sessionsignature' JSON props) — no internal inconsistency on any single side.

### opCode 395

`CgmPairingCodeG7HistoryLog` (java) ↔ `CgmPairingCodeG7HistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| pairingCode | `pairingCode`<br>string(16) @10 | `pairingCode`<br>string(16, via subdata(10..<26)) @10 | — | ✅ match | java: Bytes.readString(raw, 10, 16) in parse(), Bytes.writeString(pairingCode, 16) in buildCargo() -> offset 10, 16-byte field. swift: init(cargo:) reads cargo.subdata(in: 10..<min(26, cargo.count)) (=16 bytes when cargo.count==26) decoded as ASCII with trailing NUL trimmed; buildCargo() builds a 16-byte zero-padded ASCII buffer placed immediately after the 10-byte header (typeId(2)+timestamp(4)+seq(4)). Offsets and widths agree between java and swift. |

_No inconsistencies found._

### opCode 399

`DexcomG7CGMHistoryLog` (java) ↔ `DexcomG7CGMHistoryLog (Sources/TandemCore/Messages/HistoryLog/DexcomG7CGMHistoryLog.swift)` (swift) ↔ `LidCgmDataG7` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| glucoseValueStatus | `glucoseValueStatusRaw`<br>uint16 (Bytes.readShort) @10 | `glucoseValueStatus`<br>uint16 (Bytes.readShort) @10 | `glucoseValueStatusRaw`<br>uint16 ('>H') @12 | ❌ py-diverges-from-java | glucoseValueStatus: java uint16@10 = swift uint16@10 (Bytes.readShort(cargo,10)); py unpack_from(UINT16, raw, 12) reads uint16@12 — py offset off by +2, decoded value differs. |
| cgmDataType | `cgmDataTypeRaw`<br>uint8 (raw[12]) @12 | `cgmDataType`<br>uint8 (Int(cargo[12])) @12 | `cgmDataTypeRaw`<br>uint8 ('>B') @11 | ❌ py-diverges-from-java | cgmDataType: java uint8@12 = swift uint8@12; py unpack_from(UINT8, raw, 11) reads uint8@11 — py offset off by -1. |
| rate | `rate`<br>int8 (raw[13], Java byte auto-sign-extended into int rate field) @13 | `rate`<br>uint8 (Int(cargo[13]); cargo[13] is Swift UInt8, NOT sign-extended) @13 | `rateRaw`<br>int8 ('>b') # mg/dL/min/10 @10 | ❌ all-three-differ | rate: java signed byte@13 (raw[13] sign-extends since Java byte->int widening is sign-extending) vs swift Int(cargo[13])@13 which does NOT sign-extend (unsigned 0-255) — [PORT-BUG]; py reads signed int8 but at offset 10 instead of 13 — [PY-DIVERGENCE]. All three combinations of offset/signedness differ. |
| algorithmState | `algorithmStateRaw`<br>uint8 (raw[14]) @14 | `algorithmState`<br>uint8 (Int(cargo[14])) @14 | `algorithmStateRaw`<br>uint8 ('>B') @17 | ❌ py-diverges-from-java | algorithmState: java uint8@14 = swift uint8@14; py unpack_from(UINT8, raw, 17) reads uint8@17 — py offset off by +3. |
| rssi | `rssi`<br>int8 (raw[15], Java byte auto-sign-extended into int rssi field; real BLE RSSI is negative dBm) @15 | `rssi`<br>uint8 (Int(cargo[15]); cargo[15] is Swift UInt8, NOT sign-extended) @15 | `rssi`<br>int8 ('>b') @16 | ❌ all-three-differ | rssi: java signed byte@15 (typical dBm values like -60 decode correctly as negative) vs swift Int(cargo[15])@15 which decodes the same raw byte as an unsigned 0-255 value (e.g. -60 dBm's byte 0xC4 becomes 196 instead of -60) — [PORT-BUG], major since real RSSI is routinely negative; py reads signed int8 (matches java's sign semantics) but at offset 16 instead of 15 — [PY-DIVERGENCE]. |
| currentGlucoseDisplayValue | `currentGlucoseDisplayValue`<br>uint16 (Bytes.readShort) @16 | `currentGlucoseDisplayValue`<br>uint16 (Bytes.readShort) @16 | `currentGlucoseDisplayValue`<br>uint16 ('>H') # mg/dL @14 | ❌ py-diverges-from-java | currentGlucoseDisplayValue: java uint16@16 = swift uint16@16; py unpack_from(UINT16, raw, 14) reads uint16@14 — py offset off by -2. |
| egvTimestamp | `egvTimestamp`<br>uint32 (Bytes.readUint32) @18 | `egvTimestamp`<br>uint32 (Bytes.readUint32) @18 | `egvTimeStamp`<br>uint32 ('>I') # sec @18 | ✅ match | egvTimestamp: java uint32@18 = swift uint32@18 = py uint32@18. Only field on which all three parsers fully agree on offset and width. |
| egvInfoBitmask | `egvInfoBitmaskRaw`<br>uint16 (Bytes.readShort) @22 | `egvInfoBitmask`<br>uint16 (Bytes.readShort) @22 | `egvInfoBitmaskRaw`<br>uint16 ('>H') @24 | ❌ py-diverges-from-java | egvInfoBitmask: java uint16@22 = swift uint16@22; py unpack_from(UINT16, raw, 24) reads uint16@24 — py offset off by +2. |
| interval | `interval`<br>uint8 (raw[24]) @24 | `interval`<br>uint8 (Int(cargo[24])) @24 | `interval`<br>uint8 ('>B') @23 | ❌ py-diverges-from-java | interval: java uint8@24 = swift uint8@24; py unpack_from(UINT8, raw, 23) reads uint8@23 — py offset off by -1. Combined with the other py offsets, byte index 22 of the 26-byte record is never consumed by any of Python's 9 fields (a gap), confirming the Python layout for this record is scrambled relative to Java/Swift rather than a simple uniform shift. |

**Enum / value-map findings:**

- ✅ `GlucoseValueStatus value set (java enum vs py Enum)` — *match*: java GlucoseValueStatus{NORMAL=0,HIGH=1,LOW=2,DO_NOT_SHOW=6} == py GlucosevaluestatusEnum{PreciseValue=0,SpecialHigh=1,SpecialLow=2,DoNotShow=6}; same 4 values, labels differ (NORMAL vs PreciseValue etc.) but semantics align.
- ⚠️ `GlucoseValueStatus enum (Swift)` — *missing-in-swift*: Swift only stores raw Int glucoseValueStatus; there is no enum or decoding helper equivalent to Java's GlucoseValueStatus.fromId()/getGlucoseValueStatus().
- ✅ `AlgorithmState value set (java enum vs py Enum)` — *match*: java AlgorithmState{2,30,31,32,33,34,35,36,37,38,39} == py AlgorithmstateEnum with the identical 11 numeric values (Warmup=2 ... value 39); labels are consistently transliterated (e.g. STOPPED_SIV_FAILURE=38 vs SessionStoppedSivFailure=38).
- ⚠️ `AlgorithmState enum (Swift)` — *missing-in-swift*: Swift only stores raw Int algorithmState; no AlgorithmState enum/decoder exists in the Swift file.
- ✅ `CgmDataType bitmask value set` — *match*: java DexcomG6CGMHistoryLog.CgmDataType{FIVE_MINUTE_READING=1,BACKFILL=2,IMMEDIATE_MATCH_VALUE=4,CALIBRATION=8,NONE=16} == py CgmdatatypeBitmask(IntFlag){Fmr=1,Backfill=2,ImmNoLongerApplies=4,Calibration=8,NoneVal=16}. However py's separate CgmdatatypeMap dict is keyed 0..4 (sequential bit-index labels), inconsistent with both the IntFlag class and java's actual bit values — a Python-internal label/doc bug, not a decoding bug.
- ⚠️ `CgmDataType bitmask (Swift)` — *missing-in-swift*: Swift exposes only raw Int cgmDataType; no Set<CgmDataType>/bitmask decoding as provided by java's getCgmDataType().
- ✅ `EgvInfo bitmask value set` — *match*: java DexcomG6CGMHistoryLog.EgvInfo has 9 members with values {1,2,4,8,16,32,64,128,256} == py EgvinfobitmaskBitmask(IntFlag) with the identical 9 values. Py's EgvinfobitmaskMap dict additionally documents 'Reserved' entries at indices 9 and 10 that have no corresponding IntFlag member (doc drift only, minor).
- ⚠️ `EgvInfo bitmask (Swift)` — *missing-in-swift*: Swift exposes only raw Int egvInfoBitmask; no Set<EgvInfo>/bitmask decoding as provided by java's getEgvInfo().

**Inconsistencies:**

- [PORT-BUG] rssi: java raw[15] is a Java byte that auto-sign-extends into the int rssi field (range -128..127, matching real negative dBm RSSI readings), but Swift's `Int(cargo[15])` reads cargo[15] as an unsigned UInt8 and does NOT sign-extend, so Swift decodes the identical byte as 0..255 — e.g. a real -60 dBm reading (byte 0xC4) decodes as -60 in Java but 196 in Swift. This changes the decoded value for the common real-world case and is the highest-severity finding.
- [PORT-BUG] rate: same signedness bug as rssi — java raw[13] sign-extends into int rate (rate is documented as mg/dL/min/10, which can be negative), but Swift's `Int(cargo[13]))` treats it as unsigned 0..255. Numeric impact is smaller than rssi since \|rate\| rarely exceeds 127*0.1 mg/dL/min, but the type is still ported incorrectly.
- [PORT-BUG] DexcomG7CGMHistoryLog.swift has no buildCargo()/serializer and no full-field initializer, unlike Java's buildCargo() and unlike sibling Swift ports such as CgmDataGxHistoryLog.swift (which implements buildCargo(), a full initializer, and a description property). Only init(cargo:) exists, so the Swift type can be deserialized but not constructed/serialized — asymmetric with Java and with the rest of the Swift HistoryLog catalog.
- [PORT-BUG] Swift exposes only raw Int fields for glucoseValueStatus, algorithmState, cgmDataType, and egvInfoBitmask; it ports none of Java's nested enums/Set<> bitmask decoders (GlucoseValueStatus, AlgorithmState, CgmDataType, EgvInfo) or their fromId()/getX() accessors.
- [PY-DIVERGENCE] glucoseValueStatus: java uint16@10 = swift uint16@10 (Bytes.readShort(cargo,10)); py struct.unpack_from(UINT16, raw, 12) reads uint16@12 — offset off by +2.
- [PY-DIVERGENCE] cgmDataType: java uint8@12 = swift uint8@12; py struct.unpack_from(UINT8, raw, 11) reads uint8@11 — offset off by -1.
- [PY-DIVERGENCE] rate: java signed byte@13; py struct.unpack_from(INT8, raw, 10) reads signed int8@10 — offset off by -3 (in addition to Swift's separate signedness bug at the correct offset 13).
- [PY-DIVERGENCE] algorithmState: java uint8@14 = swift uint8@14; py struct.unpack_from(UINT8, raw, 17) reads uint8@17 — offset off by +3.
- [PY-DIVERGENCE] rssi: java signed byte@15; py struct.unpack_from(INT8, raw, 16) reads signed int8@16 — offset off by +1 (py's sign handling correctly matches java here, unlike swift).
- [PY-DIVERGENCE] currentGlucoseDisplayValue: java uint16@16 = swift uint16@16; py struct.unpack_from(UINT16, raw, 14) reads uint16@14 — offset off by -2.
- [PY-DIVERGENCE] egvInfoBitmask: java uint16@22 = swift uint16@22; py struct.unpack_from(UINT16, raw, 24) reads uint16@24 — offset off by +2.
- [PY-DIVERGENCE] interval: java uint8@24 = swift uint8@24; py struct.unpack_from(UINT8, raw, 23) reads uint8@23 — offset off by -1. Net effect: Python's 9 fields collectively skip byte offset 22 of the record entirely and read every field except egvTimestamp at the wrong offset — this is a comprehensively scrambled layout in tconnectsync's LidCgmDataG7.build(), not a simple uniform shift.
- [PY-DIVERGENCE] CgmdatatypeMap (keys '0'..'4' labeled FMR/Backfill/IMM/Calibration/None) is inconsistent with Python's own CgmdatatypeBitmask IntFlag (Fmr=1,Backfill=2,ImmNoLongerApplies=4,Calibration=8,NoneVal=16), which itself matches java's CgmDataType enum values — the Map's keys are sequential bit-index labels rather than actual bitmask values; doc/label-only bug (minor).
- [PY-DIVERGENCE] EgvinfobitmaskMap documents 'Reserved' entries at keys '9' and '10' with no corresponding member in Python's EgvinfobitmaskBitmask IntFlag, which only defines 9 members (bits 0-8) matching java's 9-member EgvInfo enum exactly — doc/map drift only (minor).

### opCode 404 — LID_CGM_START_SESSION_FSL2

`CgmStartSessionFsl2HistoryLog` (java) ↔ `CgmStartSessionFsl2HistoryLog` (swift) ↔ `LidCgmStartSessionFsl2` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| sessionStartTime | — | — | `sessionStartTime`<br>uint32 @10 | ❌ missing-in-java | java: parse() only calls parseBase(raw) (sets this.cargo=raw, reads base timestamp/seq); buildCargo(pumpTimeSec, sequenceNum) only emits opcode(2B)+timestamp(4B)+seq(4B) via HistoryLog.fillCargo — no payload field is ever extracted or written for byte offset 10+. swift init(cargo:) likewise only calls super.init(cargo:) and buildCargo() only writes typeId+pumpTimeSec+sequenceNum, matching java exactly (swift does NOT diverge from java here). python (LidCgmStartSessionFsl2.build) reads sessionStartTime as uint32 at absolute offset 10 from the same 26-byte record — a field java/swift never expose despite decoding the identical record layout. |
| sessionDuration | — | — | `sessionDuration`<br>uint8 @17 | ❌ missing-in-java | python reads sessionDuration ('# days') as uint8 at absolute offset 17. java has no corresponding field (parse()/buildCargo() never touch offset 17). swift matches java exactly — neither exposes any field beyond the 10-byte base header for this event type. |

**Inconsistencies:**

- [PY-DIVERGENCE] sessionStartTime: python uint32@10 (LidCgmStartSessionFsl2.build, struct.unpack_from(UINT32, raw[:26], 10)) is decoded and surfaced in todict()/build_from_json(); java's CgmStartSessionFsl2HistoryLog.parse(raw) only calls parseBase(raw) and never reads offset 10, and buildCargo(pumpTimeSec, sequenceNum) only writes opcode+timestamp+seqNum (10 bytes total before fillCargo padding) — no sessionStartTime field exists on the java side at all, even though the record is a fixed 26 bytes with room for it.
- [PY-DIVERGENCE] sessionDuration: python uint8@17 (days) has no counterpart in java — CgmStartSessionFsl2HistoryLog exposes only the inherited base pumpTimeSec/sequenceNum fields; the class has no additional public accessor or parsed field for a duration value.
- Swift's CgmStartSessionFsl2HistoryLog is a faithful, non-divergent port of java for this event type: init(cargo:) calls super.init(cargo:) only (mirroring parseBase), and buildCargo(pumpTimeSec:sequenceNum:) writes exactly typeId(2B)+pumpTimeSec(4B)+sequenceNum(4B) via HistoryLog.fillCargo, identical in structure to java's buildCargo. No [PORT-BUG] found — java and swift agree completely (both simply don't parse any type-specific payload for opCode 404).

### opCode 405

`CgmStopSessionFsl2HistoryLog` (java) ↔ `CgmStopSessionFsl2HistoryLog` (swift) ↔ `LidCgmStopSessionFsl2` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| sessionStartTime | — | — | `sessionStartTime`<br>uint32 ('>I' at abs offset 10) @10 | ❌ missing-in-java | Java parse() only calls parseBase(raw) and does not decode any payload fields beyond the 10-byte base header (typeId/pumpTimeSec/sequenceNum); buildCargo() likewise only emits typeId+pumpTimeSec+sequenceNum via HistoryLog.fillCargo. Swift init(cargo:)/buildCargo() mirror Java exactly (no extra fields), so Swift is also missing this field — it is not a Swift-specific porting bug, Swift faithfully ports Java's (incomplete) behavior. Only tconnectsync's LidCgmStopSessionFsl2.build() decodes sessionStartTime as uint32 at absolute offset 10. |
| sessionStopTime | — | — | `sessionStopTime`<br>uint32 ('>I' at abs offset 14) @14 | ❌ missing-in-java | Not decoded by Java or Swift (both only produce/parse the 10-byte base record for opCode 405). Python decodes it as uint32@14. Swift's omission matches Java's omission, so this is a reference-level gap rather than a Swift port divergence. |
| sessionStopReason | — | — | `sessionStopReason`<br>uint8 ('>B' at abs offset 20) @20 | ❌ missing-in-java | Not decoded by Java or Swift. Python decodes uint8@20. Note: unlike the sibling event LidCgmStopSessionGx (opCode 214), which defines a SessionstopreasonEnum/SessionstopreasonMap for this field, LidCgmStopSessionFsl2 leaves sessionStopReason as a raw int with no enum/value map — no enum comparison is possible for this event. |
| sessionDuration | — | — | `sessionDuration`<br>uint8 ('>B' at abs offset 21) — comment '# days' @21 | ❌ missing-in-java | Not decoded by Java or Swift. Python decodes uint8@21 (in build(), the unpack_from calls for sessionDuration@21 and sessionStopReason@20 appear in reversed source order relative to the field declaration order, but each is still assigned to the correct variable name — not a bug, just unusual statement ordering). |

**Enum / value-map findings:**

- ⚠️ `sessionStopReason` — *missing-in-java*: No enum/value map exists for sessionStopReason in this event on any side (Java has no field at all; Swift has no field at all; Python leaves it as a bare int with no *Map/Enum, unlike the sibling LidCgmStopSessionGx which defines SessionstopreasonEnum/SessionstopreasonMap for the same concept at a different opCode). No enum comparison is possible for opCode 405.

**Inconsistencies:**

- [PY-DIVERGENCE] tconnectsync's LidCgmStopSessionFsl2 decodes four payload fields (sessionStartTime uint32@10, sessionStopTime uint32@14, sessionStopReason uint8@20, sessionDuration uint8@21) that pumpX2's CgmStopSessionFsl2HistoryLog.parse() never extracts — Java's parse() calls only parseBase(raw) and stores the raw cargo, exposing no typed accessors for these fields, so any Java/Loop consumer of opCode 405 has no way to read session start/stop time, duration, or stop reason even though the underlying bytes are present in the 26-byte record.
- TandemKit's Swift CgmStopSessionFsl2HistoryLog.init(cargo:)/buildCargo() are a faithful 1:1 port of Java's incomplete implementation — both only handle the base typeId/pumpTimeSec/sequenceNum fields and add nothing else. This is NOT a Swift porting bug (Swift correctly mirrors Java's behavior); the gap exists in the reference implementation itself.
- Java's own buildCargo(pumpTimeSec, sequenceNum) and Swift's buildCargo(pumpTimeSec:sequenceNum:) are internally self-consistent with their own parsers on both sides (no fields are serialized that parse() doesn't also skip), so there is no internal Java-vs-Java or Swift-vs-Swift disagreement — the only disagreement is Java/Swift (no payload fields) vs Python (4 payload fields).

### opCode 406

`CgmJoinSessionFsl2HistoryLog` (java) ↔ `CgmJoinSessionFsl2HistoryLog` (swift) ↔ `LidCgmJoinSessionFsl2` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| sessionStartTime | — | — | `sessionStartTime`<br>uint32 @10 | ❌ py-diverges-from-java | [PY-DIVERGENCE] Java's parse() only calls parseBase(raw) and defines no payload fields at all (buildCargo(pumpTimeSec,sequenceNum) also takes no extra payload args) — Java treats this event as header-only. Swift's init(cargo:) likewise defines no payload fields and buildCargo(pumpTimeSec:sequenceNum:) matches Java's signature, so Swift faithfully mirrors Java's (incomplete) stub. Python's LidCgmJoinSessionFsl2.build() independently decodes sessionStartTime as uint32 at absolute offset 10 ('>I', unpack_from(..., 10)) — a real field entirely absent from both Java and Swift. |
| sessionJoinTime | — | — | `sessionJoinTime`<br>uint32 @14 | ❌ py-diverges-from-java | [PY-DIVERGENCE] Same as sessionStartTime: Java and Swift parse no payload fields for this event. Python decodes sessionJoinTime as uint32 at absolute offset 14 ('>I', unpack_from(..., 14)). |
| sessionJoinReason | — | — | `sessionJoinReason`<br>uint8 @20 | ❌ py-diverges-from-java | [PY-DIVERGENCE] Java and Swift parse no payload fields. Python decodes sessionJoinReason as uint8 at absolute offset 20 ('>B', unpack_from(..., 20)) — note Python's build() reads this field (offset 20) using the variable name paired with the *lower* offset, i.e. sessionJoinReason(20) precedes sessionDuration(21) in memory layout despite being assigned after it in code; this is just Python's own field ordering, not a cross-language inconsistency. |
| sessionDuration | — | — | `sessionDuration`<br>uint8 @21 | ❌ py-diverges-from-java | [PY-DIVERGENCE] Java and Swift parse no payload fields. Python decodes sessionDuration (comment: 'days') as uint8 at absolute offset 21 ('>B', unpack_from(..., 21)). |

**Inconsistencies:**

- Java's CgmJoinSessionFsl2HistoryLog.parse() (lines 25-30) only calls Validate.isTrue(raw.length==26) and parseBase(raw); it extracts zero payload fields beyond the shared 10-byte header (typeId/timestamp/sequenceNum). Its buildCargo(pumpTimeSec, sequenceNum) (lines 32-37) likewise takes no payload arguments and just concatenates the 2-byte opCode with the 4-byte time and 4-byte sequence number, then calls HistoryLog.fillCargo to pad to 26 bytes with zeros. Internally this is self-consistent (parser and serializer agree there is no payload), but functionally this class discards/never decodes any of the real CGM-join-session data present in the 26-byte record.
- Swift's CgmJoinSessionFsl2HistoryLog (init(cargo:) and buildCargo(pumpTimeSec:sequenceNum:)) is a faithful line-for-line port of Java's stub behavior: no payload fields are parsed or serialized beyond the base header. There is NO port-bug here — Swift matches Java's (incomplete) behavior exactly.
- [PY-DIVERGENCE] tconnectsync's LidCgmJoinSessionFsl2.build() (events.py lines 5506-5519) decodes four real payload fields that Java/Swift completely ignore: sessionStartTime (uint32@10), sessionJoinTime (uint32@14), sessionJoinReason (uint8@20), and sessionDuration (uint8@21, described in a comment as 'days'). Since Java is the reference and defines zero payload fields for opCode 406, this represents an entire independently-reverse-engineered payload structure that exists only on the Python side; the pumpX2/TandemKit implementations for LID_CGM_JOIN_SESSION_FSL2 are effectively non-functional beyond capturing the timestamp and sequence number.
- No enum/value-map divergence to report: Java and Swift define no enums for this event (no fields to enumerate), and Python's sessionJoinReason field has no accompanying *Map dict in the class, so no value-set comparison is possible.

### opCode 419 — LID_TIPS_ERROR

`TipsErrorHistoryLog` (java) ↔ `TipsErrorHistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| messageType | `messageType`<br>uint8 @10 | `messageType`<br>uint8 @10 | — | ✅ match | java raw[10] & 0xFF == swift cargo[10]; both stored as int/Int |
| requestCode | `requestCode`<br>uint8 @11 | `requestCode`<br>uint8 @11 | — | ✅ match | java raw[11] & 0xFF == swift cargo[11] |
| errorCode | `errorCode`<br>uint8 @12 | `errorCode`<br>uint8 @12 | — | ✅ match | java raw[12] & 0xFF == swift cargo[12] |
| isDataMasked | `isDataMasked`<br>uint8(bool) @13 | `isDataMasked`<br>uint8(bool) @13 | — | ✅ match | java raw[13] != 0 == swift cargo[13] != 0; both serializers write 1/0 byte identically |

_No inconsistencies found._

### opCode 438 — LID_CGM_CAL_G7

`CgmCalibrationG7HistoryLog` (java) ↔ `CgmCalibrationG7HistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| bg | `bg`<br>uint32 @10 | `bg`<br>uint32 @10 | — | ✅ match | java: Bytes.readUint32(raw, 10) into long bg; swift: Bytes.readUint32(cargo, 10) into UInt32 bg. Both buildCargo()/serializer write the same value at the same offset via Bytes.toUint32. No Python parser exists for opCode 438. |

_No inconsistencies found._

### opCode 439

`CgmBleCalibrationEvtG7HistoryLog` (java) ↔ `CgmBleCalibrationEvtG7HistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| isCalibrationAccepted | `isCalibrationAccepted`<br>uint8 (bool via raw[10] != 0) @10 | `isCalibrationAccepted`<br>uint8 (bool via cargo[10] != 0) @10 | — | ✅ match | isCalibrationAccepted: java raw[10]!=0 @10 = swift cargo[10]!=0 @10. Both build a single trailing byte (1/0) in buildCargo at the same position. No Python parser exists for opCode 439. |

_No inconsistencies found._

### opCode 441

`CgmInactiveG7HistoryLog` (java) ↔ `CgmInactiveG7HistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

**Inconsistencies:**

- No payload fields beyond the shared 10-byte header (opCode@0-1 uint16, pumpTimeSec@2-5 uint32, sequenceNum@6-9 uint32) are defined by either Java or Swift for event 441 — both parse()/init(cargo:) simply call parseBase(raw)/super.init(cargo:) with no additional field extraction, and both buildCargo() implementations only emit the 10-byte header before HistoryLog.fillCargo() pads to 26 bytes with zeros.
- Java buildCargo() and Swift buildCargo() are structurally identical: same 2-byte little-endian opCode (441 = 0x01B9, low byte then high byte), same toUint32(pumpTimeSec), same toUint32(sequenceNum), same reliance on fillCargo for zero-padding to 26 bytes.
- Python (tconnectsync) has no parser class for opCode 441 at all, so pyClass is empty and no py-side fields are reported per instructions; this absence is not counted as an inconsistency.

### opCode 443

`CgmStopSessionReqG7HistoryLog` (java) ↔ `CgmStopSessionReqG7HistoryLog` (swift) — *no Python parser* — severity: **🟢 none**

_No inconsistencies found._

### opCode 447

`CgmStopSessionG7HistoryLog` (java) ↔ `CgmStopSessionG7HistoryLog` (swift) ↔ `LidCgmStopSessionG7` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| currentTransmitterTime | — | — | `currentTransmitterTime`<br>uint32 (>I) @10 | ❌ missing-in-java | Java parse() never reads a field at offset 10 (only parseBase covers 0-9); Swift init(cargo:) likewise reads no payload fields, matching Java exactly. Only tconnectsync decodes this: sessionStartTime-adjacent transmitter time, uint32@10. |
| sessionStartTime | — | — | `sessionStartTime`<br>uint32 (>I) @14 | ❌ missing-in-java | Absent from both Java parse()/buildCargo() and Swift init(cargo:)/buildCargo(); Python reads uint32@14 (sec). |
| sessionStopTime | — | — | `sessionStopTime`<br>uint32 (>I) @18 | ❌ missing-in-java | Absent from both Java and Swift; Python reads uint32@18 (sec). |
| stopSessionCode | — | — | `stopSessionCode`<br>uint8 (>B) @23 | ❌ missing-in-java | Absent from both Java and Swift; Python reads uint8@23. |
| sessionStopReason | — | — | `sessionStopReason`<br>uint8 (>B) @24 | ❌ missing-in-java | Absent from both Java and Swift; Python reads uint8@24. |
| sessionDuration | — | — | `sessionDuration`<br>uint8 (>B), unit 'days' per Python comment @25 | ❌ missing-in-java | Absent from both Java and Swift; Python reads uint8@25. This is the last byte of the 26-byte record. |

**Inconsistencies:**

- [PY-DIVERGENCE] Java's CgmStopSessionG7HistoryLog.parse(byte[] raw) only calls parseBase(raw) (base timestamp/seqNum @2-9) and stores the full 26-byte raw array as cargo, but exposes zero payload getters/fields for opCode 447 -- the transmitter/session-stop data occupying bytes 10-25 is left completely undecoded by the reference implementation. tconnectsync's LidCgmStopSessionG7.build() independently derived 6 payload fields from the same 26-byte record: currentTransmitterTime uint32@10, sessionStartTime uint32@14, sessionStopTime uint32@18, stopSessionCode uint8@23, sessionStopReason uint8@24, sessionDuration uint8@25 (days). This is a substantive interpretation gap between the two independent codebases for the same wire record, not merely an endianness or naming difference.
- Swift's CgmStopSessionG7HistoryLog is a faithful, bug-free port of Java: init(cargo:) calls super.init(cargo:) with no additional field extraction, and buildCargo(pumpTimeSec:sequenceNum:) writes only the 2-byte opcode + 4-byte timestamp + 4-byte seqNum before HistoryLog.fillCargo() zero-pads to 26 bytes -- identical in structure and behavior to Java's buildCargo(). This is NOT a [PORT-BUG]; Swift correctly mirrors Java's (incomplete) implementation.
- Both Java and Swift buildCargo()/serializer implementations are internally self-consistent with their own parse()/init(cargo:) (neither writes nor reads any payload field), so there is no intra-language round-trip inconsistency on either the Java or Swift side -- the gap is purely that neither decodes the 6 fields Python has proven exist in the record.

### opCode 460

`CgmAlertActivatedFsl2HistoryLog` (java) ↔ `CgmAlertActivatedFsl2HistoryLog (Sources/TandemCore/Messages/HistoryLog/CgmAlertActivatedFsl2HistoryLog.swift)` (swift) ↔ `LidCgmAlertActivatedFsl2` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alertId / dalertId | `alertId`<br>uint32 @10 | `alertId`<br>uint32 @10 | `dalertIdRaw`<br>uint8 @13 | ❌ py-diverges-from-java | java: Bytes.readUint32(raw,10) covers bytes 10-13, resolved via CGMAlertStatusResponse.CGMAlert.fromId(). swift: Bytes.readUint32(cargo,10), byte-identical to java (matches). python: dalertIdRaw is only 1 byte at absolute offset 13 (struct.unpack_from(UINT8, raw, 13)), decoded via DalertidEnum (values 1,2,3,8,11,12,13,14,20,22,25,26,27,39,40,45,46,48). Java/swift's 4-byte field at 10-13 subsumes python's separate 1-byte sensorType@12 and dalertId@13 fields plus 2 unaccounted bytes at 10-11, so the same raw bytes decode to different numeric values across implementations. |
| sensorType | — | — | `sensorTypeRaw`<br>uint8 @12 | ❌ missing-in-java | python-only field: sensorTypeRaw uint8@12, decoded via SensortypeEnum (0=Invalid, 2=CgmTypeLibre2). Absent from BOTH java and swift (not just java) — java/swift never parse a byte at offset 12 independently; it is silently folded into java/swift's 4-byte alertId@10 read. |
| faultLocatorData | — | — | `faultLocatorData`<br>uint32 @14 | ❌ missing-in-java | python-only field, uint32@14. Absent from both java and swift; java's parse()/init(cargo:) never reads past offset 13 for this record type, leaving bytes 14-17 entirely unparsed on the reference and swift sides. |
| param1 | — | — | `param1`<br>uint32 @18 | ❌ missing-in-java | python-only field, uint32@18. Absent from both java and swift; bytes 18-21 unparsed on java/swift side. |
| param2 | — | — | `param2`<br>float32 @22 | ❌ missing-in-java | python-only field, float32@22. Absent from both java and swift; bytes 22-25 unparsed on java/swift side. |
| decoded CGMAlert enum accessor | `alert (getAlert())`<br>enum lookup: CGMAlertStatusResponse.CGMAlert.fromId((int)alertId) @10 | — | `dalertId (property)`<br>DalertidEnum(dalertIdRaw) @13 | ❌ missing-in-swift | java stores/exposes a decoded `alert: CGMAlertStatusResponse.CGMAlert` field via `CGMAlertStatusResponse.CGMAlert.fromId((int) alertId)` and `getAlert()`. python similarly exposes a `dalertId` property via `DalertidEnum(self.dalertIdRaw)`. swift's CgmAlertActivatedFsl2HistoryLog exposes only the raw `alertId: UInt32` with no enum decode step at all, even though an equivalent enum (CGMAlertStatusResponse.CGMAlert in Sources/TandemCore/Messages/CurrentStatus/CGMAlertStatus.swift) exists in the codebase — it just isn't wired up here, and that Swift enum only provides `fromBitmask`, not a `fromId`-style single-value lookup like java's. |

**Enum / value-map findings:**

- ⚠️ `alertId enum coverage` — *missing-in-swift*: Java resolves alertId to CGMAlertStatusResponse.CGMAlert.fromId(...) (enum defined in a file not included in this audit scope, CGMAlertStatusResponse.java). Python's DalertidEnum/DalertidMap in tconnectsync explicitly enumerates 18 named values: 1=CgmFixedLow, 2=CgmHigh, 3=CgmLow, 8=CgmRapidFall, 11=CgmSensorFail, 12=CgmSensorExpiringSoon, 13=CgmSensorExpired, 14=CgmOutOfRange, 20=CgmTransmitterError, 22=CgmSensorExpiring2, 25=CgmReplaceSensor, 26=CgmTemperature, 27=CgmFailedConnection, 39=CgmTransmitterExpired, 40=PumpBluetoothError, 45=CgmTransmitterExpiringSoon, 46=CgmTransmitterExpiring2, 48=CgmUnavailable. Swift's own CGMAlertStatusResponse.CGMAlert enum (used elsewhere for the CGM alert bitmask response, opcode 75) contains matching rawValues (FIXED_LOW_CGM_ALERT=1, HIGH_CGM_ALERT=2, LOW_CGM_ALERT=3, RAPID_FALL_CGM_ALERT=8, SENSOR_FAILED_CGM_ALERT=11, SENSOR_EXPIRING_CGM_ALERT=12, SENSOR_EXPIRED_CGM_ALERT=13, OUT_OF_RANGE_CGM_ALERT=14, TRANSMITTER_CGM_ALERT=20, SENSOR_EXPIRING_CGM_ALERT2=22, SENSOR_REUSE=25, TEMPERATURE_CGM_ALERT=26, FAILED_CONNECTION_CGM_ALERT=27, TRANSMITTER_EXPIRED_CGM_ALERT=39, PUMP_BLUETOOTH_ERROR_CGM_ALERT=40, DEFAULT_CGM_ALERT_45=45, DEFAULT_CGM_ALERT_46=46, DEFAULT_CGM_ALERT_48=48), so the value sets line up with python's map, but this enum is never invoked from CgmAlertActivatedFsl2HistoryLog.swift, so the history-log parser itself performs no enum decoding.
- ⚠️ `sensorType enum` — *missing-in-swift*: Python's SensortypeEnum/SensortypeMap (0=Invalid, 2=CgmTypeLibre2) has no counterpart in java or swift since neither parses a sensorType field for this record at all.

**Inconsistencies:**

- [PY-DIVERGENCE] alertId/dalertId: java reads a single uint32 at offset 10 (bytes 10-13, LE) as alertId and resolves it via CGMAlertStatusResponse.CGMAlert.fromId(); swift matches java exactly (uint32@10, byte-identical port). tconnectsync's LidCgmAlertActivatedFsl2 instead reads a 1-byte sensorTypeRaw@12 and a separate 1-byte dalertIdRaw@13, plus uint32 faultLocatorData@14, uint32 param1@18, and float32 param2@22 — a completely different decomposition of bytes 12-25 versus java/swift's single 4-byte field spanning 10-13. The same raw bytes decode to materially different values/fields across java+swift vs python for this event type.
- [PY-DIVERGENCE] sensorType (uint8@12), faultLocatorData (uint32@14), param1 (uint32@18), and param2 (float32@22) are present only in tconnectsync's LidCgmAlertActivatedFsl2; they are entirely absent from both pumpX2 (Java, the reference) and TandemKit (Swift), which stop parsing this 26-byte record after the single 4-byte alertId field at offset 10 and never touch bytes 14-25.
- [PORT-BUG] Swift's CgmAlertActivatedFsl2HistoryLog only stores the raw `alertId: UInt32` and never resolves it to a decoded alert enum, whereas Java's class additionally stores `alert: CGMAlertStatusResponse.CGMAlert` via `CGMAlertStatusResponse.CGMAlert.fromId((int) alertId)` and exposes `getAlert()`. TandemKit does have an equivalent `CGMAlertStatusResponse.CGMAlert` enum (Sources/TandemCore/Messages/CurrentStatus/CGMAlertStatus.swift) but it is not used here, and that Swift enum exposes only `fromBitmask(_:)`, not a `fromId`/lookup-by-single-value counterpart to Java's `fromId`. Net effect: swift callers of this history log entry lose the semantic alert-name decoding that java provides for the same raw bytes.
- [PORT-BUG] Java exposes a static `buildCargo(pumpTimeSec, sequenceNum, alertId)` serializer plus public constructors that use it, allowing this history-log entry type to be synthesized/round-tripped (e.g. for tests). TandemKit's Swift port has no buildCargo()/serializer counterpart for CgmAlertActivatedFsl2HistoryLog — in fact no HistoryLog subclass in Sources/TandemCore/Messages/HistoryLog defines a buildCargo() at all — so there is no way to construct a synthetic record and no internal-consistency check possible between a swift parser and swift serializer for this type.

### opCode 461 — LID_CGM_ALERT_CLEARED_FSL2

`CgmAlertClearedFsl2HistoryLog (historyLog)` (java) ↔ `CgmAlertClearedFsl2HistoryLog.swift (Sources/TandemCore/Messages/HistoryLog)` (swift) ↔ `LidCgmAlertClearedFsl2` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| alertId | `alertId`<br>uint32 @10 | `alertId`<br>uint32 @10 | `dalertIdRaw (dalertId)`<br>uint8 @13 | ❌ py-diverges-from-java | java: `this.alertId = Bytes.readUint32(raw, 10);` — a single 4-byte little-endian value covering absolute bytes 10-13, exposed via getAlertId()/enum lookup CGMAlertStatusResponse.CGMAlert.fromId((int) alertId). swift: `alertId = Bytes.readUint32(cargo, 10)` matches Java exactly (offset 10, width 4, uint32) — no swift-side divergence for this field. python: `dalertId, = struct.unpack_from(UINT8, raw[:EVENT_LEN], 13)` reads only 1 byte at absolute offset 13 (the last byte of the 4-byte region Java/Swift treat as one field) and treats it as its own semantic concept (`dalertId`), separate from a second concept `sensorType` @12. [PY-DIVERGENCE] alertId: java uint32@10 (bytes 10-13) = swift uint32@10; python decomposes the same 4-byte region into two independent 1-byte fields (sensorType@12, dalertId@13) instead of one 32-bit value, and ignores bytes 10-11 entirely — this is a structural field-layout difference beyond the expected LE/BE endianness swap noted in the task background, since a pure endianness difference would still read one 4-byte field at offset 10, not two 1-byte fields at 12/13. |
| sensorType | — | — | `sensorTypeRaw (sensorType)`<br>uint8 @12 | ❌ missing-in-swift | python: `sensorType, = struct.unpack_from(UINT8, raw[:EVENT_LEN], 12)`, decoded via SensortypeEnum (Invalid=0, CgmTypeLibre2=2) / SensortypeMap. This field/concept does not exist anywhere in the Java or Swift parsers for opCode 461 — java's single Bytes.readUint32(raw,10) silently absorbs this byte as part of the composite 32-bit alertId value instead of exposing it as its own field. [PY-DIVERGENCE] sensorType@12 is a python-only concept absent from both java and swift (swift inherits the gap from java, so this is not itself a swift porting bug, but it is a missing-in-java-and-swift field vs. the python reference). |
| alertId enum/label mapping | `alert (CGMAlertStatusResponse.CGMAlert)`<br>enum(uint32 backing) @10 | UInt32 (no enum) | `dalertId (DalertidEnum)`<br>enum(uint8 backing) @13 | ❌ missing-in-swift | java: `this.alert = CGMAlertStatusResponse.CGMAlert.fromId((int) alertId);` in both parse() and the (long,long,CGMAlertStatusResponse.CGMAlert) constructor, exposed via getAlert(). swift: `CgmAlertClearedFsl2HistoryLog` only exposes the raw `alertId: UInt32` — there is no analogous nested enum or `.fromId`-style lookup exposing a typed/labeled alert value the way Java does. [PORT-BUG] Swift drops Java's CGMAlertStatusResponse.CGMAlert enum lookup entirely, exposing only the raw UInt32 with no semantic label — a caller of the Swift API cannot get the decoded alert name the way Java callers can via getAlert(). |
| buildCargo()/outgoing serializer | `buildCargo(pumpTimeSec, sequenceNum, alertId)`<br>static byte[] builder — writes uint32 pumpTimeSec@2, uint32 sequenceNum@6, uint32 alertId@10 @10 | — | — | ❌ missing-in-swift | java: `CgmAlertClearedFsl2HistoryLog.buildCargo(long,long,long)` is a static serializer used by the constructors and matches parse() byte-for-byte (opcode 461 @0-1, pumpTimeSec uint32@2, sequenceNum uint32@6, alertId uint32@10). swift: `CgmAlertClearedFsl2HistoryLog` defines only `init(cargo:)` (parse path) — there is no buildCargo()/encoder counterpart at all, inherited from the base `HistoryLog` class which likewise has no serializer (only `fillCargo` for padding an already-received cargo). This is a structural gap versus Java rather than a decoding bug (history logs are pump→app only in practice), so it does not corrupt any decoded value, but it means Swift cannot construct a round-trip-verifiable fixture the way Java's own buildCargo/parse self-consistency check can. |

**Enum / value-map findings:**

- ⚠️ `alertId / dalertId (CGM alert identifier)` — *values-differ*: java: uint32 @10 (Bytes.readUint32(raw,10), spans bytes 10-13), looked up via CGMAlertStatusResponse.CGMAlert.fromId((int) alertId) — enum member list not present in this checkout so exact id set could not be cross-checked. swift: identical uint32 @10 read via Bytes.readUint32(cargo,10), stored as raw UInt32 with NO enum/label lookup (Java's CGMAlert.fromId equivalent is absent). python: dalertIdRaw is only a single uint8 @13 ('>B' at absolute offset 13), decoded through DalertidEnum/DalertidMap with 18 named values (CgmFixedLow=1, CgmHigh=2, CgmLow=3, CgmRapidFall=8, CgmSensorFail=11, CgmSensorExpiringSoon=12, CgmSensorExpired=13, CgmOutOfRange=14, CgmTransmitterError=20, CgmSensorExpiring2=22, CgmReplaceSensor=25, CgmTemperature=26, CgmFailedConnection=27, CgmTransmitterExpired=39, PumpBluetoothError=40, CgmTransmitterExpiringSoon=45, CgmTransmitterExpiring2=46, CgmUnavailable=48).
- ⚠️ `sensorType (Python-only: 0=Invalid, 2=CGM_TYPE_LIBRE2)` — *missing-in-swift*: python: SensortypeEnum/SensortypeMap decode a uint8 @12 ('>B' at absolute offset 12) with values Invalid=0, CgmTypeLibre2=2. Java and Swift never surface a distinct sensorType field for opCode 461 at all — the byte at offset 12 is silently folded into Java/Swift's single 4-byte alertId uint32 read.

**Inconsistencies:**

- [PY-DIVERGENCE] alertId: java reads a single little-endian uint32 at absolute offset 10 (bytes 10-13) = swift uint32@10 (exact match). python instead reads two separate big-endian uint8 fields at offsets 12 (sensorType) and 13 (dalertId), leaving bytes 10-11 unused/undocumented — this is a genuine structural field-layout split, not merely the expected LE/BE endianness difference, since a pure endian swap would still be one 4-byte field at offset 10.
- [PY-DIVERGENCE] sensorType@12 (uint8, values Invalid=0 / CgmTypeLibre2=2) is a concept that exists only in the python parser; java and swift never expose this byte as its own field for opCode 461 — java's uint32 read at offset 10 silently absorbs it as part of a composite 32-bit value.
- [PORT-BUG] Swift's CgmAlertClearedFsl2HistoryLog exposes only the raw `alertId: UInt32` with no equivalent to Java's `CGMAlertStatusResponse.CGMAlert.fromId((int) alertId)` enum lookup (Java's `alert`/`getAlert()`), so Swift callers lose the labeled/typed alert value that Java provides from the same bytes.
- Swift has no buildCargo()/serializer equivalent to Java's static `buildCargo(pumpTimeSec, sequenceNum, alertId)` — only the parse path (`init(cargo:)`) exists, inherited from a base `HistoryLog` class that likewise has no encoder. This is a structural gap (not a decode-value bug, since history logs are receive-only in practice) but is worth flagging per the internal-consistency check.

### opCode 477

`CgmJoinSessionFsl3HistoryLog` (java) ↔ `CgmJoinSessionFsl3HistoryLog` (swift) ↔ `LidCgmJoinSessionFsl3` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| sessionStartTime | — | — | `sessionStartTime`<br>uint32 @10 | ❌ missing-in-java | Java parse() only calls parseBase(raw) (base header: typeId 0-1, pumpTimeSec 2-5, seqNum 6-9) — no payload fields are extracted at all; buildCargo() likewise only writes the 10-byte header + zero-padding via HistoryLog.fillCargo, with no sessionStartTime field. Swift init(cargo:) mirrors this exactly (super.init(cargo:) only, no field decode) and Swift buildCargo() also only writes typeId+pumpTimeSec+sequenceNum — so Swift correctly matches Java's stub (no port bug here). Python's build() decodes sessionStartTime as uint32 at absolute offset 10 (struct.unpack_from('>I', raw[:26], 10)). [PY-DIVERGENCE] tconnectsync decodes a real payload field (session start time, seconds) that both pumpX2 (reference) and TandemKit leave completely unparsed for this history-log type, even though the 26-byte record presumably carries this data on the wire. |
| sessionJoinTime | — | — | `sessionJoinTime`<br>uint32 @14 | ❌ missing-in-java | Same as sessionStartTime: absent from both Java parse()/buildCargo() and the matching Swift init(cargo:)/buildCargo() (both are pure 10-byte-header stubs). Python decodes sessionJoinTime as uint32@14 ('>I', offset 14). [PY-DIVERGENCE] Python captures a field neither reference implementation exposes for this event. |
| sessionDuration | — | — | `sessionDuration`<br>uint8 @18 | ❌ missing-in-java | Absent from Java and Swift (both stubs, see above). Python decodes sessionDuration as uint8@18 ('>B', offset 18), documented in tconnectsync as 'Days'. [PY-DIVERGENCE] again a payload field python exposes that neither Java nor Swift decode. |
| sessionJoinReason | — | — | `sessionJoinReason`<br>uint8 @19 | ❌ missing-in-java | Absent from Java and Swift (both stubs, see above). Python decodes sessionJoinReason as uint8@19 ('>B', offset 19), with no accompanying value map (no *Map dict defined for it in the excerpt read). [PY-DIVERGENCE] payload field decoded only on the Python side; no enum/value-map cross-check possible since Java/Swift never expose the field. |

**Inconsistencies:**

- Java CgmJoinSessionFsl3HistoryLog is a complete parsing stub: parse() calls only parseBase(raw) and buildCargo(pumpTimeSec, sequenceNum) only emits the 10-byte header (typeId+pumpTimeSec+sequenceNum) padded to 26 bytes via HistoryLog.fillCargo — no payload fields for bytes 10-25 are read or written, despite the @HistoryLogProps class existing specifically for opCode 477.
- Swift CgmJoinSessionFsl3HistoryLog faithfully mirrors the Java stub: init(cargo:) only calls super.init(cargo:) and buildCargo(pumpTimeSec:sequenceNum:) only writes typeId+pumpTimeSec+sequenceNum. This is an accurate 1:1 port of Java's current (incomplete) behavior, so it is NOT a port bug — Swift is internally consistent with Java at its present level of implementation.
- [PY-DIVERGENCE] tconnectsync's LidCgmJoinSessionFsl3.build() decodes four payload fields that pumpX2 (reference) and TandemKit do not decode at all: sessionStartTime uint32@10, sessionJoinTime uint32@14, sessionDuration uint8@18 ('Days'), sessionJoinReason uint8@19. Since Java is the reference baseline and provides zero payload parsing for this event, there is no offset/type conflict to compare against — this is a completeness gap (feature present only in Python) rather than a value-mismatch bug, but it means Java/TandemKit currently discard clinically relevant CGM-session-join details (start time, join time, duration, join reason) that the pump apparently transmits and that tconnectsync's cloud-derived model can decode.
- No enum/value-map for sessionJoinReason could be cross-checked because Java and Swift never surface the field, and the read Python excerpt for this class does not include a companion *Map dict for sessionJoinReason values.

### opCode 480

`CgmDataFsl3HistoryLog` (java) ↔ `CgmDataFsl3HistoryLog` (swift) ↔ `LidCgmDataFsl3` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| status | `status`<br>uint16 @10 | — | `glucoseValueStatusRaw`<br>uint8 @13 | ❌ all-three-differ | java status=uint16@10 (raw, no scaling); python's closest semantic match glucoseValueStatusRaw is uint8@13 (1 byte, enum 0/1/2 Precise/SpecialHigh/SpecialLow); swift has no field at all. Offset AND width both diverge between java and python, and the field is entirely absent from swift. |
| type/cgmDataType | `type`<br>uint8 @12 | — | `cgmDataTypeRaw`<br>uint8 @12 | ❌ missing-in-swift | java type=raw[12] uint8; python cgmDataTypeRaw=unpack_from(UINT8,12) uint8 -- offset/width match (name differs, not an inconsistency). swift has no corresponding field; only base timestamp/seqNum are exposed. |
| rate | `rate`<br>uint8 @13 | — | `rateRaw`<br>int16 @10 | ❌ all-three-differ | java rate=raw[13] uint8, unscaled, no unit comment. python rateRaw=unpack_from(INT16,10) signed 16-bit at a completely different offset, then exposed via rate property as rateRaw*0.1 mg/dL/min. Offset (13 vs 10), width (1 byte vs 2 bytes) and signedness (unsigned vs signed) all diverge. Swift parses no rate field whatsoever. |
| rssi | `rssi`<br>uint8 @15 | — | `rssi`<br>int8 @16 | ❌ all-three-differ | java rssi=raw[15] uint8 (unsigned byte, no sign conversion despite rssi in dBm typically being negative). python rssi=unpack_from(INT8,16) signed 8-bit one byte further along (offset 16 not 15). Offset shifted by 1 byte and signedness differs. Swift has no rssi field. |
| value (glucose display value, mg/dL) | `value`<br>uint16 @16 | — | `currentGlucoseDisplayValue`<br>uint16 @14 | ❌ py-diverges-from-java | [PY-DIVERGENCE] java value=Bytes.readShort(raw,16) uint16 (glucose mg/dL); python currentGlucoseDisplayValue=unpack_from(UINT16,14) uint16 -- same width, offset shifted 2 bytes earlier (14 vs 16) versus java's layout. Swift has no value/glucose field parsed at all. |
| timestamp/egvTimeStamp | `timestamp`<br>uint32 @18 | — | `egvTimeStamp`<br>uint32 @18 | ❌ missing-in-swift | java timestamp=Bytes.readUint32(raw,18) uint32; python egvTimeStamp=unpack_from(UINT32,18) uint32 -- offset and width match exactly. Swift never parses this field (only inherited base pump-record timestamp from HistoryLog superclass, bytes 2-5, is available). |
| transmitterTimestamp | `transmitterTimestamp`<br>uint32 @22 | — | @-1 | ❌ missing-in-python | [PY-DIVERGENCE] java transmitterTimestamp=Bytes.readUint32(raw,22) uint32 (4 bytes, 22-25). Python has no 4-byte field spanning 22-25; instead it independently defines interval (uint8@23) and egvInfoBitmask (uint16@24-25), leaving byte 22 unused/unread. Swift also has no transmitterTimestamp field. |
| algorithmState (Java lacks any equivalent field) | @-1 | — | `algorithmStateRaw`<br>uint8 @17 | ❌ missing-in-java | [PY-DIVERGENCE] python-only field algorithmStateRaw=unpack_from(UINT8,17), enum AlgorithmstateEnum {OkState=100}. Java's parse() never reads byte 17 (it falls inside java's uint16 'value' field at 16-17 as the high byte). No Java or Swift equivalent exists. |
| interval (Java lacks any equivalent field) | @-1 | — | `interval`<br>uint8 @23 | ❌ missing-in-java | [PY-DIVERGENCE] python-only field interval=unpack_from(UINT8,23), part of java's transmitterTimestamp uint32 range (22-25). No Java or Swift equivalent. |
| egvInfoBitmask (Java lacks any equivalent field) | @-1 | — | `egvInfoBitmaskRaw`<br>uint16 @24 | ❌ missing-in-java | [PY-DIVERGENCE] python-only field egvInfoBitmaskRaw=unpack_from(UINT16,24), IntFlag bitmask with 11 named bits (FiveMinuteReadingFmr, Backfill, NoEgvMessage, ValidTimestamp, ValidEgvValidRange, ValidAlgstateAlgstateIs100, EgvWasSuccessfullyAddedToCgmSubsystemArrayE, OmrReadingType, SensorType bits 11-13). Falls inside java's transmitterTimestamp uint32 range (22-25). No Java or Swift equivalent. |
| padding byte @14 in Java buildCargo | `(unnamed, new byte[]{0})`<br>uint8 @14 | — | @-1 | ✅ match | java.buildCargo() writes a literal zero byte at offset 14 and parse() never reads it -- internally self-consistent (write-only padding). No corresponding concept in python (occupied by currentGlucoseDisplayValue low byte there) or swift (field absent). |

**Inconsistencies:**

- [PORT-BUG] Swift CgmDataFsl3HistoryLog.swift declares NO payload properties or parsing logic at all -- it only defines `typeId = 480` and a `buildCargo(pumpTimeSec:sequenceNum:)` that zero-fills the remaining 16 payload bytes via HistoryLog.fillCargo. Every Java field (status uint16@10, type uint8@12, rate uint8@13, rssi uint8@15, value uint16@16, timestamp uint32@18, transmitterTimestamp uint32@22) is unparsed in Swift, and there is no getter surface (getStatus/getType/getRate/getRssi/getValue/getTimestamp/getTransmitterTimestamp) mirroring Java's public accessors. This is a functional stub, not a port of Java's parse() logic.
- [PORT-BUG] Swift's buildCargo signature only accepts (pumpTimeSec, sequenceNum) whereas Java's buildCargo(pumpTimeSec, sequenceNum, status, type, rate, rssi, value, timestamp, transmitterTimestamp) accepts and serializes all 7 payload fields; Swift can only ever construct a record with every payload byte hard-zeroed, so round-tripping a real CGM reading through Swift's constructor is impossible.
- [PY-DIVERGENCE] rate: java reads rate as an unscaled uint8 at offset 13; python reads rate as a signed int16 at offset 10 and exposes it scaled by 0.1 (mg/dL/min). Offset, width, and signedness all diverge -- rate@10(2B,int16,scaled) vs rate@13(1B,uint8,raw).
- [PY-DIVERGENCE] status/glucoseValueStatus: java's status field is uint16@10 (raw numeric, no enum in the class though presumably interpreted elsewhere); python's glucoseValueStatusRaw is uint8@13 with an explicit enum (0=PreciseValue,1=SpecialHigh,2=SpecialLow). Offset and width diverge (2 bytes@10 vs 1 byte@13).
- [PY-DIVERGENCE] value/currentGlucoseDisplayValue: java value=uint16@16; python currentGlucoseDisplayValue=uint16@14. Same width, offset shifted 2 bytes earlier in python.
- [PY-DIVERGENCE] rssi: java rssi=uint8@15 (unsigned, despite rssi in dBm typically being negative); python rssi=int8@16 (signed, offset shifted 1 byte later).
- [PY-DIVERGENCE] transmitterTimestamp (java uint32@22-25) has no python counterpart; python instead independently defines interval (uint8@23) and egvInfoBitmask (uint16@24-25) inside that same byte range, leaving byte 22 unread by python. Java in turn has no algorithmState (python uint8@17), interval, or egvInfoBitmask concepts at all -- byte 17 falls inside java's 'value' uint16 high byte, and bytes 22-25 are consumed wholesale as transmitterTimestamp.

### opCode 486 — LID_CGM_STOP_SESSION_FSL3

`CgmStopSessionFsl3HistoryLog` (java) ↔ `CgmStopSessionFsl3HistoryLog` (swift) ↔ `LidCgmStopSessionFsl3` (py) — severity: **🔴 major**

| Concept | java | swift | python | Status | Notes |
|---|---|---|---|---|---|
| typeId/opCode | `(header bytes 0-1, literal 486)`<br>uint16 (2 raw bytes, written as {(byte)486,0}) @0 | `typeId (header bytes 0-1)`<br>uint16 @0 | `raw.id / header`<br>uint16 @0 | ✅ match | All three sides write/read the 2-byte event type ID at offset 0; value 486. Not a payload field but confirms base record alignment. |
| pumpTimeSec (timestamp) | `pumpTimeSec (via parseBase/buildCargo Bytes.toUint32)`<br>uint32 @2 | `pumpTimeSec`<br>uint32 @2 | `raw.timestamp / eventTimestamp`<br>uint32 @2 | ✅ match | java uint32@2 = swift uint32@2 = py uint32@2 (base record field, endianness differs by design, not reported). |
| sequenceNum | `sequenceNum (via parseBase/buildCargo Bytes.toUint32)`<br>uint32 @6 | `sequenceNum`<br>uint32 @6 | `raw.seqNum / seqNum`<br>uint32 @6 | ✅ match | java uint32@6 = swift uint32@6 = py uint32@6 (base record field). |
| sessionStartTime | @-1 | @-1 | `sessionStartTime`<br>uint32 @10 | ❌ missing-in-java | py uint32@10 (LidCgmStopSessionFsl3.build: struct.unpack_from(UINT32, raw, 10)). Java's parse() for this event only calls parseBase(raw) and never reads bytes 10-25 into any field, so sessionStartTime is entirely absent from CgmStopSessionFsl3HistoryLog; Swift's init(cargo:) likewise only calls super.init(cargo:) with no field extraction, so Swift is also missing this field. This is NOT a Swift port bug — Swift faithfully mirrors Java's incomplete parser — but it is a real behavioral gap vs. tconnectsync, which decodes real session-start data that Java/Swift silently discard. |
| sessionStopTime | @-1 | @-1 | `sessionStopTime`<br>uint32 @14 | ❌ missing-in-java | py uint32@14. Same gap as sessionStartTime: Java parse() never reads byte offset 14-17, and Swift (which only calls super.init(cargo:)) matches Java in omitting it — no port-specific divergence, but both Java and Swift lose this field that Python exposes. |
| sessionDuration | @-1 | @-1 | `sessionDuration`<br>uint8 (days) @18 | ❌ missing-in-java | py uint8@18 (days). Java parse() never reads offset 18; Swift matches Java (no field). Field absent from both little-endian parsers. |
| sessionStopReason | @-1 | @-1 | `sessionStopReason`<br>uint8 @19 | ❌ missing-in-java | py uint8@19, no enum/value map defined in Python for the reason codes (plain int). Java parse() never reads offset 19; Swift matches Java (no field), so both lose the stop-reason code entirely. |

**Inconsistencies:**

- [PY-DIVERGENCE] Java's CgmStopSessionFsl3HistoryLog.parse(raw) only calls parseBase(raw) (extracting the shared type/timestamp/sequence header) and never reads bytes 10-25, so the entire CGM-stop-session payload (sessionStartTime uint32@10, sessionStopTime uint32@14, sessionDuration uint8@18, sessionStopReason uint8@19) is dropped; tconnectsync's LidCgmStopSessionFsl3.build() decodes all four fields from those exact byte offsets. This is a real capability gap between Java/TandemKit and tconnectsync for opCode 486, not merely a naming difference.
- Java's buildCargo(pumpTimeSec, sequenceNum) only constructs bytes 0-9 (typeId + pumpTimeSec + sequenceNum) via Bytes.combine and lets HistoryLog.fillCargo zero-pad the remaining bytes 10-25; it never accepts or writes sessionStartTime/sessionStopTime/sessionDuration/sessionStopReason, so a record built via this Java constructor cannot round-trip Python's four payload fields.
- Swift's CgmStopSessionFsl3HistoryLog.init(cargo:) and buildCargo(pumpTimeSec:sequenceNum:) are structurally identical to Java's (init just calls super.init(cargo:), buildCargo only combines typeId+pumpTimeSec+sequenceNum then zero-fills via HistoryLog.fillCargo) — Swift is internally consistent with itself and faithfully matches Java's baseline, so there is no Swift-specific port bug here; the gap is inherited from Java rather than introduced by the port.
