import Foundation

/// Daily Mobi BLE connection summary (jwoglom/pumpX2#152), written every 24 h counted from the last pump restart. Provisional name; `unknown*` fields are unidentified.
/// Counts cover the 24 h ending at the header time; `connections - unauthenticatedConnections` matched TandemKit's authenticated sessions in 12 of 12 days.
public class BleDailyConnectionsHistoryLog: HistoryLog {
    public static let typeId = 474

    /// Percent of the period with a BLE connection, apparently rounded (97-100 observed).
    public let connectedPercent: Int
    public let unknown11: Int
    /// BLE connections accepted, including ones that failed encryption or authentication; byte 13 was always 0, read as uint16.
    public let connections: Int
    /// Connections that never completed JPAKE key confirmation; byte 15 was always 0, read as uint16.
    public let unauthenticatedConnections: Int
    /// Bytes 16-25, zero in every record examined.
    public let unknownTail: Data

    public var authenticatedConnections: Int {
        connections - unauthenticatedConnections
    }

    public required init(cargo: Data) {
        let start = cargo.startIndex
        connectedPercent = Int(cargo[start + 10])
        unknown11 = Int(cargo[start + 11])
        connections = Bytes.readShort(cargo, 12)
        unauthenticatedConnections = Bytes.readShort(cargo, 14)
        unknownTail = Data(cargo[(start + 16) ..< (start + 26)])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        connectedPercent: Int,
        unknown11: Int,
        connections: Int,
        unauthenticatedConnections: Int,
        unknownTail: Data = Data(count: 10)
    ) {
        let payload = BleDailyConnectionsHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            connectedPercent: connectedPercent,
            unknown11: unknown11,
            connections: connections,
            unauthenticatedConnections: unauthenticatedConnections,
            unknownTail: unknownTail
        )
        self.connectedPercent = connectedPercent
        self.unknown11 = unknown11
        self.connections = connections
        self.unauthenticatedConnections = unauthenticatedConnections
        self.unknownTail = payload.subdata(in: (payload.startIndex + 16) ..< (payload.startIndex + 26))
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        connectedPercent: Int,
        unknown11: Int,
        connections: Int,
        unauthenticatedConnections: Int,
        unknownTail: Data = Data(count: 10)
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstByteLittleEndian(connectedPercent),
                Bytes.firstByteLittleEndian(unknown11),
                Bytes.firstTwoBytesLittleEndian(connections),
                Bytes.firstTwoBytesLittleEndian(unauthenticatedConnections),
                unknownTail.prefix(10)
            )
        )
    }

    public var description: String {
        "BleDailyConnectionsHistoryLog(cargo=\(cargo.hexadecimalString), connectedPercent=\(connectedPercent), unknown11=\(unknown11), connections=\(connections), unauthenticatedConnections=\(unauthenticatedConnections), unknownTail=\(unknownTail.hexadecimalString))"
    }
}
