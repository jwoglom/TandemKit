import Foundation
import LoopKit

/// A pass dates by the pump's clock read before and after its history: read either side of a clock change, the
/// history and a lone reading disagree by the change, and neither host revises a dose once told its date.
extension TandemPumpManager {
    /// A sync reads the clock seconds before the tick it starts, which saves that tick its own read.
    static let pumpClockReadingReuseWindow: TimeInterval = 30

    static let heldHistoryAlertIdentifier = "held-history"

    func readPumpClock(reusingASyncsRead: Bool = false) -> PumpClockReading? {
        let now = self.now
        if reusingASyncsRead, let last = lastPumpClockReading {
            let age = now.timeIntervalSince(last.phoneDate)
            if age >= 0, age <= Self.pumpClockReadingReuseWindow {
                return last.carried(to: now)
            }
        }
        guard let response = bluetooth.write(TimeSinceResetRequest()) else {
            return nil
        }
        return PumpClockReading(pumpTimeSec: response.currentTime, phoneDate: self.now)
    }

    /// Call right after the history status read that gave `sequenceNum`, in its command job.
    func readPumpClockAnchor(atSequenceNum sequenceNum: UInt32) -> PumpClockAnchor? {
        readPumpClock(reusingASyncsRead: true).map {
            PumpClockAnchor(sequenceNum: sequenceNum, pumpTimeSec: $0.pumpTimeSec, phoneDate: $0.phoneDate)
        }
    }

    /// Reads the clock again after a tick's history read and, if it ran untouched since the tick's anchor,
    /// saves the anchor for the passes to date by. Otherwise gives why nothing may be dated this time.
    func confirmPumpClockAnchor(of outcome: HistoryBackfillCoordinator.TickOutcome, pumpSerial serial: HistoryLogSyncIdentifier.PumpSerial) -> String? {
        let anchor: PumpClockAnchor
        switch outcome.clock {
        case .notTaken:
            return nil
        case .unanswered:
            return "The pump did not give its clock before its history was read"
        case let .anchor(taken):
            anchor = taken
        }
        guard let after = readPumpClock() else {
            return "The pump did not give its clock after its history was read"
        }
        let before = PumpClockReading(pumpTimeSec: anchor.pumpTimeSec, phoneDate: anchor.phoneDate)
        guard before.agrees(with: after) else {
            return "The pump's clock moved while its history was read (\(before.pumpTimeSec) at \(before.phoneDate), \(after.pumpTimeSec) at \(after.phoneDate))"
        }
        state.pumpClockAnchors.record(anchor, pumpSerial: serial.rawValue)
        return nil
    }

    /// Before the app sets the pump's clock: every record so far is on the clock it had, whatever the pump
    /// then logs of the change. Read twice, since one bad reading saved here would misplace all of them.
    func recordPumpClockAnchorBeforeSettingTheClock() {
        guard state.featureFlags.historyBackfill, let serial = historyLogStoreSerial,
              let before = readPumpClock(),
              let status = bluetooth.write(HistoryLogStatusRequest()), status.numEntries > 0,
              let after = readPumpClock(), before.agrees(with: after)
        else {
            return
        }
        state.pumpClockAnchors.record(
            PumpClockAnchor(sequenceNum: status.lastSequenceNum, pumpTimeSec: after.pumpTimeSec, phoneDate: after.phoneDate),
            pumpSerial: serial.rawValue
        )
    }

    // MARK: - Held history

    /// - Parameters:
    ///   - examined: Every event the pass tried to date.
    ///   - held: Those it could not, each with how long its delivery may run on past now.
    func noteHeldHistory(examined: Set<Data>, held: [Data: TimeInterval], what: String) {
        let before = state.heldHistory
        state.heldHistory.update(examined: examined, held: held, now: now)
        let known = Set(before.entries.map(\.raw))
        let new = held.keys.filter { !known.contains($0) }
        if !new.isEmpty {
            logger.error("Holding \(new.count) \(what) from pump history that no pump clock reading dates: \(new.map(\.hexadecimalString).sorted())")
        }
        let remaining = Set(state.heldHistory.entries.map(\.raw))
        let dated = known.subtracting(remaining).intersection(examined)
        if !dated.isEmpty {
            logger.info("Pump history held before is dated now: \(dated.map(\.hexadecimalString).sorted())")
        }
    }

    var isHistoryHeldTooLong: Bool {
        !state.heldHistory.entriesHeldTooLong(now: now).isEmpty
    }

    func reconcileHeldHistoryAlert() {
        let warrants = isHistoryHeldTooLong
        guard warrants != state.heldHistoryAlertIssued else { return }

        let identifier = Self.alertIdentifier(Self.heldHistoryAlertIdentifier)
        pumpDelegate.notify { delegate in
            guard let delegate, warrants != self.state.heldHistoryAlertIssued else { return }

            if warrants {
                let content = LoopKit.Alert.Content(
                    title: String(localized: "Pump Event Not Counted", comment: "Title of the alert that the app could not date something in the pump's history"),
                    body: String(
                        localized: "The app could not tell when your pump recorded something in its history, so it has not counted it. Insulin on board in the app may be too low. Check your pump's screen for recent insulin, and check that its date and time are right.",
                        comment: "Body of the alert that the app could not date something in the pump's history"
                    ),
                    acknowledgeActionButtonLabel: String(localized: "OK", comment: "Acknowledges the alert that a pump event was not counted")
                )
                self.logger.error("Pump history has been held undated for \(Int(HeldHistoryLedger.warningDelay / 60)) min; issuing an alert")
                let alert = LoopKit.Alert(
                    identifier: identifier,
                    foregroundContent: content,
                    backgroundContent: content,
                    trigger: .immediate,
                    interruptionLevel: .timeSensitive
                )
                Task { await delegate.issueAlert(alert) }
            } else {
                self.logger.info("No pump history is held undated any more; retracting the alert")
                Task { await delegate.retractAlert(identifier: identifier) }
            }
            self.state.heldHistoryAlertIssued = warrants
            self.notifyDelegateStateUpdated()
        }
    }
}
