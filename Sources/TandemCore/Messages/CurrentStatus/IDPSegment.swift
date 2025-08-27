//
//  IDPSegment.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of IDPSegmentRequest and IDPSegmentResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/IDPSegmentRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/IDPSegmentResponse.java
//

import Foundation

/// Request a specific insulin delivery profile segment.
public class IDPSegmentRequest: Message {
    public static let props = MessageProps(
        opCode: 66,
        size: 2,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var idpId: Int
    public var segmentIndex: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.idpId = Int(cargo[0])
        self.segmentIndex = Int(cargo[1])
    }

    public init(idpId: Int, segmentIndex: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(idpId),
            Bytes.firstByteLittleEndian(segmentIndex)
        )
        self.idpId = idpId
        self.segmentIndex = segmentIndex
    }
}

/// Response describing an insulin delivery profile segment.
public class IDPSegmentResponse: Message {
    public static let props = MessageProps(
        opCode: 67,
        size: 15,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var idpId: Int
    public var segmentIndex: Int
    public var profileStartTime: Int
    public var profileBasalRate: Int
    public var profileCarbRatio: UInt32
    public var profileTargetBG: Int
    public var profileISF: Int
    public var idpStatusId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        self.idpId = Int(cargo[0])
        self.segmentIndex = Int(cargo[1])
        self.profileStartTime = Bytes.readShort(cargo, 2)
        self.profileBasalRate = Bytes.readShort(cargo, 4)
        self.profileCarbRatio = Bytes.readUint32(cargo, 6)
        self.profileTargetBG = Bytes.readShort(cargo, 10)
        self.profileISF = Bytes.readShort(cargo, 12)
        self.idpStatusId = Int(cargo[14])
    }

    public init(idpId: Int, segmentIndex: Int, profileStartTime: Int, profileBasalRate: Int, profileCarbRatio: UInt32, profileTargetBG: Int, profileISF: Int, idpStatusId: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstByteLittleEndian(idpId),
            Bytes.firstByteLittleEndian(segmentIndex),
            Bytes.firstTwoBytesLittleEndian(profileStartTime),
            Bytes.firstTwoBytesLittleEndian(profileBasalRate),
            Bytes.toUint32(profileCarbRatio),
            Bytes.firstTwoBytesLittleEndian(profileTargetBG),
            Bytes.firstTwoBytesLittleEndian(profileISF),
            Bytes.firstByteLittleEndian(idpStatusId)
        )
        self.idpId = idpId
        self.segmentIndex = segmentIndex
        self.profileStartTime = profileStartTime
        self.profileBasalRate = profileBasalRate
        self.profileCarbRatio = profileCarbRatio
        self.profileTargetBG = profileTargetBG
        self.profileISF = profileISF
        self.idpStatusId = idpStatusId
    }

    /// Which fields in the segment are populated.
    public var idpStatus: Set<IDPSegmentStatus> {
        return IDPSegmentStatus.fromBitmask(idpStatusId)
    }

    public enum IDPSegmentStatus: Int, CaseIterable {
        case BASAL_RATE = 1
        case CARB_RATIO = 2
        case TARGET_BG = 4
        case CORRECTION_FACTOR = 8
        case START_TIME = 16

        public static func fromBitmask(_ mask: Int) -> Set<IDPSegmentStatus> {
            var set = Set<IDPSegmentStatus>()
            for status in IDPSegmentStatus.allCases {
                if (mask & status.rawValue) != 0 {
                    set.insert(status)
                }
            }
            return set
        }
    }
}

