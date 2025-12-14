import Foundation
@testable import TandemCore
import XCTest

#if canImport(MbedTLS) && canImport(MbedTLSShim) && canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)

    final class MbedTLSJpakeProviderTests: XCTestCase {
        func testRoundTripMatchesSwiftECC() throws {
            let pairingCode = "123456"
            let clientRng = DeterministicRandom()
            let serverRng = DeterministicRandom()

            let provider = try XCTUnwrap(
                MbedTLSJpakeProvider(
                    pairingCode: pairingCode,
                    derivedSecret: nil,
                    rand: clientRng.next
                )
            )

            let server = EcJpake(
                role: .server,
                password: JpakeAuthBuilder.pairingCodeToBytes(pairingCode),
                random: serverRng.next
            )

            let clientRound1 = provider.makeRound1()
            let serverRound1 = server.getRound1()

            provider.readRound1(serverRound1)
            server.readRound1(clientRound1)

            let clientRound2 = provider.makeRound2()
            let serverRound2 = server.getRound2()

            provider.readRound2(serverRound2)
            server.readRound2(clientRound2)

            let clientSecret = provider.deriveSecret()
            let serverSecret = server.deriveSecret()

            XCTAssertFalse(clientSecret.isEmpty)
            XCTAssertEqual(clientSecret, serverSecret)
        }
    }

    private final class DeterministicRandom {
        private var state: UInt64 = 0x0123_4567_89ab_cdef

        func next(count: Int) -> Data {
            var output = Data(count: count)
            for index in 0 ..< count {
                state = state &* 6364136223846793005 &+ 1
                output[index] = UInt8(truncatingIfNeeded: state >> 24)
            }
            return output
        }
    }

#endif
