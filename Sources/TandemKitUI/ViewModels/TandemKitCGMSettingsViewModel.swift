import LoopKit
import SwiftUI
import TandemCore

enum CGMSessionState {
    case stopped
    case startPending
    case active
    case stopPending
    case unknown

    init(from sessionStateId: Int) {
        switch sessionStateId {
        case 0: self = .stopped
        case 1: self = .startPending
        case 2: self = .active
        case 3: self = .stopPending
        default: self = .unknown
        }
    }

    var displayText: String {
        switch self {
        case .stopped: return LocalizedString("Stopped", comment: "CGM session state: stopped")
        case .startPending: return LocalizedString("Starting...", comment: "CGM session state: starting")
        case .active: return LocalizedString("Active", comment: "CGM session state: active")
        case .stopPending: return LocalizedString("Stopping...", comment: "CGM session state: stopping")
        case .unknown: return LocalizedString("Unknown", comment: "CGM session state: unknown")
        }
    }

    var isPending: Bool {
        self == .startPending || self == .stopPending
    }
}

class TandemKitCGMSettingsViewModel: ObservableObject {
    @Published var isFetching: Bool = true
    @Published var isLoading: Bool = false
    @Published var cgmSessionState: CGMSessionState = .unknown
    @Published var commandError: String?

    private let pumpManager: TandemPumpManager?

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
        fetchCGMStatus()
    }

    // MARK: - Fetch

    func fetchCGMStatus() {
        isFetching = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let pumpManager = self.pumpManager else {
                DispatchQueue.main.async { self?.isFetching = false }
                return
            }

            if let response = pumpManager.sendMessage(message: CGMStatusRequest()) as? CGMStatusResponse {
                DispatchQueue.main.async {
                    self.cgmSessionState = CGMSessionState(from: response.sessionStateId)
                }
            }

            DispatchQueue.main.async {
                self.isFetching = false
            }
        }
    }

    // MARK: - Factory

    func createG6SetupViewModel() -> TandemKitG6SetupViewModel {
        TandemKitG6SetupViewModel(pumpManager: pumpManager)
    }

    // MARK: - Stop CGM Sensor

    func stopCGMSensor() {
        commandError = nil
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { self?.isLoading = false }
                return
            }

            let response = self.pumpManager?.sendMessage(
                message: StopDexcomCGMSensorSessionRequest()
            ) as? StopDexcomCGMSensorSessionResponse

            DispatchQueue.main.async {
                self.isLoading = false
                if response?.isStatusOK == true {
                    self.cgmSessionState = .stopPending
                } else {
                    self.commandError = LocalizedString(
                        "Failed to stop CGM sensor. Check pump connection.",
                        comment: "Error when CGM sensor stop fails"
                    )
                }
            }
        }
    }
}
