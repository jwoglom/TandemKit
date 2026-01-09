import Foundation
import SwiftUI
import TandemCore

final class TandemKitDebugViewModel: ObservableObject {
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

    @Published var lastResponseDescription: String?
    @Published var lastSendError: String?
    @Published var isSending = false

    @Published var parameterInput: [String: String] = [:]
    @Published var cargoHexInput: String = ""

    private let pumpManager: TandemPumpManager?

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
    }

    var pumpStateDebugDescription: String {
        pumpManager?.state.pumpState?.debugDescription ?? "No PumpState available"
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

    var requestMessages: [MessageMetadata] {
        MessageRegistry.all
            .filter { $0.messageType == .Request && $0.size == 0 }
            .sorted { $0.name < $1.name }
    }

    var parameterizedMessages: [ParameterizedOption] {
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
                    fields: [ParameterField(id: "bolusId", label: "Bolus ID", placeholder: "0", type: .unsigned)],
                    build: { input in
                        input["bolusId"].flatMap(UInt32.init).map(BolusPermissionReleaseRequest.init)
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

                        let useCalibration = ParameterizedOption.parseBool(input["useForCalibration"])
                        let autoPop = ParameterizedOption.parseBool(input["isAutopop"])
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
                        let enabled = ParameterizedOption.parseBool(input["enabled"])
                        return ChangeControlIQSettingsRequest(enabled: enabled, weightLbs: weight, totalDailyInsulinUnits: tdi)
                    }
                )
            )
        }

        return options.sorted { $0.metadata.name < $1.metadata.name }
    }

    func sendSimpleMessage(_ metadata: MessageMetadata) {
        let message = metadata.type.init(cargo: Data())
        send(message)
    }

    func sendParameterizedMessage(_ option: ParameterizedOption) {
        if let hexMessage = messageFromHex(option.metadata) {
            send(hexMessage)
            return
        }

        let message = option.build(parameterInput)
        send(message)
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

    private func send(_ message: Message?) {
        guard let message else {
            lastSendError = "Unable to build message"
            return
        }

        isSending = true
        lastSendError = nil
        lastResponseDescription = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let response = self.pumpManager?.sendMessage(message: message)

            DispatchQueue.main.async {
                self.isSending = false
                if let response {
                    self.lastResponseDescription = String(describing: response)
                } else {
                    self.lastSendError = "No response received"
                }
            }
        }
    }
}

private extension TandemKitDebugViewModel.ParameterizedOption {
    static func parseBool(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["true", "1", "yes"].contains(value.lowercased())
    }
}

private extension Data {
    init?(hexadecimalString: String) {
        let length = hexadecimalString.count / 2
        var data = Data(capacity: length)
        var index = hexadecimalString.startIndex
        for _ in 0 ..< length {
            let nextIndex = hexadecimalString.index(index, offsetBy: 2)
            guard nextIndex <= hexadecimalString.endIndex,
                  let byte = UInt8(hexadecimalString[index ..< nextIndex], radix: 16)
            else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
