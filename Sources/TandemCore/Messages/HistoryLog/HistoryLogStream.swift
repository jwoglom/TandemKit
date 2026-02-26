import Foundation

/// Paired request used for HistoryLogStreamResponse, which has no originating request.
public class NonexistentHistoryLogStreamRequest: Message {
    public static let props = MessageProps(
        opCode: 0,
        size: 0,
        type: .Request,
        characteristic: .HISTORY_LOG_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "NonexistentHistoryLogStreamRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response containing a stream of history log entries.
public class HistoryLogStreamResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-127)),
        size: 28,
        type: .Response,
        characteristic: .HISTORY_LOG_CHARACTERISTICS,
        variableSize: true,
        stream: true
    )

    public var cargo: Data
    public var numberOfHistoryLogs: Int
    public var streamId: Int
    public var historyLogStreamBytes: [Data]
    public var historyLogs: [HistoryLog]

    /// PumpX2 stream framing expects: 1 byte count + 1 byte streamId + N*26-byte history logs.
    public var hasExpectedLength: Bool {
        cargo.count == 2 + (numberOfHistoryLogs * HistoryLog.length)
    }

    public required init(cargo: Data) {
        self.cargo = cargo

        guard cargo.count >= 2 else {
            numberOfHistoryLogs = 0
            streamId = 0
            historyLogStreamBytes = []
            historyLogs = []
            return
        }

        numberOfHistoryLogs = Int(cargo[0])
        streamId = Int(cargo[1])

        guard hasExpectedLength else {
            historyLogStreamBytes = []
            historyLogs = []
            return
        }

        var list: [Data] = []
        var idx = 2
        while idx + HistoryLog.length <= cargo.count {
            list.append(cargo.subdata(in: idx ..< (idx + HistoryLog.length)))
            idx += HistoryLog.length
        }
        historyLogStreamBytes = list
        historyLogs = list.map { HistoryLogParser.parse($0) }
    }

    public init(numberOfHistoryLogs: Int, streamId: Int, historyLogStreamBytes: [Data]) {
        var combined = Data()
        historyLogStreamBytes.forEach { combined.append($0) }
        cargo = Bytes.combine(
            Data([UInt8(numberOfHistoryLogs)]),
            Data([UInt8(streamId)]),
            combined
        )
        self.numberOfHistoryLogs = numberOfHistoryLogs
        self.streamId = streamId
        self.historyLogStreamBytes = historyLogStreamBytes
        historyLogs = historyLogStreamBytes.map { HistoryLogParser.parse($0) }
    }

    public var description: String {
        "HistoryLogStreamResponse(cargo=\(cargo.hexadecimalString), numberOfHistoryLogs=\(numberOfHistoryLogs), streamId=\(streamId), historyLogStreamBytes=\(historyLogStreamBytes.map(\.hexadecimalString)), historyLogs=\(historyLogs))"
    }
}
