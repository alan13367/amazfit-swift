import SwiftUI
import HelioCore

struct ConnectionSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var userID = ""
    @State private var token = ""
    @State private var region: ZeppRegion = .us
    @State private var consent = false
    @State private var manualEntry = false
    @State private var showWebSignIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "link").foregroundStyle(Palette.accent).font(.title2)
                Text("Connect your Zepp account").font(.title2.weight(.semibold))
                Spacer()
            }
            Text("Sync your Helio Strap in Zepp on your iPhone first. Then sign in on Zepp's website in a private window inside Helio. The session cookies are collected automatically, without copying a token.")
                .foregroundStyle(.secondary)
            Text("This connection uses an unofficial API. Your password goes to Zepp's website, not to Helio.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Account region", selection: $region) {
                ForEach(ZeppRegion.allCases, id: \.self) { Text($0.title).tag($0) }
            }.disabled(store.isBusy)
            Text("Use the region chosen when your account was created, not necessarily your current location.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Enter cookies manually", isExpanded: $manualEntry) {
                VStack(alignment: .leading, spacing: 12) {
                    Link("Open Zepp sign-in in your browser", destination: ZeppSignIn.url)
                    Text("After signing in, open Chrome's View → Developer → Developer Tools. Under Application → Cookies, select user.huami.com. Copy the userid and apptoken values below.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Do not select Clear data, Delete account, or Revoke authorization. Never share your token in chat, email, or a support issue.")
                        .font(.caption).foregroundStyle(.orange)
                    TextField("Zepp user ID", text: $userID, prompt: Text("Numeric userid cookie"))
                    SecureField("Session token", text: $token, prompt: Text("apptoken cookie value"))
                }.padding(.top, 12)
            }.disabled(store.isBusy)
            Toggle("Save this session in macOS Keychain and cache downloaded health data locally.", isOn: $consent)
                .font(.callout).disabled(store.isBusy)
            if let error = store.error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if store.isBusy { HStack { ProgressView().controlSize(.small); Text("Checking the session and downloading data…").font(.callout) } }
            HStack {
                Text("Expired sessions require signing in again.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(store.isBusy ? "Cancel download" : "Cancel") {
                    if store.isBusy { store.cancel() } else { token = ""; dismiss() }
                }.keyboardShortcut(.cancelAction)
                Button(manualEntry ? "Connect & download" : "Sign in to Zepp") {
                    store.error = nil
                    if manualEntry { store.connect(userID: userID, token: token, region: region) }
                    else { showWebSignIn = true }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(store.isBusy || !consent || (manualEntry && (token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || userID.isEmpty)))
            }
        }.padding(28).frame(width: 650).tint(Palette.accent).preferredColorScheme(.dark)
            .interactiveDismissDisabled(store.isBusy)
            .onAppear { userID = store.credentials?.userID ?? ""; region = store.credentials?.region ?? .us }
            .onDisappear { token = "" }
            .sheet(isPresented: $showWebSignIn) {
                ZeppWebSignInSheet(region: region) { credentials in
                    showWebSignIn = false
                    store.connect(userID: credentials.userID, token: credentials.token, region: credentials.region)
                }
            }
    }
}

struct ConnectionSettings: View {
    @Bindable var store: AppStore
    @State private var confirmDisconnect = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "Zepp account", symbol: "person.crop.circle.fill", tint: Palette.accent,
                 subtitle: "Your session stays in macOS Keychain. Requests go only to your Zepp region's host.") {
                if let credentials = store.credentials {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                        row("User ID", credentials.userID)
                        row("Region", credentials.region.title)
                        row("Host", credentials.region.baseURL.host ?? "")
                        if let snapshot = store.snapshot, !store.isDemo {
                            row("Downloaded", "\(Format.shortDay(snapshot.startDate)) – \(Format.shortDay(snapshot.endDate)) · \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                            row("Device", "\(store.deviceName) · \(store.selectedSource)")
                        }
                    }
                    HStack {
                        Button("Update session…") { store.error = nil; store.showConnection = true }.disabled(store.isBusy)
                        Button("Disconnect & delete local data", role: .destructive) { confirmDisconnect = true }.disabled(store.isBusy)
                    }
                    .padding(.top, 4)
                } else {
                    Text("No account connected.").foregroundStyle(.secondary)
                    Button("Connect Zepp account…") { store.error = nil; store.showConnection = true }
                        .buttonStyle(.borderedProminent).disabled(store.isBusy)
                }
            }
            Banner(title: "What stays on this Mac", message: "Downloaded records are cached in ~/Library/Application Support/Helio/snapshot.json with owner-only permissions and excluded from backups. The cache isn't separately encrypted, so use FileVault. Disconnecting removes the saved session and cache, but not files you exported.", symbol: "internaldrive.fill")
            Banner(title: "Cloud coverage", message: "Heart rate, sleep, steps, stress, workouts, and training load come from community-documented endpoints. HRV, BioCharge/readiness, SpO₂, and respiratory rate don't have a verified route yet. Other Zepp devices can appear in account-level responses.", symbol: "icloud.fill")
            Link("Official Zepp data export and privacy support", destination: URL(string: "https://www.zepp.com/privacy-support")!).font(.callout)
        }
        .confirmationDialog("Delete the saved Zepp session and downloaded data?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect & delete", role: .destructive) { Task { await store.disconnect() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Exported files remain where you saved them.") }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).monospacedDigit()
        }
        .font(.callout)
    }
}
