//
//  NonexistentErrorRequest.swift
//  TandemCore
//
//  Created by ChatGPT on 3/15/25.
//

import Foundation

/// Placeholder request paired with ``ErrorResponse`` entries in the registry.
public final class NonexistentErrorRequest: Message {
    public static let props = MessageProps(
        opCode: 0,
        size: 0,
        type: .Request,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        variableSize: true
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        self.cargo = Data()
    }
}
