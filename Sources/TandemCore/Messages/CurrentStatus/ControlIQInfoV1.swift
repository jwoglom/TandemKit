import Foundation

/// Request Control-IQ V1 information.
public class ControlIQInfoV1Request: Message {
    public static let props = MessageProps(
        opCode: 104,
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }
}

/// Response with Control-IQ V1 information.
public class ControlIQInfoV1Response: ControlIQInfoAbstractResponse {
    override public class var props: MessageProps {
        MessageProps(
            opCode: 105,
            size: 10,
            type: .Response,
            characteristic: .CURRENT_STATUS_CHARACTERISTICS
        )
    }

    public var closedLoopEnabled: Bool
    public var weight: Int
    public var weightUnitRaw: Int
    public var totalDailyInsulin: Int
    public var currentUserModeTypeRaw: Int
    public var byte6: Int
    public var byte7: Int
    public var byte8: Int
    public var controlStateType: Int

    public required init(cargo: Data) {
        closedLoopEnabled = cargo[0] != 0
        weight = Bytes.readShort(cargo, 1)
        weightUnitRaw = Int(cargo[3])
        totalDailyInsulin = Int(cargo[4])
        currentUserModeTypeRaw = Int(cargo[5])
        byte6 = Int(cargo[6])
        byte7 = Int(cargo[7])
        byte8 = Int(cargo[8])
        controlStateType = Int(cargo[9])
        super.init(cargo: cargo)
    }

    public init(
        closedLoopEnabled: Bool,
        weight: Int,
        weightUnit: Int,
        totalDailyInsulin: Int,
        currentUserModeType: Int,
        byte6: Int,
        byte7: Int,
        byte8: Int,
        controlStateType: Int
    ) {
        let data = Bytes.combine(
            Bytes.firstByteLittleEndian(closedLoopEnabled ? 1 : 0),
            Bytes.firstTwoBytesLittleEndian(weight),
            Bytes.firstByteLittleEndian(weightUnit),
            Bytes.firstByteLittleEndian(totalDailyInsulin),
            Bytes.firstByteLittleEndian(currentUserModeType),
            Bytes.firstByteLittleEndian(byte6),
            Bytes.firstByteLittleEndian(byte7),
            Bytes.firstByteLittleEndian(byte8),
            Bytes.firstByteLittleEndian(controlStateType)
        )
        self.closedLoopEnabled = closedLoopEnabled
        self.weight = weight
        weightUnitRaw = weightUnit
        self.totalDailyInsulin = totalDailyInsulin
        currentUserModeTypeRaw = currentUserModeType
        self.byte6 = byte6
        self.byte7 = byte7
        self.byte8 = byte8
        self.controlStateType = controlStateType
        super.init(cargo: data)
    }

    override public func getClosedLoopEnabled() -> Bool { closedLoopEnabled }
    override public func getWeight() -> Int { weight }
    override public func getWeightUnitId() -> Int { weightUnitRaw }
    override public func getTotalDailyInsulin() -> Int { totalDailyInsulin }
    override public func getCurrentUserModeTypeId() -> Int { currentUserModeTypeRaw }
    override public func getByte6() -> Int { byte6 }
    override public func getByte7() -> Int { byte7 }
    override public func getByte8() -> Int { byte8 }
    override public func getControlStateType() -> Int { controlStateType }
}
