//
//  BolexActivatedHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry when an extended bolus is activated.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/BolexActivatedHistoryLog.java
//
import Foundation

public class BolexActivatedHistoryLog: HistoryLog {
    public static let typeId = 59

    public let bolusId: Int
    /// Byte 12, as in BolusActivated; equals the paired Msg2 selectedIOB in 9/9 captured records
    /// (pumpX2 #46).
    public let selectedIob: Int
    public let iob: Float
    public let bolexSize: Float

    public required init(cargo: Data) {
        bolusId = Bytes.readShort(cargo, 10)
        selectedIob = Int(cargo[12])
        iob = Bytes.readFloat(cargo, 14)
        bolexSize = Bytes.readFloat(cargo, 18)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, bolusId: Int, selectedIob: Int = 0, iob: Float, bolexSize: Float) {
        let payload = BolexActivatedHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            bolusId: bolusId,
            selectedIob: selectedIob,
            iob: iob,
            bolexSize: bolexSize
        )
        self.bolusId = bolusId
        self.selectedIob = selectedIob
        self.iob = iob
        self.bolexSize = bolexSize
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, bolusId: Int, selectedIob: Int = 0, iob: Float, bolexSize: Float) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(bolusId),
                Data([UInt8(selectedIob & 0xFF), 0]),
                Bytes.toFloat(iob),
                Bytes.toFloat(bolexSize)
            )
        )
    }

    public var selectedIobType: BolusRequestedMsg2HistoryLog.SelectedIOBType? {
        BolusRequestedMsg2HistoryLog.SelectedIOBType(rawValue: selectedIob)
    }

    public var description: String {
        "BolexActivatedHistoryLog(cargo=\(cargo.hexadecimalString), bolusId=\(bolusId), selectedIob=\(selectedIob), selectedIobType=\(String(describing: selectedIobType)), iob=\(iob), bolexSize=\(bolexSize))"
    }
}
