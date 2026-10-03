import Foundation
import XCTest
@testable import HelioCore

final class ClientTests: XCTestCase, @unchecked Sendable {
    private let secret = "test-session-keep-private"
    private func credentials(_ region: ZeppRegion = .us) throws -> ZeppCredentials {
        try ZeppCredentials(userID: "1234", token: secret, region: region)
    }
    private var date: Date { Date(timeIntervalSince1970: 1_770_076_800) }

    func testRequestConstructionUsesOnlySelectedOfficialHostAndNoTokenInURL() throws {
        let client = ZeppClient()
        for region in ZeppRegion.allCases {
            for endpoint in CloudEndpoint.allCases {
                let request = client.makeRequest(endpoint: endpoint, credentials: try credentials(region), startDay: "2026-02-03", endDay: "2026-02-04", fromMS: "1", toMS: "2")
                XCTAssertEqual(request.url?.scheme, "https")
                XCTAssertEqual(request.url?.host, region.baseURL.host)
                XCTAssertFalse(request.url!.absoluteString.contains(secret))
                XCTAssertEqual(request.value(forHTTPHeaderField: "apptoken"), secret)
                XCTAssertNil(request.value(forHTTPHeaderField: "x-hm-ekv"))
                XCTAssertEqual(request.httpMethod, "GET")
            }
        }
        let request = client.makeRequest(endpoint: .band, credentials: try credentials(), startDay: "2026-02-03", endDay: "2026-02-04", fromMS: "1", toMS: "2")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "query_type" }?.value, "detail")
        XCTAssertEqual(query.first { $0.name == "userid" }?.value, "1234")
        XCTAssertEqual(request.value(forHTTPHeaderField: "appPlatform"), "web")
    }

    func testRedirectDelegateRefusesToForwardSession() {
        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let source = URL(string: "https://api-mifit-us2.zepp.com/test")!
        let response = HTTPURLResponse(url: source, statusCode: 302, httpVersion: nil, headerFields: ["Location": "https://example.com"])!
        let task = session.dataTask(with: source)
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                            newRequest: URLRequest(url: URL(string: "https://example.com")!)) { request in
            XCTAssertNil(request)
        }
    }

    func testSuccessfulFetchPreservesPayloadsAndRedactsSecrets() async throws {
        let token = secret
        let fixture = MockFixture { request in
            if request.url!.path.contains("band_data") {
                return .json(.object(["code": .number(1), "data": .array([]), "app_token": .string(token),
                                     "message": .string("echo " + token)]))
            }
            return .json(.object(["items": .array([])]))
        }
        let result = try await ZeppClient(session: fixture.session).fetch(credentials: credentials(), from: date, to: date)
        XCTAssertEqual(result.payloads.count, 7)
        XCTAssertEqual(result.days.count, 0)
        let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        XCTAssertFalse(encoded.contains(secret))
        XCTAssertTrue(encoded.contains("[redacted]"))
        XCTAssertNotNil(result.payload(.workouts)?.warning)
    }

    func testUnauthorizedAndForbiddenAreErrors() async throws {
        for status in [401, 403] {
            let fixture = MockFixture { _ in MockResponse(status: status, data: Data("secret-server-body".utf8)) }
            do {
                _ = try await ZeppClient(session: fixture.session).fetch(credentials: credentials(), from: date, to: date)
                XCTFail("Expected authentication error")
            } catch let error as ZeppError { XCTAssertEqual(error, .authentication) }
        }
    }

    func testHTTPErrorDoesNotIncludeResponseBodyOrToken() async throws {
        let token = secret
        let fixture = MockFixture { _ in MockResponse(status: 500, data: Data(token.utf8)) }
        do {
            _ = try await ZeppClient(session: fixture.session).fetch(credentials: credentials(), from: date, to: date)
            XCTFail("Expected HTTP error")
        } catch let error as ZeppError {
            XCTAssertEqual(error, .http(500))
            XCTAssertFalse(error.localizedDescription.contains(secret))
        }
    }

    func testMalformedPrimaryJSONIsNotAnEmptySuccess() async throws {
        let fixture = MockFixture { _ in MockResponse(status: 200, data: Data("<html>sign in</html>".utf8)) }
        do {
            _ = try await ZeppClient(session: fixture.session).fetch(credentials: credentials(), from: date, to: date)
            XCTFail("Expected malformed response")
        } catch let error as ZeppError { XCTAssertEqual(error, .malformed("Band data")) }
    }

    func testOptionalFailurePreservesBandData() async throws {
        let primary = try band(summary: .object(["stp": .object(["ttl": .number(123)])]), heart: [60])
        let fixture = MockFixture { request in
            if request.url!.path.contains("band_data") { return .json(primary) }
            if request.url!.path == "/users/1234/events" { return MockResponse(status: 503, data: Data()) }
            return .json(.object(["items": .array([])]))
        }
        let result = try await ZeppClient(session: fixture.session).fetch(credentials: credentials(), from: date, to: date)
        XCTAssertEqual(result.days.first?.steps, 123)
        XCTAssertEqual(result.payload(.stress)?.raw, .null)
        XCTAssertNotNil(result.payload(.stress)?.warning)
        XCTAssertEqual(result.payloads.count, 7)
    }

    func testMalformedSummaryStillExposesDownloadedRawData() async throws {
        let fixture = MockFixture { request in
            if request.url!.path.contains("band_data") {
                return .json(.object(["code": .number(1), "data": .array([.object([
                    "date_time": .string("2026-02-03"), "summary": .string("bad")
                ])])]))
            }
            return .json(.object(["items": .array([])]))
        }
        let result = try await ZeppClient(session: fixture.session).fetch(credentials: credentials(), from: date, to: date)
        XCTAssertTrue(result.days.isEmpty)
        XCTAssertNotNil(result.payload(.band)?.warning)
        XCTAssertFalse(result.payload(.band)!.raw["data"].array.isEmpty)
    }

    func testEventLimitIsReported() async throws {
        let fixture = MockFixture { request in
            if request.url!.path.contains("band_data") { return .json(.object(["code": .number(1), "data": .array([])])) }
            return .json(.object(["items": .array(Array(repeating: .object([:]), count: 200))]))
        }
        let result = try await ZeppClient(session: fixture.session).fetch(credentials: credentials(), from: date, to: date)
        XCTAssertTrue(result.payload(.stress)?.warning?.contains("limit") ?? false)
    }

    func testAuthenticationFailureInOptionalEndpointAbortsSync() async throws {
        let fixture = MockFixture { request in
            if request.url!.path.contains("band_data") { return .json(.object(["code": .number(1), "data": .array([])])) }
            return MockResponse(status: 401, data: Data())
        }
        do {
            _ = try await ZeppClient(session: fixture.session).fetch(credentials: credentials(), from: date, to: date)
            XCTFail("Expected the authentication failure to abort the entire sync")
        } catch let error as ZeppError { XCTAssertEqual(error, .authentication) }
    }

    func testCancellationDuringSyncPropagates() async throws {
        let fixture = MockFixture { request in
            if request.url!.path.contains("band_data") { return .json(.object(["code": .number(1), "data": .array([])])) }
            return .json(.object(["items": .array([])]))
        }
        let credentials = try credentials()
        let date = date
        let task = Task {
            try await ZeppClient(session: fixture.session).fetch(credentials: credentials, from: date, to: date)
        }
        try await Task.sleep(for: .milliseconds(250))
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
    }

    func testDateRangeValidation() async throws {
        let client = ZeppClient()
        for end in [date.addingTimeInterval(-86400), date.addingTimeInterval(31 * 86400)] {
            do {
                _ = try await client.fetch(credentials: credentials(), from: date, to: end)
                XCTFail("Expected invalid range")
            } catch let error as ZeppError { XCTAssertEqual(error, .dateRange) }
        }
    }

    func testCancellationStopsBeforeNetwork() async throws {
        let fixture = MockFixture { _ in .json(.object(["code": .number(1), "data": .array([])])) }
        let credentials = try credentials()
        let date = date
        let task = Task {
            try await Task.sleep(for: .milliseconds(100))
            return try await ZeppClient(session: fixture.session).fetch(credentials: credentials, from: date, to: date)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
    }
}

private struct MockResponse: Sendable {
    let status: Int
    let data: Data
    static func json(_ value: JSONValue) -> MockResponse {
        MockResponse(status: 200, data: try! JSONEncoder().encode(value))
    }
}
private final class MockRegistry: @unchecked Sendable {
    static let shared = MockRegistry()
    private let lock = NSLock()
    private var handlers: [String: @Sendable (URLRequest) -> MockResponse] = [:]
    func set(_ id: String, handler: @escaping @Sendable (URLRequest) -> MockResponse) {
        lock.withLock { handlers[id] = handler }
    }
    func remove(_ id: String) { lock.withLock { _ = handlers.removeValue(forKey: id) } }
    func response(for request: URLRequest) -> MockResponse? {
        let handler = lock.withLock { handlers[request.value(forHTTPHeaderField: "X-Helio-Test") ?? ""] }
        return handler?(request)
    }
}
private final class MockFixture: @unchecked Sendable {
    let session: URLSession
    private let id = UUID().uuidString
    init(handler: @escaping @Sendable (URLRequest) -> MockResponse) {
        MockRegistry.shared.set(id, handler: handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        config.httpAdditionalHeaders = ["X-Helio-Test": id]
        session = URLSession(configuration: config)
    }
    deinit { session.invalidateAndCancel(); MockRegistry.shared.remove(id) }
}
private final class MockProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let response = MockRegistry.shared.response(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
