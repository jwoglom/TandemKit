#if TANDEMKIT_VIRTUAL_PUMP
import Foundation
@testable import TandemKit
import XCTest

final class SocketListenerTests: XCTestCase {
    func testAStoppedListenerTakesNoneOfTheNextListenersConnections() throws {
        for attempt in 1 ... 50 {
            let strays = DispatchSemaphore(value: 0)
            // Stopped before its accept thread has run: the window in which the thread used to pick up
            // a descriptor number the stop had freed.
            try SocketListener(name: "stopped") { _ in strays.signal() }.stop()

            let accepted = DispatchSemaphore(value: 0)
            let next = try SocketListener(name: "next") { _ in accepted.signal() }
            defer { next.stop() }
            let link = try SocketLink(connectTo: SocketPumpEndpoint(host: "127.0.0.1", port: next.port))
            defer { link.close() }

            guard accepted.wait(timeout: .now() + 2) == .success else {
                let taken = strays.wait(timeout: .now()) == .success ? ", the stopped one took it" : ""
                return XCTFail("attempt \(attempt): the next listener never saw its connection\(taken)")
            }
        }
    }
}
#endif
