import Foundation

/// Request to start a Dexcom G6 sensor session.
public class StartDexcomG6SensorSessionRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-78)),
        size: 2,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var sensorCode: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        sensorCode = Bytes.readShort(cargo, 0)
    }

    public init(sensorCode: Int = 0) {
        cargo = Bytes.firstTwoBytesLittleEndian(sensorCode)
        self.sensorCode = sensorCode
    }
}

/// Response after starting a Dexcom G6 sensor session.
public class StartDexcomG6SensorSessionResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-77)),
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
