//
//  IdpBolusHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry for Personal Profile (IDP) Bolus Data Change.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/IdpBolusHistoryLog.java
//
import Foundation

public class IdpBolusHistoryLog: HistoryLog {
    public static let typeId = 70

    public let idp: Int
    public let modification: Int
    public let bolusStatus: Int
    public let insulinDuration: Int
    public let maxBolusSize: Int
    public let bolusEntryType: Int

    public required init(cargo: Data) {
        self.idp = Int(cargo[10])
        self.modification = Int(cargo[11])
        self.bolusStatus = Int(cargo[12])
        self.insulinDuration = Bytes.readShort(cargo, 14)
        self.maxBolusSize = Bytes.readShort(cargo, 16)
        self.bolusEntryType = Int(cargo[18])
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, idp: Int, modification: Int, bolusStatus: Int, insulinDuration: Int, maxBolusSize: Int, bolusEntryType: Int) {
        let payload = IdpBolusHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, idp: idp, modification: modification, bolusStatus: bolusStatus, insulinDuration: insulinDuration, maxBolusSize: maxBolusSize, bolusEntryType: bolusEntryType)
        self.idp = idp
        self.modification = modification
        self.bolusStatus = bolusStatus
        self.insulinDuration = insulinDuration
        self.maxBolusSize = maxBolusSize
        self.bolusEntryType = bolusEntryType
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, idp: Int, modification: Int, bolusStatus: Int, insulinDuration: Int, maxBolusSize: Int, bolusEntryType: Int) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(truncatingIfNeeded: idp)]),
                Data([UInt8(truncatingIfNeeded: modification)]),
                Data([UInt8(truncatingIfNeeded: bolusStatus)]),
                Bytes.firstTwoBytesLittleEndian(insulinDuration),
                Bytes.firstTwoBytesLittleEndian(maxBolusSize),
                Data([UInt8(truncatingIfNeeded: bolusEntryType)])
            )
        )
    }
}

