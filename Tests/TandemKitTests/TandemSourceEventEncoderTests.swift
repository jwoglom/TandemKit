@testable import TandemKit
import XCTest

/// Locks the BLE→cloud byte transform used for `/cloud/upload/upload` `events[]`. A record is read
/// off the pump little-endian and sent to the cloud with the header and each 4-byte payload word
/// byte-reversed; if the transform drifts, these stop matching and the cloud would silently reject
/// or misread uploads. The vectors here are synthetic — the structure is what matters, and the
/// transform was verified byte-for-byte against a real captured Mobi upload during development
/// (see `mobi/docs/cloud-upload.md`).
final class TandemSourceEventEncoderTests: XCTestCase {
    private func hex(_ s: String) -> Data { Data(hexadecimalString: s)! }

    func testBolusGoldenVector() {
        // BOLUS_DELIVERY (typeId 280 = 0x0118), synthetic timestamp/sequence/payload.
        let ble = hex("1801" + "00000000" + "01000000" + "deadbeef" + "cafef00d" + "12345678" + "9abcdef0")
        let expectedCloud = hex("0118" + "00000000" + "00000001" + "efbeadde" + "0df0feca" + "78563412" + "f0debc9a")

        XCTAssertEqual(TandemSourceEventEncoder.uploadableBytes(from: ble), expectedCloud)
        XCTAssertEqual(
            TandemSourceEventEncoder.base64Event(for: stored(ble)),
            "ARgAAAAAAAAAAe++rd4N8P7KeFY0EvDevJo="
        )
    }

    func testDexcomG7GoldenVector() {
        // CGM_DATA_G7 (typeId 0x18F), synthetic payload. Confirms the header type crosses as 0x018F
        // rather than being truncated to a byte, and that a CGM payload reverses correctly.
        let ble = hex("8f01" + "00000000" + "02000000" + "00112233" + "44556677" + "8899aabb" + "ccddeeff")
        let cloud = hex("018f" + "00000000" + "00000002" + "33221100" + "77665544" + "bbaa9988" + "ffeeddcc")

        XCTAssertEqual(TandemSourceEventEncoder.uploadableBytes(from: ble), cloud)
        XCTAssertEqual(TandemSourceEventEncoder.base64Event(for: stored(ble)), "AY8AAAAAAAAAAjMiEQB3ZlVEu6qZiP/u3cw=")
        XCTAssertEqual(HistoryLogParser.parse(ble).typeId, 0x18F)
    }

    /// The transform is its own inverse, so re-encoding the decoded form returns the original.
    func testTransformIsInvolution() {
        let ble = hex("1801" + "00000000" + "01000000" + "deadbeef" + "cafef00d" + "12345678" + "9abcdef0")
        let cloud = TandemSourceEventEncoder.uploadableBytes(from: ble)
        XCTAssertEqual(TandemSourceEventEncoder.uploadableBytes(from: cloud), ble)
    }

    private func stored(_ cargo: Data) -> StoredHistoryLog {
        StoredHistoryLog(log: HistoryLogParser.parse(cargo), pumpSerial: 1234567)
    }
}
