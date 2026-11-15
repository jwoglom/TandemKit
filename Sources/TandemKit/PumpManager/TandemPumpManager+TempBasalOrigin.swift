import Foundation

/// Who set a temp basal: what the host is told (`automatic`), and whether it is the host's own.
struct TempBasalOrigin: Equatable {
    let automatic: Bool
    let setByHost: Bool

    static let host = TempBasalOrigin(automatic: true, setByHost: true)
    static let settings = TempBasalOrigin(automatic: false, setByHost: false)

    init(automatic: Bool, setByHost: Bool) {
        self.automatic = automatic
        self.setByHost = setByHost
    }

    init(of dose: UnfinalizedDose) {
        self.init(automatic: dose.automatic, setByHost: dose.setByHost)
    }
}

extension TandemPumpManager {
    /// A temp runs at most 72 h, and basal reconciliation reports its cycles up to the 24 h
    /// reporting horizon after that.
    static let manualTempRateMemory: TimeInterval = .hours(72 + 24)

    /// History knows a temp set from TandemKit's settings only by its `tempRateId`, and its
    /// `SetTempRateResponse` record reads like the host's, so this is what keeps it manual there.
    func rememberManualTempRate(tempRateId: Int) {
        guard tempRateId > 0, let serial = historyLogStoreSerial else { return }
        state.manualTempRates = state.manualTempRates.filter { now.timeIntervalSince($0.value) < Self.manualTempRateMemory }
        state.manualTempRates[HistoryLogSyncIdentifier.tempRate(pumpSerial: serial, tempRateId: tempRateId)] = now
    }

    func isManualTempRate(_ tempRateId: Int) -> Bool {
        guard let serial = historyLogStoreSerial,
              let setAt = state.manualTempRates[HistoryLogSyncIdentifier.tempRate(pumpSerial: serial, tempRateId: tempRateId)]
        else {
            return false
        }
        return now.timeIntervalSince(setAt) < Self.manualTempRateMemory
    }
}
