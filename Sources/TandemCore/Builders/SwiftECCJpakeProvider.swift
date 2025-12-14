import Foundation

#if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
    import BigInt
    import CryptoKit
    import SwiftECC

    final class SwiftECCJpakeProvider: JpakeProvider {
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
            rand: @escaping JpakeProvider.RandomBytesGenerator
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
#endif
