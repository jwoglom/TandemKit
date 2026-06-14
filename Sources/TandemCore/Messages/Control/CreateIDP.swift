import Foundation

/// Request to create or duplicate an insulin delivery profile.
public class CreateIDPRequest: Message {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-26)),
        size: 35,
        type: .Request,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var profileName: String // 17 bytes at offset 0-16 (null-padded)
    public var firstSegmentProfileCarbRatio: Int // uint32 at offset 17-20 (milligrams per unit)
    public var firstSegmentProfileStartTime: Int // uint16 at offset 21-22 (minutes since start of day)
    public var firstSegmentProfileBasalRate: Int // uint16 at offset 23-24
    public var firstSegmentProfileTargetBG: Int // uint16 at offset 25-26
    public var firstSegmentProfileISF: Int // uint16 at offset 27-28
    public var profileInsulinDuration: Int // uint16 at offset 29-30
    public var timeSegmentBitmask: Int // uint8 at offset 31. Bitmask: bit0=basalRate(1), bit1=carbRatio(2), bit2=targetBG(4), bit3=correctionFactor(8), bit4=startTime(16). 31=all for new, 0 for duplicate.
    public var bolusSettingsBitmask: Int // uint8 at offset 32. Bitmask: bit0=insulinDuration(1), bit1=maxBolus(2), bit2=carbEntry(4). 5=insulinDuration+carbEntry for new, 0 for duplicate.
    public var profileCarbEntry: Int // uint8 at offset 34
    public var sourceIdpId: Int // uint8 at offset 33

    public required init(cargo: Data) {
        self.cargo = cargo
        profileName = Bytes.readString(cargo, 0, 16)
        firstSegmentProfileCarbRatio = Int(Bytes.readUint32(cargo, 17)) // uint32 at offset 17-20
        firstSegmentProfileStartTime = Bytes.readShort(cargo, 21) // uint16 at offset 21-22
        firstSegmentProfileBasalRate = Bytes.readShort(cargo, 23)
        firstSegmentProfileTargetBG = Bytes.readShort(cargo, 25)
        firstSegmentProfileISF = Bytes.readShort(cargo, 27)
        profileInsulinDuration = Bytes.readShort(cargo, 29)
        timeSegmentBitmask = Int(cargo[31])
        bolusSettingsBitmask = Int(cargo[32])
        sourceIdpId = Int(cargo[33])
        profileCarbEntry = Int(cargo[34])
    }

    /// Create a brand new profile.
    public init(
        profileName: String,
        firstSegmentProfileCarbRatio: Int,
        firstSegmentProfileBasalRate: Int,
        firstSegmentProfileTargetBG: Int,
        firstSegmentProfileISF: Int,
        profileInsulinDuration: Int,
        profileCarbEntry: Int,
        timeSegmentBitmask: Int = 31,
        bolusSettingsBitmask: Int = 5
    ) {
        cargo = CreateIDPRequest.buildCargo(
            name: profileName,
            firstSegmentProfileCarbRatio: firstSegmentProfileCarbRatio,
            firstSegmentProfileStartTime: 0,
            firstSegmentProfileBasalRate: firstSegmentProfileBasalRate,
            firstSegmentProfileTargetBG: firstSegmentProfileTargetBG,
            firstSegmentProfileISF: firstSegmentProfileISF,
            profileInsulinDuration: profileInsulinDuration,
            timeSegmentBitmask: timeSegmentBitmask,
            bolusSettingsBitmask: bolusSettingsBitmask,
            carbEntry: profileCarbEntry,
            sourceIdpId: -1
        )
        self.profileName = profileName
        self.firstSegmentProfileCarbRatio = firstSegmentProfileCarbRatio
        firstSegmentProfileStartTime = 0
        self.firstSegmentProfileBasalRate = firstSegmentProfileBasalRate
        self.firstSegmentProfileTargetBG = firstSegmentProfileTargetBG
        self.firstSegmentProfileISF = firstSegmentProfileISF
        self.profileInsulinDuration = profileInsulinDuration
        self.timeSegmentBitmask = timeSegmentBitmask
        self.bolusSettingsBitmask = bolusSettingsBitmask
        self.profileCarbEntry = profileCarbEntry
        sourceIdpId = -1
    }

    /// Duplicate an existing profile by ID.
    public init(profileName: String, sourceIdpId: Int) {
        cargo = CreateIDPRequest.buildCargo(
            name: profileName,
            firstSegmentProfileCarbRatio: 0,
            firstSegmentProfileStartTime: 0,
            firstSegmentProfileBasalRate: 0,
            firstSegmentProfileTargetBG: 0,
            firstSegmentProfileISF: 0,
            profileInsulinDuration: 0,
            timeSegmentBitmask: 0,
            bolusSettingsBitmask: 0,
            carbEntry: 0,
            sourceIdpId: sourceIdpId
        )
        self.profileName = profileName
        firstSegmentProfileCarbRatio = 0
        firstSegmentProfileStartTime = 0
        firstSegmentProfileBasalRate = 0
        firstSegmentProfileTargetBG = 0
        firstSegmentProfileISF = 0
        profileInsulinDuration = 0
        timeSegmentBitmask = 0
        bolusSettingsBitmask = 0
        profileCarbEntry = 0
        self.sourceIdpId = sourceIdpId
    }

    public static func buildCargo(
        name: String,
        firstSegmentProfileCarbRatio: Int,
        firstSegmentProfileStartTime: Int = 0,
        firstSegmentProfileBasalRate: Int,
        firstSegmentProfileTargetBG: Int,
        firstSegmentProfileISF: Int,
        profileInsulinDuration: Int,
        timeSegmentBitmask: Int,
        bolusSettingsBitmask: Int,
        carbEntry: Int,
        sourceIdpId: Int
    ) -> Data {
        Bytes.combine(
            Bytes.writeString(name, 17),
            Bytes.toUint32(UInt32(firstSegmentProfileCarbRatio)), // uint32 at offset 17-20
            Bytes.firstTwoBytesLittleEndian(firstSegmentProfileStartTime), // uint16 at offset 21-22
            Bytes.firstTwoBytesLittleEndian(firstSegmentProfileBasalRate),
            Bytes.firstTwoBytesLittleEndian(firstSegmentProfileTargetBG),
            Bytes.firstTwoBytesLittleEndian(firstSegmentProfileISF),
            Bytes.firstTwoBytesLittleEndian(profileInsulinDuration),
            Data([UInt8(timeSegmentBitmask & 0xFF), UInt8(bolusSettingsBitmask & 0xFF)]),
            Data([UInt8(sourceIdpId & 0xFF)]),
            Data([UInt8(carbEntry & 0xFF)])
        )
    }

    public var description: String {
        "CreateIDPRequest(cargo=\(cargo.hexadecimalString), profileName=\(profileName), firstSegmentProfileCarbRatio=\(firstSegmentProfileCarbRatio), firstSegmentProfileStartTime=\(firstSegmentProfileStartTime), firstSegmentProfileBasalRate=\(firstSegmentProfileBasalRate), firstSegmentProfileTargetBG=\(firstSegmentProfileTargetBG), firstSegmentProfileISF=\(firstSegmentProfileISF), profileInsulinDuration=\(profileInsulinDuration), timeSegmentBitmask=\(timeSegmentBitmask), bolusSettingsBitmask=\(bolusSettingsBitmask), profileCarbEntry=\(profileCarbEntry), sourceIdpId=\(sourceIdpId))"
    }
}

/// Response indicating status of profile creation.
public class CreateIDPResponse: Message, StatusMessage {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-25)),
        size: 2,
        type: .Response,
        characteristic: CharacteristicUUID.CONTROL_CHARACTERISTICS,
        signed: true,
        modifiesInsulinDelivery: true,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data
    public var status: Int
    public var newIdpId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        status = Int(cargo[0])
        newIdpId = Int(cargo[1])
    }

    public init(status: Int, newIdpId: Int) {
        cargo = Data([UInt8(status & 0xFF), UInt8(newIdpId & 0xFF)])
        self.status = status
        self.newIdpId = newIdpId
    }

    public var description: String {
        "CreateIDPResponse(cargo=\(cargo.hexadecimalString), status=\(status), newIdpId=\(newIdpId))"
    }
}
