//
//  CommonSoftwareInfo.swift
//  TandemKit
//
//  Created by OpenAI's Codex.
//
//  Swift representations of CommonSoftwareInfoRequest and CommonSoftwareInfoResponse based on
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/request/currentStatus/CommonSoftwareInfoRequest.java
//  https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/CommonSoftwareInfoResponse.java
//

import Foundation

/// Request common software information from the pump.
public class CommonSoftwareInfoRequest: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-114)),
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

/// Response describing pump software and bootloader versions.
public class CommonSoftwareInfoResponse: Message {
    public static var props = MessageProps(
        opCode: UInt8(bitPattern: Int8(-113)),
        size: 60,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS,
        variableSize: true
    )

    public var cargo: Data
    public var appSoftwareVersion: String
    public var appSoftwarePartNumber: UInt32
    public var appSoftwarePartDashNumber: UInt32
    public var appSoftwarePartRevisionNumber: UInt32
    public var bootloaderVersion: String
    public var bootloaderPartNumber: UInt32
    public var bootloaderPartDashNumber: UInt32?
    public var bootloaderPartRevisionNumber: UInt32?

    public required init(cargo: Data) {
        self.cargo = cargo
        self.appSoftwareVersion = Bytes.readString(cargo, 0, 18)
        self.appSoftwarePartNumber = Bytes.readUint32(cargo, 18)
        self.appSoftwarePartDashNumber = Bytes.readUint32(cargo, 22)
        self.appSoftwarePartRevisionNumber = Bytes.readUint32(cargo, 26)
        self.bootloaderVersion = Bytes.readString(cargo, 30, 17)
        self.bootloaderPartNumber = Bytes.readUint32(cargo, 47)
        if cargo.count >= 60 {
            self.bootloaderPartDashNumber = Bytes.readUint32(cargo, 51)
            self.bootloaderPartRevisionNumber = Bytes.readUint32(cargo, 55)
        } else {
            self.bootloaderPartDashNumber = nil
            self.bootloaderPartRevisionNumber = nil
        }
    }

    public init(appSoftwareVersion: String, appSoftwarePartNumber: UInt32, appSoftwarePartDashNumber: UInt32, appSoftwarePartRevisionNumber: UInt32, bootloaderVersion: String, bootloaderPartNumber: UInt32, bootloaderPartDashNumber: UInt32? = nil, bootloaderPartRevisionNumber: UInt32? = nil) {
        var data = Bytes.combine(
            Bytes.writeString(appSoftwareVersion, 18),
            Bytes.toUint32(appSoftwarePartNumber),
            Bytes.toUint32(appSoftwarePartDashNumber),
            Bytes.toUint32(appSoftwarePartRevisionNumber),
            Bytes.writeString(bootloaderVersion, 17),
            Bytes.toUint32(bootloaderPartNumber)
        )
        if let dash = bootloaderPartDashNumber, let rev = bootloaderPartRevisionNumber {
            data = Bytes.combine(
                data,
                Bytes.toUint32(dash),
                Bytes.toUint32(rev)
            )
        }
        self.cargo = data
        self.appSoftwareVersion = appSoftwareVersion
        self.appSoftwarePartNumber = appSoftwarePartNumber
        self.appSoftwarePartDashNumber = appSoftwarePartDashNumber
        self.appSoftwarePartRevisionNumber = appSoftwarePartRevisionNumber
        self.bootloaderVersion = bootloaderVersion
        self.bootloaderPartNumber = bootloaderPartNumber
        self.bootloaderPartDashNumber = bootloaderPartDashNumber
        self.bootloaderPartRevisionNumber = bootloaderPartRevisionNumber
    }
}

