@testable import TandemKit
import XCTest

final class TandemSourceUploaderTests: XCTestCase {
    private let serial: UInt32 = 1234567

    /// Records a stub's calls so tests can assert what reached the cloud.
    private actor StubAPI: TandemSourceAPI {
        var maxPumpEventIndex: UInt32
        private(set) var uploadedBatches: [[String]] = []
        private(set) var lastEventQueries = 0
        init(maxPumpEventIndex: UInt32) { self.maxPumpEventIndex = maxPumpEventIndex }

        func getLastEventUploaded(serial: UInt32, deviceAssignmentId: String) async throws -> LastEventUploadedResponse {
            lastEventQueries += 1
            return LastEventUploadedResponse(maxPumpEventIndex: maxPumpEventIndex, processingStatus: 0)
        }

        func upload(bodyJSON: Data) async throws {
            let body = try JSONSerialization.jsonObject(with: bodyJSON) as! [String: Any]
            let events = (((body["package"] as! [String: Any])["device"] as! [String: Any])["data"] as! [String: Any])["events"] as! [String]
            uploadedBatches.append(events)
        }
    }

    private func store(seqs: [UInt32]) -> InMemoryHistoryLogStore {
        let store = InMemoryHistoryLogStore()
        try! store.insert(seqs.map { seq in
            var cargo = Data(count: HistoryLog.length)
            cargo.replaceSubrange(6 ..< 10, with: Bytes.toUint32(seq)) // seq at the record's offset
            return StoredHistoryLog(pumpSerial: serial, sequenceNum: seq, typeId: 280, pumpTimeSec: 0, cargo: cargo)
        })
        return store
    }

    private func deps(api: TandemSourceAPI, store: HistoryLogStore, onFill: @escaping (UInt32, [ClosedRange<UInt32>]) -> Void = { _, _ in }) -> TandemSourceUploader.Dependencies {
        TandemSourceUploader.Dependencies(
            api: api,
            store: store,
            deviceInfo: { TandemSourceDeviceInfo(serialNum: self.serial, modelNum: 1004000, partNum: 1, armSwVer: 1, mspSwVer: 0, pcbaSN: 1, configABits: 0, configBBits: 0, pumpRev: "0", pcbaRev: "0", pumpAPIVersion: "3.11", controlIQ: true, basalIQ: false) },
            deviceAssignmentId: { "assignment-uuid" },
            fillGaps: { serial, ranges in onFill(serial, ranges) },
            now: { Date(timeIntervalSince1970: 1_793_464_000) },
            pumpClock: { Date(timeIntervalSince1970: 1_793_464_000) }
        )
    }

    func testUploadsOnlyRecordsPastServerHighWaterMark() async throws {
        let api = StubAPI(maxPumpEventIndex: 100)
        let uploader = TandemSourceUploader(deps: deps(api: api, store: store(seqs: [98, 99, 100, 101, 102])))

        let result = try await uploader.uploadPending(serial: serial)

        XCTAssertEqual(result.uploadedCount, 2)
        XCTAssertEqual(result.serverMaxEventIndex, 102)
        let uploaded = await api.uploadedBatches
        XCTAssertEqual(uploaded.flatMap { $0 }.count, 2)
    }

    func testNothingToUploadWhenCaughtUp() async throws {
        let api = StubAPI(maxPumpEventIndex: 102)
        let uploader = TandemSourceUploader(deps: deps(api: api, store: store(seqs: [100, 101, 102])))

        let result = try await uploader.uploadPending(serial: serial)

        XCTAssertEqual(result.uploadedCount, 0)
        let uploaded = await api.uploadedBatches
        XCTAssertTrue(uploaded.isEmpty)
    }

    func testBatchesLargeBackfill() async throws {
        let api = StubAPI(maxPumpEventIndex: 0)
        let count = TandemSourceUploader.batchSize * 2 + 10
        let uploader = TandemSourceUploader(deps: deps(api: api, store: store(seqs: Array(1 ... UInt32(count)))))

        let result = try await uploader.uploadPending(serial: serial)

        XCTAssertEqual(result.uploadedCount, count)
        let uploaded = await api.uploadedBatches
        XCTAssertEqual(uploaded.count, 3)
        XCTAssertEqual(uploaded[0].count, TandemSourceUploader.batchSize)
        XCTAssertEqual(uploaded.last?.count, 10)
    }

    func testRequestsGapFillForMissingRanges() async throws {
        let api = StubAPI(maxPumpEventIndex: 100)
        // Stored has 101 and 105; 102...104 are missing within the (101...105) upload range.
        var filled: [ClosedRange<UInt32>] = []
        let uploader = TandemSourceUploader(deps: deps(api: api, store: store(seqs: [101, 105]), onFill: { _, ranges in filled = ranges }))

        _ = try await uploader.uploadPending(serial: serial)

        XCTAssertEqual(filled, [102 ... 104])
    }

    func testRecordOfUnparsedTypeRelaysUnchanged() async throws {
        var cargo = Data((0 ..< UInt8(HistoryLog.length)).map { $0 &* 7 })
        cargo.replaceSubrange(0 ..< 2, with: [0xFE, 0x0F]) // a type id the parser has no class for
        cargo.replaceSubrange(6 ..< 10, with: Bytes.toUint32(101))
        let log = HistoryLogParser.parse(cargo)
        XCTAssertTrue(log is UnknownHistoryLog)
        let store = InMemoryHistoryLogStore()
        try store.insert([log], pumpSerial: serial)
        let api = StubAPI(maxPumpEventIndex: 100)

        let result = try await TandemSourceUploader(deps: deps(api: api, store: store)).uploadPending(serial: serial)

        XCTAssertEqual(result.uploadedCount, 1)
        let uploaded = await api.uploadedBatches
        let event = try XCTUnwrap(uploaded.first?.first)
        XCTAssertEqual(TandemSourceEventEncoder.uploadableBytes(from: try XCTUnwrap(Data(base64Encoded: event))), cargo)
    }
}
