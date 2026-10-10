import Foundation
import SQLite3

/// One `PumpEventStored` row with its `BolusStored` / `TempBasalStored` child, as Trio saved it.
/// The fields are `TrioDoseStoreOracle.StoredEvent`'s, so the two compare directly.
struct TrioStoredPumpEvent: Equatable, CustomStringConvertible {
    var timestamp: Date
    var type: String
    var syncIdentifier: String?
    var isMutable: Bool
    var bolusAmount: Double?
    var programmedAmount: Double?
    var isSMB: Bool?
    var isExternal: Bool?
    var tempBasalRate: Double?
    var tempBasalDurationMinutes: Int?
    var isScheduledBasal: Bool?

    var description: String {
        var parts = ["\(type) at \(timestamp.timeIntervalSinceReferenceDate)", "sync \(syncIdentifier ?? "nil")", isMutable ? "mutable" : "final"]
        if let bolusAmount { parts.append("bolus \(bolusAmount)/\(programmedAmount.map(String.init(describing:)) ?? "nil") smb \(String(describing: isSMB)) external \(String(describing: isExternal))") }
        if let tempBasalRate { parts.append("rate \(tempBasalRate) for \(tempBasalDurationMinutes ?? -1) min scheduled \(String(describing: isScheduledBasal))") }
        return parts.joined(separator: ", ")
    }
}

/// Trio's Core Data store (`TrioCoreDataPersistentContainer.sqlite`), opened read-only in place while
/// Trio runs; the store is in WAL mode, so a reader sees every committed save without blocking it.
final class TrioStore {
    let url: URL
    private var db: OpaquePointer?

    init(dataContainer: URL) throws {
        let name = "TrioCoreDataPersistentContainer.sqlite"
        let found = FileManager.default.enumerator(at: dataContainer, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .first { $0.lastPathComponent == name }
        guard let found else {
            throw TrioStoreError("no \(name) under \(dataContainer.path)")
        }
        url = found
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw TrioStoreError("open \(url.path): \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func pumpEvents() throws -> [TrioStoredPumpEvent] {
        let bolusJoin = try join(child: "ZBOLUSSTORED", parentColumn: "ZBOLUS")
        let tempJoin = try join(child: "ZTEMPBASALSTORED", parentColumn: "ZTEMPBASAL")
        let sql = """
            SELECT p.ZTIMESTAMP, p.ZTYPE, p.ZSYNCIDENTIFIER, p.ZISMUTABLE,
                   b.ZAMOUNT, b.ZPROGRAMMEDAMOUNT, b.ZISSMB, b.ZISEXTERNAL,
                   t.ZRATE, t.ZDURATION, t.ZISSCHEDULEDBASAL
            FROM ZPUMPEVENTSTORED p
            LEFT JOIN ZBOLUSSTORED b ON \(bolusJoin("b"))
            LEFT JOIN ZTEMPBASALSTORED t ON \(tempJoin("t"))
            ORDER BY p.ZTIMESTAMP, p.Z_PK
            """
        return try query(sql) { row in
            TrioStoredPumpEvent(
                timestamp: Date(timeIntervalSinceReferenceDate: row.double(0) ?? 0),
                type: row.text(1) ?? "",
                syncIdentifier: row.text(2),
                isMutable: row.bool(3) ?? false,
                bolusAmount: row.double(4),
                programmedAmount: row.double(5),
                isSMB: row.bool(6),
                isExternal: row.bool(7),
                tempBasalRate: row.double(8),
                tempBasalDurationMinutes: row.double(9).map { Int($0) },
                isScheduledBasal: row.bool(10)
            )
        }
    }

    /// A to-one relationship's foreign key can sit on either table; join on whichever has it.
    private func join(child: String, parentColumn: String) throws -> (String) -> String {
        if try columns(of: child).contains("ZPUMPEVENT") {
            return { alias in "\(alias).ZPUMPEVENT = p.Z_PK" }
        }
        if try columns(of: "ZPUMPEVENTSTORED").contains(parentColumn) {
            return { alias in "\(alias).Z_PK = p.\(parentColumn)" }
        }
        throw TrioStoreError("no foreign key between ZPUMPEVENTSTORED and \(child)")
    }

    private func columns(of table: String) throws -> Set<String> {
        Set(try query("PRAGMA table_info(\(table))") { $0.text(1) ?? "" })
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
    }

    private func query<T>(_ sql: String, _ read: (Row) -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw TrioStoreError("\(sql): \(String(cString: sqlite3_errmsg(db)))")
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
                throw TrioStoreError("\(sql): \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }
}

struct TrioStoreError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
