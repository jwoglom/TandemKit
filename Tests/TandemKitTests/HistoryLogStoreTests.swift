@testable import TandemKit
import XCTest

/// Behaviour every `HistoryLogStore` implementation must share.
///
/// Each case runs against a freshly created instance of every implementation, so the in-memory
/// store used by tests can't drift from the persistent store the driver will ship. Cases are
/// written as explicit loops rather than as a subclassed abstract test case because XCTest on
/// Linux does not discover inherited test methods.
final class HistoryLogStoreTests: XCTestCase {
    private let pumpA: UInt32 = 12345
    private let pumpB: UInt32 = 67890

    private func forEachStore(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: (_ store: HistoryLogStore, _ label: String) throws -> Void
    ) {
        // Only the in-memory store exists so far; the persistent store is slotted in here when it
        // lands, so it inherits this whole suite rather than growing a parallel one.
        let factories: [(label: String, make: () throws -> HistoryLogStore)] = [
            ("InMemoryHistoryLogStore", { InMemoryHistoryLogStore() })
        ]

        for factory in factories {
            do {
                try body(try factory.make(), factory.label)
            } catch {
                XCTFail("\(factory.label): \(error)", file: file, line: line)
            }
        }
    }

    /// A synthetic 26-byte record laid out the way `HistoryLog` parses it: typeId in bytes 0-1
    /// (masked to 12 bits), pumpTimeSec in 2-5, sequenceNum in 6-9.
    private func makeCargo(typeId: Int, pumpTimeSec: UInt32, sequenceNum: UInt32) -> Data {
        var cargo = Data(count: HistoryLog.length)
        cargo[0] = UInt8(typeId & 0xFF)
        cargo[1] = UInt8((typeId >> 8) & 0x0F)
        cargo.replaceSubrange(2 ..< 6, with: Bytes.toUint32(pumpTimeSec))
        cargo.replaceSubrange(6 ..< 10, with: Bytes.toUint32(sequenceNum))
        return cargo
    }

    private func makeLog(
        pumpSerial: UInt32? = nil,
        sequenceNum: UInt32,
        typeId: Int = 1,
        pumpTimeSec: UInt32 = 500_000_000,
        receivedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> StoredHistoryLog {
        StoredHistoryLog(
            pumpSerial: pumpSerial ?? pumpA,
            sequenceNum: sequenceNum,
            typeId: typeId,
            pumpTimeSec: pumpTimeSec,
            cargo: makeCargo(typeId: typeId, pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum),
            receivedAt: receivedAt
        )
    }

    // MARK: - Insert

    func testInsertAndReadBack() {
        forEachStore { store, label in
            try store.insert([makeLog(sequenceNum: 10), makeLog(sequenceNum: 11), makeLog(sequenceNum: 12)])

            XCTAssertEqual(try store.count(pumpSerial: pumpA), 3, label)
            XCTAssertEqual(try store.logs(pumpSerial: pumpA, in: 10 ... 12).map(\.sequenceNum), [10, 11, 12], label)
            XCTAssertEqual(try store.logs(pumpSerial: pumpA, in: 11 ... 11).map(\.sequenceNum), [11], label)
        }
    }

    func testInsertPreservesAllFields() {
        forEachStore { store, label in
            let log = makeLog(
                sequenceNum: 7,
                typeId: 20,
                pumpTimeSec: 543_210_987,
                receivedAt: Date(timeIntervalSince1970: 1_600_000_000)
            )
            try store.insert([log])

            XCTAssertEqual(try store.logs(pumpSerial: pumpA, in: 7 ... 7).first, log, label)
        }
    }

    func testInsertIgnoresDuplicateSequenceNumbers() {
        forEachStore { store, label in
            let original = makeLog(sequenceNum: 5, typeId: 1)
            try store.insert([original])
            // Same key, different payload: the existing row wins (insert-ignore).
            try store.insert([makeLog(sequenceNum: 5, typeId: 99)])
            // Duplicates within a single batch collapse too.
            try store.insert([makeLog(sequenceNum: 6, typeId: 1), makeLog(sequenceNum: 6, typeId: 98)])

            XCTAssertEqual(try store.count(pumpSerial: pumpA), 2, label)
            XCTAssertEqual(try store.logs(pumpSerial: pumpA, in: 5 ... 5).first, original, label)
        }
    }

    func testEntriesAreScopedByPumpSerial() {
        forEachStore { store, label in
            try store.insert([makeLog(pumpSerial: pumpA, sequenceNum: 1)])
            try store.insert([
                makeLog(pumpSerial: pumpB, sequenceNum: 1),
                makeLog(pumpSerial: pumpB, sequenceNum: 2)
            ])

            XCTAssertEqual(try store.count(pumpSerial: pumpA), 1, label)
            XCTAssertEqual(try store.count(pumpSerial: pumpB), 2, label)
            XCTAssertEqual(try store.newest(pumpSerial: pumpA)?.sequenceNum, 1, label)
            XCTAssertEqual(try store.newest(pumpSerial: pumpB)?.sequenceNum, 2, label)
        }
    }

    func testInsertFromHistoryLogObjects() {
        forEachStore { store, label in
            let parsed = HistoryLogParser.parse(makeCargo(typeId: 1, pumpTimeSec: 500_000_100, sequenceNum: 42))
            try store.insert([parsed], pumpSerial: pumpA)

            let stored = try XCTUnwrap(store.newest(pumpSerial: pumpA), label)
            XCTAssertEqual(stored.sequenceNum, 42, label)
            XCTAssertEqual(stored.pumpTimeSec, 500_000_100, label)
            XCTAssertEqual(stored.parsed().sequenceNum, 42, label)
        }
    }

    func testInsertLargeBatchCrossesInternalBatchBoundary() {
        forEachStore { store, label in
            try store.insert((1 ... 1200).map { makeLog(sequenceNum: UInt32($0)) })

            XCTAssertEqual(try store.count(pumpSerial: pumpA), 1200, label)
            XCTAssertEqual(try store.missingRanges(pumpSerial: pumpA, in: 1 ... 1200), [], label)
        }
    }

    // MARK: - Queries

    func testOldestAndNewest() {
        forEachStore { store, label in
            XCTAssertNil(try store.oldest(pumpSerial: pumpA), label)
            XCTAssertNil(try store.newest(pumpSerial: pumpA), label)

            try store.insert([makeLog(sequenceNum: 30), makeLog(sequenceNum: 10), makeLog(sequenceNum: 20)])

            XCTAssertEqual(try store.oldest(pumpSerial: pumpA)?.sequenceNum, 10, label)
            XCTAssertEqual(try store.newest(pumpSerial: pumpA)?.sequenceNum, 30, label)
        }
    }

    func testNewestOfType() {
        forEachStore { store, label in
            try store.insert([
                makeLog(sequenceNum: 1, typeId: 20),
                makeLog(sequenceNum: 2, typeId: 21),
                makeLog(sequenceNum: 3, typeId: 20)
            ])

            XCTAssertEqual(try store.newest(pumpSerial: pumpA, ofType: 20)?.sequenceNum, 3, label)
            XCTAssertEqual(try store.newest(pumpSerial: pumpA, ofType: 21)?.sequenceNum, 2, label)
            XCTAssertNil(try store.newest(pumpSerial: pumpA, ofType: 22), label)
        }
    }

    func testLogsForTypesInASequenceRange() {
        forEachStore { store, label in
            try store.insert([
                makeLog(sequenceNum: 1, typeId: 20, pumpTimeSec: 1000),
                makeLog(sequenceNum: 2, typeId: 20, pumpTimeSec: 9000),
                makeLog(sequenceNum: 3, typeId: 21, pumpTimeSec: 10),
                makeLog(sequenceNum: 4, typeId: 22, pumpTimeSec: 4000),
                makeLog(sequenceNum: 5, typeId: 20, pumpTimeSec: 5000)
            ])

            let matching = try store.logs(pumpSerial: pumpA, ofTypes: [20, 21], in: 2 ... 4)
            XCTAssertEqual(matching.map(\.sequenceNum), [2, 3], "selected by sequence number, whatever the stamps: \(label)")
            XCTAssertEqual(try store.logs(pumpSerial: pumpA, ofTypes: [], in: 0 ... 10), [], label)
        }
    }

    func testLowestSequenceNumReceivedSince() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        forEachStore { store, label in
            try store.insert([
                makeLog(sequenceNum: 10, receivedAt: now),
                makeLog(sequenceNum: 5, receivedAt: now.addingTimeInterval(.hours(1))),
                makeLog(sequenceNum: 20, receivedAt: now.addingTimeInterval(-.hours(1)))
            ])

            XCTAssertEqual(try store.lowestSequenceNum(pumpSerial: pumpA, receivedSince: now), 5, label)
            XCTAssertNil(try store.lowestSequenceNum(pumpSerial: pumpA, receivedSince: now.addingTimeInterval(.hours(2))), label)
        }
    }

    func testTypeStats() {
        forEachStore { store, label in
            try store.insert([
                makeLog(sequenceNum: 1, typeId: 20, pumpTimeSec: 1000),
                makeLog(sequenceNum: 2, typeId: 20, pumpTimeSec: 2000),
                makeLog(sequenceNum: 3, typeId: 21, pumpTimeSec: 3000)
            ])

            XCTAssertEqual(try store.typeStats(pumpSerial: pumpA), [
                HistoryLogTypeStats(typeId: 20, count: 2, latestSequenceNum: 2, latestPumpTimeSec: 2000),
                HistoryLogTypeStats(typeId: 21, count: 1, latestSequenceNum: 3, latestPumpTimeSec: 3000)
            ], label)
        }
    }

    // MARK: - Gap detection

    func testMissingRangesOnEmptyStore() {
        forEachStore { store, label in
            XCTAssertEqual(try store.missingRanges(pumpSerial: pumpA, in: 5 ... 10), [5 ... 10], label)
        }
    }

    func testMissingRangesFindsInteriorAndEdgeGaps() {
        forEachStore { store, label in
            try store.insert([
                makeLog(sequenceNum: 2),
                makeLog(sequenceNum: 3),
                makeLog(sequenceNum: 7),
                makeLog(sequenceNum: 10)
            ])

            XCTAssertEqual(
                try store.missingRanges(pumpSerial: pumpA, in: 1 ... 12),
                [1 ... 1, 4 ... 6, 8 ... 9, 11 ... 12],
                label
            )
        }
    }

    func testMissingRangesIgnoresOtherPumps() {
        forEachStore { store, label in
            try store.insert([
                makeLog(pumpSerial: pumpB, sequenceNum: 1),
                makeLog(pumpSerial: pumpB, sequenceNum: 2)
            ])

            XCTAssertEqual(try store.missingRanges(pumpSerial: pumpA, in: 1 ... 2), [1 ... 2], label)
            XCTAssertEqual(try store.missingRanges(pumpSerial: pumpB, in: 1 ... 2), [], label)
        }
    }

    func testSequenceNumbersAreClampedToRequestedRange() {
        forEachStore { store, label in
            try store.insert((1 ... 10).map { makeLog(sequenceNum: UInt32($0)) })

            XCTAssertEqual(try store.sequenceNumbers(pumpSerial: pumpA, in: 3 ... 5), [3, 4, 5], label)
        }
    }

    // MARK: - Retention

    func testPruneRemovesOldEntriesAndAdvancesWatermark() {
        forEachStore { store, label in
            try store.insert([
                makeLog(sequenceNum: 1, pumpTimeSec: 1000),
                makeLog(sequenceNum: 2, pumpTimeSec: 2000),
                makeLog(sequenceNum: 3, pumpTimeSec: 3000)
            ])

            XCTAssertNil(try store.prunedBelowSequenceNum(pumpSerial: pumpA), label)
            XCTAssertEqual(try store.prune(pumpSerial: pumpA, belowSequenceNum: 3), 2, label)

            XCTAssertEqual(try store.count(pumpSerial: pumpA), 1, label)
            XCTAssertEqual(try store.oldest(pumpSerial: pumpA)?.sequenceNum, 3, label)
            XCTAssertEqual(try store.prunedBelowSequenceNum(pumpSerial: pumpA), 3, label)
        }
    }

    func testPrunedRangesAreNotReportedAsMissing() {
        forEachStore { store, label in
            try store.insert([
                makeLog(sequenceNum: 1, pumpTimeSec: 1000),
                makeLog(sequenceNum: 2, pumpTimeSec: 2000),
                makeLog(sequenceNum: 5, pumpTimeSec: 5000)
            ])
            try store.prune(pumpSerial: pumpA, belowSequenceNum: 3)

            // 1-2 were pruned deliberately; only the genuine hole at 3-4 is worth re-fetching.
            XCTAssertEqual(try store.missingRanges(pumpSerial: pumpA, in: 1 ... 5), [3 ... 4], label)
        }
    }

    func testPruneIsANoOpWhenNothingIsOldEnough() {
        forEachStore { store, label in
            try store.insert([makeLog(sequenceNum: 2, pumpTimeSec: 5000)])

            XCTAssertEqual(try store.prune(pumpSerial: pumpA, belowSequenceNum: 2), 0, label)
            XCTAssertEqual(try store.count(pumpSerial: pumpA), 1, label)
            XCTAssertNil(try store.prunedBelowSequenceNum(pumpSerial: pumpA), label)
        }
    }

    func testWatermarkNeverMovesBackward() {
        forEachStore { store, label in
            try store.insert([
                makeLog(sequenceNum: 1, pumpTimeSec: 1000),
                makeLog(sequenceNum: 2, pumpTimeSec: 2000)
            ])
            try store.prune(pumpSerial: pumpA, belowSequenceNum: 3)
            XCTAssertEqual(try store.prunedBelowSequenceNum(pumpSerial: pumpA), 3, label)

            // Re-inserting an already-pruned entry and pruning a narrower window must not lower it.
            try store.insert([makeLog(sequenceNum: 1, pumpTimeSec: 1000)])
            try store.prune(pumpSerial: pumpA, belowSequenceNum: 2)
            XCTAssertEqual(try store.prunedBelowSequenceNum(pumpSerial: pumpA), 3, label)
        }
    }

    func testPruneExpiredUsesNinetyDayRetention() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func received(daysAgo: Double) -> Date {
            now.addingTimeInterval(-.days(daysAgo))
        }

        XCTAssertEqual(HistoryLogRetention.default, .days(90))

        forEachStore { store, label in
            try store.insert([
                makeLog(sequenceNum: 1, receivedAt: received(daysAgo: 120)),
                makeLog(sequenceNum: 2, receivedAt: received(daysAgo: 91)),
                makeLog(sequenceNum: 3, receivedAt: received(daysAgo: 89)),
                makeLog(sequenceNum: 4, receivedAt: received(daysAgo: 1))
            ])

            XCTAssertEqual(try store.pruneExpired(pumpSerial: pumpA, now: now), 2, label)
            XCTAssertEqual(
                try store.logs(pumpSerial: pumpA, in: 0 ... UInt32.max).map(\.sequenceNum),
                [3, 4],
                label
            )
            XCTAssertEqual(try store.prunedBelowSequenceNum(pumpSerial: pumpA), 3, label)
        }
    }

    /// After a clock reset a record written minutes ago carries a stamp years old (a field log's read
    /// 2020 for records from that morning); pruned by stamp, the walk's boundary went every hour.
    func testPruneExpiredKeepsWhatWasJustReadWhateverItsStamp() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        forEachStore { store, label in
            try store.insert([
                makeLog(sequenceNum: 1, pumpTimeSec: 0, receivedAt: now.addingTimeInterval(-.minutes(5))),
                makeLog(sequenceNum: 2, pumpTimeSec: 378_691_200, receivedAt: now.addingTimeInterval(-.minutes(5)))
            ])

            XCTAssertEqual(try store.pruneExpired(pumpSerial: pumpA, now: now), 0, label)
            XCTAssertEqual(try store.count(pumpSerial: pumpA), 2, label)
            XCTAssertNil(try store.prunedBelowSequenceNum(pumpSerial: pumpA), label)
        }
    }

    /// The walk reads older records after newer ones, so an old record read recently keeps everything above it.
    func testPruneExpiredKeepsEverythingAboveTheOldestRecentRead() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        forEachStore { store, label in
            try store.insert([
                makeLog(sequenceNum: 1, receivedAt: now.addingTimeInterval(-.days(200))),
                makeLog(sequenceNum: 2, receivedAt: now.addingTimeInterval(-.days(1))),
                makeLog(sequenceNum: 3, receivedAt: now.addingTimeInterval(-.days(100))),
                makeLog(sequenceNum: 4, receivedAt: now.addingTimeInterval(-.days(100)))
            ])

            XCTAssertEqual(try store.pruneExpired(pumpSerial: pumpA, now: now), 1, label)
            XCTAssertEqual(try store.logs(pumpSerial: pumpA, in: 0 ... UInt32.max).map(\.sequenceNum), [2, 3, 4], label)
            XCTAssertEqual(try store.missingRanges(pumpSerial: pumpA, in: 1 ... 4), [], label)
        }
    }

    func testPruneExpiredWithNothingRecentKeepsTheNewestRecord() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        forEachStore { store, label in
            try store.insert([
                makeLog(sequenceNum: 7, receivedAt: now.addingTimeInterval(-.days(200))),
                makeLog(sequenceNum: 8, receivedAt: now.addingTimeInterval(-.days(100)))
            ])

            XCTAssertEqual(try store.pruneExpired(pumpSerial: pumpA, now: now), 1, label)
            XCTAssertEqual(try store.newest(pumpSerial: pumpA)?.sequenceNum, 8, label)
        }
    }

    func testDeleteAllForOnePumpLeavesOthers() {
        forEachStore { store, label in
            try store.insert([makeLog(pumpSerial: pumpA, sequenceNum: 1, pumpTimeSec: 1000)])
            try store.insert([makeLog(pumpSerial: pumpB, sequenceNum: 1)])
            try store.prune(pumpSerial: pumpA, belowSequenceNum: 2)

            try store.deleteAll(pumpSerial: pumpA)

            XCTAssertEqual(try store.count(pumpSerial: pumpA), 0, label)
            XCTAssertNil(try store.prunedBelowSequenceNum(pumpSerial: pumpA), label)
            XCTAssertEqual(try store.count(pumpSerial: pumpB), 1, label)
        }
    }

    func testDeleteAllPumps() {
        forEachStore { store, label in
            try store.insert([makeLog(pumpSerial: pumpA, sequenceNum: 1)])
            try store.insert([makeLog(pumpSerial: pumpB, sequenceNum: 1)])

            try store.deleteAll(pumpSerial: nil)

            XCTAssertEqual(try store.count(pumpSerial: pumpA), 0, label)
            XCTAssertEqual(try store.count(pumpSerial: pumpB), 0, label)
        }
    }
}

final class HistoryLogSequenceGapsTests: XCTestCase {
    func testNoGapsWhenContiguous() {
        XCTAssertEqual(HistoryLogSequenceGaps.missingRanges(present: [1, 2, 3], in: 1 ... 3), [])
    }

    func testEverythingMissingWhenNothingPresent() {
        XCTAssertEqual(HistoryLogSequenceGaps.missingRanges(present: [], in: 4 ... 6), [4 ... 6])
    }

    func testUnsortedAndDuplicateInputIsHandled() {
        XCTAssertEqual(
            HistoryLogSequenceGaps.missingRanges(present: [5, 1, 5, 3], in: 1 ... 5),
            [2 ... 2, 4 ... 4]
        )
    }

    func testSequencesOutsideTheRangeAreIgnored() {
        XCTAssertEqual(
            HistoryLogSequenceGaps.missingRanges(present: [1, 2, 9], in: 5 ... 7),
            [5 ... 7]
        )
    }

    func testRangeStartingAtZero() {
        XCTAssertEqual(HistoryLogSequenceGaps.missingRanges(present: [0, 2], in: 0 ... 3), [1 ... 1, 3 ... 3])
    }

    func testRangeEndingAtUInt32Max() {
        let start = UInt32.max - 2
        XCTAssertEqual(
            HistoryLogSequenceGaps.missingRanges(present: [UInt32.max], in: start ... UInt32.max),
            [start ... (UInt32.max - 1)]
        )
    }
}
