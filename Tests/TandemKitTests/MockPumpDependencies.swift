import Foundation
import XCTest
@testable import TandemKit
@testable import TandemCore

final class MockPeripheralManager {
    struct Entry {
        let message: Message
    }

    private(set) var sentMessages: [Entry] = []
    private var responseQueue: [(Message.Type, Result<Message, Error>)] = []
    private let lock = NSLock()

    func enqueueResponse<Response: Message>(for requestType: Message.Type, response: Response) {
        lock.lock()
        responseQueue.append((requestType, .success(response)))
        lock.unlock()
    }

    func enqueueError(for requestType: Message.Type, error: Error) {
        lock.lock()
        responseQueue.append((requestType, .failure(error)))
        lock.unlock()
    }

    func send(message: Message) throws -> Message {
        lock.lock()
        sentMessages.append(Entry(message: message))

        guard let index = responseQueue.firstIndex(where: { requestType, _ in requestType == type(of: message) }) else {
            lock.unlock()
            fatalError("No mock response registered for request type \(String(describing: type(of: message)))")
        }

        let (_, result) = responseQueue.remove(at: index)
        lock.unlock()

        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

final class MockPumpMessageTransport: PumpMessageTransport {
    private let peripheralManager: MockPeripheralManager

    init(peripheralManager: MockPeripheralManager) {
        self.peripheralManager = peripheralManager
    }

    func sendMessage(_ message: Message) throws -> Message {
        return try peripheralManager.send(message: message)
    }

    var sentMessages: [Message] {
        peripheralManager.sentMessages.map { $0.message }
    }
}

final class MockPumpComm: PumpComm {
    struct Call {
        let requestType: Message.Type
        let expectedResponseType: Message.Type
    }

    private(set) var calls: [Call] = []
    var onSend: ((Message) -> Void)?

    override func sendMessage<T>(transport: PumpMessageTransport, message: Message, expecting expectedType: T.Type) throws -> T where T : Message {
        calls.append(Call(requestType: type(of: message), expectedResponseType: expectedType))
        onSend?(message)
        return try super.sendMessage(transport: transport, message: message, expecting: expectedType)
    }
}
