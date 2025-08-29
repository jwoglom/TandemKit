import XCTest
@testable import TandemCore

final class Jpake1aRequestTests: XCTestCase {
    func test167cargoSplit() {
        MessageTester.initPumpState("test", 0)
        let centralChallengeHex = "4104e6acd57cf25de99d99b0552a7a47f68f294a4728d6f0f30322fff4ab1c047efadaa6e9980c28a13cc4eb87064e891916ed27a4881f5d819a3a6c9f55ce4cb08041040fd63cf9c8962e342bac550585ce91b7412b2fcb301bdd28bc2a7625a7961bf1c8c19841fd091e92029e9ba785c7224a183c398e336bb11f36bcec71e83d958d20404e815aca591c128e9bb49751ec080d3e4bd73fdf63d5a106577aaa66d3a79f"
        let expectedCargo = Data(hexadecimalString: "0000" + centralChallengeHex)!
        let expected = Jpake1aRequest(cargo: expectedCargo)

        let parsed: Jpake1aRequest = MessageTester.test(
            "09002000a700004104e6acd57cf25de99d99b055",
            0,
            10,
            .AUTHORIZATION_CHARACTERISTICS,
            expected,
            "08002a7a47f68f294a4728d6f0f30322fff4ab1c",
            "0700047efadaa6e9980c28a13cc4eb87064e8919",
            "060016ed27a4881f5d819a3a6c9f55ce4cb08041",
            "0500040fd63cf9c8962e342bac550585ce91b741",
            "04002b2fcb301bdd28bc2a7625a7961bf1c8c198",
            "030041fd091e92029e9ba785c7224a183c398e33",
            "02006bb11f36bcec71e83d958d20404e815aca59",
            "01001c128e9bb49751ec080d3e4bd73fdf63d5a1",
            "000006577aaa66d3a79f4541"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.appInstanceId)
        XCTAssertEqual(165, parsed.centralChallenge.count)
        MessageTester.assertHexEquals(Data(hexadecimalString: centralChallengeHex)!, parsed.centralChallenge)
    }
}
