//
//  ParamChangePumpSettingsHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  History log entry for pump settings parameter changes.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/ParamChangePumpSettingsHistoryLog.java
//
import Foundation

public class ParamChangePumpSettingsHistoryLog: HistoryLog {
    public static let typeId = 73

    public let modification: Int
    public let status: Int
    public let lowInsulinThreshold: Int
    public let cannulaPrimeSize: Int
    public let isFeatureLocked: Int
    public let autoShutdownEnabled: Int
    public let oledTimeout: Int
    public let autoShutdownDuration: Int

    public required init(cargo: Data) {
        modification = Int(cargo[10])
        status = Bytes.readShort(cargo, 12)
        lowInsulinThreshold = Int(cargo[14])
        cannulaPrimeSize = Int(cargo[15])
        isFeatureLocked = Int(cargo[16])
        autoShutdownEnabled = Int(cargo[17])
        oledTimeout = Int(cargo[19])
        autoShutdownDuration = Bytes.readShort(cargo, 20)
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        modification: Int,
        status: Int,
        lowInsulinThreshold: Int,
        cannulaPrimeSize: Int,
        isFeatureLocked: Int,
        autoShutdownEnabled: Int,
        oledTimeout: Int,
        autoShutdownDuration: Int
    ) {
        let payload = ParamChangePumpSettingsHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            modification: modification,
            status: status,
            lowInsulinThreshold: lowInsulinThreshold,
            cannulaPrimeSize: cannulaPrimeSize,
            isFeatureLocked: isFeatureLocked,
            autoShutdownEnabled: autoShutdownEnabled,
            oledTimeout: oledTimeout,
            autoShutdownDuration: autoShutdownDuration
        )
        self.modification = modification
        self.status = status
        self.lowInsulinThreshold = lowInsulinThreshold
        self.cannulaPrimeSize = cannulaPrimeSize
        self.isFeatureLocked = isFeatureLocked
        self.autoShutdownEnabled = autoShutdownEnabled
        self.oledTimeout = oledTimeout
        self.autoShutdownDuration = autoShutdownDuration
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        modification: Int,
        status: Int,
        lowInsulinThreshold: Int,
        cannulaPrimeSize: Int,
        isFeatureLocked: Int,
        autoShutdownEnabled: Int,
        oledTimeout: Int,
        autoShutdownDuration: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                Data([UInt8(typeId), 0]),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(truncatingIfNeeded: modification)]),
                Bytes.firstTwoBytesLittleEndian(status),
                Data([UInt8(truncatingIfNeeded: lowInsulinThreshold)]),
                Data([UInt8(truncatingIfNeeded: cannulaPrimeSize)]),
                Data([UInt8(truncatingIfNeeded: isFeatureLocked)]),
                Data([UInt8(truncatingIfNeeded: autoShutdownEnabled)]),
                Data([UInt8(truncatingIfNeeded: oledTimeout)]),
                Bytes.firstTwoBytesLittleEndian(autoShutdownDuration)
            )
        )
    }
}
