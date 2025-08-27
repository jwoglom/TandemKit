//
//  MalfunctionStatus.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of MalfunctionStatusRequest and MalfunctionStatusResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/MalfunctionStatusRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/MalfunctionStatusResponse.java
//

import Foundation

/// Request any malfunction codes from the pump.
public class MalfunctionStatusRequest: Message {
    public static let props = MessageProps(
        opCode: 120,
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

/// Response with malfunction codes.
public class MalfunctionStatusResponse: Message {
    public static let props = MessageProps(
        opCode: 121,
        size: 11,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var codeA: UInt32
    public var codeB: UInt32
    public var remaining: Data

    public required init(cargo: Data) {
        self.cargo = cargo
        self.codeA = Bytes.readUint32(cargo, 0)
        self.codeB = Bytes.readUint32(cargo, 4)
        self.remaining = cargo.subdata(in: 8..<11)
    }

    public init(codeA: UInt32, codeB: UInt32, remaining: Data = Data([0,0,0])) {
        self.cargo = Bytes.combine(
            Bytes.toUint32(codeA),
            Bytes.toUint32(codeB),
            remaining
        )
        self.codeA = codeA
        self.codeB = codeB
        self.remaining = remaining
    }

    /// Formatted malfunction code string if present.
    public var errorString: String {
        if !hasMalfunction { return "" }
        return String(format: "%d-%#x", codeA, codeB)
    }

    /// Whether the pump reports a malfunction.
    public var hasMalfunction: Bool {
        if codeA == 0 && codeB == 0 { return false }
        if codeA == 3 && codeB == 0x2026 { return false }
        return true
    }
}

