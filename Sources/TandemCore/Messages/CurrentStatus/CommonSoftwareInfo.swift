import Foundation

/// Request common software information from the pump.
public class CommonSoftwareInfoRequest: PumpRequest {
    public typealias Response = CommonSoftwareInfoResponse

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-114)),
        size: 0,
        type: .Request,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
        variableSize: true,
        minApi: .apiFuture
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public init(mcuType: MCUType) {
        cargo = Data([UInt8(mcuType.rawValue)])
    }

    public var mcuType: MCUType? {
        cargo.isEmpty ? nil : MCUType(rawValue: Int(cargo[cargo.startIndex]))
    }

    public enum MCUType: Int {
        case arm = 0
        case ble = 1
        case msp = 2
        case unknown = 3
    }

    public var description: String {
        "CommonSoftwareInfoRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response describing pump software and bootloader versions.
///
/// The Mobi sends 51 bytes: the requested MCU type echoed at byte 0, then the app version (1-17), part
/// number (18) and part revision (22), and the bootloader version (26-42), part number (43) and part
/// revision (47), as Tandem's Mobi app reads it. The t:slim X2 app reads a 60-byte layout with no MCU
/// byte and a dash number after each part number; no X2 response has been captured. pumpX2#152.
public class CommonSoftwareInfoResponse: Message {
    static let mobiSize = 51

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-113)),
        size: 60,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
        variableSize: true,
        minApi: .apiFuture
    )

    public var cargo: Data
    /// Echoed from the request; nil for the t:slim X2 layout.
    public var mcuTypeId: Int?
    public var appSoftwareVersion: String
    public var appSoftwarePartNumber: UInt32
    public var appSoftwarePartDashNumber: UInt32
    public var appSoftwarePartRevisionNumber: UInt32
    public var bootloaderVersion: String
    public var bootloaderPartNumber: UInt32
    public var bootloaderPartDashNumber: UInt32?
    public var bootloaderPartRevisionNumber: UInt32?

    public required init(cargo: Data) {
        self.cargo = cargo
        if cargo.count == Self.mobiSize {
            mcuTypeId = Int(cargo[cargo.startIndex])
            appSoftwareVersion = Bytes.readString(cargo, 1, 17)
            appSoftwarePartNumber = Bytes.readUint32(cargo, 18)
            appSoftwarePartDashNumber = 0
            appSoftwarePartRevisionNumber = Bytes.readUint32(cargo, 22)
            bootloaderVersion = Bytes.readString(cargo, 26, 17)
            bootloaderPartNumber = Bytes.readUint32(cargo, 43)
            bootloaderPartDashNumber = nil
            bootloaderPartRevisionNumber = Bytes.readUint32(cargo, 47)
            return
        }
        mcuTypeId = nil
        appSoftwareVersion = Bytes.readString(cargo, 0, 18)
        appSoftwarePartNumber = Bytes.readUint32(cargo, 18)
        appSoftwarePartDashNumber = Bytes.readUint32(cargo, 22)
        appSoftwarePartRevisionNumber = Bytes.readUint32(cargo, 26)
        bootloaderVersion = Bytes.readString(cargo, 30, 17)
        bootloaderPartNumber = Bytes.readUint32(cargo, 47)
        // The t:slim X2 app reads through byte 58; init(appSoftwareVersion:...) writes 59 bytes.
        if cargo.count >= 59 {
            bootloaderPartDashNumber = Bytes.readUint32(cargo, 51)
            bootloaderPartRevisionNumber = Bytes.readUint32(cargo, 55)
        } else {
            bootloaderPartDashNumber = nil
            bootloaderPartRevisionNumber = nil
        }
    }

    public convenience init(
        mcuTypeId: Int,
        appSoftwareVersion: String,
        appSoftwarePartNumber: UInt32,
        appSoftwarePartRevisionNumber: UInt32,
        bootloaderVersion: String,
        bootloaderPartNumber: UInt32,
        bootloaderPartRevisionNumber: UInt32
    ) {
        self.init(cargo: Bytes.combine(
            Data([UInt8(mcuTypeId & 0xFF)]),
            Bytes.writeString(appSoftwareVersion, 17),
            Bytes.toUint32(appSoftwarePartNumber),
            Bytes.toUint32(appSoftwarePartRevisionNumber),
            Bytes.writeString(bootloaderVersion, 17),
            Bytes.toUint32(bootloaderPartNumber),
            Bytes.toUint32(bootloaderPartRevisionNumber)
        ))
    }

    /// The t:slim X2 layout. Without both bootloader numbers the cargo is 51 bytes, which
    /// `init(cargo:)` reads as the Mobi layout.
    public init(
        appSoftwareVersion: String,
        appSoftwarePartNumber: UInt32,
        appSoftwarePartDashNumber: UInt32,
        appSoftwarePartRevisionNumber: UInt32,
        bootloaderVersion: String,
        bootloaderPartNumber: UInt32,
        bootloaderPartDashNumber: UInt32? = nil,
        bootloaderPartRevisionNumber: UInt32? = nil
    ) {
        var data = Bytes.combine(
            Bytes.writeString(appSoftwareVersion, 18),
            Bytes.toUint32(appSoftwarePartNumber),
            Bytes.toUint32(appSoftwarePartDashNumber),
            Bytes.toUint32(appSoftwarePartRevisionNumber),
            Bytes.writeString(bootloaderVersion, 17),
            Bytes.toUint32(bootloaderPartNumber)
        )
        if let dash = bootloaderPartDashNumber, let rev = bootloaderPartRevisionNumber {
            data = Bytes.combine(
                data,
                Bytes.toUint32(dash),
                Bytes.toUint32(rev)
            )
        }
        cargo = data
        mcuTypeId = nil
        self.appSoftwareVersion = appSoftwareVersion
        self.appSoftwarePartNumber = appSoftwarePartNumber
        self.appSoftwarePartDashNumber = appSoftwarePartDashNumber
        self.appSoftwarePartRevisionNumber = appSoftwarePartRevisionNumber
        self.bootloaderVersion = bootloaderVersion
        self.bootloaderPartNumber = bootloaderPartNumber
        self.bootloaderPartDashNumber = bootloaderPartDashNumber
        self.bootloaderPartRevisionNumber = bootloaderPartRevisionNumber
    }

    public var mcuType: CommonSoftwareInfoRequest.MCUType? {
        mcuTypeId.flatMap { CommonSoftwareInfoRequest.MCUType(rawValue: $0) }
    }

    public var description: String {
        "CommonSoftwareInfoResponse(cargo=\(cargo.hexadecimalString), mcuTypeId=\(String(describing: mcuTypeId)), appSoftwareVersion=\(appSoftwareVersion), appSoftwarePartNumber=\(appSoftwarePartNumber), appSoftwarePartDashNumber=\(appSoftwarePartDashNumber), appSoftwarePartRevisionNumber=\(appSoftwarePartRevisionNumber), bootloaderVersion=\(bootloaderVersion), bootloaderPartNumber=\(bootloaderPartNumber), bootloaderPartDashNumber=\(String(describing: bootloaderPartDashNumber)), bootloaderPartRevisionNumber=\(String(describing: bootloaderPartRevisionNumber)))"
    }
}
