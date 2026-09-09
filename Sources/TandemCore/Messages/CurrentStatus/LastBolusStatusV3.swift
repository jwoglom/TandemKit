import Foundation

/// Request last bolus status (V3) with dual standard/extended bolus structure.
public class LastBolusStatusV3Request: PumpRequest {
    public typealias Response = LastBolusStatusV3Response

    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-70)),
        size: 0,
        type: .Request,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "LastBolusStatusV3Request(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response with dual standard/extended last bolus information (V3, Mobi).
///
/// Binary layout (53 bytes):
///   byte  0:      lastBolusTypeBitmask (bit0=standard present, bit1=extended present)
///   -- Standard bolus section (bytes 1-24) --
///   byte  1:      standardBolusStatusId
///   bytes 2-3:    standardBolusId (uint16 LE)
///   bytes 4-5:    standardUnknown (padding)
///   bytes 6-9:    standardBolusTimestamp (uint32 LE, pump epoch seconds)
///   bytes 10-13:  standardBolusDeliveredVolume (uint32 LE)
///   byte  14:     standardBolusEndReasonId
///   byte  15:     standardBolusSourceId
///   byte  16:     standardBolusTypeBitmask
///   bytes 17-20:  standardBolusRequestedVolume (uint32 LE)
///   bytes 21-24:  standardBolusSecondsSincePumpReset (uint32 LE)
///   -- Extended bolus section (bytes 25-52) --
///   byte  25:     extendedBolusStatusId
///   bytes 26-27:  extendedBolusId (uint16 LE)
///   bytes 28-29:  extendedUnknown (padding)
///   bytes 30-33:  extendedBolusTimestamp (uint32 LE, pump epoch seconds)
///   bytes 34-37:  extendedBolusDeliveredVolume (uint32 LE)
///   byte  38:     extendedBolusEndReasonId
///   byte  39:     extendedBolusSourceId
///   byte  40:     extendedBolusTypeBitmask
///   bytes 41-44:  extendedBolusRequestedVolume (uint32 LE)
///   bytes 45-48:  extendedBolusSecondsSincePumpReset (uint32 LE)
///   bytes 49-52:  extendedBolusDuration (uint32 LE, seconds)
public class LastBolusStatusV3Response: Message, LastBolusStatusAbstractResponse {
    public static let props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-69)),
        size: 53,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
        minApi: .mobiApiV3_5,
        supportedDevices: .mobiOnly
    )

    public var cargo: Data

    /// Bitmask: bit 0 = standard bolus present, bit 1 = extended bolus present.
    public var lastBolusTypeBitmask: Int

    // Standard bolus fields
    public var standardBolusStatusId: Int
    public var standardBolusId: Int
    public var standardUnknown: Data
    public var standardBolusTimestamp: UInt32
    public var standardBolusDeliveredVolume: UInt32
    public var standardBolusEndReasonId: Int
    public var standardBolusSourceId: Int
    public var standardBolusTypeBitmask: Int
    public var standardBolusRequestedVolume: UInt32
    public var standardBolusSecondsSincePumpReset: UInt32

    // Extended bolus fields
    public var extendedBolusStatusId: Int
    public var extendedBolusId: Int
    public var extendedUnknown: Data
    public var extendedBolusTimestamp: UInt32
    public var extendedBolusDeliveredVolume: UInt32
    public var extendedBolusEndReasonId: Int
    public var extendedBolusSourceId: Int
    public var extendedBolusTypeBitmask: Int
    public var extendedBolusRequestedVolume: UInt32
    public var extendedBolusSecondsSincePumpReset: UInt32
    public var extendedBolusDuration: UInt32

    public required init(cargo: Data) {
        self.cargo = cargo
        lastBolusTypeBitmask = Int(cargo[0])

        // Standard bolus section (bytes 1-24)
        standardBolusStatusId = Int(cargo[1])
        standardBolusId = Bytes.readShort(cargo, 2)
        standardUnknown = cargo.subdata(in: 4 ..< 6)
        standardBolusTimestamp = Bytes.readUint32(cargo, 6)
        standardBolusDeliveredVolume = Bytes.readUint32(cargo, 10)
        standardBolusEndReasonId = Int(cargo[14])
        standardBolusSourceId = Int(cargo[15])
        standardBolusTypeBitmask = Int(cargo[16])
        standardBolusRequestedVolume = Bytes.readUint32(cargo, 17)
        standardBolusSecondsSincePumpReset = Bytes.readUint32(cargo, 21)

        // Extended bolus section (bytes 25-52)
        extendedBolusStatusId = Int(cargo[25])
        extendedBolusId = Bytes.readShort(cargo, 26)
        extendedUnknown = cargo.subdata(in: 28 ..< 30)
        extendedBolusTimestamp = Bytes.readUint32(cargo, 30)
        extendedBolusDeliveredVolume = Bytes.readUint32(cargo, 34)
        extendedBolusEndReasonId = Int(cargo[38])
        extendedBolusSourceId = Int(cargo[39])
        extendedBolusTypeBitmask = Int(cargo[40])
        extendedBolusRequestedVolume = Bytes.readUint32(cargo, 41)
        extendedBolusSecondsSincePumpReset = Bytes.readUint32(cargo, 45)
        extendedBolusDuration = Bytes.readUint32(cargo, 49)
    }

    public init(
        lastBolusTypeBitmask: Int,
        standardBolusStatusId: Int,
        standardBolusId: Int,
        standardUnknown: Data = Data([0, 0]),
        standardBolusTimestamp: UInt32,
        standardBolusDeliveredVolume: UInt32,
        standardBolusEndReasonId: Int,
        standardBolusSourceId: Int,
        standardBolusTypeBitmask: Int,
        standardBolusRequestedVolume: UInt32,
        standardBolusSecondsSincePumpReset: UInt32,
        extendedBolusStatusId: Int,
        extendedBolusId: Int,
        extendedUnknown: Data = Data([0, 0]),
        extendedBolusTimestamp: UInt32,
        extendedBolusDeliveredVolume: UInt32,
        extendedBolusEndReasonId: Int,
        extendedBolusSourceId: Int,
        extendedBolusTypeBitmask: Int,
        extendedBolusRequestedVolume: UInt32,
        extendedBolusSecondsSincePumpReset: UInt32,
        extendedBolusDuration: UInt32
    ) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(lastBolusTypeBitmask),
            Bytes.firstByteLittleEndian(standardBolusStatusId),
            Bytes.firstTwoBytesLittleEndian(standardBolusId),
            standardUnknown,
            Bytes.toUint32(standardBolusTimestamp),
            Bytes.toUint32(standardBolusDeliveredVolume),
            Bytes.firstByteLittleEndian(standardBolusEndReasonId),
            Bytes.firstByteLittleEndian(standardBolusSourceId),
            Bytes.firstByteLittleEndian(standardBolusTypeBitmask),
            Bytes.toUint32(standardBolusRequestedVolume),
            Bytes.toUint32(standardBolusSecondsSincePumpReset),
            Bytes.firstByteLittleEndian(extendedBolusStatusId),
            Bytes.firstTwoBytesLittleEndian(extendedBolusId),
            extendedUnknown,
            Bytes.toUint32(extendedBolusTimestamp),
            Bytes.toUint32(extendedBolusDeliveredVolume),
            Bytes.firstByteLittleEndian(extendedBolusEndReasonId),
            Bytes.firstByteLittleEndian(extendedBolusSourceId),
            Bytes.firstByteLittleEndian(extendedBolusTypeBitmask),
            Bytes.toUint32(extendedBolusRequestedVolume),
            Bytes.toUint32(extendedBolusSecondsSincePumpReset),
            Bytes.toUint32(extendedBolusDuration)
        )
        self.lastBolusTypeBitmask = lastBolusTypeBitmask
        self.standardBolusStatusId = standardBolusStatusId
        self.standardBolusId = standardBolusId
        self.standardUnknown = standardUnknown
        self.standardBolusTimestamp = standardBolusTimestamp
        self.standardBolusDeliveredVolume = standardBolusDeliveredVolume
        self.standardBolusEndReasonId = standardBolusEndReasonId
        self.standardBolusSourceId = standardBolusSourceId
        self.standardBolusTypeBitmask = standardBolusTypeBitmask
        self.standardBolusRequestedVolume = standardBolusRequestedVolume
        self.standardBolusSecondsSincePumpReset = standardBolusSecondsSincePumpReset
        self.extendedBolusStatusId = extendedBolusStatusId
        self.extendedBolusId = extendedBolusId
        self.extendedUnknown = extendedUnknown
        self.extendedBolusTimestamp = extendedBolusTimestamp
        self.extendedBolusDeliveredVolume = extendedBolusDeliveredVolume
        self.extendedBolusEndReasonId = extendedBolusEndReasonId
        self.extendedBolusSourceId = extendedBolusSourceId
        self.extendedBolusTypeBitmask = extendedBolusTypeBitmask
        self.extendedBolusRequestedVolume = extendedBolusRequestedVolume
        self.extendedBolusSecondsSincePumpReset = extendedBolusSecondsSincePumpReset
        self.extendedBolusDuration = extendedBolusDuration
    }

    /// True if a standard bolus record is present.
    public var isStandardBolusPresent: Bool {
        (lastBolusTypeBitmask & 0x01) != 0
    }

    /// True if an extended bolus record is present.
    public var isExtendedBolusPresent: Bool {
        (lastBolusTypeBitmask & 0x02) != 0
    }

    public var standardBolusSource: BolusSource? {
        BolusSource.fromId(standardBolusSourceId)
    }

    public var standardBolusTypes: Set<BolusType> {
        BolusType.fromBitmask(standardBolusTypeBitmask)
    }

    public var standardBolusTimestampDate: Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(standardBolusTimestamp))
    }

    public var extendedBolusSource: BolusSource? {
        BolusSource.fromId(extendedBolusSourceId)
    }

    public var extendedBolusTypes: Set<BolusType> {
        BolusType.fromBitmask(extendedBolusTypeBitmask)
    }

    public var extendedBolusTimestampDate: Date {
        Dates.fromJan12008EpochSecondsToDate(TimeInterval(extendedBolusTimestamp))
    }

    public var description: String {
        "LastBolusStatusV3Response(cargo=\(cargo.hexadecimalString), lastBolusTypeBitmask=\(lastBolusTypeBitmask), standardBolusStatusId=\(standardBolusStatusId), standardBolusId=\(standardBolusId), standardBolusTimestamp=\(standardBolusTimestamp), standardBolusDeliveredVolume=\(standardBolusDeliveredVolume), standardBolusEndReasonId=\(standardBolusEndReasonId), standardBolusSourceId=\(standardBolusSourceId), standardBolusTypeBitmask=\(standardBolusTypeBitmask), standardBolusRequestedVolume=\(standardBolusRequestedVolume), standardBolusSecondsSincePumpReset=\(standardBolusSecondsSincePumpReset), extendedBolusStatusId=\(extendedBolusStatusId), extendedBolusId=\(extendedBolusId), extendedBolusTimestamp=\(extendedBolusTimestamp), extendedBolusDeliveredVolume=\(extendedBolusDeliveredVolume), extendedBolusEndReasonId=\(extendedBolusEndReasonId), extendedBolusSourceId=\(extendedBolusSourceId), extendedBolusTypeBitmask=\(extendedBolusTypeBitmask), extendedBolusRequestedVolume=\(extendedBolusRequestedVolume), extendedBolusSecondsSincePumpReset=\(extendedBolusSecondsSincePumpReset), extendedBolusDuration=\(extendedBolusDuration))"
    }
}

/// One of the two bolus records carried by a `LastBolusStatusV3Response`.
///
/// A section is laid out identically to the single record in `LastBolusStatusV2Response`:
/// `statusId` is V2's `status`, and `endReasonId` is V2's `bolusStatusId`.
public struct LastBolusStatusV3Section: Equatable {
    /// Message-level status for this record; 0 indicates success.
    public let statusId: Int
    public let bolusId: Int
    public let timestamp: UInt32
    public let deliveredVolume: UInt32
    /// Why the bolus ended; the values of `LastBolusStatusAbstractResponse.BolusStatus`.
    public let endReasonId: Int
    public let bolusSourceId: Int
    public let bolusTypeBitmask: Int
    public let requestedVolume: UInt32
    public let secondsSincePumpReset: UInt32
    /// Programmed duration in seconds. Always 0 for the standard section.
    public let duration: UInt32
    /// True for the extended (bolex) section.
    public let isExtended: Bool

    public var endReason: LastBolusStatusAbstractResponseBolusStatus? {
        LastBolusStatusAbstractResponseBolusStatus(rawValue: endReasonId)
    }

    public var bolusSource: BolusSource? { BolusSource.fromId(bolusSourceId) }
    public var bolusTypes: Set<BolusType> { BolusType.fromBitmask(bolusTypeBitmask) }
    public var timestampDate: Date { Dates.fromJan12008EpochSecondsToDate(TimeInterval(timestamp)) }
}

public extension LastBolusStatusV3Response {
    /// The standard bolus record, or nil when the presence bitmask does not report one.
    var standardSection: LastBolusStatusV3Section? {
        guard isStandardBolusPresent else { return nil }
        return LastBolusStatusV3Section(
            statusId: standardBolusStatusId,
            bolusId: standardBolusId,
            timestamp: standardBolusTimestamp,
            deliveredVolume: standardBolusDeliveredVolume,
            endReasonId: standardBolusEndReasonId,
            bolusSourceId: standardBolusSourceId,
            bolusTypeBitmask: standardBolusTypeBitmask,
            requestedVolume: standardBolusRequestedVolume,
            secondsSincePumpReset: standardBolusSecondsSincePumpReset,
            duration: 0,
            isExtended: false
        )
    }

    /// The extended (bolex) bolus record, or nil when the presence bitmask does not report one.
    var extendedSection: LastBolusStatusV3Section? {
        guard isExtendedBolusPresent else { return nil }
        return LastBolusStatusV3Section(
            statusId: extendedBolusStatusId,
            bolusId: extendedBolusId,
            timestamp: extendedBolusTimestamp,
            deliveredVolume: extendedBolusDeliveredVolume,
            endReasonId: extendedBolusEndReasonId,
            bolusSourceId: extendedBolusSourceId,
            bolusTypeBitmask: extendedBolusTypeBitmask,
            requestedVolume: extendedBolusRequestedVolume,
            secondsSincePumpReset: extendedBolusSecondsSincePumpReset,
            duration: extendedBolusDuration,
            isExtended: true
        )
    }

    /// Every record the response reports as present, standard first.
    var sections: [LastBolusStatusV3Section] {
        [standardSection, extendedSection].compactMap { $0 }
    }

    /// The record the single-record `LastBolusStatusAbstractResponse` view reads: the standard
    /// portion when present, otherwise the extended one.
    var primarySection: LastBolusStatusV3Section? {
        standardSection ?? extendedSection
    }

    /// Total delivered volume in milliunits across every present record carrying `bolusId`,
    /// or nil when no record matches. A bolus split into an immediate and an extended portion
    /// under one id is only fully accounted for by summing both.
    func deliveredVolume(forBolusId bolusId: Int) -> UInt32? {
        let matching = sections.filter { $0.bolusId == bolusId }
        guard !matching.isEmpty else { return nil }
        return matching.reduce(UInt32(0)) { $0 &+ $1.deliveredVolume }
    }
}

// MARK: - LastBolusStatusAbstractResponse

/// Reads the `primarySection`, so a bolus with only an extended portion is still visible.
public extension LastBolusStatusV3Response {
    var status: Int { primarySection?.statusId ?? standardBolusStatusId }
    var bolusId: Int { primarySection?.bolusId ?? standardBolusId }
    var timestamp: UInt32 { primarySection?.timestamp ?? standardBolusTimestamp }
    var deliveredVolume: UInt32 { primarySection?.deliveredVolume ?? 0 }
    var bolusStatusId: Int { primarySection?.endReasonId ?? standardBolusEndReasonId }
    var bolusSourceId: Int { primarySection?.bolusSourceId ?? standardBolusSourceId }
    var bolusTypeBitmask: Int { primarySection?.bolusTypeBitmask ?? standardBolusTypeBitmask }
}
