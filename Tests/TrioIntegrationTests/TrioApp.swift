import Foundation
@testable import TandemKit
import XCTest

/// Trio running in the simulator on the virtual pump build of TandemKit, launched by
/// scripts/trio-test.sh: its driver reached through the control channel, and what Trio made of
/// the driver's reports read from its data container.
struct TrioApp {
    /// The port Trio's TandemKit listens on (`TANDEMKIT_VIRTUAL_PUMP_CONTROL` in the app).
    static let controlPortVariable = "TRIO_CONTROL_PORT"
    /// The app's data container, a host path the simulator's test process can read.
    static let dataContainerVariable = "TRIO_DATA_CONTAINER"

    let controlPort: UInt16
    let dataContainer: URL

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws -> TrioApp {
        guard let port = environment[controlPortVariable].flatMap(UInt16.init),
              let container = environment[dataContainerVariable]
        else {
            throw XCTSkip("\(controlPortVariable) / \(dataContainerVariable) not set; run via scripts/trio-test.sh")
        }
        return TrioApp(controlPort: port, dataContainer: URL(fileURLWithPath: container))
    }

    func connectControl() throws -> VirtualPumpControl.Client {
        try VirtualPumpControl.Client(port: controlPort)
    }

    /// `preferences.json`'s `bolusIncrement`, which Trio sets to the pump's smallest bolus when the
    /// pump manager loads, and rounds every stored bolus to.
    func bolusIncrement() throws -> Double {
        try XCTUnwrap(documentsJSON("preferences.json")["bolusIncrement"] as? Double, "preferences.json has no bolusIncrement")
    }

    /// `settings/settings.json`'s `maxBasal`; Trio drops a reported temp basal above it.
    func maxBasal() throws -> Double {
        try XCTUnwrap(documentsJSON("settings/settings.json")["maxBasal"] as? Double, "settings/settings.json has no maxBasal")
    }

    func store() throws -> TrioStore {
        try TrioStore(dataContainer: dataContainer)
    }

    private func documentsJSON(_ path: String) throws -> [String: Any] {
        let url = dataContainer.appendingPathComponent("Documents").appendingPathComponent(path)
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any], "\(path) is not a JSON object")
    }
}
