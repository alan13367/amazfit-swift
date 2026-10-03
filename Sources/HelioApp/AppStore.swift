import SwiftUI
import HelioCore
import AppKit
import UniformTypeIdentifiers

@MainActor @Observable
final class AppStore {
    var snapshot: CloudSnapshot?
    private(set) var credentials: ZeppCredentials?
    var isDemo = false
    var isBusy = false
    var status = "Connect your Zepp account to get started."
    var error: String?
    var selectedDate = ""
    var selectedSource = ""
    var syncDays = 7
    var showConnection = false
    private var operation: Task<Void, Never>?
    private let cache = SnapshotCache()
    private var restored = false

    var day: BandDay? { snapshot?.day(on: selectedDate, source: selectedSource.isEmpty ? nil : selectedSource) }
    var isConnected: Bool { credentials != nil }

    func restore() async {
        guard !restored else { return }
        restored = true
        isBusy = true
        defer { isBusy = false }
        do {
            credentials = try KeychainStore.load()
            if let credentials {
                snapshot = try await cache.load(for: credentials)
                selectLatest()
                status = snapshot == nil ? "Session saved. Sync to download data." : "Showing your last download. Sync for fresh data."
            }
        } catch { self.error = error.localizedDescription }
    }

    func connect(userID: String, token: String, region: ZeppRegion) {
        guard !isBusy else { return }
        do {
            let candidate = try ZeppCredentials(userID: userID, token: token, region: region)
            beginFetch(candidate, savingSession: true)
        } catch { self.error = error.localizedDescription }
    }

    func sync() {
        guard let credentials, !isBusy else { return }
        beginFetch(credentials, savingSession: false)
    }

    private func beginFetch(_ candidate: ZeppCredentials, savingSession: Bool) {
        isBusy = true
        error = nil
        status = "Downloading the last \(syncDays) days from Zepp…"
        let days = syncDays
        operation = Task {
            defer { isBusy = false; operation = nil }
            do {
                let today = Calendar.current.startOfDay(for: Date())
                let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: today)!
                let result = try await ZeppClient().fetch(credentials: candidate, from: start, to: today)
                try Task.checkCancellation()
                if savingSession { try KeychainStore.save(candidate) }
                credentials = candidate
                // Never cache session tokens in the health-data file.
                do { try await cache.save(result, for: candidate) }
                catch { self.error = "Data downloaded, but the local cache could not be saved. \(error.localizedDescription)" }
                try Task.checkCancellation()
                snapshot = result
                isDemo = false
                selectLatest()
                showConnection = false
                status = result.days.isEmpty
                    ? "Zepp returned no band data for this range. Sync your strap in the iPhone app, then retry."
                    : "Downloaded \(result.days.count) daily band records."
            } catch is CancellationError {
                status = "Download cancelled. Your previous data is unchanged."
            } catch {
                if Task.isCancelled { status = "Download cancelled." }
                else {
                    self.error = error.localizedDescription
                    status = "Download failed. Your previous data is unchanged."
                }
            }
        }
    }

    func cancel() { operation?.cancel() }

    func showDemo() {
        guard !isBusy else { return }
        snapshot = .demo()
        isDemo = true
        error = nil
        status = "Sample data only. These are not readings from your strap."
        selectLatest()
    }

    func leaveDemo() async {
        guard !isBusy else { return }
        snapshot = nil
        isDemo = false
        if let credentials {
            do { snapshot = try await cache.load(for: credentials) }
            catch { self.error = error.localizedDescription }
        }
        selectLatest()
        status = isConnected ? "Showing your last download." : "Connect your Zepp account to get started."
    }

    func disconnect() async {
        guard !isBusy else { return }
        do {
            try KeychainStore.clear()
            credentials = nil
            snapshot = nil
            isDemo = false
            selectedDate = ""
            selectedSource = ""
            try await cache.clear()
            error = nil
            status = "Disconnected. The saved session and local health-data cache were deleted."
        } catch { self.error = error.localizedDescription }
    }

    func selectLatest() {
        guard let snapshot else { selectedDate = ""; selectedSource = ""; return }
        if !snapshot.sources.contains(selectedSource) { selectedSource = snapshot.sources.first ?? "" }
        selectedDate = snapshot.days.filter { $0.source == selectedSource }.map(\.date).max() ?? snapshot.dates.last ?? ""
    }

    func export() {
        guard let snapshot else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = isDemo ? "helio-demo.json" : "helio-\(snapshot.endDate).json"
        panel.message = "This file contains private health data and device identifiers. It does not contain your session token."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { self.error = error.localizedDescription }
    }
}
