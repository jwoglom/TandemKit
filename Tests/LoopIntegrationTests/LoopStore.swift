import Foundation
import SQLite3
import TandemKit

/// One `PumpEvent` row as Loop saved it, in the fields `LoopDoseStoreOracle.PumpEventRow` predicts.
/// Its date is the dose's start when it has a dose (`PumpEvent.dose` sets `startDate`, which is `date`).
struct LoopStoredPumpEvent: Equatable, CustomStringConvertible {
    var raw: Data
    var date: Date
    var type: String?
    var mutable: Bool
    var doseType: String?
    var value: Double?
    var unit: String?
    var duration: TimeInterval?
    var deliveredUnits: Double?
    var automatic: Bool?

    var description: String {
        var parts = ["\(String(decoding: raw, as: UTF8.self)) at \(date.timeIntervalSinceReferenceDate)", type ?? "no type", mutable ? "mutable" : "final"]
        if let doseType {
            parts.append("\(doseType) \(value.map(String.init(describing:)) ?? "nil") \(unit ?? "") for \(duration ?? -1) s, delivered \(deliveredUnits.map(String.init(describing:)) ?? "nil"), automatic \(String(describing: automatic))")
        }
        return parts.joined(separator: ", ")
    }
}

/// One `CachedInsulinDeliveryObject` row, live or soft-deleted: the doses Loop counts, and writes to
/// HealthKit once immutable.
struct LoopCachedDose: Equatable, CustomStringConvertible {
    var syncIdentifier: String
    var startDate: Date
    var endDate: Date
    /// Units, `unitsInDeliverableIncrements` of the dose: the row's `deliveredUnits`, `value` before
    /// LoopKit's model v6.
    var value: Double
    /// `HKInsulinDeliveryReason`: 1 basal, 2 bolus.
    var reason: Int
    var isSuspend: Bool
    var isMutable: Bool
    var isDeleted: Bool
    var programmedTempBasalRate: Double?
    var automatic: Bool?

    /// DoseStore's own entry for a gap between basal doses (`LoopDoseStoreOracle.overlaying`).
    var isScheduleFill: Bool {
        syncIdentifier.hasPrefix("BasalRateSchedule ")
    }

    var isBolus: Bool {
        reason == 2
    }

    var description: String {
        var parts = [
            "\(Data(hexadecimalString: syncIdentifier).map { String(decoding: $0, as: UTF8.self) } ?? syncIdentifier)",
            "\(startDate.timeIntervalSinceReferenceDate)…\(endDate.timeIntervalSinceReferenceDate)",
            isBolus ? "bolus" : isSuspend ? "suspend" : "basal",
            "\(value) U",
        ]
        if let programmedTempBasalRate { parts.append("temp \(programmedTempBasalRate) U/hr") }
        if isMutable { parts.append("mutable") }
        if isDeleted { parts.append("deleted") }
        if let automatic { parts.append("automatic \(automatic)") }
        return parts.joined(separator: ", ")
    }
}

/// LoopKit's Core Data store in Loop's app group, opened read-only in place while Loop runs; in WAL
/// mode, a reader sees every committed save without blocking it.
final class LoopStore {
    let url: URL
    private var db: OpaquePointer?

    init(groupContainer: URL) throws {
        url = groupContainer.appendingPathComponent("com.loopkit.LoopKit/Model.sqlite")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoopStoreError("no \(url.path)")
        }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw LoopStoreError("open \(url.path): \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func pumpEvents() throws -> [LoopStoredPumpEvent] {
        let sql = """
            SELECT ZRAW, ZDATE, ZTYPE, ZMUTABLE, ZDOSETYPE, ZVALUE, ZUNIT, ZDURATION, ZDELIVEREDUNITS, ZAUTOMATIC
            FROM ZPUMPEVENT
            ORDER BY ZDATE, Z_PK
            """
        return try query(sql) { row in
            LoopStoredPumpEvent(
                raw: row.data(0) ?? Data(),
                date: Date(timeIntervalSinceReferenceDate: row.double(1) ?? 0),
                type: row.text(2),
                mutable: row.bool(3) ?? false,
                doseType: row.text(4),
                value: row.double(5),
                unit: row.text(6),
                duration: row.double(7),
                deliveredUnits: row.double(8),
                automatic: row.bool(9)
            )
        }
    }

    func cachedDoses() throws -> [LoopCachedDose] {
        let unitsColumn = try cachedDoseUnitsColumn()
        let sql = """
            SELECT ZSYNCIDENTIFIER, ZSTARTDATE, ZENDDATE, \(unitsColumn), ZREASON, ZISSUSPEND, ZISMUTABLE, ZDELETEDAT,
                   ZPROGRAMMEDTEMPBASALRATE, ZAUTOMATICALLYISSUED
            FROM ZCACHEDINSULINDELIVERYOBJECT
            ORDER BY ZSTARTDATE, Z_PK
            """
        return try query(sql) { row in
            LoopCachedDose(
                syncIdentifier: row.text(0) ?? "",
                startDate: Date(timeIntervalSinceReferenceDate: row.double(1) ?? 0),
                endDate: Date(timeIntervalSinceReferenceDate: row.double(2) ?? 0),
                value: row.double(3) ?? 0,
                reason: Int(row.double(4) ?? 0),
                isSuspend: row.bool(5) ?? false,
                isMutable: row.bool(6) ?? false,
                isDeleted: row.double(7) != nil,
                programmedTempBasalRate: row.double(8),
                automatic: row.bool(9)
            )
        }
    }

    /// When Loop's stored basal schedule changed: each `SettingsObject` whose schedule differs from the
    /// one before it, as `SettingsStore.getBasalHistory` compares them. A change of time zone alone counts:
    /// Loop sets its schedules to the pump's zone at the pump's first status (`setScheduleTimeZone`).
    func basalScheduleChangeDates() throws -> [Date] {
        let rows = try query("SELECT ZDATE, ZDATA FROM ZSETTINGSOBJECT ORDER BY ZDATE, Z_PK") { row in
            (date: Date(timeIntervalSinceReferenceDate: row.double(0) ?? 0), data: row.data(1))
        }
        var changes: [Date] = []
        var last: NSDictionary?
        for row in rows {
            guard let data = row.data,
                  let settings = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let schedule = settings["basalRateSchedule"] as? NSDictionary
            else { continue }
            if let last, !last.isEqual(schedule) {
                changes.append(row.date)
            }
            last = schedule
        }
        return changes
    }

    /// LoopKit's model v6 renamed the dose's units from `value` to `deliveredUnits`, so the column
    /// follows the LoopKit Loop was built with.
    private func cachedDoseUnitsColumn() throws -> String {
        let columns = try query("PRAGMA table_info(ZCACHEDINSULINDELIVERYOBJECT)") { $0.text(1) ?? "" }
        return columns.contains("ZDELIVEREDUNITS") ? "ZDELIVEREDUNITS" : "ZVALUE"
    }

    struct Row {
        let statement: OpaquePointer

        func double(_ column: Int32) -> Double? {
            sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_double(statement, column)
        }

        func bool(_ column: Int32) -> Bool? {
            sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, column) != 0
        }

        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }

        func data(_ column: Int32) -> Data? {
            guard sqlite3_column_type(statement, column) != SQLITE_NULL, let bytes = sqlite3_column_blob(statement, column) else {
                return nil
            }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
        }
    }

    private func query<T>(_ sql: String, _ read: (Row) -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LoopStoreError("\(sql): \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(statement) }
        var rows: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                rows.append(read(Row(statement: statement)))
            case SQLITE_DONE:
                return rows
            default:
                throw LoopStoreError("\(sql): \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }
}

struct LoopStoreError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
