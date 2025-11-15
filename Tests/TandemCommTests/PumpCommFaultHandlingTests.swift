import XCTest
@testable import TandemKit
import TandemCore

final class PumpCommFaultHandlingTests: XCTestCase {
    func testTransientFaultRetriesAndSucceeds() throws {
        let transport = MockTransport(results: [
            .message(ErrorResponse(requestCodeId: Int(ApiVersionRequest.props.opCode), errorCode: .messageBufferFull)),
            .message(ApiVersionResponse(majorVersion: 1, minorVersion: 0))
        ])
        let policy = MockRetryPolicy(decisions: [.retry(after: 0)])
        let delegate = MockDelegate()
        let pumpComm = PumpComm(pumpState: nil, retryPolicy: policy, delayHandler: { _ in })
        pumpComm.delegate = delegate

        let request = ApiVersionRequest()
        let response: ApiVersionResponse = try pumpComm.sendMessage(transport: transport, message: request, expecting: ApiVersionResponse.self)

        XCTAssertEqual(response.majorVersion, 1)
        XCTAssertEqual(transport.sentMessages.count, 2)
        XCTAssertEqual(delegate.faultEvents.count, 1)
        XCTAssertTrue(delegate.faultEvents.first?.willRetry ?? false)
        XCTAssertEqual(delegate.faultEvents.first?.code, .messageBufferFull)
    }

    func testNonRetryableFaultThrowsPumpCommError() {
        let transport = MockTransport(results: [
            .message(ErrorResponse(requestCodeId: Int(ApiVersionRequest.props.opCode), errorCode: .invalidRequiredParameter))
        ])
        let policy = MockRetryPolicy(decisions: [.doNotRetry])
        let delegate = MockDelegate()
        let pumpComm = PumpComm(pumpState: nil, retryPolicy: policy, delayHandler: { _ in })
        pumpComm.delegate = delegate

        let request = ApiVersionRequest()

        XCTAssertThrowsError(try pumpComm.sendMessage(transport: transport, message: request)) { error in
            guard case let PumpCommError.pumpFault(event) = error else {
                XCTFail("Expected PumpCommError.pumpFault, got \(error)")
                return
            }
            XCTAssertEqual(event.code, .invalidRequiredParameter)
            XCTAssertFalse(event.willRetry)
        }

        XCTAssertEqual(delegate.faultEvents.count, 1)
        XCTAssertEqual(delegate.faultEvents.first?.code, .invalidRequiredParameter)
    }

    func testAuthenticationFaultCategorized() {
        let transport = MockTransport(results: [
            .message(ErrorResponse(requestCodeId: Int(ApiVersionRequest.props.opCode), errorCode: .invalidAuthenticationError))
        ])
        let policy = MockRetryPolicy(decisions: [.doNotRetry])
        let delegate = MockDelegate()
        let pumpComm = PumpComm(pumpState: nil, retryPolicy: policy, delayHandler: { _ in })
        pumpComm.delegate = delegate

        let request = ApiVersionRequest()

        XCTAssertThrowsError(try pumpComm.sendMessage(transport: transport, message: request)) { error in
            guard case let PumpCommError.pumpFault(event) = error else {
                XCTFail("Expected PumpCommError.pumpFault, got \(error)")
                return
            }
            XCTAssertEqual(event.code, .invalidAuthenticationError)
            XCTAssertEqual(event.category, .authentication)
        }

        XCTAssertEqual(delegate.faultEvents.count, 1)
        XCTAssertEqual(delegate.faultEvents.first?.category, .authentication)
    }
}

private final class MockDelegate: PumpCommDelegate {
    var faultEvents: [PumpCommFaultEvent] = []

    func pumpComm(_ pumpComms: PumpComm, didChange pumpState: PumpState) {}

    func pumpComm(_ pumpComms: PumpComm,
                  didReceive message: Message,
                  metadata: MessageMetadata?,
                  characteristic: CharacteristicUUID,
                  txId: UInt8) {}

    func pumpComm(_ pumpComms: PumpComm, didEncounterFault event: PumpCommFaultEvent) {
        faultEvents.append(event)
    }
}

private final class MockTransport: PumpMessageTransport {
    enum Result {
        case message(Message)
        case error(Error)
    }

    private(set) var sentMessages: [Message] = []
    private var results: [Result]

    init(results: [Result]) {
        self.results = results
    }

    func sendMessage(_ message: Message) throws -> Message {
        sentMessages.append(message)
        guard !results.isEmpty else {
            throw PumpCommError.other
        }
        let result = results.removeFirst()
        switch result {
        case .message(let message):
            return message
        case .error(let error):
            throw error
        }
    }
}

private final class MockRetryPolicy: PumpCommRetryPolicy {
    private let decisions: [PumpCommRetryDecision]

    init(decisions: [PumpCommRetryDecision]) {
        self.decisions = decisions
    }

    func decision(for fault: PumpFaultCode, attempt: Int) -> PumpCommRetryDecision {
        if attempt - 1 < decisions.count {
            return decisions[attempt - 1]
        }
        return .doNotRetry
    }
}
