import LoopKit
@testable import TandemKit
import XCTest

/// Drives `syncBasalRateSchedule` against a pump model that enforces the constraint real Tandem
/// firmware does: two segments in a profile may never hold the same start time.
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerSyncBasalTests: XCTestCase {
    private struct Segment: Equatable {
        var startTime: Int
        var basalRate: Int
    }

    private struct Case {
        let name: String
        /// Profile segments on the pump, in segment-index order.
        let existing: [Segment]
        /// Schedule to sync, as (start hour, U/hr) pairs.
        let schedule: [(Double, Double)]
        /// Expected segments once the sync completes.
        let expected: [Segment]
        let file: StaticString
        let line: UInt

        init(
            _ name: String,
            existing: [Segment],
            schedule: [(Double, Double)],
            expected: [Segment],
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            self.name = name
            self.existing = existing
            self.schedule = schedule
            self.expected = expected
            self.file = file
            self.line = line
        }
    }

    /// Minimal stand-in for a single insulin delivery profile on the pump.
    private final class FakeProfile {
        private(set) var segments: [Segment]

        init(segments: [Segment]) {
            self.segments = segments
        }

        /// Applies a write the way the pump does, returning the status byte it would answer with.
        func apply(_ request: SetIDPSegmentRequest) -> Int {
            switch request.operation {
            case .modifySegmentId:
                guard request.segmentIndex < segments.count,
                      !collides(startTime: request.profileStartTime, excluding: request.segmentIndex)
                else {
                    return 1
                }
                segments[request.segmentIndex] = Segment(
                    startTime: request.profileStartTime,
                    basalRate: request.profileBasalRate
                )
                return 0
            case .createSegment:
                guard !collides(startTime: request.profileStartTime, excluding: nil) else { return 1 }
                segments.append(Segment(startTime: request.profileStartTime, basalRate: request.profileBasalRate))
                return 0
            case .deleteSegmentId:
                guard request.segmentIndex != 0, request.segmentIndex < segments.count else { return 1 }
                segments.remove(at: request.segmentIndex)
                return 0
            case .none:
                return 1
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
            "schedule unchanged",
            existing: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 900)],
            schedule: [(0, 1.0), (3, 0.9)],
            expected: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 900)]
        ),
        Case(
            "rates change but start times do not",
            existing: [.init(startTime: 0, basalRate: 1000), .init(startTime: 180, basalRate: 900)],
            schedule: [(0, 1.15), (3, 0.8)],
            expected: [.init(startTime: 0, basalRate: 1150), .init(startTime: 180, basalRate: 800)]
        ),
        Case(
            // Each write lands on the next segment's start time, so they have to go back to front.
            "every entry shifts later",
            existing: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 180, basalRate: 900),
                .init(startTime: 480, basalRate: 800),
                .init(startTime: 540, basalRate: 700)
            ],
            schedule: [(0, 1.0), (4, 0.9), (9, 0.8), (12, 0.7)],
            expected: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 240, basalRate: 900),
                .init(startTime: 540, basalRate: 800),
                .init(startTime: 720, basalRate: 700)
            ]
        ),
        Case(
            "every entry shifts earlier",
            existing: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 240, basalRate: 900),
                .init(startTime: 540, basalRate: 800),
                .init(startTime: 720, basalRate: 700)
            ],
            schedule: [(0, 1.0), (3, 0.9), (8, 0.8), (9, 0.7)],
            expected: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 180, basalRate: 900),
                .init(startTime: 480, basalRate: 800),
                .init(startTime: 540, basalRate: 700)
            ]
        ),
        Case(
            // The reported failure: deleting the surplus tail is not enough, because a segment that
            // survives the delete still blocks the entry moving from 08:00 to 09:00.
            "schedule shrinks past a retained segment",
            existing: [
                .init(startTime: 0, basalRate: 800),
                .init(startTime: 180, basalRate: 700),
                .init(startTime: 480, basalRate: 750),
                .init(startTime: 540, basalRate: 800),
                .init(startTime: 840, basalRate: 750),
                .init(startTime: 960, basalRate: 750),
                .init(startTime: 1380, basalRate: 750)
            ],
            schedule: [(0, 1.15), (3, 0.85), (9, 0.85), (14, 0.75), (20, 0.7)],
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
            existing: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 180, basalRate: 900),
                .init(startTime: 480, basalRate: 800)
            ],
            schedule: [(0, 1.25)],
            expected: [.init(startTime: 0, basalRate: 1250)]
        ),
        Case(
            "schedule grows, created segment must not collide",
            existing: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 180, basalRate: 900),
                .init(startTime: 480, basalRate: 800)
            ],
            schedule: [(0, 1.0), (5, 0.9), (9, 0.85), (14, 0.8)],
            expected: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 300, basalRate: 900),
                .init(startTime: 540, basalRate: 850),
                .init(startTime: 840, basalRate: 800)
            ]
        ),
        Case(
            "schedule grows onto start times still occupied",
            existing: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 180, basalRate: 900)
            ],
            schedule: [(0, 1.0), (8, 0.9), (12, 0.8), (3, 0.95)],
            expected: [
                .init(startTime: 0, basalRate: 1000),
                .init(startTime: 180, basalRate: 950),
                .init(startTime: 480, basalRate: 900),
                .init(startTime: 720, basalRate: 800)
            ]
        )
    ]

    // MARK: - Tests

    func testSyncAppliesScheduleWithoutStartTimeCollisions() {
        for testCase in cases {
            let profile = FakeProfile(segments: testCase.existing)
            let result = sync(profile: profile, schedule: testCase.schedule)

            guard case .success = result else {
                XCTFail(
                    "\(testCase.name): expected success, received \(result)",
                    file: testCase.file,
                    line: testCase.line
                )
                continue
            }

            XCTAssertEqual(
                profile.segments,
                testCase.expected,
                testCase.name,
                file: testCase.file,
                line: testCase.line
            )
        }
    }

    /// A schedule the pump already matches must not produce any writes at all.
    func testUnchangedScheduleSendsNoSegmentWrites() {
        let profile = FakeProfile(segments: [
            .init(startTime: 0, basalRate: 1000),
            .init(startTime: 180, basalRate: 900)
        ])
        let bluetooth = makeStub(profile: profile)

        XCTAssertNoThrow(try runSync(bluetooth: bluetooth, schedule: [(0, 1.0), (3, 0.9)]).get())
        XCTAssertFalse(bluetooth.didSend(SetIDPSegmentRequest.self))
    }

    func testEmptyScheduleIsRejectedWithoutTouchingThePump() {
        let profile = FakeProfile(segments: [.init(startTime: 0, basalRate: 1000)])
        let bluetooth = makeStub(profile: profile)

        XCTAssertThrowsError(try runSync(bluetooth: bluetooth, schedule: []).get())
        XCTAssertTrue(bluetooth.sentMessages.isEmpty)
    }

    // MARK: - Harness

    private func sync(profile: FakeProfile, schedule: [(Double, Double)]) -> Result<BasalRateSchedule, Error> {
        runSync(bluetooth: makeStub(profile: profile), schedule: schedule)
    }

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
            guard let request = request as? SetIDPSegmentRequest else { return nil }
            return SetIDPSegmentResponse(status: profile.apply(request), unknown: 0)
        }

        return bluetooth
    }
}
