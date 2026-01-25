import Foundation
import TandemCore

/// Represents a paired request-response exchange with the pump
public struct RequestResponsePair {
    public let request: Message
    public let requestMetadata: MessageMetadata
    public let response: Message?
    public let responseMetadata: MessageMetadata?
    public let txId: UInt8
    public let timestamp: Date
    public let characteristic: CharacteristicUUID

    public init(
        request: Message,
        requestMetadata: MessageMetadata,
        response: Message? = nil,
        responseMetadata: MessageMetadata? = nil,
        txId: UInt8,
        timestamp: Date = Date(),
        characteristic: CharacteristicUUID
    ) {
        self.request = request
        self.requestMetadata = requestMetadata
        self.response = response
        self.responseMetadata = responseMetadata
        self.txId = txId
        self.timestamp = timestamp
        self.characteristic = characteristic
    }

    /// Create a pair with a response added
    public func withResponse(_ response: Message) -> RequestResponsePair {
        let responseMeta = MessageRegistry.metadata(for: response)
        return RequestResponsePair(
            request: request,
            requestMetadata: requestMetadata,
            response: response,
            responseMetadata: responseMeta,
            txId: txId,
            timestamp: timestamp,
            characteristic: characteristic
        )
    }

    /// Check if this pair has a response
    public var hasResponse: Bool {
        response != nil
    }

    /// Get a description of this pair for logging
    public var description: String {
        let respDesc = response != nil ? String(describing: type(of: response!)) : "no response"
        return "[\(timestamp)] TxId:\(txId) \(requestMetadata.name) -> \(respDesc)"
    }
}
