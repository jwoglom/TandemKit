import LoopKit
@testable import TandemKit
import XCTest

/// Drives `syncBasalRateSchedule` against a pump model of Tandem firmware: segment 0 always starts at
/// midnight, no two segments share a start time, and a modify changes only the fields its status
/// mask flags. A modify flagging segment 0's start time is refused even unchanged, as a Mobi did.
///
/// Each case states the profile the pump starts with, the schedule to sync, the exact commands the
/// driver should send, with the fields each modify flags, and the profile those commands produce.
/// The command sequence is asserted against what the driver sent, and separately replayed through
/// the pump model to confirm it reaches the stated end state without a rejection.
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerSyncBasalTests: XCTestCase {
    private typealias Segment = StubIDPPump.Segment
    private typealias Command = StubIDPPump.Command

    private struct Case {
        let name: String
        /// Profile segments on the pump before the sync, in segment-index order.
        let current: [Segment]
        /// Schedule to sync, as (start hour, U/hr) pairs.
        let schedule: [(Double, Double)]
        /// Exact commands the driver is expected to send, in order.
        let commands: [Command]
        /// Profile segments once those commands have been applied.
        let expected: [Segment]
        let file: StaticString
        let line: UInt

        init(
            _ name: String,
            current: [Segment],
            schedule: [(Double, Double)],
            commands: [Command],
            expected: [Segment],
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            self.name = name
            self.current = current
            self.schedule = schedule
            self.commands = commands
            self.expected = expected
            self.file = file
            self.line = line
        }
    }

    // MARK: - Cases

    private let cases: [Case] = [
        Case(
            "schedule already matches the pump",
            current: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 900)],
            schedule: [(0, 1.0), (3, 0.9)],
            commands: [],
            expected: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 900)]
        ),

        // One segment, one field: segment 0 can only change its rate.
        Case(
            "segment 0's rate changes",
            current: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 900)],
            schedule: [(0, 1.1), (3, 0.9)],
            commands: [.modify(segment: 0, basalRate: 1100)],
            expected: [.init(startTime: 0, basalRate: 1100), .init(startTime: 180, basalRate: 900)]
        ),
        Case(
            "a later segment's rate changes",
            current: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 900)],
            schedule: [(0, 1.0), (3, 0.8)],
            commands: [.modify(segment: 1, basalRate: 800)],
            expected: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 800)]
        ),
        Case(
            "a later segment moves later",
            current: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 900)],
            schedule: [(0, 1.0), (5, 0.9)],
            commands: [.modify(segment: 1, startTime: 300)],
            expected: [.init(startTime: 0, basalRate: 1000), .init(startTime: 300, basalRate: 900)]
        ),
        Case(
            "a later segment moves earlier",
            current: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 900)],
            schedule: [(0, 1.0), (1, 0.9)],
            commands: [.modify(segment: 1, startTime: 60)],
            expected: [.init(startTime: 0, basalRate: 1000), .init(startTime: 60, basalRate: 900)]
        ),
        Case(
            "a later segment moves and changes rate",
            current: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 900)],
            schedule: [(0, 1.0), (5, 0.7)],
            commands: [.modify(segment: 1, startTime: 300, basalRate: 700)],
            expected: [.init(startTime: 0, basalRate: 1000), .init(startTime: 300, basalRate: 700)]
        ),

        // Several segments, each flagging its own fields.
        Case(
            "rates change but start times do not",
            current: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 900)],
            schedule: [(0, 1.15), (3, 0.8)],
            commands: [
                .modify(segment: 0, basalRate: 1150),
                .modify(segment: 1, basalRate: 800)
            ],
            expected: [.init(startTime: 0, basalRate: 1150), .init(startTime: 180, basalRate: 800)]
        ),
        Case(
            "segment 0's rate and a later segment's start and rate change",
            current: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 900)],
            schedule: [(0, 1.2), (5, 0.7)],
            commands: [
                .modify(segment: 0, basalRate: 1200),
                .modify(segment: 1, startTime: 300, basalRate: 700)
            ],
            expected: [.init(startTime: 0, basalRate: 1200), .init(startTime: 300, basalRate: 700)]
        ),
        Case(
            // Each write lands on the next segment's start time, so they have to go back to front.
            "every entry shifts later",
            current: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 180, basalRate: 900),
                .init(startTime: 480, basalRate: 800),
                .init(startTime: 540, basalRate: 700)
            ],
            schedule: [(0, 1.0), (4, 0.9), (9, 0.8), (12, 0.7)],
            commands: [
                .modify(segment: 1, startTime: 240),
                .modify(segment: 3, startTime: 720),
                .modify(segment: 2, startTime: 540)
            ],
            expected: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 240, basalRate: 900),
                .init(startTime: 540, basalRate: 800),
                .init(startTime: 720, basalRate: 700)
            ]
        ),
        Case(
            // Nothing blocks anything here, so index order is already safe.
            "every entry shifts earlier",
            current: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 240, basalRate: 900),
                .init(startTime: 540, basalRate: 800),
                .init(startTime: 720, basalRate: 700)
            ],
            schedule: [(0, 1.0), (3, 0.9), (8, 0.8), (9, 0.7)],
            commands: [
                .modify(segment: 1, startTime: 180),
                .modify(segment: 2, startTime: 480),
                .modify(segment: 3, startTime: 540)
            ],
            expected: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 180, basalRate: 900),
                .init(startTime: 480, basalRate: 800),
                .init(startTime: 540, basalRate: 700)
            ]
        ),

        // Shrinking: deletes go first, then the retained segments are modified.
        Case(
            // The Mobi onboarding report: the pump refused this modify while it flagged a start time.
            "three segments at one rate become one faster rate",
            current: [
                .init(startTime: 0, basalRate: 1100),
                .init(startTime: 480, basalRate: 1100),
                .init(startTime: 720, basalRate: 1100)
            ],
            schedule: [(0, 1.2)],
            commands: [
                .delete(segment: 2),
                .delete(segment: 1),
                .modify(segment: 0, basalRate: 1200)
            ],
            expected: [.init(startTime: 0, basalRate: 1200)]
        ),
        Case(
            "schedule shrinks to a single entry at the same rate",
            current: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 900)],
            schedule: [(0, 1.0)],
            commands: [.delete(segment: 1)],
            expected: [.init(startTime: 0, basalRate: 1000)]
        ),
        Case(
            "schedule shrinks and the retained segment changes rate",
            current: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 180, basalRate: 900),
                .init(startTime: 480, basalRate: 800)
            ],
            schedule: [(0, 1.0), (3, 0.85)],
            commands: [
                .delete(segment: 2),
                .modify(segment: 1, basalRate: 850)
            ],
            expected: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 850)]
        ),
        Case(
            "schedule shrinks and the retained segment takes a deleted one's start time",
            current: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 180, basalRate: 900),
                .init(startTime: 480, basalRate: 800)
            ],
            schedule: [(0, 1.0), (8, 0.9)],
            commands: [
                .delete(segment: 2),
                .modify(segment: 1, startTime: 480)
            ],
            expected: [.init(startTime: 0, basalRate: 1000), .init(startTime: 480, basalRate: 900)]
        ),
        Case(
            // Deleting the surplus tail is not enough, because segment 3 survives the delete and
            // still holds the 09:00 that segment 2 has to move onto.
            "schedule shrinks past a retained segment",
            current: [
                .init(startTime: 0, basalRate: 800),
                .init(startTime: 180, basalRate: 700),
                .init(startTime: 480, basalRate: 750),
                .init(startTime: 540, basalRate: 800),
                .init(startTime: 840, basalRate: 750),
                .init(startTime: 960, basalRate: 750),
                .init(startTime: 1380, basalRate: 750)
            ],
            schedule: [(0, 1.15), (3, 0.85), (9, 0.85), (14, 0.75), (20, 0.7)],
            commands: [
                .delete(segment: 6),
                .delete(segment: 5),
                .modify(segment: 0, basalRate: 1150),
                .modify(segment: 1, basalRate: 850),
                .modify(segment: 4, startTime: 1200, basalRate: 700),
                .modify(segment: 3, startTime: 840, basalRate: 750),
                .modify(segment: 2, startTime: 540, basalRate: 850)
            ],
            expected: [
                .init(startTime: 0, basalRate: 1150),
                .init(startTime: 180, basalRate: 850),
                .init(startTime: 540, basalRate: 850),
                .init(startTime: 840, basalRate: 750),
                .init(startTime: 1200, basalRate: 700)
            ]
        ),

        // Growing: creates go after the modifies, with all five fields flagged.
        Case(
            "schedule grows from a single segment",
            current: [.init(startTime: 0, basalRate: 1000)],
            schedule: [(0, 1.2), (6, 0.8)],
            commands: [
                .modify(segment: 0, basalRate: 1200),
                .create(startTime: 360, basalRate: 800)
            ],
            expected: [.init(startTime: 0, basalRate: 1200), .init(startTime: 360, basalRate: 800)]
        ),
        Case(
            "a moved segment frees the start time a created one takes",
            current: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 900)],
            schedule: [(0, 1.0), (1, 0.9), (3, 0.8)],
            commands: [
                .modify(segment: 1, startTime: 60),
                .create(startTime: 180, basalRate: 800)
            ],
            expected: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 60, basalRate: 900),
                .init(startTime: 180, basalRate: 800)
            ]
        ),
        Case(
            "schedule grows",
            current: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 180, basalRate: 900),
                .init(startTime: 480, basalRate: 800)
            ],
            schedule: [(0, 1.0), (5, 0.9), (9, 0.85), (14, 0.8)],
            commands: [
                .modify(segment: 1, startTime: 300),
                .modify(segment: 2, startTime: 540, basalRate: 850),
                .create(startTime: 840, basalRate: 800)
            ],
            expected: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 300, basalRate: 900),
                .init(startTime: 540, basalRate: 850),
                .init(startTime: 840, basalRate: 800)
            ]
        ),
        Case(
            "unsorted schedule grows the profile",
            current: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 180, basalRate: 900)
            ],
            schedule: [(0, 1.0), (8, 0.9), (12, 0.8), (3, 0.95)],
            commands: [
                .modify(segment: 1, basalRate: 950),
                .create(startTime: 480, basalRate: 900),
                .create(startTime: 720, basalRate: 800)
            ],
            expected: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 180, basalRate: 950),
                .init(startTime: 480, basalRate: 900),
                .init(startTime: 720, basalRate: 800)
            ]
        )
    ]

    // MARK: - Tests

    /// The driver sends exactly the stated commands, and the pump ends up in the stated state.
    func testSyncSendsExpectedCommands() {
        for testCase in cases {
            let profile = StubIDPPump(testCase.current)
            let bluetooth = makeStub(profile: profile)
            let result = runSync(bluetooth: bluetooth, schedule: testCase.schedule)

            guard case .success = result else {
                XCTFail("\(testCase.name): expected success, got \(result)", file: testCase.file, line: testCase.line)
                continue
            }

            let sent = bluetooth.sent(SetIDPSegmentRequest.self).compactMap(Command.init)
            XCTAssertEqual(sent, testCase.commands, testCase.name, file: testCase.file, line: testCase.line)
            XCTAssertEqual(profile.segments, testCase.expected, testCase.name, file: testCase.file, line: testCase.line)
        }
    }

    /// Replaying the stated commands against the stated starting profile reaches the stated end
    /// state with every command accepted, independently of what the driver actually produced.
    func testExpectedCommandsProduceExpectedProfile() {
        for testCase in cases {
            let profile = StubIDPPump(testCase.current)

            for command in testCase.commands {
                XCTAssertEqual(
                    profile.apply(command),
                    0,
                    "\(testCase.name): pump would reject \(command)",
                    file: testCase.file,
                    line: testCase.line
                )
            }

            XCTAssertEqual(profile.segments, testCase.expected, testCase.name, file: testCase.file, line: testCase.line)
        }
    }

    /// Every profile of up to four segments, at two rates and start times from 00:00, 03:00, 08:00
    /// and 12:00, synced to every other: the pump ends up holding the schedule, and each modify
    /// flags exactly the fields that differ.
    func testEveryProfileCombinationSyncs() {
        let profiles = Self.profileCombinations(startTimes: [180, 480, 720], basalRates: [800, 1000])

        for current in profiles {
            for target in profiles {
                let profile = StubIDPPump(current)
                let bluetooth = makeStub(profile: profile)
                let schedule = target.map { (Double($0.startTime) / 60, Double($0.basalRate) / 1000) }
                let label = "\(current) -> \(target)"

                guard case .success = runSync(bluetooth: bluetooth, schedule: schedule) else {
                    XCTFail("\(label): sync failed")
                    continue
                }
                XCTAssertEqual(profile.segments, target, label)

                let writes = bluetooth.sent(SetIDPSegmentRequest.self)
                XCTAssertEqual(writes.compactMap(Command.init).count, writes.count, "\(label): unexpected mask")
                if current == target {
                    XCTAssertTrue(writes.isEmpty, "\(label): wrote an unchanged profile")
                }
                for case let .modify(index, startTime, basalRate) in writes.compactMap(Command.init) {
                    let before = current[index]
                    XCTAssertTrue(startTime != nil || basalRate != nil, "\(label): empty modify of \(index)")
                    XCTAssertNotEqual(startTime, before.startTime, "\(label): flagged an unchanged start time")
                    XCTAssertNotEqual(basalRate, before.basalRate, "\(label): flagged an unchanged rate")
                }
            }
        }
    }

    func testEmptyScheduleIsRejectedWithoutTouchingThePump() {
        let bluetooth = makeStub(profile: StubIDPPump([.init(startTime: 0, basalRate: 1000)]))

        XCTAssertThrowsError(try runSync(bluetooth: bluetooth, schedule: []).get())
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }

    func testScheduleOverTheSegmentLimitIsRejectedWithoutTouchingThePump() {
        let bluetooth = makeStub(profile: StubIDPPump([.init(startTime: 0, basalRate: 1000)]))
        let manager = makeManager(bluetooth: bluetooth)
        let schedule = (0 ..< 17).map { (Double($0), 1.0 + Double($0) / 100) }

        let result = runSync(manager, schedule: schedule)

        guard case let .failure(error) = result else {
            return XCTFail("Expected a failure, got \(result)")
        }
        XCTAssertEqual(error as? BasalScheduleSyncError, .tooManyEntries(count: 17, maximum: 16))
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
        XCTAssertFalse(manager.state.hasSyncedBasalRateSchedule)
    }

    func testScheduleNotStartingAtMidnightIsRejectedWithoutTouchingThePump() {
        let bluetooth = makeStub(profile: StubIDPPump([
            .init(startTime: 0, basalRate: 1000),
            .init(startTime: 180, basalRate: 900),
            .init(startTime: 480, basalRate: 800)
        ]))
        let manager = makeManager(bluetooth: bluetooth)

        let result = runSync(manager, schedule: [(6, 0.8), (1, 1.0)])

        guard case let .failure(error) = result else {
            return XCTFail("Expected a failure, got \(result)")
        }
        XCTAssertEqual(error as? BasalScheduleSyncError, .firstEntryNotAtMidnight)
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
        XCTAssertFalse(manager.state.hasSyncedBasalRateSchedule)
    }

    func testSuccessfulSyncIsRecorded() {
        let manager = makeManager(bluetooth: makeStub(profile: StubIDPPump([.init(startTime: 0, basalRate: 1000)])))

        guard case .success = runSync(manager, schedule: [(0, 1.0), (6, 0.8)]) else {
            return XCTFail("Expected success")
        }
        XCTAssertTrue(manager.state.hasSyncedBasalRateSchedule)
    }

    func testSyncThatLeavesThePumpMismatchedIsNotRecorded() {
        let profile = StubIDPPump([.init(startTime: 0, basalRate: 1000)])
        profile.appliesWrites = false
        let manager = makeManager(bluetooth: makeStub(profile: profile))

        guard case .failure = runSync(manager, schedule: [(0, 1.0), (6, 0.8)]) else {
            return XCTFail("Expected failure")
        }
        XCTAssertFalse(manager.state.hasSyncedBasalRateSchedule)
    }

    func testSegmentsAddedToAProfileWithoutTargetOrCorrectionFactorFlagOnlyWhatItHolds() {
        let profile = StubIDPPump([.init(startTime: 0, basalRate: 0)])
        profile.settings = [.CARB_RATIO]
        let bluetooth = makeStub(profile: profile)

        let result = runSync(bluetooth: bluetooth, schedule: [(0, 1.0), (8, 1.2), (11, 1.0)])

        guard case .success = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(profile.segments, [
            .init(startTime: 0, basalRate: 1000),
            .init(startTime: 480, basalRate: 1200),
            .init(startTime: 660, basalRate: 1000)
        ])
        let creates = bluetooth.sent(SetIDPSegmentRequest.self).filter { $0.operation == .createSegment }
        XCTAssertEqual(creates.map(\.idpStatus), Array(repeating: [.START_TIME, .BASAL_RATE, .CARB_RATIO], count: 2))
    }

    func testScheduleAtTheSegmentLimitIsWritten() {
        let profile = StubIDPPump([.init(startTime: 0, basalRate: 1000)])
        let bluetooth = makeStub(profile: profile)
        let schedule = (0 ..< 16).map { (Double($0), 1.0 + Double($0) / 100) }

        let result = runSync(bluetooth: bluetooth, schedule: schedule)

        guard case .success = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(profile.segments.count, 16)
    }

    // MARK: - Harness

    private func makeManager(bluetooth: StubPumpBluetooth) -> TandemPumpManager {
        TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
    }

    private func runSync(
        bluetooth: StubPumpBluetooth,
        schedule: [(Double, Double)]
    ) -> Result<BasalRateSchedule, Error> {
        runSync(makeManager(bluetooth: bluetooth), schedule: schedule)
    }

    private func runSync(
        _ manager: TandemPumpManager,
        schedule: [(Double, Double)]
    ) -> Result<BasalRateSchedule, Error> {
        let items = schedule.map { RepeatingScheduleValue(startTime: $0.0 * 3600, value: $0.1) }

        var result: Result<BasalRateSchedule, Error>?
        let expectation = expectation(description: "Sync basal schedule")
        manager.syncBasalRateSchedule(items: items) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        return result ?? .failure(PumpCommError.requestConstructionFailed(reason: "no completion"))
    }

    /// Segment 0 at midnight plus every ascending subset of `startTimes`, at every rate assignment.
    private static func profileCombinations(startTimes: [Int], basalRates: [Int]) -> [[Segment]] {
        let startSets = (0 ..< (1 << startTimes.count)).map { mask in
            [0] + startTimes.indices.filter { mask & (1 << $0) != 0 }.map { startTimes[$0] }
        }
        return startSets.flatMap { starts in
            starts.reduce([[Segment]()]) { prefixes, start in
                prefixes.flatMap { prefix in
                    basalRates.map { prefix + [Segment(startTime: start, basalRate: $0)] }
                }
            }
        }
    }

    private func makeStub(profile: StubIDPPump) -> StubPumpBluetooth {
        let bluetooth = StubPumpBluetooth()
        profile.install(on: bluetooth)
        return bluetooth
    }
}
