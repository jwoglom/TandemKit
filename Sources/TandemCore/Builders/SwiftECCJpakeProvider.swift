#if canImport(SwiftECC) && canImport(BigInt)
import BigInt
import CryptoKit
import Foundation
import SwiftECC

final class SwiftECCJpakeProvider {
    let pairingCode: String
    private var cli: EcJpake

    init(
        pairingCode: String,
        step _: JpakeStep? = nil,
        clientRound1 _: Data? = nil,
        serverRound1 _: Data? = nil,
        clientRound2 _: Data? = nil,
        serverRound2 _: Data? = nil,
        derivedSecret _: Data?,
        rand: @escaping (Int) -> Data
    ) {
        self.pairingCode = pairingCode
        cli = EcJpake(
            role: .client,
            password: JpakeAuthBuilder.pairingCodeToBytes(pairingCode),
            random: rand
        )
    }

    func makeRound1() -> Data {
        cli.getRound1()
    }

    func readRound1(_ data: Data) {
        cli.readRound1(data)
    }

    func makeRound2() -> Data {
        cli.getRound2()
    }

    func readRound2(_ data: Data) {
        cli.readRound2(data)
    }

    func deriveSecret() -> Data {
        cli.deriveSecret()
    }
}

#else
import Foundation

// Linux/desktop SwiftPM builds have no SwiftECC/BigInt, so the JPAKE crypto
// cannot run. This stub keeps `JpakeAuthBuilder` (and its callers in the iOS
// integration layer) type-checkable, but any attempt to actually perform the
// pairing handshake traps loudly rather than returning fabricated crypto.
final class SwiftECCJpakeProvider {
    let pairingCode: String

    init(
        pairingCode: String,
        step _: JpakeStep? = nil,
        clientRound1 _: Data? = nil,
        serverRound1 _: Data? = nil,
        clientRound2 _: Data? = nil,
        serverRound2 _: Data? = nil,
        derivedSecret _: Data?,
        rand _: @escaping (Int) -> Data
    ) {
        self.pairingCode = pairingCode
    }

    private func unavailable() -> Never {
        fatalError("JPAKE pairing is unavailable on this platform: SwiftECC/BigInt are not compiled into the Linux SwiftPM build.")
    }

    func makeRound1() -> Data { unavailable() }
    func readRound1(_: Data) { unavailable() }
    func makeRound2() -> Data { unavailable() }
    func readRound2(_: Data) { unavailable() }
    func deriveSecret() -> Data { unavailable() }
}

#endif
