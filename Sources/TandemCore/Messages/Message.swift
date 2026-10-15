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

/// A request the driver can send to the pump, carrying the type of the reply it will get back.
///
/// The stream placeholders (`Nonexistent*StreamRequest`) deliberately do not conform: they stand in
/// for unsolicited notifications and are never sent.
public protocol PumpRequest: Message {
    associatedtype Response: Message
}

public extension PumpRequest {
    /// `Response` reachable through `any PumpRequest.Type`, so the pairing can be validated
    /// against the message catalog without naming each request.
    static var responseType: any Message.Type { Response.self }
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
    /// Never written to the pump: `TandemPeripheralManager` refuses it.
    public let dangerousDoNotInvoke: Bool
    /// Left out of Debug Options, which has no confirmation strong enough for it.
    public let dangerousRequireExplicitConfirmation: Bool

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
        supportedDevices: SupportedDevices = .all,
        dangerousDoNotInvoke: Bool = false,
        dangerousRequireExplicitConfirmation: Bool = false
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
        self.dangerousDoNotInvoke = dangerousDoNotInvoke
        self.dangerousRequireExplicitConfirmation = dangerousRequireExplicitConfirmation
    }
}
