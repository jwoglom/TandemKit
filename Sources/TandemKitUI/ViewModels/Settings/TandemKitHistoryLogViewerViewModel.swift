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
    @Published var selectedCount: Int = 256
    @Published var pumpStatusDescription: String?
    @Published var fetchedCount = 0
    @Published var expectedCount = 0
    @Published var earliestFetched: Date?

    /// History logs keyed by sequence number.
    @Published private(set) var logsBySequence: [UInt32: HistoryLog] = [:]
    /// History logs grouped by type name, each list sorted ascending by sequence number.
    @Published private(set) var logsByType: [String: [HistoryLog]] = [:]
    /// All history logs sorted descending by sequence number, for the "By Time" tab.
    @Published private(set) var logsDescending: [LogEntry] = []

    /// Multiples of 32 offered in the "how many logs back" dropdown.
    let countOptions: [Int] = Array(stride(from: 32, through: 8192, by: 32))

    private let pumpManager: TandemPumpManager?
    private var fetcher: HistoryLogFetcher?
    /// Every stream message received during fetches, in arrival order, for JSONL export.
    private var streamMessages: [(receivedAt: Date, message: HistoryLogStreamResponse)] = []

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
                    self.phase = .ready
                } else {
                    self.pumpStatusDescription = "Unable to read history log status from the pump"
                    self.phase = .statusUnavailable
                }
            }
        }
    }

    func startFetch() {
        guard let fetcher, phase != .fetching else {
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

        fetcher.start(numberOfLogs: selectedCount) { [weak self] result in
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
        fetcher?.cancel()
    }

    func stop() {
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
