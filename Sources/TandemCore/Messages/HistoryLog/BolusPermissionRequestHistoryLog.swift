import Foundation

/// Opcode 338 (no Tandem name; provisional): one per signed BolusPermissionRequest from a BLE app. pumpX2#142
public class BolusPermissionRequestHistoryLog: HistoryLog {
    public static let typeId = 338

    /// The request's signature-trailer time as the app sent it: TandemKit's last-read pumpTimeSinceReset, not a pump clock.
    public let requestTimestamp: UInt32

    public required init(cargo: Data) {
        requestTimestamp = Bytes.readUint32(cargo, 10)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, requestTimestamp: UInt32) {
        let payload = BolusPermissionRequestHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            requestTimestamp: requestTimestamp
        )
        self.requestTimestamp = requestTimestamp
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, requestTimestamp: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(requestTimestamp)
            )
        )
    }

    public var description: String {
        "BolusPermissionRequestHistoryLog(cargo=\(cargo.hexadecimalString), requestTimestamp=\(requestTimestamp))"
    }
}
