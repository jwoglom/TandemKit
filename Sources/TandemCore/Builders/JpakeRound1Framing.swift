import Foundation

/// Splits and reassembles JPAKE round-1 payloads across the pump's two fixed-size frames.
///
/// Round 1 is two `(point, ZKP)` groups laid out as length-prefixed fields:
///
///     [1-byte len][X point][1-byte len][V point][1-byte len][scalar r]
///
/// With uncompressed P-256 points (65 bytes) and a full-width scalar (32 bytes) each group is
/// exactly 165 bytes, which is why `Jpake1aRequest`/`Jpake1bRequest` each carry a 165-byte
/// challenge. But `r` is written with its leading zero bytes stripped, so it is 32 bytes only
/// about 255/256 of the time, and the pair is exactly 330 bytes only about 99.2% of the time.
///
/// Both frames are one stream cut at byte 165 and zero-padded at its end, as pumpX2's client and
/// server both send it (`Arrays.copyOfRange(round1, 165, 330)`), and the peer reads round 1 by
/// concatenating the frames. Padding a short first group to its own frame put a zero in the middle
/// of that stream, which pumpX2 read as an empty point.
enum JpakeRound1Framing {
    /// Bytes of challenge carried by one JPAKE frame.
    static let frameSize = 165

    /// Total length of the length-prefixed group starting at `offset`, or nil if the buffer is
    /// truncated part-way through one.
    static func groupLength(in data: Data, at offset: Int) -> Int? {
        var cursor = offset
        // A group is exactly three length-prefixed fields: the point, the ZKP's point, and the
        // ZKP's scalar.
        for _ in 0 ..< 3 {
            guard cursor < data.count else { return nil }
            let fieldLength = Int(data[data.startIndex + cursor])
            cursor += 1 + fieldLength
            guard cursor <= data.count else { return nil }
        }
        return cursor - offset
    }

    /// `round1` cut at `frameSize` and zero-padded at its end to two frames. Returns nil when
    /// `round1` is not two well-formed groups, or when they do not fit two frames.
    static func splitRound1(_ round1: Data) -> (first: Data, second: Data)? {
        guard let firstLength = groupLength(in: round1, at: 0),
              let secondLength = groupLength(in: round1, at: firstLength),
              firstLength + secondLength <= 2 * frameSize
        else {
            return nil
        }

        var stream = Data(round1.prefix(firstLength + secondLength))
        stream.append(Data(repeating: 0, count: 2 * frameSize - stream.count))
        return (stream.subdata(in: 0 ..< frameSize), stream.subdata(in: frameSize ..< 2 * frameSize))
    }

    /// The pump's two frames as the round-1 payload they were cut from; the padding at the end is
    /// past the second group, where the parser never reaches.
    static func joinRound1(first: Data, second: Data) -> Data {
        Bytes.combine(first, second)
    }

    /// Right-pads `data` with zero bytes to `frameSize`, or truncates if it is somehow longer.
    static func padToFrame(_ data: Data) -> Data {
        if data.count == frameSize { return data }
        if data.count > frameSize { return data.prefix(frameSize) }
        var padded = Data(data)
        padded.append(Data(repeating: 0, count: frameSize - data.count))
        return padded
    }
}
