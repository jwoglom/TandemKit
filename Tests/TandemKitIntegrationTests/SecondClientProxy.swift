import CoreBluetooth
import Foundation
@testable import TandemKit

/// Sits between the driver's virtual CoreBluetooth and faketandem's GATT socket and passes every
/// message through. A pump has one link to the phone, shared by every app on it that talks to the
/// pump, and iOS notifies each subscribed app of every response; through `onPumpNotification` a
/// test delivers what another app's requests would also have brought the driver.
final class SecondClientProxy {
    private let upstream: SocketPumpEndpoint
    private let lock = NSLock()
    private var listener: SocketListener?
    private var links: [SocketLink] = []
    private var _onDriverWrite: ((CBUUID, Data) -> Void)?
    private var _onPumpNotification: ((CBUUID, Data) -> [(CBUUID, Data)])?

    /// Each write the driver sends, from a proxy thread, before it is forwarded.
    var onDriverWrite: ((CBUUID, Data) -> Void)? {
        get { locked { _onDriverWrite } }
        set { locked { _onDriverWrite = newValue } }
    }

    /// Each notification the pump sends the driver, from a proxy thread; what it returns goes to the
    /// driver in its place, in order.
    var onPumpNotification: ((CBUUID, Data) -> [(CBUUID, Data)])? {
        get { locked { _onPumpNotification } }
        set { locked { _onPumpNotification = newValue } }
    }

    var endpoint: SocketPumpEndpoint {
        SocketPumpEndpoint(host: "127.0.0.1", port: listener?.port ?? 0)
    }

    init(upstream: SocketPumpEndpoint) throws {
        self.upstream = upstream
        listener = try SocketListener(name: "SecondClientProxy") { [weak self] driver in
            self?.relay(driver)
        }
    }

    func stop() {
        listener?.stop()
        for link in locked({ links }) {
            link.shutdown()
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func relay(_ driver: SocketLink) {
        guard let pump = try? SocketLink(connectTo: upstream) else {
            driver.close()
            return
        }
        locked { links += [driver, pump] }

        let pumpSide = Thread { [weak self] in
            while let line = try? pump.readLine(timeout: nil) {
                for out in self?.fromPump(line) ?? [line] {
                    try? driver.send(line: out)
                }
            }
            driver.shutdown()
            pump.close()
        }
        pumpSide.start()

        while let line = try? driver.readLine(timeout: nil) {
            if let (characteristic, value) = Self.decode(line, type: "write") {
                onDriverWrite?(characteristic, value)
            }
            try? pump.send(line: line)
        }
        pump.shutdown()
        driver.close()
    }

    private func fromPump(_ line: Data) -> [Data] {
        guard let hook = onPumpNotification, let (characteristic, value) = Self.decode(line, type: "notify") else {
            return [line]
        }
        return hook(characteristic, value).compactMap { characteristic, value in
            try? JSONSerialization.data(withJSONObject: [
                "type": "notify",
                "characteristic": characteristic.virtualPumpString,
                "value": value.hexadecimalString,
            ])
        }
    }

    private static func decode(_ line: Data, type: String) -> (CBUUID, Data)? {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              message["type"] as? String == type,
              let characteristic = (message["characteristic"] as? String).flatMap(CBUUID.virtualPump),
              let value = (message["value"] as? String).flatMap({ Data(hexadecimalString: $0) })
        else {
            return nil
        }
        return (characteristic, value)
    }
}
