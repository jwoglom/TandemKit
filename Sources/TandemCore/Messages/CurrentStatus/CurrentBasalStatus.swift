import Foundation
import LoopKit

/// Request information about the current basal delivery rate.
public class CurrentBasalStatusRequest: Message {
    public static let props = MessageProps(
        opCode: 40,
        size: 0,
        type: .Request,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "CurrentBasalStatusRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response describing the basal profile rate and current delivery rate.
public class CurrentBasalStatusResponse: Message {
    public static let props = MessageProps(
        opCode: 41,
        size: 9,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var basalModifiedBitmask: Int
    private var rawProfileBasalRate: UInt32
    private var rawCurrentBasalRate: UInt32

    public var basalType: DoseType {
        switch basalModifiedBitmask {
        case 0x01:
            return .suspend
        case 0x02:
            return .tempBasal
        default:
            return .basal
        }
    }

    public var profileBasalRate: Double {
        Double(rawProfileBasalRate) / 1000.0
    }

    public var currentBasalRate: Double {
        Double(rawCurrentBasalRate) / 1000.0
    }

    public required init(cargo: Data) {
        self.cargo = cargo
        rawProfileBasalRate = Bytes.readUint32(cargo, 0)
        rawCurrentBasalRate = Bytes.readUint32(cargo, 4)
        basalModifiedBitmask = Int(cargo[8])
    }

    public init(profileBasalRate: UInt32, currentBasalRate: UInt32, basalModifiedBitmask: Int) {
        cargo = Bytes.combine(
            Bytes.toUint32(profileBasalRate),
            Bytes.toUint32(currentBasalRate),
            Bytes.firstByteLittleEndian(basalModifiedBitmask)
        )
        rawProfileBasalRate = profileBasalRate
        rawCurrentBasalRate = currentBasalRate
        self.basalModifiedBitmask = basalModifiedBitmask
    }

    public var description: String {
        "CurrentBasalStatusResponse(cargo=\(cargo.hexadecimalString), profileBasalRate=\(profileBasalRate), currentBasalRate=\(currentBasalRate), basalModifiedBitmask=\(basalModifiedBitmask))"
    }
}
