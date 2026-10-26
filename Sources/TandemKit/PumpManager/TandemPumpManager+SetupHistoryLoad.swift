import Foundation

public enum SetupHistoryLoadError: Error, Equatable {
    case historyUnreadable
}

extension SetupHistoryLoadError: LocalizedError {
    public var errorDescription: String? {
        String(
            localized: "The pump's history could not be read. Keep the pump near your phone and try again.",
            comment: "Error when setup could not read the pump's history log"
        )
    }
}

/// Setup's history load: reports what the pump delivered in the `setupHistoryLoadWindow` before
/// it was paired. A new manager reports nothing older than its ledgers' `trackingSince`, since it cannot
/// tell another host's app boluses from the pump's own; the user's answer can. Run before the host
/// adopts the manager, so the host doses on none of the pump's history until all of it has been
/// reported: the reports are held, and replayed when it attaches.
extension TandemPumpManager {
    public static let setupHistoryLoadWindow: TimeInterval = .hours(6)

    /// Done once a tick has read to the pump's newest record as of a status read this recent. Not the
    /// newest record's own age: an idle pump writes a BasalDelivery record only every 5 minutes.
    static let setupHistoryLoadMaximumLag: TimeInterval = .minutes(1)

    /// Ticks in a row that read nothing before the load fails.
    static let setupHistoryLoadFailureLimit = 3

    static let setupHistoryLoadRetryDelay: TimeInterval = .seconds(2)

    static let setupHistoryLoadProgressInterval: TimeInterval = .seconds(1)

    /// Bolus reporting is what makes the load matter; without the backfill there is nothing to read.
    public var canLoadHistoryForSetup: Bool {
        state.featureFlags.historyBackfill && state.featureFlags.historyDoseReporting
    }

    /// `progress` is called from 0 to 1 on an unspecified queue while the load runs, `completion` once.
    public func loadHistoryForSetup(progress: @escaping (Double) -> Void, completion: @escaping (Error?) -> Void) {
        let since = now.addingTimeInterval(-Self.setupHistoryLoadWindow)
        logger.info("Loading pump history since \(since) for setup")
        inheritArchivedReports()
        state.bolusReportLedger.reportHistory(since: since)
        state.reportedBasal.reportHistory(since: since)
        state.deliveryTransitions.reportHistory(since: since)
        notifyDelegateStateUpdated()

        let progressQueue = DispatchQueue(label: "com.jwoglom.TandemKit.setupHistoryLoad")
        let timer = DispatchSource.makeTimerSource(queue: progressQueue)
        timer.schedule(deadline: .now(), repeating: Self.setupHistoryLoadProgressInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            progress(self.setupHistoryLoadProgress(since: since))
        }
        timer.resume()

        runSetupHistoryLoadTick(failures: 0) { error in
            timer.cancel()
            // Behind a reading already under way, so none lands after the last.
            progressQueue.async {
                if error == nil {
                    self.logger.info("Loaded pump history for setup")
                    progress(1)
                }
                completion(error)
            }
        }
    }

    /// The host still counts what managers deleted from this app reported for the pump.
    func inheritArchivedReports() {
        guard let serial = state.pumpState.pumpSerial,
              let reported = reportedHistoryArchive.reported(pumpSerial: serial, now: now)
        else {
            return
        }
        logger.info(
            "Taking \(reported.boluses.count) bolus(es), \(reported.basalRows.count) basal row(s) and \(reported.transitions.count) suspend/resume(s) this app was given for pump \(serial) as reported"
        )
        state.bolusReportLedger.inherit(reported.boluses)
        state.reportedBasal.inherit(reported.basalRows)
        state.deliveryTransitions.inherit(reported.transitions)
    }

    /// For the next manager this app sets up for the pump, with what earlier ones archived. Only what the
    /// host keeps: the next manager's first replacing batch deletes a mutable row.
    func archiveReportedHistory() {
        guard let serial = state.pumpState.pumpSerial else {
            return
        }
        var boluses = state.bolusReportLedger
        var basal = state.reportedBasal
        var transitions = state.deliveryTransitions
        if let earlier = reportedHistoryArchive.reported(pumpSerial: serial, now: now) {
            boluses.inherit(earlier.boluses)
            basal.inherit(earlier.basalRows)
            transitions.inherit(earlier.transitions)
        }
        boluses.prune(now: now)
        basal.prune(now: now)
        transitions.prune(before: now.addingTimeInterval(-DeliveryTransitionLedger.retention))
        // Another pump's record numbers would mark this one's records as reported.
        let transitionsAreThisPumps = transitions.pumpSerial.map { $0 == serial } ?? true
        let reported = ReportedHistoryArchive.Reported(
            savedAt: now,
            boluses: boluses.entries.filter { $0.isFinalized && $0.pumpSerial == serial },
            basalRows: basal.rows.filter { !$0.isMutable },
            transitions: transitionsAreThisPumps ? transitions.entries.filter(\.isReported) : []
        )
        reportedHistoryArchive.save(reported, pumpSerial: serial)
        logger.info(
            "Archived \(reported.boluses.count) bolus(es), \(reported.basalRows.count) basal row(s) and \(reported.transitions.count) suspend/resume(s) given for pump \(serial)"
        )
    }

    /// The share of the window from `since` to the pump's clock now that the session's store spans.
    func setupHistoryLoadProgress(since: Date) -> Double {
        guard let span = historyBackfillCoordinator.sessionPumpTimeSpan() else {
            return 0
        }
        let pumpSince = since.addingTimeInterval(state.pumpClockOffset)
        let pumpNow = now.addingTimeInterval(state.pumpClockOffset)
        let window = pumpNow.timeIntervalSince(pumpSince)
        guard window > 0 else {
            return 0
        }
        let covered = span.upperBound.timeIntervalSince(max(span.lowerBound, pumpSince))
        return min(max(covered / window, 0), 1)
    }

    func isSetupHistoryLoaded(by outcome: HistoryBackfillCoordinator.TickOutcome) -> Bool {
        outcome.isDeepBackfillComplete && outcome.readsThroughPumpEnd
            && now.timeIntervalSince(outcome.startedAt) < Self.setupHistoryLoadMaximumLag
    }

    private func runSetupHistoryLoadTick(failures: Int, completion: @escaping (Error?) -> Void) {
        historyBackfillCoordinator.runTick { outcome in
            guard let outcome else {
                // A tick already running reruns itself once it ends, but tells nobody.
                let isBusy = self.historyBackfillCoordinator.isTickRunning || self.historyFetchGate.isBusy
                self.retrySetupHistoryLoad(failures: isBusy ? failures : failures + 1, completion: completion)
                return
            }
            guard self.isSetupHistoryLoaded(by: outcome) else {
                self.runSetupHistoryLoadTick(failures: outcome.rangesRead.isEmpty ? failures + 1 : 0, completion: completion)
                return
            }
            // The tick's report pass is a command job queued ahead of this one.
            self.bluetooth.ensureConnected { _ in
                let reported = self.reconciliationLog.passes.contains { $0.startedAt == outcome.startedAt && $0.skipped == nil }
                guard reported else {
                    self.retrySetupHistoryLoad(failures: failures + 1, completion: completion)
                    return
                }
                completion(nil)
            }
        }
    }

    private func retrySetupHistoryLoad(failures: Int, completion: @escaping (Error?) -> Void) {
        guard failures < Self.setupHistoryLoadFailureLimit else {
            logger.error("Could not load pump history for setup")
            completion(SetupHistoryLoadError.historyUnreadable)
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.setupHistoryLoadRetryDelay) {
            self.runSetupHistoryLoadTick(failures: failures, completion: completion)
        }
    }
}
