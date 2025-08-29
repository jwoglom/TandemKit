#if canImport(HealthKit)
import Foundation
import TandemCore

public protocol PumpMessageTransport {
    func sendMessage(_ message: Message) throws -> Message
}
#endif
