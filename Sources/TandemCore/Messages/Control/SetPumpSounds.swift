import Foundation

/// Request to update pump annunciation (audio/vibrate) settings.
public class SetPumpSoundsRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-28)),
        size: 9,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var quickBolusAnnunRaw: Int
    public var generalAnnunRaw: Int
    public var reminderAnnunRaw: Int
    public var alertAnnunRaw: Int
    public var alarmAnnunRaw: Int
    public var cgmAlertAnnunA: Int
    public var cgmAlertAnnunB: Int
    public var changeBitmaskRaw: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        quickBolusAnnunRaw = Int(cargo[1])
        generalAnnunRaw = Int(cargo[2])
        reminderAnnunRaw = Int(cargo[3])
        alertAnnunRaw = Int(cargo[4])
        alarmAnnunRaw = Int(cargo[5])
        cgmAlertAnnunA = Int(cargo[6])
        cgmAlertAnnunB = Int(cargo[7])
        changeBitmaskRaw = Int(cargo[8])
    }

    public init(
        quickBolusAnnunRaw: Int,
        generalAnnunRaw: Int,
        reminderAnnunRaw: Int,
        alertAnnunRaw: Int,
        alarmAnnunRaw: Int,
        cgmAlertAnnunA: Int,
        cgmAlertAnnunB: Int,
        changeBitmaskRaw: Int
    ) {
        cargo = SetPumpSoundsRequest.buildCargo(
            quickBolusAnnunRaw: quickBolusAnnunRaw,
            generalAnnunRaw: generalAnnunRaw,
            reminderAnnunRaw: reminderAnnunRaw,
            alertAnnunRaw: alertAnnunRaw,
            alarmAnnunRaw: alarmAnnunRaw,
            cgmAlertAnnunA: cgmAlertAnnunA,
            cgmAlertAnnunB: cgmAlertAnnunB,
            changeBitmaskRaw: changeBitmaskRaw
        )
        self.quickBolusAnnunRaw = quickBolusAnnunRaw
        self.generalAnnunRaw = generalAnnunRaw
        self.reminderAnnunRaw = reminderAnnunRaw
        self.alertAnnunRaw = alertAnnunRaw
        self.alarmAnnunRaw = alarmAnnunRaw
        self.cgmAlertAnnunA = cgmAlertAnnunA
        self.cgmAlertAnnunB = cgmAlertAnnunB
        self.changeBitmaskRaw = changeBitmaskRaw
    }

    public convenience init(
        quickBolusAnnun: PumpGlobalsResponse.AnnunciationEnum,
        generalAnnun: PumpGlobalsResponse.AnnunciationEnum,
        reminderAnnun: PumpGlobalsResponse.AnnunciationEnum,
        alertAnnun: PumpGlobalsResponse.AnnunciationEnum,
        alarmAnnun: PumpGlobalsResponse.AnnunciationEnum,
        cgmAlertAnnun: CgmAlertAnnunciationEnum,
        changeBitmask: PumpSoundChangeBitmask
    ) {
        self.init(
            quickBolusAnnunRaw: quickBolusAnnun.rawValue,
            generalAnnunRaw: generalAnnun.rawValue,
            reminderAnnunRaw: reminderAnnun.rawValue,
            alertAnnunRaw: alertAnnun.rawValue,
            alarmAnnunRaw: alarmAnnun.rawValue,
            cgmAlertAnnunA: cgmAlertAnnun.idA,
            cgmAlertAnnunB: cgmAlertAnnun.idB,
            changeBitmaskRaw: changeBitmask.rawValue
        )
    }

    public static func buildCargo(
        quickBolusAnnunRaw: Int,
        generalAnnunRaw: Int,
        reminderAnnunRaw: Int,
        alertAnnunRaw: Int,
        alarmAnnunRaw: Int,
        cgmAlertAnnunA: Int,
        cgmAlertAnnunB: Int,
        changeBitmaskRaw: Int
    ) -> Data {
        Bytes.combine(
            Data([0]),
            Data([UInt8(quickBolusAnnunRaw & 0xFF)]),
            Data([UInt8(generalAnnunRaw & 0xFF)]),
            Data([UInt8(reminderAnnunRaw & 0xFF)]),
            Data([UInt8(alertAnnunRaw & 0xFF)]),
            Data([UInt8(alarmAnnunRaw & 0xFF)]),
            Data([UInt8(cgmAlertAnnunA & 0xFF)]),
            Data([UInt8(cgmAlertAnnunB & 0xFF)]),
            Data([UInt8(changeBitmaskRaw & 0xFF)])
        )
    }

    public var quickBolusAnnun: PumpGlobalsResponse
        .AnnunciationEnum? { PumpGlobalsResponse.AnnunciationEnum(rawValue: quickBolusAnnunRaw) }
    public var generalAnnun: PumpGlobalsResponse
        .AnnunciationEnum? { PumpGlobalsResponse.AnnunciationEnum(rawValue: generalAnnunRaw) }
    public var reminderAnnun: PumpGlobalsResponse
        .AnnunciationEnum? { PumpGlobalsResponse.AnnunciationEnum(rawValue: reminderAnnunRaw) }
    public var alertAnnun: PumpGlobalsResponse.AnnunciationEnum? { PumpGlobalsResponse.AnnunciationEnum(rawValue: alertAnnunRaw) }
    public var alarmAnnun: PumpGlobalsResponse.AnnunciationEnum? { PumpGlobalsResponse.AnnunciationEnum(rawValue: alarmAnnunRaw) }
    public var cgmAlertAnnun: CgmAlertAnnunciationEnum? { CgmAlertAnnunciationEnum.fromIds(cgmAlertAnnunA, cgmAlertAnnunB) }
    public var changeBitmask: Set<PumpSoundChangeBitmask> { PumpSoundChangeBitmask.fromBitmask(changeBitmaskRaw) }

    public var description: String {
        "SetPumpSoundsRequest(cargo=\(cargo.hexadecimalString), quickBolusAnnun=\(String(describing: quickBolusAnnun)), quickBolusAnnunRaw=\(quickBolusAnnunRaw), generalAnnun=\(String(describing: generalAnnun)), generalAnnunRaw=\(generalAnnunRaw), reminderAnnun=\(String(describing: reminderAnnun)), reminderAnnunRaw=\(reminderAnnunRaw), alertAnnun=\(String(describing: alertAnnun)), alertAnnunRaw=\(alertAnnunRaw), alarmAnnun=\(String(describing: alarmAnnun)), alarmAnnunRaw=\(alarmAnnunRaw), cgmAlertAnnunA=\(cgmAlertAnnunA), cgmAlertAnnunB=\(cgmAlertAnnunB), changeBitmaskRaw=\(changeBitmaskRaw))"
    }

    /// CGM alert annunciation type, composed of two byte IDs.
    public enum CgmAlertAnnunciationEnum {
        case vibrate
        case beep
        case hypoRepeat

        public var idA: Int {
            switch self {
            case .vibrate: return 0
            case .beep: return 0
            case .hypoRepeat: return 0
            }
        }

        public var idB: Int {
            switch self {
            case .vibrate: return 0
            case .beep: return 2
            case .hypoRepeat: return 3
            }
        }

        public static func fromIds(_ idA: Int, _ idB: Int) -> CgmAlertAnnunciationEnum? {
            switch (idA, idB) {
            case (0, 0): return .vibrate
            case (0, 2): return .beep
            case (0, 3): return .hypoRepeat
            default: return nil
            }
        }
    }
}

/// Response confirming pump sound settings update.
public class SetPumpSoundsResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-27)),
        size: 1,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var status: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        status = Int(cargo[0])
    }

    public init(status: Int) {
        cargo = Data([UInt8(status & 0xFF)])
        self.status = status
    }

    public var description: String {
        "SetPumpSoundsResponse(cargo=\(cargo.hexadecimalString), status=\(status))"
    }
}

/// Bitmask fields indicating which annunciation settings changed.
public enum PumpSoundChangeBitmask: Int, CaseIterable {
    case quickBolusAnnun = 2
    case generalAnnun = 4
    case reminderAnnun = 8
    case alertAnnun = 16
    case alarmAnnun = 32
    case cgmAlert = 64

    public static func all() -> Int {
        toBitmask([
            .quickBolusAnnun,
            .generalAnnun,
            .reminderAnnun,
            .alertAnnun,
            .alarmAnnun,
            .cgmAlert
        ])
    }

    public static func fromBitmask(_ bitmask: Int) -> Set<PumpSoundChangeBitmask> {
        var set = Set<PumpSoundChangeBitmask>()
        for field in PumpSoundChangeBitmask.allCases {
            if (bitmask & field.rawValue) != 0 { set.insert(field) }
        }
        return set
    }

    public static func toBitmask(_ fields: [PumpSoundChangeBitmask]) -> Int {
        var mask = 0
        for field in fields {
            mask |= field.rawValue
        }
        return mask
    }
}
