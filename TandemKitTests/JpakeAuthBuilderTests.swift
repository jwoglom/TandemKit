import Testing
@testable import TandemKit
import Foundation

struct JpakeAuthBuilderTests {
    @Test func pairingCodeConversion() async throws {
        let bytes = JpakeAuthBuilder.pairingCodeToBytes("123456")
        #expect(bytes == Data([49,50,51,52,53,54]))
    }

    @Test func initialStep() async throws {
        #expect(JpakeAuthBuilder.decideInitialStep(derivedSecret: nil) == .BOOTSTRAP_INITIAL)
        #expect(JpakeAuthBuilder.decideInitialStep(derivedSecret: Data([1])) == .CONFIRM_INITIAL)
    }

    @Test func nextRequestBootstrap() async throws {
        let builder = JpakeAuthBuilder(pairingCode: "123456", derivedSecret: nil, rand: AllZeroSecureRandom.nextBytes)
        let req = builder.nextRequest()
        #expect(req is Jpake1aRequest)
        let chal = (req as! Jpake1aRequest).centralChallenge
        #expect(chal.count == 165)
        #expect(builder.step == .ROUND_1A_SENT)
    }
}
