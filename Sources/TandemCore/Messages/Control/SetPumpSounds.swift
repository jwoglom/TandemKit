import Foundation

/// Request to update pump annunciation (audio/vibrate) settings.
public class SetPumpSoundsRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-28)),
        size: 9,
        type: .Request,
        characteristic: .CONTROL_CHARACTERISTICS,
        signed: true
    )

    public var cargo: Data
    public var quickBolusAnnunRaw: Int
    public var generalAnnunRaw: Int
    public var reminderAnnunRaw: Int
    public var alertAnnunRaw: Int
    public var alarmAnnunRaw: Int
    public var cgmAlertAnnun: Int
    public var changeBitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        quickBolusAnnunRaw = Int(cargo[1])
        generalAnnunRaw = Int(cargo[2])
        reminderAnnunRaw = Int(cargo[3])
        alertAnnunRaw = Int(cargo[4])
        alarmAnnunRaw = Int(cargo[5])
        cgmAlertAnnun = Int(cargo[6]) | (Int(cargo[7]) << 8)
        changeBitmask = Int(cargo[8])
    }

    public init(
        quickBolusAnnunRaw: Int,
        generalAnnunRaw: Int,
        reminderAnnunRaw: Int,
        alertAnnunRaw: Int,
        alarmAnnunRaw: Int,
        cgmAlertAnnun: Int,
        changeBitmask: Int
    ) {
        cargo = SetPumpSoundsRequest.buildCargo(
            quickBolusAnnunRaw: quickBolusAnnunRaw,
            generalAnnunRaw: generalAnnunRaw,
            reminderAnnunRaw: reminderAnnunRaw,
            alertAnnunRaw: alertAnnunRaw,
            alarmAnnunRaw: alarmAnnunRaw,
            cgmAlertAnnun: cgmAlertAnnun,
            changeBitmask: changeBitmask
        )
        self.quickBolusAnnunRaw = quickBolusAnnunRaw
        self.generalAnnunRaw = generalAnnunRaw
        self.reminderAnnunRaw = reminderAnnunRaw
        self.alertAnnunRaw = alertAnnunRaw
        self.alarmAnnunRaw = alarmAnnunRaw
        self.cgmAlertAnnun = cgmAlertAnnun
        self.changeBitmask = changeBitmask
    }

    public static func buildCargo(
        quickBolusAnnunRaw: Int,
        generalAnnunRaw: Int,
        reminderAnnunRaw: Int,
        alertAnnunRaw: Int,
        alarmAnnunRaw: Int,
        cgmAlertAnnun: Int,
        changeBitmask: Int
    ) -> Data {
        Bytes.combine(
            Data([0]),
            Data([UInt8(quickBolusAnnunRaw & 0xFF)]),
            Data([UInt8(generalAnnunRaw & 0xFF)]),
            Data([UInt8(reminderAnnunRaw & 0xFF)]),
            Data([UInt8(alertAnnunRaw & 0xFF)]),
            Data([UInt8(alarmAnnunRaw & 0xFF)]),
            Data([UInt8((cgmAlertAnnun >> 8) & 0xFF)]),
            Data([UInt8(cgmAlertAnnun & 0xFF)]),
            Data([UInt8(changeBitmask & 0xFF)])
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

    public var description: String {
        "SetPumpSoundsRequest(cargo=\(cargo.hexadecimalString), quickBolusAnnun=\(String(describing: quickBolusAnnun)), quickBolusAnnunRaw=\(quickBolusAnnunRaw), generalAnnun=\(String(describing: generalAnnun)), generalAnnunRaw=\(generalAnnunRaw), reminderAnnun=\(String(describing: reminderAnnun)), reminderAnnunRaw=\(reminderAnnunRaw), alertAnnun=\(String(describing: alertAnnun)), alertAnnunRaw=\(alertAnnunRaw), alarmAnnun=\(String(describing: alarmAnnun)), alarmAnnunRaw=\(alarmAnnunRaw), cgmAlertAnnun=\(cgmAlertAnnun), changeBitmask=\(changeBitmask))"
    }
}

/// Response confirming pump sound settings update.
public class SetPumpSoundsResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-27)),
        size: 1,
        type: .Response,
        characteristic: .CONTROL_CHARACTERISTICS,
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
