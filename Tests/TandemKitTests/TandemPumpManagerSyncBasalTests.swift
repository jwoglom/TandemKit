import LoopKit
@testable import TandemKit
import XCTest

/// Covers `syncBasalRateSchedule` against a pump model that enforces the constraint real Tandem
/// firmware does: two segments in a profile may never hold the same start time. Applying a
/// schedule segment-by-segment in index order violates that whenever a segment moves onto a start
/// time the following segment still occupies, which is how a shrinking schedule used to fail with
/// `status: 1` after having already written part of the profile.
@available(macOS 13.0, iOS 14.0, *) final class TandemPumpManagerSyncBasalTests: XCTestCase {
    /// Minimal stand-in for a single insulin delivery profile on the pump.
    private final class FakeProfile {
        struct Segment {
            var startTime: Int
            var basalRate: Int
        }

        /// Indexed by segment index, mirroring how the pump addresses them.
        private(set) var segments: [Segment]

        init(segments: [Segment]) {
            self.segments = segments
        }

        /// Applies a write the way the pump does, returning the status byte it would answer with.
        func apply(_ request: SetIDPSegmentRequest) -> Int {
            switch request.operation {
            case .modifySegmentId:
                guard request.segmentIndex < segments.count else { return 1 }
                if collides(startTime: request.profileStartTime, excluding: request.segmentIndex) { return 1 }
                segments[request.segmentIndex].startTime = request.profileStartTime
                segments[request.segmentIndex].basalRate = request.profileBasalRate
                return 0
            case .createSegment:
                if collides(startTime: request.profileStartTime, excluding: nil) { return 1 }
                segments.append(Segment(startTime: request.profileStartTime, basalRate: request.profileBasalRate))
                return 0
            case .deleteSegmentId:
                guard request.segmentIndex != 0, request.segmentIndex < segments.count else { return 1 }
                // The pump only ever gets asked to drop the tail, so removing in place keeps the
                // remaining indices stable exactly as it does.
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

    private func sync(
        profile: FakeProfile,
        items: [RepeatingScheduleValue<Double>]
    ) -> Result<BasalRateSchedule, Error> {
        let bluetooth = makeStub(profile: profile)
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)

        var result: Result<BasalRateSchedule, Error>?
        let expectation = expectation(description: "Sync basal schedule")
        manager.syncBasalRateSchedule(items: items) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        return result ?? .failure(PumpCommError.requestConstructionFailed(reason: "no completion"))
    }

    private func item(hour: Double, rate: Double) -> RepeatingScheduleValue<Double> {
        RepeatingScheduleValue(startTime: hour * 3600, value: rate)
    }

    /// The reported failure: seven segments collapse to five. Deleting the two surplus tail
    /// segments is not enough, because the entry that has to move from 08:00 to 09:00 lands on a
    /// start time a segment that survives the delete still holds.
    func testShrinkingScheduleReordersWritesAroundStartTimeCollisions() {
        let profile = FakeProfile(segments: [
            .init(startTime: 0, basalRate: 800),
            .init(startTime: 180, basalRate: 700),
            .init(startTime: 480, basalRate: 750),
            .init(startTime: 540, basalRate: 800),
            .init(startTime: 840, basalRate: 750),
            .init(startTime: 960, basalRate: 750),
            .init(startTime: 1380, basalRate: 750)
        ])

        let result = sync(profile: profile, items: [
            item(hour: 0, rate: 1.15),
            item(hour: 3, rate: 0.85),
            item(hour: 9, rate: 0.85),
            item(hour: 14, rate: 0.75),
            item(hour: 20, rate: 0.7)
        ])

        guard case .success = result else {
            return XCTFail("Expected success, received: \(result)")
        }

        XCTAssertEqual(profile.segments.map(\.startTime), [0, 180, 540, 840, 1200])
        XCTAssertEqual(profile.segments.map(\.basalRate), [1150, 850, 850, 750, 700])
    }

    /// Every segment slides later by an hour, so each write lands on the next segment's start time
    /// until the schedule is applied back to front.
    func testScheduleShiftedLaterAppliesBackToFront() {
        let profile = FakeProfile(segments: [
            .init(startTime: 0, basalRate: 1000),
            .init(startTime: 180, basalRate: 900),
            .init(startTime: 480, basalRate: 800),
            .init(startTime: 540, basalRate: 700)
        ])

        let result = sync(profile: profile, items: [
            item(hour: 0, rate: 1.0),
            item(hour: 4, rate: 0.9),
            item(hour: 9, rate: 0.8),
            item(hour: 12, rate: 0.7)
        ])

        guard case .success = result else {
            return XCTFail("Expected success, received: \(result)")
        }

        XCTAssertEqual(profile.segments.map(\.startTime), [0, 240, 540, 720])
        XCTAssertEqual(profile.segments.map(\.basalRate), [1000, 900, 800, 700])
    }

    /// Growing the schedule appends segments; the created segment must not land on a start time a
    /// segment still waiting to move occupies.
    func testGrowingScheduleCreatesSegmentsWithoutCollisions() {
        let profile = FakeProfile(segments: [
            .init(startTime: 0, basalRate: 1000),
            .init(startTime: 180, basalRate: 900),
            .init(startTime: 480, basalRate: 800)
        ])

        let result = sync(profile: profile, items: [
            item(hour: 0, rate: 1.0),
            item(hour: 5, rate: 0.9),
            item(hour: 9, rate: 0.85),
            item(hour: 14, rate: 0.8)
        ])

        guard case .success = result else {
            return XCTFail("Expected success, received: \(result)")
        }

        XCTAssertEqual(profile.segments.map(\.startTime), [0, 300, 540, 840])
        XCTAssertEqual(profile.segments.map(\.basalRate), [1000, 900, 850, 800])
    }

    /// A schedule the pump already matches must not produce any writes at all.
    func testUnchangedScheduleSendsNoSegmentWrites() {
        let profile = FakeProfile(segments: [
            .init(startTime: 0, basalRate: 1000),
            .init(startTime: 180, basalRate: 900)
        ])
        let bluetooth = makeStub(profile: profile)
        let manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)

        let expectation = expectation(description: "Sync basal schedule")
        manager.syncBasalRateSchedule(items: [
            item(hour: 0, rate: 1.0),
            item(hour: 3, rate: 0.9)
        ]) { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 5)

        XCTAssertFalse(bluetooth.didSend(SetIDPSegmentRequest.self))
    }
}
