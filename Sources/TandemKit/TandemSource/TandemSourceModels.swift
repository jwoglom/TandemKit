import Foundation

/// The device-identity and feature block Tandem Source expects at `package.device` in an upload.
///
/// Every field maps to a `PumpVersionResponse` / `ApiVersionResponse` value the driver reads from the
/// pump; see `TandemSourceDeviceInfo.init(from:)`. The pump's own Mobi app sends `0`/`"0"` for the
/// fields it has no value for (`mspSwVer`, `pumpRev`, `pcbaRev`), so matching defaults are safe.
struct TandemSourceDeviceInfo: Equatable, Codable {
    var serialNum: UInt32
    var modelNum: UInt32
    var partNum: UInt32
    var armSwVer: UInt32
    var mspSwVer: UInt32
    var pcbaSN: UInt32
    var configABits: UInt32
    var configBBits: UInt32
    var pumpRev: String
    var pcbaRev: String
    var pumpAPIVersion: String
    /// What the pump supports, as the Mobi app reports it — not what is running.
    var dexcomG6: Bool
    var basalIQ: Bool
    var controlIQ: Bool
}

/// A Tandem Source upload request body. Serialized once; the serialized bytes are what the
/// `TDCToken` HMAC signs and what is POSTed, so the field set here is the signed set.
struct TandemSourceUploadBody: Encodable {
    let client = "mHealth"
    let package: Package

    /// An upload carries either history `events` or the base64 `settings` JSON, never both, as the
    /// app's does; the one left nil is omitted from the body.
    init(device: TandemSourceDeviceInfo, deviceAssignmentId: String, events: [String]? = nil, settings: String? = nil, now: Date, pumpClock: Date) {
        package = Package(device: Device(info: device, deviceAssignmentId: deviceAssignmentId, events: events, settings: settings, now: now, pumpClock: pumpClock))
    }

    struct Package: Encodable {
        let device: Device
    }

    struct Device: Encodable {
        let pumpRev: String
        let armSwVer: UInt32
        let mspSwVer: UInt32
        let modelNum: UInt32
        let serialNum: UInt32
        let partNum: UInt32
        let pcbaSN: UInt32
        let pcbaRev: String
        let configABits: UInt32
        let configBBits: UInt32
        let data: DeviceData

        init(info: TandemSourceDeviceInfo, deviceAssignmentId: String, events: [String]?, settings: String?, now: Date, pumpClock: Date) {
            pumpRev = info.pumpRev
            armSwVer = info.armSwVer
            mspSwVer = info.mspSwVer
            modelNum = info.modelNum
            serialNum = info.serialNum
            partNum = info.partNum
            pcbaSN = info.pcbaSN
            pcbaRev = info.pcbaRev
            configABits = info.configABits
            configBBits = info.configBBits
            data = DeviceData(
                misc: Misc(info: info, deviceAssignmentId: deviceAssignmentId, now: now, pumpClock: pumpClock),
                events: events,
                settings: settings
            )
        }
    }

    struct DeviceData: Encodable {
        let misc: Misc
        let events: [String]?
        let settings: String?
    }

    struct Misc: Encodable {
        let uploaderClient = "mobile_mobi"
        let appVersion: String
        let platform: String
        let pumpAPIVersion: String
        let pumpDateTime: String
        let clientDateTimeWithOffset: String
        let deviceAssignmentId: String
        let pumpFeatures: PumpFeatures

        init(info: TandemSourceDeviceInfo, deviceAssignmentId: String, now: Date, pumpClock: Date) {
            appVersion = TandemSourceConfig.appVersion
            platform = TandemSourceConfig.platform
            pumpAPIVersion = info.pumpAPIVersion
            pumpDateTime = Self.pumpFormatter.string(from: pumpClock)
            clientDateTimeWithOffset = Self.offsetFormatter.string(from: now)
            self.deviceAssignmentId = deviceAssignmentId
            pumpFeatures = PumpFeatures(dexcomG6: info.dexcomG6, controlIQ: info.controlIQ, basalIQ: info.basalIQ)
        }

        /// Pump wall clock, no zone (the pump reports local time with no offset), matching the app's
        /// `pumpDateTime: "2026-10-31T09:41:05"`.
        static let pumpFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return f
        }()

        /// Phone clock with offset, matching `clientDateTimeWithOffset: "2026-10-31T09:41:24-07:00"`.
        static let offsetFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
            return f
        }()
    }

    /// The app sends these three false whatever the pump supports.
    struct PumpFeatures: Encodable {
        let dexcomG6: Bool
        let controlIQ: Bool
        let basalIQ: Bool
        let dexcomG5 = false
        let freestyleLibre2 = false
        let freestyleLibre3 = false
    }
}

/// `GET /cloud/upload/getlasteventuploaded` response.
struct LastEventUploadedResponse: Decodable {
    let maxPumpEventIndex: UInt32
    let processingStatus: Int
}

/// `GET /pumpers/api/pumpers/{pumperId}` response — only the fields used to resolve a pump's
/// `deviceAssignmentId`. The pumper carries the account's devices; each assigned device has an
/// `assignmentId`, and `releasedAt` is non-nil once a device has been unassigned.
struct PumperResponse: Decodable {
    let devices: [PumperDevice]

    struct PumperDevice: Decodable {
        let serialNumber: String
        let assignmentId: String
        let releasedAt: String?
    }
}
