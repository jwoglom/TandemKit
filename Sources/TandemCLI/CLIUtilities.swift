import Foundation
import TandemCore

struct CLIError: Error, CustomStringConvertible {
    let message: String
    let exitCode: Int
    var description: String { message }

    init(_ message: String = "", exitCode: Int = 1) {
        self.message = message
        self.exitCode = exitCode
    }
}

struct PacketHeader {
    let packetsRemaining: UInt8
    let packetTxId: UInt8
    let opCode: UInt8
    let messageTxId: UInt8
    let declaredPayloadLength: Int
}

func parseHeader(from data: Data) throws -> PacketHeader {
    guard data.count >= 5 else {
        throw CLIError("Packet must contain at least 5 bytes, found \(data.count)")
    }
    let packetsRemaining = data[0]
    let packetTxId = data[1]
    let opCode = data[2]
    let messageTxId = data[3]
    let declaredLength = Int(data[4])
    return PacketHeader(
        packetsRemaining: packetsRemaining,
        packetTxId: packetTxId,
        opCode: opCode,
        messageTxId: messageTxId,
        declaredPayloadLength: declaredLength
    )
}

func sanitizeHexInput(_ input: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let withoutPrefix = trimmed.replacingOccurrences(of: "0x", with: "", options: [.caseInsensitive, .anchored])
    let filtered = withoutPrefix.filter { !$0.isWhitespace && $0 != "_" }
    return filtered
}

func dataFromHex(_ hex: String) throws -> Data {
    let sanitized = sanitizeHexInput(hex)
    guard let data = Data(hexadecimalString: sanitized) else {
        throw CLIError("Invalid hexadecimal string: \(hex)")
    }
    return data
}

enum OutputFormat: String {
    case json
    case text
}

enum CharacteristicParser {
    static func parse(_ value: String) throws -> CharacteristicUUID {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let known = aliasMap[normalized] {
            return known
        }

        let stripped = normalized.replacingOccurrences(of: "-", with: "")
        let formatted: String
        if stripped.count == 32 {
            formatted = stride(from: 0, to: stripped.count, by: 4).map { idx -> String in
                let start = stripped.index(stripped.startIndex, offsetBy: idx)
                let end = stripped.index(stripped.startIndex, offsetBy: min(idx + 4, stripped.count))
                return String(stripped[start ..< end])
            }.joined(separator: "-")
        } else {
            formatted = value
        }

        if let uuid = CharacteristicUUID(rawValue: formatted.uppercased()) {
            return uuid
        }

        if let match = AllPumpCharacteristicUUIDs
            .first(where: { $0.rawValue.compare(formatted, options: .caseInsensitive) == .orderedSame })
        {
            return match
        }

        throw CLIError("Unknown characteristic: \(value)")
    }

    private static let aliasMap: [String: CharacteristicUUID] = [
        "auth": .AUTHORIZATION_CHARACTERISTICS,
        "authorization": .AUTHORIZATION_CHARACTERISTICS,
        "authorisation": .AUTHORIZATION_CHARACTERISTICS,
        "currentstatus": .CURRENT_STATUS_CHARACTERISTICS,
        "current_status": .CURRENT_STATUS_CHARACTERISTICS,
        "current-status": .CURRENT_STATUS_CHARACTERISTICS,
        "status": .CURRENT_STATUS_CHARACTERISTICS,
        "history": .HISTORY_LOG_CHARACTERISTICS,
        "history_log": .HISTORY_LOG_CHARACTERISTICS,
        "historylog": .HISTORY_LOG_CHARACTERISTICS,
        "qualifying": .QUALIFYING_EVENTS_CHARACTERISTICS,
        "qualifyingevents": .QUALIFYING_EVENTS_CHARACTERISTICS,
        "qualifying_events": .QUALIFYING_EVENTS_CHARACTERISTICS,
        "control": .CONTROL_CHARACTERISTICS,
        "controlstream": .CONTROL_STREAM_CHARACTERISTICS,
        "control_stream": .CONTROL_STREAM_CHARACTERISTICS,
        "control-stream": .CONTROL_STREAM_CHARACTERISTICS
    ]
}
