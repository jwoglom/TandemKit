import Foundation

/// Request a snapshot of bolus calculator data from the pump.
public class BolusCalcDataSnapshotRequest: Message {
    public static let props = MessageProps(
        opCode: 114,
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .apiV2_5
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }
}

/// Response containing bolus calculator snapshot data.
public class BolusCalcDataSnapshotResponse: Message {
    public static let props = MessageProps(
        opCode: 115,
        size: 46,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .apiV2_5
    )

    public var cargo: Data
    public var isUnacked: Bool
    public var correctionFactor: Int
    public var iob: UInt32
    public var cartridgeRemainingInsulin: Int
    public var targetBg: Int
    public var isf: Int
    public var carbEntryEnabled: Bool
    public var carbRatio: UInt32
    public var maxBolusAmount: Int
    public var maxBolusHourlyTotal: UInt32
    public var maxBolusEventsExceeded: Bool
    public var maxIobEventsExceeded: Bool
    public var unknown11bytes: Data
    public var isAutopopAllowed: Bool
    public var unknown8bytes: Data

    public required init(cargo: Data) {
        self.cargo = cargo
        isUnacked = cargo[0] != 0
        correctionFactor = Bytes.readShort(cargo, 1)
        iob = Bytes.readUint32(cargo, 3)
        cartridgeRemainingInsulin = Bytes.readShort(cargo, 7)
        targetBg = Bytes.readShort(cargo, 9)
        isf = Bytes.readShort(cargo, 11)
        carbEntryEnabled = cargo[13] != 0
        carbRatio = Bytes.readUint32(cargo, 14)
        maxBolusAmount = Bytes.readShort(cargo, 18)
        maxBolusHourlyTotal = Bytes.readUint32(cargo, 20)
        maxBolusEventsExceeded = cargo[24] != 0
        maxIobEventsExceeded = cargo[25] != 0
        unknown11bytes = cargo.subdata(in: 26 ..< 37)
        isAutopopAllowed = cargo[37] != 0
        unknown8bytes = cargo.subdata(in: 38 ..< 46)
    }

    public init(
        isUnacked: Bool,
        correctionFactor: Int,
        iob: UInt32,
        cartridgeRemainingInsulin: Int,
        targetBg: Int,
        isf: Int,
        carbEntryEnabled: Bool,
        carbRatio: UInt32,
        maxBolusAmount: Int,
        maxBolusHourlyTotal: UInt32,
        maxBolusEventsExceeded: Bool,
        maxIobEventsExceeded: Bool,
        isAutopopAllowed: Bool,
        unknown11bytes: Data = Bytes.emptyBytes(11),
        unknown8bytes: Data = Bytes.emptyBytes(8)
    ) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(isUnacked ? 1 : 0),
            Bytes.firstTwoBytesLittleEndian(correctionFactor),
            Bytes.toUint32(iob),
            Bytes.firstTwoBytesLittleEndian(cartridgeRemainingInsulin),
            Bytes.firstTwoBytesLittleEndian(targetBg),
            Bytes.firstTwoBytesLittleEndian(isf),
            Bytes.firstByteLittleEndian(carbEntryEnabled ? 1 : 0),
            Bytes.toUint32(carbRatio),
            Bytes.firstTwoBytesLittleEndian(maxBolusAmount),
            Bytes.toUint32(maxBolusHourlyTotal),
            Bytes.firstByteLittleEndian(maxBolusEventsExceeded ? 1 : 0),
            Bytes.firstByteLittleEndian(maxIobEventsExceeded ? 1 : 0),
            unknown11bytes,
            Bytes.firstByteLittleEndian(isAutopopAllowed ? 1 : 0),
            unknown8bytes
        )
        self.isUnacked = isUnacked
        self.correctionFactor = correctionFactor
        self.iob = iob
        self.cartridgeRemainingInsulin = cartridgeRemainingInsulin
        self.targetBg = targetBg
        self.isf = isf
        self.carbEntryEnabled = carbEntryEnabled
        self.carbRatio = carbRatio
        self.maxBolusAmount = maxBolusAmount
        self.maxBolusHourlyTotal = maxBolusHourlyTotal
        self.maxBolusEventsExceeded = maxBolusEventsExceeded
        self.maxIobEventsExceeded = maxIobEventsExceeded
        self.unknown11bytes = unknown11bytes
        self.isAutopopAllowed = isAutopopAllowed
        self.unknown8bytes = unknown8bytes
    }
}
