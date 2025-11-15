import Foundation

/// Request CGM hardware information from the pump.
public class CGMHardwareInfoRequest: Message {
    public static let props = MessageProps(
        opCode: 96,
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

/// Response containing CGM hardware information (e.g. transmitter ID).
public class CGMHardwareInfoResponse: Message {
    public static let props = MessageProps(
        opCode: 97,
        size: 17,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var hardwareInfoString: String
    public var lastByte: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        hardwareInfoString = Bytes.readString(cargo, 0, 16)
        lastByte = Int(cargo[16])
    }

    public init(hardwareInfoString: String, lastByte: Int) {
        cargo = Bytes.combine(
            Bytes.writeString(hardwareInfoString, 16),
            Bytes.firstByteLittleEndian(lastByte)
        )
        self.hardwareInfoString = hardwareInfoString
        self.lastByte = lastByte
    }
}
