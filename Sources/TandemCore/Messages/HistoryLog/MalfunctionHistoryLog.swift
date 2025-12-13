import Foundation

/// History log entry for a malfunction activation.
public class MalfunctionHistoryLog: HistoryLog {
    public static let typeId = 6

    public let malfId: UInt32
    public let faultLocatorData: UInt32
    public let param1: UInt32
    public let param2: Float

    public required init(cargo: Data) {
        malfId = Bytes.readUint32(cargo, 10)
        faultLocatorData = Bytes.readUint32(cargo, 14)
        param1 = Bytes.readUint32(cargo, 18)
        param2 = Bytes.readFloat(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, malfId: UInt32, faultLocatorData: UInt32, param1: UInt32, param2: Float) {
        let payload = MalfunctionHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            malfId: malfId,
            faultLocatorData: faultLocatorData,
            param1: param1,
            param2: param2
        )
        self.malfId = malfId
        self.faultLocatorData = faultLocatorData
        self.param1 = param1
        self.param2 = param2
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        malfId: UInt32,
        faultLocatorData: UInt32,
        param1: UInt32,
        param2: Float
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId & 0xFF), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.toUint32(malfId),
                Bytes.toUint32(faultLocatorData),
                Bytes.toUint32(param1),
                Bytes.toFloat(param2)
            )
        )
    }
}

public extension MalfunctionHistoryLog {
    var description: String {
        "MalfunctionHistoryLog(cargo=\(cargo.hexadecimalString), malfId=\(malfId), faultLocatorData=\(faultLocatorData), param1=\(param1), param2=\(param2))"
    }
}
