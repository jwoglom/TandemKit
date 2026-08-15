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
/// about 255/256 of the time; a group is 164 bytes (or shorter) the rest of the time, and the
/// pair is exactly 330 bytes only about 99.2% of the time.
///
/// Slicing the payload at fixed offsets 0..<165 and 165..<330 — which is what pumpX2 does, and
/// what this driver used to do — therefore misaligns the second frame whenever the *first*
/// scalar is short, and runs off the end of the buffer whenever the second one is. Splitting on
/// the real group boundary and right-padding each frame to 165 fixes both: the pump's parser is
/// length-prefixed, so it stops at the end of the group and never looks at the padding.
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

    /// Splits `round1` on the boundary between its two groups, right-padding each half with zero
    /// bytes to `frameSize`. Returns nil when `round1` is not two well-formed groups, or when
    /// either group is too large for a frame.
    static func splitRound1(_ round1: Data) -> (first: Data, second: Data)? {
        guard let firstLength = groupLength(in: round1, at: 0),
              let secondLength = groupLength(in: round1, at: firstLength),
              firstLength <= frameSize,
              secondLength <= frameSize
        else {
            return nil
        }

        let start = round1.startIndex
        let first = round1.subdata(in: start ..< start + firstLength)
        let second = round1.subdata(in: start + firstLength ..< start + firstLength + secondLength)
        return (padToFrame(first), padToFrame(second))
    }

    /// Rejoins the two frames the pump sent into a single parseable round-1 payload, dropping the
    /// padding the first frame may carry. Padding on the *second* frame is harmless — it lands at
    /// the end of the stream, where the parser never reaches it — so it is left alone.
    static func joinRound1(first: Data, second: Data) -> Data {
        guard let firstLength = groupLength(in: first, at: 0) else {
            // Not parseable: hand back the naive concatenation so the caller's own error handling
            // reports the malformed payload rather than this helper silently reshaping it.
            return Bytes.combine(first, second)
        }
        let start = first.startIndex
        return Bytes.combine(first.subdata(in: start ..< start + firstLength), second)
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
