import LoopKit
import SwiftUI
import TandemCore

class TandemKitDeliveryLimitsViewModel: ObservableObject {
    @Published var maxBasalRate: Double = 2.5 { didSet { checkDirtyState() } }
    @Published var maxBolus: Double = 25.0 { didSet { checkDirtyState() } }
    @Published var defaultMaxBasalRate: Double?
    @Published var defaultMaxBolus: Double?

    @Published var isLoading: Bool = false
    @Published var isDirty: Bool = false
    @Published var isFetching: Bool = false
    @Published var saveError: String?

    private var originalMaxBasalRate: Double = 2.5
    private var originalMaxBolus: Double = 25.0

    private let pumpManager: TandemPumpManager?

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager

        guard let pumpManager = pumpManager else {
            return
        }

        let state = pumpManager.state
        if state.maxBasalLimitMilliunits != nil {
            loadFromState(state)
        }

        pumpManager.addStatusObserver(self, queue: .main)
    }

    deinit {
        pumpManager?.removeStatusObserver(self)
    }

    private func loadFromState(_ state: TandemPumpManagerState) {
        if let basalMilliunits = state.maxBasalLimitMilliunits {
            maxBasalRate = Double(basalMilliunits) / 1000.0
            originalMaxBasalRate = maxBasalRate
        }
        if let basalDefaultMilliunits = state.maxBasalLimitDefaultMilliunits {
            defaultMaxBasalRate = Double(basalDefaultMilliunits) / 1000.0
        }
        if let bolusMilliunits = state.maxBolusLimitMilliunits {
            maxBolus = Double(bolusMilliunits) / 1000.0
            originalMaxBolus = maxBolus
        }
        if let bolusDefaultMilliunits = state.maxBolusLimitDefaultMilliunits {
            defaultMaxBolus = Double(bolusDefaultMilliunits) / 1000.0
        }
    }

    var maxBasalRateText: String {
        String(format: "%.2f U/hr", maxBasalRate)
    }

    var maxBolusText: String {
        String(format: "%.1f U", maxBolus)
    }

    var defaultMaxBasalRateText: String? {
        guard let defaultMaxBasalRate else { return nil }
        return String(format: "Default: %.2f U/hr", defaultMaxBasalRate)
    }

    var defaultMaxBolusText: String? {
        guard let defaultMaxBolus else { return nil }
        return String(format: "Default: %.1f U", defaultMaxBolus)
    }

    func submit() {
        saveError = nil
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let pumpManager = self.pumpManager else {
                DispatchQueue.main.async { self?.isLoading = false }
                return
            }

            var success = true

            if self.maxBasalRate != self.originalMaxBasalRate {
                let milliunits = Int((self.maxBasalRate * 1000.0).rounded())
                if !pumpManager.setMaxBasalLimit(milliunits: milliunits) {
                    success = false
                }
            }

            if self.maxBolus != self.originalMaxBolus {
                let milliunits = Int((self.maxBolus * 1000.0).rounded())
                if !pumpManager.setMaxBolusLimit(milliunits: milliunits) {
                    success = false
                }
            }

            DispatchQueue.main.async {
                self.isLoading = false
                if success {
                    self.originalMaxBasalRate = self.maxBasalRate
                    self.originalMaxBolus = self.maxBolus
                    self.isDirty = false
                } else {
                    self.saveError = "Failed to update delivery limits. Check pump connection."
                }
            }
        }
    }

    func checkDirtyState() {
        DispatchQueue.main.async {
            self.isDirty = (
                self.originalMaxBasalRate != self.maxBasalRate ||
                    self.originalMaxBolus != self.maxBolus
            )
        }
    }
}

extension TandemKitDeliveryLimitsViewModel: PumpManagerStatusObserver {
    func pumpManager(
        _ loopkitPumpManager: any LoopKit.PumpManager,
        didUpdate _: LoopKit.PumpManagerStatus,
        oldStatus _: LoopKit.PumpManagerStatus
    ) {
        guard let pumpManager = loopkitPumpManager as? TandemPumpManager, !isDirty else { return }

        DispatchQueue.main.async {
            self.loadFromState(pumpManager.state)
            self.isFetching = false
        }
    }
}
