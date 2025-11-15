import Foundation

/// Request general information on insulin delivery profiles.
public class ProfileStatusRequest: Message {
    public static let props = MessageProps(
        opCode: 62,
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
}

/// Response containing insulin delivery profile slots.
public class ProfileStatusResponse: Message {
    public static let props = MessageProps(
        opCode: 63,
        size: 8,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var numberOfProfiles: Int
    public var idpSlot0Id: Int
    public var idpSlot1Id: Int
    public var idpSlot2Id: Int
    public var idpSlot3Id: Int
    public var idpSlot4Id: Int
    public var idpSlot5Id: Int
    public var activeSegmentIndex: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        numberOfProfiles = Int(cargo[0])
        idpSlot0Id = Int(cargo[1])
        idpSlot1Id = Int(cargo[2])
        idpSlot2Id = Int(cargo[3])
        idpSlot3Id = Int(cargo[4])
        idpSlot4Id = Int(cargo[5])
        idpSlot5Id = Int(cargo[6])
        activeSegmentIndex = Int(cargo[7])
    }

    public init(
        numberOfProfiles: Int,
        idpSlot0Id: Int,
        idpSlot1Id: Int,
        idpSlot2Id: Int,
        idpSlot3Id: Int,
        idpSlot4Id: Int,
        idpSlot5Id: Int,
        activeSegmentIndex: Int
    ) {
        cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(numberOfProfiles),
            Bytes.firstByteLittleEndian(idpSlot0Id),
            Bytes.firstByteLittleEndian(idpSlot1Id),
            Bytes.firstByteLittleEndian(idpSlot2Id),
            Bytes.firstByteLittleEndian(idpSlot3Id),
            Bytes.firstByteLittleEndian(idpSlot4Id),
            Bytes.firstByteLittleEndian(idpSlot5Id),
            Bytes.firstByteLittleEndian(activeSegmentIndex)
        )
        self.numberOfProfiles = numberOfProfiles
        self.idpSlot0Id = idpSlot0Id
        self.idpSlot1Id = idpSlot1Id
        self.idpSlot2Id = idpSlot2Id
        self.idpSlot3Id = idpSlot3Id
        self.idpSlot4Id = idpSlot4Id
        self.idpSlot5Id = idpSlot5Id
        self.activeSegmentIndex = activeSegmentIndex
    }

    /// Returns the active insulin delivery profile ID.
    public var activeIdpSlotId: Int { idpSlot0Id }

    /// All IDP slot IDs in order, limited to `numberOfProfiles`.
    public var idpSlotIds: [Int] {
        [idpSlot0Id, idpSlot1Id, idpSlot2Id, idpSlot3Id, idpSlot4Id, idpSlot5Id].prefix(numberOfProfiles).map { $0 }
    }
}
