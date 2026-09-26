import Foundation

/// One record per signed CONTROL-characteristic request the pump received, except the bolus-flow requests.
/// Provisional name; see https://github.com/jwoglom/pumpX2/issues/145.
public class ControlRequestHistoryLog: HistoryLog {
    public static let typeId = 290

    /// The time value from the request's signed trailer as the app sent it: `pumpTimeSinceReset` with
    /// TandemKit/pumpX2, the phone's UTC seconds since 2008 with Tandem's app. Not a pump clock reading.
    public let requestTimestamp: UInt32
    /// Unsigned opcode of the request, e.g. 164 SetTempRateRequest, 166 StopTempRateRequest.
    public let requestOpCode: Int

    public required init(cargo: Data) {
        requestTimestamp = Bytes.readUint32(cargo, 10)
        requestOpCode = Int(cargo[cargo.startIndex + 14])
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, requestTimestamp: UInt32, requestOpCode: Int) {
        let payload = ControlRequestHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            requestTimestamp: requestTimestamp,
            requestOpCode: requestOpCode
        )
        self.requestTimestamp = requestTimestamp
        self.requestOpCode = requestOpCode
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, requestTimestamp: UInt32, requestOpCode: Int) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(requestTimestamp),
                Bytes.firstByteLittleEndian(requestOpCode)
            )
        )
    }

    public var description: String {
        "ControlRequestHistoryLog(cargo=\(cargo.hexadecimalString), requestTimestamp=\(requestTimestamp), requestOpCode=\(requestOpCode))"
    }
}
