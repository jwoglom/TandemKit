import Foundation

/// Every request and response of one read of the pump's insulin delivery profiles, for the debug
/// Pump Profile Viewer: `ProfileStatusRequest`, then `IDPSettingsRequest` for each profile slot,
/// then `IDPSegmentRequest` for each of that profile's segments.
public struct PumpProfileReadout {
    public struct Exchange {
        public let request: Message
        /// Nil when the pump never answered, which ends the read.
        public let response: Message?
        public let receivedAt: Date
    }

    public struct Profile {
        public let idpId: Int
        public let settings: Exchange
        public var segments: [Exchange] = []
    }

    public var status: Exchange?
    public var profiles: [Profile] = []
    /// Why the read stopped early; nil when every profile and segment was read.
    public var failure: String?

    /// A message's stored properties in declaration order, excluding `cargo`.
    public static func fields(of message: Message) -> [(label: String, value: String)] {
        Mirror(reflecting: message).children.compactMap { child in
            guard let label = child.label, label != "cargo" else { return nil }
            return (label, displayValue(child.value))
        }
    }

    public static func messageName(_ message: Message) -> String {
        String(describing: type(of: message))
    }

    public func jsonData(exportedAt: Date) -> Data? {
        try? JSONSerialization.data(withJSONObject: jsonObject(exportedAt: exportedAt), options: [.prettyPrinted, .sortedKeys])
    }

    func jsonObject(exportedAt: Date) -> [String: Any] {
        [
            "exportedAt": Self.timestampFormatter.string(from: exportedAt),
            "complete": failure == nil,
            "failure": failure ?? NSNull(),
            "profileStatus": status.map(Self.jsonObject(for:)) ?? NSNull(),
            "profiles": profiles.map { profile in
                [
                    "idpId": profile.idpId,
                    "settings": Self.jsonObject(for: profile.settings),
                    "segments": profile.segments.map(Self.jsonObject(for:))
                ] as [String: Any]
            }
        ]
    }

    private static func jsonObject(for exchange: Exchange) -> [String: Any] {
        [
            "request": jsonObject(for: exchange.request),
            "response": exchange.response.map(jsonObject(for:)) ?? NSNull(),
            "receivedAt": timestampFormatter.string(from: exchange.receivedAt)
        ]
    }

    private static func jsonObject(for message: Message) -> [String: Any] {
        var fields: [String: Any] = [:]
        for child in Mirror(reflecting: message).children {
            guard let label = child.label, label != "cargo" else { continue }
            fields[label] = jsonValue(child.value)
        }
        return [
            "name": messageName(message),
            "opCode": Int(type(of: message).props.opCode),
            "cargoHex": message.cargo.hexadecimalString,
            "fields": fields
        ]
    }

    private static func jsonValue(_ value: Any) -> Any {
        switch value {
        case let value as Bool: value
        case let value as String: value
        case let value as Data: value.hexadecimalString
        case let value as any BinaryInteger: Int(value)
        default: String(describing: value)
        }
    }

    private static func displayValue(_ value: Any) -> String {
        if let data = value as? Data {
            return data.hexadecimalString
        }
        return String(describing: value)
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

public extension TandemPumpManager {
    /// Calls `completion` on the command queue.
    func readPumpProfiles(completion: @escaping (PumpProfileReadout) -> Void) {
        bluetooth.ensureConnected { error in
            if let error {
                completion(PumpProfileReadout(failure: "Could not connect to the pump: \(error)"))
                return
            }
            completion(self.readPumpProfilesInCommandJob())
        }
    }
}

extension TandemPumpManager {
    /// Stops at the first unanswered request: that is almost always a dropped connection, and each
    /// further request would only wait out its own timeout.
    func readPumpProfilesInCommandJob() -> PumpProfileReadout {
        var readout = PumpProfileReadout()

        let statusRequest = ProfileStatusRequest()
        let status = bluetooth.write(statusRequest)
        readout.status = .init(request: statusRequest, response: status, receivedAt: now)
        guard let status else {
            readout.failure = "No response to ProfileStatusRequest"
            return readout
        }

        for idpId in status.idpSlotIds {
            let settingsRequest = IDPSettingsRequest(idpId: idpId)
            let settings = bluetooth.write(settingsRequest)
            var profile = PumpProfileReadout.Profile(
                idpId: idpId,
                settings: .init(request: settingsRequest, response: settings, receivedAt: now)
            )
            guard let settings else {
                readout.profiles.append(profile)
                readout.failure = "No response to IDPSettingsRequest for IDP \(idpId)"
                return readout
            }

            for segmentIndex in 0 ..< settings.numberOfProfileSegments {
                let segmentRequest = IDPSegmentRequest(idpId: idpId, segmentIndex: segmentIndex)
                let segment = bluetooth.write(segmentRequest)
                profile.segments.append(.init(request: segmentRequest, response: segment, receivedAt: now))
                guard segment != nil else {
                    readout.profiles.append(profile)
                    readout.failure = "No response to IDPSegmentRequest for IDP \(idpId) segment \(segmentIndex)"
                    return readout
                }
            }
            readout.profiles.append(profile)
        }

        return readout
    }
}
