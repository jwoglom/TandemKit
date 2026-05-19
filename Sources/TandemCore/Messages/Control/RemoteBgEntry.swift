import Foundation

/// The type of blood glucose reading: manually entered or auto-populated from CGM.
/// Maps to byte[3] of RemoteBgEntryRequest cargo.
public enum BloodGlucoseReadingType: UInt8 {
    case manual = 0
    case auto = 1
    case unknown = 2

    public init(fromId id: UInt8) {
        self = BloodGlucoseReadingType(rawValue: id) ?? .unknown
    }
}

/// The source of a blood glucose reading: entered on the pump or remotely via BLE.
/// Maps to byte[4] of RemoteBgEntryRequest cargo.
public enum BloodGlucoseReadingSource: UInt8 {
    case pump = 0
    case remote = 1
    case unknown = 2

    public init(fromId id: UInt8) {
        self = BloodGlucoseReadingSource(rawValue: id) ?? .unknown
    }
}

/// Request to add a blood glucose entry on the pump during bolusing.
public class RemoteBgEntryRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-74)),
        size: 11,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .apiV2_5
    )

    public var cargo: Data
    public var bg: Int
    public var useForCgmCalibration: Bool
    public var entryType: BloodGlucoseReadingType
    public var source: BloodGlucoseReadingSource
    public var pumpTime: UInt32
    public var bolusId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        bg = Bytes.readShort(cargo, 0)
        useForCgmCalibration = cargo[2] == 1
        entryType = BloodGlucoseReadingType(fromId: cargo[3])
        source = BloodGlucoseReadingSource(fromId: cargo[4])
        pumpTime = Bytes.readUint32(cargo, 5)
        bolusId = Bytes.readShort(cargo, 9)
    }

    public init(
        bg: Int,
        useForCgmCalibration: Bool,
        entryType: BloodGlucoseReadingType,
        source: BloodGlucoseReadingSource,
        pumpTime: UInt32,
        bolusId: Int
    ) {
        cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(bg),
            Data([useForCgmCalibration ? 1 : 0]),
            Data([entryType.rawValue]),
            Data([source.rawValue]),
            Bytes.toUint32(pumpTime),
            Bytes.firstTwoBytesLittleEndian(bolusId)
        )
        self.bg = bg
        self.useForCgmCalibration = useForCgmCalibration
        self.entryType = entryType
        self.source = source
        self.pumpTime = pumpTime
        self.bolusId = bolusId
    }

    /// Deprecated: Use init(bg:useForCgmCalibration:entryType:source:pumpTime:bolusId:) instead.
    /// This initializer hardcodes entryType to .manual and maps isAutopopBg to source (true=.remote, false=.pump).
    public convenience init(bg: Int, useForCgmCalibration: Bool, isAutopopBg: Bool, pumpTime: UInt32, bolusId: Int) {
        self.init(
            bg: bg,
            useForCgmCalibration: useForCgmCalibration,
            entryType: .manual,
            source: isAutopopBg ? .remote : .pump,
            pumpTime: pumpTime,
            bolusId: bolusId
        )
    }

    /// Deprecated: Use source instead.
    public var isAutopopBg: Bool {
        source == .remote
    }

    public var description: String {
        "RemoteBgEntryRequest(cargo=\(cargo.hexadecimalString), bg=\(bg), useForCgmCalibration=\(useForCgmCalibration), entryType=\(entryType), source=\(source), pumpTime=\(pumpTime), bolusId=\(bolusId))"
    }
}

/// Response after adding a BG entry.
public class RemoteBgEntryResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-73)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true,
        minApi: .apiV2_5
    )

    public var cargo: Data
    public var status: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        status = Int(cargo[0])
    }

    public init(status: Int) {
        cargo = Data([UInt8(status & 0xFF)])
        self.status = status
    }

    public var description: String {
        "RemoteBgEntryResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}
