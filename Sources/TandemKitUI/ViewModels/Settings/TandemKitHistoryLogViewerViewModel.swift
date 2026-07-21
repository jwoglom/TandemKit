import Combine
import Foundation
import SwiftUI

final class TandemKitHistoryLogViewerViewModel: ObservableObject {
    enum Phase: Equatable {
        case loadingStatus
        case statusUnavailable
        case ready
        case fetching
        case complete
        case failed(String)
    }

    /// How the user picks which slice of history to pull.
    enum NavigationMode: Int, CaseIterable, Identifiable {
        /// A fixed number of logs walking backward from a chosen Start ID.
        case aroundTime
        /// Every log between two chosen dates (count is derived, not chosen).
        case dateRange

        var id: Int { rawValue }
    }

    /// Progress of the background guidepost calibration used for date⇄ID estimation.
    enum CalibrationState: Equatable {
        case idle
        case running(done: Int, total: Int)
        case ready
    }

    /// The exact ID window a date range resolved to, via binary search.
    struct ResolvedRange: Equatable {
        let fromId: UInt32
        let toId: UInt32
        var count: Int { toId >= fromId ? Int(toId - fromId) + 1 : 0 }
        var isEmpty: Bool { count == 0 }
    }

    struct TypeCount: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    struct LogEntry: Identifiable {
        let log: HistoryLog
        var id: UInt32 { log.sequenceNum }
        var typeName: String { HistoryLogExport.typeName(log) }
    }

    @Published var phase: Phase = .loadingStatus
    @Published var navigationMode: NavigationMode = .aroundTime
    @Published var selectedCount: Int = 256
    @Published var pumpStatusDescription: String?
    @Published var fetchedCount = 0
    @Published var expectedCount = 0
    @Published var earliestFetched: Date?

    /// Newest/oldest sequence numbers reported by the pump's history log status.
    @Published private(set) var firstSequenceNum: UInt32?
    @Published private(set) var lastSequenceNum: UInt32?

    // MARK: Around-a-time controls
    /// The newest log in the window; "number of logs" walks backward from here.
    @Published var startId: UInt32 = 0
    /// The date/time picker's value, translated into `startId` via the calibration.
    @Published var pickerDate: Date = Date()
    /// Quick "N days ago" stepper value.
    @Published var daysAgo: Int = 0

    // MARK: Date-range controls
    @Published var rangeStart: Date = Date().addingTimeInterval(-86_400)
    @Published var rangeEnd: Date = Date()
    @Published private(set) var resolvedRange: ResolvedRange?
    @Published private(set) var isResolvingRange = false

    // MARK: Calibration
    @Published private(set) var calibration = HistoryLogCalibration()
    @Published private(set) var calibrationState: CalibrationState = .idle

    /// History logs keyed by sequence number.
    @Published private(set) var logsBySequence: [UInt32: HistoryLog] = [:]
    /// History logs grouped by type name, each list sorted ascending by sequence number.
    @Published private(set) var logsByType: [String: [HistoryLog]] = [:]
    /// All history logs sorted descending by sequence number, for the "By Time" tab.
    @Published private(set) var logsDescending: [LogEntry] = []

    /// Multiples of 256 offered in the "how many logs back" dropdown.
    let countOptions: [Int] = Array(stride(from: 256, through: 8192, by: 256))

    /// Guideposts are sampled every this many sequence numbers, this many times, back from newest.
    static let guidepostSpacing: Int64 = 4096
    static let guidepostCount = 30

    /// Fetching more than this many logs in one pull is slow enough to warn about.
    static let largeFetchThreshold = 5000

    private let pumpManager: TandemPumpManager?
    private var fetcher: HistoryLogFetcher?
    /// Every stream message received during fetches, in arrival order, for JSONL export. Guidepost
    /// and binary-search probes deliberately bypass this, so they never enter the export or lists.
    private var streamMessages: [(receivedAt: Date, message: HistoryLogStreamResponse)] = []

    /// Serial queue for background single-log probing (calibration + range resolution).
    private let probeQueue = DispatchQueue(label: "com.jwoglom.TandemKit.historyLogViewer.probe")
    /// Monotonic token used to cancel in-flight background probing when state changes.
    private let tokenLock = NSLock()
    private var token = 0
    private var didInitializeNavDefaults = false

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
    }

    var hasLogs: Bool {
        !logsBySequence.isEmpty
    }

    /// Type name groups sorted descending by log count for the "By Type" tab.
    var typeCounts: [TypeCount] {
        logsByType
            .map { TypeCount(name: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.name < rhs.name
            }
    }

    var progressFraction: Double {
        guard expectedCount > 0 else { return 0 }
        return min(1.0, Double(fetchedCount) / Double(expectedCount))
    }

    /// e.g. "Fetched 64 history logs (earliest: 1h23m ago)"
    var progressSummary: String {
        var summary = "Fetched \(fetchedCount) history log\(fetchedCount == 1 ? "" : "s")"
        if let earliestFetched {
            summary += " (earliest: \(Self.relativeTimeAgo(earliestFetched)) ago)"
        }
        return summary
    }

    // MARK: - Status

    func loadStatus() {
        guard phase == .loadingStatus || phase == .statusUnavailable else {
            return
        }
        guard let pumpManager else {
            phase = .statusUnavailable
            pumpStatusDescription = "Pump not available"
            return
        }

        phase = .loadingStatus
        let fetcher = fetcher ?? HistoryLogFetcher(pumpManager: pumpManager)
        self.fetcher = fetcher
        fetcher.fetchStatus { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                if let status {
                    self.pumpStatusDescription =
                        "\(status.numEntries) entries on pump (sequence \(status.firstSequenceNum)–\(status.lastSequenceNum))"
                    self.firstSequenceNum = status.firstSequenceNum
                    self.lastSequenceNum = status.lastSequenceNum
                    self.initializeNavDefaultsIfNeeded()
                    self.phase = .ready
                    self.startCalibration()
                } else {
                    self.pumpStatusDescription = "Unable to read history log status from the pump"
                    self.phase = .statusUnavailable
                }
            }
        }
    }

    private func initializeNavDefaultsIfNeeded() {
        guard !didInitializeNavDefaults, let last = lastSequenceNum else { return }
        didInitializeNavDefaults = true
        startId = last
        let now = Date()
        pickerDate = now
        rangeEnd = now
        rangeStart = now.addingTimeInterval(-86_400)
    }

    // MARK: - Calibration (guidepost sampling)

    /// Probes single logs spaced `guidepostSpacing` apart, back from the newest entry, to learn the
    /// ID→date relationship. Results feed the calibration only — never the displayed lists or export.
    private func startCalibration() {
        guard let fetcher, let first = firstSequenceNum, let last = lastSequenceNum else { return }

        var targets: [UInt32] = []
        var seen = Set<UInt32>()
        for step in 0 ... Self.guidepostCount {
            let seq = Int64(last) - Self.guidepostSpacing * Int64(step)
            guard seq >= Int64(first) else { break }
            let value = UInt32(seq)
            if seen.insert(value).inserted { targets.append(value) }
        }
        // Anchor the oldest available entry so estimates near the start of history stay bounded.
        if seen.insert(first).inserted { targets.append(first) }

        let myToken = bumpToken()
        calibrationState = .running(done: 0, total: targets.count)

        probeQueue.async { [weak self] in
            guard let self else { return }
            for (index, seq) in targets.enumerated() {
                guard self.isCurrent(myToken) else { return }
                let log = fetcher.probeLog(sequenceNum: seq)
                DispatchQueue.main.async {
                    guard self.isCurrent(myToken) else { return }
                    if let log {
                        self.calibration.insert(
                            sequenceNum: log.sequenceNum,
                            date: Dates.fromJan12008EpochSecondsToDate(TimeInterval(log.pumpTimeSec))
                        )
                    }
                    self.calibrationState = .running(done: index + 1, total: targets.count)
                }
            }
            DispatchQueue.main.async {
                guard self.isCurrent(myToken) else { return }
                self.calibrationState = .ready
            }
        }
    }

    var isCalibrated: Bool { calibration.isUsable }

    /// e.g. "Calibrated from 31 points · 2026-06-20 → 2026-07-21"
    var calibrationSummary: String {
        switch calibrationState {
        case .idle:
            return "Not calibrated yet"
        case let .running(done, total):
            return "Calibrating… \(done)/\(total) sample logs"
        case .ready:
            guard let earliest = calibration.earliest, let latest = calibration.latest else {
                return "Calibration produced no samples"
            }
            let span = "\(Self.shortDate(earliest.date)) → \(Self.shortDate(latest.date))"
            return "Calibrated from \(calibration.count) point\(calibration.count == 1 ? "" : "s") · \(span)"
        }
    }

    // MARK: - Around-a-time navigation

    func setStartId(fromText text: String) {
        let digits = text.filter(\.isNumber)
        // Don't clamp mid-typing (a partial "4" shouldn't snap up to the first sequence number);
        // the window computation and the fetcher both clamp into range at fetch time.
        guard let value = UInt32(digits) else {
            if digits.isEmpty { startId = 0 }
            return
        }
        startId = value
    }

    /// Applies the current `pickerDate` to `startId` using the calibration estimate.
    func applyPickerDate() {
        guard let estimate = estimatedStartId(forDate: pickerDate) else { return }
        startId = estimate
    }

    /// Sets `pickerDate` to `daysAgo` days before now, then applies it.
    func applyDaysAgo() {
        pickerDate = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        applyPickerDate()
    }

    func resetStartToNewest() {
        guard let last = lastSequenceNum else { return }
        startId = last
        pickerDate = calibration.estimatedDate(forSequenceNum: last) ?? Date()
        daysAgo = 0
    }

    func estimatedStartId(forDate date: Date) -> UInt32? {
        calibration.estimatedSequenceNum(forDate: date, lowerBound: firstSequenceNum, upperBound: lastSequenceNum)
    }

    func estimatedDate(forSequenceNum sequenceNum: UInt32) -> Date? {
        calibration.estimatedDate(forSequenceNum: sequenceNum)
    }

    /// Human-readable estimated date for a sequence number, or "—" before calibration.
    func dateText(forSequenceNum sequenceNum: UInt32) -> String {
        guard let date = estimatedDate(forSequenceNum: sequenceNum) else { return "—" }
        return Self.shortDate(date)
    }

    /// The [start, end] ID window and count implied by the current Start ID + selected count.
    /// `end` is clamped into the pump's range so the summary matches what will actually be fetched.
    var aroundWindow: (start: UInt32, end: UInt32, count: Int)? {
        guard let first = firstSequenceNum else { return nil }
        let end = Int64(clampToPumpRange(startId))
        let start = max(Int64(first), end - Int64(selectedCount) + 1)
        guard end >= start else { return nil }
        return (UInt32(start), UInt32(end), Int(end - start) + 1)
    }

    /// e.g. "IDs 40960–41215 · 256 logs · 6/20/26, 2:14 PM → 6/20/26, 3:02 PM"
    var aroundWindowSummary: String? {
        guard let window = aroundWindow else { return nil }
        return "IDs \(window.start)–\(window.end) · \(window.count) logs · "
            + "\(dateText(forSequenceNum: window.start)) → \(dateText(forSequenceNum: window.end))"
    }

    /// The count that will actually be fetched for the current mode/selection, if known.
    var selectionCount: Int? {
        switch navigationMode {
        case .aroundTime:
            return aroundWindow?.count
        case .dateRange:
            return resolvedRange?.count ?? estimatedRangeCount
        }
    }

    /// Whether the current selection is large enough that a fetch would be slow.
    var isLargeSelection: Bool {
        (selectionCount ?? 0) > Self.largeFetchThreshold
    }

    // MARK: - Date-range navigation

    private func orderedRangeDates() -> (lower: Date, upper: Date) {
        rangeStart <= rangeEnd ? (rangeStart, rangeEnd) : (rangeEnd, rangeStart)
    }

    /// Clears a previously resolved range (call when the from/to dates change).
    func invalidateResolvedRange() {
        resolvedRange = nil
    }

    /// e.g. "1,240 logs · IDs 39001–40240" for the resolved date range.
    var resolvedRangeSummary: String? {
        guard let range = resolvedRange else { return nil }
        if range.isEmpty {
            return "No logs in that time range"
        }
        return "\(range.count) logs · IDs \(range.fromId)–\(range.toId)"
    }

    /// Rough count for the chosen date range straight from the calibration (no probing), shown live
    /// as the user adjusts the pickers.
    var estimatedRangeCount: Int? {
        let (lower, upper) = orderedRangeDates()
        guard let lo = estimatedStartId(forDate: lower), let hi = estimatedStartId(forDate: upper) else {
            return nil
        }
        return hi >= lo ? Int(hi - lo) + 1 : 0
    }

    /// Binary-searches the exact start/end IDs for the chosen date range, using guideposts to
    /// bracket the search and caching every probe. Runs in the background; `completion` fires on the
    /// main queue (with nil if resolution was superseded or failed).
    func resolveRange(completion: ((ResolvedRange?) -> Void)? = nil) {
        guard let fetcher, let first = firstSequenceNum, let last = lastSequenceNum else {
            completion?(nil)
            return
        }
        let (lower, upper) = orderedRangeDates()
        let snapshot = calibration
        let myToken = bumpToken()
        isResolvingRange = true
        resolvedRange = nil

        probeQueue.async { [weak self] in
            guard let self else { return }
            var cache: [UInt32: Date] = [:]
            for point in snapshot.points { cache[point.sequenceNum] = point.date }

            let probe: (UInt32) -> Date? = { seq in
                if let cached = cache[seq] { return cached }
                guard self.isCurrent(myToken) else { return nil }
                guard let log = fetcher.probeLog(sequenceNum: seq) else { return nil }
                let date = Dates.fromJan12008EpochSecondsToDate(TimeInterval(log.pumpTimeSec))
                cache[seq] = date
                return date
            }

            let fromBounds = snapshot.sequenceBounds(forDate: lower) ?? (first, last)
            let toBounds = snapshot.sequenceBounds(forDate: upper) ?? (first, last)

            let fromId = HistoryLogCalibration.binarySearchBoundary(
                .firstAtOrAfter, target: lower,
                lowerBound: fromBounds.lower, upperBound: fromBounds.upper, probe: probe
            )
            let toId = HistoryLogCalibration.binarySearchBoundary(
                .lastAtOrBefore, target: upper,
                lowerBound: toBounds.lower, upperBound: toBounds.upper, probe: probe
            )

            DispatchQueue.main.async {
                // Superseded by a newer operation or cancelled: drop silently so we don't clobber
                // freshly set state (e.g. a cancel that returned the UI to .ready).
                guard self.isCurrent(myToken) else { return }
                self.isResolvingRange = false
                // Fold newly learned points back into the calibration for sharper future estimates.
                for (seq, date) in cache {
                    self.calibration.insert(sequenceNum: seq, date: date)
                }
                let resolved = ResolvedRange(fromId: fromId, toId: toId)
                self.resolvedRange = resolved
                completion?(resolved)
            }
        }
    }

    // MARK: - Fetch

    func startFetch() {
        guard fetcher != nil, phase != .fetching else {
            return
        }
        // Stop any background probing so it can't contend with the fetch's stream subscription.
        _ = bumpToken()
        isResolvingRange = false

        switch navigationMode {
        case .aroundTime:
            beginFetch(numberOfLogs: selectedCount, endingAt: startId)

        case .dateRange:
            if let range = resolvedRange {
                guard !range.isEmpty else {
                    phase = .failed("No logs found in that time range")
                    return
                }
                beginFetch(numberOfLogs: range.count, endingAt: range.toId)
            } else {
                phase = .fetching
                resolveRange { [weak self] range in
                    guard let self else { return }
                    guard let range, !range.isEmpty else {
                        self.phase = .failed("No logs found in that time range")
                        return
                    }
                    self.beginFetch(numberOfLogs: range.count, endingAt: range.toId)
                }
            }
        }
    }

    private func beginFetch(numberOfLogs: Int, endingAt endingSequenceNum: UInt32) {
        guard let fetcher, numberOfLogs > 0 else {
            phase = .failed("Nothing to fetch for that selection")
            return
        }

        resetResults()
        phase = .fetching

        fetcher.onLog = { [weak self] log in
            self?.store(log)
        }
        fetcher.onStreamMessage = { [weak self] receivedAt, message in
            self?.streamMessages.append((receivedAt, message))
        }
        fetcher.onProgress = { [weak self] progress in
            self?.apply(progress)
        }

        fetcher.start(numberOfLogs: numberOfLogs, endingAtSequenceNum: endingSequenceNum) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(progress):
                self.apply(progress)
                self.phase = .complete
            case .failure(.cancelled):
                self.phase = self.hasLogs ? .complete : .ready
            case let .failure(error):
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancelFetch() {
        if isResolvingRange {
            // Still binary-searching the date range; abort probing and return to the controls.
            _ = bumpToken()
            isResolvingRange = false
            phase = hasLogs ? .complete : .ready
        } else {
            fetcher?.cancel()
        }
    }

    func stop() {
        _ = bumpToken()
        fetcher?.cancel()
    }

    func prettyDescription(for log: HistoryLog) -> String {
        HistoryLogExport.prettyDescription(log)
    }

    /// Writes all received stream messages as cliparser-format JSONL and returns the file URL.
    func exportFileURL() -> URL? {
        guard !streamMessages.isEmpty else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-logs-\(formatter.string(from: Date())).jsonl")

        let contents = HistoryLogExport.jsonl(for: streamMessages) + "\n"
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func relativeTimeAgo(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24

        if days > 0 {
            return "\(days)d\(hours % 24)h"
        }
        if hours > 0 {
            return "\(hours)h\(minutes % 60)m"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(seconds)s"
    }

    static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Private

    private func clampToPumpRange(_ value: UInt32) -> UInt32 {
        var result = value
        if let last = lastSequenceNum, result > last { result = last }
        if let first = firstSequenceNum, result < first { result = first }
        return result
    }

    private func bumpToken() -> Int {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        token += 1
        return token
    }

    private func isCurrent(_ candidate: Int) -> Bool {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        return token == candidate
    }

    private func resetResults() {
        logsBySequence = [:]
        logsByType = [:]
        logsDescending = []
        streamMessages = []
        fetchedCount = 0
        expectedCount = 0
        earliestFetched = nil
    }

    private func apply(_ progress: HistoryLogFetcher.Progress) {
        fetchedCount = progress.fetchedCount
        expectedCount = progress.expectedCount
        earliestFetched = progress.earliestFetched
    }

    private func store(_ log: HistoryLog) {
        guard logsBySequence[log.sequenceNum] == nil else {
            return
        }
        logsBySequence[log.sequenceNum] = log

        let typeName = HistoryLogExport.typeName(log)
        var typeLogs = logsByType[typeName] ?? []
        typeLogs.insert(log, at: insertionIndex(in: typeLogs, ascending: true, sequenceNum: log.sequenceNum))
        logsByType[typeName] = typeLogs

        let entry = LogEntry(log: log)
        let index = insertionIndexDescending(in: logsDescending, sequenceNum: log.sequenceNum)
        logsDescending.insert(entry, at: index)
    }

    private func insertionIndex(in logs: [HistoryLog], ascending: Bool, sequenceNum: UInt32) -> Int {
        var low = 0
        var high = logs.count
        while low < high {
            let mid = (low + high) / 2
            let midSeq = logs[mid].sequenceNum
            if ascending ? midSeq < sequenceNum : midSeq > sequenceNum {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private func insertionIndexDescending(in entries: [LogEntry], sequenceNum: UInt32) -> Int {
        var low = 0
        var high = entries.count
        while low < high {
            let mid = (low + high) / 2
            if entries[mid].log.sequenceNum > sequenceNum {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
