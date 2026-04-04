import Foundation

/// Request CGM support package validity status.
public class CGMSupportPackageStatusRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-56)),
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .apiFuture
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "CGMSupportPackageStatusRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response indicating whether the CGM support package is valid.
///
/// Binary layout (2 bytes):
///   byte 0: status   - 0 = ACK/success, 1 = NACK/failure
///   byte 1: validity - nonzero = true, CGM support package is valid
public class CGMSupportPackageStatusResponse: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-55)),
        size: 2,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        minApi: .apiFuture
    )

    public var cargo: Data
    public var status: Int
    public var validity: Bool

    public required init(cargo: Data) {
        self.cargo = cargo
        status = Int(cargo[0])
        validity = cargo[1] != 0
    }

    public init(status: Int, validity: Bool) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(status),
            Data([validity ? 1 : 0])
        )
        self.status = status
        self.validity = validity
    }

    /// True if the status byte is ACK (success).
    public var isSuccess: Bool {
        status == 0
    }

    public var description: String {
        "CGMSupportPackageStatusResponse(cargo=\(cargo.hexadecimalString), status=\(status), validity=\(validity))"
    }
}
