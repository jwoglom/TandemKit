import LoopKit
import LoopKitUI
import SwiftUI

enum TandemScreen {
    case setup
    case deviceScanning
    case setupComplete
    case pumpInformation
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
    case debug
    case historyLogViewer

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

    private func hostingController<Content: View>(
        rootView: Content,
        title: String? = nil,
        largeTitleDisplayMode: UINavigationItem.LargeTitleDisplayMode = .automatic
    ) -> DismissibleHostingController<some View> {
        let rootView = rootView
            .environment(\.appName, Bundle.main.bundleDisplayName)
        let hostedView = DismissibleHostingController(content: rootView, colorPalette: colorPalette)
        hostedView.navigationItem.title = title
        hostedView.navigationItem.largeTitleDisplayMode = largeTitleDisplayMode
        return hostedView
    }

    private var pumpSettingsTitle: String {
        return "Tandem Mobi"
    }

    private func viewControllerForScreen(_ screen: TandemScreen) -> UIViewController {
        switch screen {
        case .setup:
            let view = TandemKitSetupView(nextAction: stepFinished)
            return hostingController(
                rootView: view,
                title: String(localized: "Tandem Mobi Setup", comment: "Title for TandemKitSetupView")
            )
        case .deviceScanning:
            let nextStep = {
                self.resetNavigationTo([.setupComplete])
            }

            let viewModel = TandemKitScanViewModel(pumpManager, nextStep: nextStep)
            return hostingController(
                rootView: TandemKitScanView(viewModel: viewModel),
                title: String(localized: "Tandem Mobi Pairing", comment: "Title for Mobi pairing"),
                largeTitleDisplayMode: .never
            )
        case .setupComplete:
            pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didOnboardPumpManager: pumpManager)
            let returnToMainScreen: () -> Void = {
                self.pumpManager.state.onboarded = true
                self.pumpManager.notifyDelegateStateUpdated()

                self.pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didCreatePumpManager: self.pumpManager)
                self.completionDelegate?.completionNotifyingDidComplete(self)
            }

            let view = TandemKitSetupCompleteView(finish: returnToMainScreen)
            return hostingController(
                rootView: view,
                title: String(localized: "Setup Complete", comment: "Title for setup complete")
            )
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
            return hostingController(
                rootView: view,
                title: String(localized: "Select insulin type", comment: "Title for insulin type")
            )

        case .pumpInformation:
            let viewModel = TandemKitPumpInformationViewModel(
                pumpManager: pumpManager,
                openDebug: { self.navigateTo(.debug) },
                allowDebugFeatures: allowDebugFeatures
            )
            return hostingController(
                rootView: TandemKitPumpInformationView(viewModel: viewModel),
                title: String(localized: "Pump Information", comment: "Title for pump information")
            )

        case .pumpSettings:
            // next step = deactivate the pump
            let viewModel = TandemKitSettingsViewModel(
                pumpManager,
                nextStep: stepFinished,
                openPumpInformation: { self.navigateTo(.pumpInformation) },
                openNotifications: { self.navigateTo(.notifications) },
                openInsulinType: { self.navigateTo(.insulinType) },
                openSoundSettings: { self.navigateTo(.soundSettings) },
                openCartridgeChange: { self.navigateTo(.changeCartridge) },
                openFillTubing: { self.navigateTo(.fillTubing) },
                openFillCannula: { self.navigateTo(.fillCannula) },
                openCgmSettings: { self.navigateTo(.cgmSettings) },
                openControlIQSettings: { self.navigateTo(.controlIQSettings) },
                openQuickBolus: { self.navigateTo(.quickBolus) },
                openAlertSettings: { self.navigateTo(.alertSettings) },
                openDebug: { self.navigateTo(.debug) },
                allowDebugFeatures: allowDebugFeatures
            )
            let view = TandemKitSettingsView(viewModel: viewModel)
            return hostingController(rootView: view, title: pumpSettingsTitle)
        case .soundSettings:
            let isOnboarded = pumpManager.isOnboarded
            let onSubmit = !isOnboarded ? {
                self.navigateTo(.deviceScanning)
            } : nil

            let viewModel = TandemKitSoundSettingsViewModel(pumpManager: pumpManager, onSubmit: onSubmit)
            return hostingController(
                rootView: TandemKitSoundSettingsView(viewModel: viewModel),
                title: String(localized: "Sound Settings", comment: "Title for sound settings")
            )

        case .changeCartridge:
            let viewModel = TandemKitChangeCartridgeViewModel(
                pumpManager: pumpManager,
                done: { self.resetNavigationTo([.pumpSettings]) },
                toFillTubing: { self.navigateTo(.fillTubing) }
            )

            return hostingController(
                rootView: TandemKitChangeCartridgeView(viewModel: viewModel),
                title: String(localized: "Change Cartridge", comment: "Title for change cartridge"),
                largeTitleDisplayMode: .never
            )

        case .fillTubing:
            let viewModel = TandemKitFillTubingViewModel(
                pumpManager: pumpManager,
                done: { self.resetNavigationTo([.pumpSettings]) },
                toFillingCannula: { self.navigateTo(.fillCannula) }
            )

            return hostingController(
                rootView: TandemKitFillTubingView(viewModel: viewModel),
                title: String(localized: "Fill Tubing", comment: "Title for fill tubing"),
                largeTitleDisplayMode: .never
            )

        case .fillCannula:
            let viewModel = TandemKitFillCannulaViewModel(
                pumpManager: pumpManager,
                done: { self.resetNavigationTo([.pumpSettings]) }
            )
            return hostingController(
                rootView: TandemKitFillCannulaView(viewModel: viewModel),
                title: String(localized: "Fill Cannula", comment: "Title for fill cannula"),
                largeTitleDisplayMode: .never
            )

        case .notifications:
            let viewModel = TandemKitNotificationsViewModel(pumpManager)
            return hostingController(
                rootView: TandemKitNotificationsView(viewModel: viewModel),
                title: String(localized: "Notifications", comment: "Notifications view title")
            )

        case .cgmSettings:
            let viewModel = TandemKitCGMSettingsViewModel(pumpManager: pumpManager)
            return hostingController(
                rootView: TandemKitCGMSettingsView(viewModel: viewModel),
                title: String(localized: "CGM Settings", comment: "Label for CGM settings")
            )

        case .controlIQSettings:
            let viewModel = TandemKitControlIQSettingsViewModel(pumpManager: pumpManager)
            return hostingController(
                rootView: TandemKitControlIQSettingsView(viewModel: viewModel),
                title: String(localized: "Control-IQ Settings", comment: "Title for Control-IQ settings screen")
            )

        case .quickBolus:
            let viewModel = TandemKitQuickBolusSettingsViewModel(pumpManager: pumpManager)
            return hostingController(
                rootView: TandemKitQuickBolusSettingsView(viewModel: viewModel),
                title: String(localized: "Quick Bolus Settings", comment: "Title for quick bolus settings")
            )

        case .alertSettings:
            let viewModel = TandemKitAlertSettingsViewModel(pumpManager: pumpManager)
            return hostingController(
                rootView: TandemKitAlertSettingsView(viewModel: viewModel),
                title: String(localized: "Alert Settings", comment: "Title for alert settings screen")
            )

        case .debug:
            let viewModel = TandemKitDebugViewModel(
                pumpManager: pumpManager,
                openHistoryLogViewer: { self.navigateTo(.historyLogViewer) }
            )
            return hostingController(
                rootView: TandemKitDebugView(viewModel: viewModel),
                title: String(localized: "Debug Options", comment: "Title for debug options screen")
            )

        case .historyLogViewer:
            let viewModel = TandemKitHistoryLogViewerViewModel(pumpManager: pumpManager)
            return hostingController(
                rootView: TandemKitHistoryLogViewerView(viewModel: viewModel),
                title: String(localized: "History Log Viewer", comment: "Title for history log viewer screen")
            )
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
