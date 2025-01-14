//
//  HmacSha1.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//

import CommonCrypto

func HmacSha1(data: Data, key: Data) -> Data {
    var macData = Data(count: Int(CC_SHA1_DIGEST_LENGTH))

   macData.withUnsafeMutableBytes { macBytes in
       data.withUnsafeBytes { messageBytes in
           key.withUnsafeBytes { keyBytes in
               CCHmac(
                   CCHmacAlgorithm(kCCHmacAlgSHA1),
                   keyBytes.baseAddress, key.count,
                   messageBytes.baseAddress, data.count,
                   macBytes.bindMemory(to: UInt8.self).baseAddress
               )
           }
       }
   }
   return macData
}
