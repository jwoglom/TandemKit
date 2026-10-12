import Foundation
@testable import TandemKit
import XCTest

/// Base for every test against the emulator: skips without the environment, resets the pump before
/// each test, tears the driver down after it, and attaches the pump-side request log to a failure.
class FaketandemIntegrationTestCase: XCTestCase {
    var harness: FaketandemHarness!
    private(set) var driver: FaketandemHarness.Driver?

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        harness = try FaketandemHarness.fromEnvironment()
        try harness.reset()
    }

    override func tearDownWithError() throws {
        if let harness {
            attachRequestLog()
            if let driver {
                do {
                    try harness.shutDown(driver)
                } catch {
                    XCTFail("driver shutdown failed: \(error)")
                }
            }
        }
        driver = nil
        harness = nil
        try super.tearDownWithError()
    }

    /// `stageBasalScheduleSync` marks setup's basal sync done, as a seeded pairing stages the key,
    /// so a test about something else can set temp basals without syncing a schedule first.
    func makeDriver(
        state: TandemPumpManagerState = TandemPumpManagerState(rawValue: [:]),
        clock: TandemClock = ManualClock(Date()),
        stageBasalScheduleSync: Bool = true,
        poweredOnBeforeAttach: Bool = false
    ) -> FaketandemHarness.Driver {
        precondition(driver == nil, "one driver per test; shut the previous one down first")
        var state = state
        if stageBasalScheduleSync {
            state.hasSyncedBasalRateSchedule = true
        }
        let created = harness.makeDriver(state: state, clock: clock, poweredOnBeforeAttach: poweredOnBeforeAttach)
        driver = created
        return created
    }

    #if !canImport(ObjectiveC)
    override func recordFailure(withDescription description: String, inFile filePath: String, atLine lineNumber: Int, expected: Bool) {
        if ExpectedFailureScope.absorb(description) { return }
        super.recordFailure(withDescription: description, inFile: filePath, atLine: lineNumber, expected: expected)
    }
    #endif

    /// Ends the current driver as the app going away does, so a second one (a relaunch) can attach to
    /// the pump.
    func shutDownDriver() throws {
        guard let driver else { return }
        try harness.shutDown(driver)
        self.driver = nil
    }

    /// The host deletes the pump manager.
    func deactivateDriver() throws {
        guard let driver else { return }
        try harness.deactivate(driver)
        self.driver = nil
    }

    private func attachRequestLog() {
        guard let entries = try? harness.requestLog() else { return }
        let lines = entries.map { entry -> String in
            var line = "\(entry.seq) \(entry.kind)"
            if let characteristic = entry.characteristic { line += " \(characteristic)" }
            if let opcode = entry.opcode { line += " op=\(opcode)" }
            if let message = entry.message { line += " \(message)" }
            if let connected = entry.connected { line += " connected=\(connected)" }
            if let fault = entry.fault { line += " fault=\(fault)" }
            if let note = entry.note { line += " note=\(note)" }
            if let fragments = entry.fragments { line += " \(fragments.joined(separator: "|"))" }
            return line
        }
        #if canImport(ObjectiveC)
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "faketandem-request-log.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
        #else
        // swift-corelibs-xctest has no attachments; integration-test.sh points this at LOG_DIR.
        guard let directory = ProcessInfo.processInfo.environment["FAKETANDEM_REQUEST_LOG_DIR"] else { return }
        let file = URL(fileURLWithPath: directory)
            .appendingPathComponent(name.replacingOccurrences(of: "/", with: "_") + ".faketandem-request-log.txt")
        try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        #endif
    }
}
