import SwiftUI
import WebKit
import HelioCore

/// A private WebKit session, separate from Safari, Chrome, and the cloud client's URLSession.
@MainActor @Observable
final class ZeppWebSession: NSObject, WKHTTPCookieStoreObserver, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    let webView: WKWebView
    private(set) var isLoading = false
    private(set) var host = "user.huami.com"
    private(set) var error: String?
    private let region: ZeppRegion
    private let onSignIn: (ZeppCredentials) -> Void
    private var active = false
    private var delivered = false
    private var popupWindows: [NSWindow] = []

    init(region: ZeppRegion, onSignIn: @escaping (ZeppCredentials) -> Void) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.region = region
        self.onSignIn = onSignIn
        super.init()
    }

    func observeCookies() {
        guard !active, !delivered else { return }
        active = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.configuration.websiteDataStore.httpCookieStore.add(self)
        readCookies()
    }

    func loadSignInPage() {
        guard active else { return }
        error = nil
        isLoading = true
        webView.load(URLRequest(url: ZeppSignIn.url))
    }

    func stop() {
        guard active else { return }
        active = false
        isLoading = false
        let dataStore = webView.configuration.websiteDataStore
        dataStore.httpCookieStore.remove(self)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        for window in popupWindows {
            if let popup = window.contentView as? WKWebView {
                popup.stopLoading()
                popup.navigationDelegate = nil
                popup.uiDelegate = nil
            }
            window.delegate = nil
            window.close()
        }
        popupWindows.removeAll()
        dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        readCookies()
    }

    private func readCookies() {
        guard active, !delivered else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self, self.active, !self.delivered,
                  let credentials = ZeppSignIn.credentials(from: cookies, region: self.region) else { return }
            self.delivered = true
            self.stop()
            self.onSignIn(credentials)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard active, let url = navigationAction.request.url else { return .cancel }
        // Allow HTTPS identity-provider redirects, but never file URLs, insecure HTTP, or custom schemes.
        guard (url.scheme == "https" && url.user == nil && url.password == nil) || url.absoluteString == "about:blank" else {
            error = "This sign-in link cannot open here. Cancel and use manual cookie entry if your sign-in provider requires an external browser."
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard active else { return }
        if webView === self.webView { isLoading = true; error = nil }
        updateHost(for: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard active else { return }
        updateHost(for: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard active else { return }
        if webView === self.webView { isLoading = false }
        updateHost(for: webView)
        // Also check at navigation completion; cookie observation covers the site's client-side login flow.
        readCookies()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pageFailed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        pageFailed(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard active else { return }
        isLoading = false
        error = "The sign-in page stopped unexpectedly. Try Reload, or cancel and use manual cookie entry."
    }

    private func pageFailed(_ failure: Error) {
        guard active, (failure as NSError).code != NSURLErrorCancelled else { return }
        isLoading = false
        // Do not display a failing URL or response body, which could contain login secrets.
        error = "The sign-in page could not load. Check your connection and try Reload, or cancel and use manual cookie entry."
    }

    private func updateHost(for browser: WKWebView) {
        guard let host = browser.url?.host else { return }
        if browser === webView { self.host = host }
        else { popupWindows.first { $0.contentView === browser }?.title = "Sign in · https://\(host)" }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard active, navigationAction.targetFrame == nil, popupWindows.count < 3 else { return nil }
        // A real popup preserves identity providers' window.opener and postMessage flows.
        configuration.websiteDataStore = self.webView.configuration.websiteDataStore
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 650),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Zepp sign-in"
        window.contentView = popup
        window.delegate = self
        popupWindows.append(window)
        window.center()
        window.makeKeyAndOrderFront(nil)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        popupWindows.first { $0.contentView === webView }?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if let popup = window.contentView as? WKWebView {
            popup.stopLoading()
            popup.navigationDelegate = nil
            popup.uiDelegate = nil
        }
        popupWindows.removeAll { $0 === window }
    }
}

struct ZeppWebSignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: ZeppWebSession

    init(region: ZeppRegion, onSignIn: @escaping (ZeppCredentials) -> Void) {
        _session = State(initialValue: ZeppWebSession(region: region, onSignIn: onSignIn))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sign in to Zepp").font(.title2.weight(.semibold))
                Spacer()
                Button("Reload") { session.loadSignInPage() }
            }
            Text("Use the same account as in Zepp on your iPhone. Helio will collect the session cookies and start your download after sign-in. Your password goes to Zepp's website.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Label("https://\(session.host)", systemImage: "lock").font(.caption).textSelection(.enabled)
                Spacer()
                if session.isLoading { ProgressView().controlSize(.small) }
            }
            ZeppBrowser(webView: session.webView)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            if let error = session.error {
                Text(error).font(.callout).foregroundStyle(.orange)
            }
            HStack {
                Text("Waiting for Zepp's session cookies. If sign-in is blocked, cancel and use manual entry.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { session.stop(); dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(width: 780, height: 690)
        .onAppear { session.observeCookies(); session.loadSignInPage() }
        .onDisappear { session.stop() }
    }
}

private struct ZeppBrowser: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
