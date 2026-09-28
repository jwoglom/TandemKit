import LoopKit
import SwiftUI

class TandemKitQuickBolusSettingsViewModel: ObservableObject {
    @Published var enabled: Bool = false { didSet { checkDirtyState() } }
    @Published var unitsIncrementIndex: Int = 0 { didSet { checkDirtyState() } }
    @Published var pumpIsInCarbsMode: Bool = false

    @Published var isLoading: Bool = false
    @Published var isDirty: Bool = false
    @Published var saveError: String?

    private var originalEnabled: Bool = false
    private var originalUnitsIncrementIndex: Int = 0

    private let pumpManager: TandemPumpManager?

    static let unitIncrements: [(label: String, increment: QuickBolusIncrement)] = [
        ("0.5 U", .units0_5),
        ("1.0 U", .units1_0),
        ("2.0 U", .units2_0),
        ("5.0 U", .units5_0)
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
        let incrementUnits = state.quickBolusIncrementUnits ?? 500

        enabled = isEnabled
        pumpIsInCarbsMode = isEnabled && state.quickBolusEntryType == QuickBolusMode.carbs.rawValue
        unitsIncrementIndex = Self.unitsIndexForMilliunits(incrementUnits)

        originalEnabled = enabled
        originalUnitsIncrementIndex = unitsIncrementIndex
    }

    private static func unitsIndexForMilliunits(_ milliunits: Int) -> Int {
        // PumpGlobalsResponse quickBolusIncrementUnits is in milliunits
        // 500 = 0.5U, 1000 = 1.0U, 2000 = 2.0U, 5000 = 5.0U
        switch milliunits {
        case ...500: return 0
        case 501 ... 1000: return 1
        case 1001 ... 2000: return 2
        default: return 3
        }
    }

    var selectedIncrement: QuickBolusIncrement {
        if !enabled {
            return .disabled
        }
        return Self.unitIncrements[unitsIncrementIndex].increment
    }

    func submit() {
        saveError = nil
        isLoading = true

        pumpManager?.setQuickBolusSettings(
            enabled: enabled,
            increment: selectedIncrement
        ) { success in
            DispatchQueue.main.async {
                self.isLoading = false
                guard success else {
                    self.saveError = String(
                        localized: "Could not save quick bolus settings to the pump.",
                        comment: "Error shown when saving quick bolus settings fails"
                    )
                    return
                }
                self.originalEnabled = self.enabled
                self.originalUnitsIncrementIndex = self.unitsIncrementIndex
                self.isDirty = false
                if let pumpManager = self.pumpManager {
                    self.loadFromState(pumpManager.state)
                }
            }
        }
    }

    func checkDirtyState() {
        DispatchQueue.main.async {
            self.isDirty = (
                self.originalEnabled != self.enabled ||
                    self.originalUnitsIncrementIndex != self.unitsIncrementIndex
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
