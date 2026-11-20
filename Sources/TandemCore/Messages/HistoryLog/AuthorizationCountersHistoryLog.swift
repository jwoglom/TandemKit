import Foundation

/// Two-hourly Mobi counters (jwoglom/pumpX2#151). Provisional name; `unknown*` fields are unidentified.
/// `authorizationRequestCount` counts AUTHORIZATION requests answered since the previous burst.
public class AuthorizationCountersHistoryLog: HistoryLog {
    public static let typeId = 494

    public let authorizationRequestCount: UInt32
    public let unknown14: UInt32
    public let unknown18: UInt32
    public let unknown22: UInt32

    public required init(cargo: Data) {
        authorizationRequestCount = Bytes.readUint32(cargo, 10)
        unknown14 = Bytes.readUint32(cargo, 14)
        unknown18 = Bytes.readUint32(cargo, 18)
        unknown22 = Bytes.readUint32(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, authorizationRequestCount: UInt32, unknown14: UInt32, unknown18: UInt32, unknown22: UInt32) {
        let payload = AuthorizationCountersHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            authorizationRequestCount: authorizationRequestCount,
            unknown14: unknown14,
            unknown18: unknown18,
            unknown22: unknown22
        )
        self.authorizationRequestCount = authorizationRequestCount
        self.unknown14 = unknown14
        self.unknown18 = unknown18
        self.unknown22 = unknown22
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, authorizationRequestCount: UInt32, unknown14: UInt32, unknown18: UInt32, unknown22: UInt32) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(authorizationRequestCount),
                Bytes.toUint32(unknown14),
                Bytes.toUint32(unknown18),
                Bytes.toUint32(unknown22)
            )
        )
    }

    override public var description: String {
        "AuthorizationCountersHistoryLog(cargo=\(cargo.hexadecimalString), authorizationRequestCount=\(authorizationRequestCount), unknown14=\(unknown14), unknown18=\(unknown18), unknown22=\(unknown22))"
    }
}
