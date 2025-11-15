import LoopKit
import LoopKitUI
import SwiftUI

enum TandemScreen {
    case setup
    case deviceScanning
    case setupComplete

    func next() -> TandemScreen? {
        switch self {
        case .setup:
            return .deviceScanning
        case .deviceScanning:
            return .setupComplete
        case .setupComplete:
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
        pumpManagerSettings _: PumpManagerSetupSettings? = nil,
        allowDebugFeatures: Bool,
        allowedInsulinTypes: [InsulinType] = []
    )
    {
        if pumpManager == nil {
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

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

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
            pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didOnboardPumpManager: pumpManager!)

            let viewModel = TandemKitScanViewModel(pumpManager, nextStep: stepFinished)
            return hostingController(rootView: TandemKitScanView(viewModel: viewModel))
        case .setupComplete:
            let nextStep: () -> Void = {
                self.pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didCreatePumpManager: self.pumpManager!)
                self.completionDelegate?.completionNotifyingDidComplete(self)
            }

            let view = TandemKitSetupCompleteView(finish: nextStep)
            return hostingController(rootView: view)
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
        guard let pumpManager = self.pumpManager else {
            return .setup
        }

        if pumpManager.isOnboarded {
            // If already onboarded, skip to settings or complete
            return .setupComplete
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
}
