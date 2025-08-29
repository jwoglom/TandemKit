//
//  ApiVersion.swift
//  TandemKit
//
//  Created by James Woglom on 1/7/25.
//
// https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/ApiVersionRequest.java
// https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/ApiVersionResponse.java

import Foundation

/**
 * Returns the major and minor API version of the pump.
 */
public class ApiVersionRequest: Message {
    public static let props = MessageProps(
        opCode: 32,
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

    public static let opCode = props.opCode
    public var payload: Data { cargo }
}

/**
 * The major and minor API version of the pump.
 */
public class ApiVersionResponse: Message {
    public static let props = MessageProps(
        opCode: 33,
        size: 4,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )
    
    public var cargo: Data
    public var majorVersion: Int
    public var minorVersion: Int
    
    public required init(cargo: Data) {
        self.cargo = cargo
        self.majorVersion = Bytes.readShort(cargo, 0)
        self.minorVersion = Bytes.readShort(cargo, 2)
    }
    
    public init(majorVersion: Int, minorVersion: Int) {
        self.cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(majorVersion),
            Bytes.firstTwoBytesLittleEndian(minorVersion)
        )
        self.majorVersion = majorVersion
        self.minorVersion = minorVersion
    }
    
    public func getApiVersion() -> ApiVersion {
        return ApiVersion(major: self.majorVersion, minor: self.minorVersion)
    }
}
