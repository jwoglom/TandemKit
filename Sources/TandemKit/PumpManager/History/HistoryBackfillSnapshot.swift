import Foundation
import LoopKit

/// The history backfill and history dose reporting at one moment, for the diagnostics screen.
/// `HistoryBackfillReport` lays it out.
struct HistoryBackfillSnapshot {
    struct Bolus: Equatable {
        let bolusId: Int?
        let programmedUnits: Double
        /// The date it is reported under.
        let programmedAt: Date
        let deliveryStartedAt: Date?
        /// For a held bolus, when it was held: the start of the retry window.
        let estimatedEndAt: Date
        /// For a held bolus, its fallback.
        let deliveredUnits: Double
        let automatic: Bool

        init(_ dose: UnfinalizedDose) {
            bolusId = dose.bolusId
            programmedUnits = dose.value
            programmedAt = dose.startDate
            deliveryStartedAt = dose.deliveryStartDate
            estimatedEndAt = dose.estimatedEndDate
            deliveredUnits = dose.deliveredUnits
            automatic = dose.automatic
        }
    }

    struct Basal: Equatable {
        let type: DoseType
        let rate: Double
        let startedAt: Date
        let estimatedEndAt: Date
        let tempRateId: Int?

        init(_ dose: UnfinalizedDose) {
            type = dose.type
            rate = dose.value
            startedAt = dose.startDate
            estimatedEndAt = dose.estimatedEndDate
            tempRateId = dose.tempRateId
        }
    }

    struct StoredEntry: Equatable {
        let sequenceNum: UInt32
        /// Raw pump clock, as `StoredHistoryLog.pumpDate`.
        let pumpDate: Date
        let receivedAt: Date

        init(_ log: StoredHistoryLog) {
            sequenceNum = log.sequenceNum
            pumpDate = log.pumpDate
            receivedAt = log.receivedAt
        }
    }

    let capturedAt: Date
    let flags: TandemFeatureFlags
    let isPumpSerialKnown: Bool
    /// Nil until a tick has saved some.
    let bookkeeping: HistoryBackfillState?
    /// Nil when there is no bookkeeping or no serial to compare it with.
    let bookkeepingMatchesPump: Bool?
    let deepFetchTarget: Date
    let emitFloor: Date
    let monitor: HistoryBackfillMonitor.Snapshot
    let watermarkEntry: StoredEntry?
    let newestPumpEntry: StoredEntry?
    let sessionOldestEntry: StoredEntry?
    let sessionNewestEntry: StoredEntry?
    /// Includes whatever the History Log Viewer read.
    let storedEntryCount: Int
    let storeGaps: [ClosedRange<UInt32>]
    let prunedBelow: UInt32?
    let isHistoryStreamBusy: Bool
    let bolusState: PumpManagerStatus.BolusState
    let activeBolus: Bolus?
    let hasBolusProgressReporter: Bool
    let heldBolus: Bolus?
    let basal: Basal
    let lastReconciliation: Date?
    let pumpClockOffset: TimeInterval
    let ledger: BolusReportLedger
    let resolutions: BolusResolutionLog
}

extension TandemPumpManager {
    func historyBackfillSnapshot(now: Date? = nil) -> HistoryBackfillSnapshot {
        let now = now ?? self.now
        let state = state
        let monitor = historyBackfillMonitor.snapshot
        let serial = HistoryLogSyncIdentifier.PumpSerial(state.pumpState.pumpSerial)
        let covered = monitor.sessionCovered

        func stored(_ sequenceNum: UInt32?) -> HistoryBackfillSnapshot.StoredEntry? {
            guard let sequenceNum, let serial,
                  let log = try? historyLogStore.logs(pumpSerial: serial.rawValue, in: sequenceNum ... sequenceNum).first
            else {
                return nil
            }
            return HistoryBackfillSnapshot.StoredEntry(log)
        }

        var resolutions = state.bolusResolutionLog
        resolutions.prune(now: now)

        return HistoryBackfillSnapshot(
            capturedAt: now,
            flags: state.featureFlags,
            isPumpSerialKnown: serial != nil,
            bookkeeping: state.historyBackfill,
            bookkeepingMatchesPump: serial.flatMap { serial in
                state.historyBackfill.map { $0.pumpSerial == serial.rawValue }
            },
            deepFetchTarget: HistoryBackfillPlanner.deepFetchTarget(firstSeenFloor: state.historyBackfill?.firstSeenFloor, now: now),
            emitFloor: HistoryBackfillPlanner.emitFloor(
                bookkeeping: state.historyBackfill,
                trackingSince: state.bolusReportLedger.trackingSince,
                now: now
            ),
            monitor: monitor,
            watermarkEntry: stored(state.historyBackfill?.watermark),
            newestPumpEntry: stored(monitor.lastStatus?.lastSequenceNum),
            sessionOldestEntry: stored(covered?.lowerBound),
            sessionNewestEntry: stored(covered?.upperBound),
            storedEntryCount: serial.flatMap { try? historyLogStore.count(pumpSerial: $0.rawValue) } ?? 0,
            storeGaps: serial.flatMap { serial in
                covered.flatMap { try? historyLogStore.missingRanges(pumpSerial: serial.rawValue, in: $0) }
            } ?? [],
            prunedBelow: serial.flatMap { try? historyLogStore.prunedBelowSequenceNum(pumpSerial: $0.rawValue) },
            isHistoryStreamBusy: historyFetchGate.isBusy,
            bolusState: state.bolusState,
            activeBolus: state.bolusDose.map(HistoryBackfillSnapshot.Bolus.init),
            hasBolusProgressReporter: bolusProgressReport != nil,
            heldBolus: state.pendingBolusFinalization.map(HistoryBackfillSnapshot.Bolus.init),
            basal: HistoryBackfillSnapshot.Basal(state.basalDose),
            lastReconciliation: state.lastReconciliation,
            pumpClockOffset: state.pumpClockOffset,
            ledger: state.bolusReportLedger,
            resolutions: resolutions
        )
    }

    /// Reads `HistoryLogStatus` now instead of waiting for the next tick.
    func readHistoryLogStatus(completion: @escaping (HistoryLogStatusReading?) -> Void) {
        bluetooth.ensureConnected { error in
            guard error == nil, let response = self.bluetooth.write(HistoryLogStatusRequest()) else {
                completion(nil)
                return
            }
            let reading = HistoryLogStatusReading(response, readAt: self.now)
            self.historyBackfillMonitor.statusRead(reading)
            completion(reading)
        }
    }

    /// Runs a backfill tick now instead of at the next sync. A no-op while the flag is off.
    func runHistoryBackfillTick(completion: @escaping () -> Void) {
        historyBackfillCoordinator.runTick { _ in completion() }
    }

    func resetHistoryDiagnostics() {
        state.bolusResolutionLog.reset(now: now)
        historyBackfillMonitor.resetTotals()
        notifyDelegateStateUpdated()
    }
}
