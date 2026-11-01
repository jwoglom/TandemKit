@testable import TandemKit
import XCTest

final class TandemSourceClientTests: XCTestCase {
    /// Intercepts the client's requests so the retry-on-401 path runs without a network.
    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var responder: ((URLRequest) -> (Int, Data))!
        nonisolated(unsafe) static var seenRequests: [URLRequest] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.seenRequests.append(request)
            let (status, body) = Self.responder(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private final class StubTokenProvider: TandemSourceTokenProvider {
        var isAuthenticated = true
        private(set) var forceRefreshCount = 0
        func accessToken(forceRefresh: Bool) async throws -> String {
            if forceRefresh { forceRefreshCount += 1 }
            return forceRefresh ? "fresh-token" : "stale-token"
        }
    }

    private func makeClient(_ provider: TandemSourceTokenProvider) -> TandemSourceHTTPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.seenRequests = []
        return TandemSourceHTTPClient(session: URLSession(configuration: config), tokenProvider: provider)
    }

    func testUploadRetriesOnceAfter401ThenRefreshes() async throws {
        let provider = StubTokenProvider()
        let client = makeClient(provider)
        var calls = 0
        StubURLProtocol.responder = { _ in
            calls += 1
            return calls == 1 ? (401, Data()) : (200, Data(#"{"message":"ok"}"#.utf8))
        }

        try await client.upload(bodyJSON: Data(#"{"client":"mHealth"}"#.utf8))

        XCTAssertEqual(calls, 2)
        XCTAssertEqual(provider.forceRefreshCount, 1)
        // The retry used the refreshed bearer, and both requests carried a TDCToken over the body.
        XCTAssertEqual(StubURLProtocol.seenRequests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer fresh-token")
        XCTAssertNotNil(StubURLProtocol.seenRequests.first?.value(forHTTPHeaderField: "TDCToken"))
    }

    func testGetLastEventUploadedDecodes() async throws {
        let client = makeClient(StubTokenProvider())
        StubURLProtocol.responder = { _ in (200, Data(#"{"maxPumpEventIndex":2726123,"processingStatus":0}"#.utf8)) }

        let result = try await client.getLastEventUploaded(serial: 1234567, deviceAssignmentId: "uuid")

        XCTAssertEqual(result.maxPumpEventIndex, 2726123)
    }

    func testNon401ErrorDoesNotRetry() async {
        let provider = StubTokenProvider()
        let client = makeClient(provider)
        var calls = 0
        StubURLProtocol.responder = { _ in calls += 1; return (500, Data("boom".utf8)) }

        do {
            try await client.upload(bodyJSON: Data("{}".utf8))
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(provider.forceRefreshCount, 0)
        }
    }
}
