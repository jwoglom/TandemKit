import Foundation

/// Request additional battery information available on newer API versions.
public class CurrentBatteryV2Request: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-112)),
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

/// Extended battery information including charging status.
public class CurrentBatteryV2Response: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-111)),
        size: 11,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .apiV2_5
    )

    public var cargo: Data
    public var currentBatteryAbc: Int
    public var currentBatteryIbc: Int
    public var chargingStatus: Int
    public var unknown1: Int
    public var unknown2: Int
    public var unknown3: Int
    public var unknown4: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        currentBatteryAbc = Int(cargo[0])
        currentBatteryIbc = Int(cargo[1])
        chargingStatus = Int(cargo[2])
        unknown1 = Bytes.readShort(cargo, 3)
        unknown2 = Bytes.readShort(cargo, 5)
        unknown3 = Bytes.readShort(cargo, 7)
        unknown4 = Bytes.readShort(cargo, 9)
    }

    public init(
        currentBatteryAbc: Int,
        currentBatteryIbc: Int,
        chargingStatus: Int,
        unknown1: Int,
        unknown2: Int,
        unknown3: Int,
        unknown4: Int
    ) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(currentBatteryAbc),
            Bytes.firstByteLittleEndian(currentBatteryIbc),
            Bytes.firstByteLittleEndian(chargingStatus),
            Bytes.firstTwoBytesLittleEndian(unknown1),
            Bytes.firstTwoBytesLittleEndian(unknown2),
            Bytes.firstTwoBytesLittleEndian(unknown3),
            Bytes.firstTwoBytesLittleEndian(unknown4)
        )
        self.currentBatteryAbc = currentBatteryAbc
        self.currentBatteryIbc = currentBatteryIbc
        self.chargingStatus = chargingStatus
        self.unknown1 = unknown1
        self.unknown2 = unknown2
        self.unknown3 = unknown3
        self.unknown4 = unknown4
    }

    /// Convenience accessor mapping to battery percent used by the pump UI.
    public func getBatteryPercent() -> Int {
        currentBatteryIbc
    }

    /// Returns true if the pump is currently charging.
    public func isCharging() -> Bool {
        chargingStatus == 1
    }
}

extension CurrentBatteryV2Response: CurrentBatteryAbstractResponse {}
