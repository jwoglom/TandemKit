//
//  ProfileStatus.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of ProfileStatusRequest and ProfileStatusResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/ProfileStatusRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/ProfileStatusResponse.java
//

import Foundation

/// Request general information on insulin delivery profiles.
public class ProfileStatusRequest: Message {
    public static var props = MessageProps(
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
        self.cargo = Data()
    }
}

/// Response containing insulin delivery profile slots.
public class ProfileStatusResponse: Message {
    public static var props = MessageProps(
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
        self.numberOfProfiles = Int(cargo[0])
        self.idpSlot0Id = Int(cargo[1])
        self.idpSlot1Id = Int(cargo[2])
        self.idpSlot2Id = Int(cargo[3])
        self.idpSlot3Id = Int(cargo[4])
        self.idpSlot4Id = Int(cargo[5])
        self.idpSlot5Id = Int(cargo[6])
        self.activeSegmentIndex = Int(cargo[7])
    }

    public init(numberOfProfiles: Int, idpSlot0Id: Int, idpSlot1Id: Int, idpSlot2Id: Int, idpSlot3Id: Int, idpSlot4Id: Int, idpSlot5Id: Int, activeSegmentIndex: Int) {
        self.cargo = Bytes.combine(
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
    public var activeIdpSlotId: Int { return idpSlot0Id }

    /// All IDP slot IDs in order, limited to `numberOfProfiles`.
    public var idpSlotIds: [Int] {
        return [idpSlot0Id, idpSlot1Id, idpSlot2Id, idpSlot3Id, idpSlot4Id, idpSlot5Id].prefix(numberOfProfiles).map { $0 }
    }
}

