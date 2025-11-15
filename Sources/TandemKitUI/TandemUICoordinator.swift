import LoopKit
import LoopKitUI

class TandemUICoordinator: UINavigationController, PumpManagerOnboarding, CompletionNotifying, UINavigationControllerDelegate {
    var pumpManagerOnboardingDelegate: PumpManagerOnboardingDelegate?

    var completionDelegate: CompletionDelegate?

    private let colorPalette: LoopUIColorPalette

    private var pumpManager: TandemPumpManager?

    private var allowedInsulinTypes: [InsulinType]

    private var allowDebugFeatures: Bool

    init(
        pumpManager: TandemPumpManager? = nil,
        colorPalette: LoopUIColorPalette,
        pumpManagerSettings: PumpManagerSetupSettings? = nil,
        allowDebugFeatures: Bool,
        allowedInsulinTypes: [InsulinType] = []
    )
    {
        if pumpManager == nil, pumpManagerSettings == nil {
            self
                .pumpManager =
                TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]) ?? TandemPumpManagerState(pumpState: nil))
        } else {
            self.pumpManager = pumpManager
        }

        self.colorPalette = colorPalette

        self.allowDebugFeatures = allowDebugFeatures

        self.allowedInsulinTypes = allowedInsulinTypes

        super.init(navigationBarClass: UINavigationBar.self, toolbarClass: UIToolbar.self)
    }

    @available(*, unavailable)  required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
