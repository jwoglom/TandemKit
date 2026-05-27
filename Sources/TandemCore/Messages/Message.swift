import CoreBluetooth
import Foundation

public protocol Message: CustomStringConvertible {
    static var props: MessageProps { get }

    var cargo: Data { get }
    init(cargo: Data)
}

public extension Message {
    var description: String {
        "Message(cargo=\(cargo.hexadecimalString))"
    }
}

public enum MessageType: Sendable {
    case Request
    case Response
}

public struct MessageProps {
    public let opCode: UInt8
    public let size: UInt8
    public let type: MessageType
    public let characteristic: CBUUID
    public let variableSize: Bool
    public let stream: Bool
    public let signed: Bool
    public let minApi: KnownApiVersion
    public let supportedDevices: SupportedDevices
    public let modifiesInsulinDelivery: Bool

    public init(
        opCode: UInt8,
        size: UInt8,
        type: MessageType,
        characteristic: CBUUID,
        variableSize: Bool = false,
        stream: Bool = false,
        signed: Bool = false,
        modifiesInsulinDelivery: Bool = false,
        minApi: KnownApiVersion = .apiV2_1,
        supportedDevices: SupportedDevices = .all
    ) {
        self.opCode = opCode
        self.size = size
        self.type = type
        self.characteristic = characteristic
        self.variableSize = variableSize
        self.stream = stream
        self.signed = signed
        self.modifiesInsulinDelivery = modifiesInsulinDelivery
        self.minApi = minApi
        self.supportedDevices = supportedDevices
    }
}
