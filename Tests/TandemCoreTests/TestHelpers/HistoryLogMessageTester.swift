@testable import TandemKit
import XCTest

/// Swift port of pumpX2's `HistoryLogMessageTester`: parses a raw 26-byte history log record
/// through the production `HistoryLogParser` and compares it against an expected instance.
enum HistoryLogMessageTester {
    /// Parses `rawHex` (52 hex chars, bytes copied verbatim from a captured record), asserts it
    /// dispatches to `T` with the expected typeId, and compares every stored property except
    /// `cargo` against `expected` (the equivalent of pumpX2's `verboseToString` comparison).
    /// Returns the typed parsed log so callers can additionally assert a full cargo round-trip
    /// via `MessageTester.assertHexEquals(expected.cargo, parsed.cargo)` when the record is
    /// byte-exactly reproducible.
    @discardableResult
    static func testSingle<T: HistoryLog>(
        _ rawHex: String,
        _ expected: T,
        file: StaticString = #file,
        line: UInt = #line
    ) -> T {
        guard let raw = Data(hexadecimalString: rawHex) else {
            XCTFail("invalid hex: \(rawHex)", file: file, line: line)
            return expected
        }
        let parsed = HistoryLogParser.parse(raw)
        guard let typed = parsed as? T else {
            XCTFail("parsed \(type(of: parsed)) (typeId \(parsed.typeId)), expected \(T.self)", file: file, line: line)
            return expected
        }
        XCTAssertEqual(expected.typeId, typed.typeId, file: file, line: line)
        XCTAssertEqual(
            verboseDescription(of: expected),
            verboseDescription(of: typed),
            file: file,
            line: line
        )
        return typed
    }

    /// Mirrors pumpX2's `HistoryLogMessageTester.testSingleIgnoringBaseFields`: used for record
    /// types whose Java (and Swift) convenience initializer doesn't accept `pumpTimeSec`/
    /// `sequenceNum` at all (only the 0-argument-delegating overload), so those two base fields
    /// on `expected` are always 0 and can't be compared against a real capture's parsed values.
    /// Excludes `pumpTimeSec`/`sequenceNum` from the comparison instead of pumpX2's mutation
    /// (`clearBaseFieldsForTesting`), since those fields are `let` on the Swift `HistoryLog` base.
    @discardableResult
    static func testSingleIgnoringBaseFields<T: HistoryLog>(
        _ rawHex: String,
        _ expected: T,
        file: StaticString = #file,
        line: UInt = #line
    ) -> T {
        guard let raw = Data(hexadecimalString: rawHex) else {
            XCTFail("invalid hex: \(rawHex)", file: file, line: line)
            return expected
        }
        let parsed = HistoryLogParser.parse(raw)
        guard let typed = parsed as? T else {
            XCTFail("parsed \(type(of: parsed)) (typeId \(parsed.typeId)), expected \(T.self)", file: file, line: line)
            return expected
        }
        XCTAssertEqual(expected.typeId, typed.typeId, file: file, line: line)
        XCTAssertEqual(
            verboseDescription(of: expected, ignoringBaseFields: true),
            verboseDescription(of: typed, ignoringBaseFields: true),
            file: file,
            line: line
        )
        return typed
    }

    /// Mirrors the cargo-bytes side effect of pumpX2's `clearBaseFieldsForTesting`: zeroes the
    /// pumpTimeSec/sequenceNum region (cargo offsets 2..<10) so a `cargo` round-trip assertion can
    /// be compared against an `expected` built via the 0-pumpTimeSec/0-sequenceNum convenience
    /// initializer, exactly as pumpX2's `assertHexEquals(expected.getCargo(), parsedRes.getCargo())`
    /// does after `testSingleIgnoringBaseFields` mutates the parsed object's cargo in place.
    static func cargoIgnoringBaseFields(_ log: HistoryLog) -> Data {
        var cargo = log.cargo
        for i in 2 ..< 10 {
            cargo[cargo.startIndex + i] = 0
        }
        return cargo
    }

    /// Converts a pumpX2 Java test's expected `Instant` literal into the `Date` the Swift decoder
    /// is expected to produce for the same `pumpTimeSec`.
    ///
    /// pumpX2's `Dates.fromJan12008EpochSecondsToDate` treats the wire value as seconds since
    /// 2008-01-01 **UTC**, so its tests assert literals like `Instant.parse("2022-02-18T17:51:04Z")`.
    /// Swift's `Dates.fromJan12008ToUnixEpochSeconds` deliberately differs: the pump keeps its clock
    /// in local time, so it subtracts `TimeZone.current.secondsFromGMT()` to turn that pump
    /// wall-clock reading into an absolute instant. The ISO literal is therefore the pump's
    /// *wall clock*, not the instant, and porting it verbatim only agreed with the decoder on a host
    /// whose zone offset is zero. Applying the same offset here keeps the assertion — and the
    /// pumpX2 fixture value it documents — correct in every host time zone.
    static func expectedDate(
        pumpWallClock iso: String,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Date? {
        guard let wallClock = ISO8601DateFormatter().date(from: iso) else {
            XCTFail("invalid ISO8601 pump wall clock: \(iso)", file: file, line: line)
            return nil
        }
        return wallClock.addingTimeInterval(-TimeInterval(TimeZone.current.secondsFromGMT()))
    }

    /// Field-by-field description across the class hierarchy, excluding raw `cargo` bytes,
    /// mirroring pumpX2's `verboseToString` (which excludes cargo from the comparison).
    /// When `ignoringBaseFields` is set, also excludes `pumpTimeSec`/`sequenceNum`.
    static func verboseDescription(of log: HistoryLog, ignoringBaseFields: Bool = false) -> String {
        var parts: [String] = []
        var mirror: Mirror? = Mirror(reflecting: log)
        while let m = mirror {
            for child in m.children {
                guard let label = child.label, label != "cargo" else { continue }
                if ignoringBaseFields, label == "pumpTimeSec" || label == "sequenceNum" { continue }
                parts.append("\(label)=\(String(describing: child.value))")
            }
            mirror = m.superclassMirror
        }
        return "\(type(of: log))[\(parts.joined(separator: ","))]"
    }
}
