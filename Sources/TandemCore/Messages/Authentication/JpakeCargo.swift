import Foundation

/// A JPAKE challenge response whose payload ends in a ZKP scalar. The scalar is written with its
/// leading zero bytes stripped, so the pump's payload can be up to a full scalar width shorter than
/// the declared message size, and the transport must not reject it as truncated.
protocol JpakeChallengeResponse: Message {}

/// A JPAKE message body is `[2-byte app instance id][challenge payload]`, and the payload is a run
/// of length-prefixed fields. `Data.subdata` traps on a range that runs past the end, so the
/// payload slice is clamped to what actually arrived rather than taken blind.
enum JpakeCargo {
    /// How much shorter than `props.size` a challenge response may legitimately be: the P-256
    /// scalar it ends with can encode to as little as one byte.
    static let maxScalarShortfall = 32

    /// The app instance id in the first two bytes, or 0 when the cargo is too short to hold one.
    /// `Bytes.readShort` traps on a short buffer, and these responses are built from whatever the
    /// pump sent.
    static func appInstanceId(_ cargo: Data) -> Int {
        guard cargo.count >= 2 else { return 0 }
        return Bytes.readShort(cargo, 0)
    }

    static func challengePayload(_ cargo: Data, declaredSize: Int) -> Data {
        let start = cargo.startIndex
        let end = Swift.min(start + declaredSize, cargo.endIndex)
        guard end > start + 2 else { return Data() }
        return cargo.subdata(in: start + 2 ..< end)
    }
}
