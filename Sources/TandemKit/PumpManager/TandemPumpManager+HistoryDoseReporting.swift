import Foundation
import LoopKit

/// Reports history boluses the live path didn't report or couldn't finish. Boluses only (#354).
extension TandemPumpManager {
    func reportHistoryDoses(after outcome: HistoryBackfillCoordinator.TickOutcome, now: Date) {
        guard state.featureFlags.historyDoseReporting,
              let serial = historyLogStoreSerial,
              let covered = outcome.sessionCovered
        else {
            return
        }

        // A command job, so it cannot interleave with the live path finalizing the same bolus.
        bluetooth.ensureConnected { error in
            if let error {
                self.logger.warning("Deferring history dose reporting to the next tick: \(error.localizedDescription)")
                var pass = HistoryBackfillMonitor.ReportingPass(date: self.now, covered: covered, floor: outcome.emitFloor)
                pass.result = .deferred(error.localizedDescription)
                self.historyBackfillMonitor.reportingPassFinished(pass)
                return
            }
            self.reportHistoryBoluses(in: covered, pumpSerial: serial, floor: outcome.emitFloor, now: now)
        }
    }

    func reportHistoryBoluses(
        in covered: ClosedRange<UInt32>,
        pumpSerial serial: HistoryLogSyncIdentifier.PumpSerial,
        floor: Date,
        now: Date
    ) {
        // `now` is when the tick started, which can be a whole walk earlier.
        let decidedAt = self.now
        var pass = HistoryBackfillMonitor.ReportingPass(date: decidedAt, covered: covered, floor: floor)
        defer { historyBackfillMonitor.reportingPassFinished(pass) }

        let logs: [HistoryLog]
        do {
            logs = try historyLogStore.logs(pumpSerial: serial.rawValue, in: covered)
                .map { $0.parsed() }
                .filter(Self.isReportedBolusInput)
        } catch {
            logger.error("Could not read the history log store for dose reporting: \(error)")
            pass.result = .storeUnreadable
            return
        }

        for bolex in logs.compactMap({ $0 as? BolexActivatedHistoryLog }) {
            logger.warning("Extended bolus \(bolex.bolusId) in pump history is not reported to the app")
            pass.extendedBoluses += 1
            if !state.bolusResolutionLog.contains(.extendedBolusNotReported, bolusId: bolex.bolusId) {
                state.bolusResolutionLog.record(BolusResolutionLog.Event(
                    date: decidedAt,
                    kind: .extendedBolusNotReported,
                    bolusId: bolex.bolusId,
                    doseDate: Dates.fromJan12008EpochSecondsToDate(TimeInterval(bolex.pumpTimeSec)),
                    programmedUnits: HistoryToDoseMapper.roundToReportingResolution(Double(bolex.bolexSize))
                ))
            }
        }
        let bolusSources = Self.bolusSources(in: logs)

        state.bolusReportLedger.prune(now: now)
        let ledger = state.bolusReportLedger

        // Fresh each pass: a shared one would apply each clock change once per pass.
        let events = HistoryToDoseMapper().mapToEvents(
            logs,
            reconciler: HistoryTimestampReconciler(),
            pumpSerial: serial,
            insulinType: state.insulinType,
            scheduledBasalRate: { _ in 0 },
            roundBasalRate: { $0 },
            isCommandedBolus: { ledger.entry(bolusId: $0, pumpSerial: serial.rawValue)?.origin == .commanded }
        )

        var reports: [NewPumpEvent] = []
        for event in events {
            guard let dose = event.dose, dose.type == .bolus,
                  let decoded = HistoryLogSyncIdentifier.decode(event.raw), decoded.scheme == .bolus
            else {
                continue
            }
            pass.boluses += 1
            guard dose.startDate >= floor else {
                pass.belowFloor += 1
                continue
            }

            let bolusId = Int(decoded.identifier)
            switch historyBolusDecision(event, dose: dose, bolusId: bolusId, serial: serial) {
            case let .report(report, kind):
                reports.append(report)
                pass.reported += 1
                state.bolusResolutionLog.record(BolusResolutionLog.Event(
                    date: decidedAt,
                    kind: kind,
                    bolusId: bolusId,
                    doseDate: report.date,
                    programmedUnits: report.dose?.programmedUnits,
                    deliveredUnits: report.dose?.isMutable == false ? report.dose?.deliveredUnits : nil,
                    isMutable: report.dose?.isMutable ?? false,
                    automatic: report.dose?.automatic,
                    bolusSource: bolusSources[bolusId]
                ))
            case .alreadyFinalized:
                pass.alreadyFinalized += 1
            case .awaitingCompletion:
                pass.awaitingCompletion += 1
            case .liveTracking:
                pass.leftToLivePath += 1
            }
        }

        guard !reports.isEmpty else {
            return
        }

        logger.info("Reporting \(reports.count) bolus event(s) from pump history")
        emitPumpEvents(reports.sorted { $0.date < $1.date }, replacePendingEvents: false)
        notifyDelegateStateUpdated()
    }

    private static func isReportedBolusInput(_ log: HistoryLog) -> Bool {
        switch log {
        case is BolusActivatedHistoryLog, is BolusCompletedHistoryLog, is BolusDeliveryHistoryLog,
             is BolusRequestedMsg2HistoryLog, is BolexActivatedHistoryLog,
             is TimeChangedHistoryLog, is DateChangeHistoryLog:
            return true
        default:
            return false
        }
    }

    /// `BolusDeliveryHistoryLog.BolusSource` raw value per `bolusId`.
    private static func bolusSources(in logs: [HistoryLog]) -> [Int: Int] {
        var sources: [Int: Int] = [:]
        for case let delivery as BolusDeliveryHistoryLog in logs {
            sources[delivery.bolusID] = delivery.bolusSource
        }
        return sources
    }

    private enum HistoryBolusDecision {
        case report(NewPumpEvent, BolusResolutionLog.Kind)
        case alreadyFinalized
        /// Already reported mutable; nothing new until its completion is read (#452).
        case awaitingCompletion
        case liveTracking
    }

    private func historyBolusDecision(
        _ event: NewPumpEvent,
        dose: DoseEntry,
        bolusId: Int,
        serial: HistoryLogSyncIdentifier.PumpSerial
    ) -> HistoryBolusDecision {
        guard let entry = state.bolusReportLedger.entry(bolusId: bolusId, pumpSerial: serial.rawValue) else {
            state.bolusReportLedger.record(BolusReportLedger.Entry(
                bolusId: bolusId,
                pumpSerial: serial.rawValue,
                origin: .history,
                raw: event.raw,
                eventDate: event.date,
                automatic: dose.automatic ?? false,
                isFinalized: false
            ))
            return .report(event, .pumpBolusFound)
        }

        guard !entry.isFinalized else {
            return .alreadyFinalized
        }
        guard !dose.isMutable else {
            return .awaitingCompletion
        }

        if entry.origin == .commanded {
            guard !isTrackingBolusLive(bolusId) else {
                return .liveTracking
            }
            releaseLiveBolusState(bolusId)
            return .report(Self.reported(dose, as: entry), .appBolusFinalizedFromHistory)
        }

        return .report(Self.reported(dose, as: entry), .pumpBolusFinalized)
    }

    private func isTrackingBolusLive(_ bolusId: Int) -> Bool {
        bolusProgressReport != nil && state.bolusDose?.bolusId == bolusId
    }

    private func releaseLiveBolusState(_ bolusId: Int) {
        if state.pendingBolusFinalization?.bolusId == bolusId {
            state.pendingBolusFinalization = nil
        }
        if state.bolusDose?.bolusId == bolusId {
            state.bolusDose = nil
            state.bolusState = .noBolus
        }
    }

    /// Under the host's existing identity and date, so it updates that row instead of adding one.
    private static func reported(_ dose: DoseEntry, as entry: BolusReportLedger.Entry) -> NewPumpEvent {
        let rekeyed = DoseEntry(
            type: .bolus,
            startDate: dose.startDate,
            endDate: dose.endDate,
            value: dose.programmedUnits,
            unit: .units,
            deliveredUnits: dose.deliveredUnits,
            description: dose.description,
            syncIdentifier: entry.raw.hexadecimalString,
            insulinType: dose.insulinType,
            automatic: entry.automatic,
            isMutable: dose.isMutable,
            wasProgrammedByPumpUI: entry.origin == .history
        )
        return NewPumpEvent(date: entry.eventDate, dose: rekeyed, raw: entry.raw, title: "Bolus", type: .bolus)
    }
}
