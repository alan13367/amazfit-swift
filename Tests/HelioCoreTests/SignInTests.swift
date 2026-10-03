import Foundation
import XCTest
import HelioCore

final class SignInTests: XCTestCase {
    func testSignInLinkOpensZeppLoginRatherThanPrivacyOperations() throws {
        let components = try XCTUnwrap(URLComponents(url: ZeppSignIn.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "user.huami.com")
        XCTAssertEqual(components.path, "/privacy/index.html")
        XCTAssertEqual(components.fragment, "/login", "The privacy landing page has account deletion controls, not a sign-in form.")
        XCTAssertEqual(components.queryItems?.first { $0.name == "platform_app" }?.value,
                       "com.huami.watch.hmwatchmanager", "Without the Zepp product selector, the site defaults to Zepp Life.")
        XCTAssertNil(components.user)
        XCTAssertNil(components.password)
    }

    func testReadsCompleteSessionAndPreservesSelectedRegion() throws {
        let credentials = try XCTUnwrap(ZeppSignIn.credentials(from: [
            cookie("userid", "12345"), cookie("apptoken", "session-token"), cookie("unrelated", "ignored")
        ], region: .europe))
        XCTAssertEqual(credentials.userID, "12345")
        XCTAssertEqual(credentials.token, "session-token")
        XCTAssertEqual(credentials.region, .europe)
    }

    func testWaitsForBothCookies() {
        XCTAssertNil(ZeppSignIn.credentials(from: [], region: .us))
        XCTAssertNil(ZeppSignIn.credentials(from: [cookie("userid", "123")], region: .us))
        XCTAssertNil(ZeppSignIn.credentials(from: [cookie("apptoken", "secret")], region: .us))
        XCTAssertNil(ZeppSignIn.credentials(from: [cookie("userid", "123"), cookie("token", "secret")], region: .us))
    }

    func testRejectsCookiesFromUnrelatedAndLookalikeDomains() {
        for domain in ["example.com", "user.huami.com.example.com", "evilhuami.com", ".auth.huami.com", "user.zepp.com"] {
            let cookies = [cookie("userid", "123", domain: domain), cookie("apptoken", "secret", domain: domain)]
            XCTAssertNil(ZeppSignIn.credentials(from: cookies, region: .us), domain)
            // An unrelated cookie must not complete an otherwise valid pair.
            XCTAssertNil(ZeppSignIn.credentials(from: [cookie("userid", "123"), cookies[1]], region: .us), domain)
        }
    }

    func testAcceptsParentDomainAndCaseInsensitiveDomains() {
        for domain in [".huami.com", "huami.com", ".user.huami.com", "USER.HUAMI.COM"] {
            let cookies = [cookie("userid", "123", domain: domain), cookie("apptoken", "secret", domain: domain)]
            XCTAssertNotNil(ZeppSignIn.credentials(from: cookies, region: .global), domain)
        }
    }

    func testCookiePathMustApplyToSignInPage() {
        for path in ["/", "/privacy", "/privacy/", "/privacy/index.html"] {
            let cookies = [cookie("userid", "123", path: path), cookie("apptoken", "secret", path: path)]
            XCTAssertNotNil(ZeppSignIn.credentials(from: cookies, region: .us), path)
        }
        for path in ["/other", "/priv", "/privacy/index", "/privacy/index.html/child"] {
            let cookies = [cookie("userid", "123", path: path), cookie("apptoken", "secret", path: path)]
            XCTAssertNil(ZeppSignIn.credentials(from: cookies, region: .us), path)
        }
    }

    func testExpiredCookiesDoNotCompleteSession() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for expiration in [now.addingTimeInterval(-1), now] {
            let cookies = [cookie("userid", "123"), cookie("apptoken", "secret", expires: expiration)]
            XCTAssertNil(ZeppSignIn.credentials(from: cookies, region: .us, now: now))
        }
        let cookies = [cookie("userid", "123"), cookie("apptoken", "secret", expires: now.addingTimeInterval(1))]
        XCTAssertNotNil(ZeppSignIn.credentials(from: cookies, region: .us, now: now))
    }

    func testRejectsMalformedCredentials() {
        for userID in ["", "not-numeric", "123/456"] {
            XCTAssertNil(ZeppSignIn.credentials(from: [cookie("userid", userID), cookie("apptoken", "secret")], region: .us))
        }
        for token in ["", "has spaces", "é"] {
            XCTAssertNil(ZeppSignIn.credentials(from: [cookie("userid", "123"), cookie("apptoken", token)], region: .us))
        }
    }

    func testRejectsConflictingDuplicateCookiesButAcceptsIdenticalValues() {
        let pair = [cookie("userid", "123"), cookie("apptoken", "secret")]
        XCTAssertNil(ZeppSignIn.credentials(from: pair + [cookie("userid", "456", domain: ".huami.com")], region: .us))
        XCTAssertNil(ZeppSignIn.credentials(from: pair + [cookie("apptoken", "other", path: "/privacy")], region: .us))
        XCTAssertNotNil(ZeppSignIn.credentials(from: pair + [cookie("apptoken", "secret", path: "/privacy")], region: .us))
        XCTAssertNotNil(ZeppSignIn.credentials(from: pair + [cookie("apptoken", "untrusted", domain: "example.com")], region: .us))
    }

    func testSupportsHTTPOnlyAndLegacyNonSecureSessionCookies() throws {
        let token = try XCTUnwrap(HTTPCookie(properties: [
            .name: "apptoken", .value: "secret", .domain: "user.huami.com", .path: "/",
            HTTPCookiePropertyKey("HttpOnly"): "TRUE"
        ]))
        XCTAssertTrue(token.isHTTPOnly)
        XCTAssertFalse(token.isSecure)
        XCTAssertNil(token.expiresDate)
        XCTAssertNotNil(ZeppSignIn.credentials(from: [cookie("userid", "123"), token], region: .us))
    }

    private func cookie(_ name: String, _ value: String, domain: String = "user.huami.com",
                        path: String = "/", expires: Date? = nil) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
        if let expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)!
    }
}
