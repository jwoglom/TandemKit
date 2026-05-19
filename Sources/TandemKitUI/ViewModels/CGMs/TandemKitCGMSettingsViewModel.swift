import LoopKit
import SwiftUI

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
        case .stopped: return String(localized: "Stopped", comment: "CGM session state: stopped")
        case .startPending: return String(localized: "Starting...", comment: "CGM session state: starting")
        case .active: return String(localized: "Active", comment: "CGM session state: active")
        case .stopPending: return String(localized: "Stopping...", comment: "CGM session state: stopping")
        case .unknown: return String(localized: "Unknown", comment: "CGM session state: unknown")
        }
    }

    var isPending: Bool {
        self == .startPending || self == .stopPending
    }
}

class TandemKitCGMSettingsViewModel: ObservableObject {
    var appName: String { HostApp.current.appName }

    @Published var isFetching: Bool = true
    @Published var isLoading: Bool = false
    @Published var cgmSessionState: CGMSessionState = .unknown
    @Published var sensorTypeText: String?
    @Published var sensorStartedDate: Date?
    @Published var sessionDuration: String?
    @Published var sessionTimeRemaining: String?
    @Published var transmitterBattery: String?
    @Published var gracePeriod: Bool = false
    @Published var commandError: String?

    private let pumpManager: TandemPumpManager?

    private var hasFetched = false

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
    }

    // MARK: - Fetch

    func fetchCGMStatus(force: Bool = false) {
        guard !hasFetched || force else { return }
        hasFetched = true
        isFetching = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let pumpManager = self.pumpManager else {
                DispatchQueue.main.async { self?.isFetching = false }
                return
            }

            if let response = pumpManager.sendMessage(message: CGMStatusV2Request()) as? CGMStatusV2Response {
                let sensorType: String? = {
                    switch response.cgmSensorType {
                    case .dexcomG6: return "Dexcom G6"
                    case .dexcomG7: return "Dexcom G7"
                    default: return nil
                    }
                }()

                let batteryText: String? = {
                    switch response.transmitterBatteryStatus {
                    case .okay: return String(localized: "OK", comment: "Transmitter battery: OK")
                    case .error: return String(localized: "Error", comment: "Transmitter battery: Error")
                    case .expired: return String(localized: "Expired", comment: "Transmitter battery: Expired")
                    case .outOfRange: return String(localized: "Out of Range", comment: "Transmitter battery: Out of Range")
                    case .unavailable: return String(localized: "Unavailable", comment: "Transmitter battery: Unavailable")
                    case .unknown: return nil
                    }
                }()

                let duration = Self.formatDuration(seconds: response.sessionDurationSeconds)
                let remaining = Self.formatDuration(seconds: response.sessionTimeRemainingSeconds)
                let startedDate = response.sensorStartedTimestamp > 0 ? response.sensorStartedDate : nil

                DispatchQueue.main.async {
                    self.cgmSessionState = CGMSessionState(from: response.sessionStateId)
                    self.sensorTypeText = sensorType
                    self.sensorStartedDate = startedDate
                    self.sessionDuration = response.sessionDurationSeconds > 0 ? duration : nil
                    self.sessionTimeRemaining = response.sessionTimeRemainingSeconds > 0 ? remaining : nil
                    self.transmitterBattery = batteryText
                    self.gracePeriod = response.gracePeriod
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

    func createG7SetupViewModel() -> TandemKitG7SetupViewModel {
        TandemKitG7SetupViewModel(pumpManager: pumpManager)
    }

    // MARK: - Helpers

    private static func formatDuration(seconds: UInt32) -> String {
        let totalMinutes = Int(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        }
        return String(format: "%dm", minutes)
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
                    self.commandError = String(
                        localized:
                        "Failed to stop CGM sensor. Check pump connection.",
                        comment: "Error when CGM sensor stop fails"
                    )
                }
            }
        }
    }
}
