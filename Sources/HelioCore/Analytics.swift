import Foundation

public struct MetricPoint: Identifiable, Sendable {
    public let date: Date
    public let value: Double
    public let segment: Int
    public var id: Date { date }
    public init(date: Date, value: Double, segment: Int = 0) {
        self.date = date
        self.value = value
        self.segment = segment
    }
}

public extension BandDay {
    var midnight: Date? { dayFormatter(deviceTimeZone).date(from: date) }

    var deviceTimeZone: TimeZone {
        if let seconds = summary["tz"].number, abs(seconds) <= 86400,
           let zone = TimeZone(secondsFromGMT: Int(seconds)) {
            return zone
        }
        return .current
    }

    var heartRatePoints: [MetricPoint] {
        guard let start = midnight else { return [] }
        var segment = 0
        var lastMinute: Int?
        return heartRate.prefix(1440).enumerated().compactMap { minute, value in
            guard (1...253).contains(value) else { return nil }
            if let lastMinute, minute - lastMinute > 1 { segment += 1 }
            lastMinute = minute
            return MetricPoint(date: start.addingTimeInterval(Double(minute) * 60), value: Double(value), segment: segment)
        }
    }

    var steps: Double? { summary["stp"]["ttl"].number }
    var calories: Double? { summary["stp"]["cal"].number }
    var distance: Double? { summary["stp"]["dis"].number }
    var stepGoal: Double? { positive(summary["goal"].number) }
    var restingHeartRate: Double? { positive(summary["slp"]["rhr"].number) }
    /// The day's peak reading as reported by the device, which can exceed the minute averages.
    var maxHeartRate: (bpm: Double, date: Date?)? {
        guard let bpm = positive(summary["hr"]["maxHr"]["hr"].number), bpm < 254 else { return nil }
        return (bpm, epochDate(summary["hr"]["maxHr"]["ts"].number))
    }
    var sleepScore: Double? { positive(summary["slp"]["ss"].number) }
    var sleepStart: Date? { epochDate(summary["slp"]["st"].number) }
    var sleepEnd: Date? { epochDate(summary["slp"]["ed"].number) }
    var sleepWindowMinutes: Double? {
        guard let start = sleepStart, let end = sleepEnd, end > start else { return nil }
        return end.timeIntervalSince(start) / 60
    }
    var wakeCount: Double? {
        guard !sleepStages.isEmpty else { return nil }
        return summary["slp"]["wc"].number
    }
    // Only known asleep stages count. The interval between start and end also contains awake time.
    var asleepMinutes: Double? {
        let stages = sleepStages.filter { [4, 5, 7, 8].contains($0.mode) }
        guard !stages.isEmpty else { return nil }
        let asleep = stages.filter { [4, 5, 8].contains($0.mode) }.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var interval: (start: Date, end: Date)?
        for stage in asleep {
            if let previous = interval {
                if stage.start <= previous.end { interval = (previous.start, max(previous.end, stage.end)) }
                else { total += previous.end.timeIntervalSince(previous.start); interval = (stage.start, stage.end) }
            } else { interval = (stage.start, stage.end) }
        }
        if let interval { total += interval.end.timeIntervalSince(interval.start) }
        return total / 60
    }
    func minutes(in stage: SleepStage.Kind) -> Double {
        sleepStages.filter { $0.kind == stage }.reduce(0) { $0 + $1.minutes }
    }
    /// Stage minutes are offsets from a midnight, and stop minutes are inclusive.
    /// Real Helio records count from the midnight before the record date, so the anchor
    /// is whichever candidate midnight places the first stage nearest the reported sleep start.
    var sleepStages: [SleepStage] {
        guard let midnight else { return [] }
        let raw: [(index: Int, lower: Double, upper: Double, mode: Int)] = summary["slp"]["stage"].array.enumerated().compactMap { index, item in
            guard let lower = item["start"].number, let upper = item["stop"].number,
                  let mode = item["mode"].number, (0...255).contains(mode), mode.rounded() == mode,
                  lower >= 0, upper >= lower, upper < 4320 else { return nil }
            return (index, lower, upper, Int(mode))
        }
        guard let first = raw.map(\.lower).min() else { return [] }
        let previous = midnight.addingTimeInterval(-86400)
        let anchor: Date
        if let start = sleepStart {
            anchor = [previous, midnight].min {
                abs($0.addingTimeInterval(first * 60).timeIntervalSince(start)) < abs($1.addingTimeInterval(first * 60).timeIntervalSince(start))
            }!
        } else { anchor = previous }
        return raw.map { SleepStage(id: $0.index, start: anchor.addingTimeInterval($0.lower * 60),
                                    end: anchor.addingTimeInterval(($0.upper + 1) * 60), mode: $0.mode) }
    }

    /// Per-minute activity from the binary `data` field: kind, intensity, and step count bytes.
    /// The step bytes sum to the daily step total in real records. Kind and intensity remain undocumented.
    var activityMinutes: [ActivityMinute] {
        guard let encoded = raw["data"].string, let bytes = Data(base64Encoded: encoded),
              bytes.count % 3 == 0, bytes.count <= 4320 else { return [] }
        let values = [UInt8](bytes)
        return stride(from: 0, to: values.count, by: 3).map {
            ActivityMinute(minute: $0 / 3, kind: Int(values[$0]), intensity: Int(values[$0 + 1]), steps: Int(values[$0 + 2]))
        }
    }
    /// Steps per hour of the device day, or nil when no minute data was returned.
    var hourlySteps: [Int]? {
        let minutes = activityMinutes
        guard !minutes.isEmpty else { return nil }
        var hours = Array(repeating: 0, count: 24)
        for minute in minutes where minute.minute < 1440 { hours[minute.minute / 60] += minute.steps }
        return hours
    }
    var activitySegments: [ActivitySegment] {
        guard let midnight else { return [] }
        return summary["stp"]["stage"].array.enumerated().compactMap { index, item in
            guard let lower = item["start"].number, let upper = item["stop"].number,
                  let mode = item["mode"].number, lower >= 0, upper >= lower, upper < 1440 else { return nil }
            return ActivitySegment(id: index, start: midnight.addingTimeInterval(lower * 60),
                                   end: midnight.addingTimeInterval((upper + 1) * 60), mode: Int(mode),
                                   steps: item["step"].number, distance: item["dis"].number, calories: item["cal"].number)
        }.sorted { $0.start < $1.start }
    }
    var activeMinutes: Double? {
        let segments = activitySegments
        guard !segments.isEmpty else { return nil }
        return segments.reduce(0) { $0 + $1.minutes }
    }
    /// Minutes with a valid heart-rate reading, a proxy for how long the strap was worn.
    var wornMinutes: Int { heartRate.prefix(1440).filter { (1...253).contains($0) }.count }
    var deviceName: String { DeviceCatalog.name(source: raw["source"].scalarDescription, serial: source) }
}

public struct SleepStage: Identifiable, Sendable {
    public enum Kind: Int, CaseIterable, Sendable {
        case awake = 7, rem = 8, light = 4, deep = 5
        public var title: String {
            switch self { case .awake: "Awake"; case .rem: "REM"; case .light: "Light"; case .deep: "Deep" }
        }
    }
    public let id: Int
    public let start: Date
    public let end: Date
    public let mode: Int
    public var kind: Kind? { Kind(rawValue: mode) }
    public var minutes: Double { end.timeIntervalSince(start) / 60 }
    public var title: String { kind?.title ?? "Unknown" }
}

public struct ActivityMinute: Sendable {
    public let minute: Int
    public let kind: Int
    public let intensity: Int
    public let steps: Int
}

public struct ActivitySegment: Identifiable, Sendable {
    public let id: Int
    public let start: Date
    public let end: Date
    public let mode: Int
    public let steps: Double?
    public let distance: Double?
    public let calories: Double?
    public var minutes: Double { end.timeIntervalSince(start) / 60 }
    /// Community decodes of Mi Fit summaries: 1 slow walk, 3 brisk walk, 4 run. Other modes are unverified.
    public var title: String {
        switch mode { case 1: "Walk"; case 3: "Brisk walk"; case 4: "Run"; default: "Active" }
    }
}

public enum DeviceCatalog {
    public static func name(source: String?, serial: String) -> String {
        switch source {
        case "10289411": "Helio Strap"
        default: serial.count > 4 ? "Device ··" + serial.suffix(4) : serial
        }
    }
}

public extension CloudSnapshot {
    var dates: [String] { Array(Set(days.map(\.date))).sorted() }
    var sources: [String] { Array(Set(days.map(\.source))).sorted() }
    func day(on date: String, source: String?) -> BandDay? {
        days.first { $0.date == date && (source == nil || $0.source == source) }
    }
    func payload(_ endpoint: CloudEndpoint) -> EndpointPayload? { payloads.first { $0.endpoint == endpoint } }

    /// Heart-rate readings for an interval that can span two daily records, such as a night's sleep.
    func heartRatePoints(from start: Date, to end: Date, source: String) -> [MetricPoint] {
        let points = days.filter { $0.source == source }.sorted { $0.date < $1.date }
            .flatMap(\.heartRatePoints).filter { $0.date >= start && $0.date < end }
        var segment = 0
        var previous: Date?
        return points.map { point in
            if let previous, point.date.timeIntervalSince(previous) > 60 { segment += 1 }
            previous = point.date
            return MetricPoint(date: point.date, value: point.value, segment: segment)
        }
    }

    func stressPoints(on date: String, timeZone: TimeZone = .current) -> [MetricPoint] {
        let items = payload(.stress)?.raw["items"].array ?? []
        let formatter = dayFormatter(timeZone)
        var values: [Date: Double] = [:]
        for item in items {
            for reading in stressReadings(item) {
                guard let ms = reading["time"].number, ms > 0,
                      let value = reading["value"].number, (1...100).contains(value) else { continue }
                let timestamp = Date(timeIntervalSince1970: ms / 1000)
                if formatter.string(from: timestamp) == date { values[timestamp] = value }
            }
        }
        var segment = 0
        var previous: Date?
        return values.keys.sorted().map { timestamp in
            if let previous, timestamp.timeIntervalSince(previous) > 600 { segment += 1 }
            previous = timestamp
            return MetricPoint(date: timestamp, value: values[timestamp]!, segment: segment)
        }
    }

    /// Daily stress summaries, keyed by the device date of each record's timestamp.
    func stressDays(timeZone: TimeZone = .current) -> [StressDay] {
        let formatter = dayFormatter(timeZone)
        var result: [String: StressDay] = [:]
        for item in payload(.stress)?.raw["items"].array ?? [] {
            guard let ms = item["timestamp"].number, ms > 0 else { continue }
            let date = formatter.string(from: Date(timeIntervalSince1970: ms / 1000))
            let proportions = [item["relaxProportion"], item["normalProportion"], item["mediumProportion"], item["highProportion"]].map(\.number)
            result[date] = StressDay(date: date, average: bounded(item["avgStress"].number), minimum: bounded(item["minStress"].number),
                                     maximum: bounded(item["maxStress"].number),
                                     proportions: proportions.contains(nil) ? nil : proportions.map { $0! })
        }
        return result.values.sorted { $0.date < $1.date }
    }

    var trainingLoad: [TrainingLoadDay] {
        (payload(.sportLoad)?.raw["items"].array ?? []).compactMap { item in
            guard let day = item["dayId"].string, let total = item["wtlSum"].number, total >= 0 else { return nil }
            return TrainingLoadDay(date: day, weeklyLoad: total, dayLoad: positive(item["currnetDayTrainLoad"].number ?? item["currentDayTrainLoad"].number),
                                   optimalMin: positive(item["wtlSumOptimalMin"].number),
                                   optimalMax: positive(item["wtlSumOptimalMax"].number),
                                   overreaching: positive(item["wtlSumOverreaching"].number))
        }.sorted { $0.date < $1.date }
    }

    private func stressReadings(_ item: JSONValue) -> [JSONValue] {
        let data = item["data"]
        if let text = data.string, let bytes = text.data(using: .utf8), let decoded = try? JSONValue.decode(bytes) {
            return decoded.array
        }
        return data.array
    }
}

public struct StressDay: Identifiable, Sendable {
    public var id: String { date }
    public let date: String
    public let average: Double?
    public let minimum: Double?
    public let maximum: Double?
    /// Percent of measured time that was relaxed, normal, medium, and high.
    public let proportions: [Double]?
}

public enum StressLevel: Int, CaseIterable, Sendable {
    case relaxed, normal, medium, high
    public var title: String {
        switch self { case .relaxed: "Relaxed"; case .normal: "Normal"; case .medium: "Medium"; case .high: "High" }
    }
    /// Zepp's published bands: 1–39, 40–59, 60–79, 80–100.
    public var range: ClosedRange<Double> {
        switch self { case .relaxed: 1...39; case .normal: 40...59; case .medium: 60...79; case .high: 80...100 }
    }
    public init(value: Double) {
        self = value < 40 ? .relaxed : value < 60 ? .normal : value < 80 ? .medium : .high
    }
}

public struct TrainingLoadDay: Identifiable, Sendable {
    public var id: String { date }
    public let date: String
    public let weeklyLoad: Double
    public let dayLoad: Double?
    public let optimalMin: Double?
    public let optimalMax: Double?
    public let overreaching: Double?
    public var status: String {
        if let overreaching, weeklyLoad >= overreaching { return "Overreaching" }
        if let optimalMax, weeklyLoad > optimalMax { return "High" }
        if let optimalMin, weeklyLoad >= optimalMin { return "Optimal" }
        return optimalMin == nil ? "Recorded" : "Low"
    }
}

func positive(_ value: Double?) -> Double? {
    guard let value, value > 0 else { return nil }
    return value
}
func epochDate(_ value: Double?) -> Date? {
    guard let value, value > 0, value < 32_503_680_000 else { return nil }
    return Date(timeIntervalSince1970: value)
}
private func bounded(_ value: Double?) -> Double? {
    guard let value, (1...100).contains(value) else { return nil }
    return value
}
/// Day formatters are costly to create and are needed for every record, so one is kept per time zone.
/// DateFormatter is thread-safe for parsing and formatting once configured.
func dayFormatter(_ timeZone: TimeZone) -> DateFormatter {
    DayFormatterCache.shared.formatter(for: timeZone)
}

private final class DayFormatterCache: @unchecked Sendable {
    static let shared = DayFormatterCache()
    private let lock = NSLock()
    private var formatters: [TimeZone: DateFormatter] = [:]

    func formatter(for timeZone: TimeZone) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let formatter = formatters[timeZone] { return formatter }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatters[timeZone] = formatter
        return formatter
    }
}
