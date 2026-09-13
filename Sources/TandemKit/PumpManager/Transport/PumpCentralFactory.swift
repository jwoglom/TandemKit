import Foundation

enum PumpCentralFactory {
    /// `host:port` of a faketandem virtual GATT link. Debug builds only; release builds ignore it.
    static let virtualPumpEnvironmentVariable = "TANDEMKIT_VIRTUAL_PUMP"

    /// The central `TandemPumpManager.init(state:)` uses, so Loop and Trio need no changes to talk
    /// to a virtual pump: set the environment variable on the app process and every pump manager
    /// they create goes over the socket instead of CoreBluetooth.
    static func makeDefault(environment: [String: String] = ProcessInfo.processInfo.environment) -> PumpCentral {
        #if DEBUG
        if let address = environment[virtualPumpEnvironmentVariable] {
            if let endpoint = SocketPumpEndpoint(address) {
                return SocketPumpCentral(endpoint: endpoint)
            }
            TandemLogger(category: "PumpCentralFactory")
                .error("Ignoring \(virtualPumpEnvironmentVariable)=\(address): expected host:port")
        }
        #endif
        return CoreBluetoothCentral()
    }
}
