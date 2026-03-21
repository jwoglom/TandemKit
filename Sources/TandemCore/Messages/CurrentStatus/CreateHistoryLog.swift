import Foundation

/// Request the pump to create history log entries.
public class CreateHistoryLogRequest: Message {
    public static let props = MessageProps(
        opCode: 126,
        size: 4,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var numberOfLogs: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        numberOfLogs = Bytes.readUint32(cargo, 0)
    }

    public init(numberOfLogs: UInt32) {
        cargo = Bytes.toUint32(numberOfLogs)
        self.numberOfLogs = numberOfLogs
    }

    public var description: String {
        "CreateHistoryLogRequest(cargo=\(cargo.hexadecimalString), numberOfLogs=\(numberOfLogs))"
    }
}

/// Response to the create history log request.
public class CreateHistoryLogResponse: Message {
    public static let props = MessageProps(
        opCode: 127,
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

    public var description: String {
        "CreateHistoryLogResponse(cargo=\(cargo.hexadecimalString), status=\(status), streamId=\(streamId))"
    }
}
