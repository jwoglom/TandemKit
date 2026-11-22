import LoopKit
@testable import TandemKit
import XCTest

@available(macOS 13.0, iOS 14.0, *) final class HostDeviceLogTests: XCTestCase {
    private static let pumpSerial: UInt32 = 1_234_567

    private var manager: TandemPumpManager!
    private var delegate: MockPumpManagerDelegate!
    private let logger = TandemLogger(category: "HostDeviceLogTests")

    override func setUp() {
        super.setUp()
        var state = TandemPumpManagerState(rawValue: [:])
        state.pumpState.pumpSerial = Self.pumpSerial
        manager = TandemPumpManager(state: state, bluetooth: StubPumpBluetooth())
        delegate = MockPumpManagerDelegate()
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        super.tearDown()
    }

    func testInfoWarningAndErrorLinesReachTheHostUnderThePumpSerial() {
        adopt()

        logger.debug("debug line")
        logger.info("info line")
        logger.warning("warning line")
        logger.error("error line")
        manager.waitForDelegateCalls()

        let entries = loggedEntries()
        XCTAssertEqual(entries.map(\.level), ["[INFO]", "[WARNING]", "[ERROR]"])
        XCTAssertTrue(entries.allSatisfy { $0.entry.type == .delegate })
        XCTAssertTrue(entries.allSatisfy { $0.entry.deviceIdentifier == String(Self.pumpSerial) })
        XCTAssertTrue(entries[0].entry.message.hasSuffix(": info line"), entries[0].entry.message)
    }

    func testALineLoggedBeforeTheHostAdoptsTheManagerIsNotSentLater() {
        logger.info("info line")
        adopt()

        manager.waitForDelegateCalls()

        XCTAssertTrue(loggedEntries().isEmpty)
    }

    func testAPumpPairedAfterAdoptionIsTheIdentifier() {
        manager.state.pumpState.pumpSerial = nil
        adopt()

        logger.info("info line")
        manager.state.pumpState.pumpSerial = Self.pumpSerial + 1
        logger.info("info line")
        manager.waitForDelegateCalls()

        XCTAssertEqual(loggedEntries().map(\.entry.deviceIdentifier), [nil, String(Self.pumpSerial + 1)])
    }

    private func adopt() {
        manager.pumpManagerDelegate = delegate
    }

    /// The manager logs as it is adopted, so only this test's own lines.
    private func loggedEntries() -> [(level: String, entry: MockPumpManagerDelegate.DeviceLogEntry)] {
        delegate.deviceLogEntries
            .filter { $0.message.contains("HostDeviceLogTests.swift") }
            .map { (String($0.message.prefix { $0 != " " }), $0) }
    }
}
