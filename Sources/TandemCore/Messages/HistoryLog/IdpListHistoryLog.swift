//
//  IdpListHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry for Personal Profile (IDP) List.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/IdpListHistoryLog.java
//
import Foundation

public class IdpListHistoryLog: HistoryLog {
    public static let typeId = 71

    public let numProfiles: Int
    public let slot1: Int
    public let slot2: Int
    public let slot3: Int
    public let slot4: Int
    public let slot5: Int
    public let slot6: Int

    public required init(cargo: Data) {
        numProfiles = Int(cargo[10])
        slot1 = Int(cargo[14])
        slot2 = Int(cargo[15])
        slot3 = Int(cargo[16])
        slot4 = Int(cargo[17])
        slot5 = Int(cargo[18])
        slot6 = Int(cargo[19])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        numProfiles: Int,
        slot1: Int,
        slot2: Int,
        slot3: Int,
        slot4: Int,
        slot5: Int,
        slot6: Int
    ) {
        let payload = IdpListHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            numProfiles: numProfiles,
            slot1: slot1,
            slot2: slot2,
            slot3: slot3,
            slot4: slot4,
            slot5: slot5,
            slot6: slot6
        )
        self.numProfiles = numProfiles
        self.slot1 = slot1
        self.slot2 = slot2
        self.slot3 = slot3
        self.slot4 = slot4
        self.slot5 = slot5
        self.slot6 = slot6
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        numProfiles: Int,
        slot1: Int,
        slot2: Int,
        slot3: Int,
        slot4: Int,
        slot5: Int,
        slot6: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(truncatingIfNeeded: numProfiles)]),
                Data([UInt8(truncatingIfNeeded: slot1)]),
                Data([UInt8(truncatingIfNeeded: slot2)]),
                Data([UInt8(truncatingIfNeeded: slot3)]),
                Data([UInt8(truncatingIfNeeded: slot4)]),
                Data([UInt8(truncatingIfNeeded: slot5)]),
                Data([UInt8(truncatingIfNeeded: slot6)])
            )
        )
    }
}
