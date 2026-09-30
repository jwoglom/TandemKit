import Foundation
import SwiftUI
import UIKit

final class TandemKitHistoryBackfillViewModel: ObservableObject {
    @Published private(set) var report: HistoryBackfillReport?
    @Published private(set) var isReadingStatus = false
    @Published private(set) var statusReadFailed = false
    @Published private(set) var isRunningTick = false
    @Published var showingResetConfirmation = false

    static let refreshInterval: TimeInterval = 5

    private let pumpManager: TandemPumpManager?
    private let snapshotQueue = DispatchQueue(label: "com.jwoglom.TandemKit.historyBackfillDiagnostics")
    private var refreshTimer: Timer?

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
    }

    deinit {
        refreshTimer?.invalidate()
    }

    var isBackfillEnabled: Bool {
        pumpManager?.state.featureFlags.historyBackfill == true
    }

    func start() {
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Built off the main queue: the snapshot walks the session history store.
    func refresh() {
        guard let pumpManager else {
            return
        }
        snapshotQueue.async { [weak self] in
            let report = HistoryBackfillReport(pumpManager.historyBackfillSnapshot())
            DispatchQueue.main.async {
                self?.report = report
            }
        }
    }

    func readPumpStatus() {
        guard let pumpManager, !isReadingStatus else {
            return
        }
        isReadingStatus = true
        statusReadFailed = false
        pumpManager.readHistoryLogStatus { [weak self] reading in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.isReadingStatus = false
                self.statusReadFailed = reading == nil
                self.refresh()
            }
        }
    }

    func runTick() {
        guard let pumpManager, isBackfillEnabled, !isRunningTick else {
            return
        }
        isRunningTick = true
        pumpManager.runHistoryBackfillTick { [weak self] in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.isRunningTick = false
                self.refresh()
            }
        }
        refresh()
    }

    func copyReport() {
        guard let report else {
            return
        }
        UIPasteboard.general.string = report.text
    }

    func resetCounts() {
        pumpManager?.resetHistoryDiagnostics()
        refresh()
    }
}
