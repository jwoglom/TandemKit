import Foundation

public class TipsErrorHistoryLog: HistoryLog {
    public static let typeId = 419

    public let messageType: Int
    public let requestCode: Int
    public let errorCode: Int
    public let isDataMasked: Bool

    public required init(cargo: Data) {
        messageType = Int(cargo[10])
        requestCode = Int(cargo[11])
        errorCode = Int(cargo[12])
        isDataMasked = cargo[13] != 0
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        messageType: Int,
        requestCode: Int,
        errorCode: Int,
        isDataMasked: Bool
    ) {
        let payload = TipsErrorHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            messageType: messageType,
            requestCode: requestCode,
            errorCode: errorCode,
            isDataMasked: isDataMasked
        )
        self.messageType = messageType
        self.requestCode = requestCode
        self.errorCode = errorCode
        self.isDataMasked = isDataMasked
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        messageType: Int,
        requestCode: Int,
        errorCode: Int,
        isDataMasked: Bool
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(messageType & 0xFF), UInt8(requestCode & 0xFF), UInt8(errorCode & 0xFF), isDataMasked ? 1 : 0])
            )
        )
    }

    public var description: String {
        "TipsErrorHistoryLog(cargo=\(cargo.hexadecimalString), messageType=\(messageType), requestCode=\(requestCode), errorCode=\(errorCode), isDataMasked=\(isDataMasked))"
    }
}
