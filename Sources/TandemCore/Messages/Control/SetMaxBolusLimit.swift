import Foundation

/// Request to set the maximum bolus amount.
public class SetMaxBolusLimitRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-122)),
        size: 2,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var maxBolusMilliunits: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        maxBolusMilliunits = Bytes.readShort(cargo, 0)
    }

    public init(maxBolusMilliunits: Int) {
        cargo = Bytes.firstTwoBytesLittleEndian(maxBolusMilliunits)
        self.maxBolusMilliunits = maxBolusMilliunits
    }
}

/// Response after setting the max bolus limit.
public class SetMaxBolusLimitResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-121)),
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
