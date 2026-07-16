import Foundation

/// Formatting helpers for displaying and exporting history logs.
///
/// The export format mirrors the JSONL emitted by pumpX2's cliparser `jsonlines` subcommand
/// (https://github.com/jwoglom/pumpX2), where each line is
/// `{"parsed": {name, messageProps, params, cargoHex}, "raw": {btChar, type, value, ts}}`
/// and each history log inside `params.historyLogs` is a commons-lang style
/// `TypeName[field=value,...,cargo={...},pumpTimeSec=...,sequenceNum=...]` string.
public enum HistoryLogExport {
    /// Short type name for a history log, e.g. "BolusCompletedHistoryLog".
    public static func typeName(_ log: HistoryLog) -> String {
        String(describing: type(of: log))
    }

    /// Ordered (label, value) pairs for a history log: the concrete type's own fields first
    /// (declaration order), then the shared cargo/pumpTimeSec/sequenceNum, matching the field
    /// order of pumpX2's reflection-based toString. `typeId` is only included for
    /// UnknownHistoryLog, where pumpX2 stores it as a field rather than a method.
    public static func fields(_ log: HistoryLog) -> [(label: String, value: String)] {
        var result: [(label: String, value: String)] = []
        let mirror = Mirror(reflecting: log)
        for child in mirror.children {
            guard let label = child.label else { continue }
            result.append((label, formatValue(child.value)))
        }
        if log is UnknownHistoryLog {
            result.append(("typeId", String(log.typeId)))
        }
        result.append(("cargo", formatValue(log.cargo)))
        result.append(("pumpTimeSec", String(log.pumpTimeSec)))
        result.append(("sequenceNum", String(log.sequenceNum)))
        return result
    }

    /// pumpX2 cliparser-style single-line string, e.g.
    /// `TempRateActivatedHistoryLog[duration=900000.0,percent=101.0,tempRateId=15,cargo={2,16,...},pumpTimeSec=535733187,sequenceNum=41481]`
    public static func pumpX2String(_ log: HistoryLog) -> String {
        let body = fields(log).map { "\($0.label)=\($0.value)" }.joined(separator: ",")
        return "\(typeName(log))[\(body)]"
    }

    /// Multi-line human-readable dump of a history log for detail views.
    public static func prettyDescription(_ log: HistoryLog) -> String {
        var lines = ["\(typeName(log)) (typeId \(log.typeId))"]
        lines.append("sequenceNum: \(log.sequenceNum)")
        let date = Dates.fromJan12008EpochSecondsToDate(TimeInterval(log.pumpTimeSec))
        lines.append("pumpTimeSec: \(log.pumpTimeSec) (\(prettyDateFormatter.string(from: date)))")
        let mirror = Mirror(reflecting: log)
        for child in mirror.children {
            guard let label = child.label else { continue }
            lines.append("\(label): \(formatValue(child.value))")
        }
        lines.append("cargo: \(log.cargo.hexadecimalString)")
        return lines.joined(separator: "\n")
    }

    /// One cliparser-format JSONL line per received HistoryLogStreamResponse.
    public static func jsonl(for messages: [(receivedAt: Date, message: HistoryLogStreamResponse)]) -> String {
        messages.compactMap { jsonlLine(for: $0.message, receivedAt: $0.receivedAt) }
            .joined(separator: "\n")
    }

    /// Single cliparser-format JSON line for a HistoryLogStreamResponse.
    public static func jsonlLine(for message: HistoryLogStreamResponse, receivedAt: Date) -> String? {
        let object = jsonObject(for: message, receivedAt: receivedAt)
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return line
    }

    static func jsonObject(for message: HistoryLogStreamResponse, receivedAt: Date) -> [String: Any] {
        // Static props mirroring pumpX2's HistoryLogStreamResponse messageProps output.
        let messageProps: [String: Any] = [
            "opCode": -127,
            "size": 28,
            "type": "RESPONSE",
            "characteristic": "HISTORY_LOG",
            "characteristicUuid": "7b83fff8-9f77-4e5c-8064-aae2c24838b9",
            "variableSize": true,
            "stream": true,
            "signed": false,
            "modifiesInsulinDelivery": false,
            "supportedDevices": "ALL",
            "minApi": "API_V2_1",
            "requestName": "request.historyLog.NonexistentHistoryLogStreamRequest",
            "requestOpCode": 0
        ]

        let params: [String: Any] = [
            "numberOfHistoryLogs": message.numberOfHistoryLogs,
            "streamId": message.streamId,
            "historyLogs": message.historyLogs.map { pumpX2String($0) },
            "cargo": message.cargo.map { Int(Int8(bitPattern: $0)) }
        ]

        let parsed: [String: Any] = [
            "name": "response.historyLog.HistoryLogStreamResponse",
            "cargoHex": message.cargo.hexadecimalString,
            "messageProps": messageProps,
            "params": params
        ]

        // The cliparser echoes back its input BT capture line as "raw"; we don't retain the
        // BLE packet framing here, so only the characteristic/timestamp context is provided.
        let raw: [String: Any] = [
            "btChar": "7b83fff89f774e5c8064aae2c24838b9",
            "type": "ReadResp",
            "value": "",
            "ts": rawTimestampFormatter.string(from: receivedAt)
        ]

        return ["parsed": parsed, "raw": raw]
    }

    /// Formats a mirrored field value in pumpX2 toString style: Data as signed byte lists
    /// (`{2,16,-61}`), optionals unwrapped (nil as `<null>`), everything else via its
    /// default string representation.
    static func formatValue(_ value: Any) -> String {
        if let data = value as? Data {
            return "{" + data.map { String(Int8(bitPattern: $0)) }.joined(separator: ",") + "}"
        }

        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let unwrapped = mirror.children.first?.value else {
                return "<null>"
            }
            return formatValue(unwrapped)
        }

        return String(describing: value)
    }

    private static let rawTimestampFormatter: DateFormatter = {
        // Matches the wireshark-csv-to-jsonl.py timestamps consumed/echoed by cliparser.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
        return formatter
    }()

    private static let prettyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
