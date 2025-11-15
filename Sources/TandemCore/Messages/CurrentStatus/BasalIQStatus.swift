import Foundation

/// Request the current Basal-IQ status from the pump.
public class BasalIQStatusRequest: Message {
    public static let props = MessageProps(
        opCode: 112,
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

/// Response describing current Basal-IQ state.
public class BasalIQStatusResponse: Message {
    public static let props = MessageProps(
        opCode: 113,
        size: 2,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var basalIQStatusStateId: Int
    public var deliveringTherapy: Bool

    public required init(cargo: Data) {
        self.cargo = cargo
        basalIQStatusStateId = Int(cargo[0])
        deliveringTherapy = cargo[1] != 0
    }

    public init(basalIQStatusStateId: Int, deliveringTherapy: Bool) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(basalIQStatusStateId),
            Bytes.firstByteLittleEndian(deliveringTherapy ? 1 : 0)
        )
        self.basalIQStatusStateId = basalIQStatusStateId
        self.deliveringTherapy = deliveringTherapy
    }

    public var basalIQStatusState: BasalIQStatusState? {
        BasalIQStatusState.fromId(basalIQStatusStateId)
    }

    public enum BasalIQStatusState: Int {
        case idle = 0
        case suspend = 1
        case disabled = 2
        case unavailable = 3

        static func fromId(_ id: Int) -> BasalIQStatusState? {
            BasalIQStatusState(rawValue: id)
        }
    }
}
