import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TandemKit
import XCTest

/// Loop running in the simulator on the virtual pump build of TandemKit, launched by
/// scripts/app-launcher.py: its driver reached through the control channel, and what Loop made of
/// the driver's reports read from its containers.
struct LoopApp {
    /// scripts/loop-test.sh sets it to the launcher's address.
    static let launcherVariable = "LOOP_LAUNCHER_URL"

    let launcher: URL
    /// The port Loop's TandemKit listens on (`TANDEMKIT_VIRTUAL_PUMP_CONTROL` in the app).
    let controlPort: UInt16
    /// Host paths the simulator's test process can read.
    let dataContainer: URL
    /// Loop's store and the UserDefaults suite its settings and onboarding live in.
    let groupContainer: URL

    /// A new install of Loop, seeded to start set up with an unpaired Tandem pump. `files`, keyed by
    /// path in the data container, are written over the seed and `groupDefaults` set in Loop's app
    /// group suite, before Loop first launches.
    static func launchNew(
        name: String,
        files: [String: String],
        groupDefaults: [String: Any],
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> LoopApp {
        guard let launcher = environment[launcherVariable].flatMap(URL.init(string:)) else {
            throw XCTSkip("\(launcherVariable) not set; run via scripts/loop-test.sh")
        }
        var install = URLComponents(url: launcher.appendingPathComponent("install"), resolvingAgainstBaseURL: false)!
        install.queryItems = [URLQueryItem(name: "name", value: name)]
        let defaults = try PropertyListSerialization.data(fromPropertyList: groupDefaults, format: .xml, options: 0)
        _ = try post(install.url!, ["files": files, "defaults": ["group": String(decoding: defaults, as: UTF8.self)]])
        return try launch(launcher, "launch", ["arguments": arguments])
    }

    /// Loop stopped and started again on the same data, with the same launch arguments, as after
    /// the system ended it. `files` are written over that data first, as `launchNew`'s are.
    func relaunched(files: [String: String] = [:]) throws -> LoopApp {
        try Self.launch(launcher, "relaunch", ["files": files])
    }

    /// With `sample`, the launcher first records a few seconds of Loop's stacks into the test's logs.
    func stop(sample: Bool = false) throws {
        _ = try Self.post(launcher.appendingPathComponent("stop"), ["sample": sample])
    }

    func connectControl() throws -> VirtualPumpControl.Client {
        try VirtualPumpControl.Client(port: controlPort)
    }

    /// The driver state Loop last saved, which a relaunch restores.
    func savedPumpManagerState() throws -> TandemPumpManagerState? {
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: pumpManagerStateURL), format: nil)
        return ((plist as? [String: Any])?["state"] as? [String: Any]).map(TandemPumpManagerState.init(rawValue:))
    }

    /// Whether Loop has a pump manager saved to restore at its next launch; deleting one removes the file.
    func hasSavedPumpManager() -> Bool {
        FileManager.default.fileExists(atPath: pumpManagerStateURL.path)
    }

    private var pumpManagerStateURL: URL {
        dataContainer.appendingPathComponent("Documents/PumpManagerState.plist")
    }

    func store() throws -> LoopStore {
        try LoopStore(groupContainer: groupContainer)
    }

    private struct Launched: Decodable {
        let controlPort: UInt16
        let dataContainer: String
        let groupContainer: String
    }

    private static func launch(_ launcher: URL, _ path: String, _ body: [String: Any]) throws -> LoopApp {
        let launched = try JSONDecoder().decode(Launched.self, from: post(launcher.appendingPathComponent(path), body))
        guard !launched.groupContainer.isEmpty else {
            throw VirtualPumpControl.ControlError("app-launcher found no app group container for Loop")
        }
        return LoopApp(
            launcher: launcher,
            controlPort: launched.controlPort,
            dataContainer: URL(fileURLWithPath: launched.dataContainer),
            groupContainer: URL(fileURLWithPath: launched.groupContainer)
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
        let (data, response) = try box.wait("app-launcher \(url.path)", timeout: 310).get()
        guard response.statusCode == 200 else {
            let reason = (try? JSONDecoder().decode(LauncherError.self, from: data))?.error ?? String(decoding: data, as: UTF8.self)
            throw VirtualPumpControl.ControlError("app-launcher \(url.path): \(reason)")
        }
        return data
    }
}
