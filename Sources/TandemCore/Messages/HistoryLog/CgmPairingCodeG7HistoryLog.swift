import Foundation

public class CgmPairingCodeG7HistoryLog: HistoryLog {
    public static let typeId = 395

    public let pairingCode: String

    public required init(cargo: Data) {
        let codeData = cargo.subdata(in: 10 ..< min(26, cargo.count))
        pairingCode = String(bytes: codeData, encoding: .ascii)?
            .trimmingCharacters(in: .init(charactersIn: "\0")) ?? ""
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, pairingCode: String) {
        let payload = CgmPairingCodeG7HistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            pairingCode: pairingCode
        )
        self.pairingCode = pairingCode
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, pairingCode: String) -> Data {
        var codeBytes = Data(repeating: 0, count: 16)
        if let ascii = pairingCode.data(using: .ascii) {
            let count = min(16, ascii.count)
            codeBytes.replaceSubrange(0 ..< count, with: ascii.prefix(count))
        }
        return HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                codeBytes
            )
        )
    }

    override public var description: String {
        "CgmPairingCodeG7HistoryLog(cargo=\(cargo.hexadecimalString), pairingCode=\(pairingCode))"
    }
}
