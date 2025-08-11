import Foundation

public enum MessageType: Sendable {
    case request
    case response
}

public protocol TandemMessage {
    static var opCode: UInt8 { get }
    static var messageType: MessageType { get }
    init()
    init(payload: [UInt8])
    var payload: [UInt8] { get }
}
