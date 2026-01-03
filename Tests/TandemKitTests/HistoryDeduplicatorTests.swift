@testable import TandemKit
import TandemCore
import XCTest

final class HistoryDeduplicatorTests: XCTestCase {
    func testFiltersUnseenLogsAndMarksSeen() {
        let deduplicator = HistoryDeduplicator()
        let logs = [
            mockLog(sequenceNum: 1),
            mockLog(sequenceNum: 2),
            mockLog(sequenceNum: 3)
        ]

        let unseen = deduplicator.filterUnseen(logs)
        XCTAssertEqual(unseen.map { $0.sequenceNum }, [1, 2, 3])

        XCTAssertTrue(deduplicator.isSeen(1))
        XCTAssertTrue(deduplicator.isSeen(2))
        XCTAssertTrue(deduplicator.isSeen(3))
    }

    func testFiltersOutPreviouslySeenEntries() {
        let deduplicator = HistoryDeduplicator()
        deduplicator.markSeen(2)

        let logs = [
            mockLog(sequenceNum: 1),
            mockLog(sequenceNum: 2),
            mockLog(sequenceNum: 3)
        ]

        let unseen = deduplicator.filterUnseen(logs)
        XCTAssertEqual(unseen.map { $0.sequenceNum }, [1, 3])
    }

    func testPersistAndRestore() throws {
        let deduplicator = HistoryDeduplicator()
        deduplicator.markSeen(4)
        deduplicator.markSeen(5)

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try deduplicator.persist(to: tempFile)

        let restored = HistoryDeduplicator()
        try restored.restore(from: tempFile)

        XCTAssertTrue(restored.isSeen(4))
        XCTAssertTrue(restored.isSeen(5))
    }

    // MARK: - Helpers

    private func mockLog(sequenceNum: UInt32) -> HistoryLog {
        let cargo = Data([0x00, 0x00] + Array(repeating: 0, count: 24))
        return HistoryLog(cargo: cargo.replacingSequenceNum(with: sequenceNum))
    }
}

private extension Data {
    func replacingSequenceNum(with sequenceNum: UInt32) -> Data {
        var data = self
        var mutableSequenceNum = sequenceNum
        let bytes: [UInt8] = [
            UInt8(truncatingIfNeeded: mutableSequenceNum >> 24),
            UInt8(truncatingIfNeeded: mutableSequenceNum >> 16),
            UInt8(truncatingIfNeeded: mutableSequenceNum >> 8),
            UInt8(truncatingIfNeeded: mutableSequenceNum)
        ]
        data.replaceSubrange(6 ..< 10, with: bytes)
        return data
    }
}
