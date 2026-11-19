import Foundation

/// The pump's response to a SetTempRateRequest, written right after its `ControlRequestHistoryLog`.
/// Provisional name; see https://github.com/jwoglom/pumpX2/issues/145.
public class SetTempRateResponseHistoryLog: HistoryLog {
    public static let typeId = 309

    /// 0 when the temp rate started, 1 when it was rejected.
    public let status: Int
    /// Byte 3 of SetTempRateResponse; 0 on success, 1 on every rejection observed.
    public let unknown11: Int
    /// Matches `TempRateActivatedHistoryLog.tempRateId`; 0 when rejected.
    public let tempRateId: Int

    public required init(cargo: Data) {
        status = Int(cargo[cargo.startIndex + 10])
        unknown11 = Int(cargo[cargo.startIndex + 11])
        tempRateId = Bytes.readShort(cargo, 12)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, status: Int, unknown11: Int, tempRateId: Int) {
        let payload = SetTempRateResponseHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            status: status,
            unknown11: unknown11,
            tempRateId: tempRateId
        )
        self.status = status
        self.unknown11 = unknown11
        self.tempRateId = tempRateId
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, status: Int, unknown11: Int, tempRateId: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstByteLittleEndian(status),
                Bytes.firstByteLittleEndian(unknown11),
                Bytes.firstTwoBytesLittleEndian(tempRateId)
            )
        )
    }

    override public var description: String {
        "SetTempRateResponseHistoryLog(cargo=\(cargo.hexadecimalString), status=\(status), unknown11=\(unknown11), tempRateId=\(tempRateId))"
    }
}
