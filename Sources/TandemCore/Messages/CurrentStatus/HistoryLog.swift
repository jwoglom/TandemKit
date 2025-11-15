import Foundation

/// Request a set of history log entries starting from a sequence number.
public class HistoryLogRequest: Message {
    public static let props = MessageProps(
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
        startLog = Bytes.readUint32(cargo, 0)
        numberOfLogs = Int(cargo[4])
    }

    public init(startLog: UInt32, numberOfLogs: Int) {
        cargo = Bytes.combine(
            Bytes.toUint32(startLog),
            Bytes.firstByteLittleEndian(numberOfLogs)
        )
        self.startLog = startLog
        self.numberOfLogs = numberOfLogs
    }
}

/// Response containing status and stream ID for a history log request.
public class HistoryLogResponse: Message {
    public static let props = MessageProps(
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
        status = Int(cargo[0])
        streamId = Int(cargo[1])
    }

    public init(status: Int, streamId: Int) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(status),
            Bytes.firstByteLittleEndian(streamId)
        )
        self.status = status
        self.streamId = streamId
    }
}
