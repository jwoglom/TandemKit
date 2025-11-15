import Foundation

/// Pump error message that accompanies rejected requests.
public final class ErrorResponse: Message {
    public static let props = MessageProps(
        opCode: 77,
        size: 2,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        variableSize: true,
        signed: true
    )

    public var cargo: Data
    public let requestCodeId: Int
    public let errorCodeId: Int
    public let remainingBytes: Data
    public let errorCode: PumpFaultCode

    public required init(cargo: Data) {
        self.cargo = cargo
        if cargo.count >= 1 {
            requestCodeId = Int(cargo[0])
        } else {
            requestCodeId = 0
        }
        if cargo.count >= 2 {
            errorCodeId = Int(cargo[1])
        } else {
            errorCodeId = 0
        }
        if cargo.count > 2 {
            remainingBytes = Data(cargo.dropFirst(2))
        } else {
            remainingBytes = Data()
        }
        errorCode = PumpFaultCode(rawValue: errorCodeId)
    }

    public init(requestCodeId: Int, errorCode: PumpFaultCode, remainingBytes: Data = Data()) {
        var payload = Data([UInt8(requestCodeId & 0xFF), UInt8(errorCode.rawValue & 0xFF)])
        if !remainingBytes.isEmpty {
            payload.append(contentsOf: remainingBytes)
        }
        cargo = payload
        self.requestCodeId = requestCodeId
        errorCodeId = errorCode.rawValue
        self.remainingBytes = remainingBytes
        self.errorCode = errorCode
    }

    public convenience init(requestCodeId: Int, errorCodeId: Int, remainingBytes: Data = Data()) {
        self.init(requestCodeId: requestCodeId, errorCode: PumpFaultCode(rawValue: errorCodeId), remainingBytes: remainingBytes)
    }

    /// Indicates whether Tandem appended a signature for signed characteristics.
    public var containsSignature: Bool { remainingBytes.count >= 24 }
}
