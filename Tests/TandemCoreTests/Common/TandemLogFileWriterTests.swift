import Foundation
import XCTest
@testable import TandemKit

final class TandemLogFileWriterTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("tandem-log-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testConcurrentWritersKeepEveryLineIntact() throws {
        let writer = TandemLogFileWriter(directory: directory)
        let threads = 8
        let perThread = 500

        DispatchQueue.concurrentPerform(iterations: threads) { thread in
            for n in 0 ..< perThread {
                let padding = String(repeating: "x", count: (thread * 7 + n) % 90)
                writer.append("[ts INFO] t\(thread) n\(n) \(padding) end\n")
            }
        }

        let lines = try String(contentsOf: writer.logFile, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        XCTAssertEqual(lines.count, threads * perThread)
        XCTAssertTrue(lines.allSatisfy { $0.hasPrefix("[ts INFO] t") && $0.hasSuffix(" end") })
        XCTAssertEqual(Set(lines).count, lines.count)
    }

    func testRotatesToPrevFileOnceTheDayChanges() throws {
        let writer = TandemLogFileWriter(directory: directory)
        let start = Date()
        writer.append("first\n", now: start)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        writer.append("second\n", now: tomorrow)

        XCTAssertEqual(try String(contentsOf: writer.logFilePrev, encoding: .utf8), "first\n")
        XCTAssertEqual(try String(contentsOf: writer.logFile, encoding: .utf8), "second\n")
    }
}
