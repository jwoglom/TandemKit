import Foundation

/// Request the current amount of insulin remaining in the pump.
public class InsulinStatusRequest: Message {
    public static let props = MessageProps(
        opCode: 36,
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

/// Response describing remaining insulin in the reservoir.
public class InsulinStatusResponse: Message {
    public static let props = MessageProps(
        opCode: 37,
        size: 4,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var currentInsulinAmount: Int
    public var isEstimate: Int
    public var insulinLowAmount: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        currentInsulinAmount = Bytes.readShort(cargo, 0)
        isEstimate = Int(cargo[2])
        insulinLowAmount = Int(cargo[3])
    }

    public init(currentInsulinAmount: Int, isEstimate: Int, insulinLowAmount: Int) {
        cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(currentInsulinAmount),
            Bytes.firstByteLittleEndian(isEstimate),
            Bytes.firstByteLittleEndian(insulinLowAmount)
        )
        self.currentInsulinAmount = currentInsulinAmount
        self.isEstimate = isEstimate
        self.insulinLowAmount = insulinLowAmount
    }
}
