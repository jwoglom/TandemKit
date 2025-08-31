import XCTest
@testable import TandemCore

final class Jpake2ResponseTests: XCTestCase {
    // ./android-2024-02-29-6char2.csv
    func test167cargoResponseSplit() {
        MessageTester.initPumpState("test", 0)
        let centralChallengeHash = Data(hexadecimalString: "0300174104634f4cfde021623a609c98311ae7508b41126542de029b76b1781de8f3db6e723950a8e64715c97cf44d80a6976b91ab846cdbf732bf160c1c0223f0a674a4734104732ff948fed2dbb06806502a7ae7ca0afdf1991eab79c866ff53e9d23bd4d1886f3cb55663b7979947f6a96d52511ac843b9d28b20805f263365bc50d1b93d7620bec12ade679a6b482ba5bfbe973e91dcdcd87bc3ab04090803db2945cca39e4c")!
        let expected = Jpake2Response(appInstanceId: 0, centralChallengeHash: centralChallengeHash)

        let parsed: Jpake2Response = MessageTester.test(
            "00022502aa00000300174104634f4cfde021623a609c98311ae7508b41126542de029b76b1781de8f3db6e723950a8e64715c97cf44d80a6976b91ab846cdbf732bf160c1c0223f0a674a4734104732ff948fed2dbb06806502a7ae7ca0afdf1991eab79c866ff53e9d23bd4d1886f3cb55663b7979947f6a96d52511ac843b9d28b20805f263365bc50d1b93d7620bec12ade679a6b482ba5bfbe973e91dcdcd87bc3ab04090803db2945cca39e4c9be8",
            2,
            10,
            .AUTHORIZATION_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        MessageTester.assertHexEquals(expected.centralChallengeHash, parsed.centralChallengeHash)
    }
}
