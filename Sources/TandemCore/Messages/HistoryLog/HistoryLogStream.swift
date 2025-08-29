//
//  HistoryLogStream.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representations of NonexistentHistoryLogStreamRequest and HistoryLogStreamResponse.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/historyLog/NonexistentHistoryLogStreamRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/HistoryLogStreamResponse.java
//

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
        self.cargo = Data()
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

    public required init(cargo: Data) {
        self.cargo = cargo
        self.numberOfHistoryLogs = Int(cargo[0])
        self.streamId = Int(cargo[1])

        var list: [Data] = []
        var idx = 2
        while idx + HistoryLog.length <= cargo.count {
            list.append(cargo.subdata(in: idx..<(idx + HistoryLog.length)))
            idx += HistoryLog.length
        }
        self.historyLogStreamBytes = list
        self.historyLogs = list.map { HistoryLogParser.parse($0) }
    }

    public init(numberOfHistoryLogs: Int, streamId: Int, historyLogStreamBytes: [Data]) {
        var combined = Data()
        historyLogStreamBytes.forEach { combined.append($0) }
        self.cargo = Bytes.combine(
            Data([UInt8(numberOfHistoryLogs)]),
            Data([UInt8(streamId)]),
            combined
        )
        self.numberOfHistoryLogs = numberOfHistoryLogs
        self.streamId = streamId
        self.historyLogStreamBytes = historyLogStreamBytes
        self.historyLogs = historyLogStreamBytes.map { HistoryLogParser.parse($0) }
    }
}

