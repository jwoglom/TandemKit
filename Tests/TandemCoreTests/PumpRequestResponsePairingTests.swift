@testable import TandemKit
import XCTest

/// Checks every `PumpRequest`'s declared `Response` against the message catalog, so the pairing is
/// verified once where it is declared rather than at each call site.
///
/// Driven off `MessageRegistry.all`, so a request added to the catalog is covered without being
/// listed here.
final class PumpRequestResponsePairingTests: XCTestCase {
    private var requests: [MessageMetadata] {
        MessageRegistry.all.filter { $0.messageType == .Request }
    }

    /// The stream placeholders stand in for unsolicited notifications and are never sent, so they
    /// deliberately do not conform. Everything else must.
    func testEverySendableRequestDeclaresItsResponse() {
        for meta in requests where !meta.name.contains("Nonexistent") {
            XCTAssertTrue(
                meta.type is any PumpRequest.Type,
                "\(meta.name) does not conform to PumpRequest, so it cannot be sent"
            )
        }
    }

    func testStreamPlaceholdersAreNotSendable() {
        for meta in requests where meta.name.contains("Nonexistent") {
            XCTAssertFalse(
                meta.type is any PumpRequest.Type,
                "\(meta.name) stands in for an unsolicited notification and must not be sendable"
            )
        }
    }

    func testDeclaredResponseIsAResponse() {
        for (meta, response) in pairings() {
            XCTAssertEqual(
                response.props.type,
                .Response,
                "\(meta.name) declares \(response) as its Response, which is not a response type"
            )
        }
    }

    /// Every pairing in the catalog answers on the opcode one above the request's.
    func testDeclaredResponseOpcodeFollowsTheRequest() {
        for (meta, response) in pairings() {
            XCTAssertEqual(
                response.props.opCode,
                meta.opCode &+ 1,
                "\(meta.name) (opcode \(meta.opCode)) declares \(response) (opcode \(response.props.opCode))"
            )
        }
    }

    /// A reply arrives on the characteristic the request went out on, which is where the transport
    /// watches for it.
    func testDeclaredResponseSharesTheRequestCharacteristic() {
        for (meta, response) in pairings() {
            XCTAssertEqual(
                response.props.characteristic,
                meta.characteristic,
                "\(meta.name) declares \(response), which answers on a different characteristic"
            )
        }
    }

    func testCatalogCoversTheExpectedNumberOfRequests() {
        XCTAssertEqual(pairings().count, 131)
    }

    private func pairings() -> [(MessageMetadata, any Message.Type)] {
        requests.compactMap { meta in
            guard let requestType = meta.type as? any PumpRequest.Type else { return nil }
            return (meta, requestType.responseType)
        }
    }
}
