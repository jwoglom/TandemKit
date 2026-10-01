import Combine
import Foundation

final class TandemKitFeatureFlagsViewModel: ObservableObject {
    @Published private(set) var values: [TandemFeatureFlags.Flag: Bool] = [:]

    private let pumpManager: TandemPumpManager?

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
        values = Dictionary(uniqueKeysWithValues: TandemFeatureFlags.Flag.allCases.map { flag in
            (flag, pumpManager?.state.featureFlags[flag] ?? flag.defaultValue)
        })
    }

    var flags: [TandemFeatureFlags.Flag] {
        TandemFeatureFlags.Flag.allCases
    }

    var hasFlagOffItsDefault: Bool {
        flags.contains { isEnabled($0) != $0.defaultValue }
    }

    func isEnabled(_ flag: TandemFeatureFlags.Flag) -> Bool {
        values[flag] ?? flag.defaultValue
    }

    func setFlag(_ flag: TandemFeatureFlags.Flag, enabled: Bool) {
        pumpManager?.setFeatureFlag(flag, enabled: enabled)
        values[flag] = enabled
    }
}
