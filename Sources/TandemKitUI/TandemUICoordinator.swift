import LoopKit
import LoopKitUI
import SwiftUI

enum TandemScreen {
    case setup
    case deviceScanning
    case loadHistory
    case setupComplete
    case pumpInformation
    case pumpSettings
    case insulinType
    case soundSettings
    case changeCartridge
    case fillTubing
    case fillTubingAfterCartridgeChange
    case fillCannula
    case notifications
    case cgmSettings
    case controlIQSettings
    case quickBolus
    case alertSettings
    case debug
    case historyLogViewer
    case pumpProfileViewer
    case reconciliation
    case featureFlags
    case troubleshootConnection

    func next() -> TandemScreen? {
        switch self {
        case .setup:
            return .insulinType
        case .insulinType:
            return .soundSettings
        case .soundSettings:
            return .deviceScanning
        case .deviceScanning:
            return .loadHistory
        case .loadHistory:
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
    weak var pumpManagerOnboardingDelegate: PumpManagerOnboardingDelegate?

    weak var completionDelegate: CompletionDelegate?

    var screenStack = [TandemScreen]()
    var currentScreen: TandemScreen {
        screenStack.last!
    }

    private let colorPalette: LoopUIColorPalette

    let pumpManager: TandemPumpManager

    /// True while a manager this flow created is nobody else's: until pairing hands it to the host,
    /// a flow that goes away takes it down with it (#603).
    private(set) var ownsPumpManager: Bool

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
                    .basalSchedule ?? BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0)])!,
                maxBasalRateUnitsPerHour: pumpManagerSettings?.maxBasalRateUnitsPerHour,
                maxBolusUnits: pumpManagerSettings?.maxBolusUnits
            )
            self.pumpManager = TandemPumpManager(state: state)
        }
        ownsPumpManager = pumpManager == nil

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
            let view = TandemKitSetupView(nextAction: { [weak self] in self?.stepFinished() })
            return hostingController(
                rootView: view,
                title: String(localized: "Tandem Mobi Setup", comment: "Title for TandemKitSetupView")
            )
        case .deviceScanning:
            let nextStep: () -> Void = { [weak self] in
                self?.pairingFinished()
            }

            let viewModel = TandemKitScanViewModel(pumpManager, nextStep: nextStep)
            return hostingController(
                rootView: TandemKitScanView(viewModel: viewModel),
                title: String(localized: "Tandem Mobi Pairing", comment: "Title for Mobi pairing"),
                largeTitleDisplayMode: .never
            )
        case .loadHistory:
            let viewModel = TandemKitLoadHistoryViewModel(reading: setupDeliveryReading, done: { [weak self] loads in
                self?.loadsSetupHistory = loads
                self?.resetNavigationTo([.setupComplete])
            })
            return hostingController(
                rootView: TandemKitLoadHistoryView(viewModel: viewModel),
                title: String(localized: "Load Pump History", comment: "Title for the setup step that loads the pump's history")
            )
        case .setupComplete:
            let viewModel = TandemKitSetupCompleteViewModel(pumpManager: pumpManager, loadsHistory: loadsSetupHistory, pumpIsSetUp: { [weak self] in
                self?.handPumpManagerToHost()
            })
            let view = TandemKitSetupCompleteView(viewModel: viewModel, finish: { [weak self] in
                guard let self else { return }
                self.completionDelegate?.completionNotifyingDidComplete(self)
            })
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
                didConfirm: { [weak self] type in
                    guard let self else { return }
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
                openDebug: { [weak self] in self?.navigateTo(.debug) },
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
                nextStep: { [weak self] in self?.stepFinished() },
                openPumpInformation: { [weak self] in self?.navigateTo(.pumpInformation) },
                openNotifications: { [weak self] in self?.navigateTo(.notifications) },
                openInsulinType: { [weak self] in self?.navigateTo(.insulinType) },
                openSoundSettings: { [weak self] in self?.navigateTo(.soundSettings) },
                openCartridgeChange: { [weak self] in self?.navigateTo(.changeCartridge) },
                openFillTubing: { [weak self] in self?.navigateTo(.fillTubing) },
                openFillCannula: { [weak self] in self?.navigateTo(.fillCannula) },
                openCgmSettings: { [weak self] in self?.navigateTo(.cgmSettings) },
                openControlIQSettings: { [weak self] in self?.navigateTo(.controlIQSettings) },
                openQuickBolus: { [weak self] in self?.navigateTo(.quickBolus) },
                openAlertSettings: { [weak self] in self?.navigateTo(.alertSettings) },
                openDebug: { [weak self] in self?.navigateTo(.debug) },
                openTroubleshootConnection: { [weak self] in self?.navigateTo(.troubleshootConnection) },
                allowDebugFeatures: allowDebugFeatures
            )
            let view = TandemKitSettingsView(viewModel: viewModel)
            return hostingController(rootView: view, title: pumpSettingsTitle)
        case .soundSettings:
            let isOnboarded = pumpManager.isOnboarded
            let onSubmit: (() -> Void)? = !isOnboarded ? { [weak self] in
                self?.navigateTo(.deviceScanning)
            } : nil

            let viewModel = TandemKitSoundSettingsViewModel(pumpManager: pumpManager, onSubmit: onSubmit)
            return hostingController(
                rootView: TandemKitSoundSettingsView(viewModel: viewModel),
                title: String(localized: "Sound Settings", comment: "Title for sound settings")
            )

        case .changeCartridge:
            let viewModel = TandemKitChangeCartridgeViewModel(
                pumpManager: pumpManager,
                done: { [weak self] in self?.resetNavigationTo([.pumpSettings]) },
                toFillTubing: { [weak self] in self?.navigateTo(.fillTubingAfterCartridgeChange) }
            )

            return hostingController(
                rootView: TandemKitChangeCartridgeView(viewModel: viewModel),
                title: String(localized: "Change Cartridge", comment: "Title for change cartridge"),
                largeTitleDisplayMode: .never
            )

        case .fillTubing, .fillTubingAfterCartridgeChange:
            let viewModel = TandemKitFillTubingViewModel(
                pumpManager: pumpManager,
                done: { [weak self] in self?.resetNavigationTo([.pumpSettings]) },
                toFillingCannula: { [weak self] in self?.navigateTo(.fillCannula) },
                followsCartridgeChange: screen == .fillTubingAfterCartridgeChange
            )

            return hostingController(
                rootView: TandemKitFillTubingView(viewModel: viewModel),
                title: String(localized: "Fill Tubing", comment: "Title for fill tubing"),
                largeTitleDisplayMode: .never
            )

        case .fillCannula:
            let viewModel = TandemKitFillCannulaViewModel(
                pumpManager: pumpManager,
                done: { [weak self] in self?.resetNavigationTo([.pumpSettings]) }
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
            let viewModel = TandemKitControlIQSettingsViewModel(
                pumpManager: pumpManager,
                openCgmSettings: { [weak self] in self?.navigateTo(.cgmSettings) }
            )
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
                openHistoryLogViewer: { [weak self] in self?.navigateTo(.historyLogViewer) },
                openPumpProfileViewer: { [weak self] in self?.navigateTo(.pumpProfileViewer) },
                openReconciliation: { [weak self] in self?.navigateTo(.reconciliation) },
                openFeatureFlags: { [weak self] in self?.navigateTo(.featureFlags) },
                rerunInitialSetup: { [weak self] in
                    self?.pumpManager.deleteSavedPumpState()
                    self?.resetNavigationTo([.setup])
                }
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

        case .pumpProfileViewer:
            let viewModel = TandemKitPumpProfileViewerViewModel(pumpManager: pumpManager)
            return hostingController(
                rootView: TandemKitPumpProfileViewerView(viewModel: viewModel),
                title: String(localized: "Pump Profile Viewer", comment: "Title for pump profile viewer screen")
            )

        case .reconciliation:
            let viewModel = TandemKitReconciliationViewModel(pumpManager: pumpManager)
            return hostingController(
                rootView: TandemKitReconciliationView(viewModel: viewModel),
                title: String(localized: "Reconciliation", comment: "Title for the reconciliation debug screen")
            )

        case .featureFlags:
            let viewModel = TandemKitFeatureFlagsViewModel(pumpManager: pumpManager)
            return hostingController(
                rootView: TandemKitFeatureFlagsView(viewModel: viewModel),
                title: String(localized: "Feature Flags", comment: "Title for feature flags screen")
            )

        case .troubleshootConnection:
            let viewModel = TandemKitTroubleshootConnectionViewModel(pumpManager: pumpManager)
            return hostingController(
                rootView: TandemKitTroubleshootConnectionView(viewModel: viewModel),
                title: String(localized: "Troubleshoot connection", comment: "Title for troubleshoot connection screen")
            )
        }
    }

    func stepFinished() {
        if let nextStep = currentScreen.next() {
            navigateTo(nextStep)
        } else {
            // Held to the end: Trio's sheet lets this flow go once its pump manager is nil, and then only
            // this call dismisses the sheet.
            pumpManager.prepareForDeactivation { _ in
                DispatchQueue.main.async {
                    self.completionDelegate?.completionNotifyingDidComplete(self)
                }
            }
        }
    }

    /// What the pump reported right after pairing, for the Load Pump History step.
    private(set) var setupDeliveryReading = SetupDeliveryReading()
    private(set) var loadsSetupHistory = false

    /// Before setup writes anything, so the readings are what the pump's last user left, and before the
    /// host has the manager, so it doses on none of the pump's history until the user has chosen.
    func pairingFinished() {
        pumpManager.readDeliveryForSetup { [weak self] reading in
            DispatchQueue.main.async {
                self?.showStepAfterPairing(reading)
            }
        }
    }

    func showStepAfterPairing(_ reading: SetupDeliveryReading) {
        setupDeliveryReading = reading
        resetNavigationTo([pumpManager.canLoadHistoryForSetup ? .loadHistory : .setupComplete])
    }

    /// Pairing, the history load and the onboarding writes are done: the pump holds a key for this
    /// phone, so the host owns the manager from here, and a setup left before Finish is in its
    /// settings, where it can be deleted (#603). Created, then onboarded: the order the hosts adopt a
    /// manager in.
    func handPumpManagerToHost() {
        pumpManager.state.onboarded = true
        pumpManager.notifyDelegateStateUpdated()
        ownsPumpManager = false
        pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didCreatePumpManager: pumpManager)
        pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didOnboardPumpManager: pumpManager)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            abandonSetupIfOwned()
        }
    }

    deinit {
        abandonSetupIfOwned()
    }

    /// A flow that goes away with its manager still its own takes the manager's link down: one left
    /// pairing on in the background held the pump's one link against every attempt after it (#603).
    private func abandonSetupIfOwned() {
        guard ownsPumpManager else { return }
        ownsPumpManager = false
        pumpManager.abandonSetup()
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
