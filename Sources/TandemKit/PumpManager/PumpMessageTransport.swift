import Foundation

public protocol PumpMessageTransport {
    func sendMessage(_ message: Message) throws -> Message
}
