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
    var screen: Screen? = .today
    var selectedWorkoutID: String?
    private var operation: Task<Void, Never>?
    private let cache = SnapshotCache()
    private var restored = false
    // Derived values are cached per download and device. Views read them many times per update,
    // and several require decoding nested JSON. Not observed: they change only when their inputs do.
    @ObservationIgnored fileprivate var memo: [String: Any] = [:]
    @ObservationIgnored fileprivate var memoKey = ""

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

enum Screen: String, CaseIterable, Identifiable {
    case today, heart, sleep, stress, activity, workouts, data, account
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        case .heart: "Heart"
        case .sleep: "Sleep"
        case .stress: "Stress"
        case .activity: "Activity"
        case .workouts: "Workouts"
        case .data: "Raw data"
        case .account: "Account"
        }
    }
    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .heart: "heart.fill"
        case .sleep: "moon.stars.fill"
        case .stress: "brain.head.profile"
        case .activity: "figure.walk"
        case .workouts: "dumbbell.fill"
        case .data: "curlybraces"
        case .account: "person.crop.circle"
        }
    }
    var tint: Color {
        switch self {
        case .today: Palette.accent
        case .heart: Palette.heart
        case .sleep: Palette.sleep
        case .stress: Palette.stress
        case .activity: Palette.activity
        case .workouts: Palette.workout
        case .data, .account: Palette.muted
        }
    }
    /// Screens that show one device day and use the date strip.
    var isDaily: Bool { [.today, .heart, .sleep, .stress, .activity].contains(self) }
}

// MARK: - Derived data for the selected device and day

extension AppStore {
    /// Returns a cached value, computing it once per snapshot and selected device.
    func cached<T>(_ key: String, _ make: () -> T) -> T {
        let current = "\(snapshot?.fetchedAt.timeIntervalSince1970 ?? 0)|\(snapshot?.days.count ?? 0)|\(isDemo)|\(selectedSource)"
        if current != memoKey { memo.removeAll(keepingCapacity: true); memoKey = current }
        // Unwrap the dictionary lookup first: casting a missing entry to an Optional T would succeed as nil.
        if let stored = memo[key], let value = stored as? T { return value }
        let value = make()
        memo[key] = value
        return value
    }

    var zone: TimeZone { day?.deviceTimeZone ?? deviceDays.last?.deviceTimeZone ?? .current }
    var deviceDays: [BandDay] {
        cached("deviceDays") { (snapshot?.days ?? []).filter { $0.source == selectedSource }.sorted { $0.date < $1.date } }
    }
    var deviceName: String { deviceDays.last?.deviceName ?? "Helio Strap" }
    var dayStart: Date? {
        guard let day else { return nil }
        return cached("midnight:" + day.id) { day.midnight }
    }
    var dayRange: ClosedRange<Date>? {
        guard let start = dayStart else { return nil }
        return start...start.addingTimeInterval(86400)
    }

    func heartPoints(_ day: BandDay) -> [MetricPoint] { cached("hr:" + day.id) { day.heartRatePoints } }
    func stages(_ day: BandDay) -> [SleepStage] { cached("stages:" + day.id) { day.sleepStages } }
    var heartPoints: [MetricPoint] { day.map(heartPoints) ?? [] }
    var stages: [SleepStage] { day.map(stages) ?? [] }

    var workouts: [Workout] { cached("workouts") { snapshot?.workouts ?? [] } }
    var heartZoneBounds: [Double]? { cached("zoneBounds") { snapshot?.heartZoneBounds } }
    func workouts(on date: String) -> [Workout] {
        cached("workouts:" + date) {
            let formatter = dateFormatter(zone)
            return workouts.filter { formatter.string(from: $0.start) == date }.sorted { $0.start < $1.start }
        }
    }
    var dayWorkouts: [Workout] { workouts(on: selectedDate) }
    var selectedWorkout: Workout? {
        workouts.first { $0.id == selectedWorkoutID } ?? workouts.first
    }

    var stressDays: [StressDay] { cached("stressDays") { snapshot?.stressDays(timeZone: zone) ?? [] } }
    var stressDay: StressDay? { stressDays.first { $0.date == selectedDate } }
    var stressPoints: [MetricPoint] {
        cached("stress:" + selectedDate) { snapshot?.stressPoints(on: selectedDate, timeZone: zone) ?? [] }
    }

    /// The most recent training-load record on or before the selected day.
    var trainingLoad: TrainingLoadDay? {
        let records = cached("trainingLoad") { snapshot?.trainingLoad ?? [] }
        return records.last { $0.date <= selectedDate } ?? records.last
    }

    var sleepHeartRate: [MetricPoint] {
        guard let day else { return [] }
        return cached("sleepHR:" + day.id) {
            let stages = stages(day)
            guard let start = stages.first?.start ?? day.sleepStart, let end = stages.last?.end ?? day.sleepEnd, end > start else { return [] }
            return snapshot?.heartRatePoints(from: start, to: end, source: day.source) ?? []
        }
    }

    /// Lowest and highest minute reading for each day, for the range trend.
    var dailyHeartRanges: [DailyValue] {
        cached("hrRanges") {
            deviceDays.compactMap { day in
                let values = heartPoints(day).map(\.value)
                guard let low = values.min(), let high = values.max() else { return nil }
                return DailyValue(date: day.date, value: high, low: low)
            }
        }
    }

    var canGoBack: Bool { deviceDays.first.map { $0.date < selectedDate } ?? false }
    var canGoForward: Bool { deviceDays.last.map { $0.date > selectedDate } ?? false }
    func step(_ offset: Int) {
        let dates = deviceDays.map(\.date)
        guard let index = dates.firstIndex(of: selectedDate) else { return }
        let next = index + offset
        if dates.indices.contains(next) { selectedDate = dates[next] }
    }
    func showWorkout(_ workout: Workout) {
        selectedWorkoutID = workout.id
        screen = .workouts
    }
}

private func dateFormatter(_ zone: TimeZone) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = zone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}
