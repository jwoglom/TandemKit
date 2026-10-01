import Harmonize
import XCTest

final class TestsDoNotUseMocks: XCTestCase {
    func testTestFilesDoNotImportAMockingLibrary() {
        TandemHarmonize.testCode.sources().assertFalse(rule: Self.rule) { file in
            file.imports().contains { Self.mockingLibraries.contains($0.name) }
        }
    }

    private static let mockingLibraries = ["Cuckoo", "Mockingbird", "SwiftyMocky", "OCMock", "Mockolo", "MockSwift"]

    private static let rule = Rule(
        description: "Tests never use mocking libraries.",
        rationale: """
            Manager tests run real command sequences through StubPumpBluetooth, which answers with constructed
            responses, and the integration tests run the driver against faketandem. A generated mock asserts on
            the calls it saw instead, so a reordered or dropped pump command still passes.
            """,
        fixHint: "Drive TandemPumpManager through StubPumpBluetooth (init(state:bluetooth:)), or hand-write a fake for the protocol under test.",
        badExample: "import Cuckoo\nlet bluetooth = MockPumpBluetoothConnection()",
        goodExample: "let bluetooth = StubPumpBluetooth()\nlet manager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: bluetooth)"
    )
}
