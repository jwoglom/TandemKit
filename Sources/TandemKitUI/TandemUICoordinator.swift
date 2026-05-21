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
    case changeCartridge
    case fillTubing
    case fillCannula
    case notifications
    case cgmSettings
    case controlIQSettings
    case quickBolus
    case alertSettings

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

    private var pumpManager: TandemPumpManager

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
        if let pumpManager {
            self.pumpManager = pumpManager
        } else {
            let state = TandemPumpManagerState(
                basalRateSchedule: pumpManagerSettings?
                    .basalSchedule ?? BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0)])!
            )
            self.pumpManager = TandemPumpManager(state: state)
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
            pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didOnboardPumpManager: pumpManager)
            let returnToMainScreen: () -> Void = {
                self.pumpManager.state.onboarded = true
                self.pumpManager.notifyDelegateStateUpdated()

                self.pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didCreatePumpManager: self.pumpManager)
                self.completionDelegate?.completionNotifyingDidComplete(self)
            }

            let view = TandemKitSetupCompleteView(finish: returnToMainScreen)
            return hostingController(rootView: view)
        case .insulinType:
            let isOnboarded = pumpManager.isOnboarded
            let view = TandemKitInsulinType(
                initialValue: pumpManager.state.insulinType ?? allowedInsulinTypes.first,
                supportedInsulinTypes: allowedInsulinTypes,
                label: !isOnboarded ? String(localized: "Continue", comment: "continue") :
                    String(localized: "Save", comment: "save"),
                didConfirm: { type in
                    self.pumpManager.state.insulinType = type
                    self.pumpManager.notifyDelegateStateUpdated()

                    if !isOnboarded {
                        self.navigateTo(.soundSettings)
                    }
                }
            )
            return hostingController(rootView: view)
        case .pumpSettings:
            // next step = deactivate the pump
            let viewModel = TandemKitSettingsViewModel(
                pumpManager,
                nextStep: stepFinished,
                openNotifications: { self.navigateTo(.notifications) },
                openInsulinType: { self.navigateTo(.insulinType) },
                openSoundSettings: { self.navigateTo(.soundSettings) },
                openCartridgeChange: { self.navigateTo(.changeCartridge) },
                openFillTubing: { self.navigateTo(.fillTubing) },
                openFillCannula: { self.navigateTo(.fillCannula) },
                openCgmSettings: { self.navigateTo(.cgmSettings) },
                openControlIQSettings: { self.navigateTo(.controlIQSettings) },
                openQuickBolus: { self.navigateTo(.quickBolus) },
                openAlertSettings: { self.navigateTo(.alertSettings) }
            )
            let view = TandemKitSettingsView(viewModel: viewModel)
            return hostingController(rootView: view)
        case .soundSettings:
            let isOnboarded = pumpManager.isOnboarded
            let onSubmit = !isOnboarded ? {
                self.navigateTo(.deviceScanning)
            } : nil

            let viewModel = TandemKitSoundSettingsViewModel(pumpManager: pumpManager, onSubmit: onSubmit)
            return hostingController(rootView: TandemKitSoundSettingsView(viewModel: viewModel))

        case .changeCartridge:
            let viewModel = TandemKitChangeCartridgeViewModel(
                pumpManager: pumpManager,
                done: { self.resetNavigationTo([.pumpSettings]) },
                toFillTubing: { self.navigateTo(.fillTubing) }
            )

            return hostingController(rootView: TandemKitChangeCartridgeView(viewModel: viewModel))

        case .fillTubing:
            let viewModel = TandemKitFillTubingViewModel(
                pumpManager: pumpManager,
                done: { self.resetNavigationTo([.pumpSettings]) },
                toFillingCannula: { self.navigateTo(.fillCannula) }
            )

            return hostingController(rootView: TandemKitFillTubingView(viewModel: viewModel))

        case .fillCannula:
            let viewModel = TandemKitFillCannulaViewModel(
                pumpManager: pumpManager,
                done: { self.resetNavigationTo([.pumpSettings]) }
            )
            return hostingController(rootView: TandemKitFillCannulaView(viewModel: viewModel))

        case .notifications:
            let viewModel = TandemKitNotificationsViewModel(pumpManager)
            return hostingController(rootView: TandemKitNotificationsView(viewModel: viewModel))

        case .cgmSettings:
            let viewModel = TandemKitCGMSettingsViewModel(pumpManager: pumpManager)
            return hostingController(rootView: TandemKitCGMSettingsView(viewModel: viewModel))

        case .controlIQSettings:
            let viewModel = TandemKitControlIQSettingsViewModel(pumpManager: pumpManager)
            return hostingController(rootView: TandemKitControlIQSettingsView(viewModel: viewModel))

        case .quickBolus:
            let viewModel = TandemKitQuickBolusSettingsViewModel(pumpManager: pumpManager)
            return hostingController(rootView: TandemKitQuickBolusSettingsView(viewModel: viewModel))

        case .alertSettings:
            let viewModel = TandemKitAlertSettingsViewModel(pumpManager: pumpManager)
            return hostingController(rootView: TandemKitAlertSettingsView(viewModel: viewModel))
        }
    }

    func stepFinished() {
        if let nextStep = currentScreen.next() {
            navigateTo(nextStep)
        } else {
            pumpManager.prepareForDeactivation { _ in
                DispatchQueue.main.async {
                    self.completionDelegate?.completionNotifyingDidComplete(self)
                }
            }
        }
    }

    func getInitialScreen() -> TandemScreen {
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
