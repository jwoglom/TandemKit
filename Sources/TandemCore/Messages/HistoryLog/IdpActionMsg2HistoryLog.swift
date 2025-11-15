//
//  IdpActionMsg2HistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry for Personal Profile (IDP) Action 2/2.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/IdpActionMsg2HistoryLog.java
//
import Foundation

public class IdpActionMsg2HistoryLog: HistoryLog {
    public static let typeId = 57

    public let idp: Int
    public let name: String

    public required init(cargo: Data) {
        idp = Int(cargo[10])
        name = Bytes.readString(cargo, 18, 8)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, idp: Int, name: String) {
        let payload = IdpActionMsg2HistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, idp: idp, name: name)
        self.idp = idp
        self.name = name
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, idp: Int, name: String) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(truncatingIfNeeded: idp)]),
                Bytes.writeString(name, 8)
            )
        )
    }
}
