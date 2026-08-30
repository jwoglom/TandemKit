import Foundation
@testable import TandemKit
import XCTest

/// Covers the backfill decision logic on its own: what to read on a tick, how far back to read,
/// and how far back events may be reported.
final class HistoryBackfillPlannerTests: XCTestCase {
    private let serial: UInt32 = 123_456

    private func bookkeeping(watermark: UInt32?, firstSeenFloor: Date? = nil) -> HistoryBackfillState {
        HistoryBackfillState(pumpSerial: serial, watermark: watermark, firstSeenFloor: firstSeenFloor)
    }

    // MARK: - Incremental

    func testIncrementalRangeStartsAboveTheWatermark() {
        let plan = HistoryBackfillPlanner.plan(
            firstSequenceNum: 1,
            lastSequenceNum: 120,
            watermark: 100,
            sessionCovered: 50 ... 100,
            isDeepTargetCovered: true
        )

        XCTAssertEqual(plan.incremental, 101 ... 120)
        XCTAssertNil(plan.deep)
        XCTAssertTrue(plan.gaps.isEmpty)
    }

    func testNothingIncrementalWhenTheWatermarkIsCurrent() {
        let plan = HistoryBackfillPlanner.plan(
            firstSequenceNum: 1,
            lastSequenceNum: 100,
            watermark: 100,
            sessionCovered: 50 ... 100,
            isDeepTargetCovered: true
        )

        XCTAssertNil(plan.incremental)
        XCTAssertTrue(plan.isEmpty)
    }

    /// A pump whose log was erased reports a last sequence below the watermark. Treating that as
    /// an incremental range would build an inverted range; there is simply nothing new to read.
    func testErasedLogDoesNotProduceAnInvertedRange() {
        let plan = HistoryBackfillPlanner.plan(
            firstSequenceNum: 1,
            lastSequenceNum: 10,
            watermark: 100,
            sessionCovered: 50 ... 100,
            isDeepTargetCovered: true
        )

        XCTAssertNil(plan.incremental)
    }

    /// After a relaunch the watermark survives but the session store is empty. The tick must
    /// read only what is new — treating the watermark's span as store coverage would report the
    /// whole of it as one hole and re-read history the driver deliberately did not keep.
    func testRelaunchReadsOnlyNewEntriesDespiteAnEmptySessionStore() {
        let plan = HistoryBackfillPlanner.plan(
            firstSequenceNum: 1,
            lastSequenceNum: 910,
            watermark: 900,
            sessionCovered: nil,
            storeGaps: [],
            isDeepTargetCovered: false
        )

        XCTAssertEqual(plan.incremental, 901 ... 910)
        XCTAssertTrue(plan.gaps.isEmpty)
        XCTAssertNil(plan.deep, "The walk backward needs a floor from this session first")
    }

    // MARK: - First contact

    /// A pump nothing has been read from opens with one slice of the newest entries, not with a
    /// single request covering its entire log.
    func testFirstTickTakesOneSliceOfTheNewestEntries() {
        let plan = HistoryBackfillPlanner.plan(
            firstSequenceNum: 1,
            lastSequenceNum: 5000,
            watermark: nil,
            isDeepTargetCovered: false
        )

        XCTAssertEqual(plan.incremental, 4746 ... 5000)
        XCTAssertEqual(plan.incremental?.count, Int(HistoryBackfillPlanner.maxDeepSliceSize))
        XCTAssertNil(plan.deep, "The walk backward starts on the next tick, from a known floor")
        XCTAssertFalse(plan.isDeepBackfillComplete)
    }

    func testFirstTickOnAShortLogTakesWhateverExists() {
        let plan = HistoryBackfillPlanner.plan(
            firstSequenceNum: 8,
            lastSequenceNum: 20,
            watermark: nil,
            isDeepTargetCovered: false
        )

        XCTAssertEqual(plan.incremental, 8 ... 20)
    }

    // MARK: - Deep backfill

    func testDeepSliceWalksBackwardFromTheLowestFetchedEntry() {
        let plan = HistoryBackfillPlanner.plan(
            firstSequenceNum: 1,
            lastSequenceNum: 5000,
            watermark: 5000,
            sessionCovered: 4746 ... 5000,
            isDeepTargetCovered: false
        )

        XCTAssertEqual(plan.deep, 4491 ... 4745)
        XCTAssertFalse(plan.isDeepBackfillComplete)
    }

    func testDeepSliceIsClampedToTheOldestEntryThePumpHolds() {
        let plan = HistoryBackfillPlanner.plan(
            firstSequenceNum: 4700,
            lastSequenceNum: 5000,
            watermark: 5000,
            sessionCovered: 4746 ... 5000,
            isDeepTargetCovered: false
        )

        XCTAssertEqual(plan.deep, 4700 ... 4745)
    }

    func testDeepBackfillStopsOnceTheTargetDateIsCovered() {
        let plan = HistoryBackfillPlanner.plan(
            firstSequenceNum: 1,
            lastSequenceNum: 5000,
            watermark: 5000,
            sessionCovered: 4746 ... 5000,
            isDeepTargetCovered: true
        )

        XCTAssertNil(plan.deep)
        XCTAssertTrue(plan.isDeepBackfillComplete)
    }

    func testDeepBackfillStopsAtThePumpsOldestEntry() {
        let plan = HistoryBackfillPlanner.plan(
            firstSequenceNum: 4746,
            lastSequenceNum: 5000,
            watermark: 5000,
            sessionCovered: 4746 ... 5000,
            isDeepTargetCovered: false
        )

        XCTAssertNil(plan.deep, "There is nothing older to read, however short of the target it is")
        XCTAssertTrue(plan.isDeepBackfillComplete)
    }

    // MARK: - Gaps

    func testGapsAreClampedToWhatThePumpStillHolds() {
        let plan = HistoryBackfillPlanner.plan(
            firstSequenceNum: 100,
            lastSequenceNum: 300,
            watermark: 300,
            sessionCovered: 50 ... 300,
            storeGaps: [10 ... 20, 150 ... 160, 290 ... 400],
            isDeepTargetCovered: true
        )

        XCTAssertEqual(plan.gaps, [150 ... 160, 290 ... 300], "A pruned or unwritten range is not chased")
    }

    // MARK: - Deep fetch target

    func testDeepFetchTargetCoversTheLongestDIA() {
        let now = Date()
        let target = HistoryBackfillPlanner.deepFetchTarget(firstSeenFloor: nil, now: now)

        XCTAssertEqual(target.timeIntervalSince(now), -HistoryBackfillPlanner.deepFetchLookback, accuracy: 1)
        XCTAssertGreaterThanOrEqual(HistoryBackfillPlanner.deepFetchLookback, .hours(6))
    }

    /// Reading below first sight would import a replacement pump's pre-service history.
    func testDeepFetchTargetNeverReadsBelowTheFirstSeenFloor() {
        let now = Date()
        let floor = now.addingTimeInterval(-.hours(2))

        XCTAssertEqual(
            HistoryBackfillPlanner.deepFetchTarget(firstSeenFloor: floor, now: now),
            floor
        )
    }

    func testDeepFetchTargetIgnoresAFloorOlderThanTheLookback() {
        let now = Date()
        let floor = now.addingTimeInterval(-.hours(72))

        XCTAssertEqual(
            HistoryBackfillPlanner.deepFetchTarget(firstSeenFloor: floor, now: now).timeIntervalSince(now),
            -HistoryBackfillPlanner.deepFetchLookback,
            accuracy: 1
        )
    }

    // MARK: - Emit floor

    func testEmitFloorTakesTheLaterOfHostAndPumpFloors() {
        let older = Date(timeIntervalSinceReferenceDate: 1000)
        let newer = Date(timeIntervalSinceReferenceDate: 2000)

        XCTAssertEqual(
            HistoryBackfillPlanner.emitFloor(
                hostFloor: older,
                bookkeeping: bookkeeping(watermark: 2, firstSeenFloor: newer)
            ),
            newer
        )
        XCTAssertEqual(
            HistoryBackfillPlanner.emitFloor(
                hostFloor: newer,
                bookkeeping: bookkeeping(watermark: 2, firstSeenFloor: older)
            ),
            newer
        )
    }

    func testEmitFloorFallsBackToWhicheverSideIsKnown() {
        let date = Date(timeIntervalSinceReferenceDate: 1000)

        XCTAssertEqual(HistoryBackfillPlanner.emitFloor(hostFloor: date, bookkeeping: nil), date)
        XCTAssertEqual(
            HistoryBackfillPlanner.emitFloor(
                hostFloor: nil,
                bookkeeping: bookkeeping(watermark: 2, firstSeenFloor: date)
            ),
            date
        )
        XCTAssertNil(HistoryBackfillPlanner.emitFloor(hostFloor: nil, bookkeeping: nil))
    }

    // MARK: - Bookkeeping identity

    /// A replacement pump's sequence numbers describe its own history, not this driver's reading
    /// of it, and its log may predate entering service. Both are handled by starting over.
    func testReplacementPumpDiscardsBookkeepingAndFloorsAtFirstSight() {
        let now = Date()
        let previous = bookkeeping(watermark: 100, firstSeenFloor: .distantPast)

        let fresh = previous.matching(pumpSerial: 999, now: now)

        XCTAssertEqual(fresh.pumpSerial, 999)
        XCTAssertNil(fresh.watermark, "The old pump's sequence numbers say nothing about this one")
        XCTAssertEqual(
            fresh.firstSeenFloor?.timeIntervalSince(now),
            -HistoryBackfillPlanner.deepFetchLookback,
            "Only insulin that can still be acting is imported from a pump seen for the first time"
        )
    }

    /// Re-pairing the same pump keeps its original floor, so the gap while the app was away is
    /// still eligible to be reported.
    func testRepairedPumpKeepsItsBookkeeping() {
        let floor = Date(timeIntervalSinceReferenceDate: 1000)
        let previous = bookkeeping(watermark: 100, firstSeenFloor: floor)

        XCTAssertEqual(previous.matching(pumpSerial: serial, now: Date()), previous)
    }

    func testWatermarkOnlyEverAdvances() {
        var state = HistoryBackfillState(firstSeenPumpSerial: serial)
        XCTAssertNil(state.watermark)

        state.advanceWatermark(through: 200)
        XCTAssertEqual(state.watermark, 200)

        state.advanceWatermark(through: 240)
        XCTAssertEqual(state.watermark, 240)

        // A pump whose log was erased reports lower sequence numbers; forgetting the high-water
        // mark would re-read history already accounted for.
        state.advanceWatermark(through: 60)
        XCTAssertEqual(state.watermark, 240)
    }

    /// A relaunch onto a pump that has written nothing since the watermark still needs a read:
    /// the walk backward has no frontier to step down from until something lands in the empty
    /// session store, so without this the store would stay empty however long the pump idled.
    func testColdStartReadsTheNewestSliceEvenWithNothingNewToFetch() {
        let plan = HistoryBackfillPlanner.plan(
            firstSequenceNum: 1,
            lastSequenceNum: 900,
            watermark: 900,
            sessionCovered: nil,
            isDeepTargetCovered: false
        )

        XCTAssertEqual(plan.incremental, (900 - HistoryBackfillPlanner.maxDeepSliceSize + 1) ... 900)
        XCTAssertFalse(plan.isEmpty, "A tick that read nothing here would never start the walk")
    }

    /// Once this session has a frontier, an up-to-date watermark really does mean no read.
    func testNothingIsReadWhenTheSessionAlreadyHasAFrontierAndTheWatermarkIsCurrent() {
        let plan = HistoryBackfillPlanner.plan(
            firstSequenceNum: 1,
            lastSequenceNum: 900,
            watermark: 900,
            sessionCovered: 1 ... 900,
            isDeepTargetCovered: false
        )

        XCTAssertNil(plan.incremental)
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: - Log erase

    /// The pump can never hold less than has already been read from it unless its log was
    /// erased and the counter restarted. The watermark is then meaningless as a read position,
    /// but the pump is the same one in the same service, so its floor still stands.
    func testWatermarkAboveThePumpsNewestEntryIsDropped() {
        let floor = Date(timeIntervalSinceReferenceDate: 1000)
        let stale = bookkeeping(watermark: 900, firstSeenFloor: floor)

        let reset = stale.resettingWatermarkIfAbove(lastSequenceNum: 50)

        XCTAssertNil(reset.watermark)
        XCTAssertEqual(reset.firstSeenFloor, floor)
        XCTAssertEqual(reset.pumpSerial, stale.pumpSerial)
    }

    func testWatermarkIsKeptWhenThePumpStillHoldsIt() {
        let state = bookkeeping(watermark: 900)

        XCTAssertEqual(state.resettingWatermarkIfAbove(lastSequenceNum: 900), state)
        XCTAssertEqual(state.resettingWatermarkIfAbove(lastSequenceNum: 910), state)
        XCTAssertEqual(bookkeeping(watermark: nil).resettingWatermarkIfAbove(lastSequenceNum: 5).watermark, nil)
    }

    /// Without the reset the same comparison that means "nothing new to read" on an idle pump
    /// would mean it forever on an erased one.
    func testAnErasedLogWouldOtherwisePlanNoReadAtAll() {
        let stale = bookkeeping(watermark: 900)

        let blocked = HistoryBackfillPlanner.plan(
            firstSequenceNum: 1,
            lastSequenceNum: 50,
            watermark: stale.watermark,
            sessionCovered: 1 ... 50,
            isDeepTargetCovered: false
        )
        XCTAssertNil(blocked.incremental, "This is the state the reset exists to break out of")

        let afterReset = HistoryBackfillPlanner.plan(
            firstSequenceNum: 1,
            lastSequenceNum: 50,
            watermark: stale.resettingWatermarkIfAbove(lastSequenceNum: 50).watermark,
            sessionCovered: 1 ... 50,
            isDeepTargetCovered: false
        )
        XCTAssertEqual(afterReset.incremental, 1 ... 50)
    }

    // MARK: - Deep slices

    func testDeepSliceStepsDownOneChunkFromTheSessionFloor() {
        let slice = HistoryBackfillPlanner.deepSlice(
            firstSequenceNum: 1,
            sessionCovered: 1000 ... 2000,
            isDeepTargetCovered: false
        )

        XCTAssertEqual(slice, (1000 - HistoryBackfillPlanner.maxDeepSliceSize) ... 999)
    }

    func testDeepSliceIsClampedToThePumpsOldestEntry() {
        XCTAssertEqual(
            HistoryBackfillPlanner.deepSlice(
                firstSequenceNum: 900,
                sessionCovered: 1000 ... 2000,
                isDeepTargetCovered: false
            ),
            900 ... 999
        )
    }

    func testNoDeepSliceOnceTheTargetIsCoveredOrTheLogIsExhausted() {
        XCTAssertNil(HistoryBackfillPlanner.deepSlice(
            firstSequenceNum: 1,
            sessionCovered: 1000 ... 2000,
            isDeepTargetCovered: true
        ))
        XCTAssertNil(HistoryBackfillPlanner.deepSlice(
            firstSequenceNum: 1000,
            sessionCovered: 1000 ... 2000,
            isDeepTargetCovered: false
        ))
        XCTAssertNil(
            HistoryBackfillPlanner.deepSlice(firstSequenceNum: 1, sessionCovered: nil, isDeepTargetCovered: false),
            "The walk needs a frontier to step down from"
        )
    }

    /// The walk covers the whole lookback within a tick, so the cap must leave room for far more
    /// entries than a pump writes in that window.
    func testThePerTickSliceCapLeavesRoomForAFullLookback() {
        let entriesPerTick = UInt32(HistoryBackfillPlanner.maxDeepSlicesPerTick) * HistoryBackfillPlanner.maxDeepSliceSize
        XCTAssertGreaterThan(entriesPerTick, 4000)
    }

    // MARK: - Persistence

    func testBookkeepingSurvivesARawValueRoundTrip() throws {
        let original = bookkeeping(watermark: 240, firstSeenFloor: Date(timeIntervalSinceReferenceDate: 1234))

        let restored = try XCTUnwrap(HistoryBackfillState(rawValue: original.rawValue))
        XCTAssertEqual(restored, original)
    }

    func testBookkeepingRoundTripsThroughPumpManagerState() throws {
        var state = TandemPumpManagerState(rawValue: [:])
        state.historyBackfill = bookkeeping(watermark: 240, firstSeenFloor: Date())

        let restored = TandemPumpManagerState(rawValue: state.rawValue)
        XCTAssertEqual(restored.historyBackfill, state.historyBackfill)
    }

    /// A pump seen but never read from round-trips with both optionals absent.
    func testBookkeepingWithoutAWatermarkRoundTrips() throws {
        let original = HistoryBackfillState(pumpSerial: serial)
        XCTAssertNil(original.watermark)
        XCTAssertNil(original.firstSeenFloor)

        let restored = try XCTUnwrap(HistoryBackfillState(rawValue: original.rawValue))
        XCTAssertEqual(restored, original)
    }

    /// The field was first persisted under "emitFloor", when it doubled as the emission floor.
    /// An install carrying that key keeps its first-seen date rather than re-flooring at now.
    func testBookkeepingReadsTheFloorFromItsOriginalKey() throws {
        let floor = Date(timeIntervalSinceReferenceDate: 1234)
        let legacy: HistoryBackfillState.RawValue = [
            "pumpSerial": serial,
            "watermark": UInt32(240),
            "emitFloor": floor.timeIntervalSinceReferenceDate,
        ]

        let restored = try XCTUnwrap(HistoryBackfillState(rawValue: legacy))

        XCTAssertEqual(restored.firstSeenFloor, floor)
        XCTAssertEqual(restored.watermark, 240)
    }

    func testUnreadableBookkeepingDecodesAsNil() {
        XCTAssertNil(HistoryBackfillState(rawValue: [:]))
        XCTAssertNil(TandemPumpManagerState(rawValue: [:]).historyBackfill)
    }
}
