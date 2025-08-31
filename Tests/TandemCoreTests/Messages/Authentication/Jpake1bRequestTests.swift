import XCTest
@testable import TandemCore

final class Jpake1bRequestTests: XCTestCase {
    func test167cargoPumpchallengeSplit() {
        MessageTester.initPumpState("test", 0)
        let centralChallengeHex = "4104faf1c1c7737041a88872ba435c79fe67b14fd793f452b4e1a41cf4e8569ed1b67c9ab0523d97f79a536ab498d23d0d941443b319402f9406393c1c800c203cac41042dd19aad7f25eabd064b6f2ee474ac900fd61550aef781eca29b4e9fdb921a1ecd395e88cc0ee6f09c961d49e3e31d22cb178ea63ce560ebe71127521b6f7d3320303b8172c67d855dbdeeac9a32f1f067ea4924b95701563021874c2f78785e6a"
        let expectedCargo = Data(hexadecimalString: "0000" + centralChallengeHex)!
        let expected = Jpake1bRequest(cargo: expectedCargo)

        let parsed: Jpake1bRequest = MessageTester.test(
            "09012201a700004104faf1c1c7737041a88872ba",
            1,
            10,
            .AUTHORIZATION_CHARACTERISTICS,
            expected,
            "0801435c79fe67b14fd793f452b4e1a41cf4e856",
            "07019ed1b67c9ab0523d97f79a536ab498d23d0d",
            "0601941443b319402f9406393c1c800c203cac41",
            "0501042dd19aad7f25eabd064b6f2ee474ac900f",
            "0401d61550aef781eca29b4e9fdb921a1ecd395e",
            "030188cc0ee6f09c961d49e3e31d22cb178ea63c",
            "0201e560ebe71127521b6f7d3320303b8172c67d",
            "0101855dbdeeac9a32f1f067ea4924b957015630",
            "000121874c2f78785e6afd38"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.appInstanceId)
        XCTAssertEqual(165, parsed.centralChallenge.count)
        MessageTester.assertHexEquals(Data(hexadecimalString: centralChallengeHex)!, parsed.centralChallenge)
    }

    func testGetEccDetails() {
        let centralChallengeV2RequestBytes = Data(hexadecimalString: "4104faf1c1c7737041a88872ba435c79fe67b14fd793f452b4e1a41cf4e8569ed1b67c9ab0523d97f79a536ab498d23d0d941443b319402f9406393c1c800c203cac41042dd19aad7f25eabd064b6f2ee474ac900fd61550aef781eca29b4e9fdb921a1ecd395e88cc0ee6f09c961d49e3e31d22cb178ea63ce560ebe71127521b6f7d3320303b8172c67d855dbdeeac9a32f1f067ea4924b95701563021874c2f78785e6a")!
        let challengeV2ResponseBytes = Data(hexadecimalString: "4104dc82c0b7f60e601ebed41ebafac79dac6b23055d6c2949e3bd7643acd951c400ca60513dbff125da5238e0a7eee27ff4533afded0725ad2804987c90646ade0f41048177dda93af133fcfcc3a78408af82370d76af3ecfe78bc16c732310ed00b188ae0b4c2769876ac29d6c65a205c96dd518e3166aa57d61bca1a6756aabbe4f6920c472ac523abdd69e678149c128daa073861c6c9371f04254d158b6481f2226ba")!
        let reqCurve = getCurve(centralChallengeV2RequestBytes)
        let respCurve = getCurve(challengeV2ResponseBytes)
        XCTAssertEqual(reqCurve.namedCurve, respCurve.namedCurve)
        // XCTAssertEqual(reqCurve.curveId, respCurve.curveId)
    }

    private func getCurve(_ data: Data) -> (namedCurve: Int, curveId: Int) {
        let namedCurve = Int(data[0])
        let curveId = Int(data[1]) << 8 | Int(data[2])
        return (namedCurve, curveId)
    }
}
