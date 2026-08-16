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

    /// Field-by-field description across the class hierarchy, excluding raw `cargo` bytes,
    /// mirroring pumpX2's `verboseToString` (which excludes cargo from the comparison).
    static func verboseDescription(of log: HistoryLog) -> String {
        var parts: [String] = []
        var mirror: Mirror? = Mirror(reflecting: log)
        while let m = mirror {
            for child in m.children {
                guard let label = child.label, label != "cargo" else { continue }
                parts.append("\(label)=\(String(describing: child.value))")
            }
            mirror = m.superclassMirror
        }
        return "\(type(of: log))[\(parts.joined(separator: ","))]"
    }
}
