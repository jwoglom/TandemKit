import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Each test gets a new install of Trio, on a reset faketandem. What Trio stored is compared with
/// TrioDoseStoreOracle, the model of Trio's DeviceDataManager and pump history the conformance tests
/// use: fed the batches the driver gave Trio, the oracle must predict the rows Trio stored.
class TrioTestCase: FaketandemIntegrationTestCase {
    /// Trio's own defaults, seeded so the tests know them before Trio is installed.
    static let maxBasal = 2.0
    static let maxBolus = 10.0
    /// Trio's basal profile, and the schedule the tests sync to the pump.
    static let scheduledBasalRate = 1.0
    /// The pump's, which Trio rounds stored boluses to only from its second launch with the pump: it
    /// saves it to disk, not to the preferences it loaded at launch.
    static let bolusIncrement = 0.05
    /// The emulator's default (`bolus_rate_units_per_second`).
    static let defaultBolusRate = 0.05

    private(set) var trio: TrioApp!
    private(set) var control: VirtualPumpControl.Client!
    /// Batches the driver gave Trio before a relaunch; each launch's driver logs from scratch.
    private var earlierLaunchesBatches: [VirtualPumpControl.Batch] = []

    /// Written over the launcher's seed before Trio first launches, keyed by path in its data
    /// container. A subclass adds to these.
    func seededFiles() throws -> [String: String] {
        try [
            "Documents/settings/settings.json": Self.json([
                "insulin_action_curve": 10,
                "maxBolus": Self.maxBolus,
                "maxBasal": Self.maxBasal,
            ]),
            "Documents/settings/basal_profile.json": Self.json([
                ["start": "00:00:00", "minutes": 0, "rate": Self.scheduledBasalRate],
            ]),
            "Documents/preferences.json": Self.json(preferences),
        ]
    }

    /// Trio's oref preferences; the rest take Trio's defaults.
    var preferences: [String: Any] {
        ["bolus_increment": Self.bolusIncrement]
    }

    var launchArguments: [String] {
        []
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try restorePumpDelivery()
        trio = try TrioApp.launchNew(name: name, files: seededFiles(), arguments: launchArguments)
        control = try trio.connectControl()
    }

    override func tearDownWithError() throws {
        control?.close()
        control = nil
        do {
            // `hasSucceeded` is false until the run stops, which is after tearDown.
            try trio?.stop(sample: (testRun?.totalFailureCount ?? 0) > 0)
        } catch {
            XCTFail("stopping Trio failed: \(error)")
        }
        trio = nil
        if harness != nil {
            do {
                try restorePumpDelivery()
            } catch {
                XCTFail("restoring the pump's delivery failed: \(error)")
            }
        }
        try super.tearDownWithError()
    }

    /// `harness.reset()` puts back pairing, clock, faults and the link, not what the pump is
    /// delivering, its profile or its limits, which the next test's Trio would otherwise find.
    private func restorePumpDelivery() throws {
        let client = harness.client
        let pump = try client.snapshot()
        if pump.bolus.active {
            try client.abortBolus()
        }
        if pump.basal.tempActive {
            try client.stopTempBasal()
        }
        if pump.basal.suspended {
            try client.resume(clearAlarms: true)
        }
        let profile = FaketandemIDPProfile.emulatorDefault
        var state: [String: Any] = [
            "bolus_rate_units_per_second": Self.defaultBolusRate,
            "idp_profiles": [profile.fields],
            "basal_rate": Double(profile.segments[0].basalRate) / 1000,
        ]
        if let limits = pump.limits {
            state["max_basal_milliunits"] = limits.maxBasalDefaultMilliunits
            state["max_bolus_milliunits"] = limits.maxBolusDefaultMilliunits
        }
        try client.setState(state)
    }

    /// Pairs the driver inside Trio with faketandem: by default on a long-term key given to both, as a
    /// returning pairing does, or `withCode`, through the whole exchange on the pump's code.
    func pairTrio(withCode: Bool = false, thenSync: Bool = true) throws {
        var request = VirtualPumpControl.Request(command: .pair, code: FaketandemHarness.pairingCode)
        if !withCode {
            var key = Data(count: 32)
            for index in key.indices {
                key[index] = UInt8.random(in: .min ... .max)
            }
            _ = try harness.control.setLongTermKey(key)
            request.longTermKey = key.hexadecimalString
        }
        let paired = try control.send(request)
        XCTAssertEqual(paired.status?.onboarded, true)
        XCTAssertEqual(paired.status?.delegateAttached, true, "Trio's DeviceDataManager must be the driver's delegate")
        if thenSync {
            try control.send(.init(command: .sync))
        }
    }

    /// What the pump does on its own reaches Trio through its history log, which the driver starts
    /// reading on a sync after pairing.
    func waitForTheDriversFirstHistoryRead() throws {
        try IntegrationWait.until("the driver to have read the pump's history", timeout: 180) {
            try self.control.send(.init(command: .sync))
            return try self.trio.savedPumpManagerState()?.historyBackfill != nil
        }
    }

    /// One segment, as saving Trio's basal profile syncs it.
    func syncBasalSchedule(unitsPerHour: Double = scheduledBasalRate) throws {
        try control.send(.init(command: .syncBasalSchedule, basalSchedule: [RepeatingScheduleValue(startTime: 0, value: unitsPerHour)]))
    }

    /// Stops Trio and starts it again on the same data once it has stored everything it was given.
    func relaunchTrio() throws {
        earlierLaunchesBatches = try trioStored("every batch before the relaunch") { _ in true }
        control.close()
        trio = try trio.relaunched()
        control = try trio.connectControl()
    }

    /// Every batch the driver gave Trio, once `condition` holds of their events and Trio has stored
    /// them all (Trio calls a batch's completion once it has saved it). With `syncing`, syncs before
    /// each look, as the host does before it doses.
    @discardableResult
    func trioStored(
        _ what: String,
        syncing: Bool = false,
        timeout: TimeInterval = 120,
        until condition: @escaping ([NewPumpEvent]) -> Bool
    ) throws -> [VirtualPumpControl.Batch] {
        let control = try XCTUnwrap(control)
        let batches = try IntegrationWait.value("Trio to have stored \(what)", timeout: timeout) { () -> [VirtualPumpControl.Batch]? in
            if syncing {
                try control.send(.init(command: .sync))
            }
            let batches = try self.allBatches()
            return condition(batches.flatMap(\.pumpEvents)) && batches.allSatisfy(\.completed) ? batches : nil
        }
        XCTAssertEqual(batches.compactMap(\.delegateError), [], "Trio failed to store a batch")
        return batches
    }

    /// Trio stores a row dated ahead of its clock at its clock, which would pull a report the driver
    /// dated a second after another back into that one's second.
    func waitForASecondToPass(since date: Date) throws {
        try IntegrationWait.until("a second to pass since \(date)", timeout: 10) {
            Date() >= date.addingTimeInterval(1)
        }
    }

    /// Feeds the oracle every batch Trio was given and checks Trio stored the rows it predicts;
    /// returns the rows in time order.
    /// The store is read between two reads of the batches that agree and are all completed, so
    /// nothing the driver sends meanwhile (a loop, a pump notification) is missing from either.
    @discardableResult
    func assertTrioStoredWhatTheOracleExpects(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (stored: [TrioStoredPumpEvent], oracle: TrioDoseStoreOracle) {
        let store = try trio.store()
        let (batches, stored) = try IntegrationWait.value("Trio's store to settle", timeout: 120) {
            () -> ([VirtualPumpControl.Batch], [TrioStoredPumpEvent])? in
            let before = try self.allBatches()
            guard before.allSatisfy(\.completed) else {
                return nil
            }
            let stored = try store.pumpEvents().sorted(by: Self.rowOrder)
            return try self.allBatches() == before ? (before, stored) : nil
        }
        XCTAssertEqual(batches.compactMap(\.delegateError), [], "Trio failed to store a batch", file: file, line: line)

        let oracle = try TrioDoseStoreOracle(maxBasal: trio.maxBasal(), bolusIncrement: Self.bolusIncrement)
        for batch in batches {
            oracle.addPumpEvents(
                batch.pumpEvents,
                lastReconciliation: batch.lastReconciliation,
                replacePendingEvents: batch.replacePendingEvents,
                now: batch.hostNow
            )
        }
        assertSameRows(stored, oracle.events.map(TrioStoredPumpEvent.init), file: file, line: line)
        return (stored, oracle)
    }

    private func allBatches() throws -> [VirtualPumpControl.Batch] {
        try earlierLaunchesBatches + XCTUnwrap(control.send(.init(command: .pumpEventBatches)).batches)
    }

    /// Trio fetches rows at one timestamp, such as a site change and its prime, in no fixed order.
    private static func rowOrder(_ a: TrioStoredPumpEvent, _ b: TrioStoredPumpEvent) -> Bool {
        (a.timestamp, a.syncIdentifier ?? "", a.type) < (b.timestamp, b.syncIdentifier ?? "", b.type)
    }

    /// Row for row, in timestamp order. Trio dates a row `min(event.date, now)` with its own now at
    /// saving, the oracle with the driver's at sending, so timestamps agree to a second or two.
    private func assertSameRows(
        _ stored: [TrioStoredPumpEvent],
        _ predicted: [TrioStoredPumpEvent],
        file: StaticString,
        line: UInt
    ) {
        let stored = stored.sorted(by: Self.rowOrder)
        let predicted = predicted.sorted(by: Self.rowOrder)
        let report = "Trio stored:\n\(stored.map { "  \($0)" }.joined(separator: "\n"))\noracle predicted:\n\(predicted.map { "  \($0)" }.joined(separator: "\n"))"
        guard stored.count == predicted.count else {
            return XCTFail("row counts differ\n\(report)", file: file, line: line)
        }
        for (actual, expected) in zip(stored, predicted) {
            var expected = expected
            if abs(actual.timestamp.timeIntervalSince(expected.timestamp)) <= 2 {
                expected.timestamp = actual.timestamp
            }
            for keyPath in [\TrioStoredPumpEvent.bolusAmount, \.programmedAmount, \.tempBasalRate] {
                if let a = actual[keyPath: keyPath], let e = expected[keyPath: keyPath], abs(a - e) < 1e-6 {
                    expected[keyPath: keyPath] = a
                }
            }
            XCTAssertEqual(actual, expected, report, file: file, line: line)
        }
    }

    static func milliunits(_ units: Double) -> Int {
        Int((units * 1000).rounded())
    }

    static func json(_ object: Any) throws -> String {
        try String(decoding: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    static func plist(_ object: Any) throws -> String {
        try String(decoding: PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0), as: UTF8.self)
    }
}

extension TrioStoredPumpEvent {
    init(_ row: TrioDoseStoreOracle.StoredEvent) {
        let double = { (value: Decimal?) in value.map { NSDecimalNumber(decimal: $0).doubleValue } }
        self.init(
            timestamp: row.timestamp,
            type: row.type.rawValue,
            syncIdentifier: row.syncIdentifier,
            isMutable: row.isMutable,
            bolusAmount: double(row.bolusAmount),
            programmedAmount: double(row.programmedAmount),
            isSMB: row.isSMB,
            isExternal: row.isExternal,
            tempBasalRate: double(row.tempBasalRate),
            tempBasalDurationMinutes: row.tempBasalDurationMinutes,
            isScheduledBasal: row.type == .tempBasal ? row.isScheduledBasal : nil
        )
    }

    var eventType: TrioDoseStoreOracle.EventType? {
        TrioDoseStoreOracle.EventType(rawValue: type)
    }

    var isTempBasal: Bool {
        eventType == .tempBasal && isScheduledBasal == false
    }

    var isScheduledBasalMarker: Bool {
        eventType == .tempBasal && isScheduledBasal == true
    }
}
