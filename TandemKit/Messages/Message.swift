//
//  Message.swift
//  TandemKit
//
//  Created by James Woglom on 1/7/25.
//

// https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/Message.java
public protocol Message: CustomStringConvertible {
    static var props: MessageProps { get }

    var cargo: Data { get }
    init(cargo: Data)
}

extension Message {
    public var description: String {
        return "Message(opCode=\(cargo.hexadecimalString))"
    }
}

public enum MessageType {
    case Request
    case Response
}

// https://github.com/jwoglom/pumpX2/blob/main/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/annotations/MessageProps.java
public struct MessageProps {
    var opCode: UInt8
    var size: UInt8
    var type: MessageType
    var characteristic: CharacteristicUUID
    var variableSize: Bool = false
    var stream: Bool = false
    var signed: Bool = false
    var minApi: KnownApiVersion = .apiV2_1
    var supportedDevices: SupportedDevices = .all
    var modifiesInsulinDelivery: Bool = false

}
