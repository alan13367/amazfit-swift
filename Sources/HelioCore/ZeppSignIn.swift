import Foundation

public enum ZeppSignIn {
    // The unparameterized page defaults to Zepp Life's privacy operations menu.
    // This product selector and hash route render Zepp's actual sign-in form.
    public static let url = URL(string: "https://user.huami.com/privacy/index.html?platform_app=com.huami.watch.hmwatchmanager#/login")!

    /// Read only a complete, unambiguous session belonging to the official sign-in page.
    public static func credentials(from cookies: [HTTPCookie], region: ZeppRegion, now: Date = Date()) -> ZeppCredentials? {
        let applicable = cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            let host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            guard host == "user.huami.com" || host == "huami.com",
                  cookie.expiresDate.map({ $0 > now }) ?? true else { return false }
            let path = cookie.path
            guard path.hasPrefix("/") else { return false }
            let pagePath = url.path
            return pagePath == path || (pagePath.hasPrefix(path) && (path.hasSuffix("/") || pagePath.dropFirst(path.count).hasPrefix("/")))
        }
        // Conflicting cookies can refer to different sessions. Do not mix accounts or pick one arbitrarily.
        let tokens = Set(applicable.filter { $0.name == "apptoken" }.map(\.value))
        let userIDs = Set(applicable.filter { $0.name == "userid" }.map(\.value))
        guard tokens.count == 1, userIDs.count == 1, let token = tokens.first, let userID = userIDs.first else { return nil }
        return try? ZeppCredentials(userID: userID, token: token, region: region)
    }
}
