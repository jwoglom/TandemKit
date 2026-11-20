import Foundation

/// The pump's response to a DismissNotificationRequest, written right after that request's `ControlRequestHistoryLog`.
/// Provisional name; see https://github.com/jwoglom/pumpX2/issues/147.
public class DismissNotificationResponseHistoryLog: HistoryLog {
    public static let typeId = 334

    /// Unsigned opcode of the response: always 185, DismissNotificationResponse.
    public let responseOpCode: Int
    public let unknown11: Int
    /// The response's status byte; 0 is success.
    public let status: Int
    public let unknownTail: Data

    public required init(cargo: Data) {
        let start = cargo.startIndex
        responseOpCode = Int(cargo[start + 10])
        unknown11 = Int(cargo[start + 11])
        status = Int(cargo[start + 12])
        unknownTail = Data(cargo[(start + 13) ..< (start + 26)])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        responseOpCode: Int,
        unknown11: Int = 0,
        status: Int,
        unknownTail: Data = Data(count: 13)
    ) {
        let payload = DismissNotificationResponseHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            responseOpCode: responseOpCode,
            unknown11: unknown11,
            status: status,
            unknownTail: unknownTail
        )
        self.responseOpCode = responseOpCode
        self.unknown11 = unknown11
        self.status = status
        self.unknownTail = payload.subdata(in: (payload.startIndex + 13) ..< (payload.startIndex + 26))
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        responseOpCode: Int,
        unknown11: Int = 0,
        status: Int,
        unknownTail: Data = Data(count: 13)
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstByteLittleEndian(responseOpCode),
                Bytes.firstByteLittleEndian(unknown11),
                Bytes.firstByteLittleEndian(status),
                unknownTail.prefix(13)
            )
        )
    }

    override public var description: String {
        "DismissNotificationResponseHistoryLog(cargo=\(cargo.hexadecimalString), responseOpCode=\(responseOpCode), unknown11=\(unknown11), status=\(status), unknownTail=\(unknownTail.hexadecimalString))"
    }
}
