import Foundation

/// A message requesting the pump API version.
/// Mirrors pumpX2 `ApiVersionRequest` with opcode 0x20.
public struct ApiVersionRequest: TandemMessage {
    public static let opCode: UInt8 = 0x20
    public static let messageType: MessageType = .request

    public var payload: [UInt8]

    public init() {
        self.payload = []
    }

    public init(payload: [UInt8]) {
        self.payload = payload
    }
}
