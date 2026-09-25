import Foundation

/// Opcode 206 (no Tandem name; provisional): IOB snapshot when a bolus is initiated. pumpX2#143
public class IobSnapshotPreBolusHistoryLog: HistoryLog {
    public static let typeId = 206

    public let bolusId: Int
    /// 1 with Control-IQ off, mostly 3 with it on, occasionally 2 or 0; meaning unknown.
    public let unknownU8At12: Int
    /// The displayed IOB model; equals BolusRequestedMsg2 selectedIOB (0 Mudaliar, 1 Swan).
    public let selectedIob: Int
    /// Units; ControlIQIOBResponse.mudaliarIOB.
    public let mudaliarIob: Float
    /// Units; ControlIQIOBResponse.swan6hrIOB.
    public let swan6hrIob: Float
    /// Units; a third IOB-like value of unidentified model, usually below swan6hrIob.
    public let unknownFloatAt22: Float

    public required init(cargo: Data) {
        bolusId = Bytes.readShort(cargo, 10)
        unknownU8At12 = Int(cargo[12])
        selectedIob = Int(cargo[13])
        mudaliarIob = Bytes.readFloat(cargo, 14)
        swan6hrIob = Bytes.readFloat(cargo, 18)
        unknownFloatAt22 = Bytes.readFloat(cargo, 22)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        bolusId: Int,
        unknownU8At12: Int,
        selectedIob: Int,
        mudaliarIob: Float,
        swan6hrIob: Float,
        unknownFloatAt22: Float
    ) {
        let payload = IobSnapshotPreBolusHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            bolusId: bolusId,
            unknownU8At12: unknownU8At12,
            selectedIob: selectedIob,
            mudaliarIob: mudaliarIob,
            swan6hrIob: swan6hrIob,
            unknownFloatAt22: unknownFloatAt22
        )
        self.bolusId = bolusId
        self.unknownU8At12 = unknownU8At12
        self.selectedIob = selectedIob
        self.mudaliarIob = mudaliarIob
        self.swan6hrIob = swan6hrIob
        self.unknownFloatAt22 = unknownFloatAt22
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        bolusId: Int,
        unknownU8At12: Int,
        selectedIob: Int,
        mudaliarIob: Float,
        swan6hrIob: Float,
        unknownFloatAt22: Float
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(bolusId),
                Data([UInt8(unknownU8At12 & 0xFF), UInt8(selectedIob & 0xFF)]),
                Bytes.toFloat(mudaliarIob),
                Bytes.toFloat(swan6hrIob),
                Bytes.toFloat(unknownFloatAt22)
            )
        )
    }

    public var selectedIobType: BolusRequestedMsg2HistoryLog.SelectedIOBType? {
        BolusRequestedMsg2HistoryLog.SelectedIOBType(rawValue: selectedIob)
    }

    public var description: String {
        "IobSnapshotPreBolusHistoryLog(cargo=\(cargo.hexadecimalString), bolusId=\(bolusId), unknownU8At12=\(unknownU8At12), selectedIob=\(selectedIob), mudaliarIob=\(mudaliarIob), swan6hrIob=\(swan6hrIob), unknownFloatAt22=\(unknownFloatAt22))"
    }
}
