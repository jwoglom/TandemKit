import LoopKit
import SwiftUI
import TandemCore

class TandemKitQuickBolusSettingsViewModel: ObservableObject {
    @Published var enabled: Bool = false { didSet { checkDirtyState() } }
    @Published var modeIndex: Int = 0 { didSet { checkDirtyState() } }
    @Published var unitsIncrementIndex: Int = 0 { didSet { checkDirtyState() } }
    @Published var carbsIncrementIndex: Int = 0 { didSet { checkDirtyState() } }

    @Published var isLoading: Bool = false
    @Published var isDirty: Bool = false
    @Published var saveError: String?

    private var originalEnabled: Bool = false
    private var originalModeIndex: Int = 0
    private var originalUnitsIncrementIndex: Int = 0
    private var originalCarbsIncrementIndex: Int = 0

    private let pumpManager: TandemPumpManager?

    static let unitIncrements: [(label: String, increment: QuickBolusIncrement)] = [
        ("0.5 U", .units0_5),
        ("1.0 U", .units1_0),
        ("2.0 U", .units2_0),
        ("5.0 U", .units5_0),
    ]

    static let carbIncrements: [(label: String, increment: QuickBolusIncrement)] = [
        ("2 g", .carbs2g),
        ("5 g", .carbs5g),
        ("10 g", .carbs10g),
        ("15 g", .carbs15g),
    ]

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager

        guard let pumpManager = pumpManager else { return }

        let state = pumpManager.state
        loadFromState(state)

        pumpManager.addStatusObserver(self, queue: .main)
    }

    deinit {
        pumpManager?.removeStatusObserver(self)
    }

    private func loadFromState(_ state: TandemPumpManagerState) {
        let isEnabled = state.quickBolusEnabled ?? false
        let entryType = state.quickBolusEntryType ?? 0
        let incrementUnits = state.quickBolusIncrementUnits ?? 500
        let incrementCarbs = state.quickBolusIncrementCarbs ?? 2000

        enabled = isEnabled
        modeIndex = entryType == 1 ? 1 : 0

        // Map increment values to picker indices
        unitsIncrementIndex = Self.unitsIndexForMilliunits(incrementUnits)
        carbsIncrementIndex = Self.carbsIndexForMilliunits(incrementCarbs)

        originalEnabled = enabled
        originalModeIndex = modeIndex
        originalUnitsIncrementIndex = unitsIncrementIndex
        originalCarbsIncrementIndex = carbsIncrementIndex
    }

    private static func unitsIndexForMilliunits(_ milliunits: Int) -> Int {
        // PumpGlobalsResponse quickBolusIncrementUnits is in milliunits
        // 500 = 0.5U, 1000 = 1.0U, 2000 = 2.0U, 5000 = 5.0U
        switch milliunits {
        case ...500: return 0
        case 501...1000: return 1
        case 1001...2000: return 2
        default: return 3
        }
    }

    private static func carbsIndexForMilliunits(_ milliunits: Int) -> Int {
        // PumpGlobalsResponse quickBolusIncrementCarbs is in milliunits
        // 2000 = 2g, 5000 = 5g, 10000 = 10g, 15000 = 15g
        switch milliunits {
        case ...2000: return 0
        case 2001...5000: return 1
        case 5001...10000: return 2
        default: return 3
        }
    }

    var selectedIncrement: QuickBolusIncrement {
        if !enabled {
            return .disabled
        }
        if modeIndex == 1 {
            return Self.carbIncrements[carbsIncrementIndex].increment
        } else {
            return Self.unitIncrements[unitsIncrementIndex].increment
        }
    }

    var selectedMode: QuickBolusMode {
        modeIndex == 1 ? .carbs : .units
    }

    func submit() {
        saveError = nil
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let pumpManager = self.pumpManager else {
                DispatchQueue.main.async { self?.isLoading = false }
                return
            }

            pumpManager.setQuickBolusSettings(
                enabled: self.enabled,
                mode: self.selectedMode,
                increment: self.selectedIncrement
            )

            DispatchQueue.main.async {
                self.isLoading = false
                self.originalEnabled = self.enabled
                self.originalModeIndex = self.modeIndex
                self.originalUnitsIncrementIndex = self.unitsIncrementIndex
                self.originalCarbsIncrementIndex = self.carbsIncrementIndex
                self.isDirty = false
            }
        }
    }

    func checkDirtyState() {
        DispatchQueue.main.async {
            self.isDirty = (
                self.originalEnabled != self.enabled ||
                    self.originalModeIndex != self.modeIndex ||
                    self.originalUnitsIncrementIndex != self.unitsIncrementIndex ||
                    self.originalCarbsIncrementIndex != self.carbsIncrementIndex
            )
        }
    }
}

extension TandemKitQuickBolusSettingsViewModel: PumpManagerStatusObserver {
    func pumpManager(
        _: any LoopKit.PumpManager,
        didUpdate _: LoopKit.PumpManagerStatus,
        oldStatus _: LoopKit.PumpManagerStatus
    ) {
        guard let pumpManager = pumpManager, !isDirty else { return }

        DispatchQueue.main.async {
            self.loadFromState(pumpManager.state)
        }
    }
}
