import Foundation
import LoopKit
@testable import TandemKit
import XCTest

/// Each test gets a new install of Loop, on a reset faketandem. Both of DoseStore's tables must hold what
/// LoopDoseStoreOracle, fed the batches the driver gave Loop, predicts.
class LoopTestCase: FaketandemIntegrationTestCase {
    static let maxBasal = 2.0
    static let maxBolus = 10.0
    /// Loop's basal schedule, and the schedule the tests sync to the pump.
    static let scheduledBasalRate = 1.0
    /// The emulator's default (`bolus_rate_units_per_second`).
    static let defaultBolusRate = 0.05

    /// Loop decodes a schedule's zone as a fixed offset from GMT.
    static var basalSchedule: BasalRateSchedule {
        BasalRateSchedule(
            dailyItems: [RepeatingScheduleValue(startTime: 0, value: scheduledBasalRate)],
            timeZone: TimeZone(secondsFromGMT: TimeZone.current.secondsFromGMT())
        )!
    }

    private(set) var loop: LoopApp!
    private(set) var control: VirtualPumpControl.Client!
    /// Batches the driver gave Loop before a relaunch; each launch's driver logs from scratch.
    private var earlierLaunchesBatches: [VirtualPumpControl.Batch] = []

    /// Closed loop; off while the test commands every dose, as Loop's screens do.
    var dosingEnabled: Bool {
        false
    }

    /// `AutomaticDosingStrategy`: 0 temp basal only, 1 automatic bolus.
    var dosingStrategy: Int {
        0
    }

    /// Written over the launcher's seed before Loop first launches, keyed by path in its data
    /// container. A subclass adds to these.
    func seededFiles() throws -> [String: String] {
        [:]
    }

    var launchArguments: [String] {
        []
    }

    /// Loop's therapy settings as the legacy keys SettingsManager migrates at launch (LoopCore
    /// NSUserDefaults.swift), in their raw-value form; the launcher adds the onboarding flag.
    func groupDefaults() -> [String: Any] {
        func schedule(_ value: Any, unit: String? = nil) -> [String: Any] {
            var raw: [String: Any] = ["timeZone": TimeZone.current.secondsFromGMT(), "items": [["startTime": 0.0, "value": value]]]
            if let unit {
                raw["unit"] = unit
            }
            return raw
        }
        return [
            "com.loopkit.Loop.loopSettings": [
                "version": 1,
                "dosingEnabled": dosingEnabled,
                "overridePresets": [Any](),
                "glucoseTargetRangeSchedule": schedule([100.0, 110.0], unit: "mg/dL"),
                "maximumBasalRatePerHour": Self.maxBasal,
                "maximumBolus": Self.maxBolus,
                "minimumBGGuard": ["units": "mg/dL", "value": 80.0],
                "dosingStrategy": dosingStrategy,
            ] as [String: Any],
            "com.loudnate.Naterade.BasalRateSchedule": schedule(Self.scheduledBasalRate),
            "com.loudnate.Naterade.InsulinSensitivitySchedule": schedule(45.0, unit: "mg/dL"),
            "com.loudnate.Naterade.CarbRatioSchedule": schedule(10.0, unit: "g"),
        ]
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try restorePumpDelivery()
        loop = try LoopApp.launchNew(name: name, files: seededFiles(), groupDefaults: groupDefaults(), arguments: launchArguments)
        control = try loop.connectControl()
    }

    override func tearDownWithError() throws {
        control?.close()
        control = nil
        do {
            // `hasSucceeded` is false until the run stops, which is after tearDown.
            try loop?.stop(sample: (testRun?.totalFailureCount ?? 0) > 0)
        } catch {
            XCTFail("stopping Loop failed: \(error)")
        }
        loop = nil
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
    /// delivering, its profile or its limits, which the next test's Loop would otherwise find.
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

    /// Pairs the driver inside Loop with faketandem: by default on a long-term key given to both, as a
    /// returning pairing does, or `withCode`, through the whole exchange on the pump's code.
    func pairLoop(withCode: Bool = false, thenSync: Bool = true) throws {
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
        XCTAssertEqual(paired.status?.delegateAttached, true, "Loop's DeviceDataManager must be the driver's delegate")
        if thenSync {
            try control.send(.init(command: .sync))
        }
    }

    /// What the pump does on its own reaches Loop through its history log, which the driver starts
    /// reading on a sync after pairing.
    func waitForTheDriversFirstHistoryRead() throws {
        try IntegrationWait.until("the driver to have read the pump's history", timeout: 180) {
            try self.control.send(.init(command: .sync))
            return try self.loop.savedPumpManagerState()?.historyBackfill != nil
        }
    }

    /// One segment, as saving Loop's basal rates syncs it.
    func syncBasalSchedule(unitsPerHour: Double = scheduledBasalRate) throws {
        try control.send(.init(command: .syncBasalSchedule, basalSchedule: [RepeatingScheduleValue(startTime: 0, value: unitsPerHour)]))
    }

    /// Stops Loop and starts it again on the same data once it has stored everything it was given.
    func relaunchLoop() throws {
        earlierLaunchesBatches = try loopStored("every batch before the relaunch") { _ in true }
        control.close()
        loop = try loop.relaunched()
        control = try loop.connectControl()
    }

    /// Every batch the driver gave Loop, once `condition` holds of their events and Loop has saved them
    /// all to both tables, which DoseStore does before it completes a batch. `syncing` syncs first.
    @discardableResult
    func loopStored(
        _ what: String,
        syncing: Bool = false,
        timeout: TimeInterval = 300,
        until condition: @escaping ([NewPumpEvent]) -> Bool
    ) throws -> [VirtualPumpControl.Batch] {
        let control = try XCTUnwrap(control)
        let batches = try IntegrationWait.value("Loop to have stored \(what)", timeout: timeout) { () -> [VirtualPumpControl.Batch]? in
            if syncing {
                try control.send(.init(command: .sync))
            }
            let batches = try self.allBatches()
            return condition(batches.flatMap(\.pumpEvents)) && batches.allSatisfy(\.completed) ? batches : nil
        }
        XCTAssertEqual(batches.compactMap(\.delegateError), [], "Loop failed to store a batch")
        return batches
    }

    /// The driver dates a resume at least a second after its suspend, ahead of Loop's clock inside that
    /// second, and DoseStore caches no finished dose that ends ahead of its clock.
    func waitForASecondToPass(since date: Date) throws {
        try IntegrationWait.until("a second to pass since \(date)", timeout: 10) {
            Date() >= date.addingTimeInterval(1)
        }
    }

    /// Feeds the oracle every batch Loop was given and checks Loop stored the rows it predicts. The store
    /// is read between two reads of the batches that agree, so nothing sent meanwhile is missing.
    @discardableResult
    func assertLoopStoredWhatTheOracleExpects(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (events: [LoopStoredPumpEvent], doses: [LoopCachedDose], oracle: LoopDoseStoreOracle) {
        let store = try loop.store()
        let (batches, events, doses) = try IntegrationWait.value("Loop's store to settle", timeout: 120) {
            () -> ([VirtualPumpControl.Batch], [LoopStoredPumpEvent], [LoopCachedDose])? in
            let before = try self.allBatches()
            guard before.allSatisfy(\.completed) else {
                return nil
            }
            let events = try store.pumpEvents()
            let doses = try store.cachedDoses()
            return try self.allBatches() == before ? (before, events, doses) : nil
        }
        XCTAssertEqual(batches.compactMap(\.delegateError), [], "Loop failed to store a batch", file: file, line: line)

        let oracle = LoopDoseStoreOracle(basalSchedule: Self.basalSchedule)
        for batch in batches {
            oracle.addPumpEvents(
                batch.pumpEvents,
                lastReconciliation: batch.lastReconciliation,
                replacePendingEvents: batch.replacePendingEvents,
                now: batch.hostNow
            )
        }
        assertSamePumpEvents(events, oracle.pumpEvents.map(LoopStoredPumpEvent.init), file: file, line: line)
        let predicted = oracle.cachedDoses.map(LoopCachedDose.init)
        assertSameDoses(doses.filter { !$0.isScheduleFill }, predicted.filter { !$0.isScheduleFill }, file: file, line: line)
        assertSameScheduleFill(in: doses, predicted.filter(\.isScheduleFill), file: file, line: line)
        return (events, doses.sorted { $0.startDate < $1.startDate }, oracle)
    }

    private func allBatches() throws -> [VirtualPumpControl.Batch] {
        try earlierLaunchesBatches + XCTUnwrap(control.send(.init(command: .pumpEventBatches)).batches)
    }

    /// Row for row in date order. Both sides take every field from the driver's events, so they agree
    /// to Core Data's rounding.
    private func assertSamePumpEvents(
        _ stored: [LoopStoredPumpEvent],
        _ predicted: [LoopStoredPumpEvent],
        file: StaticString,
        line: UInt
    ) {
        let order: (LoopStoredPumpEvent, LoopStoredPumpEvent) -> Bool = {
            ($0.date, $0.raw.hexadecimalString) < ($1.date, $1.raw.hexadecimalString)
        }
        let stored = stored.sorted(by: order)
        let predicted = predicted.sorted(by: order)
        let report = "Loop stored PumpEvent rows:\n\(stored.map { "  \($0)" }.joined(separator: "\n"))\noracle predicted:\n\(predicted.map { "  \($0)" }.joined(separator: "\n"))"
        guard stored.count == predicted.count else {
            return XCTFail("PumpEvent row counts differ\n\(report)", file: file, line: line)
        }
        for (actual, expected) in zip(stored, predicted) {
            var expected = expected
            if abs(actual.date.timeIntervalSince(expected.date)) < 1e-3 {
                expected.date = actual.date
            }
            for keyPath in [\LoopStoredPumpEvent.value, \.duration, \.deliveredUnits] {
                if let a = actual[keyPath: keyPath], let e = expected[keyPath: keyPath], abs(a - e) < 1e-6 {
                    expected[keyPath: keyPath] = a
                }
            }
            XCTAssertEqual(actual, expected, report, file: file, line: line)
        }
    }

    /// One row per identity, live or soft-deleted, the identities the driver's doses carry.
    private func assertSameDoses(_ stored: [LoopCachedDose], _ predicted: [LoopCachedDose], file: StaticString, line: UInt) {
        let stored = stored.sorted { ($0.startDate, $0.syncIdentifier) < ($1.startDate, $1.syncIdentifier) }
        let predicted = predicted.sorted { ($0.startDate, $0.syncIdentifier) < ($1.startDate, $1.syncIdentifier) }
        let report = "Loop stored doses:\n\(stored.map { "  \($0)" }.joined(separator: "\n"))\noracle predicted:\n\(predicted.map { "  \($0)" }.joined(separator: "\n"))"
        guard stored.map(\.syncIdentifier) == predicted.map(\.syncIdentifier) else {
            return XCTFail("the doses differ\n\(report)", file: file, line: line)
        }
        for (actual, expected) in zip(stored, predicted) {
            var expected = expected
            if abs(actual.startDate.timeIntervalSince(expected.startDate)) < 1e-3 {
                expected.startDate = actual.startDate
            }
            if abs(actual.endDate.timeIntervalSince(expected.endDate)) < 1e-3 {
                expected.endDate = actual.endDate
            }
            if abs(actual.value - expected.value) < 1e-6 {
                expected.value = actual.value
            }
            if let a = actual.programmedTempBasalRate, let e = expected.programmedTempBasalRate, abs(a - e) < 1e-6 {
                expected.programmedTempBasalRate = a
            }
            XCTAssertEqual(actual, expected, report, file: file, line: line)
        }
    }

    /// The first piece starts a day before the save, on Loop's clock where the oracle has the driver's,
    /// so it is compared to a minute. Loop counts a piece at its schedule's rate over whatever it covers.
    private func assertSameScheduleFill(
        in doses: [LoopCachedDose],
        _ predicted: [LoopCachedDose],
        file: StaticString,
        line: UInt
    ) {
        let fill = doses.filter(\.isScheduleFill).sorted { $0.startDate < $1.startDate }
        let predicted = predicted.sorted { $0.startDate < $1.startDate }
        let report = "Loop's schedule fill:\n\(fill.map { "  \($0)" }.joined(separator: "\n"))\noracle predicted:\n\(predicted.map { "  \($0)" }.joined(separator: "\n"))"
        guard fill.count == predicted.count else {
            return XCTFail("schedule fill counts differ\n\(report)", file: file, line: line)
        }
        for (index, (actual, expected)) in zip(fill, predicted).enumerated() {
            XCTAssertEqual(actual.startDate.timeIntervalSince(expected.startDate), 0, accuracy: index == 0 ? 60 : 1e-3, report, file: file, line: line)
            XCTAssertEqual(actual.endDate.timeIntervalSince(expected.endDate), 0, accuracy: 1e-3, report, file: file, line: line)
            XCTAssertEqual(actual.isMutable, false, report, file: file, line: line)
            XCTAssertEqual(actual.isDeleted, expected.isDeleted, report, file: file, line: line)
        }
        let reported = doses.filter { !$0.isScheduleFill && !$0.isBolus && !$0.isDeleted }
        for piece in fill where !piece.isDeleted {
            for dose in reported where min(piece.endDate, dose.endDate).timeIntervalSince(max(piece.startDate, dose.startDate)) > 1 {
                XCTFail("Loop counts its schedule over a dose the driver reported: \(piece) overlaps \(dose)", file: file, line: line)
            }
        }
    }

    static func milliunits(_ units: Double) -> Int {
        Int((units * 1000).rounded())
    }

    static func plist(_ object: Any) throws -> String {
        try String(decoding: PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0), as: UTF8.self)
    }
}

extension LoopStoredPumpEvent {
    /// `PumpEvent.dose`'s setter writes the dose over the event's own date and leaves `duration` at its
    /// default of 0 for an event without one.
    init(_ row: LoopDoseStoreOracle.PumpEventRow) {
        self.init(
            raw: row.raw,
            date: row.dose?.startDate ?? row.date,
            type: row.type?.rawValue,
            mutable: row.mutable,
            doseType: row.dose?.type.rawValue,
            value: row.dose.map(LoopDoseStoreOracle.programmedValue),
            unit: row.dose?.unit.rawValue,
            duration: row.dose.map { $0.endDate.timeIntervalSince($0.startDate) } ?? 0,
            deliveredUnits: row.dose?.deliveredUnits,
            automatic: row.dose?.automatic
        )
    }

    var isBolus: Bool {
        doseType == DoseType.bolus.rawValue
    }
}

extension LoopCachedDose {
    /// CachedInsulinDeliveryObject.create(from:) / update(from:).
    init(_ stored: LoopDoseStoreOracle.StoredDose) {
        let dose = stored.dose
        self.init(
            syncIdentifier: stored.syncIdentifier,
            startDate: dose.startDate,
            endDate: dose.endDate,
            value: stored.value,
            reason: dose.type == .bolus ? 2 : 1,
            isSuspend: dose.type == .suspend,
            isMutable: stored.isMutable,
            isDeleted: stored.isDeleted,
            programmedTempBasalRate: dose.type == .tempBasal ? dose.unitsPerHour : nil,
            automatic: dose.automatic
        )
    }

    var isTempBasal: Bool {
        programmedTempBasalRate != nil
    }
}
