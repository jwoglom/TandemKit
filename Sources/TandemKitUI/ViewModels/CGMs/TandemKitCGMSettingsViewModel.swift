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
    @Published var sensorStartedText: String?
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

    /// Fetches CGM status from the pump. Pass `showsSpinner: false` to refresh in place, leaving
    /// the currently displayed values visible while the pump round-trip is in flight.
    func fetchCGMStatus(force: Bool = false, showsSpinner: Bool = true) {
        guard !hasFetched || force else { return }
        hasFetched = true
        if showsSpinner {
            isFetching = true
        }

        pumpManager?.getCGMStatus { response in
            DispatchQueue.main.async {
                self.isFetching = false

                guard let response else {
                    return
                }

                let sensorType: String? = {
                    switch response.cgmSensorType {
                    case .dexcomG6: return "Dexcom G6"
                    case .dexcomG7: return "Dexcom G7"
                    default: return nil
                    }
                }()

                // The pump only reports transmitter battery for G6; on a G7 session it always
                // reads back as unavailable, so the row is omitted entirely.
                let batteryText: String? = {
                    guard response.cgmSensorType != .dexcomG7 else { return nil }

                    switch response.transmitterBatteryStatus {
                    case .okay: return String(localized: "OK", comment: "Transmitter battery: OK")
                    case .error: return String(localized: "Error", comment: "Transmitter battery: Error")
                    case .expired: return String(localized: "Expired", comment: "Transmitter battery: Expired")
                    case .outOfRange: return String(localized: "Out of Range", comment: "Transmitter battery: Out of Range")
                    case .unavailable: return String(localized: "Unavailable", comment: "Transmitter battery: Unavailable")
                    case .unknown: return nil
                    }
                }()

                let duration = formatCompactDuration(seconds: response.sessionDurationSeconds)
                let remaining = formatCompactDuration(seconds: response.sessionTimeRemainingSeconds)
                let startedText: String? = response.sensorStartedTimestamp > 0
                    ? String(format: String(
                        localized: "%@ ago",
                        comment: "Relative time suffix, parameter is a duration"
                    ), formatCompactDuration(since: response.sensorStartedDate))
                    : nil

                self.cgmSessionState = CGMSessionState(from: response.sessionStateId)
                self.sensorTypeText = sensorType
                self.sensorStartedText = startedText
                self.sessionDuration = response.sessionDurationSeconds > 0 ? duration : nil
                self.sessionTimeRemaining = response.sessionTimeRemainingSeconds > 0 ? remaining : nil
                self.transmitterBattery = batteryText
                self.gracePeriod = response.gracePeriod
            }
        }
    }

    // MARK: - Factory

    func createG6SetupViewModel() -> TandemKitG6SetupViewModel {
        TandemKitG6SetupViewModel(pumpManager: pumpManager) { [weak self] in
            self?.handleSetupCompleted()
        }
    }

    func createG7SetupViewModel() -> TandemKitG7SetupViewModel {
        TandemKitG7SetupViewModel(pumpManager: pumpManager) { [weak self] in
            self?.handleSetupCompleted()
        }
    }

    /// Called when a setup wizard finishes talking to the pump. The displayed status is stale at
    /// that point, so show the expected state immediately and reload the authoritative one.
    private func handleSetupCompleted() {
        cgmSessionState = .startPending
        fetchCGMStatus(force: true, showsSpinner: false)
    }

    // MARK: - Stop CGM Sensor

    func stopCGMSensor() {
        commandError = nil
        isLoading = true

        pumpManager?.stopCGMSensor { success in
            DispatchQueue.main.async {
                self.isLoading = false

                if success {
                    self.cgmSessionState = .stopPending
                    self.fetchCGMStatus(force: true, showsSpinner: false)
                } else {
                    self.commandError = String(
                        localized: "Failed to stop CGM sensor. Check pump connection.",
                        comment: "Error when CGM sensor stop fails"
                    )
                }
            }
        }
    }
}
