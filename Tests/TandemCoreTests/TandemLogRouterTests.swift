import XCTest
@testable import TandemKit

private final class RecordingDestination: TandemLogDestination {
    struct Entry {
        let category: String
        let level: TandemLogLevel
        let message: String
        let file: String
        let function: String
        let line: Int
    }

    let minimumLevel: TandemLogLevel
    private(set) var entries: [Entry] = []

    init(minimumLevel: TandemLogLevel) {
        self.minimumLevel = minimumLevel
    }

    func write(
        category: String,
        level: TandemLogLevel,
        message: String,
        file: String,
        function: String,
        line: Int,
        date _: Date
    ) {
        entries.append(Entry(
            category: category,
            level: level,
            message: message,
            file: file,
            function: function,
            line: line
        ))
    }
}

final class TandemLogRouterTests: XCTestCase {
    override func tearDown() {
        TandemLogRouter.resetToDefaults()
        super.tearDown()
    }

    func testEveryDestinationReceivesTheSameLine() {
        TandemLogRouter.removeAllDestinations()
        let first = RecordingDestination(minimumLevel: .info)
        let second = RecordingDestination(minimumLevel: .info)
        TandemLogRouter.add(first)
        TandemLogRouter.add(second)

        TandemLogger(category: "Pairing").info("hello pump")

        XCTAssertEqual(first.entries.count, 1)
        XCTAssertEqual(second.entries.count, 1)
        XCTAssertEqual(first.entries.first?.message, "hello pump")
        XCTAssertEqual(second.entries.first?.message, "hello pump")
        XCTAssertEqual(first.entries.first?.category, "Pairing")
        XCTAssertEqual(first.entries.first?.level, .info)
    }

    func testDestinationsBelowMinimumLevelAreSkipped() {
        TandemLogRouter.removeAllDestinations()
        let verbose = RecordingDestination(minimumLevel: .debug)
        let quiet = RecordingDestination(minimumLevel: .error)
        TandemLogRouter.add(verbose)
        TandemLogRouter.add(quiet)

        let logger = TandemLogger(category: "Transport")
        logger.debug("chatty")
        logger.warning("uh oh")
        logger.error("broken")

        XCTAssertEqual(verbose.entries.map(\.level), [.debug, .warning, .error])
        XCTAssertEqual(quiet.entries.map(\.level), [.error])
    }

    func testLevelLabels() {
        XCTAssertEqual(TandemLogLevel.debug.trioPrefix, "DEV")
        XCTAssertEqual(TandemLogLevel.info.trioPrefix, "INFO")
        XCTAssertEqual(TandemLogLevel.warning.trioPrefix, "WARN")
        XCTAssertEqual(TandemLogLevel.error.trioPrefix, "ERR")
        XCTAssertEqual(TandemLogLevel.warning.label, "WARNING")
        XCTAssertTrue(TandemLogLevel.info < TandemLogLevel.warning)
    }
}
