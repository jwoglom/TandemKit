import Foundation

/// Request stream data readiness status.
public class StreamDataReadinessRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-58)),
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

    public var description: String {
        "StreamDataReadinessRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response with stream data readiness status.
///
/// Binary layout (2 bytes):
///   byte 0: freestyleLibre2ReadinessId - readiness status for FSL2 sensor context transfer
///   byte 1: streamDataTypeOrdinal - type of stream data (0 = FSL2 sensor context)
public class StreamDataReadinessResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-57)),
        size: 2,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var freestyleLibre2ReadinessId: Int
    public var streamDataTypeOrdinal: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        freestyleLibre2ReadinessId = Int(cargo[0])
        streamDataTypeOrdinal = Int(cargo[1])
    }

    public init(freestyleLibre2ReadinessId: Int, streamDataTypeOrdinal: Int) {
        cargo = Data([
            UInt8(truncatingIfNeeded: freestyleLibre2ReadinessId),
            UInt8(truncatingIfNeeded: streamDataTypeOrdinal)
        ])
        self.freestyleLibre2ReadinessId = freestyleLibre2ReadinessId
        self.streamDataTypeOrdinal = streamDataTypeOrdinal
    }

    public var freestyleLibre2Readiness: FreestyleLibre2Readiness {
        FreestyleLibre2Readiness.fromId(freestyleLibre2ReadinessId)
    }

    public var streamDataType: StreamDataType {
        StreamDataType(rawValue: streamDataTypeOrdinal) ?? .unknown
    }

    /// Readiness status for a FreeStyle Libre 2 sensor context transfer.
    /// The numeric IDs are sparse/non-sequential as used by the pump firmware.
    public enum FreestyleLibre2Readiness: Int {
        case pumpReadyForFsl2ContextTransfer = 0
        case notReadyAnotherCgmSessionIsAlreadyActive = 2
        case notReadyPumpTimeIsInvalid = 5
        case notReadyPumpWorkflowDoesNotAllowFsl2Start = 6
        case freestyleLibre2CgmIsUnavailable = 8
        case notReadyPumpUnableToFulfillRequest = 11
        case unknown = -1

        public static func fromId(_ id: Int) -> FreestyleLibre2Readiness {
            FreestyleLibre2Readiness(rawValue: id) ?? .unknown
        }
    }

    /// Type of streaming data being queried for readiness.
    public enum StreamDataType: Int {
        case freestyleLibre2SensorContext = 0
        case unknown = 1
    }

    public var description: String {
        "StreamDataReadinessResponse(cargo=\(cargo.hexadecimalString), freestyleLibre2ReadinessId=\(freestyleLibre2ReadinessId), freestyleLibre2Readiness=\(freestyleLibre2Readiness), streamDataTypeOrdinal=\(streamDataTypeOrdinal), streamDataType=\(streamDataType))"
    }
}
