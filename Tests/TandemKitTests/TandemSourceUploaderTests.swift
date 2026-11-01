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

    private func record(_ seq: UInt32) -> StoredHistoryLog {
        var cargo = Data(count: HistoryLog.length)
        cargo.replaceSubrange(6 ..< 10, with: Bytes.toUint32(seq)) // seq at the record's offset
        return StoredHistoryLog(pumpSerial: serial, sequenceNum: seq, typeId: 280, pumpTimeSec: 0, cargo: cargo)
    }

    private func store(seqs: [UInt32]) -> InMemoryHistoryLogStore {
        let store = InMemoryHistoryLogStore()
        try! store.insert(seqs.map(record))
        return store
    }

    private func uploadedSeqs(_ api: StubAPI) async -> [UInt32] {
        await api.uploadedBatches.flatMap { $0 }.map { event in
            let bytes = TandemSourceEventEncoder.uploadableBytes(from: Data(base64Encoded: event)!)
            return Bytes.readUint32(bytes, 6)
        }
    }

    private func deps(
        api: TandemSourceAPI,
        store: HistoryLogStore,
        resendFrom: UInt32? = nil,
        onFill: @escaping (UInt32, [ClosedRange<UInt32>]) -> UInt32? = { _, _ in nil }
    ) -> TandemSourceUploader.Dependencies {
        TandemSourceUploader.Dependencies(
            api: api,
            store: store,
            deviceInfo: { TandemSourceDeviceInfo(serialNum: self.serial, modelNum: 1004000, partNum: 1, armSwVer: 1, mspSwVer: 0, pcbaSN: 1, configABits: 0, configBBits: 0, pumpRev: "0", pcbaRev: "0", pumpAPIVersion: "3.11", dexcomG6: false, basalIQ: false, controlIQ: true) },
            deviceAssignmentId: { "assignment-uuid" },
            fillGaps: { serial, ranges in onFill(serial, ranges) },
            resendFrom: { resendFrom },
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
        let uploader = TandemSourceUploader(deps: deps(api: api, store: store(seqs: [101, 105]), onFill: { _, ranges in filled = ranges; return nil }))

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
        XCTAssertEqual(Data(base64Encoded: event), TandemSourceEventEncoder.uploadableBytes(from: cargo))
    }

    func testStopsAtTheFirstRecordItCouldNotRead() async throws {
        let api = StubAPI(maxPumpEventIndex: 100)
        let uploader = TandemSourceUploader(deps: deps(api: api, store: store(seqs: [101, 102, 104, 105])))

        let result = try await uploader.uploadPending(serial: serial)

        let uploaded = await uploadedSeqs(api)
        XCTAssertEqual(uploaded, [101, 102])
        XCTAssertEqual(result.serverMaxEventIndex, 102)
        XCTAssertEqual(result.waitingForSequenceNum, 103)
    }

    func testAGapAtTheStartUploadsNothingAndLeavesTheIndex() async throws {
        let api = StubAPI(maxPumpEventIndex: 100)
        let uploader = TandemSourceUploader(deps: deps(api: api, store: store(seqs: [103, 104])))

        let result = try await uploader.uploadPending(serial: serial)

        let uploaded = await uploadedSeqs(api)
        XCTAssertEqual(uploaded, [])
        XCTAssertEqual(result.serverMaxEventIndex, 100)
        XCTAssertEqual(result.waitingForSequenceNum, 101)
    }

    func testRecordsReadFromThePumpAreUploadedInOrder() async throws {
        let api = StubAPI(maxPumpEventIndex: 100)
        let store = store(seqs: [101, 104])
        let uploader = TandemSourceUploader(deps: deps(api: api, store: store, onFill: { _, ranges in
            try! store.insert(ranges.flatMap { Array($0) }.map(self.record))
            return 1
        }))

        let result = try await uploader.uploadPending(serial: serial)

        let uploaded = await uploadedSeqs(api)
        XCTAssertEqual(uploaded, [101, 102, 103, 104])
        XCTAssertNil(result.waitingForSequenceNum)
    }

    func testRecordsThePumpNoLongerHoldsAreSkipped() async throws {
        let api = StubAPI(maxPumpEventIndex: 100)
        // The pump's oldest entry is 104, so 101...103 can never be read.
        let uploader = TandemSourceUploader(deps: deps(api: api, store: store(seqs: [104, 105]), onFill: { _, _ in 104 }))

        let result = try await uploader.uploadPending(serial: serial)

        let uploaded = await uploadedSeqs(api)
        XCTAssertEqual(uploaded, [104, 105])
        XCTAssertEqual(result.serverMaxEventIndex, 105)
        XCTAssertNil(result.waitingForSequenceNum)
    }

    func testResendSendsRecordsTheServerAlreadyPassed() async throws {
        let api = StubAPI(maxPumpEventIndex: 105)
        let uploader = TandemSourceUploader(deps: deps(api: api, store: store(seqs: [101, 102, 103, 104, 105]), resendFrom: 102))

        let result = try await uploader.uploadPending(serial: serial)

        let uploaded = await uploadedSeqs(api)
        XCTAssertEqual(uploaded, [102, 103, 104, 105])
        XCTAssertEqual(result.serverMaxEventIndex, 105)
        XCTAssertNil(result.resendFrom)
    }

    func testAResendStoppedByAGapResumesFromIt() async throws {
        let api = StubAPI(maxPumpEventIndex: 105)
        let uploader = TandemSourceUploader(deps: deps(api: api, store: store(seqs: [101, 102, 104, 105]), resendFrom: 101))

        let result = try await uploader.uploadPending(serial: serial)

        let uploaded = await uploadedSeqs(api)
        XCTAssertEqual(uploaded, [101, 102])
        XCTAssertEqual(result.serverMaxEventIndex, 105)
        XCTAssertEqual(result.resendFrom, 103)
    }

    func testTheOldestGapIsReadFirstWithinTheCap() {
        XCTAssertEqual(TandemSourceUploader.capped([20 ... 29, 1 ... 5], to: 8), [1 ... 5, 20 ... 22])
    }

    func testAGapLargerThanOneReadStepIsReadInOneRun() async throws {
        let api = StubAPI(maxPumpEventIndex: 100)
        let newest = UInt32(100 + TandemSourceUploader.fillStep * 2 + 10)
        let store = store(seqs: [101, newest])
        var steps = 0
        let uploader = TandemSourceUploader(deps: deps(api: api, store: store, onFill: { _, ranges in
            steps += 1
            try! store.insert(ranges.flatMap { Array($0) }.map(self.record))
            return 1
        }))

        let result = try await uploader.uploadPending(serial: serial)

        XCTAssertEqual(steps, 3)
        XCTAssertEqual(result.uploadedCount, Int(newest) - 100)
        XCTAssertNil(result.waitingForSequenceNum)
    }

    func testAReadThatReturnsNothingStopsInsteadOfRetrying() async throws {
        let api = StubAPI(maxPumpEventIndex: 100)
        var steps = 0
        let uploader = TandemSourceUploader(deps: deps(api: api, store: store(seqs: [101, 105]), onFill: { _, _ in
            steps += 1
            return 1
        }))

        let result = try await uploader.uploadPending(serial: serial)

        XCTAssertEqual(steps, 1)
        XCTAssertEqual(result.waitingForSequenceNum, 102)
    }
}
