import Foundation
import SwiftUI
import UIKit

final class TandemKitDebugViewModel: ObservableObject {
    private let log = TandemLogger(category: "TandemKitDebugViewModel")

    struct ParameterField: Identifiable {
        enum FieldType {
            case integer
            case unsigned
            case boolean
        }

        let id: String
        let label: String
        let placeholder: String
        let type: FieldType
    }

    struct ParameterizedOption {
        let metadata: MessageMetadata
        let fields: [ParameterField]
        let build: ([String: String]) -> Message?
    }

    /// A single request that can be sent from a category sheet. `parameterized` is non-nil
    /// when the request needs structured input; otherwise it can be sent with empty cargo.
    struct RequestEntry: Identifiable {
        let metadata: MessageMetadata
        let parameterized: ParameterizedOption?

        var id: String { metadata.name }
        var name: String { metadata.name }

        /// Requests that require user input before they can be built and sent.
        var requiresInput: Bool {
            parameterized != nil || metadata.size > 0
        }
    }

    /// All requests belonging to a single pump message category (CurrentStatus, Control, …).
    struct CategoryGroup: Identifiable {
        let category: MessageCategory
        let requests: [RequestEntry]

        var id: String { category.rawValue }
        var sendButtonTitle: String { category.sendButtonTitle }
    }

    enum Confirmation {
        case command(Message)
        case dangerous(Message, reason: String)
    }

    @Published var lastResponseDescription: String?
    @Published var lastResponseJSON: String?
    @Published var lastSendError: String?
    @Published var isSending = false
    @Published private(set) var awaitingConfirmation: Confirmation?

    @Published var parameterInput: [String: String] = [:]
    @Published var cargoHexInput: String = ""

    @Published var useSilentMode: Bool = false

    // MARK: Tandem Source relay
    @Published var tandemSourceEnabled: Bool = false
    /// Resolved automatically from the account; shown read-only, never entered by the user.
    @Published private(set) var tandemSourceAssignmentId: String = ""
    @Published private(set) var tandemSourceSignedIn: Bool = false
    @Published private(set) var tandemSourceStatus: [String] = []
    @Published var tandemSourceBusy: Bool = false
    @Published var tandemSourceLoginError: String?

    private let pumpManager: TandemPumpManager?
    private var lastRequestMessage: Message?
    let openHistoryLogViewer: (() -> Void)?
    let openPumpProfileViewer: (() -> Void)?
    let openReconciliation: (() -> Void)?
    let openFeatureFlags: (() -> Void)?
    /// Re-runs the initial setup wizard (pairing included) against the existing pump manager,
    /// without removing it. Nil when the coordinator did not provide a navigation target.
    let rerunInitialSetup: (() -> Void)?

    init(
        pumpManager: TandemPumpManager?,
        openHistoryLogViewer: (() -> Void)? = nil,
        openPumpProfileViewer: (() -> Void)? = nil,
        openReconciliation: (() -> Void)? = nil,
        openFeatureFlags: (() -> Void)? = nil,
        rerunInitialSetup: (() -> Void)? = nil
    ) {
        self.pumpManager = pumpManager
        self.openHistoryLogViewer = openHistoryLogViewer
        self.openPumpProfileViewer = openPumpProfileViewer
        self.openReconciliation = openReconciliation
        self.openFeatureFlags = openFeatureFlags
        self.rerunInitialSetup = rerunInitialSetup
        useSilentMode = pumpManager?.state.useSilentTones ?? false
        refreshTandemSource()
    }

    func setSilentMode(_ enabled: Bool) {
        pumpManager?.configureSilentMode(enabled)
        useSilentMode = enabled
    }

    // MARK: Tandem Source relay

    func refreshTandemSource() {
        guard let pumpManager else { return }
        let state = pumpManager.state
        tandemSourceEnabled = state.tandemSourceUploadEnabled
        tandemSourceAssignmentId = state.tandemSourceDeviceAssignmentId ?? ""
        tandemSourceSignedIn = pumpManager.tandemSourceIsAuthenticated

        var lines: [String] = []
        lines.append(tandemSourceSignedIn ? "Signed in" : "Not signed in")
        if let last = state.lastTandemSourceUpload {
            lines.append("Last upload: \(Self.tandemSourceDateFormatter.string(from: last))")
        }
        if let index = state.lastTandemSourceEventIndex {
            lines.append("Server event index: \(index)")
        }
        if let error = state.lastTandemSourceError {
            lines.append("Last error: \(error)")
        }
        tandemSourceStatus = lines
    }

    func setTandemSourceEnabled(_ enabled: Bool) {
        pumpManager?.setTandemSourceUploadEnabled(enabled)
        refreshTandemSource()
    }

    func uploadTandemSourceNow() {
        pumpManager?.uploadToTandemSourceIfDue(force: true)
        scheduleTandemSourceRefreshes()
    }

    /// The upload that resolves the assignment id and advances the server index runs in a background
    /// task, so a single refresh right after kicking it off would miss the result. Re-read state a
    /// few times over the next several seconds to pick it up.
    private func scheduleTandemSourceRefreshes() {
        for delay in [2.0, 5.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refreshTandemSource() }
        }
    }

    func signOutTandemSource() {
        pumpManager?.signOutTandemSource()
        refreshTandemSource()
    }

    @MainActor
    func signInToTandemSource() async {
        guard let pumpManager else { return }
        guard let anchor = Self.keyWindow() else {
            tandemSourceLoginError = String(localized: "No window available to present sign-in.", comment: "Tandem Source: no presentation anchor")
            return
        }
        tandemSourceBusy = true
        tandemSourceLoginError = nil
        defer { tandemSourceBusy = false }
        do {
            let (code, verifier, redirect) = try await TandemSourceLoginSession(anchor: anchor).authorize()
            try await pumpManager.completeTandemSourceSignIn(code: code, codeVerifier: verifier, redirectURI: redirect)
            // Sign-in kicks a first upload in the background; pick up the resolved id when it lands.
            scheduleTandemSourceRefreshes()
        } catch TandemSourceLoginSession.LoginError.cancelled {
            // User dismissed the sheet; nothing to report.
        } catch {
            log.error("Tandem Source sign-in failed: \(error)")
            tandemSourceLoginError = String(describing: error)
        }
        refreshTandemSource()
    }

    @MainActor
    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    private static let tandemSourceDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var pumpStateDebugDescription: String {
        pumpManager?.state.pumpState.debugDescription ?? "No PumpState available"
    }

    var managerStateDebugDescription: String {
        pumpManager?.state.debugDescription ?? "No TandemPumpManagerState available"
    }

    var pumpStateJsonDebugDescription: String {
        guard let state = pumpManager?.state.pumpState else {
            return jsonString(from: ["error": "No PumpState available"])
        }
        return jsonString(from: state.rawValue)
    }

    var managerStateJsonDebugDescription: String {
        guard let state = pumpManager?.state else {
            return jsonString(from: ["error": "No TandemPumpManagerState available"])
        }
        return jsonString(from: state.rawValue)
    }

    private func jsonString(from dictionary: [String: Any]) -> String {
        let jsonCompatible = makeJsonCompatible(dictionary)
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonCompatible, options: [.prettyPrinted, .sortedKeys]),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            return "{}"
        }
        return jsonString
    }

    private func makeJsonCompatible(_ value: Any) -> Any {
        if let data = value as? Data {
            return data.base64EncodedString()
        } else if let dict = value as? [String: Any] {
            return dict.mapValues { makeJsonCompatible($0) }
        } else if let array = value as? [Any] {
            return array.map { makeJsonCompatible($0) }
        } else if let date = value as? Date {
            return ISO8601DateFormatter().string(from: date)
        } else {
            return value
        }
    }

    /// All request messages grouped by category, in display order. Categories without any
    /// sendable requests are omitted.
    var categories: [CategoryGroup] {
        let optionsByName = Dictionary(
            parameterizedOptions.map { ($0.metadata.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let sendable = MessageRegistry.all.filter {
            $0.messageType == .Request && !$0.type.props.dangerousDoNotInvoke
        }
        let grouped = Dictionary(grouping: sendable) {
            $0.category
        }

        return MessageCategory.allCases.compactMap { category in
            guard let metadatas = grouped[category], !metadatas.isEmpty else {
                return nil
            }
            let entries = metadatas
                .map { RequestEntry(metadata: $0, parameterized: optionsByName[$0.name]) }
                .sorted { $0.name < $1.name }
            return CategoryGroup(category: category, requests: entries)
        }
    }

    /// Curated definitions for requests that need structured parameters before sending.
    private var parameterizedOptions: [ParameterizedOption] {
        var options: [ParameterizedOption] = []

        if let metadata = MessageRegistry.metadata(for: IDPSegmentRequest.self) {
            options.append(
                ParameterizedOption(
                    metadata: metadata,
                    fields: [
                        ParameterField(id: "idpId", label: "IDP ID", placeholder: "0", type: .integer),
                        ParameterField(id: "segmentIndex", label: "Segment Index", placeholder: "0", type: .integer)
                    ],
                    build: { input in
                        guard let idpId = input["idpId"].flatMap(Int.init),
                              let segmentIndex = input["segmentIndex"].flatMap(Int.init)
                        else { return nil }
                        return IDPSegmentRequest(idpId: idpId, segmentIndex: segmentIndex)
                    }
                )
            )
        }

        if let metadata = MessageRegistry.metadata(for: IDPSettingsRequest.self) {
            options.append(
                ParameterizedOption(
                    metadata: metadata,
                    fields: [ParameterField(id: "idpId", label: "IDP ID", placeholder: "0", type: .integer)],
                    build: { input in
                        guard let idpId = input["idpId"].flatMap(Int.init) else { return nil }
                        return IDPSettingsRequest(idpId: idpId)
                    }
                )
            )
        }

        if let metadata = MessageRegistry.metadata(for: HistoryLogRequest.self) {
            options.append(
                ParameterizedOption(
                    metadata: metadata,
                    fields: [
                        ParameterField(id: "startLog", label: "Start Log Sequence", placeholder: "0", type: .unsigned),
                        ParameterField(id: "count", label: "Number of Logs", placeholder: "1", type: .integer)
                    ],
                    build: { input in
                        guard let startLog = input["startLog"].flatMap(UInt32.init),
                              let count = input["count"].flatMap(Int.init)
                        else { return nil }
                        return HistoryLogRequest(startLog: startLog, numberOfLogs: count)
                    }
                )
            )
        }

        if let metadata = MessageRegistry.metadata(for: InitiateBolusRequest.self) {
            options.append(
                ParameterizedOption(
                    metadata: metadata,
                    fields: [
                        ParameterField(id: "totalVolume", label: "Total Volume (raw units)", placeholder: "0", type: .unsigned),
                        ParameterField(id: "bolusId", label: "Bolus ID", placeholder: "0", type: .integer),
                        ParameterField(id: "bolusType", label: "Bolus Type Bitmask", placeholder: "0", type: .integer),
                        ParameterField(id: "foodVolume", label: "Food Volume", placeholder: "0", type: .unsigned),
                        ParameterField(id: "correctionVolume", label: "Correction Volume", placeholder: "0", type: .unsigned),
                        ParameterField(id: "bolusCarbs", label: "Bolus Carbs", placeholder: "0", type: .integer),
                        ParameterField(id: "bolusBG", label: "Bolus BG", placeholder: "0", type: .integer),
                        ParameterField(id: "bolusIOB", label: "Bolus IOB", placeholder: "0", type: .unsigned),
                        ParameterField(id: "extendedVolume", label: "Extended Volume", placeholder: "0", type: .unsigned),
                        ParameterField(id: "extendedSeconds", label: "Extended Seconds", placeholder: "0", type: .unsigned)
                    ],
                    build: { input in
                        guard let totalVolume = input["totalVolume"].flatMap(UInt32.init),
                              let bolusId = input["bolusId"].flatMap(Int.init),
                              let bolusTypeBitmask = input["bolusType"].flatMap(Int.init),
                              let foodVolume = input["foodVolume"].flatMap(UInt32.init),
                              let correctionVolume = input["correctionVolume"].flatMap(UInt32.init),
                              let bolusCarbs = input["bolusCarbs"].flatMap(Int.init),
                              let bolusBG = input["bolusBG"].flatMap(Int.init),
                              let bolusIOB = input["bolusIOB"].flatMap(UInt32.init)
                        else { return nil }

                        let extendedVolume = input["extendedVolume"].flatMap(UInt32.init) ?? 0
                        let extendedSeconds = input["extendedSeconds"].flatMap(UInt32.init) ?? 0

                        return InitiateBolusRequest(
                            totalVolume: totalVolume,
                            bolusID: bolusId,
                            bolusTypeBitmask: bolusTypeBitmask,
                            foodVolume: foodVolume,
                            correctionVolume: correctionVolume,
                            bolusCarbs: bolusCarbs,
                            bolusBG: bolusBG,
                            bolusIOB: bolusIOB,
                            extendedVolume: extendedVolume,
                            extendedSeconds: extendedSeconds
                        )
                    }
                )
            )
        }

        if let metadata = MessageRegistry.metadata(for: CancelBolusRequest.self) {
            options.append(
                ParameterizedOption(
                    metadata: metadata,
                    fields: [ParameterField(id: "bolusId", label: "Bolus ID", placeholder: "0", type: .integer)],
                    build: { input in
                        input["bolusId"].flatMap(Int.init).map(CancelBolusRequest.init)
                    }
                )
            )
        }

        if let metadata = MessageRegistry.metadata(for: BolusPermissionChangeReasonRequest.self) {
            options.append(
                ParameterizedOption(
                    metadata: metadata,
                    fields: [ParameterField(id: "bolusId", label: "Bolus ID", placeholder: "0", type: .integer)],
                    build: { input in
                        input["bolusId"].flatMap(Int.init).map(BolusPermissionChangeReasonRequest.init)
                    }
                )
            )
        }

        if let metadata = MessageRegistry.metadata(for: BolusPermissionReleaseRequest.self) {
            options.append(
                ParameterizedOption(
                    metadata: metadata,
                    fields: [ParameterField(id: "bolusId", label: "Bolus ID", placeholder: "0", type: .integer)],
                    build: { input in
                        input["bolusId"].flatMap(Int.init).map { BolusPermissionReleaseRequest(bolusID: $0) }
                    }
                )
            )
        }

        if let metadata = MessageRegistry.metadata(for: RemoteBgEntryRequest.self) {
            options.append(
                ParameterizedOption(
                    metadata: metadata,
                    fields: [
                        ParameterField(id: "bg", label: "BG", placeholder: "0", type: .integer),
                        ParameterField(
                            id: "useForCalibration",
                            label: "Use For Calibration (true/false)",
                            placeholder: "false",
                            type: .boolean
                        ),
                        ParameterField(id: "isAutopop", label: "Auto-pop BG (true/false)", placeholder: "false", type: .boolean),
                        ParameterField(id: "pumpTime", label: "Pump Time (seconds)", placeholder: "0", type: .unsigned),
                        ParameterField(id: "bolusId", label: "Bolus ID", placeholder: "0", type: .integer)
                    ],
                    build: { input in
                        guard let bg = input["bg"].flatMap(Int.init),
                              let pumpTime = input["pumpTime"].flatMap(UInt32.init),
                              let bolusId = input["bolusId"].flatMap(Int.init)
                        else { return nil }

                        let useCalibration = Self.parseBool(input["useForCalibration"])
                        let autoPop = Self.parseBool(input["isAutopop"])
                        return RemoteBgEntryRequest(
                            bg: bg,
                            useForCgmCalibration: useCalibration,
                            isAutopopBg: autoPop,
                            pumpTime: pumpTime,
                            bolusId: bolusId
                        )
                    }
                )
            )
        }

        if let metadata = MessageRegistry.metadata(for: RemoteCarbEntryRequest.self) {
            options.append(
                ParameterizedOption(
                    metadata: metadata,
                    fields: [
                        ParameterField(id: "carbs", label: "Carbs", placeholder: "0", type: .integer),
                        ParameterField(id: "pumpTime", label: "Pump Time (seconds)", placeholder: "0", type: .unsigned),
                        ParameterField(id: "bolusId", label: "Bolus ID", placeholder: "0", type: .integer)
                    ],
                    build: { input in
                        guard let carbs = input["carbs"].flatMap(Int.init),
                              let pumpTime = input["pumpTime"].flatMap(UInt32.init),
                              let bolusId = input["bolusId"].flatMap(Int.init)
                        else { return nil }

                        return RemoteCarbEntryRequest(carbs: carbs, pumpTime: pumpTime, bolusId: bolusId)
                    }
                )
            )
        }

        if let metadata = MessageRegistry.metadata(for: SetTempRateRequest.self) {
            options.append(
                ParameterizedOption(
                    metadata: metadata,
                    fields: [
                        ParameterField(id: "minutes", label: "Minutes", placeholder: "0", type: .integer),
                        ParameterField(id: "percent", label: "Percent", placeholder: "100", type: .integer)
                    ],
                    build: { input in
                        guard let minutes = input["minutes"].flatMap(Int.init),
                              let percent = input["percent"].flatMap(Int.init)
                        else { return nil }
                        return SetTempRateRequest(minutes: minutes, percent: percent)
                    }
                )
            )
        }

        if let metadata = MessageRegistry.metadata(for: ChangeControlIQSettingsRequest.self) {
            options.append(
                ParameterizedOption(
                    metadata: metadata,
                    fields: [
                        ParameterField(id: "enabled", label: "Enabled (true/false)", placeholder: "true", type: .boolean),
                        ParameterField(id: "weight", label: "Weight (lbs)", placeholder: "0", type: .integer),
                        ParameterField(id: "tdi", label: "Total Daily Insulin", placeholder: "0", type: .integer)
                    ],
                    build: { input in
                        guard let weight = input["weight"].flatMap(Int.init),
                              let tdi = input["tdi"].flatMap(Int.init)
                        else { return nil }
                        let enabled = Self.parseBool(input["enabled"])
                        return ChangeControlIQSettingsRequest(enabled: enabled, weightLbs: weight, totalDailyInsulinUnits: tdi)
                    }
                )
            )
        }

        return options
    }

    /// Sends a request that needs no input (empty cargo).
    func sendSimpleEntry(_ entry: RequestEntry) {
        send(entry.metadata.type.init(cargo: Data()))
    }

    /// Sends a request after the user has supplied parameters and/or raw cargo hex.
    func sendEntry(_ entry: RequestEntry) {
        // A raw cargo hex override always takes precedence when provided.
        if let hexMessage = messageFromHex(entry.metadata) {
            send(hexMessage)
            return
        }

        if let option = entry.parameterized {
            send(option.build(parameterInput))
            return
        }

        // No parameters defined: fall back to empty cargo for zero-length requests.
        if entry.metadata.size == 0 {
            send(entry.metadata.type.init(cargo: Data()))
        } else {
            lastSendError = "Provide parameters or raw cargo hex before sending"
        }
    }

    func resendLastMessage() {
        guard let lastRequestMessage else {
            lastSendError = "No previous request to resend"
            return
        }
        send(lastRequestMessage)
    }

    /// Clears any transient input/response state, e.g. when opening a request detail screen.
    func resetInput() {
        parameterInput = [:]
        cargoHexInput = ""
        lastResponseDescription = nil
        lastResponseJSON = nil
        lastSendError = nil
    }

    private func messageFromHex(_ metadata: MessageMetadata) -> Message? {
        let cleaned = cargoHexInput.replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty,
              let data = Data(hexadecimalString: cleaned)
        else {
            return nil
        }
        return metadata.type.init(cargo: data)
    }

    var isAwaitingCommandConfirmation: Bool {
        if case .command = awaitingConfirmation { return true }
        return false
    }

    var isAwaitingDangerousConfirmation: Bool {
        if case .dangerous = awaitingConfirmation { return true }
        return false
    }

    var confirmationMessage: String {
        switch awaitingConfirmation {
        case let .command(message):
            return "You are sending a command which can modify the pump's state: \(String(describing: message))"
        case let .dangerous(_, reason):
            return "This is a dangerous command, are you sure you want to continue? Reason: \(reason)"
        case nil:
            return ""
        }
    }

    /// Returns whether the message went out; false when it still waits on the dangerous-command confirmation.
    @discardableResult
    func confirmPendingSend() -> Bool {
        switch awaitingConfirmation {
        case let .command(message):
            awaitingConfirmation = nil
            if let reason = type(of: message).props.dangerousRequireExplicitConfirmation {
                // SwiftUI drops an alert presented while the one before it is still animating away.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.awaitingConfirmation = .dangerous(message, reason: reason)
                }
                return false
            }
            dispatch(message)
            return true
        case let .dangerous(message, _):
            awaitingConfirmation = nil
            dispatch(message)
            return true
        case nil:
            return false
        }
    }

    func cancelPendingSend() {
        awaitingConfirmation = nil
    }

    private func send(_ message: Message?) {
        guard let message else {
            lastSendError = "Unable to build message"
            return
        }

        guard pumpManager != nil else {
            lastSendError = "Pump not available"
            return
        }

        let reason = type(of: message).props.dangerousRequireExplicitConfirmation
        switch MessageRegistry.metadata(for: message)?.category {
        case .control,
             .authentication:
            lastSendError = nil
            awaitingConfirmation = .command(message)
        default:
            if let reason {
                lastSendError = nil
                awaitingConfirmation = .dangerous(message, reason: reason)
            } else {
                dispatch(message)
            }
        }
    }

    private func dispatch(_ message: Message) {
        guard let pumpManager else {
            lastSendError = "Pump not available"
            return
        }

        lastRequestMessage = message
        isSending = true
        lastSendError = nil
        lastResponseDescription = nil
        lastResponseJSON = nil

        pumpManager.sendDebugMessage(message) { [weak self] response in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSending = false
                if let response {
                    self.lastResponseDescription = String(describing: response)
                    self.lastResponseJSON = PumpProfileReadout.jsonString(for: response)
                } else {
                    self.lastSendError = "No response received"
                }
            }
        }
    }

    private static func parseBool(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["true", "1", "yes"].contains(value.lowercased())
    }
}
