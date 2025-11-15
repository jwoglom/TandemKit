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
    public var cgmAlertAnnunA: Int
    public var cgmAlertAnnunB: Int
    public var changeBitmask: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        quickBolusAnnunRaw = Int(cargo[1])
        generalAnnunRaw = Int(cargo[2])
        reminderAnnunRaw = Int(cargo[3])
        alertAnnunRaw = Int(cargo[4])
        alarmAnnunRaw = Int(cargo[5])
        cgmAlertAnnunA = Int(cargo[6])
        cgmAlertAnnunB = Int(cargo[7])
        changeBitmask = Int(cargo[8])
    }

    public init(
        quickBolusAnnunRaw: Int,
        generalAnnunRaw: Int,
        reminderAnnunRaw: Int,
        alertAnnunRaw: Int,
        alarmAnnunRaw: Int,
        cgmAlertAnnunA: Int,
        cgmAlertAnnunB: Int,
        changeBitmask: Int
    ) {
        cargo = SetPumpSoundsRequest.buildCargo(
            quickBolusAnnunRaw: quickBolusAnnunRaw,
            generalAnnunRaw: generalAnnunRaw,
            reminderAnnunRaw: reminderAnnunRaw,
            alertAnnunRaw: alertAnnunRaw,
            alarmAnnunRaw: alarmAnnunRaw,
            cgmAlertAnnunA: cgmAlertAnnunA,
            cgmAlertAnnunB: cgmAlertAnnunB,
            changeBitmask: changeBitmask
        )
        self.quickBolusAnnunRaw = quickBolusAnnunRaw
        self.generalAnnunRaw = generalAnnunRaw
        self.reminderAnnunRaw = reminderAnnunRaw
        self.alertAnnunRaw = alertAnnunRaw
        self.alarmAnnunRaw = alarmAnnunRaw
        self.cgmAlertAnnunA = cgmAlertAnnunA
        self.cgmAlertAnnunB = cgmAlertAnnunB
        self.changeBitmask = changeBitmask
    }

    public static func buildCargo(
        quickBolusAnnunRaw: Int,
        generalAnnunRaw: Int,
        reminderAnnunRaw: Int,
        alertAnnunRaw: Int,
        alarmAnnunRaw: Int,
        cgmAlertAnnunA: Int,
        cgmAlertAnnunB: Int,
        changeBitmask: Int
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
}

/// Bitmask fields indicating which annunciation settings changed.
public enum PumpSoundChangeBitmask: Int {
    case quickBolus = 1
    case general = 2
    case reminder = 4
    case alert = 8
    case alarm = 16
    case cgmAlert = 32
}
