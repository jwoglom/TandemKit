//
//  BasalDeliveryHistoryLog.swift
//  TandemKit
//
//  Created by OpenAI's ChatGPT.
//
//  Swift representation of PumpX2's BasalDeliveryHistoryLog.
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/historyLog/BasalDeliveryHistoryLog.java
//
import Foundation

/// History log entry detailing basal rate delivery.
public class BasalDeliveryHistoryLog: HistoryLog {
    public static let typeId = 279

    public let commandedRateSource: Int

    /// Raw value of bytes 12-13 (see pumpX2 issue #77).
    ///
    /// Only the values 0 and 3 have been observed (~49k records across two captures). The field is
    /// 3 when any of the rate fields changed versus the previous record, or when a
    /// TempRateActivated / TempRateCompleted / PumpingSuspended / PumpingResumed event fell in the
    /// 5-minute interval, and in nearly every record written while suspended. It is 0 for
    /// steady-state delivery. It is not a temp-rate indicator: it reads 0 in most records written
    /// with a temp rate active. The individual bit meanings are unknown and the field is unnamed in
    /// Tandem's export, so it is exposed as a raw integer.
    public let basalDeliveryFlags: Int

    public let commandedRate: Int
    public let profileBasalRate: Int
    public let algorithmRate: Int
    public let tempRate: Int

    public required init(cargo: Data) {
        let raw = HistoryLog.fillCargo(cargo)
        commandedRateSource = Bytes.readShort(raw, 10)
        basalDeliveryFlags = Bytes.readShort(raw, 12)
        commandedRate = Bytes.readShort(raw, 14)
        profileBasalRate = Bytes.readShort(raw, 16)
        algorithmRate = Bytes.readShort(raw, 18)
        tempRate = Bytes.readShort(raw, 20)
        super.init(cargo: raw)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        commandedRateSource: Int,
        basalDeliveryFlags: Int = 0,
        commandedRate: Int,
        profileBasalRate: Int,
        algorithmRate: Int,
        tempRate: Int
    ) {
        let payload = BasalDeliveryHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            commandedRateSource: commandedRateSource,
            basalDeliveryFlags: basalDeliveryFlags,
            commandedRate: commandedRate,
            profileBasalRate: profileBasalRate,
            algorithmRate: algorithmRate,
            tempRate: tempRate
        )
        self.commandedRateSource = commandedRateSource
        self.basalDeliveryFlags = basalDeliveryFlags
        self.commandedRate = commandedRate
        self.profileBasalRate = profileBasalRate
        self.algorithmRate = algorithmRate
        self.tempRate = tempRate
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        commandedRateSource: Int,
        basalDeliveryFlags: Int = 0,
        commandedRate: Int,
        profileBasalRate: Int,
        algorithmRate: Int,
        tempRate: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Bytes.firstTwoBytesLittleEndian(commandedRateSource),
                Bytes.firstTwoBytesLittleEndian(basalDeliveryFlags),
                Bytes.firstTwoBytesLittleEndian(commandedRate),
                Bytes.firstTwoBytesLittleEndian(profileBasalRate),
                Bytes.firstTwoBytesLittleEndian(algorithmRate),
                Bytes.firstTwoBytesLittleEndian(tempRate)
            )
        )
    }

    /// Source of the commanded basal rate, following Tandem's export map.
    ///
    /// Values 0, 1 and 2 are confirmed on the wire in a Mobi capture with Control-IQ off:
    /// 2 in 768/768 records where `commandedRate == tempRate`, 0 in 20/20 records written while
    /// suspended, and 1 in 10/10 records where `commandedRate == profileBasalRate`. Value 3 was
    /// seen in an earlier Control-IQ capture. Value 4 comes from Tandem's export map and has not
    /// yet been observed.
    public enum CommandedRateSource: Int {
        case suspended = 0
        case profile = 1
        case tempRate = 2
        case algorithm = 3
        case tempRateAndAlgorithm = 4
    }

    /// Typed view of `commandedRateSource`, or `nil` for an unrecognised value.
    public var commandedRateSourceEnum: CommandedRateSource? { CommandedRateSource(rawValue: commandedRateSource) }

    override public var description: String {
        "BasalDeliveryHistoryLog(cargo=\(cargo.hexadecimalString), commandedRateSource=\(commandedRateSource), commandedRateSourceEnum=\(String(describing: commandedRateSourceEnum)), basalDeliveryFlags=\(basalDeliveryFlags), commandedRate=\(commandedRate), profileBasalRate=\(profileBasalRate), algorithmRate=\(algorithmRate), tempRate=\(tempRate))"
    }
}
