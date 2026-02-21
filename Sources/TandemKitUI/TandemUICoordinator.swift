import LoopKit
import LoopKitUI
import SwiftUI

enum TandemScreen {
    case setup
    case deviceScanning
    case setupComplete
    case pumpSettings
    case insulinType
    case soundSettings

    func next() -> TandemScreen? {
        switch self {
        case .setup:
            return .insulinType
        case .insulinType:
            return .soundSettings
        case .soundSettings:
            return .deviceScanning
        case .deviceScanning:
            return .setupComplete
        case .setupComplete:
            return .pumpSettings
        default:
            return nil
        }
    }
}

protocol TandemUINavigator: AnyObject {
    func navigateTo(_ screen: TandemScreen)
}

class TandemUICoordinator: UINavigationController, PumpManagerOnboarding, CompletionNotifying, UINavigationControllerDelegate {
    var pumpManagerOnboardingDelegate: PumpManagerOnboardingDelegate?

    var completionDelegate: CompletionDelegate?

    var screenStack = [TandemScreen]()
    var currentScreen: TandemScreen {
        screenStack.last!
    }

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
        if pumpManager == nil {
            self.pumpManager =
                TandemPumpManager(state: TandemPumpManagerState(
                    pumpState: nil,
                    basalDeliveryState: .active(Date.now),
                    basalRateSchedule: pumpManagerSettings?.basalSchedule,
                ))
        } else {
            self.pumpManager = pumpManager
        }

        self.colorPalette = colorPalette

        self.allowDebugFeatures = allowDebugFeatures

        self.allowedInsulinTypes = allowedInsulinTypes

        super.init(navigationBarClass: UINavigationBar.self, toolbarClass: UIToolbar.self)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self

        navigationBar.prefersLargeTitles = true // Ensure nav bar text is displayed correctly

        if screenStack.isEmpty {
            screenStack = [getInitialScreen()]
            let viewController = viewControllerForScreen(currentScreen)
            viewController.isModalInPresentation = false
            setViewControllers([viewController], animated: false)
        }
    }

    private func hostingController<Content: View>(rootView: Content) -> DismissibleHostingController<some View> {
        let rootView = rootView
            .environment(\.appName, Bundle.main.bundleDisplayName)
        return DismissibleHostingController(content: rootView, colorPalette: colorPalette)
    }

    private func viewControllerForScreen(_ screen: TandemScreen) -> UIViewController {
        switch screen {
        case .setup:
            let view = TandemKitSetupView(nextAction: stepFinished)
            return hostingController(rootView: view)
        case .deviceScanning:
            let nextStep = {
                self.resetNavigationTo([.setupComplete])
            }

            let viewModel = TandemKitScanViewModel(pumpManager, nextStep: nextStep)
            return hostingController(rootView: TandemKitScanView(viewModel: viewModel))
        case .setupComplete:
            pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didOnboardPumpManager: pumpManager!)
            let returnToMainScreen: () -> Void = {
                guard let pumpManager = self.pumpManager else {
                    return
                }

                var state = pumpManager.state
                state.onboarded = true
                pumpManager.lockedState.value = state

                self.pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didCreatePumpManager: pumpManager)
                self.completionDelegate?.completionNotifyingDidComplete(self)
            }

            let view = TandemKitSetupCompleteView(finish: returnToMainScreen)
            return hostingController(rootView: view)
        case .insulinType:
            let isOnboarded = pumpManager?.isOnboarded ?? false
            let view = TandemKitInsulinType(
                initialValue: pumpManager?.state.insulinType ?? allowedInsulinTypes.first,
                supportedInsulinTypes: allowedInsulinTypes,
                label: !isOnboarded ? LocalizedString("Continue", comment: "continue") : LocalizedString("Save", comment: "save"),
                didConfirm: { type in
                    guard let pumpManager = self.pumpManager else { return }

                    pumpManager.lockedState.value.insulinType = type
                    pumpManager.notifyPumpManagerDelegateDidUpdateState()

                    if !isOnboarded {
                        self.navigateTo(.soundSettings)
                    }
                }
            )
            return hostingController(rootView: view)
        case .pumpSettings:
            // next step = deactivate the pump
            let openInsulinType = { self.navigateTo(.insulinType) }
            let openSoundSettings = { self.navigateTo(.soundSettings) }
            let viewModel = TandemKitSettingsViewModel(
                pumpManager,
                nextStep: stepFinished,
                openInsulinType: openInsulinType,
                openSoundSettings: openSoundSettings
            )
            let view = TandemKitSettingsView(viewModel: viewModel)
            return hostingController(rootView: view)
        case .soundSettings:
            let isOnboarded = pumpManager?.isOnboarded ?? false
            let onSubmit = !isOnboarded ? {
                self.navigateTo(.deviceScanning)
            } : nil

            let viewModel = TandemKitSoundSettingsViewModel(pumpManager: pumpManager, onSubmit: onSubmit)
            return hostingController(rootView: TandemKitSoundSettingsView(viewModel: viewModel))
        }
    }

    func stepFinished() {
        if let nextStep = currentScreen.next() {
            navigateTo(nextStep)
        } else {
            pumpManager?.prepareForDeactivation { _ in
                DispatchQueue.main.async {
                    self.completionDelegate?.completionNotifyingDidComplete(self)
                }
            }
        }
    }

    func getInitialScreen() -> TandemScreen {
        guard let pumpManager = pumpManager else {
            return .setup
        }

        if pumpManager.isOnboarded {
            // If already onboarded, skip to settings or complete
            return .pumpSettings
        }

        return .setup
    }
}

extension TandemUICoordinator: TandemUINavigator {
    func navigateTo(_ screen: TandemScreen) {
        screenStack.append(screen)
        let viewController = viewControllerForScreen(screen)
        viewController.isModalInPresentation = false
        pushViewController(viewController, animated: true)
        viewController.view.layoutSubviews()
    }

    func resetNavigationTo(_ screens: [TandemScreen]) {
        screenStack = screens
        let viewControllers = screenStack.map {
            let viewController = viewControllerForScreen($0)
            viewController.isModalInPresentation = false
            viewController.view.layoutSubviews()
            return viewController
        }

        setViewControllers(viewControllers, animated: true)
    }
}
