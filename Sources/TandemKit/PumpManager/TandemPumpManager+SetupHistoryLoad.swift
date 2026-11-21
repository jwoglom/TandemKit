import Foundation

/// What the pump reports about its delivery when setup has just paired it.
public struct SetupDeliveryReading: Equatable, CustomStringConvertible {
    public enum LastBolus: Equatable {
        case unread
        /// The pump reports no bolus.
        case none
        /// On the phone's clock.
        case delivered(at: Date)
    }

    public var insulinOnBoard: Double?
    public var lastBolus: LastBolus
    /// Nil while suspended.
    public var currentBasalRate: Double?
    public var isSuspended: Bool

    public init(
        insulinOnBoard: Double? = nil,
        lastBolus: LastBolus = .unread,
        currentBasalRate: Double? = nil,
        isSuspended: Bool = false
    ) {
        self.insulinOnBoard = insulinOnBoard
        self.lastBolus = lastBolus
        self.currentBasalRate = currentBasalRate
        self.isSuspended = isSuspended
    }

    public var description: String {
        "IOB \(insulinOnBoard.map { "\($0) U" } ?? "unread"), last bolus \(lastBolus), "
            + (isSuspended ? "suspended" : "basal \(currentBasalRate.map { "\($0) U/hr" } ?? "unread")")
    }
}

/// What setup's history load read and reported.
public struct SetupHistoryLoadSummary: Equatable {
    /// The pump's bolus and basal records in the window, every one the reporting passes read.
    public var pumpBolusRecords: Int
    public var pumpBasalRecords: Int
    /// The doses the load reported to the host, by `raw`.
    public var reportedBolusRecords: Int
    public var reportedBasalRecords: Int

    public init(pumpBolusRecords: Int, pumpBasalRecords: Int, reportedBolusRecords: Int, reportedBasalRecords: Int) {
        self.pumpBolusRecords = pumpBolusRecords
        self.pumpBasalRecords = pumpBasalRecords
        self.reportedBolusRecords = reportedBolusRecords
        self.reportedBasalRecords = reportedBasalRecords
    }
}

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

    static let pumpBolusRecordTypes = [
        BolusActivatedHistoryLog.typeId, BolusRequestedMsg2HistoryLog.typeId, BolusDeliveryHistoryLog.typeId,
        BolusCompletedHistoryLog.typeId, BolexActivatedHistoryLog.typeId, BolexCompletedHistoryLog.typeId
    ]

    static let pumpBasalRecordTypes = [
        BasalDeliveryHistoryLog.typeId, DailyBasalHistoryLog.typeId, TempRateActivatedHistoryLog.typeId,
        TempRateCompletedHistoryLog.typeId, SetTempRateResponseHistoryLog.typeId,
        PumpingSuspendedHistoryLog.typeId, PumpingResumedHistoryLog.typeId
    ]

    /// Bolus reporting is what makes the load matter; without the backfill there is nothing to read.
    public var canLoadHistoryForSetup: Bool {
        state.featureFlags.historyBackfill && state.featureFlags.historyDoseReporting
    }

    /// Called before setup pairs a pump. A history load the user declines leaves everything the pump wrote
    /// before pairing unread: the first history status read after it floors the walk at the pump's newest record.
    public func holdHistoryBeforePairing() {
        guard !state.onboarded else {
            return
        }
        state.historyBeforePairing = .held
    }

    /// Run once pairing is done and before setup writes anything, so it reads what the pump was doing
    /// for its last user.
    public func readDeliveryForSetup(completion: @escaping (SetupDeliveryReading) -> Void) {
        bluetooth.ensureConnected { error in
            if let error {
                self.logger.warning("Pump delivery not read during setup: \(error.localizedDescription)")
                completion(SetupDeliveryReading())
                return
            }
            self.fetchPumpInformation()
            // Takes the pairing floor now, not at the setup sync: a pump-screen bolus while the user chooses is after it.
            if self.state.historyBeforePairing == .held {
                self.historyBackfillCoordinator.runTick()
            }
            self.fetchTimeSinceReset()
            // The IOB opcode is known only once the pump has answered a Control-IQ read.
            self.fetchControlIQStatus()

            let basal = self.bluetooth.write(CurrentBasalStatusRequest())
            let reading = SetupDeliveryReading(
                insulinOnBoard: self.readInsulinOnBoardForSetup(),
                lastBolus: self.readLastBolusForSetup(),
                currentBasalRate: basal.flatMap { $0.basalType == .suspend ? nil : $0.currentBasalRate },
                isSuspended: basal?.basalType == .suspend
            )
            self.logger.info("Pump delivery before setup: \(reading)")
            completion(reading)
        }
    }

    private func readInsulinOnBoardForSetup() -> Double? {
        guard state.controlIQEnabled != nil, let response = bluetooth.write(ControlIQIOBRequest()) else {
            return nil
        }
        return Double(response.pumpDisplayedIOB) / 1000
    }

    private func readLastBolusForSetup() -> SetupDeliveryReading.LastBolus {
        let request = LastBolusRequestBuilder.create(apiVersion: state.pumpState.apiVersion, pumpModel: state.pumpState.pumpModel)
        guard let response = bluetooth.write(request) as? LastBolusStatusAbstractResponse else {
            return .unread
        }
        let pumpDate: Date?
        if let v3 = response as? LastBolusStatusV3Response {
            pumpDate = v3.sections.filter { $0.timestamp != 0 }.map(\.timestampDate).max()
        } else {
            pumpDate = response.timestamp == 0 ? nil : response.timestampDate
        }
        guard let pumpDate else {
            return .none
        }
        guard let pumpNow = bluetooth.write(TimeSinceResetRequest())?.currentTimeDate else {
            return .unread
        }
        return .delivered(at: now.addingTimeInterval(-pumpNow.timeIntervalSince(pumpDate)))
    }

    /// `progress` is called from 0 to 1 on an unspecified queue while the load runs, `completion` once.
    public func loadHistoryForSetup(
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<SetupHistoryLoadSummary, Error>) -> Void
    ) {
        let since = now.addingTimeInterval(-Self.setupHistoryLoadWindow)
        logger.info("Loading pump history since \(since) for setup")
        if state.historyBeforePairing != .read {
            state.historyBeforePairing = .loaded
        }
        state.bolusReportLedger.reportHistory(since: since)
        state.reportedBasal.reportHistory(since: since)
        state.deliveryTransitions.reportHistory(since: since)
        notifyDelegateStateUpdated()
        _ = heldEventsSinceSetupHistoryLoadStarted(starting: true)

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
                if let error {
                    completion(.failure(error))
                    return
                }
                let summary = self.setupHistoryLoadSummary(since: since)
                self.logger.info("Loaded pump history for setup: \(summary)")
                progress(1)
                completion(.success(summary))
            }
        }
    }

    func setupHistoryLoadSummary(since: Date) -> SetupHistoryLoadSummary {
        var reportedBoluses = Set<Data>()
        var reportedBasal = Set<Data>()
        for event in heldEventsSinceSetupHistoryLoadStarted(starting: false) {
            switch event.dose?.type {
            case .bolus?:
                reportedBoluses.insert(event.raw)
            case .basal?, .tempBasal?, .suspend?, .resume?:
                reportedBasal.insert(event.raw)
            case nil:
                break
            }
        }
        return SetupHistoryLoadSummary(
            pumpBolusRecords: pumpRecordCount(ofTypes: Self.pumpBolusRecordTypes, since: since),
            pumpBasalRecords: pumpRecordCount(ofTypes: Self.pumpBasalRecordTypes, since: since),
            reportedBolusRecords: reportedBoluses.count,
            reportedBasalRecords: reportedBasal.count
        )
    }

    private func pumpRecordCount(ofTypes typeIds: [Int], since: Date) -> Int {
        guard let serial = historyLogStoreSerial, let range = reportableHistoryRange else {
            return 0
        }
        do {
            return try datedHistory(ofTypes: typeIds, in: range, since: since, pumpSerial: serial).logs.count
        } catch {
            logger.warning("Could not count the pump's records for setup: \(error)")
            return 0
        }
    }

    /// The share of the window from `since` to now that the session's store spans.
    func setupHistoryLoadProgress(since: Date) -> Double {
        guard let span = historyBackfillCoordinator.sessionPhoneTimeSpan() else {
            return 0
        }
        let window = now.timeIntervalSince(since)
        guard window > 0 else {
            return 0
        }
        let covered = span.upperBound.timeIntervalSince(max(span.lowerBound, since))
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
