import LoopKit
@testable import TandemKit
import XCTest

/// Drives `syncBasalRateSchedule` against a pump model that enforces the constraint real Tandem
/// firmware does: two segments in a profile may never hold the same start time.
///
/// Each case states the profile the pump starts with, the schedule to sync, the exact commands the
/// driver should send, and the profile those commands produce. The command sequence is asserted
/// against what the driver sent, and separately replayed through the pump model to confirm it
/// reaches the stated end state without a rejection.
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerSyncBasalTests: XCTestCase {
    private struct Segment: Equatable, CustomStringConvertible {
        var startTime: Int
        var basalRate: Int

        var description: String { "\(startTime)/\(basalRate)" }
    }

    private enum Command: Equatable, CustomStringConvertible {
        case modify(segment: Int, startTime: Int, basalRate: Int)
        case create(startTime: Int, basalRate: Int)
        case delete(segment: Int)

        init?(_ request: SetIDPSegmentRequest) {
            switch request.operation {
            case .modifySegmentId:
                self = .modify(
                    segment: request.segmentIndex,
                    startTime: request.profileStartTime,
                    basalRate: request.profileBasalRate
                )
            case .createSegment:
                self = .create(startTime: request.profileStartTime, basalRate: request.profileBasalRate)
            case .deleteSegmentId:
                self = .delete(segment: request.segmentIndex)
            case .none:
                return nil
            }
        }

        var description: String {
            switch self {
            case let .modify(segment, startTime, basalRate): "modify(\(segment) -> \(startTime)/\(basalRate))"
            case let .create(startTime, basalRate): "create(\(startTime)/\(basalRate))"
            case let .delete(segment): "delete(\(segment))"
            }
        }
    }

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

    /// Minimal stand-in for a single insulin delivery profile on the pump.
    private final class FakeProfile {
        private(set) var segments: [Segment]

        init(_ segments: [Segment]) {
            self.segments = segments
        }

        /// Applies a command the way the pump does, returning the status byte it would answer with.
        func apply(_ command: Command) -> Int {
            switch command {
            case let .modify(index, startTime, basalRate):
                guard index < segments.count, !collides(startTime: startTime, excluding: index) else { return 1 }
                segments[index] = Segment(startTime: startTime, basalRate: basalRate)
                return 0
            case let .create(startTime, basalRate):
                guard !collides(startTime: startTime, excluding: nil) else { return 1 }
                segments.append(Segment(startTime: startTime, basalRate: basalRate))
                return 0
            case let .delete(index):
                guard index != 0, index < segments.count else { return 1 }
                segments.remove(at: index)
                return 0
            }
        }

        private func collides(startTime: Int, excluding index: Int?) -> Bool {
            segments.enumerated().contains { offset, segment in
                offset != index && segment.startTime == startTime
            }
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
        Case(
            "rates change but start times do not",
            current: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 900)],
            schedule: [(0, 1.15), (3, 0.8)],
            commands: [
                .modify(segment: 0, startTime: 0, basalRate: 1150),
                .modify(segment: 1, startTime: 180, basalRate: 800)
            ],
            expected: [.init(startTime: 0, basalRate: 1150), .init(startTime: 180, basalRate: 800)]
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
                .modify(segment: 1, startTime: 240, basalRate: 900),
                .modify(segment: 3, startTime: 720, basalRate: 700),
                .modify(segment: 2, startTime: 540, basalRate: 800)
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
                .modify(segment: 1, startTime: 180, basalRate: 900),
                .modify(segment: 2, startTime: 480, basalRate: 800),
                .modify(segment: 3, startTime: 540, basalRate: 700)
            ],
            expected: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 180, basalRate: 900),
                .init(startTime: 480, basalRate: 800),
                .init(startTime: 540, basalRate: 700)
            ]
        ),
        Case(
            // The reported failure: deleting the surplus tail is not enough, because segment 3
            // survives the delete and still holds the 09:00 that segment 2 has to move onto.
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
                .modify(segment: 0, startTime: 0, basalRate: 1150),
                .modify(segment: 1, startTime: 180, basalRate: 850),
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
        Case(
            "schedule shrinks to a single entry",
            current: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 180, basalRate: 900),
                .init(startTime: 480, basalRate: 800)
            ],
            schedule: [(0, 1.25)],
            commands: [
                .delete(segment: 2),
                .delete(segment: 1),
                .modify(segment: 0, startTime: 0, basalRate: 1250)
            ],
            expected: [.init(startTime: 0, basalRate: 1250)]
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
                .modify(segment: 1, startTime: 300, basalRate: 900),
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
                .modify(segment: 1, startTime: 180, basalRate: 950),
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
            let profile = FakeProfile(testCase.current)
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
            let profile = FakeProfile(testCase.current)

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

    func testEmptyScheduleIsRejectedWithoutTouchingThePump() {
        let bluetooth = makeStub(profile: FakeProfile([.init(startTime: 0, basalRate: 1000)]))

        XCTAssertThrowsError(try runSync(bluetooth: bluetooth, schedule: []).get())
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }

    // MARK: - Harness

    private func runSync(
        bluetooth: StubPumpBluetooth,
        schedule: [(Double, Double)]
    ) -> Result<BasalRateSchedule, Error> {
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)
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

    private func makeStub(profile: FakeProfile) -> StubPumpBluetooth {
        let bluetooth = StubPumpBluetooth()

        bluetooth.stub(ProfileStatusRequest.self, with: ProfileStatusResponse(
            cargo: Data([0x01, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])
        ))
        bluetooth.stub(IDPSettingsRequest.self) { _ in
            var cargo = Data([0x00])
            cargo.append(contentsOf: Array("Profile".utf8))
            cargo.append(contentsOf: [UInt8](repeating: 0, count: 16 - 7))
            cargo.append(UInt8(profile.segments.count))
            cargo.append(contentsOf: [0x2C, 0x01]) // insulin duration 300
            cargo.append(contentsOf: [0x80, 0x3E]) // max bolus 16000
            cargo.append(0x01)
            return IDPSettingsResponse(cargo: cargo)
        }
        bluetooth.stub(IDPSegmentRequest.self) { request in
            guard let request = request as? IDPSegmentRequest,
                  request.segmentIndex < profile.segments.count
            else {
                return nil
            }
            let segment = profile.segments[request.segmentIndex]
            return IDPSegmentResponse(
                idpId: 0,
                segmentIndex: request.segmentIndex,
                profileStartTime: segment.startTime,
                profileBasalRate: segment.basalRate,
                profileCarbRatio: 10000,
                profileTargetBG: 110,
                profileISF: 74,
                idpStatusId: 15
            )
        }
        bluetooth.stub(SetIDPSegmentRequest.self) { request in
            guard let request = request as? SetIDPSegmentRequest, let command = Command(request) else { return nil }
            return SetIDPSegmentResponse(status: profile.apply(command), unknown: 0)
        }

        return bluetooth
    }
}
