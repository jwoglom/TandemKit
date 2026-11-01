import Foundation

/// Converts a pump history record from its BLE wire form into the form Tandem Source expects in a
/// `/cloud/upload/upload` body's `events[]`.
///
/// The Mobi app is a relay: the 26-byte record it reads over BLE is the same record it sends to the
/// cloud, but with the byte order flipped. Over BLE every integer is little-endian; in the cloud the
/// header is big-endian and each of the four 4-byte payload words is reversed. `HistoryLogNetwork
/// ExtensionKt.getUploadableBytes` in the Mobi app does exactly this, word by word. We reproduce it
/// as a byte transform on the raw record so the pump's own `typeId`, timestamp and sequence number
/// cross unchanged in value — the header high nibble included, which a re-emit from the masked
/// `typeId` would drop.
///
/// Verified byte-for-byte against a captured Mobi upload during development: a bolus record and a
/// Dexcom G7 reading both encoded to the exact bytes Tandem received. See
/// `TandemSourceEventEncoderTests` and `mobi/docs/cloud-upload.md`.
enum TandemSourceEventEncoder {
    /// Reverse each of these byte groups in the 26-byte record: typeId (2), timestamp (4), sequence
    /// number (4), then the four payload words (4 each). Little-endian in, big-endian out.
    private static let groups: [Range<Int>] = [0 ..< 2, 2 ..< 6, 6 ..< 10, 10 ..< 14, 14 ..< 18, 18 ..< 22, 22 ..< 26]

    /// The cloud `events[]` string for one stored record.
    static func base64Event(for log: StoredHistoryLog) -> String {
        uploadableBytes(from: log.cargo).base64EncodedString()
    }

    /// The big-endian cloud form of a 26-byte little-endian BLE record. Pads or truncates to 26
    /// bytes first, matching `HistoryLog.fillCargo`, so a short cargo can't shift the word boundaries.
    static func uploadableBytes(from cargo: Data) -> Data {
        let le = [UInt8](HistoryLog.fillCargo(cargo))
        var out = [UInt8]()
        out.reserveCapacity(HistoryLog.length)
        for group in groups {
            out.append(contentsOf: le[group].reversed())
        }
        return Data(out)
    }
}
