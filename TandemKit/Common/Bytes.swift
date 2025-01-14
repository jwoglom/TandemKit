//
//  Bytes.swift
//  TandemKit
//
//  Created by James Woglom on 1/7/25.
//

import Foundation
import Foundation

struct Bytes {

    /// Drops the first `n` bytes from the data and returns the remainder.
    static func dropFirstN(_ data: Data, _ n: Int) -> Data {
        guard n <= data.count else { return Data() }
        return data.subdata(in: n..<data.count)
    }

    /// Drops the last `n` bytes from the data and returns the remainder.
    static func dropLastN(_ data: Data, _ n: Int) -> Data {
        guard n <= data.count else { return Data() }
        return data.subdata(in: 0..<(data.count - n))
    }

    /// Gets the first `n` bytes from the data.
    static func firstN(_ data: Data, _ n: Int) -> Data {
        guard n <= data.count else { return Data() }
        return data.subdata(in: 0..<n)
    }

    /// Returns a reversed copy of the given data.
    static func reverse(_ data: Data) -> Data {
        return Data(data.reversed())
    }

    /// Concatenates any number of `Data` objects into a single `Data`.
    static func combine(_ items: Data...) -> Data {
        // You can also do: items.reduce(Data()) { $0 + $1 }
        var result = Data()
        for item in items {
            result.append(item)
        }
        return result
    }

    /// Returns a `Data` instance of the specified size, initialized to all 0s.
    static func emptyBytes(_ size: Int) -> Data {
        return Data(repeating: 0, count: size)
    }

    /// Reads a 16-bit little-endian integer from `data` at index `i`.
    /// (Equivalent to `readShort` in Java.)
    static func readShort(_ data: Data, _ i: Int) -> Int {
        precondition(i >= 0 && i + 1 < data.count, "Index out of bounds")

        // Same logic as Java: ((raw[i+1] & 0xFF) << 8) | (raw[i] & 0xFF)
        let lo = UInt16(data[i] & 0xFF)
        let hi = UInt16(data[i + 1] & 0xFF)
        return Int((hi << 8) | lo)
    }

    /// Reads a 32-bit float (little-endian) from `data` at index `i`.
    /// (Equivalent to `readFloat` in Java.)
    static func readFloat(_ data: Data, _ i: Int) -> Float {
        precondition(i >= 0 && i + 3 < data.count, "Index out of bounds")
        let sub = data.subdata(in: i..<(i + 4))
        // We'll interpret these 4 bytes as a Float in little-endian order.
        return sub.withUnsafeBytes { ptr -> Float in
            // Load raw bits from memory:
            let bitPattern = ptr.load(as: UInt32.self)
            // Convert from little-endian to native-endian, then to Float:
            return Float(bitPattern: UInt32(littleEndian: bitPattern))
        }
    }

    /// Converts a `Float` to a 4-byte `Data` (little-endian).
    /// (Equivalent to `toFloat` in Java.)
    static func toFloat(_ value: Float) -> Data {
        var bitPattern = value.bitPattern.littleEndian
        return withUnsafeBytes(of: &bitPattern) { Data($0) }
    }

    /// Reads a 32-bit unsigned value (little-endian) from `data` at index `i`.
    /// (Equivalent to `readUint32` in Java.)
    static func readUint32(_ data: Data, _ i: Int) -> UInt32 {
        precondition(i >= 0 && i + 3 < data.count, "Index out of bounds")
        // Java code: (b[i+3] << 24) + (b[i+2] << 16) + (b[i+1] << 8) + b[i]
        let b0 = UInt32(data[i])     // & 0xFF not really needed in Swift
        let b1 = UInt32(data[i + 1])
        let b2 = UInt32(data[i + 2])
        let b3 = UInt32(data[i + 3])
        return (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
    }

    /// Reads a 64-bit unsigned value (little-endian) from `data` at index `i`.
    /// Java version returns a `BigInteger`; here we return a `UInt64`.
    /// (Equivalent to `readUint64` in Java.)
    static func readUint64(_ data: Data, _ i: Int) -> UInt64 {
        precondition(i >= 0 && i + 7 < data.count, "Index out of bounds")
        // The Java code reversed the bytes before creating the BigInteger
        // to interpret them in big-endian. We replicate that logic for a UInt64:
        let sub = data.subdata(in: i..<(i + 8)).reversed()
        return sub.reduce(UInt64(0)) { (acc, byte) in
            (acc << 8) | UInt64(byte)
        }
    }

    /// Converts a 64-bit value to a 4-byte `Data` (little-endian),
    /// returning only the lowest 4 bytes. (Equivalent to `toUint32`.)
    static func toUint32(_ value: UInt32) -> Data {
        var little = value.littleEndian
        let full8 = withUnsafeBytes(of: &little) { Data($0) } // 8 bytes
        return full8.prefix(4) // lowest 4 bytes
    }

    /// Converts a 64-bit value to an 8-byte `Data` (little-endian).
    /// (Equivalent to `toUint64`.)
    static func toUint64(_ value: UInt64) -> Data {
        var little = value.littleEndian
        return withUnsafeBytes(of: &little) { Data($0) }
    }

    /// Returns the first two bytes of an `Int` in little-endian.
    /// (Equivalent to `firstTwoBytesLittleEndian`.)
    static func firstTwoBytesLittleEndian(_ i: Int) -> Data {
        let truncated = UInt32(i & 0xFFFF).littleEndian
        return withUnsafeBytes(of: truncated) { Data($0) }.prefix(2)
    }

    /// Returns the first byte of an `Int` in little-endian.
    /// (Equivalent to `firstByteLittleEndian`.)
    static func firstByteLittleEndian(_ i: Int) -> Data {
        let truncated = UInt32(i & 0xFF).littleEndian
        return withUnsafeBytes(of: truncated) { Data($0) }.prefix(1)
    }

    /// Reads a string from `data` starting at index `i`, until encountering
    /// a null byte (0) or reaching `length` characters. (Equivalent to `readString`.)
    static func readString(_ data: Data, _ i: Int, _ length: Int) -> String {
        precondition(i >= 0 && i < data.count, "Index out of bounds")
        var idx = i
        var strData = Data()
        // Read bytes until null or until we reach `length`
        while idx < data.count && data[idx] != 0 {
            strData.append(data[idx])
            if strData.count >= length {
                break
            }
            idx += 1
        }
        return String(data: strData, encoding: .utf8) ?? ""
    }

    /// Encodes a string as UTF-8 and zero-pads up to `length`.
    /// (Equivalent to `writeString`.)
    static func writeString(_ input: String, _ length: Int) -> Data {
        var encoded = Data(input.utf8)
        // Pad with null bytes up to the requested length
        while encoded.count < length {
            encoded.append(0)
        }
        return encoded
    }
}
