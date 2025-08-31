import XCTest
@testable import TandemCore

final class Jpake2RequestTests: XCTestCase {
    func test167cargoThirdchallengeSplit() {
        MessageTester.initPumpState("test", 0)
        let centralChallengeHex = "4104cf87b9389904510a1dc60a01b0bcfcfbcd15787aa9af7fc5ec130d29b422799cc0faeec10f0d1800052c882a4100becee73d5c98c31d264428026f23994ecfdf41040f3dbda4ba90c341c891376502823e405adf32dc3c7039d7399e1b4953a435d056fd2a1ed2a834f8f40c6215f503dd470c6862d63e2fa47c52b90e77e6cd725920f12b8b1ffadb0c65b53eba740aa751f3c59912e19a5f2e6622619797fe770c0b"
        let expectedCargo = Data(hexadecimalString: "0000" + centralChallengeHex)!
        let expected = Jpake2Request(cargo: expectedCargo)

        let parsed: Jpake2Request = MessageTester.test(
            "09022402a700004104cf87b9389904510a1dc60a",
            2,
            10,
            .AUTHORIZATION_CHARACTERISTICS,
            expected,
            "080201b0bcfcfbcd15787aa9af7fc5ec130d29b4",
            "070222799cc0faeec10f0d1800052c882a4100be",
            "0602cee73d5c98c31d264428026f23994ecfdf41",
            "0502040f3dbda4ba90c341c891376502823e405a",
            "0402df32dc3c7039d7399e1b4953a435d056fd2a",
            "03021ed2a834f8f40c6215f503dd470c6862d63e",
            "02022fa47c52b90e77e6cd725920f12b8b1ffadb",
            "01020c65b53eba740aa751f3c59912e19a5f2e66",
            "000222619797fe770c0b4106"
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
        XCTAssertEqual(0, parsed.appInstanceId)
        XCTAssertEqual(165, parsed.centralChallenge.count)
        MessageTester.assertHexEquals(Data(hexadecimalString: centralChallengeHex)!, parsed.centralChallenge)
    }
}
