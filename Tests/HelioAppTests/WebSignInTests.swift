import XCTest
import WebKit
import HelioCore
#if SWIFT_PACKAGE
@testable import HelioApp
#else
@testable import Helio
#endif

@MainActor
final class WebSignInTests: XCTestCase, @unchecked Sendable {
    func testUsesIsolatedNonPersistentCookieStores() async throws {
        let first = ZeppWebSession(region: .us) { _ in XCTFail("Incomplete session") }
        let second = ZeppWebSession(region: .us) { _ in XCTFail("Incomplete session") }
        first.observeCookies()
        second.observeCookies()
        defer { first.stop(); second.stop() }
        let firstStore = first.webView.configuration.websiteDataStore
        let secondStore = second.webView.configuration.websiteDataStore
        XCTAssertFalse(firstStore.isPersistent)
        XCTAssertFalse(secondStore.isPersistent)
        XCTAssertFalse(firstStore === secondStore)
        await firstStore.httpCookieStore.setCookie(cookie("userid", "123"))
        let firstCookies = await firstStore.httpCookieStore.allCookies()
        let secondCookies = await secondStore.httpCookieStore.allCookies()
        XCTAssertEqual(firstCookies.count, 1)
        XCTAssertTrue(secondCookies.isEmpty)
    }

    func testCookieObservationDeliversSessionExactlyOnceInEitherOrder() async throws {
        for tokenFirst in [true, false] {
            let signedIn = expectation(description: "Automatically collected the complete session")
            signedIn.assertForOverFulfill = true
            var deliveries = 0
            let session = ZeppWebSession(region: .europe) { credentials in
                deliveries += 1
                XCTAssertEqual(credentials.userID, "123")
                XCTAssertEqual(credentials.token, "test-session")
                XCTAssertEqual(credentials.region, .europe)
                signedIn.fulfill()
            }
            session.observeCookies()
            defer { session.stop() }
            let store = session.webView.configuration.websiteDataStore.httpCookieStore
            let token = cookie("apptoken", "test-session")
            let userID = cookie("userid", "123")
            await store.setCookie(tokenFirst ? token : userID)
            XCTAssertEqual(deliveries, 0)
            await store.setCookie(tokenFirst ? userID : token)
            await fulfillment(of: [signedIn], timeout: 5)
            // A queued notification after success must not connect a second time.
            session.cookiesDidChange(in: store)
            session.webView(session.webView, didFinish: nil)
            await Task.yield()
            XCTAssertEqual(deliveries, 1)
            XCTAssertNil(session.webView.navigationDelegate)
            XCTAssertNil(session.webView.uiDelegate)
        }
    }

    func testClientSideCookieWritesAreCollectedWithoutRedirect() async throws {
        let signedIn = expectation(description: "Collected cookies written by a client-side login page")
        let session = ZeppWebSession(region: .us) { credentials in
            XCTAssertEqual(credentials.userID, "123")
            XCTAssertEqual(credentials.token, "test-session")
            signedIn.fulfill()
        }
        session.observeCookies()
        defer { session.stop() }
        // Local HTML only. No requests or credentials go to the real site.
        session.webView.loadHTMLString("""
            <html><head><script>
            document.cookie = "userid=123; path=/";
            setTimeout(() => { document.cookie = "apptoken=test-session; path=/"; }, 50);
            </script></head><body>Offline sign-in fixture</body></html>
            """, baseURL: ZeppSignIn.url)
        await fulfillment(of: [signedIn], timeout: 5)
    }

    func testReadsCookiesAlreadyPresentWhenObservationStarts() async throws {
        let signedIn = expectation(description: "Initial cookie snapshot")
        let session = ZeppWebSession(region: .global) { credentials in
            XCTAssertEqual(credentials.region, .global)
            signedIn.fulfill()
        }
        defer { session.stop() }
        let store = session.webView.configuration.websiteDataStore.httpCookieStore
        await store.setCookie(cookie("userid", "123"))
        await store.setCookie(cookie("apptoken", "test-session"))
        session.observeCookies()
        await fulfillment(of: [signedIn], timeout: 5)
    }

    func testCancelIgnoresPendingCookieReadAndLaterNotifications() async throws {
        let unexpected = expectation(description: "Cancelled sign-in must not connect")
        unexpected.isInverted = true
        let session = ZeppWebSession(region: .us) { _ in unexpected.fulfill() }
        let store = session.webView.configuration.websiteDataStore.httpCookieStore
        await store.setCookie(cookie("userid", "123"))
        await store.setCookie(cookie("apptoken", "test-session"))
        session.observeCookies()
        session.stop()
        session.cookiesDidChange(in: store)
        await fulfillment(of: [unexpected], timeout: 0.25)
        let remainingCookies = await store.allCookies()
        XCTAssertTrue(remainingCookies.isEmpty)
        XCTAssertFalse(session.isLoading)
        XCTAssertNil(session.webView.navigationDelegate)
        XCTAssertNil(session.webView.uiDelegate)
    }

    func testUnrelatedCookiesCannotSignIn() async throws {
        let unexpected = expectation(description: "Untrusted cookies must not connect")
        unexpected.isInverted = true
        let session = ZeppWebSession(region: .us) { _ in unexpected.fulfill() }
        session.observeCookies()
        defer { session.stop() }
        let store = session.webView.configuration.websiteDataStore.httpCookieStore
        await store.setCookie(cookie("userid", "123"))
        await store.setCookie(cookie("apptoken", "test-session", domain: "example.com"))
        session.cookiesDidChange(in: store)
        await fulfillment(of: [unexpected], timeout: 0.25)
    }

    func testPageFailureDoesNotExposeURLsOrSecretsAndCancelIsIgnored() {
        let session = ZeppWebSession(region: .us) { _ in XCTFail("No cookies") }
        session.observeCookies()
        defer { session.stop() }
        let browser = session.webView
        let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        session.webView(browser, didFailProvisionalNavigation: nil, withError: cancelled)
        XCTAssertNil(session.error)
        let secret = "test-secret-in-url"
        let failure = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost,
                              userInfo: [NSLocalizedDescriptionKey: "https://example.com/?token=\(secret)"])
        session.webView(browser, didFailProvisionalNavigation: nil, withError: failure)
        XCTAssertNotNil(session.error)
        XCTAssertFalse(session.error?.contains(secret) ?? true)
        XCTAssertFalse(session.isLoading)
    }

    func testNavigationPolicyAllowsHTTPSButRejectsUnsafeURLs() async throws {
        let session = ZeppWebSession(region: .us) { _ in XCTFail("No cookies") }
        session.observeCookies()
        defer { session.stop() }
        for url in [ZeppSignIn.url.absoluteString, "https://identity.example.com/login", "about:blank"] {
            let action = TestNavigationAction(url: URL(string: url)!)
            let policy = await session.webView(session.webView, decidePolicyFor: action)
            XCTAssertEqual(policy, .allow, url)
        }
        for url in ["http://user.huami.com/", "file:///tmp/private", "data:text/html,hello", "custom://login", "https://name:password@user.huami.com/"] {
            let action = TestNavigationAction(url: URL(string: url)!)
            let policy = await session.webView(session.webView, decidePolicyFor: action)
            XCTAssertEqual(policy, .cancel, url)
        }
        session.stop()
        let policy = await session.webView(session.webView, decidePolicyFor: TestNavigationAction(url: ZeppSignIn.url))
        XCTAssertEqual(policy, .cancel)
    }

    private func cookie(_ name: String, _ value: String, domain: String = "user.huami.com") -> HTTPCookie {
        HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: "/"])!
    }
}

@MainActor
private final class TestNavigationAction: WKNavigationAction {
    private let testRequest: URLRequest
    init(url: URL) {
        testRequest = URLRequest(url: url)
        super.init()
    }
    override var request: URLRequest { testRequest }
}
