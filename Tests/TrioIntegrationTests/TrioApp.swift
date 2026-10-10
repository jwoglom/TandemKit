import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TandemKit
import XCTest

/// Trio running in the simulator on the virtual pump build of TandemKit, launched by
/// scripts/trio-launcher.py: its driver reached through the control channel, and what Trio made of
/// the driver's reports read from its data container.
struct TrioApp {
    /// scripts/trio-test.sh sets it to the launcher's address.
    static let launcherVariable = "TRIO_LAUNCHER_URL"

    let launcher: URL
    /// The port Trio's TandemKit listens on (`TANDEMKIT_VIRTUAL_PUMP_CONTROL` in the app).
    let controlPort: UInt16
    /// A host path the simulator's test process can read.
    let dataContainer: URL

    /// A new install of Trio, seeded to start set up with an unpaired Tandem pump. `files`, keyed by
    /// path in the data container, are written over the seed before Trio first launches.
    static func launchNew(
        name: String,
        files: [String: String],
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> TrioApp {
        guard let launcher = environment[launcherVariable].flatMap(URL.init(string:)) else {
            throw XCTSkip("\(launcherVariable) not set; run via scripts/trio-test.sh")
        }
        var install = URLComponents(url: launcher.appendingPathComponent("install"), resolvingAgainstBaseURL: false)!
        install.queryItems = [URLQueryItem(name: "name", value: name)]
        _ = try post(install.url!, ["files": files])
        return try launch(launcher, "launch", ["arguments": arguments])
    }

    /// Trio stopped and started again on the same data, with the same launch arguments, as after
    /// the system ended it.
    func relaunched() throws -> TrioApp {
        try Self.launch(launcher, "relaunch", [:])
    }

    func stop() throws {
        _ = try Self.post(launcher.appendingPathComponent("stop"), [:])
    }

    func connectControl() throws -> VirtualPumpControl.Client {
        try VirtualPumpControl.Client(port: controlPort)
    }

    /// `settings/settings.json`'s `maxBasal`; Trio drops a reported temp basal above it.
    func maxBasal() throws -> Double {
        try XCTUnwrap(documentsJSON("settings/settings.json")["maxBasal"] as? Double, "settings/settings.json has no maxBasal")
    }

    /// The driver state Trio last saved, which a relaunch restores.
    func savedPumpManagerState() throws -> TandemPumpManagerState? {
        let url = documents.appendingPathComponent("PumpManagerState.plist")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return ((plist as? [String: Any])?["state"] as? [String: Any]).map(TandemPumpManagerState.init(rawValue:))
    }

    func store() throws -> TrioStore {
        try TrioStore(dataContainer: dataContainer)
    }

    private var documents: URL {
        dataContainer.appendingPathComponent("Documents")
    }

    private func documentsJSON(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: documents.appendingPathComponent(path))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any], "\(path) is not a JSON object")
    }

    private struct Launched: Decodable {
        let controlPort: UInt16
        let dataContainer: String
    }

    private static func launch(_ launcher: URL, _ path: String, _ body: [String: Any]) throws -> TrioApp {
        let launched = try JSONDecoder().decode(Launched.self, from: post(launcher.appendingPathComponent(path), body))
        return TrioApp(
            launcher: launcher,
            controlPort: launched.controlPort,
            dataContainer: URL(fileURLWithPath: launched.dataContainer)
        )
    }

    private struct LauncherError: Decodable {
        let error: String
    }

    /// An install and a launch take a minute or two on a CI runner.
    private static func post(_ url: URL, _ body: [String: Any]) throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let box = ResultBox<Result<(Data, HTTPURLResponse), Error>>()
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                return box.set(.failure(error))
            }
            box.set(.success((data ?? Data(), response as! HTTPURLResponse)))
        }.resume()
        let (data, response) = try box.wait("trio-launcher \(url.path)", timeout: 310).get()
        guard response.statusCode == 200 else {
            let reason = (try? JSONDecoder().decode(LauncherError.self, from: data))?.error ?? String(decoding: data, as: UTF8.self)
            throw VirtualPumpControl.ControlError("trio-launcher \(url.path): \(reason)")
        }
        return data
    }
}
