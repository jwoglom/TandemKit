//
//  PumpFeaturesAbstract.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift translation of PumpFeaturesAbstractResponse
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/PumpFeaturesAbstractResponse.java
//

import Foundation

/// Base response for pump feature messages.
public class PumpFeaturesAbstractResponse: Message {
    public static var props = MessageProps(
        opCode: 0,
        size: 0,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public func getPrimaryFeatures() -> Set<PumpFeaturesV1Response.PumpFeatureType> { fatalError("abstract") }
}

