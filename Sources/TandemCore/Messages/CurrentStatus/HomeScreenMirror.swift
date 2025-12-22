import Foundation

/// Request basic home screen status info.
public class HomeScreenMirrorRequest: Message {
    public static let props = MessageProps(
        opCode: 56,
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
        "HomeScreenMirrorRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response mirroring the pump home screen icons.
public class HomeScreenMirrorResponse: Message {
    public static let props = MessageProps(
        opCode: 57,
        size: 9,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var cgmTrendIconId: Int
    public var cgmAlertIconId: Int
    public var statusIcon0Id: Int
    public var statusIcon1Id: Int
    public var bolusStatusIconId: Int
    public var basalStatusIconId: Int
    public var apControlStateIconId: Int
    public var remainingInsulinPlusIcon: Bool
    public var cgmDisplayData: Bool

    public required init(cargo: Data) {
        self.cargo = cargo
        cgmTrendIconId = Int(cargo[0])
        cgmAlertIconId = Int(cargo[1])
        statusIcon0Id = Int(cargo[2])
        statusIcon1Id = Int(cargo[3])
        bolusStatusIconId = Int(cargo[4])
        basalStatusIconId = Int(cargo[5])
        apControlStateIconId = Int(cargo[6])
        remainingInsulinPlusIcon = cargo[7] != 0
        cgmDisplayData = cargo[8] != 0
    }

    public init(
        cgmTrendIconId: Int,
        cgmAlertIconId: Int,
        statusIcon0Id: Int,
        statusIcon1Id: Int,
        bolusStatusIconId: Int,
        basalStatusIconId: Int,
        apControlStateIconId: Int,
        remainingInsulinPlusIcon: Bool,
        cgmDisplayData: Bool
    ) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(cgmTrendIconId),
            Bytes.firstByteLittleEndian(cgmAlertIconId),
            Bytes.firstByteLittleEndian(statusIcon0Id),
            Bytes.firstByteLittleEndian(statusIcon1Id),
            Bytes.firstByteLittleEndian(bolusStatusIconId),
            Bytes.firstByteLittleEndian(basalStatusIconId),
            Bytes.firstByteLittleEndian(apControlStateIconId),
            Bytes.firstByteLittleEndian(remainingInsulinPlusIcon ? 1 : 0),
            Bytes.firstByteLittleEndian(cgmDisplayData ? 1 : 0)
        )
        self.cgmTrendIconId = cgmTrendIconId
        self.cgmAlertIconId = cgmAlertIconId
        self.statusIcon0Id = statusIcon0Id
        self.statusIcon1Id = statusIcon1Id
        self.bolusStatusIconId = bolusStatusIconId
        self.basalStatusIconId = basalStatusIconId
        self.apControlStateIconId = apControlStateIconId
        self.remainingInsulinPlusIcon = remainingInsulinPlusIcon
        self.cgmDisplayData = cgmDisplayData
    }

    public var description: String {
        "HomeScreenMirrorResponse(cargo=\(cargo.hexadecimalString), cgmTrendIcon=\(cgmTrendIcon), cgmTrendIconId=\(cgmTrendIconId), cgmAlertIcon=\(cgmAlertIcon), cgmAlertIconId=\(cgmAlertIconId), statusIcon0=\(statusIcon0), statusIcon0Id=\(statusIcon0Id), statusIcon1=\(statusIcon1), statusIcon1Id=\(statusIcon1Id), bolusStatusIcon=\(bolusStatusIcon), bolusStatusIconId=\(bolusStatusIconId), basalStatusIcon=\(basalStatusIcon), basalStatusIconId=\(basalStatusIconId), apControlStateIcon=\(apControlStateIcon), apControlStateIconId=\(apControlStateIconId), remainingInsulinPlusIcon=\(remainingInsulinPlusIcon), cgmDisplayData=\(cgmDisplayData))"
    }
}

public extension HomeScreenMirrorResponse {
    enum CGMTrendIcon: Int {
        case noArrow = 0
        case doubleUp = 1
        case up = 2
        case upRight = 3
        case flat = 4
        case downRight = 5
        case down = 6
        case doubleDown = 7
    }

    enum CGMAlertIcon: Int {
        case startup1 = 0
        case startup2 = 1
        case startup3 = 2
        case startup4 = 3
        case calibrate = 4
        case startupCalibrate = 5
        case checkmarkBloodDrop = 6
        case errorHighWedge = 7
        case errorLowWedge = 8
        case replaceSensor = 11
        case replaceTransmitter = 12
        case outOfRange = 13
        case failedSensor = 14
        case tripleDashes = 15
        case low = 16
        case high = 17
        case noError = 255
    }

    enum StatusIcon0: Int {
        case aam = 0
        case cgmTransmitter = 1
        case cgmTransmitterOutOfRange = 4
        case hide = 200
    }

    enum StatusIcon1: Int {
        case aam = 0
        case bloodDrop = 1
        case hide = 200
    }

    enum BolusStatusIcon: Int {
        case bolus = 0
        case autoBolus = 1
        case blackLockSecurityPin = 2
        case greyLockSecurityPinCgmGraphActive = 3
        case hide = 200
    }

    enum BasalStatusIcon: Int {
        case basal = 0
        case zeroBasal = 1
        case tempRate = 2
        case zeroTempRate = 3
        case suspend = 4
        case hypoSuspendBasalIQ = 5
        case increaseBasal = 6
        case attenuatedBasal = 7
        case hide = 200
    }

    enum ApControlStateIcon: Int {
        case stateGray = 0
        case stateGrayRedBasalSuspended = 1
        case stateGrayBlueIncralue: cgmTrendIconId) }
    var cgmAlertIcon: CGMAlertIcon? { CGMAlertIcon(rawValue: cgmAlertIconId) }
    var statusIcon0: StatusIcon0? { StatusIcon0(rawValue: statusIcon0Id) }
    var statusIcon1: StatusIcon1? { StatusIcon1(rawValue: statusIcon1Id) }
    var bolusStatusIcon: BolusStatusIcon? { BolusStatusIcon(rawValue: bolusStatusIconId) }
    var basalStatusIcon: BasalStatusIcon? { BasalStatusIcon(rawValue: basalStatusIconId) }
    var apControlStateIcon: ApControlStateIcon? { ApControlStateIcon(rawValue: apControlStateIconId) }
}

public extension HomeScreenMirrorRequest {
    var description: String {
        "HomeScreenMirrorRequest(cargo=\(cargo.hexadecimalString))"
    }
}

