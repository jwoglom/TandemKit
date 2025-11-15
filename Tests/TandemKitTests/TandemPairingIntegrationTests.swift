import Foundation
@testable import TandemBLE
@testable import TandemCore
@testable import TandemKit
import XCTest

#if canImport(CoreBluetooth)
    import CoreBluetooth
#endif

/// Integration tests for pairing with Tandem pumps
///
/// These tests require a physical pump or BLE simulator to run properly.
/// They are intended for manual testing and validation of the pairing flow.
final class TandemPairingIntegrationTests: XCTestCase {
    // MARK: - Mock Transport for Testing

    /// Simple thread-safe storage helper for use in tests
    private final class Locked<Value> {
        private var valueStorage: Value
        private let lock = NSLock()

        init(_ value: Value) {
            valueStorage = value
        }

        var value: Value {
            get {
                lock.lock()
                defer { lock.unlock() }
                return valueStorage
            }
            set {
                lock.lock()
                valueStorage = newValue
                lock.unlock()
            }
        }
    }

    /// Mock transport that simulates pump responses for testing
    class MockPumpTransport: PumpMessageTransport {
        var sentMessages: [Message] = []
        var responseQueue: [Message] = []
        var shouldFail: Bool = false
        private var lastAppInstanceId: Int = 0

        func sendMessage(_ message: Message) throws -> Message {
            sentMessages.append(message)

            if shouldFail {
                throw PumpCommError.noResponse
            }

            // Return canned responses based on message type
            if let request = message as? CentralChallengeRequest {
                lastAppInstanceId = request.appInstanceId
                return CentralChallengeResponse(
                    appInstanceId: lastAppInstanceId,
                    centralChallengeHash: Data(repeating: 0xAA, count: 20),
                    hmacKey: Data(repeating: 0xBB, count: 8)
                )
            }

            if let request = message as? PumpChallengeRequest {
                lastAppInstanceId = request.appInstanceId
                return PumpChallengeResponse(appInstanceId: lastAppInstanceId, success: true)
            }

            #if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
                // JPAKE flow responses
                if message is Jpake1aRequest {
                    let request = message as! Jpake1aRequest
                    lastAppInstanceId = request.appInstanceId
                    return Jpake1aResponse(
                        appInstanceId: request.appInstanceId,
                        centralChallengeHash: Data(repeating: 0xCC, count: 165)
                    )
                }

                if message is Jpake1bRequest {
                    let request = message as! Jpake1bRequest
                    lastAppInstanceId = request.appInstanceId
                    return Jpake1bResponse(
                        appInstanceId: request.appInstanceId,
                        centralChallengeHash: Data(repeating: 0xDD, count: 165)
                    )
                }

                if message is Jpake2Request {
                    let request = message as! Jpake2Request
                    lastAppInstanceId = request.appInstanceId
                    return Jpake2Response(
                        appInstanceId: request.appInstanceId,
                        centralChallengeHash: Data(repeating: 0xEE, count: 165)
                    )
                }

                if message is Jpake3SessionKeyRequest {
                    return Jpake3SessionKeyResponse(
                        appInstanceId: lastAppInstanceId,
                        nonce: Data(repeating: 0xFF, count: 8),
                        reserved: Jpake3SessionKeyResponse.RESERVED
                    )
                }

                if message is Jpake4KeyConfirmationRequest {
                    let request = message as! Jpake4KeyConfirmationRequest
                    return Jpake4KeyConfirmationResponse(
                        appInstanceId: request.appInstanceId,
                        nonce: Data(repeating: 0x11, count: 8),
                        reserved: Jpake4KeyConfirmationResponse.RESERVED,
                        hashDigest: Data(repeating: 0x22, count: 32)
                    )
                }
            #endif

            throw PumpCommError.other
        }
    }

    // MARK: - Unit Tests (No Hardware Required)

    func testPairingCodeValidation() throws {
        // Test 6-digit code validation
        XCTAssertNoThrow(try PumpChallengeRequestBuilder.processPairingCode("123456"))
        XCTAssertNoThrow(try PumpChallengeRequestBuilder.processPairingCode("123 456"))
        XCTAssertNoThrow(try PumpChallengeRequestBuilder.processPairingCode("123-456"))

        // Test 16-character code validation
        XCTAssertNoThrow(try PumpChallengeRequestBuilder.processPairingCode("abcd-efgh-ijkl-mnop"))
        XCTAssertNoThrow(try PumpChallengeRequestBuilder.processPairingCode("abcdefghijklmnop"))

        // Test invalid codes
        XCTAssertThrowsError(try PumpChallengeRequestBuilder.processPairingCode("123")) // Too short
        XCTAssertThrowsError(try PumpChallengeRequestBuilder.processPairingCode("12345678901234567")) // Too long
    }

    func testLegacyPairingFlowWithMockTransport() throws {
        let mockTransport = MockPumpTransport()
        let pumpState = PumpState()
        let session = PumpCommSession(pumpState: pumpState, delegate: nil)

        let expectation = expectation(description: "Legacy pairing completes")
        let pairError = Locked<Error?>(nil)

        session.runSession(withName: "Test Pairing") {
            do {
                try session.pair(transport: mockTransport, pairingCode: "abcd-efgh-ijkl-mnop")
            } catch {
                pairError.value = error
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertNil(pairError.value, "Pairing should succeed with mock transport")
        XCTAssertEqual(mockTransport.sentMessages.count, 2, "Should send CentralChallengeRequest and PumpChallengeRequest")
        XCTAssertTrue(mockTransport.sentMessages[0] is CentralChallengeRequest)
        XCTAssertTrue(mockTransport.sentMessages[1] is PumpChallengeRequest)
    }

    #if canImport(SwiftECC) && canImport(BigInt) && canImport(CryptoKit)
        func testJPAKEPairingFlowWithMockTransport() throws {
            let mockTransport = MockPumpTransport()
            let pumpState = PumpState()
            let session = PumpCommSession(pumpState: pumpState, delegate: nil)

            PumpCommSession.testOverrideJpakeArtifacts = {
                (Data(repeating: 0x11, count: 32), Data(repeating: 0x22, count: 8))
            }
            PumpChallengeRequestBuilder.testJpakeHandler = { response, _ in
                Jpake1bRequest(appInstanceId: response.appInstanceId, centralChallenge: Data(repeating: 0xAA, count: 165))
            }

            let expectation = expectation(description: "JPAKE pairing completes")

            session.runSession(withName: "Test JPAKE Pairing") {
                do {
                    try session.pair(transport: mockTransport, pairingCode: "123456")
                } catch {
                    XCTFail("Pairing should succeed with override: \(error)")
                }
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 2.0)

            XCTAssertEqual(session.state.derivedSecret, Data(repeating: 0x11, count: 32))
            XCTAssertEqual(session.state.serverNonce, Data(repeating: 0x22, count: 8))

            PumpCommSession.testOverrideJpakeArtifacts = nil
            PumpChallengeRequestBuilder.testJpakeHandler = nil
        }
    #endif

    // MARK: - Error Handling Tests

    func testPairingWithFailingTransport() throws {
        let mockTransport = MockPumpTransport()
        mockTransport.shouldFail = true

        let pumpState = PumpState()
        let session = PumpCommSession(pumpState: pumpState, delegate: nil)

        let expectation = expectation(description: "Pairing fails with transport error")
        let pairError = Locked<Error?>(nil)

        session.runSession(withName: "Test Failing Pairing") {
            do {
                try session.pair(transport: mockTransport, pairingCode: "abcd-efgh-ijkl-mnop")
            } catch {
                pairError.value = error
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertNotNil(pairError.value, "Pairing should fail when transport fails")
        XCTAssertTrue(pairError.value is PumpCommError)
    }

    // MARK: - Manual Hardware Testing Instructions

    /// This test is disabled by default as it requires real hardware.
    /// To run with a physical pump:
    /// 1. Put your Tandem pump into pairing mode
    /// 2. Update the pairingCode below with your pump's code
    /// 3. Enable this test by removing the 'disabled_' prefix
    func disabled_testRealPumpPairing() throws {
        #if canImport(CoreBluetooth) && !os(Linux)

            // ⚠️ IMPORTANT: Update this with your actual pump pairing code
            let pairingCode = "000000" // Replace with actual code

            print("Starting real pump pairing test...")
            print("Make sure your pump is in pairing mode!")
            print("Pairing code: \(pairingCode)")

            let state = TandemPumpManagerState(pumpState: PumpState())

            #if canImport(UIKit)
                let manager = TandemPumpManager(state: state)

                let expectation = XCTestExpectation(description: "Pump pairs successfully")

                manager.pairPump(with: pairingCode) { result in
                    switch result {
                    case .success:
                        print("✓ Pairing succeeded!")
                        expectation.fulfill()
                    case let .failure(error):
                        print("✗ Pairing failed: \(error)")
                        XCTFail("Pairing failed: \(error)")
                        expectation.fulfill()
                    }
                }

                // Wait longer for real hardware
                wait(for: [expectation], timeout: 60.0)
            #else
                throw XCTSkip("Real pump pairing requires UIKit support")
            #endif

        #else
            throw XCTSkip("Real pump pairing requires CoreBluetooth support")
        #endif
    }
}
