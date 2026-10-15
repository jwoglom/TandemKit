@testable import TandemKit
import XCTest

final class DangerousRequestTests: XCTestCase {
    private func names(where flag: (MessageProps) -> Bool) -> Set<String> {
        Set(MessageRegistry.all.filter { flag($0.type.props) }.map(\.name))
    }

    func testOnlyFactoryResetsAndShelfModeAreNeverInvoked() {
        XCTAssertEqual(
            names { $0.dangerousDoNotInvoke },
            ["ActivateShelfModeRequest", "FactoryResetRequest", "FactoryResetBRequest"]
        )
    }

    func testOnlyDisconnectPumpAsksForExplicitConfirmation() {
        XCTAssertEqual(names { $0.dangerousRequireExplicitConfirmation != nil }, ["DisconnectPumpRequest"])
        XCTAssertEqual(
            DisconnectPumpRequest.props.dangerousRequireExplicitConfirmation,
            "this will disconnect your pump from your phone"
        )
    }
}
