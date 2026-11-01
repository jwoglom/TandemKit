import Foundation

/// Relays stored pump history to Tandem Source, resuming from the server's high-water mark.
///
/// `getlasteventuploaded` gives the last pump event index the cloud holds, and the records after it
/// are sent ascending, in batches, as the Mobi app sends them. The pump's own sequence numbers are
/// the cloud's index, so overlapping re-sends are harmless and a switch back to the Mobi app stays
/// continuous. Only an unbroken run is sent: the server's index is a high-water mark, so a record
/// sent past a gap moves it beyond the missing ones, and no later run would send them.
actor TandemSourceUploader {
    struct Result: Equatable {
        var uploadedCount: Int
        var serverMaxEventIndex: UInt32
        /// The assignment id actually used (resolved automatically when not already configured), so
        /// the caller can persist it.
        var deviceAssignmentId: String
        /// The first record this run stopped at because it couldn't be read; nil when caught up.
        var waitingForSequenceNum: UInt32? = nil
        /// Where a re-send left off, for the next run; nil once it has reached the server's index.
        var resendFrom: UInt32? = nil
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
        /// Reads `ranges` from the pump into `store`. Returns the oldest sequence number the pump
        /// still holds, or nil when the read didn't complete (the pump unreachable, or another
        /// reader holding its history stream).
        var fillGaps: (_ serial: UInt32, _ ranges: [ClosedRange<UInt32>]) async -> UInt32?
        /// Set to send again from an index the server has already passed.
        var resendFrom: () -> UInt32? = { nil }
        var now: () -> Date = { Date() }
        var pumpClock: () -> Date
    }

    /// Records per upload body. The capture sent 1–36; 50 keeps bodies small while cutting round
    /// trips on a large backfill.
    static let batchSize = 50
    /// The most records one run reads from the pump; at 255 per request, about ten requests.
    static let maxFillPerRun = 2500

    private let deps: Dependencies

    init(deps: Dependencies) {
        self.deps = deps
    }

    func uploadPending(serial: UInt32) async throws -> Result {
        guard let assignmentId = deps.deviceAssignmentId() else { throw UploadError.notConfigured }
        guard let device = deps.deviceInfo() else { throw UploadError.noDeviceInfo }

        let last = try await deps.api.getLastEventUploaded(serial: serial, deviceAssignmentId: assignmentId)
        let serverIndex = last.maxPumpEventIndex
        tandemSourceLogger.debug("Tandem Source server at \(serverIndex), processing status \(last.processingStatus)")
        let resendFrom = deps.resendFrom().flatMap { $0 <= serverIndex ? $0 : nil }
        let start = resendFrom ?? serverIndex + 1
        guard let newest = try deps.store.newest(pumpSerial: serial), newest.sequenceNum >= start else {
            return Result(uploadedCount: 0, serverMaxEventIndex: serverIndex, deviceAssignmentId: assignmentId)
        }

        let range = start ... newest.sequenceNum
        var missing = try deps.store.missingRanges(pumpSerial: serial, in: range)
        if !missing.isEmpty {
            if let pumpFirst = await deps.fillGaps(serial, Self.capped(missing, to: Self.maxFillPerRun)) {
                missing = try deps.store.missingRanges(pumpSerial: serial, in: range)
                let gone = missing.filter { $0.lowerBound < pumpFirst }
                if !gone.isEmpty {
                    let count = gone.reduce(0) { $0 + Int(min($1.upperBound, pumpFirst - 1) - $1.lowerBound) + 1 }
                    tandemSourceLogger.warning("Tandem Source: skipping \(count) records the pump no longer holds")
                    missing = missing.compactMap { $0.upperBound < pumpFirst ? nil : max($0.lowerBound, pumpFirst) ... $0.upperBound }
                }
            } else {
                missing = try deps.store.missingRanges(pumpSerial: serial, in: range)
            }
        }

        let through = missing.first.map { $0.lowerBound - 1 } ?? newest.sequenceNum
        let pending = through >= start ? try deps.store.logs(pumpSerial: serial, in: start ... through) : []
        if let gap = missing.first {
            tandemSourceLogger.warning("Tandem Source: waiting for records \(gap.lowerBound)-\(gap.upperBound) from the pump; uploading \(pending.count) before them")
        }

        var uploaded = 0
        for batch in stride(from: 0, to: pending.count, by: Self.batchSize) {
            let slice = Array(pending[batch ..< min(batch + Self.batchSize, pending.count)])
            tandemSourceLogger.debug("Tandem Source batch \(batch / Self.batchSize + 1): \(slice.count) records, \(Self.typeSummary(slice))")
            try await upload(slice, device: device, assignmentId: assignmentId)
            uploaded += slice.count
        }
        let reached = pending.last?.sequenceNum ?? (start == 0 ? 0 : start - 1)
        return Result(
            uploadedCount: uploaded,
            serverMaxEventIndex: max(serverIndex, reached),
            deviceAssignmentId: assignmentId,
            waitingForSequenceNum: missing.first?.lowerBound,
            resendFrom: resendFrom != nil && reached < serverIndex ? reached + 1 : nil
        )
    }

    /// The lowest ranges first, trimmed to `limit` records: the upload goes ascending, so the oldest
    /// gap is the one holding it back.
    static func capped(_ ranges: [ClosedRange<UInt32>], to limit: Int) -> [ClosedRange<UInt32>] {
        var left = limit
        var out: [ClosedRange<UInt32>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) where left > 0 {
            let take = min(range.count, left)
            out.append(range.lowerBound ... range.lowerBound + UInt32(take - 1))
            left -= take
        }
        return out
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
