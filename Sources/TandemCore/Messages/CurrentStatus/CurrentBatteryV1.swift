import Foundation

/// Request the current battery information (legacy API).
public class CurrentBatteryV1Request: Message {
    public static let props = MessageProps(
        opCode: 52,
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

/// Response with basic battery info for older API versions.
public class CurrentBatteryV1Response: Message {
    public static let props = MessageProps(
        opCode: 53,
        size: 2,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var currentBatteryAbc: Int
    public var currentBatteryIbc: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        currentBatteryAbc = Int(cargo[0])
        currentBatteryIbc = Int(cargo[1])
    }

    public init(currentBatteryAbc: Int, currentBatteryIbc: Int) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(currentBatteryAbc),
            Bytes.firstByteLittleEndian(currentBatteryIbc)
        )
        self.currentBatteryAbc = currentBatteryAbc
        self.currentBatteryIbc = currentBatteryIbc
    }

    /// Convenience accessor mapping to battery percent used by the pump UI.
    public func getBatteryPercent() -> Int {
        currentBatteryIbc
    }
}

extension CurrentBatteryV1Response: CurrentBatteryAbstractResponse {}
