//
//  HmacSha1.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//

import Foundation

func HmacSha1(data: Data, key: Data) -> Data {
    let blockSize = 64
    var keyData = key
    if keyData.count > blockSize {
        keyData = SHA1.hash(keyData)
    }
    if keyData.count < blockSize {
        keyData.append(contentsOf: [UInt8](repeating: 0, count: blockSize - keyData.count))
    }
    var oKey = Data(repeating: 0x5c, count: blockSize)
    var iKey = Data(repeating: 0x36, count: blockSize)
    for i in 0..<blockSize {
        oKey[i] ^= keyData[i]
        iKey[i] ^= keyData[i]
    }
    let innerHash = SHA1.hash(iKey + data)
    let finalHash = SHA1.hash(oKey + innerHash)
    return finalHash
}
