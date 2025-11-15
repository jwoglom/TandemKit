import Foundation

/// Request to set the maximum hourly basal rate.
public class SetMaxBasalLimitRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-120)),
        size: 4,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var maxHourlyBasalMilliunits: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        maxHourlyBasalMilliunits = Bytes.readShort(cargo, 0)
    }

    public init(maxHourlyBasalMilliunits: Int) {
        cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(maxHourlyBasalMilliunits),
            Data([0, 0])
        )
        self.maxHourlyBasalMilliunits = maxHourlyBasalMilliunits
    }
}

/// Response after setting the max basal limit.
public class SetMaxBasalLimitResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-119)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
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
}
