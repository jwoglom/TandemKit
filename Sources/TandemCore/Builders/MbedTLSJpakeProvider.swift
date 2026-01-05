import Foundation

#if canImport(MbedTLS) && canImport(MbedTLSShim)

    final class MbedTLSJpakeProvider: JpakeProvider {
        let pairingCode: String

        private let adapter: MbedTLSJpakeAdapter
        private let log = TandemLogger(category: "MbedTLSJpakeProvider")

        init(
            pairingCode: String,
            step _: JpakeStep? = nil,
            clientRound1 _: Data? = nil,
            serverRound1 _: Data? = nil,
            clientRound2 _: Data? = nil,
            serverRound2 _: Data? = nil,
            derivedSecret _: Data?,
            rand: @escaping JpakeProvider.RandomBytesGenerator
        ) throws {
            self.pairingCode = pairingCode
            adapter = try MbedTLSJpakeAdapter(
                password: JpakeAuthBuilder.pairingCodeToBytes(pairingCode),
                random: rand
            )
        }

        func makeRound1() -> Data {
            perform("round1") { try adapter.round1() }
        }

        func readRound1(_ data: Data) {
            perform("readRound1") { try adapter.consumeRound1(data) }
        }

        func makeRound2() -> Data {
            perform("round2") { try adapter.round2() }
        }

        func readRound2(_ data: Data) {
            perform("readRound2") { try adapter.consumeRound2(data) }
        }

        func deriveSecret() -> Data {
            perform("deriveSecret") { try adapter.deriveSecret() }
        }

        private func perform(_ label: String, _ action: () throws -> Data) -> Data {
            do {
                return try action()
            } catch let error as MbedTLSJpakeError {
                log.error("[MbedTLSJpakeProvider] Failed to \(label): \(error)")
                return Data()
            } catch {
                log.error("[MbedTLSJpakeProvider] Failed to \(label): \(error)")
                return Data()
            }
        }

        private func perform(_ label: String, _ action: () throws -> Void) {
            do {
                try action()
            } catch let error as MbedTLSJpakeError {
                log.error("[MbedTLSJpakeProvider] Failed to \(label): \(error)")
            } catch {
                log.error("[MbedTLSJpakeProvider] Failed to \(label): \(error)")
            }
        }
    }

#endif
