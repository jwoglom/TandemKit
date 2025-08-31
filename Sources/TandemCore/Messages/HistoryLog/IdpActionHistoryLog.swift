//
//  IdpActionHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry for Personal Profile (IDP) Action 1/2.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/IdpActionHistoryLog.java
//
import Foundation

public class IdpActionHistoryLog: HistoryLog {
    public static let typeId = 69

    public let idp: Int
    public let status: Int
    public let sourceIdp: Int
    public let name: String

    public required init(cargo: Data) {
        self.idp = Int(cargo[10])
        self.status = Int(cargo[11])
        self.sourceIdp = Int(cargo[12])
        self.name = Bytes.readString(cargo, 18, 8)
        super.init(cargo: cargo)
    }

    public init(pumpTimeSec: UInt32, sequenceNum: UInt32, idp: Int, status: Int, sourceIdp: Int, name: String) {
        let payload = IdpActionHistoryLog.buildCargo(pumpTimeSec: pumpTimeSec, sequenceNum: sequenceNum, idp: idp, status: status, sourceIdp: sourceIdp, name: name)
        self.idp = idp
        self.status = status
        self.sourceIdp = sourceIdp
        self.name = name
        super.init(cargo: payload)
    }

    public static func buildCargo(pumpTimeSec: UInt32, sequenceNum: UInt32, idp: Int, status: Int, sourceIdp: Int, name: String) -> Data {
        return HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(truncatingIfNeeded: idp)]),
                Data([UInt8(truncatingIfNeeded: status)]),
                Data([UInt8(truncatingIfNeeded: sourceIdp)]),
                Bytes.writeString(name, 8)
            )
        )
    }
}

