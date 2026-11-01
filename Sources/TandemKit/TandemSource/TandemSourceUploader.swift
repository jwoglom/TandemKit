import Foundation

/// Relays stored pump history to Tandem Source, resuming from the server's high-water mark.
///
/// This does for Tandem's cloud what the Mobi app does: `getlasteventuploaded` gives the last pump
/// event index the cloud holds, and everything the driver has stored past that is sent, ascending,
/// in batches, as base64 records in an upload body. The pump's own sequence numbers are the cloud's
/// index, so overlapping re-sends are harmless and a later switch back to the Mobi app stays
/// continuous.
///
/// It owns no BLE or storage of its own: the history store, the pump-connected gap fetch, and the
/// device metadata are injected, so the whole flow is exercised in tests against a stub API and an
/// `InMemoryHistoryLogStore`.
actor TandemSourceUploader {
    struct Result: Equatable {
        var uploadedCount: Int
        var serverMaxEventIndex: UInt32
        /// The assignment id actually used (resolved automatically when not already configured), so
        /// the caller can persist it.
        var deviceAssignmentId: String
    }

    enum UploadError: Error, Equatable {
        case notConfigured
        case noDeviceInfo
    }

    struct Dependencies {
        var api: TandemSourceAPI
        var store: HistoryLogStore
        var deviceInfo: () -> TandemSourceDeviceInfo?
        var deviceAssignmentId: () -> String?
        /// Best-effort fetch of missing sequence ranges from the pump before uploading. May be a
        /// no-op (e.g. the pump is unreachable); the uploader still sends whatever it has.
        var fillGaps: (_ serial: UInt32, _ ranges: [ClosedRange<UInt32>]) async -> Void
        var now: () -> Date = { Date() }
        var pumpClock: () -> Date
    }

    /// Records per upload body. The capture sent 1–36; 50 keeps bodies small while cutting round
    /// trips on a large backfill.
    static let batchSize = 50

    private let deps: Dependencies

    init(deps: Dependencies) {
        self.deps = deps
    }

    func uploadPending(serial: UInt32) async throws -> Result {
        guard let assignmentId = deps.deviceAssignmentId() else { throw UploadError.notConfigured }
        guard let device = deps.deviceInfo() else { throw UploadError.noDeviceInfo }

        let last = try await deps.api.getLastEventUploaded(serial: serial, deviceAssignmentId: assignmentId)
        guard let newest = try deps.store.newest(pumpSerial: serial), newest.sequenceNum > last.maxPumpEventIndex else {
            return Result(uploadedCount: 0, serverMaxEventIndex: last.maxPumpEventIndex, deviceAssignmentId: assignmentId)
        }

        let range = (last.maxPumpEventIndex + 1) ... newest.sequenceNum
        let missing = try deps.store.missingRanges(pumpSerial: serial, in: range)
        if !missing.isEmpty {
            await deps.fillGaps(serial, missing)
            let unfilled = try deps.store.missingRanges(pumpSerial: serial, in: range)
            if !unfilled.isEmpty {
                // The server's index moves past them with this upload, so no later run sends them.
                tandemSourceLogger.warning("Tandem Source: \(Self.count(unfilled)) of \(Self.count([range])) records past server index \(last.maxPumpEventIndex) aren't in the session store and won't be uploaded")
            }
        }

        let pending = try deps.store.logs(pumpSerial: serial, in: range)
        var uploaded = 0
        for batch in stride(from: 0, to: pending.count, by: Self.batchSize) {
            let slice = Array(pending[batch ..< min(batch + Self.batchSize, pending.count)])
            tandemSourceLogger.debug("Tandem Source batch \(batch / Self.batchSize + 1): \(slice.count) records, \(Self.typeSummary(slice))")
            try await upload(slice, device: device, assignmentId: assignmentId)
            uploaded += slice.count
        }
        return Result(uploadedCount: uploaded, serverMaxEventIndex: newest.sequenceNum, deviceAssignmentId: assignmentId)
    }

    /// Sends the pump's settings JSON as the app does: an upload with `settings` and no events.
    func uploadSettings(_ settingsJSON: Data) async throws -> String {
        guard let assignmentId = deps.deviceAssignmentId() else { throw UploadError.notConfigured }
        guard let device = deps.deviceInfo() else { throw UploadError.noDeviceInfo }
        let body = TandemSourceUploadBody(
            device: device,
            deviceAssignmentId: assignmentId,
            settings: settingsJSON.base64EncodedString(),
            now: deps.now(),
            pumpClock: deps.pumpClock()
        )
        try await deps.api.upload(bodyJSON: JSONEncoder().encode(body))
        return assignmentId
    }

    private static func count(_ ranges: [ClosedRange<UInt32>]) -> Int {
        ranges.reduce(0) { $0 + $1.count }
    }

    /// Record type names and counts, e.g. `BasalDelivery×3, CgmDataG7×2`.
    static func typeSummary(_ logs: [StoredHistoryLog]) -> String {
        var counts: [String: Int] = [:]
        for log in logs {
            let name = String(describing: type(of: HistoryLogParser.parse(log.cargo)))
            counts[name.hasSuffix("HistoryLog") ? String(name.dropLast("HistoryLog".count)) : name, default: 0] += 1
        }
        return counts.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: ", ")
    }

    private func upload(_ logs: [StoredHistoryLog], device: TandemSourceDeviceInfo, assignmentId: String) async throws {
        let events = logs.map { TandemSourceEventEncoder.base64Event(for: $0) }
        let body = TandemSourceUploadBody(
            device: device,
            deviceAssignmentId: assignmentId,
            events: events,
            now: deps.now(),
            pumpClock: deps.pumpClock()
        )
        let json = try JSONEncoder().encode(body)
        try await deps.api.upload(bodyJSON: json)
    }
}
