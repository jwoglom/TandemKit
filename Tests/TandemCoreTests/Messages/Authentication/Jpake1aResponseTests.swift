import XCTest
@testable import TandemCore

final class Jpake1aResponseTests: XCTestCase {
    func test167cargoResponseSplit() {
        MessageTester.initPumpState("test", 0)
        let expected = Jpake1aResponse(cargo: Data(hexadecimalString: "000041048139ce7f5012e2c32c8be4a3eb4511f9bd1c471bed0f1ccf623a2a0399e4f7de35e00c2ae0d8b42d173183ed624b276caf83bb68ce665f1acab03b758056dbca41047a0e04939c0089e44de6268e0018c390c5fb1d4d832a52fd67dcd003d31fd576ff3eb7a838d0b389a0d2544fc740119aced931ac6385ab8ca620e0756d17f5fb20b570ea8e5460cc45b1b733c2edb2bc32a206f1aab956da044e01ba1be6d09913")!)

        let parsed: Jpake1aResponse = MessageTester.test(
            "00002100a7000041048139ce7f5012e2c32c8be4a3eb4511f9bd1c471bed0f1ccf623a2a0399e4f7de35e00c2ae0d8b42d173183ed624b276caf83bb68ce665f1acab03b758056dbca41047a0e04939c0089e44de6268e0018c390c5fb1d4d832a52fd67dcd003d31fd576ff3eb7a838d0b389a0d2544fc740119aced931ac6385ab8ca620e0756d17f5fb20b570ea8e5460cc45b1b733c2edb2bc32a206f1aab956da044e01ba1be6d099132562",
            0,
            10,
            .AUTHORIZATION_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }

    func testOneoffResponse() {
        MessageTester.initPumpState("test", 0)
        let expected = Jpake1aResponse(cargo: Data(hexadecimalString: "0100410441e099e06fda4ba1ea6b6e727e4790fee1303018a97a8a1eed5093f2dab4cbced4ac1f392fbff14a89cc7b8ee06fdadd09d4b67222e1af69612ae3b727679ae94104c9dd154dd328e468cda64f39d6c5e5dfc6645fa60883cee41ca536d22fd6f5ddf12ed045c8eff2edf59f13249268cf403e19585711e8393872954632e896fbb820a8c41909ae5120fa17fc0716ca65dc5fb440e94b78ce9c82c997a0fc4f855d41")!)

        let parsed: Jpake1aResponse = MessageTester.test(
            "00002100a70100410441e099e06fda4ba1ea6b6e727e4790fee1303018a97a8a1eed5093f2dab4cbced4ac1f392fbff14a89cc7b8ee06fdadd09d4b67222e1af69612ae3b727679ae94104c9dd154dd328e468cda64f39d6c5e5dfc6645fa60883cee41ca536d22fd6f5ddf12ed045c8eff2edf59f13249268cf403e19585711e8393872954632e896fbb820a8c41909ae5120fa17fc0716ca65dc5fb440e94b78ce9c82c997a0fc4f855d416119",
            0,
            10,
            .AUTHORIZATION_CHARACTERISTICS,
            expected
        )

        MessageTester.assertHexEquals(expected.cargo, parsed.cargo)
    }
}
