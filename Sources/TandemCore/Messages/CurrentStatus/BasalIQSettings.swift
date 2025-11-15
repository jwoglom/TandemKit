import Foundation

/// Request Basal-IQ configuration settings from the pump.
public class BasalIQSettingsRequest: Message {
    public static let props = MessageProps(
        opCode: 98,
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

/// Response describing Basal-IQ configuration settings.
public class BasalIQSettingsResponse: Message {
    public static let props = MessageProps(
        opCode: 99,
        size: 3,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var hypoMinimization: Int
    public var suspendAlert: Int
    public var resumeAlert: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        hypoMinimization = Int(cargo[0])
        suspendAlert = Int(cargo[1])
        resumeAlert = Int(cargo[2])
    }

    public init(hypoMinimization: Int, suspendAlert: Int, resumeAlert: Int) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(hypoMinimization),
            Bytes.firstByteLittleEndian(suspendAlert),
            Bytes.firstByteLittleEndian(resumeAlert)
        )
        self.hypoMinimization = hypoMinimization
        self.suspendAlert = suspendAlert
        self.resumeAlert = resumeAlert
    }
}
