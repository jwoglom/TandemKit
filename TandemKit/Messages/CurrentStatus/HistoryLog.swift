//
//  HistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of HistoryLogRequest and HistoryLogResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/HistoryLogRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/HistoryLogResponse.java
//

import Foundation

/// Request a set of history log entries starting from a sequence number.
public class HistoryLogRequest: Message {
    public static var props = MessageProps(
        opCode: 60,
        size: 5,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var startLog: UInt32
    public var numberOfLogs: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.startLog = Bytes.readUint32(cargo, 0)
        self.numberOfLogs = Int(cargo[4])
    }

    public init(startLog: UInt32, numberOfLogs: Int) {
        self.cargo = Bytes.combine(
            Bytes.toUint32(startLog),
            Bytes.firstByteLittleEndian(numberOfLogs)
        )
        self.startLog = startLog
        self.numberOfLogs = numberOfLogs
    }
}

/// Response containing status and stream ID for a history log request.
public class HistoryLogResponse: Message {
    public static var props = MessageProps(
        opCode: 61,
        size: 2,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var status: Int
    public var streamId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.status = Int(cargo[0])
        self.streamId = Int(cargo[1])
    }

    public init(status: Int, streamId: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(status),
            Bytes.firstByteLittleEndian(streamId)
        )
        self.status = status
        self.streamId = streamId
    }
}

